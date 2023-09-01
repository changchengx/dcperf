#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2023 Liu, Changcheng <changcheng.liu@aliyun.com>

for i in `seq 0 99`
do
    virsh attach-device snap_vm_gp0 0/vf$i.xml --config
done
