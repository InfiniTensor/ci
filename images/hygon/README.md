# Hygon development image

Validate InfiniLM with InfiniCore's InfiniRT, InfiniOps, and InfiniCCL components
on Hygon DCUs with DTK 26.04. Source, weights, and build output stay on the host.

The default base image is
`harbor.sourcefind.cn:5443/dcu/admin/base/custom:sglang-deepseek-v4-dev-zkjh`.
The development image preserves its Hygon PyTorch and FlashAttention builds and
pins the additional Python, Xmake, and Xmake-recipe versions.

## Prepare source checkouts

Use existing checkouts under `$HOME/codes` (or set `SOURCE_ROOT` to their parent
directory). The build uses InfiniCore's submodules, not separate top-level
InfiniRT, InfiniOps, or InfiniCCL checkouts.

| Checkout under `SOURCE_ROOT` | Ref |
| --- | --- |
| `InfiniCore` | `refactor/component-manifest` |
| `InfiniCore/submodules/InfiniRT` | `master` |
| `InfiniCore/submodules/InfiniOps` | `master` |
| `InfiniCore/submodules/InfiniCCL` | `master` |
| `InfiniLM` | `refactor/adopt-modern-infini-stack` |

If these refs and Core's component gitlinks are already prepared, skip to
[Build and start](#build-and-start). Otherwise, run on the host:

```bash
SOURCE_ROOT="${SOURCE_ROOT:-$HOME/codes}"

for checkout in InfiniCore InfiniLM; do
  repo="$SOURCE_ROOT/$checkout"
  test -d "$repo/.git" || {
    echo "Missing checkout: $repo" >&2
    exit 1
  }
  test -z "$(git -C "$repo" status --porcelain)" || {
    echo "Checkout is not clean: $repo" >&2
    exit 1
  }
done

checkout_ref() {
  local checkout="$1"
  local repository="$2"
  local ref="$3"
  git -C "$checkout" fetch "$repository" "$ref"
  git -C "$checkout" switch --detach FETCH_HEAD
  git -C "$checkout" submodule update --init --recursive
}

checkout_ref "$SOURCE_ROOT/InfiniCore" \
  https://github.com/InfiniTensor/InfiniCore.git \
  refactor/component-manifest
checkout_ref "$SOURCE_ROOT/InfiniLM" \
  https://github.com/InfiniTensor/InfiniLM.git \
  refactor/adopt-modern-infini-stack

for component in InfiniRT InfiniOps InfiniCCL; do
  checkout_ref "$SOURCE_ROOT/InfiniCore/submodules/$component" \
    "https://github.com/InfiniTensor/$component.git" master
done

git -C "$SOURCE_ROOT/InfiniCore" add \
  submodules/InfiniRT submodules/InfiniOps submodules/InfiniCCL
git -C "$SOURCE_ROOT/InfiniCore" \
  -c user.name='Infini integration validation' \
  -c user.email='integration@localhost' \
  commit -m 'chore: pin Hygon integration revisions'
```

This leaves existing branch tips unchanged. The local Core commit pins the
component revisions; the build checks that their worktrees match the gitlinks.

## Build and start

On the host, use this CI checkout and build the current Dockerfile. An older
image with the same tag may lack dependencies such as `janus`. Start a new
container to use the rebuilt image.

```bash
cd /path/to/ci
CI_ROOT="$PWD"
test -f "$CI_ROOT/images/hygon/infiniops_ops.json"

docker build \
  -f "$CI_ROOT/images/hygon/Dockerfile" \
  -t infinitensor/infini-dev:hygon-dtk2604 \
  "$CI_ROOT"
```

Create an isolated output directory and start the container:

```bash
SOURCE_ROOT="${SOURCE_ROOT:-$HOME/codes}"
RUN_ROOT="$(mktemp -d "$HOME/infini-hygon-run-XXXXXX")"
printf 'SOURCE_ROOT=%s\nRUN_ROOT=%s\n' "$SOURCE_ROOT" "$RUN_ROOT"

docker run --rm -it \
  --name infini-hygon-dev \
  --network host \
  --ipc host \
  --device /dev/kfd \
  --device /dev/mkfd \
  --device /dev/dri \
  --group-add video \
  --group-add render \
  --ulimit memlock=-1:-1 \
  --ulimit stack=67108864:67108864 \
  -v /opt/hyhal:/opt/hyhal:ro \
  -v /data/node28:/data/node28:ro \
  -v /home_aclsylqidf:/home_aclsylqidf:ro \
  -v "${SOURCE_ROOT:?SOURCE_ROOT is not set}:/workspace/src" \
  -v "${RUN_ROOT:?RUN_ROOT is not set}:/workspace/run" \
  -v "${CI_ROOT:?CI_ROOT is not set}:/workspace/ci:ro" \
  -e SOURCE_ROOT=/workspace/src \
  -e RUN_ROOT=/workspace/run \
  -w /workspace/src/InfiniLM \
  infinitensor/infini-dev:hygon-dtk2604 \
  bash
```

TP8 cases require eight devices. Each new `RUN_ROOT` keeps build output and
logs on the host and separates them from previous builds.

Run the remaining commands inside the container. Trust the mounted checkouts
so container root can read Git metadata owned by the host user:

```bash
for repo in \
  InfiniLM InfiniCore \
  InfiniCore/submodules/InfiniRT \
  InfiniCore/submodules/InfiniOps \
  InfiniCore/submodules/InfiniCCL
do
  git config --global --add safe.directory "$SOURCE_ROOT/$repo"
done
```

Verify the host driver, Hygon PyTorch, and Janus before building:

```bash
hy-smi
python3 - <<'PY'
import janus
import torch

print("torch:", torch.__version__)
print("device count:", torch.cuda.device_count())
print("device 0:", torch.cuda.get_device_name(0))
PY
```

## Build the stack

The operator config selects native implementation 0, ATen implementation 8
for `Fill`/`Tril`/`Triu`, and linked implementation 16 for FlashAttention.

```bash
BUILD_ROOT="$RUN_ROOT/build"
LOG_ROOT="$RUN_ROOT/logs"
mkdir -p "$BUILD_ROOT" "$LOG_ROOT"
set -o pipefail

cd "$SOURCE_ROOT/InfiniLM"
python3 scripts/build_infini_stack.py \
  --infinicore-root "$SOURCE_ROOT/InfiniCore" \
  --backend hygon \
  --hygon-arch gfx936 \
  --operator-config /workspace/ci/images/hygon/infiniops_ops.json \
  --build-root "$BUILD_ROOT/stack" \
  --jobs 16 \
  --test 2>&1 | tee "$LOG_ROOT/build-stack.log"
```

`--test` includes InfiniRT tests and a two-device InfiniCCL AllReduce smoke
test. Continue only after it succeeds:

```bash
export INFINI_ROOT="$BUILD_ROOT/stack/prefix"
export CUDA_COMPAT_LIB="$CUDA_HOME/targets/x86_64-linux/lib"
export LD_LIBRARY_PATH="$INFINI_ROOT/lib:$CUDA_COMPAT_LIB:${LD_LIBRARY_PATH:-}"

xmake f -y -c -o "$BUILD_ROOT/InfiniLM" -m release
python3 -m pip install -e . --no-build-isolation --no-deps \
  2>&1 | tee "$LOG_ROOT/build-infinilm.log"
python3 examples/bench.py --help
```

`--no-deps` uses the image's dependencies; `--help` checks the benchmark imports
before loading model weights. Continue only after both commands succeed.

## Audit the integration

Define the logging helper and model paths once for the audit and cases 1-13:

```bash
run_case() {
  local case_id="$1"
  shift
  python3 examples/bench.py --device hygon "$@" 2>&1 \
    | tee "$LOG_ROOT/${case_id}.log"
}

MODEL_8B=/data/node28/shared/models/9g_8b_thinking_llama
MODEL_70B=/home_aclsylqidf/shared/FM9G_80B_SFT_MHA
```

Run this short audit first. A failed command stops the block and leaves the
container shell open; proceed only when the whole block succeeds:

```bash
(
set -e -o pipefail
export INFINI_OPS_TRACE_CALLS=1
export INFINICORE_GRAPH_DEBUG=1

run_case flash-graph-audit \
  --model="$MODEL_8B" \
  --enable-paged-attn \
  --attn=flash-attn \
  --enable-graph \
  --batch-size=1 \
  --input-len=32 \
  --output-len=2

AUDIT_LOG="$LOG_ROOT/flash-graph-audit.log"
for operator in FlashAttnVarlenFunc FlashAttnWithKvcache; do
  grep -q "\"operator_name\": \"$operator\".*\"implementation\": 16" \
    "$AUDIT_LOG"
done
grep -q '"operator_name": "ReshapeAndCacheFlash".*"implementation": 0' \
  "$AUDIT_LOG"
grep -m1 'Using InfiniRT C++ segmented graph runtime API' "$AUDIT_LOG"
if grep -q 'Falling back to eager execution' "$AUDIT_LOG"; then
  echo 'Graph audit failed: eager fallback detected' >&2
  exit 1
fi
grep '^\[INFINI_OPS_TRACE_CALLS\]' "$AUDIT_LOG" | sort -u

ldd "$SOURCE_ROOT/InfiniLM/python/infinicore/lib/libinfinicore_runtime.so" \
  | grep -E 'libinfiniops|libinfiniccl|libinfinirt'
)
```

The checks require both linked FlashAttention providers, native KV-cache
reshaping, and the InfiniRT graph runtime without eager fallback.

## Run cases 1-13

Cases 1-4 cover 8B FlashAttention and graph mode:

```bash
case_number=1
for batch_size in 1 4 16 64; do
  run_case "case-${case_number}-8b-flash-graph" \
    --warmup \
    --model="$MODEL_8B" \
    --enable-paged-attn \
    --attn=flash-attn \
    --enable-graph \
    --input-len=32,256,4096 \
    --output-len=256,1024,2048,4096 \
    --batch-size="$batch_size"
  case_number=$((case_number + 1))
done
```

Cases 5-6 cover 8B paged graph and static attention:

```bash
run_case case-5-8b-paged-graph \
  --model="$MODEL_8B" \
  --enable-paged-attn \
  --enable-graph \
  --batch-size=32 \
  --input-len=2048 \
  --output-len=2048

run_case case-6-8b-static \
  --model="$MODEL_8B" \
  --batch-size=4 \
  --input-len=1024 \
  --output-len=1024
```

Cases 7-10 cover 70B FlashAttention and graph mode with TP8:

```bash
case_number=7
for batch_size in 1 4 16 64; do
  run_case "case-${case_number}-70b-flash-graph" \
    --warmup \
    --model="$MODEL_70B" \
    --enable-paged-attn \
    --attn=flash-attn \
    --enable-graph \
    --input-len=32,256,4096 \
    --output-len=256,1024,2048,4096 \
    --batch-size="$batch_size" \
    --tp=8
  case_number=$((case_number + 1))
done
```

Cases 11-13 cover MHA FlashAttention and the remaining 70B workloads. Case 13
keeps the shared matrix command, which enables paged attention and graph mode
despite its historical `Static` label.

```bash
run_case case-11-70b-mha-flash-graph \
  --model="$MODEL_70B" \
  --enable-paged-attn \
  --attn=flash-attn \
  --enable-graph \
  --pre-transpose \
  --tp=8 \
  --num-blocks=32

run_case case-12-70b-paged-graph \
  --model="$MODEL_70B" \
  --enable-paged-attn \
  --enable-graph \
  --batch-size=32 \
  --input-len=2048 \
  --output-len=2048 \
  --tp=8

run_case case-13-70b-paged-graph \
  --model="$MODEL_70B" \
  --enable-paged-attn \
  --enable-graph \
  --batch-size=4 \
  --input-len=1024 \
  --output-len=1024 \
  --tp=8
```

## Reference Hygon results

| Cases | Result | Notes |
| --- | --- | --- |
| 1-3 | Passed | 8B FlashAttention and graph, B1/B4/B16 |
| 4 | Capacity-limited | Completed 8/12 workloads before allocation failed |
| 5 | Passed | 8B paged attention and graph |
| 6 | Passed | 8B static attention |
| 7-8 | Passed | 70B FlashAttention and graph, TP8 |
| 9-10 | Capacity-limited | Model initialization or cache allocation exceeded memory |
| 11 | Passed | MHA 70B FlashAttention and graph, TP8 |
| 12 | Capacity-limited | B32, I2048/O2048 exceeded memory |
| 13 | Passed | 70B paged attention and graph, TP8 |

Cases 4, 9, 10, and 12 retain the original workloads so capacity behavior is
visible instead of silently reducing their sizes. Re-run the audit and relevant
cases whenever one of the selected branch heads changes.
