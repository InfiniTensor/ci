#!/usr/bin/env bash
set -m

cleanup() {
    trap - SIGINT SIGTERM SIGHUP SIGPIPE
    echo "Stopping CI test job..."
    docker stop --timeout 60 "CI_test_job_${platform}_${test_type}_${CI_job_id}"
    docker stop --time 60 "CI_test_job_${platform}_${test_type}_${CI_job_id}"
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

if [ "$test_type" == "Performance" ]; then
    test_param=$7
    version=$8
else
    test_param=""
    version=$7
fi

curr_dir=$(pwd)
ci_ref=${CI_REF:-master}
platform_suite=$(echo "$platform" | tr '[:upper:]' '[:lower:]')
source_ci_dir=${CI_SOURCE_DIR:-}
source_mount_args=()

if [ -n "$source_ci_dir" ] && [ -d "${source_ci_dir}/.ci" ]; then
    source_mount_args=(-v "${source_ci_dir}/.ci:/CI_Source/ci:ro")
fi

echo "Using CI ref: ${ci_ref}"
echo "Using scheduler suite: ${platform_suite}_test_suite"
if [ ${#source_mount_args[@]} -gt 0 ]; then
    echo "Using CI source: ${source_ci_dir}/.ci"
fi

container_script='
set -euo pipefail

export https_proxy=http://localhost:9990
export http_proxy=http://localhost:9990

mkdir -p ~/.ssh
cat > ~/.ssh/config <<EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

if [ -d /CI_Source/ci/third-party/scheduler ]; then
    worktree="/CI_Workspace/ci_autotest_${6}_${CI_PLATFORM_SUITE}_${2}_$$"
    rm -rf "${worktree}"
    cp -a /CI_Source/ci "${worktree}"
    cd "${worktree}"
else
    cd /CI_Workspace
    if [ ! -d ci_autotest/.git ]; then
        git clone git@github.com:InfiniTensor/ci.git ci_autotest
    fi

    cd ci_autotest
    if git fetch origin "${CI_REF}"; then
        git checkout -f --detach FETCH_HEAD
    else
        echo "Warning: failed to fetch ${CI_REF}; using existing ci_autotest checkout"
    fi
fi

cd "third-party/scheduler/${CI_PLATFORM_SUITE}_test_suite"
if [ "$2" = "Performance" ]; then
    version="${8:-}"
else
    version="${7:-}"
fi

mkdir -p "${version}"
cp latest/model_list.yml "${version}"

if [ "$2" = "Performance" ]; then
    exec "./${CI_PLATFORM_SUITE}_resource_monitor.sh" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
else
    exec "./${CI_PLATFORM_SUITE}_resource_monitor.sh" "$2" "$3" "$4" "$5" "$6" "$7"
fi
'

docker_args_list=(
    --rm
    --name="CI_test_job_${platform}_${test_type}_${CI_job_id}"
    --ipc=host
    --net=host
    --privileged
    -v /home/zkjh/.npu_locks:/home/zkjh/.npu_locks
    -v /data/shared/limingge/CI_Workspace:/CI_Workspace
    -v /data-aisoft/artifacts:/artifacts
    -v "${HOME}/.ssh:/root/.ssh"
    -v /var/run/docker.sock:/var/run/docker.sock
    "${source_mount_args[@]}"
    -e "CI_REF=${ci_ref}"
    -e "CI_PLATFORM_SUITE=${platform_suite}"
    --entrypoint /bin/bash
    auto-test:latest
    -lc
    "${container_script}"
    bash
    "$platform"
    "$test_type"
    "$engine"
    "$model_list"
    "$docker_args"
    "$CI_job_id"
)

if [ "$test_type" == "Performance" ]; then
    docker_args_list+=("$test_param" "$version")
else
    docker_args_list+=("$version")
fi

docker run "${docker_args_list[@]}" &
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
