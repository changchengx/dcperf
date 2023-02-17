#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2023 Liu, Changcheng <changcheng.liu@aliyun.com>

rm -rf /tmp/client*.log

for i in `seq 1 32`
do
    ./client.sh 2010 9876 9867 9786 9768 9687 9678 8976 8967 8796 8769 8697 8679 7986 7968 7896 7869 7698 7689 6987 6978 6897 6879 6798 6789 19876 19867 19786 19768 19687 19678 18976 18967 > /tmp/client${i}.log 2>&1 &

    sleep_count=0
    while true
    do
        active=0
        grep "active" /tmp/client${i}.log -q
        rst=$?

        if [ $rst -eq 0 ]; then
            active=`grep 'active' /tmp/client${i}.log  | tail -1 | sed -n -e 's/.*active:\(.*\)\/.* buffers.*/\1/p'`
            if [ $active -eq 64320 ]; then
                echo "##############${i}  ${sleep_count}:${active}###############"
                break;
            fi
        fi

        sleep_count=$((sleep_count+1))
        echo "##############${i}  ${sleep_count}:${active}###############"
        sleep 10
    done

    sleep 10
done
