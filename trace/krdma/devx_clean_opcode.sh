#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2023 Liu, Changcheng <changcheng.liu@aliyun.com>

cd /sys/kernel/debug/tracing

#uobject: arg1
#obj: +24($arg1)
#opcode: obj->inbox, +20(obj)
#obj_type: obj->inbox[6], +6(+20(obj))( not work, need to use +26(obj) )
#flags: obj->flags, +84(obj)
echo 'p:mlx5_ib/clean mlx5_ib:devx_obj_cleanup opcode=+20(+24($arg1)):x16 obj_type=+26(+24($arg1)):x16 flags=+84(+24($arg1)):x32' > kprobe_events
echo 1 > events/mlx5_ib/clean/enable

#How to disable:
# # echo 0 > /sys/kernel/debug/tracing/events/mlx5_ib/clean/enable
# # echo '-:mlx5_ib/clean' > /sys/kernel/debug/tracing/kprobe_events
