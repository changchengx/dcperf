#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2023 Liu, Changcheng <changcheng.liu@aliyun.com>

count=0

init_time=`date`
start_time=$(date +%s)

while [ true ]
do
    date

    end_time=$(date +%s)
    diff_time=$((end_time - start_time))
    if [ $diff_time -gt 1200 ]; then
        echo "count: $count"
        echo "time: $init_time, " `date`
        break
    fi

    sleep 5
    ssh -o ConnectTimeout=10 root@clx-virgo-026 'sleep 10'
    rst=$?

    if [ $rst -eq 0 ]; then
        end_time=$(date +%s)
        ssh -o ConnectTimeout=10 root@clx-virgo-026 'reboot'
        count=$((count+1))
        echo "count: $count, " $((end_time - start_time))
        start_time=$(date +%s)
    else
         continue
    fi
done
