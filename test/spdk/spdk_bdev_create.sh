#!/bin/bash

sudo scripts/rpc.py iobuf_set_options --small_pool_count 65535
sleep 5
sudo scripts/rpc.py iobuf_set_options --large_pool_count 8191
sleep 5
sudo scripts/rpc.py framework_start_init
sudo scripts/rpc.py framework_wait_init
sleep 2

sudo scripts/rpc.py nvmf_create_transport -t tcp -u 8192 -n 8192

sudo scripts/rpc.py bdev_malloc_create -b ram0 128 512
sudo scripts/rpc.py bdev_malloc_create -b ram1 128 512
sudo scripts/rpc.py bdev_malloc_create -b ram2 128 512
sudo scripts/rpc.py bdev_malloc_create -b ram3 128 512
sudo scripts/rpc.py bdev_malloc_create -b ram4 128 512
sudo scripts/rpc.py bdev_malloc_create -b ram5 128 512
sudo scripts/rpc.py bdev_malloc_create -b ram6 128 512
sudo scripts/rpc.py bdev_malloc_create -b ram7 128 512
sudo scripts/rpc.py bdev_malloc_create -b ram8 128 512
sudo scripts/rpc.py bdev_malloc_create -b ram9 128 512
sudo scripts/rpc.py bdev_malloc_create -b ram10 128 512
sudo scripts/rpc.py bdev_malloc_create -b ram11 128 512
sudo scripts/rpc.py bdev_malloc_create -b ram12 128 512
sudo scripts/rpc.py bdev_malloc_create -b ram13 128 512

sudo scripts/rpc.py nvmf_create_subsystem nqn.2023-12.io.ram0:0 -a -s RAM0 -d ControllerRAM0
sudo scripts/rpc.py nvmf_subsystem_add_ns nqn.2023-12.io.ram0:0 ram0
sudo scripts/rpc.py nvmf_subsystem_add_listener nqn.2023-12.io.ram0:0 -t tcp -a 192.168.30.20 -s 59152

sudo scripts/rpc.py nvmf_create_subsystem nqn.2023-12.io.ram1:1 -a -s RAM1 -d ControllerRAM1
sudo scripts/rpc.py nvmf_subsystem_add_ns nqn.2023-12.io.ram1:1 ram1
sudo scripts/rpc.py nvmf_subsystem_add_listener nqn.2023-12.io.ram1:1 -t tcp -a 192.168.30.20 -s 59154

sudo scripts/rpc.py nvmf_create_subsystem nqn.2023-12.io.ram2:2 -a -s RAM2 -d ControllerRAM2
sudo scripts/rpc.py nvmf_subsystem_add_ns nqn.2023-12.io.ram2:2 ram2
sudo scripts/rpc.py nvmf_subsystem_add_listener nqn.2023-12.io.ram2:2 -t tcp -a 192.168.30.20 -s 59156

sudo scripts/rpc.py nvmf_create_subsystem nqn.2023-12.io.ram3:3 -a -s RAM3 -d ControllerRAM3
sudo scripts/rpc.py nvmf_subsystem_add_ns nqn.2023-12.io.ram3:3 ram3
sudo scripts/rpc.py nvmf_subsystem_add_listener nqn.2023-12.io.ram3:3 -t tcp -a 192.168.30.20 -s 59158

sudo scripts/rpc.py nvmf_create_subsystem nqn.2023-12.io.ram4:4 -a -s RAM4 -d ControllerRAM4
sudo scripts/rpc.py nvmf_subsystem_add_ns nqn.2023-12.io.ram4:4 ram4
sudo scripts/rpc.py nvmf_subsystem_add_listener nqn.2023-12.io.ram4:4 -t tcp -a 192.168.30.20 -s 59150

sudo scripts/rpc.py nvmf_create_subsystem nqn.2023-12.io.ram5:5 -a -s RAM5 -d ControllerRAM5
sudo scripts/rpc.py nvmf_subsystem_add_ns nqn.2023-12.io.ram5:5 ram5
sudo scripts/rpc.py nvmf_subsystem_add_listener nqn.2023-12.io.ram5:5 -t tcp -a 192.168.30.20 -s 59151

sudo scripts/rpc.py nvmf_create_subsystem nqn.2023-12.io.ram6:6 -a -s RAM6 -d ControllerRAM6
sudo scripts/rpc.py nvmf_subsystem_add_ns nqn.2023-12.io.ram6:6 ram6
sudo scripts/rpc.py nvmf_subsystem_add_listener nqn.2023-12.io.ram6:6 -t tcp -a 192.168.30.20 -s 59153

sudo scripts/rpc.py nvmf_create_subsystem nqn.2023-12.io.ram7:7 -a -s RAM7 -d ControllerRAM7
sudo scripts/rpc.py nvmf_subsystem_add_ns nqn.2023-12.io.ram7:7 ram7
sudo scripts/rpc.py nvmf_subsystem_add_listener nqn.2023-12.io.ram7:7 -t tcp -a 192.168.30.20 -s 59155

sudo scripts/rpc.py nvmf_create_subsystem nqn.2023-12.io.ram8:8 -a -s RAM8 -d ControllerRAM8
sudo scripts/rpc.py nvmf_subsystem_add_ns nqn.2023-12.io.ram8:8 ram8
sudo scripts/rpc.py nvmf_subsystem_add_listener nqn.2023-12.io.ram8:8 -t tcp -a 192.168.30.20 -s 59157

sudo scripts/rpc.py nvmf_create_subsystem nqn.2023-12.io.ram9:9 -a -s RAM9 -d ControllerRAM9
sudo scripts/rpc.py nvmf_subsystem_add_ns nqn.2023-12.io.ram9:9 ram9
sudo scripts/rpc.py nvmf_subsystem_add_listener nqn.2023-12.io.ram9:9 -t tcp -a 192.168.30.20 -s 59159

sudo scripts/rpc.py nvmf_create_subsystem nqn.2023-12.io.ram10:10 -a -s RAM10 -d ControllerRAM10
sudo scripts/rpc.py nvmf_subsystem_add_ns nqn.2023-12.io.ram10:10 ram10
sudo scripts/rpc.py nvmf_subsystem_add_listener nqn.2023-12.io.ram10:10 -t tcp -a 192.168.30.20 -s 59162

sudo scripts/rpc.py nvmf_create_subsystem nqn.2023-12.io.ram11:11 -a -s RAM11 -d ControllerRAM11
sudo scripts/rpc.py nvmf_subsystem_add_ns nqn.2023-12.io.ram11:11 ram11
sudo scripts/rpc.py nvmf_subsystem_add_listener nqn.2023-12.io.ram11:11 -t tcp -a 192.168.30.20 -s 59163

sudo scripts/rpc.py nvmf_create_subsystem nqn.2023-12.io.ram12:12 -a -s RAM12 -d ControllerRAM12
sudo scripts/rpc.py nvmf_subsystem_add_ns nqn.2023-12.io.ram12:12 ram12
sudo scripts/rpc.py nvmf_subsystem_add_listener nqn.2023-12.io.ram12:12 -t tcp -a 192.168.30.20 -s 59164

sudo scripts/rpc.py nvmf_create_subsystem nqn.2023-12.io.ram13:13 -a -s RAM13 -d ControllerRAM13
sudo scripts/rpc.py nvmf_subsystem_add_ns nqn.2023-12.io.ram13:13 ram13
sudo scripts/rpc.py nvmf_subsystem_add_listener nqn.2023-12.io.ram13:13 -t tcp -a 192.168.30.20 -s 59165
