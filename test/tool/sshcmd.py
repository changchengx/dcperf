#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2023 Liu, Changcheng <changcheng.liu@aliyun.com>

import paramiko
import sys
import os


def ssh_cmd(commands, hostname, username, port="22"):
    ssh_client = paramiko.SSHClient()
    ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy)
    try:
        ssh_client.connect(hostname=hostname, username=username, port=port)
    except Exception as e:
        print('connest to %s failed'.format(hostname))
        print(e)
        sys.exit()
    for cmd in commands:
        print(f'$ {cmd}')
        stdin, stdout, stderr = ssh_client.exec_command(cmd)
        print(stdout.read().decode("utf-8"))
        print(stderr.read().decode("utf-8"))
    ssh_client.close()


if __name__ == '__main__':
    default_servers = [
        "127.0.0.1",
    ]
    servers = os.environ.get("servers")
    if servers:
        servers = servers.split(',')
    else:
        servers = default_servers
    username = ''
    with os.popen('whoami') as f:
        username = f.readline().strip()
    if len(sys.argv) <= 1:
        commands = [
            'pwd',
            'ls -lh /tmp/'
        ]
    else:
        commands = sys.argv[1:]
    for hostname in servers:
        print('{:-^48s}'.format(hostname))
        print('user: {}'.format(username))
        ssh_cmd(commands, hostname, username)
        print('{:-^48s}'.format(hostname))
