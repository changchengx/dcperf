#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2025 Liu, Changcheng <changcheng.liu@aliyun.com>

vblk_id=$1
ctrl=$2
vuid="MT2306XZ0077VBLKS1D0F0"

#cp /root/jerry/nvmx/install/src/snap_rpc.py /usr/bin/

bdev=`spdk_rpc.py bdev_malloc_create 1024 512`

create_attach() {
    info=`snap_rpc.py virtio_blk_function_create`

    vhca_id=`echo $info | cut -d ',' -f 1 | awk '{print $3}'`
    if [ "$vhca_id" -ne 5 ] && [ "$vhca_id" -ne 6 ] && [ "$vhca_id" -ne 7 ] && [ "$vhca_id" -ne 8 ]; then
        echo "The vhca_id is not 5 and not 6"
        exit
    fi

    vuid=`echo $info | cut -d ',' -f 2 | awk '{print $2}' | cut -d '"' -f 2`

    snap_rpc.py virtio_blk_controller_create -c $ctrl --vuid $vuid --bdev $bdev --num_queues 8 --seg_max 16 --size_max 65536 --vblk_id $vblk_id
    snap_rpc.py virtio_blk_controller_modify -c $ctrl --num_queues 8 --num_msix 10
    snap_rpc.py virtio_blk_controller_hotplug -c $ctrl --wait_for_done
}

detach_destroy() {
    snap_rpc.py virtio_blk_controller_bdev_detach -c $ctrl
    snap_rpc.py virtio_blk_controller_bdev_attach -c $ctrl --dbg_bdev_type null --bdev none --vblk_id $vblk_id
    sleep 2

    snap_rpc.py virtio_blk_controller_hotunplug -c $ctrl --wait_for_done
#    state=`/usr/bin/snap_hotplug_mgr mlx5_0 info | grep $vuid -A 2 | grep 'pci_state_info' | cut -d '"' -f 4 | cut -d ' ' -f 1`
#    if [ "$state" -ne 3 ]; then
#        echo "state:$state, not POWER_OFF, exit"
#        snap_rpc.py virtio_blk_controller_dbg_debug_stats_get --ctrl $ctrl
#        exit
#    fi
    snap_rpc.py virtio_blk_controller_destroy -c $ctrl
    snap_rpc.py virtio_blk_function_destroy --vuid $vuid
}

for ((i=1;i<3000;i++)); do
    echo ---------  test round $i start ----------
    create_attach

    echo ---------  sleeping 100 ----------
    sleep 100

    echo ---------  sleeped 100  ----------
    detach_destroy
    echo --------   test round $i end   -----------
done
