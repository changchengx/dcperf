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

#
# You should add one single parameter for thsi scritp when running at first time
#

export SNAP_RPC_SRC=/root/alibaba_org/snap_rpc.py
export SNAP_RPC_DST=/root/fur/snap_rpc.py

export SPDK_SOCK_SRC=/var/tmp/spdk.sock.src
export SPDK_SOCK_DST=/var/tmp/spdk.sock.dst

export SRC_SNAP=/root/alibaba_org/install/bin
export DST_SNAP=/root/fur/install/bin

export NVME_EMU_PROVIDER=dpa
source /root/alibaba_org/install/bin/set_environment_variables.sh

$SRC_SNAP/snap_service -m 0xF000 -r $SPDK_SOCK_SRC >> /root/snap_src.log 2>&1 &

TIMEOUT=30  # Total timeout in seconds
RETRIES=60  # Number of retries
start_time=$(date +%s)

while (( $(date +%s) - start_time < TIMEOUT )); do
  for (( attempt=0; attempt<RETRIES; attempt++ )); do
    if spdk_rpc.py -s $SPDK_SOCK_SRC spdk_get_version &>/dev/null; then
      break 2
    fi
  done

  sleep 1
done

if (( $(date +%s) - start_time >= TIMEOUT )); then
  echo "[$(date +"%Y-%m-%d %H:%M:%S.%N")] Timeout of $TIMEOUT seconds reached. SPDK_SOCK has not been detected."
fi

if [ $# -ne 0 ]; then
    $SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_emulation_device_attach --num_msix 5
fi


$SNAP_RPC_SRC -s $SPDK_SOCK_SRC snap_log_level_set -l 4
spdk_rpc.py   -s $SPDK_SOCK_SRC bdev_malloc_create -b Malloc0 1024 512 --uuid 1ebe1c37-f6fd-47fd-8438-de55235a7500
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_subsystem_create -s nqn.2022-10.io.nvda.nvme:0 -mn 'BF3 SNAP Ctrl' -sn 'JX_DBG' -mnan 1024 -nn 1024 --single_ctrl
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_namespace_create --nqn nqn.2022-10.io.nvda.nvme:0 --nsid 1 --bdev_name Malloc0 --uuid 3d9c3b54-5c31-410a-b4f0-7cf2afd9e100
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_create --vhca_id 6 --ctrl NVMeCtrl1 --nqn nqn.2022-10.io.nvda.nvme:0 --mdts 6 --num_queues 4 --suspended
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_attach_ns --ctrl NVMeCtrl1 --nsid 1
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_resume -c NVMeCtrl1

echo "execute command on host: sudo fio --ioengine=libaio --direct=1 --group_reporting --time_based --runtime=259200 --iodepth=264 --numjobs=16 --bs=1M --rw=write --name=vdb --filename=/dev/nvme1n1"
sleep 20

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
spdk_rpc.py   -s $SPDK_SOCK_DST bdev_malloc_create -b Malloc0 1024 512 --uuid 1ebe1c37-f6fd-47fd-8438-de55235a7500
$SNAP_RPC_DST -s $SPDK_SOCK_DST nvme_subsystem_create -s nqn.2022-10.io.nvda.nvme:0 -mn 'BF3 SNAP Ctrl' -sn 'JX_DBG' -mnan 1024 -nn 1024 --single_ctrl
$SNAP_RPC_DST -s $SPDK_SOCK_DST nvme_namespace_create --nqn nqn.2022-10.io.nvda.nvme:0 --nsid 1 --bdev_name Malloc0 --uuid 3d9c3b54-5c31-410a-b4f0-7cf2afd9e100

$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_suspend --ctrl NVMeCtrl1 --admin_only
$SNAP_RPC_DST -s $SPDK_SOCK_DST nvme_controller_create --vhca_id 6 --ctrl NVMeCtrl1 --nqn nqn.2022-10.io.nvda.nvme:0 --mdts 6 --num_queues 4 --suspended --live_update_listener
$SNAP_RPC_DST -s $SPDK_SOCK_DST nvme_controller_attach_ns --ctrl NVMeCtrl1 --nsid 1

$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_suspend --ctrl NVMeCtrl1 --live_update_notifier --timeout_ms 600
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_detach_ns --ctrl NVMeCtrl1 --nsid 1
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_destroy --ctrl NVMeCtrl1
spdk_rpc.py   -s $SPDK_SOCK_SRC bdev_malloc_delete Malloc0

ORG_PID=`pgrep -xof "$SRC_SNAP/snap_service -m 0xF000 -r $SPDK_SOCK_SRC"`
kill -9 $ORG_PID
while kill -0 $ORG_PID 2> /dev/null; do true; done
