#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2023 Liu, Changcheng <changcheng.liu@aliyun.com>

export UCX_SOCKADDR_TLS_PRIORITY=rdmacm
export UCX_ADDRESS_VERSION=v2
export UCX_TLS=dc_x
export UCX_NET_DEVICES=mlx5_bond_0:1

sudo sysctl net.ipv4.ip_local_port_range="1024 65535"
sudo sysctl net.rdma_ucm.max_backlog=1073741823
sudo sysctl vm.max_map_count=1073741823

arg_array=($*)
arg_len=${#arg_array[@]}
for idx in `seq 0 $((arg_len - 1))`
do
    port=${arg_array[$idx]}
    ./install/bin/io_demo -d 32 -n inf -t inf -p $port 2>&1 | tee /tmp/server$port &
done
