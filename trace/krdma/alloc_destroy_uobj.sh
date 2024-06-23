#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2023 Liu, Changcheng <changcheng.liu@aliyun.com>

#Note:
# 1. run this script before running application. Ignore it reports error at line 28 & 33 & 38 if the events have been created
# 2. run application
# 3. kill application until it exits
# 4. cat /sys/kernel/debug/tracing/trace > aid_uobj.log
# 5. sed -n -e 's/.* aid=\(.*\)/\1/p' aid_uobj | sort -d | uniq > aid
# 6. sed -n -e 's/.* uobj=\(.*\)/\1/p' aid_uobj | sort -d | uniq > uobj

cd /sys/kernel/debug/tracing

echo 0 > tracing_on

echo > trace
echo > set_ftrace_filter
echo > set_graph_function
echo > set_ftrace_notrace
echo nop > current_tracer
echo 0 > options/func_stack_trace

echo 16384 > /sys/kernel/debug/tracing/buffer_size_kb

#https://github.com/torvalds/linux/blob/v6.10-rc5/drivers/infiniband/core/rdma_core.c#L453
#static struct ib_uobject * alloc_begin_fd_uobject(const struct uverbs_api_object *obj,
echo 'r:rf/u ib_uverbs:alloc_begin_fd_uobject aid=$retval:x64' >> kprobe_events
echo 1 > events/rf/u/enable

#https://github.com/torvalds/linux/blob/v6.10-rc5/drivers/infiniband/core/rdma_core.c#L424
#static struct ib_uobject * alloc_begin_idr_uobject(const struct uverbs_api_object *obj,
echo 'r:ri/u ib_uverbs:alloc_begin_idr_uobject aid=$retval:x64' >> kprobe_events
echo 1 > events/ri/u/enable

#https://github.com/torvalds/linux/blob/v6.10-rc5/drivers/infiniband/core/rdma_core.c#L122
#static int uverbs_destroy_uobject(struct ib_uobject *uobj,
echo 'p:dst/u ib_uverbs:uverbs_destroy_uobject uobj=$arg1:x64' >> kprobe_events
echo 1 > events/dst/u/enable

echo 1 > tracing_on
