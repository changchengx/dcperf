#!/bin/bash
cd /sys/kernel/debug/tracing
# Clear filters and trace buffer
echo > set_ftrace_filter
echo > set_ftrace_notrace
echo 0 > tracing_on
echo > trace
# Set tracer
echo function > current_tracer
# Start the command in background and get its PID
pid=$$
# Restrict trace to this PID
echo $pid > set_ftrace_pid
echo 1 > tracing_on
echo 1 > /sys/bus/pci/devices/0000:3d:00.2/reset
echo 0 > tracing_on
# Check trace output
cat trace > /tmp/log
