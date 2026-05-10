/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright(c) 2026 Liu, Changcheng <changcheng.liu@aliyun.com>
 */

#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

#include <execinfo.h>
#include <dlfcn.h>
#include <link.h>
#include <dirent.h>
#include <bfd.h>
#include <unistd.h>
#include <sys/syscall.h>

#include "backtrace.h"

#define DEBUG_BACKTRACE_LINE_FMT "%2d 0x%016lx %s()  %s:%u\n"
#define DEBUG_BACKTRACE_LINE_ARG(_n, _line) \
        _n, (_line)->address, \
        (_line)->function ? (_line)->function : "??", \
        (_line)->file ? (_line)->file : "??", \
        (_line)->lineno

struct dl_address_search {
    unsigned long address;
    const char    *filename;
    unsigned long base;
};

struct backtrace_line {
    unsigned long address;
    char          *file;
    char          *function;
    unsigned      lineno;
};

struct backtrace_file {
    struct dl_address_search dl;
    bfd                      *abfd;
    asymbol                  **syms;
};

#define BACKTRACE_MAX 64
struct backtrace {
    struct backtrace_line lines[BACKTRACE_MAX];
    int                   size;
    int                   position;
};

struct backtrace_search {
    int count;
    struct backtrace_file *file;

    /* search the line where the function call took place,
     * instead of return address
     */
    int                   backoff;

    struct backtrace_line *lines;
    int                   max_lines;
};

static
int debug_backtrace_is_excluded(void *address, const char *symbol)
{
    return !strcmp(symbol, "todo");
}

static
const char *get_exe()
{
    static char exe[1024];
    int ret = 0;

    ret = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (ret < 0) {
        exe[0] = '\0';
    } else {
        exe[ret] = '\0';
    }

    return exe;
}

static
int dl_match_address(struct dl_phdr_info *info, size_t size, void *data)
{
    struct dl_address_search *dl = data;
    const ElfW(Phdr) *phdr;
    ElfW(Addr) load_base = info->dlpi_addr;
    long n;

    phdr = info->dlpi_phdr;
    for (n = info->dlpi_phnum; --n >= 0; phdr++) {
        ElfW(Addr) vbaseaddr = phdr->p_vaddr + load_base;
        if (dl->address >= vbaseaddr &&
            dl->address < vbaseaddr + phdr->p_memsz) {
            dl->filename = info->dlpi_name;
            dl->base     = info->dlpi_addr;
        }
    }

    return 0;
}

static
int dl_lookup_address(struct dl_address_search *dl)
{
    dl->filename = NULL;
    dl->base     = 0;

    dl_iterate_phdr(dl_match_address, dl);
    if (dl->filename == NULL) {
        return -1;
    }

    if (strlen(dl->filename) == 0) {
        dl->filename = get_exe();
    }
    return 0;
}

static
void find_address_in_section(bfd *abfd, asection *section, void *data)
{
    struct backtrace_search *search = data;
    bfd_size_type size;
    bfd_vma vma;
    unsigned long address;
    const char *filename, *function;
    unsigned lineno;
    int found;

    if ((search->count > 0) || (search->max_lines == 0) ||
        ((bfd_get_section_flags(abfd, section) & SEC_ALLOC) == 0)) {
        return;
    }

    address = search->file->dl.address - search->file->dl.base;
    vma = bfd_section_vma(abfd, section);
    if (address < vma) {
        return;
    }

    size = bfd_section_size(abfd, section);
    if (address >= vma + size) {
        return;
    }

    /* Search in address-1 to get the calling line instead of return address */
    found = bfd_find_nearest_line(abfd, section, search->file->syms,
                                  address - vma - search->backoff,
                                  &filename, &function, &lineno);
    do {
        search->lines[search->count].address  = address;
        search->lines[search->count].file     = strdup(filename ? filename :
                                                       "???");
        search->lines[search->count].function = strdup(function ? function :
                                                       "???");
        search->lines[search->count].lineno   = lineno;
        if (search->count == 0) {
            /* To get the inliner info, search at the original address */
            bfd_find_nearest_line(abfd, section, search->file->syms,
                                  address - vma, &filename, &function, &lineno);
        }

        ++search->count;
        found = bfd_find_inliner_info(abfd, &filename, &function, &lineno);
    } while (found && (search->count < search->max_lines));
}

static
int get_line_info(struct backtrace_file *file, int backoff,
                  struct backtrace_line *lines, int max)
{
    struct backtrace_search search;

    search.file = file;
    search.backoff = backoff;
    search.count = 0;
    search.lines = lines;
    search.max_lines = max;
    bfd_map_over_sections(file->abfd, find_address_in_section, &search);
    return search.count;
}

static
int load_file(struct backtrace_file *file)
{
    long symcount;
    unsigned int size;
    char **matching;

    file->syms = NULL;
    file->abfd = bfd_openr(file->dl.filename, NULL);
    if (!file->abfd) {
        goto err;
    }

    if (bfd_check_format(file->abfd, bfd_archive)) {
        goto err_close;
    }

    if (!bfd_check_format_matches(file->abfd, bfd_object, &matching)) {
        goto err_close;
    }

    if ((bfd_get_file_flags(file->abfd) & HAS_SYMS) == 0) {
        goto err_close;
    }

    symcount = bfd_read_minisymbols(file->abfd, 0,
                                    (void*)&file->syms, &size);
    if (symcount == 0) {
        free(file->syms);
        symcount = bfd_read_minisymbols(file->abfd, 1,
                                        (void*)&file->syms, &size);
    }
    if (symcount < 0) {
        goto err_close;
    }

    return 0;

err_close:
    bfd_close(file->abfd);
err:
    return -1;
}

static
void unload_file(struct backtrace_file *file)
{
    free(file->syms);
    bfd_close(file->abfd);
}

static
int debug_backtrace_create(struct backtrace **bckt, int strip)
{
    struct backtrace_file file;
    void *addresses[BACKTRACE_MAX];
    int bckt_idx, bckt_total;
    int ret;

    *bckt = NULL;
    *bckt = malloc(sizeof(**bckt));
    if (*bckt == NULL) {
        return -ENOMEM;
    }

    bckt_total = backtrace(addresses, BACKTRACE_MAX);

    (*bckt)->size = 0;
    (*bckt)->position = strip;
    for (bckt_idx = 0; bckt_idx < bckt_total; ++bckt_idx) {
        file.dl.address = (unsigned long)addresses[bckt_idx];
        if (dl_lookup_address(&file.dl) == 0 && load_file(&file) == 0) {
            (*bckt)->size += get_line_info(&file, 1,
                                           (*bckt)->lines + (*bckt)->size,
                                           BACKTRACE_MAX - (*bckt)->size);
            unload_file(&file);
        }
    }

    return 0;
}

static
int debug_backtrace_next(struct backtrace *bckt, struct backtrace_line **line)
{
    struct backtrace_line *ln;

    do {
        if (bckt->position >= bckt->size) {
            return 0;
        }

        ln = &bckt->lines[bckt->position++];
    } while (debug_backtrace_is_excluded((void*)ln->address, ln->function));

    *line = ln;
    return 1;
}

static
void debug_backtrace_destroy(struct backtrace *bckt)
{
    int bckt_line_idx = 0;

    for (bckt_line_idx = 0; bckt_line_idx < bckt->size; ++bckt_line_idx) {
        free(bckt->lines[bckt_line_idx].function);
        free(bckt->lines[bckt_line_idx].file);
    }

    bckt->size = 0;
    free(bckt);
}

void debug_print_backtrace(FILE *stream, int strip)
{
	struct backtrace *bckt           = NULL;
    struct backtrace_line *bckt_line = NULL;
	int bckt_idx;
	int rst;

    rst = debug_backtrace_create(&bckt, strip);
    if (rst != 0) {
        return;
    }

    fprintf(stream, "==== backtrace (tid:%7d) ====\n", syscall(SYS_gettid));
    for (bckt_idx = 0; debug_backtrace_next(bckt, &bckt_line); ++bckt_idx) {
        fprintf(stream, DEBUG_BACKTRACE_LINE_FMT,
                DEBUG_BACKTRACE_LINE_ARG(bckt_idx, bckt_line));
    }
    fprintf(stream, "=================================\n", syscall(SYS_gettid));

    debug_backtrace_destroy(bckt);
}

int main(void)
{
    debug_print_backtrace(stdout, 2);
    return 0;
}

// vim: ts=4 sw=4 expandtab fileencoding=utf-8 ft=c
