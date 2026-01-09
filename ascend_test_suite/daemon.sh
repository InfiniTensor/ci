#!/usr/bin/env bash
set -m

cleanup() {
    trap - SIGINT SIGTERM SIGHUP SIGPIPE
    docker stop --time 60 lmg_test
    # docker kill --signal=SIGTERM lmg_test
    # docker kill -s TERM lmg_test
    exit 130
}

trap cleanup SIGINT SIGTERM SIGHUP SIGPIPE

test_type=$1
engine=$2
model_list=$3
CI_job_id=$4
version=$5

docker run --name="CI_test_job_${CI_job_id}" -v /home/s_limingge/.npu_locks:/home/s_limingge/.npu_locks -v /var/run/docker.sock:/var/run/docker.sock auto-test:latest $test_type $engine $model_list $CI_job_id $version &
CHILD_PID=$!

echo -n "Running"
while kill -0 $CHILD_PID 2>/dev/null; do
    # echo -ne "\r\033[KRunning..."
    echo -n "."
    sleep 1
done
