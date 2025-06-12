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
export SRC_SNAP=/root/old/install/bin

export NVME_EMU_PROVIDER=dpa
source /root/old/install/bin/set_environment_variables.sh

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

$SNAP_RPC_SRC -s $SPDK_SOCK_SRC snap_log_level_set -l 4

$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_subsystem_create --nqn nqn.2022-10.io.nvda.nvme:0 -mn 'BF3 SNAP Ctrl' -sn 'JX_DBG' -mnan 1024 -nn 1024
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_create --nqn nqn.2022-10.io.nvda.nvme:0 --ctrl NVMeCtrl1 --pf_id 0 --admin_only
 
spdk_rpc.py   -s $SPDK_SOCK_SRC bdev_null_create null1 64 512 --uuid 1ebe1c37-f6fd-47fd-8438-de55235a7500
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_namespace_create -b null1 -n 1 --nqn nqn.2022-10.io.nvda.nvme:0 --uuid 3d9c3b54-5c31-410a-b4f0-7cf2afd9e100
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_create --nqn nqn.2022-10.io.nvda.nvme:0 --ctrl NVMeCtrl2 --pf_id 0 --vf_id 0 --suspended
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_attach_ns -c NVMeCtrl2 -n 1
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_resume -c NVMeCtrl2
 
spdk_rpc.py   -s $SPDK_SOCK_SRC bdev_null_create null2 64 512 --uuid 1ebe1c37-f6fd-47fd-8438-de55235a7501
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_namespace_create -b null2 -n 2 --nqn nqn.2022-10.io.nvda.nvme:0 --uuid 3d9c3b54-5c31-410a-b4f0-7cf2afd9e101
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_create --nqn nqn.2022-10.io.nvda.nvme:0 --ctrl NVMeCtrl3 --pf_id 0 --vf_id 1 --suspended
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_attach_ns -c NVMeCtrl3 -n 2
$SNAP_RPC_SRC -s $SPDK_SOCK_SRC nvme_controller_resume -c NVMeCtrl3

echo "execute command on host:"
echo "sudo su -c 'echo 2 > /sys/bus/pci/devices/0000:05:00.2/sriov_numvfs"
echo "sudo fio --ioengine=libaio --direct=1 --group_reporting --time_based --runtime=259200 --iodepth=264 --numjobs=16 --bs=1M --rw=write --name=vdb --filename=/dev/nvme1n1 --name=vdc --filename=/dev/nvme1n2"
