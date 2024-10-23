#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2024 Liu, Changcheng <changcheng.liu@aliyun.com>

#
#debug_mask: 1 = dump cmd data, 2 = dump cmd exec time, 3 = both. Default=0 (uint)
#

if [ $(id -u) -ne 0 ]; then
echo "need root permission"
exit
fi

dbg_fs="/sys/kernel/debug"
mlx_dbg_dir="$dbg_fs/mlx5"

if ! [[ -d $mlx_dbg_dir ]]; then
        mount -t debugfs none $dbg_fs
fi

if ! [[ -d $mlx_dbg_dir ]]; then
        echo "unable to mount debugfs"
fi

if [ "$1" != "on" ]; then

echo 'func dump_command -p' > $dbg_fs/dynamic_debug/control
echo 'func dump_buf -p' > $dbg_fs/dynamic_debug/control
echo 0 > /sys/module/mlx5_core/parameters/debug_mask
echo "off trace mlx5 cmd"

else

echo 1 > /sys/module/mlx5_core/parameters/debug_mask
echo 'func dump_command +p' > $dbg_fs/dynamic_debug/control
echo 'func dump_buf +p' > $dbg_fs/dynamic_debug/control
echo "on trace mlx5 cmd"

fi
