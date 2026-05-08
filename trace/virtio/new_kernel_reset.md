# Virtio-Block Device Reset (FLR) Process Analysis

This document analyzes the virtio-block device reset flow triggered by:

```bash
echo 1 > /sys/bus/pci/devices/0000:3d:00.2/reset
```

The trace was captured by `/.autodirect/swgwork/jerrliu/dpu35/flr/6.14.sh` using
the kernel `function` tracer, and the resulting log
(`/.autodirect/swgwork/jerrliu/dpu35/flr/new_kernel.log`) is mapped to the
upstream Linux source.

The reset spans roughly **121 ms** (t=`1176.149106` → `1176.270220`),
dominated by the FLR settle time. Three layers cooperate:

**PCI core → virtio-pci core → virtio-blk driver**

---

## High-Level Flow

```
echo 1 > .../reset
   │
   ▼
reset_store (PCI sysfs)                         drivers/pci/pci-sysfs.c:1381
   │
   ▼
pci_reset_function                              drivers/pci/pci.c:5308
   ├── pci_dev_lock(bridge), pci_dev_lock(dev), pci_cfg_access_lock
   │
   ├── pci_dev_save_and_disable                 drivers/pci/pci.c:5147
   │     ├── err_handler->reset_prepare = virtio_pci_reset_prepare
   │     │     └── virtio_device_reset_prepare      drivers/virtio/virtio.c:634
   │     │           ├── virtio_config_core_disable
   │     │           └── drv->reset_prepare = virtblk_reset_prepare
   │     │                 └── virtblk_freeze_priv  drivers/block/virtio_blk.c:1583
   │     │                       ├── blk_mq_freeze_queue / quiesce_nowait / unfreeze
   │     │                       ├── virtio_reset_device → vp_reset (status=0, poll)
   │     │                       ├── flush_work(config_work)
   │     │                       └── vp_del_vqs (free MSI-X, vrings, IRQs)
   │     ├── pci_save_state
   │     └── PCI_COMMAND ← INTX_DISABLE   (then pci_disable_device)
   │
   ├── __pci_reset_function_locked              drivers/pci/pci.c:5230
   │     └── pcie_reset_flr → pcie_flr          drivers/pci/pci.c:4535
   │           ├── set BCR_FLR in PCIe DEVCTL
   │           ├── msleep(100)
   │           └── pci_dev_wait
   │
   ├── pci_dev_restore                          drivers/pci/pci.c:5180
   │     ├── pci_restore_state
   │     └── err_handler->reset_done = virtio_pci_reset_done
   │           ├── pci_enable_device + pci_set_master
   │           └── virtio_device_reset_done
   │                 └── virtio_device_restore_priv(restore=false)   drivers/virtio/virtio.c:549
   │                       ├── virtio_reset_device (vp_reset)
   │                       ├── status: ACKNOWLEDGE → DRIVER
   │                       ├── finalize_features + virtio_features_ok → FEATURES_OK
   │                       ├── drv->reset_done = virtblk_reset_done
   │                       │     └── virtblk_restore_priv
   │                       │           ├── init_vq (recreate virtqueues, MSI-X)
   │                       │           ├── virtio_device_ready (DRIVER_OK)
   │                       │           └── blk_mq_unquiesce_queue + run_hw_queues
   │                       └── virtio_config_core_enable
   │
   └── pci_cfg_access_unlock, pci_dev_unlock(dev), pci_dev_unlock(bridge)
```

---

## Stage 1 — Sysfs Entry: `reset_store`

Trace (line 851):

```
reset_store <-kernfs_fop_write_iter
__pm_runtime_resume <-reset_store
pci_reset_function <-reset_store
```

Source — `drivers/pci/pci-sysfs.c:1381`:

```c
static ssize_t reset_store(struct device *dev, struct device_attribute *attr,
                           const char *buf, size_t count)
{
    struct pci_dev *pdev = to_pci_dev(dev);
    unsigned long val;
    ssize_t result;

    if (kstrtoul(buf, 0, &val) < 0)
        return -EINVAL;
    if (val != 1)
        return -EINVAL;

    pm_runtime_get_sync(dev);
    result = pci_reset_function(pdev);
    pm_runtime_put(dev);
    ...
}
```

Writing `1` validates input, wakes the device via runtime PM, and calls
`pci_reset_function()`.

---

## Stage 2 — `pci_reset_function`: Lock → Save+Disable → Reset → Restore

Trace (lines 856–869, 3142, 3270, 3277, 5944):

```
pci_reset_function
  mutex_lock           (bridge lock)  pci_cfg_access_lock
  mutex_lock           (dev lock)     pci_cfg_access_lock
  pci_dev_save_and_disable           <-- calls driver's reset_prepare
  ... (long preparation work) ...
  __pci_reset_function_locked        <-- actual hardware FLR
    pcie_reset_flr
      pcie_flr
        pci_dev_wait                 (wait device readiness)
  pci_dev_restore                    <-- calls driver's reset_done
  pci_cfg_access_unlock
```

Source — `drivers/pci/pci.c:5308`:

```c
int pci_reset_function(struct pci_dev *dev)
{
    struct pci_dev *bridge;
    int rc;

    if (!pci_reset_supported(dev))
        return -ENOTTY;

    bridge = pci_upstream_bridge(dev);
    if (bridge)
        pci_dev_lock(bridge);

    pci_dev_lock(dev);
    pci_dev_save_and_disable(dev);

    rc = __pci_reset_function_locked(dev);

    pci_dev_restore(dev);
    pci_dev_unlock(dev);

    if (bridge)
        pci_dev_unlock(bridge);

    return rc;
}
```

The bridge + device locks keep the bus topology consistent during the FLR.

---

## Stage 3 — `pci_dev_save_and_disable`: Quiesce the Driver

Trace (lines 869–870, 3136):

```
pci_dev_save_and_disable <-pci_reset_function
  virtio_pci_reset_prepare <-pci_dev_save_and_disable   <-- err_handler->reset_prepare
  ...
  pci_write_config_word    (PCI_COMMAND = INTX_DISABLE)
```

Source — `drivers/pci/pci.c:5147`:

```c
static void pci_dev_save_and_disable(struct pci_dev *dev)
{
    const struct pci_error_handlers *err_handler =
            dev->driver ? dev->driver->err_handler : NULL;

    if (err_handler && err_handler->reset_prepare)
        err_handler->reset_prepare(dev);
    ...
    pci_set_power_state(dev, PCI_D0);
    pci_save_state(dev);
    pci_write_config_word(dev, PCI_COMMAND, PCI_COMMAND_INTX_DISABLE);
}
```

The bound virtio-pci driver registers these handlers
(`drivers/virtio/virtio_pci_common.c:832`):

```c
static const struct pci_error_handlers virtio_pci_err_handler = {
    .reset_prepare  = virtio_pci_reset_prepare,
    .reset_done     = virtio_pci_reset_done,
};
```

---

## Stage 4 — `virtio_pci_reset_prepare` → `virtio_device_reset_prepare`

Trace (lines 870–876):

```
virtio_pci_reset_prepare
  virtio_device_reset_prepare
    _raw_spin_lock_irq                 (config_core_enabled = false)
    vp_get_status / vp_modern_get_status
    virtblk_reset_prepare              <-- drv->reset_prepare
```

Source — `drivers/virtio/virtio_pci_common.c:797`:

```c
static void virtio_pci_reset_prepare(struct pci_dev *pci_dev)
{
    struct virtio_pci_device *vp_dev = pci_get_drvdata(pci_dev);
    int ret = 0;

    ret = virtio_device_reset_prepare(&vp_dev->vdev);
    ...
    if (pci_is_enabled(pci_dev))
        pci_disable_device(pci_dev);
}
```

Source — `drivers/virtio/virtio.c:634`:

```c
int virtio_device_reset_prepare(struct virtio_device *dev)
{
    struct virtio_driver *drv = drv_to_virtio(dev->dev.driver);
    int ret;

    if (!drv || !drv->reset_prepare)
        return -EOPNOTSUPP;

    virtio_config_core_disable(dev);
    dev->failed = dev->config->get_status(dev) & VIRTIO_CONFIG_S_FAILED;
    ret = drv->reset_prepare(dev);
    ...
}
```

`virtio_config_core_disable` clears `config_core_enabled` so any incoming
config-change interrupt is queued (not dispatched) until restore completes.

---

## Stage 5 — `virtblk_reset_prepare` → `virtblk_freeze_priv` (heavy lifting)

Trace (lines 876–2638), ~14 ms of pre-FLR work:

```
virtblk_reset_prepare
  virtblk_freeze_priv
    blk_mq_freeze_queue_nomemsave        line 878
    blk_mq_freeze_queue_wait             line 908   (drain in-flight bios)
    blk_mq_quiesce_queue_nowait          line 1011  (block dispatchers)
    blk_mq_unfreeze_queue_nomemrestore   line 1015  (queue still quiesced)
    virtio_reset_device                  line 1027
      vp_reset                           line 1028
        vp_modern_set_status   (status=0)         line 1029
        vp_modern_get_status   loop + msleep(1)   lines 1030..1238
        vp_synchronize_vectors                    line 1239
    flush_work (config_work)              line 1276
    vp_del_vqs                            line 1280
      pci_irq_vector / __irq_apply_affinity_hint / free_irq   x N vqs
      vp_del_vq.isra.0 → del_vq → vp_modern_queue_vector
                       → vring_del_virtqueue → kfree
      vp_modern_config_vector                line 1482
      pci_free_irq_vectors                   line 1483
    kfree(vblk->vqs)                      line 2638
```

Source — `drivers/block/virtio_blk.c:1583`:

```c
static int virtblk_freeze_priv(struct virtio_device *vdev)
{
    struct virtio_blk *vblk = vdev->priv;
    struct request_queue *q = vblk->disk->queue;
    unsigned int memflags;

    /* Ensure no requests in virtqueues before deleting vqs. */
    memflags = blk_mq_freeze_queue(q);
    blk_mq_quiesce_queue_nowait(q);
    blk_mq_unfreeze_queue(q, memflags);

    /* Ensure we don't receive any more interrupts */
    virtio_reset_device(vdev);

    /* Make sure no work handler is accessing the device. */
    flush_work(&vblk->config_work);

    vdev->config->del_vqs(vdev);
    kfree(vblk->vqs);

    return 0;
}
```

The freeze/quiesce/unfreeze sequence drains in-flight bios and keeps the queue
quiesced so the block layer stops dispatching across the FLR window.

`virtio_reset_device` calls the transport reset
(`drivers/virtio/virtio.c:253`):

```c
void virtio_reset_device(struct virtio_device *dev)
{
#ifdef CONFIG_VIRTIO_HARDEN_NOTIFICATION
    virtio_break_device(dev);
    virtio_synchronize_cbs(dev);
#endif
    dev->config->reset(dev);
}
```

The trace confirms the modern transport (`drivers/virtio/virtio_pci_modern.c:535`):

```c
static void vp_reset(struct virtio_device *vdev)
{
    struct virtio_pci_device *vp_dev = to_vp_device(vdev);
    struct virtio_pci_modern_device *mdev = &vp_dev->mdev;

    /* 0 status means a reset. */
    vp_modern_set_status(mdev, 0);
    while (vp_modern_get_status(mdev))
        msleep(1);

    vp_modern_avq_cleanup(vdev);
    vp_synchronize_vectors(vdev);
}
```

The visible `msleep` loop (lines 1031, 1135) is the spec-mandated polling for
`device_status` to read 0 after writing 0 — flushing both the status write and
in-flight MSI-X.

After this, `del_vqs` releases per-VQ MSI-X IRQs and tears down vrings, and
`pci_free_irq_vectors` releases the MSI-X table. Back in
`virtio_pci_reset_prepare`, `pci_disable_device(pci_dev)` clears Bus Master via
`pci_write_config_word` (line 3136) — the final step of
`pci_dev_save_and_disable`.

---

## Stage 6 — `__pci_reset_function_locked`: The Actual FLR

Trace (lines 3142–3270):

```
__pci_reset_function_locked
  pcie_reset_flr
    pcie_flr
      pcie_capability_set_word(PCI_EXP_DEVCTL, BCR_FLR)
      msleep(100)
  pci_dev_wait     <-- ~102 ms total wait until config space responds
```

Source — `drivers/pci/pci.c:5230`:

```c
int __pci_reset_function_locked(struct pci_dev *dev)
{
    int i, m, rc;

    might_sleep();

    for (i = 0; i < PCI_NUM_RESET_METHODS; i++) {
        m = dev->reset_methods[i];
        if (!m)
            return -ENOTTY;

        rc = pci_reset_fn_methods[m].reset_fn(dev, PCI_RESET_DO_RESET);
        if (!rc)
            return 0;
        if (rc != -ENOTTY)
            return rc;
    }
    return -ENOTTY;
}
```

Source — `drivers/pci/pci.c:4535`:

```c
int pcie_flr(struct pci_dev *dev)
{
    if (!pci_wait_for_pending_transaction(dev))
        pci_err(dev, "timed out waiting for pending transaction; performing function level reset anyway\n");

    pcie_capability_set_word(dev, PCI_EXP_DEVCTL, PCI_EXP_DEVCTL_BCR_FLR);

    if (dev->imm_ready)
        return 0;

    msleep(100);

    return pci_dev_wait(dev, "FLR", PCIE_RESET_READY_POLL_MS);
}
```

The selected reset method is FLR (`pcie_reset_flr` is index 3 in
`pci_reset_fn_methods[]`). The 100 ms sleep is required by the PCIe spec; the
trace timestamp jump from `1176.164349` to `1176.267009` matches.

---

## Stage 7 — `pci_dev_restore` → `virtio_pci_reset_done`

Trace (lines 3277, 3701–3754):

```
pci_dev_restore
  pci_restore_state ...
  virtio_pci_reset_done           <-- err_handler->reset_done
    pci_enable_device
    pci_set_master
    virtio_device_reset_done
      virtio_device_restore_priv(restore=false)
```

Source — `drivers/pci/pci.c:5180`:

```c
static void pci_dev_restore(struct pci_dev *dev)
{
    const struct pci_error_handlers *err_handler =
            dev->driver ? dev->driver->err_handler : NULL;

    pci_restore_state(dev);

    if (err_handler && err_handler->reset_done)
        err_handler->reset_done(dev);
    ...
}
```

Source — `drivers/virtio/virtio_pci_common.c:814`:

```c
static void virtio_pci_reset_done(struct pci_dev *pci_dev)
{
    struct virtio_pci_device *vp_dev = pci_get_drvdata(pci_dev);
    int ret;

    if (pci_is_enabled(pci_dev))
        return;

    ret = pci_enable_device(pci_dev);
    if (!ret) {
        pci_set_master(pci_dev);
        ret = virtio_device_reset_done(&vp_dev->vdev);
    }
    ...
}
```

---

## Stage 8 — `virtio_device_restore_priv` (Re-init Device + Driver)

Trace (lines 3754–5944):

```
virtio_device_restore_priv
  vp_reset                                  (line 3755 — sanity reset)
    vp_modern_set_status(0) + poll + msleep
  vp_set_status (ACKNOWLEDGE)               (line 3885)
  vp_set_status (DRIVER)                    (line 3890)
  vp_finalize_features                      (line 3892)
  virtio_features_ok                        (line 3895)
  vp_set_status (FEATURES_OK)               (line 3902)
  virtblk_reset_done                        (line 3905)   <-- drv->reset_done
    init_vq                                 (line 3906)
    vp_set_status (DRIVER_OK)               (line 5917)
    blk_mq_unquiesce_queue                  (line 5919)
    blk_mq_run_hw_queues                    (line 5923)
  virtio_config_core_enable                 (line 5941)
```

Source — `drivers/virtio/virtio.c:549`:

```c
static int virtio_device_restore_priv(struct virtio_device *dev, bool restore)
{
    struct virtio_driver *drv = drv_to_virtio(dev->dev.driver);
    int ret;

    virtio_reset_device(dev);
    virtio_add_status(dev, VIRTIO_CONFIG_S_ACKNOWLEDGE);
    if (dev->failed)
        virtio_add_status(dev, VIRTIO_CONFIG_S_FAILED);
    if (!drv) return 0;

    virtio_add_status(dev, VIRTIO_CONFIG_S_DRIVER);
    ret = dev->config->finalize_features(dev);
    if (ret) goto err;
    ret = virtio_features_ok(dev);
    if (ret) goto err;

    if (restore) {
        if (drv->restore) ret = drv->restore(dev);
    } else {
        ret = drv->reset_done(dev);
    }
    if (ret) goto err;

    if (!(dev->config->get_status(dev) & VIRTIO_CONFIG_S_DRIVER_OK))
        virtio_device_ready(dev);

    virtio_config_core_enable(dev);
    return 0;
err:
    virtio_add_status(dev, VIRTIO_CONFIG_S_FAILED);
    return ret;
}
```

This is the canonical virtio init handshake:

> RESET → ACKNOWLEDGE → DRIVER → FEATURES_OK → DRIVER_OK

Each step appears in the trace as a `vp_modern_set_status` call.

The driver's restore hook is `virtblk_reset_done`
(`drivers/block/virtio_blk.c:1606`):

```c
static int virtblk_restore_priv(struct virtio_device *vdev)
{
    struct virtio_blk *vblk = vdev->priv;
    int ret;

    ret = init_vq(vdev->priv);
    if (ret)
        return ret;

    virtio_device_ready(vdev);
    blk_mq_unquiesce_queue(vblk->disk->queue);

    return 0;
}

static int virtblk_reset_done(struct virtio_device *vdev)
{
    return virtblk_restore_priv(vdev);
}
```

`init_vq` re-allocates virtqueues (the long block ending around line 5915 —
MSI-X re-allocation, vring rebuild, queue→vector mapping). `virtio_device_ready`
writes `DRIVER_OK`, `blk_mq_unquiesce_queue` releases the block layer, and
`blk_mq_run_hw_queues` flushes pending I/O.

Finally `virtio_config_core_enable` re-arms the config-change path and
`pci_reset_function` drops the locks — reset complete.

---

## Key Observations

1. **The reset method selected is FLR.** Of the 7 methods in
   `pci_reset_fn_methods[]`, `pcie_reset_flr` (index 3) succeeds first, so
   `__pci_reset_function_locked` returns after `pcie_flr`.
2. **Two `vp_reset` events occur.** First inside `virtblk_freeze_priv` (cleanly
   stops the device before FLR); second inside `virtio_device_restore_priv`
   (defensive reset before re-init). Both write `status=0` and poll until the
   device clears its status register.
3. **Block I/O is paused, not lost.** `blk_mq_freeze_queue` drains in-flight
   requests, `blk_mq_quiesce_queue_nowait` blocks new dispatches across the
   FLR window, and `blk_mq_unquiesce_queue` resumes them only after `DRIVER_OK`.
4. **Hot-path timing.** `pcie_flr` enforces `msleep(100)` after writing
   `BCR_FLR` — this single sleep is the dominant cost
   (`1176.164349` → `1176.267009`, ~103 ms of the ~121 ms total).
5. **Config-change isolation.** `virtio_config_core_disable` /
   `virtio_config_core_enable` brackets the whole reset, ensuring config-change
   interrupts during the window are queued and re-emitted after restore.
6. **The status register handshake is fully spec-compliant.**
   RESET (=0) → ACKNOWLEDGE → DRIVER → FEATURES_OK → DRIVER_OK is visible 1:1
   in the trace as successive `vp_modern_set_status` calls.

---

## File / Function Reference

| Function                          | File                                     | Role                                                   |
|----------------------------------:|------------------------------------------|--------------------------------------------------------|
| `reset_store`                     | `drivers/pci/pci-sysfs.c:1381`           | sysfs entry point                                      |
| `pci_reset_function`              | `drivers/pci/pci.c:5308`                 | top-level orchestrator (locks, save/restore)           |
| `pci_dev_save_and_disable`        | `drivers/pci/pci.c:5147`                 | invokes `reset_prepare`, saves state, disables device  |
| `__pci_reset_function_locked`     | `drivers/pci/pci.c:5230`                 | iterates `pci_reset_fn_methods[]`                      |
| `pcie_reset_flr` / `pcie_flr`     | `drivers/pci/pci.c:4563` / `:4535`       | actual FLR (write `BCR_FLR`, sleep 100 ms, wait)       |
| `pci_dev_restore`                 | `drivers/pci/pci.c:5180`                 | restores config, invokes `reset_done`                  |
| `virtio_pci_reset_prepare/done`   | `drivers/virtio/virtio_pci_common.c:797/814` | virtio-pci `pci_error_handlers`                    |
| `virtio_device_reset_prepare/done`| `drivers/virtio/virtio.c:634/656`        | core virtio prepare/done dispatch                      |
| `virtio_device_restore_priv`      | `drivers/virtio/virtio.c:549`            | virtio status handshake + driver restore               |
| `vp_reset`                        | `drivers/virtio/virtio_pci_modern.c:535` | transport reset (status=0, poll, sync vectors)         |
| `virtio_reset_device`             | `drivers/virtio/virtio.c:253`            | wraps `dev->config->reset`                             |
| `virtblk_reset_prepare`           | `drivers/block/virtio_blk.c:1633`        | virtio-blk prepare hook                                |
| `virtblk_freeze_priv`             | `drivers/block/virtio_blk.c:1583`        | freeze/quiesce queue, reset, free VQs                  |
| `virtblk_reset_done`              | `drivers/block/virtio_blk.c:1638`        | virtio-blk done hook                                   |
| `virtblk_restore_priv`            | `drivers/block/virtio_blk.c:1606`        | re-init VQs, mark `DRIVER_OK`, unquiesce queue         |
