#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2025 Liu, Changcheng <changcheng.liu@aliyun.com>

# FW(32.43.2566) cfg
#
# $ mlxconfig -d /dev/mst/mt41692_pciconf0 -y reset
# $ mlxconfig -d /dev/mst/mt41692_pciconf0 -y set NVME_EMULATION_ENABLE=1 NVME_EMULATION_NUM_MSIX=4 PF_TOTAL_SF=32 PF_SF_BAR_SIZE=8
#

export NVME_EMU_PROVIDER=dpa
source /root/nvmx_453/install/bin/set_environment_variables.sh

/root/nvmx_453/install/bin/snap_service -m 0xF000 -s 1024 --iova-mode pa -r /var/tmp/spdk.sock.src >> /root/snap.log 2>&1 &
# Wait for bootup src service
sleep 20

spdk_rpc.py -s /var/tmp/spdk.sock.src bdev_malloc_create -b Malloc0 1024 512 --uuid 1ebe1c37-f6fd-47fd-8438-de55235a7500
spdk_rpc.py -s /var/tmp/spdk.sock.src bdev_delay_create -b Malloc0 -d Delay0 -t 10000000 -w 10000000 -n 10000000 -r 10000000
snap_rpc.py -s /var/tmp/spdk.sock.src nvme_subsystem_create -s nqn.2022-10.io.nvda.nvme:0 -mn 'BF3 SNAP Ctrl' -sn 'JX_DBG' -mnan 1024 -nn 1024 --single_ctrl
snap_rpc.py -s /var/tmp/spdk.sock.src nvme_namespace_create --nqn nqn.2022-10.io.nvda.nvme:0 --nsid 1 --bdev_name Delay0 --uuid 3d9c3b54-5c31-410a-b4f0-7cf2afd9e100
snap_rpc.py -s /var/tmp/spdk.sock.src nvme_controller_create --vhca_id 2 --ctrl NVMeCtrl1 --nqn nqn.2022-10.io.nvda.nvme:0 --mdts 6 --num_queues 2 --suspended
snap_rpc.py -s /var/tmp/spdk.sock.src nvme_controller_attach_ns --ctrl NVMeCtrl1 --nsid 1
snap_rpc.py -s /var/tmp/spdk.sock.src nvme_controller_resume -c NVMeCtrl1

# Host is running fio
sleep 120

/root/nvmx_453/install/bin/snap_service -m 0x0F00 -s 1024 --iova-mode pa -r /var/tmp/spdk.sock.dst >> /root/snap.log_new 2>&1 &
# Wait for bootup dst service
sleep 20

spdk_rpc.py -s /var/tmp/spdk.sock.dst bdev_malloc_create 1024 512 -b Malloc0 --uuid 1ebe1c37-f6fd-47fd-8438-de55235a7500
spdk_rpc.py -s /var/tmp/spdk.sock.dst bdev_delay_create -b Malloc0 -d Delay0 -t 10000000 -w 10000000 -n 10000000 -r 10000000
snap_rpc.py -s /var/tmp/spdk.sock.dst nvme_subsystem_create -s nqn.2022-10.io.nvda.nvme:0 -mn 'BF3 SNAP Ctrl' -sn 'JX_DGB' -mnan 1024 -nn 1024 --single_ctrl
snap_rpc.py -s /var/tmp/spdk.sock.dst nvme_namespace_create --nqn nqn.2022-10.io.nvda.nvme:0 --nsid 1 --bdev_name Delay0 --uuid 3d9c3b54-5c31-410a-b4f0-7cf2afd9e100
snap_rpc.py -s /var/tmp/spdk.sock.src nvme_controller_suspend --ctrl NVMeCtrl1
snap_rpc.py -s /var/tmp/spdk.sock.dst nvme_controller_create --vhca_id 2 --ctrl NVMeCtrl1 --nqn nqn.2022-10.io.nvda.nvme:0 --mdts 6 --num_queues 2 --suspended --live_update_listener
snap_rpc.py -s /var/tmp/spdk.sock.dst nvme_controller_attach_ns --ctrl NVMeCtrl1 --nsid 1

snap_rpc.py -s /var/tmp/spdk.sock.src  nvme_controller_suspend --ctrl NVMeCtrl1 --live_update_notifier --timeout_ms 600
snap_rpc.py -s /var/tmp/spdk.sock.src  nvme_controller_detach_ns --ctrl NVMeCtrl1 --nsid 1
spdk_rpc.py -s /var/tmp/spdk.sock.src  bdev_delay_delete Delay0
spdk_rpc.py -s /var/tmp/spdk.sock.src  bdev_malloc_delete Malloc0
snap_rpc.py -s /var/tmp/spdk.sock.src  nvme_controller_destroy --ctrl NVMeCtrl1

# Kill src service
PID=`pgrep -xof '/root/nvmx_453/install/bin/snap_service -m 0xF000 -s 1024 --iova-mode pa -r /var/tmp/spdk.sock.src'`
kill -9 $PID
