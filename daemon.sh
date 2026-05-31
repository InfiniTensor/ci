#!/usr/bin/env bash
set -m

cleanup() {
    trap - SIGINT SIGTERM SIGHUP SIGPIPE
    echo "Stopping CI test job..."
    docker stop --timeout 60 CI_test_job_${platform}_${test_type}_${test_param// /_}_${CI_job_id}
    docker stop --time 60 CI_test_job_${platform}_${test_type}_${test_param// /_}_${CI_job_id}
    # docker kill --signal=SIGTERM CI_test_job_${CI_job_id}
    # docker kill -s TERM CI_test_job_${CI_job_id}
    # rm -rf $curr_dir
    exit 130
}

trap cleanup SIGINT SIGTERM SIGHUP SIGPIPE

platform=$1
test_type=$2
engine=$3
model_list=$4
docker_args="$5"
CI_job_id=$6
test_param="$7"
version=$8

curr_dir=$(pwd)

container_script='
set -euo pipefail

mkdir -p ~/.ssh
if [ -d /CI_Host_SSH ]; then
    cp -LR /CI_Host_SSH/. ~/.ssh/
fi
chmod 700 ~/.ssh
find ~/.ssh -type f -name "id_*" -exec chmod 600 {} +
cat > ~/.ssh/config <<EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
chmod 600 ~/.ssh/config

if [ -d /CI_Workspace/ci_autotest ]; then
    git config --global --add safe.directory /CI_Workspace/ci_autotest
fi

exec /CI_Workspace/entrypoint.sh "$@"
'

if [ $platform == "Hygon" ]; then
    CI_Workspace="/data-aisoft/limingge/CI_Workspace_for_InfiniLM"
else
    CI_Workspace="/data/shared/limingge/CI_Workspace_for_InfiniLM"
fi

docker run --rm \
    --name="CI_test_job_${platform}_${test_type}_${test_param// /_}_${CI_job_id}" \
    --ipc=host \
    --net=host \
    --privileged \
    -v /home/zkjh/.npu_locks:/home/zkjh/.npu_locks \
    -v ${CI_Workspace}:/CI_Workspace \
    -v /data-aisoft/artifacts:/artifacts \
    -v "${HOME}/.ssh:/CI_Host_SSH:ro" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --entrypoint /bin/bash \
    auto-test:latest \
    -lc "${container_script}" \
    bash \
    "$platform" \
    "$test_type" \
    "$engine" \
    "$model_list" \
    "$docker_args" \
    "$CI_job_id" \
    "$test_param" \
    "$version" &
CHILD_PID=$!

echo -n "Running"
while kill -0 $CHILD_PID 2>/dev/null; do
    # echo -ne "\r\033[KRunning..."
    echo -n "."
    sleep 1
done

wait $CHILD_PID
EXIT_CODE=$?

# rm -rf $curr_dir

exit $EXIT_CODE
