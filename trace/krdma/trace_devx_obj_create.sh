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
echo mlx5_ib_handler_MLX5_IB_METHOD_DEVX_OBJ_CREATE > set_graph_function

echo _raw_spin_lock_irqsave > set_ftrace_notrace
echo _raw_spin_unlock_irqrestore >> set_ftrace_notrace
echo _raw_spin_lock_irq  >> set_ftrace_notrace
echo _raw_spin_unlock_irq >> set_ftrace_notrace
echo _raw_spin_lock >> set_ftrace_notrace
echo _raw_spin_unlock >> set_ftrace_notrace
echo __rcu_read_lock >> set_ftrace_notrace
echo __rcu_read_unlock >> set_ftrace_notrace
echo __check_object_size >> set_ftrace_notrace
echo preempt_schedule_irq >> set_ftrace_notrace
echo pick_next_task_fair >> set_ftrace_notrace
echo psi_task_switch >> set_ftrace_notrace
echo check_and_switch_context >> set_ftrace_notrace
echo fpsimd_thread_switch >> set_ftrace_notrace
echo should_failslab >> set_ftrace_notrace
echo check_stack_object >> set_ftrace_notrace

echo mlx5_command_str >> set_ftrace_notrace
echo uverbs_copy_to >> set_ftrace_notrace
echo _uverbs_alloc >> set_ftrace_notrace
echo in_to_opcode >> set_ftrace_notrace
echo cmd_status_err >> set_ftrace_notrace
echo mlx5_eqn2comp_eq >> set_ftrace_notrace
echo mlx5_eq_add_cq >> set_ftrace_notrace
echo mlx5_get_async_eq >> set_ftrace_notrace
echo mlx5_eq_add_cq >> set_ftrace_notrace
echo mlx5_debug_cq_add >> set_ftrace_notrace

echo __init_swait_queue_head >> set_ftrace_notrace
echo kmem_cache_alloc_trace >> set_ftrace_notrace
echo do_debug_exception >> set_ftrace_notrace
echo arm64_preempt_schedule_irq >> set_ftrace_notrace

echo funcgraph-abstime > trace_options
echo funcgraph-proc >> trace_options

echo 1 > tracing_on
