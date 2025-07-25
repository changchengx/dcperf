#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2023 Liu, Changcheng <changcheng.liu@aliyun.com>
#
# $ cat -n .ssh/config
# 1  Host *
# 2      LogLevel ERROR
# 3      User root
# 4      StrictHostKeyChecking=no
# 5      UserKnownHostsFile=/dev/null

set_up_sf_if()
{
    /sbin/mlnx-sf --action create --device 0000:03:00.0 --sfnum 0 --hwaddr fe:03:27:08:11:aa
    sleep 3
    ip a a 172.3.99.27/24 dev enp3s0f0s0
    sleep 5
}

set_up_sf_if

boot_snap_service()
{
    source /opt/nvidia/nvda_snap/bin/set_environment_variables.sh
    env SNAP_RDMA_ZCOPY_ENABLE=0 VIRTIO_EMU_PROVIDER=dpu /opt/nvidia/nvda_snap/bin/snap_service -m 0xff00 > /root/snap.log 2>&1 &
    
    TIMEOUT=30  # Total timeout in seconds
    RETRIES=60  # Number of retries
    start_time=$(date +%s)
    
    while (( $(date +%s) - start_time < TIMEOUT )); do
      for (( attempt=0; attempt<RETRIES; attempt++ )); do
        if spdk_rpc.py spdk_get_version &>/dev/null; then
          break 2
        fi
      done
    
      sleep 1
    done
    
    snap_rpc.py snap_log_level_set -l 4
}

#Note: you should run boo_snap_service in this script. You need to execute the commands in a separate session.
#      Or, the snap_service will also be killed then this script exit
if [ 0 -eq 0 ]; then
boot_snap_service
fi

count=0
wait_for_os_bootup()
{
    os_count=$((count+1))
    start_time=$(date +%s)

    while [ true ]
    do
        date
        end_time=$(date +%s)

        diff_time=$((end_time - start_time))
        if [ $diff_time -gt 1200 ]; then
             return 1
        fi

        sleep 5
    	ssh -o ConnectTimeout=10 root@clx-virgo-027 'sleep 10'
        rst=$?

        if [ $rst -eq 0 ]; then
            return 0
        fi
    done
}

remote_attach_disk()
{
    attach_count=0

    while [ true ]
    do
        attach_rst=`/root/ssh_cmd.py bash /root/nvmf/start_new_ubuntu27.sh`
        echo $attach_rst | grep 'nqn.2025-01.baidu.boot:ubuntu27' > /dev/null 2>&1
        rst=$?

        if [ $rst -ne 0 ]; then
            attach_count=$((attach_count+1))
            if [ $attach_count -gt 10 ]; then
                echo "remote failed to attach ubuntu img"
                exit
            fi
            continue
        else
            break;
        fi
    done

    spdk_rpc.py bdev_nvme_attach_controller -b nvme_ubuntu -t rdma -a 172.3.99.200 -f ipv4 -s 4420 -n nqn.2025-01.baidu.boot:ubuntu27
    rst=$?

    if [ $rst -ne 0 ]; then
        echo "failed to attach ubuntu controller, exit"
        exit
    fi
    sleep 5
}

remote_detach_disk()
{
    detach_count=0
    spdk_rpc.py bdev_nvme_detach_controller nvme_ubuntu

    while [ true ]
    do
        detach_rst=`/root/ssh_cmd.py bash /root/nvmf/stop_used_ubuntu27.sh`
        echo $detach_rst | grep 'nqn.2014-08.org.nvmexpress.discovery' > /dev/null 2>&1
        rst=$?

        if [ $rst -ne 0 ]; then
            detach_count=$((detach_count+1))
            if [ $detach_count -gt 10 ]; then
                echo "remote failed to detach ubuntu img"
                exit
            fi
            continue
        else
            break
        fi
    done

    echo $detach_rst | grep 'nqn.2025-01.baidu.boot:ubuntu27' > /dev/null 2>&1
    rst=$?

    if [ $rst -eq 0 ]; then
        echo "failed to detach ubuntu controller, exit"
        exit
    fi
}

spdk_rpc.py bdev_nvme_attach_controller -b nvme_rocky8 -t rdma -a 172.3.99.200 -f ipv4 -s 4420 -n nqn.2025-01.baidu.boot:rocky8
snap_rpc.py virtio_blk_controller_create --pf_id 0 --dbg_bdev_type null --bdev none --num_queues 8 --seg_max 16 --size_max 65536 --ctrl VblkCtrl1
remote_attach_disk

while [ true ]
do
    round_start_time=$(date +%s)

    snap_rpc.py virtio_blk_controller_bdev_detach --ctrl VblkCtrl1
    remote_detach_disk

    snap_rpc.py virtio_blk_controller_bdev_attach --ctrl VblkCtrl1 --dbg_bdev_type null --bdev none
    ipmitool -I lanplus -H clx-virgo-027-ilo.mtl.labs.mlnx -U root -P 3tango11 chassis power reset
    sleep 60
    
    snap_rpc.py virtio_blk_controller_bdev_detach --ctrl VblkCtrl1
    snap_rpc.py virtio_blk_controller_bdev_attach --ctrl VblkCtrl1 --bdev nvme_rocky8n1
    ipmitool -I lanplus -H clx-virgo-027-ilo.mtl.labs.mlnx -U root -P 3tango11 chassis power reset
    
    #Must be able to login into OSB
    echo "Waiting for OSB BOOTUP"
    wait_for_os_bootup
    rst=$?
    if [ $rst -ne 0 ]; then
        echo "count: $count, OSB can't bootup"
        exit 1
    else
        echo "count: $count, OSB bootup"
    fi

    #OSB halt
    ssh -o ConnectTimeout=10 root@clx-virgo-027 'shutdown --halt now'
    sleep 1
    #We can't execut "power soft" or "shutdown"
    #ipmitool -I lanplus -H clx-virgo-027-ilo.mtl.labs.mlnx -U root -P 3tango11 chassis power soft
    #ssh -o ConnectTimeout=10 root@clx-virgo-027 'shutdown'

    remote_attach_disk
    snap_rpc.py virtio_blk_controller_bdev_detach --ctrl VblkCtrl1
    snap_rpc.py virtio_blk_controller_bdev_attach --ctrl VblkCtrl1 --dbg_bdev_type null --bdev none
    snap_rpc.py virtio_blk_controller_bdev_detach --ctrl VblkCtrl1
    snap_rpc.py virtio_blk_controller_bdev_attach --ctrl VblkCtrl1 --bdev nvme_ubuntun1
    ipmitool -I lanplus -H clx-virgo-027-ilo.mtl.labs.mlnx -U root -P 3tango11 chassis power reset
    
    #Must be able to login into OSA successfully, the disk maybe detached at any time
    echo "Waiting for OSA BOOTUP"
    wait_for_os_bootup
    rst=$?
    if [ $rst -ne 0 ]; then
        echo "count: $count, OSA can't bootup"
        exit 1
    else
        echo "count: $count, OSA bootup"
    fi

    round_end_time=$(date +%s)
    round_run_time=$((round_end_time - round_start_time))

    count=$((count+1))
    echo "count: $count, time: $round_run_time, another round of test"

done
