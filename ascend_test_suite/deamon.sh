#!/usr/bin/env bash
set -m

cleanup() {
    touch ci_test.txt
    trap - SIGINT SIGTERM SIGHUP SIGPIPE
    kill -SIGTERM -$CHILD_PID
    exit 130
}

trap cleanup SIGINT SIGTERM SIGHUP SIGPIPE

./ascend_resource_monitor.sh $@ &
CHILD_PID=$!

while kill -0 $CHILD_PID 2>/dev/null; do
    echo "Running..."
    sleep 1
done
