#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2023 Liu, Changcheng <changcheng.liu@aliyun.com>

cd /sys/kernel/debug/tracing

echo 0 > tracing_on

echo > trace
echo > set_ftrace_filter
echo > set_graph_function
echo > set_ftrace_notrace
echo function_graph > current_tracer
echo 0 > options/func_stack_trace

echo 32768 > /sys/kernel/debug/tracing/buffer_size_kb
echo 3 > max_graph_depth
echo devx_obj_cleanup > set_graph_function

echo _raw_spin_lock_irqsave > set_ftrace_notrace
echo _raw_spin_unlock_irqrestore >> set_ftrace_notrace
echo _raw_spin_lock >> set_ftrace_notrace
echo _raw_spin_lock >> set_ftrace_notrace
echo _raw_spin_unlock >> set_ftrace_notrace
echo kfree >> set_ftrace_notrace
echo call_rcu >> set_ftrace_notrace
echo __slab_free >> set_ftrace_notrace
echo res_to_dev >> set_ftrace_notrace
echo __rcu_read_lock >> set_ftrace_notrace
echo __rcu_read_unlock >> set_ftrace_notrace
echo down_write >> set_ftrace_notrace
echo up_write >> set_ftrace_notrace
echo uverbs_uobject_free >> set_ftrace_notrace
echo put_device >> set_ftrace_notrace
echo mutex_lock >> set_ftrace_notrace
echo mutex_unlock >> set_ftrace_notrace
echo kvfree_call_rcu >> set_ftrace_notrace
echo __srcu_read_lock >> set_ftrace_notrace
echo __srcu_read_unlock >> set_ftrace_notrace
echo ib_rdmacg_uncharge >> set_ftrace_notrace
echo rdmacg_uncharge >> set_ftrace_notrace
echo rcu_segcblist_enqueue >> set_ftrace_notrace
echo mmap_obj_cleanup >> set_ftrace_notrace
echo rdma_user_mmap_entry_remove >> set_ftrace_notrace
echo _raw_spin_lock_irq  >> set_ftrace_notrace
echo _raw_spin_unlock_irq >> set_ftrace_notrace
echo __wake_up >> set_ftrace_notrace
echo rdmacg_uncharge_hierarchy >> set_ftrace_notrace

echo do_debug_exception >> set_ftrace_notrace

echo funcgraph-abstime > trace_options
echo funcgraph-proc >> trace_options

echo 1 > tracing_on
