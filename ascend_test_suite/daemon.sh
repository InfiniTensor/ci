#!/usr/bin/env bash
set -m

cleanup() {
    trap - SIGINT SIGTERM SIGHUP SIGPIPE
    docker stop --time 60 CI_test_job_${platform}_${test_type}_${CI_job_id}
    # docker kill --signal=SIGTERM CI_test_job_${CI_job_id}
    # docker kill -s TERM CI_test_job_${CI_job_id}
    rm -rf $curr_dir
    exit 130
}

trap cleanup SIGINT SIGTERM SIGHUP SIGPIPE

platform=$1
test_type=$2
engine=$3
model_list=$4
CI_job_id=$5
version=$6

curr_dir=$(pwd)

docker run --rm --name="CI_test_job_${platform}_${test_type}_${CI_job_id}" --ipc=host --net=host --privileged -v /home/zkjh/.npu_locks:/home/zkjh/.npu_locks -v /home/zkjh/CI_Workspace:/CI_Workspace -v /var/run/docker.sock:/var/run/docker.sock auto-test:latest $platform $test_type $engine $model_list $CI_job_id $version &
CHILD_PID=$!

echo -n "Running"
while kill -0 $CHILD_PID 2>/dev/null; do
    # echo -ne "\r\033[KRunning..."
    echo -n "."
    sleep 1
done

wait $CHILD_PID
EXIT_CODE=$?

rm -rf $curr_dir

exit $EXIT_CODE
