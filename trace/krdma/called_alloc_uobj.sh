#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2023 Liu, Changcheng <changcheng.liu@aliyun.com>

cd /sys/kernel/debug/tracing

echo 0 > tracing_on

echo > trace
echo > set_ftrace_filter
echo > set_graph_function
echo > set_ftrace_notrace
echo nop > current_tracer
echo 0 > options/func_stack_trace

echo 16384 > /sys/kernel/debug/tracing/buffer_size_kb

echo alloc_uobj > set_ftrace_filter
echo uverbs_destroy_uobject >> set_ftrace_filter

echo function > current_tracer
echo 1 > options/func_stack_trace

echo 1 > tracing_on
