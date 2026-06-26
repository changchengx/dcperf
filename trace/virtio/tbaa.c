/* SPDX-License-Identifier: Apache-2.0
 * Copyright(c) 2026 Liu, Changcheng <changcheng.liu@aliyun.com>
 */

/*
 * TBACC(type based alias analysis) and strict-aliasing example
 *
 * The PCI config space is type-punned: it is written as raw uint32_t dwords
 * through a *different* struct type (pcie_raw_cfg, reached via a cast), but read
 * back through the typed fields (sriov_cap.num_vfs, a uint16_t) that occupy the
 * same storage.  Under -fstrict-aliasing (on by default at -O2/-O3) the compiler
 * assumes the uint32_t store and the uint16_t read do not alias, so it may reuse
 * (CSE) a value read *before* the store for a read *after* it.  Result: the
 * read-back of num_vfs returns the stale pre-write value, exactly like
 * vblk_pci_sriov_post_write() seeing NumVfs "0 -> 0" instead of "0 -> 1".
 *
 * Build & run (reproduces on gcc x86 and aarch64 at -O2/-O3):
 *   gcc -O2 -Wall /tmp/tbaa.c -o /tmp/tbaa && /tmp/tbaa 1
 *
 * Candidate fixes (verified on gcc 8.5/x86, gcc 11.4/x86, gcc 12.2/aarch64):
 *   -DFIX_TYPEDEF        : read/write THROUGH a may_alias typedef pointer  -> OK   (this is the real fix)
 *   -DFIX_MEMBER         : may_alias attribute on the struct member        -> BUG  (does NOT work)
 *   -DFIX_STRUCT         : may_alias attribute on the struct type          -> BUG  (does NOT work)
 *   -fno-strict-aliasing : disables the optimization globally              -> OK
 *
 * KEY LESSON: may_alias governs the type of the lvalue AT THE POINT OF ACCESS.
 * You must read/write THROUGH a pointer to the may_alias type (the typedef/cast
 * form).  Merely declaring the storage with the attribute (member/struct form)
 * does not make the element store an aliasing access, so it does NOT fix the bug.
 *
 * Expected `./tbaa 1`: buggy -> typed read-back 0; fixed -> 1.  In every build
 * the raw read-back shows 1, proving the store landed and only the typed read
 * was miscompiled.
 *
 * NOTE: the real pcie_virtio_dev also has a union overlay (cfg <-> dw_regs).
 * In a small standalone TU that union member keeps the compiler conservative and
 * hides the bug, so this reproducer omits it; the raw access goes only through
 * the separate pcie_raw_cfg type, exactly as the real raw view is reached.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef FIX_MEMBER
#define MAY_ALIAS __attribute__((__may_alias__))
#else
#define MAY_ALIAS
#endif

#define CFG_DWORDS 4

#ifdef FIX_TYPEDEF
typedef uint32_t __attribute__((__may_alias__)) cfg_dw_t;
#else
typedef uint32_t cfg_dw_t;
#endif

/* Simplified SR-IOV capability: num_vfs is the low 16 bits of dword 0. */
struct sriov_cap {
	uint16_t num_vfs;    /* offset 0x0, low 16 bits of dw_regs[0] */
	uint16_t sriov_ctrl; /* offset 0x2, high 16 bits of dw_regs[0] */
	uint32_t rest[CFG_DWORDS - 1];
};

/* Typed view of the config space (the only view the reader uses). */
struct pcie_virtio_dev {
	struct {
		struct sriov_cap sriov_cap;
	} cfg;
} __attribute__((packed));

/* A *separate* struct type used as the "raw" overlay, reached only via a cast. */
#ifdef FIX_STRUCT
struct __attribute__((__may_alias__)) pcie_raw_cfg {
	uint32_t dw_regs[CFG_DWORDS];
} __attribute__((packed));
#else
struct pcie_raw_cfg {
	uint32_t dw_regs[CFG_DWORDS] MAY_ALIAS;
} __attribute__((packed));
#endif

#define TO_PCIE_RAW_CFG(d) ((struct pcie_raw_cfg *)(d))

/* The host config write: a raw uint32_t store through pcie_raw_cfg. */
static inline void pcie_config_write(struct pcie_raw_cfg *raw, unsigned reg, uint32_t val)
{
	((cfg_dw_t *)raw->dw_regs)[reg] = val;
}

/*
 * Read the raw dword back.  Kept noinline and OUT of the hot path on purpose: a
 * uint32_t read of the object would tell the optimizer "this object is accessed
 * as uint32_t" and make it conservative, hiding the very bug we want to show.
 */
static uint32_t __attribute__((noinline)) read_raw_dw(struct pcie_virtio_dev *d, unsigned reg)
{
	return TO_PCIE_RAW_CFG(d)->dw_regs[reg];
}

/* Mirrors vblk_pci_sriov_post_write(): the post-write typed read lives in a
 * separate function that the optimizer inlines back into the handler. */
static uint16_t post_write(struct pcie_virtio_dev *d, unsigned reg, uint16_t prev_num_vfs)
{
	(void)reg;
	(void)prev_num_vfs;
	return d->cfg.sriov_cap.num_vfs; /* typed read AFTER store (the bug) */
}

/*
 * Mirrors vblk_pci_handle_cfg_write0() + vblk_pci_sriov_post_write():
 *   prev = typed read  ->  raw store  ->  post_write() typed read.
 */
static uint16_t emulate_numvfs_write(struct pcie_virtio_dev *d, unsigned reg, uint32_t dw_write,
				     uint16_t *out_prev)
{
	uint16_t prev_num_vfs = d->cfg.sriov_cap.num_vfs;    /* read BEFORE the store */

	pcie_config_write(TO_PCIE_RAW_CFG(d), reg, dw_write); /* raw uint32_t store    */

	*out_prev = prev_num_vfs;
	return post_write(d, reg, prev_num_vfs);
}

int main(int argc, char **argv)
{
	struct pcie_virtio_dev *dev = calloc(1, sizeof(*dev)); /* heap so it escapes */
	uint32_t val = (argc > 1) ? (uint32_t)strtoul(argv[1], NULL, 0) : 1u; /* runtime, no const-fold */
	/* Runtime dword index (default 0), mirroring dw_regs[ext_reg_num]. */
	unsigned reg = (argc > 2) ? (unsigned)strtoul(argv[2], NULL, 0) : 0u;
	uint16_t prev = 0;
	uint32_t raw = 0;

	if (dev == NULL)
		return 1;

	/* Host writes NumVfs=val to SR-IOV dword `reg` (num_vfs is its low 16 bits). */
	uint16_t now = emulate_numvfs_write(dev, reg, val, &prev);
	raw = read_raw_dw(dev, reg); /* prove the store really landed in memory */

	printf("wrote NumVfs=%u\n", val);
	printf("  typed read-back num_vfs : %u -> %u\n", prev, now);
	printf("  raw  read-back dw_regs[0]: 0x%08x (low16=%u)\n", raw, raw & 0xffffu);

	if (now == (uint16_t)val) {
		printf("RESULT: OK   (typed read saw the write)\n");
		free(dev);
		return 0;
	}

	printf("RESULT: BUG  (typed read is STALE: read %u, memory holds %u) "
	       "-- strict-aliasing CSE dropped the write\n",
	       now, raw & 0xffffu);
	free(dev);
	return 2;
}
