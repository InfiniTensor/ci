# Iluvatar CoreX development image

This image reproduces the CoreX 4.5 environment used to validate the modern
InfiniCore and InfiniLM stack on BI-V150. Source and model weights stay on the
host.

The default base image is
`corex:4.5.0-10.2-ubuntu24.04-llm-py3.10` (CoreX 4.5.0.20260615,
Python 3.10, CoreX PyTorch 2.10.0). The development image preserves that
PyTorch build and pins the additional Python, Xmake, and Xmake-recipe versions.

## Prepare source checkouts

Prepare the repositories on the host before starting the container. The current
integration branches are temporary; switch them to the default branches after
the corresponding refactors merge.

| Checkout under `SOURCE_ROOT` | Current branch |
| --- | --- |
| `InfiniCore` | `refactor/component-manifest` |
| `InfiniCore/submodules/InfiniRT` | `master` |
| `InfiniCore/submodules/InfiniOps` | `master` |
| `InfiniCore/submodules/InfiniCCL` | `master` |
| `InfiniLM` | `refactor/adopt-modern-infini-stack` |

Set the directory containing those checkouts and inspect the prepared state:

```bash
SOURCE_ROOT="$HOME/codes"
git -C "$SOURCE_ROOT/InfiniCore" status --short --branch
git -C "$SOURCE_ROOT/InfiniCore" \
  submodule foreach --recursive 'git status --short --branch'
git -C "$SOURCE_ROOT/InfiniLM" status --short --branch
```

The three submodule worktrees must be clean, and InfiniCore `HEAD` must record
their prepared heads in its gitlinks. `build_infini_stack.py` enforces this
contract. The container does not fetch, switch, or modify source revisions.

## Build and start

Run from the root of the `InfiniTensor/ci` checkout:

```bash
docker build \
  -f images/iluvatar/Dockerfile.dev \
  -t infinitensor/infini-dev:iluvatar-corex45 .
```

Use `--build-arg BASE_IMAGE=<registry>/corex:4.5.0-10.2-ubuntu24.04-llm-py3.10`
when the base image has a registry-qualified name. Publish validated images by
digest because tags are mutable.

Create an isolated host directory and start the container. `SOURCE_ROOT`
defaults to `$HOME/codes` when it was not set earlier:

```bash
# Run unchanged: mktemp replaces XXXXXX with random characters.
SOURCE_ROOT="${SOURCE_ROOT:-$HOME/codes}"
RUN_ROOT="$(mktemp -d "$HOME/infini-iluvatar-run-XXXXXX")"
printf 'SOURCE_ROOT=%s\nRUN_ROOT=%s\n' "$SOURCE_ROOT" "$RUN_ROOT"

docker run --rm -it \
  --name infini-iluvatar-dev \
  --privileged \
  --network host \
  --ipc host \
  --ulimit memlock=-1:-1 \
  --ulimit stack=67108864:67108864 \
  -v /usr/local/corex-4.5.0:/usr/local/corex-host:ro \
  -v /data-aisoft:/data-aisoft:ro \
  -v "${SOURCE_ROOT:?SOURCE_ROOT is not set}:/workspace/src" \
  -v "${RUN_ROOT:?RUN_ROOT is not set}:/workspace/run" \
  -v "$(pwd):/workspace/ci:ro" \
  -e SOURCE_ROOT=/workspace/src \
  -e RUN_ROOT=/workspace/run \
  -e CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7 \
  -w /workspace/src/InfiniLM \
  infinitensor/infini-dev:iluvatar-corex45 \
  bash
```

`RUN_ROOT` needs no manual suffix and no `export`: the host shell expands it in
`docker run`, while the container always uses `/workspace/run`. The directory
keeps builds and logs after the `--rm` container exits, and a new one prevents
stale build state from affecting later validation. Source remains in the
user-managed `SOURCE_ROOT` checkout.

Eight BI-V150 devices are required for the TP8 cases. The 160 GB 70B checkpoint
also needs roughly 220 GiB usable host memory. Stop conflicting jobs first.

Inside the container, verify the host driver and CoreX PyTorch:

```bash
/usr/local/corex-host/bin/ixsmi
python3 - <<'PY'
import torch

print("torch:", torch.__version__)
print("cuda compatibility:", torch.version.cuda)
print("device count:", torch.cuda.device_count())
print("device 0:", torch.cuda.get_device_name(0))
PY
```

## Build the stack

The external operator config selects Iluvatar native implementation 0 for model
kernels and ATen implementation 8 only for `Argmax`, `Tril`, and `Triu`.

```bash
BUILD_ROOT="$RUN_ROOT/build"
LOG_ROOT="$RUN_ROOT/logs"
mkdir -p "$BUILD_ROOT" "$LOG_ROOT"

cd "$SOURCE_ROOT/InfiniLM"

python3 scripts/build_infini_stack.py \
  --infinicore-root "$SOURCE_ROOT/InfiniCore" \
  --backend iluvatar \
  --operator-config /workspace/ci/images/iluvatar/infiniops_ops.json \
  --build-root "$BUILD_ROOT/stack" \
  --test
```

`--test` includes InfiniRT tests and a two-device InfiniCCL AllReduce smoke
test. Continue only after the stack build succeeds:

```bash
export INFINI_ROOT="$BUILD_ROOT/stack/prefix"
export LD_LIBRARY_PATH="$INFINI_ROOT/lib:${LD_LIBRARY_PATH:-}"

xmake f -y -c \
  -o "$BUILD_ROOT/InfiniLM" \
  --cxx11-abi=0 \
  -m release
python3 -m pip install -e . --no-build-isolation --no-deps
```

## Audit the integration

Define one logging helper for the audit and all benchmark cases:

```bash
cd "$SOURCE_ROOT/InfiniLM"
set -o pipefail

run_case() {
  local case_id="$1"
  shift
  python3 examples/bench.py --device iluvatar "$@" 2>&1 \
    | tee "$LOG_ROOT/${case_id}.log"
}

MODEL_8B=/data-aisoft/mechdancer/models/9g_8b_thinking_llama
MODEL_70B=/data-aisoft/mechdancer/models/FM9G_70B
MODEL_70B_MHA=/data-aisoft/mechdancer/models/FM9G_70B_SFT_MHA
```

Run a short trace before the long matrix:

```bash
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
for operator in FlashAttnVarlenFunc FlashAttnWithKvcache ReshapeAndCacheFlash; do
  grep -m1 "\"operator_name\": \"$operator\".*\"implementation\": 0" \
    "$AUDIT_LOG"
done
grep -m1 'Using InfiniRT C++ segmented graph runtime API' "$AUDIT_LOG"
grep -m1 'segmented graph:' "$AUDIT_LOG"
! grep -q 'Falling back to eager execution' "$AUDIT_LOG"

ldd "$SOURCE_ROOT/InfiniLM/python/infinicore/lib/libinfinicore_runtime.so" \
  | grep -E 'libinfiniops|libinfiniccl|libinfinirt'

unset INFINI_OPS_TRACE_CALLS
```

Implementation 0 is native Iluvatar; implementation 8 is ATen. A graph case is
not a pass if its log contains `Falling back to eager execution`.

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

Cases 7-10 cover the 64-head/8-KV-head GQA 70B model with TP8:

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

Cases 11-13 cover MHA FlashAttention and the remaining GQA workloads. Case 13
keeps the original test command, which enables paged attention and graph mode
despite its `Static` label.

```bash
run_case case-11-70b-mha-flash-graph \
  --model="$MODEL_70B_MHA" \
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

## Reference BI-V150 results

| Cases | Result | Notes |
| --- | --- | --- |
| 1-3 | Passed | 8B FlashAttention and graph, B1/B4/B16 |
| 4 | Expected OOM | B64 exceeds per-device memory |
| 5 | Passed | 8B paged attention and graph |
| 6 | Passed | 8B static attention |
| 7-8 | Passed | GQA 70B FlashAttention and graph, TP8 |
| 9 | Capacity-limited | Graph OOM causes eager fallback |
| 10 | Expected OOM | B64 cache exceeds per-device memory |
| 11 | Passed | MHA 70B FlashAttention and graph, TP8 |
| 12 | Expected OOM | B32, I2048/O2048 exceeds per-device memory |
| 13 | Passed | GQA 70B paged attention and graph, TP8 |

These results were recorded from a clean container before source preparation
changed to moving branch tips. Re-run the audit and relevant cases for the
current checkouts. The reference run revalidated cases 6 and 13; case 13
completed with 1123 operators, 161 segments, 80 host segments, and no eager
fallback. Cases 4, 9, 10, and 12 are capacity outcomes on 32 GiB BI-V150, not
functional passes.
