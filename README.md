# .ci - CI Images and Pipeline

This directory contains the shared CI configuration, Docker image builder,
local runner helpers, GitHub Actions matrix converter, and tests.

```
.ci/
├── config.yaml
├── build.py
├── run.py
├── ci_resource.py
├── daemon.sh
├── scripts/
│   └── config_to_matrix.py
├── images/
│   ├── nvidia/
│   ├── iluvatar/
│   ├── metax/
│   ├── moore/
│   ├── cambricon/
│   └── ascend/
└── tests/
```

Prerequisites: Docker, Python 3.10+, and `pip install pyyaml`.

## Configuration

`config.yaml` uses a platform-centric structure. `utils.normalize_config()`
flattens each platform job to `{platform}_{job}`, for example `nvidia_gpu`.

Important resource fields:

| Field | Description |
|---|---|
| `resources.ngpus` | Number of devices to reserve when `gpu_ids` is `auto` or omitted |
| `resources.gpu_ids` | `auto`, `all`, or static IDs such as `"0"` / `"0,2"` |
| `resources.gpu_style` | Docker device style: `nvidia`, `none`, or `mlu` |
| `resources.memory` | Container memory limit |
| `resources.shm_size` | Docker `--shm-size` |
| `resources.timeout` | Stage timeout in seconds |

Platform device visibility is handled by `ci_resource.PLATFORM_DEVICE_ENV`:

| Platform | Detection tool | Device exposure |
|---|---|---|
| `nvidia` | `nvidia-smi` | Docker `--gpus` |
| `iluvatar` | `ixsmi` | `CUDA_VISIBLE_DEVICES` |
| `metax` | `mx-smi` | `CUDA_VISIBLE_DEVICES` |
| `moore` | `mthreads-gmi` | `MTHREADS_VISIBLE_DEVICES` |
| `cambricon` | `cnmon` | `MLU_VISIBLE_DEVICES` |
| `ascend` | `npu-smi` | `ASCEND_VISIBLE_DEVICES` |

## Image Builder

```bash
python .ci/build.py --platform nvidia
python .ci/build.py --platform metax --force
python .ci/build.py --platform all --dry-run
```

Supported platforms are `nvidia`, `iluvatar`, `metax`, `moore`, `cambricon`,
`ascend`, and `all`. Image tags default to `infiniops-ci/<platform>:<commit>`
and `infiniops-ci/<platform>:latest` unless a registry is configured.

## Local Runner

```bash
python .ci/run.py
python .ci/run.py --job gpu --stage test --dry-run
python .ci/run.py --job nvidia_gpu --gpu-id 0 --local
python .ci/run.py --test tests/test_gemm.py::test_gemm
```

`run.py` detects the current platform from the vendor CLI on `PATH`, resolves
matching jobs, allocates GPUs for `gpu_ids: auto`, builds Docker arguments, and
runs the configured stages. With `--local`, the current checkout is mounted
read-only and copied into the container before setup.

## GitHub Actions

`.github/workflows/ci_test.yml` calls:

```bash
python .ci/scripts/config_to_matrix.py --config .ci/config.yaml --write-github-outputs
```

The child workflows use the generated matrix and call `.ci/daemon.sh` to hand
the Docker argument string to the platform test launcher.

## Validation

Run these from `.ci/` after changes:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 scripts/config_to_matrix.py --config config.yaml --dump-by-type >/tmp/ci-matrix.json
bash -n daemon.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest tests -q
```
