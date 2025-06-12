#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2025 Liu, Changcheng <changcheng.liu@aliyun.com>

# FW(32.43.2566) cfg
#
# $ mlxconfig -d /dev/mst/mt41692_pciconf0 -y reset
# $ mlxconfig -d /dev/mst/mt41692_pciconf0 -y reset
# $ mlxconfig -d /dev/mst/mt41692_pciconf0 -y set  NVME_EMULATION_ENABLE=1
# $ mlxconfig -d /dev/mst/mt41692_pciconf0 -y set  NVME_EMULATION_NUM_VF=50
# $ mlxconfig -d /dev/mst/mt41692_pciconf0 -y set  NVME_EMULATION_NUM_MSIX=32
# $ mlxconfig -d /dev/mst/mt41692_pciconf0 -y set  NVME_EMULATION_NUM_VF_MSIX=32
# $ mlxconfig -d /dev/mst/mt41692_pciconf0 -y set  PCI_SWITCH_EMULATION_NUM_PORT=32
# $ mlxconfig -d /dev/mst/mt41692_pciconf0 -y set  PCI_SWITCH_EMULATION_ENABLE=1
# $ mlxconfig -d /dev/mst/mt41692_pciconf0 -y set  PF_TOTAL_SF=32
# $ mlxconfig -d /dev/mst/mt41692_pciconf0 -y set  PF_SF_BAR_SIZE=8
#

export SNAP_RPC_SRC=/root/old/snap_rpc.py
export SPDK_SOCK_SRC=/var/tmp/spdk.sock.src
export SRC_SNAP=/root/lod/install/bin

export SNAP_RPC_DST=/root/new/snap_rpc.py
export SPDK_SOCK_DST=/var/tmp/spdk.sock.dst
export DST_SNAP=/root/new/install/bin

export NVME_EMU_PROVIDER=dpa
source /root/new/install/bin/set_environment_variables.sh

$DST_SNAP/snap_service -m 0x0F00 -r $SPDK_SOCK_DST >> /root/snap_dst.log 2>&1 &

TIMEOUT=30  # Total timeout in seconds
RETRIES=60  # Number of retries
start_time=$(date +%s)

while (( $(date +%s) - start_time < TIMEOUT )); do
  for (( attempt=0; attempt<RETRIES; attempt++ )); do
    if spdk_rpc.py -s $SPDK_SOCK_DST spdk_get_version &>/dev/null; then
      break 2
    fi
  done

  sleep 1
done

if (( $(date +%s) - start_time >= TIMEOUT )); then
  echo "[$(date +"%Y-%m-%d %H:%M:%S.%N")] Timeout of $TIMEOUT seconds reached. SPDK_SOCK has not been detected."
fi

$SNAP_RPC_DST -s $SPDK_SOCK_DST snap_log_level_set -l 4

$SNAP_RPC_DST -s $SPDK_SOCK_DST nvme_subsystem_create -s nqn.2022-10.io.nvda.nvme:0 -mn 'BF3 SNAP Ctrl' -sn 'JX_DBG' -mnan 1024 -nn 1024
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_suspend -c NVMeCtrl1 --admin_only
$SNAP_RPC_DST -s $SPDK_SOCK_DST nvme_controller_create --pf_id 0 --ctrl NVMeCtrl1 --nqn nqn.2022-10.io.nvda.nvme:0 --mdts 7 --num_queues 0 --suspended --live_update_listener
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_suspend -c NVMeCtrl1 --live_update_notifier --timeout_ms 20
 
spdk_rpc.py -s $SPDK_SOCK_DST bdev_null_create null2 64 512 --uuid 1ebe1c37-f6fd-47fd-8438-de55235a7501
$SNAP_RPC_DST -s $SPDK_SOCK_DST nvme_namespace_create --nqn nqn.2022-10.io.nvda.nvme:0 --nsid 2 --bdev_name null2 --uuid 3d9c3b54-5c31-410a-b4f0-7cf2afd9e101
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_suspend -c NVMeCtrl3 --admin_only
$SNAP_RPC_DST -s $SPDK_SOCK_DST nvme_controller_create --pf_id 0 --vf_id 1 --ctrl NVMeCtrl3 --nqn nqn.2022-10.io.nvda.nvme:0 --mdts 7 --num_queues 1 --suspended --live_update_listener
$SNAP_RPC_DST -s $SPDK_SOCK_DST nvme_controller_attach_ns --ctrl NVMeCtrl3 --nsid 2
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_suspend -c NVMeCtrl3 --live_update_notifier --timeout_ms 20
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_detach_ns --ctrl NVMeCtrl3 --nsid 2
spdk_rpc.py   -s $SPDK_SOCK_SRC bdev_null_delete null2
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_destroy --ctrl NVMeCtrl3
 
 
spdk_rpc.py -s $SPDK_SOCK_DST bdev_null_create null1 64 512 --uuid 1ebe1c37-f6fd-47fd-8438-de55235a7500
$SNAP_RPC_DST -s $SPDK_SOCK_DST nvme_namespace_create --nqn nqn.2022-10.io.nvda.nvme:0 --nsid 1 --bdev_name null1 --uuid 3d9c3b54-5c31-410a-b4f0-7cf2afd9e100
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_suspend -c NVMeCtrl2 --admin_only
$SNAP_RPC_DST -s $SPDK_SOCK_DST nvme_controller_create --pf_id 0 --vf_id 0 --ctrl NVMeCtrl2 --nqn nqn.2022-10.io.nvda.nvme:0 --mdts 7 --num_queues 1 --suspended --live_update_listener
$SNAP_RPC_DST -s $SPDK_SOCK_DST nvme_controller_attach_ns --ctrl NVMeCtrl2 --nsid 1
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_suspend -c NVMeCtrl2 --live_update_notifier --timeout_ms 20
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_detach_ns --ctrl NVMeCtrl2 --nsid 1
spdk_rpc.py   -s $SPDK_SOCK_SRC bdev_null_delete null1
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_destroy --ctrl NVMeCtrl2
 
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_destroy --ctrl NVMeCtrl1

ORG_PID=`pgrep -xof "$SRC_SNAP/snap_service -m 0xF000 -r $SPDK_SOCK_SRC"`
kill -9 $ORG_PID
while kill -0 $ORG_PID 2> /dev/null; do true; done
sudo fio --ioengine=libaio --direct=1 --group_reporting --time_based --runtime=259200 --iodepth=264 --numjobs=16 --bs=1M --rw=write --name=vdb --filename=/dev/nvme1n1 --name=vdc --filename=/dev/nvme1n2
