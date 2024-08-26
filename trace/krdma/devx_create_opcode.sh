#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2023 Liu, Changcheng <changcheng.liu@aliyun.com>

cd /sys/kernel/debug/tracing

# objdump -S `modinfo mlx5_ib | grep 'filename' | cut -d ':' -f 2` > mlx5_ib.s
# || 0000000000031608 <mlx5_ib_handler_MLX5_IB_METHOD_DEVX_OBJ_CREATE>:
# || 317d8: sxtw  x0, w24
# ||
# || 317f8: b.ls  318c8 <mlx5_ib_handler_MLX5_IB_METHOD_DEVX_OBJ_CREATE+0x2c0>  // b.plast
# ||
# || 318c8: adrp  x0, 0 <kmalloc_caches>
# || 318ec: ldr   w2, [sp, #116]         ==> opcode is at sp[116]
# || 318f8: cmp   w2, #0x200
# ||
# || 31a84: b.ne  31a94 <mlx5_ib_handler_MLX5_IB_METHOD_DEVX_OBJ_CREATE+0x48c>  // b.any
# || 31a88: ldr   w0, [x27, #4]
# || 31a8c: rev   w0, w0
# || 31a90: lsl   w0, w0, #16            ==> w0 = obj_type << 16
# ||
# || 31a94: ldr   w1, [sp, #116]         ==> w1 = opcode
# || 31a98: ldr   w2, [sp, #132]
# ||
# || 31a9c: orr   w0, w1, w0             ==> w0 = opcode | obj_type << 16
# || 31aa0: ldr   w1, [x28, #84]         ==> w1 = obj->flags
# || 31aa4: orr   x0, x2, x0, lsl #32    ==> x0 = x2 | x0 << 32
# || 31aa8: str   x0, [x28, #8]          ==> x28 is pointer obj
# || 31aac: tbz   w1, #0, 31774 <mlx5_ib_handler_MLX5_IB_METHOD_DEVX_OBJ_CREATE+0x16c>
# || 31ab0: ldr   w3, [x27, #20]

echo 'p:mlx5_ib/create mlx5_ib:mlx5_ib_handler_MLX5_IB_METHOD_DEVX_OBJ_CREATE+0x490 opcode=%x1:x16 obj_type=%x0:x32 flags=+84(%x28):x32' > kprobe_events
echo 1 > events/mlx5_ib/create/enable

#How to disable?
# # echo 0 > /sys/kernel/debug/tracing/events/mlx5_ib/create/enable
# # echo '-:mlx5_ib/create' > /sys/kernel/debug/tracing/kprobe_events
