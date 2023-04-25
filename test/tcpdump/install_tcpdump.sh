#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2023 Liu, Changcheng <changcheng.liu@aliyun.com>

tool_base_dir=/.autodirect/swgwork/$(whoami)/wireshark/tool
mkdir -p $tool_base_dir

pushd $PWD

cd $tool_base_dir

rm -rf libpcap
git clone https://github.com/the-tcpdump-group/libpcap.git
cd libpcap
git checkout tags/libpcap-1.10.3 -b v1.10.3
./configure --enable-rdma --with-dpdk=no --prefix=$PWD/install
make
make install
cd ..

rm -rf tcpdump
git clone https://github.com/the-tcpdump-group/tcpdump.git
cd tcpdump
git checkout tags/tcpdump-4.99.3 -b v4.99.3
LDFLAGS=-L${tool_base_dir}/libpcap/install/lib ./configure --prefix=$PWD/install
make
make install
cd ..

popd

grep 'alias sudo' $HOME/.bashrc -q
if [ $? -eq 1 ]; then
echo "alias sudo='sudo '" >> $HOME/.bashrc
fi

grep 'alias tcpdump' $HOME/.bashrc -q
if [ $? -eq 1 ]; then
echo "alias tcpdump='LD_LIBRARY_PATH=$tool_base_dir/libpcap/install/lib:$LD_LIBRARY_PATH $tool_base_dir/tcpdump/install/bin/tcpdump'" >> $HOME/.bashrc
fi
