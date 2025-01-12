#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2025 Liu, Changcheng <changcheng.liu@aliyun.com>

prev_ts=`date +%s`
while [ true ]
do
    s1=$(lsblk /dev/$1 | awk 'NR == 2' | awk '{print $4}')
    curr_ts=`date +%s`
    if [ "$s1" == "1G" ]
    then
        sudo fio --cpus_allowed=1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31,33,35,37,39,41,43,45,47,49,51,53,55,57,59,61,63 --filename=/dev/$1 --ioengine=libaio --rw=randwrite --bs=4k --direct=0 --numjobs=32 --group_reporting --iodepth=256 --name=rrw --time_based --runtime=180

        prev_ts=`date +%s`
    elif [ $((curr_ts - prev_ts)) -ge 200 ]
    then
        exit
    fi
done
