from pathlib import Path

import pytest

import run


# ---------------------------------------------------------------------------
# Tests for `resolve_image`.
# ---------------------------------------------------------------------------


def test_resolve_image_with_registry():
    cfg = {"registry": {"url": "localhost:5000", "project": "infiniops"}}
    img = run.resolve_image(cfg, "nvidia", "latest")
    assert img == "localhost:5000/infiniops/nvidia:latest"


def test_resolve_image_without_registry(minimal_config):
    img = run.resolve_image(minimal_config, "nvidia", "abc1234")
    assert img == "infiniops-ci/nvidia:abc1234"


# ---------------------------------------------------------------------------
# Tests for `build_runner_script`.
# ---------------------------------------------------------------------------


def test_runner_script_contains_git_clone():
    script = run.build_runner_script()
    assert "git clone" in script


def test_runner_script_contains_setup_cmd():
    script = run.build_runner_script()
    assert "SETUP_CMD" in script


def test_runner_script_exits_on_failure():
    script = run.build_runner_script()
    assert "exit $failed" in script


def test_runner_script_creates_results_dir():
    script = run.build_runner_script()
    assert "mkdir -p /workspace/results" in script


# ---------------------------------------------------------------------------
# Tests for `build_docker_args` basic structure.
# ---------------------------------------------------------------------------


def test_docker_args_basic_structure(minimal_config):
    args = run.build_docker_args(
        minimal_config,
        "nvidia_gpu",
        "https://github.com/example/repo.git",
        "master",
        minimal_config["jobs"]["nvidia_gpu"]["stages"],
        "/workspace",
        None,
    )
    assert args[0] == "--rm"
    assert "--rm" in args


def test_docker_args_correct_image(minimal_config):
    args = run.build_docker_args(
        minimal_config,
        "nvidia_gpu",
        "https://github.com/example/repo.git",
        "master",
        minimal_config["jobs"]["nvidia_gpu"]["stages"],
        "/workspace",
        None,
    )
    assert "infiniops-ci/nvidia:latest" in args


def test_docker_args_image_tag_override(minimal_config):
    args = run.build_docker_args(
        minimal_config,
        "nvidia_gpu",
        "https://github.com/example/repo.git",
        "master",
        minimal_config["jobs"]["nvidia_gpu"]["stages"],
        "/workspace",
        "abc1234",
    )
    assert "infiniops-ci/nvidia:abc1234" in args


# ---------------------------------------------------------------------------
# Tests for `build_docker_args` proxy passthrough.
# ---------------------------------------------------------------------------


def test_docker_args_proxy_present_when_set(minimal_config, monkeypatch):
    monkeypatch.setenv("HTTP_PROXY", "http://proxy.example.com:8080")
    args = run.build_docker_args(
        minimal_config,
        "nvidia_gpu",
        "https://github.com/example/repo.git",
        "master",
        minimal_config["jobs"]["nvidia_gpu"]["stages"],
        "/workspace",
        None,
    )
    assert "-e" in args
    assert "HTTP_PROXY=http://proxy.example.com:8080" in args
    assert "http_proxy=http://proxy.example.com:8080" in args


def test_docker_args_proxy_absent_when_not_set(minimal_config, monkeypatch):
    monkeypatch.delenv("HTTP_PROXY", raising=False)
    monkeypatch.delenv("http_proxy", raising=False)
    monkeypatch.delenv("HTTPS_PROXY", raising=False)
    monkeypatch.delenv("https_proxy", raising=False)
    monkeypatch.delenv("NO_PROXY", raising=False)
    monkeypatch.delenv("no_proxy", raising=False)
    args = run.build_docker_args(
        minimal_config,
        "nvidia_gpu",
        "https://github.com/example/repo.git",
        "master",
        minimal_config["jobs"]["nvidia_gpu"]["stages"],
        "/workspace",
        None,
    )

    for arg in args:
        assert not arg.startswith("HTTP_PROXY=")
        assert not arg.startswith("http_proxy=")
        assert not arg.startswith("HTTPS_PROXY=")
        assert not arg.startswith("https_proxy=")
        assert not arg.startswith("NO_PROXY=")
        assert not arg.startswith("no_proxy=")


def test_docker_args_proxy_lowercase_fallback(minimal_config, monkeypatch):
    monkeypatch.delenv("HTTP_PROXY", raising=False)
    monkeypatch.setenv("http_proxy", "http://lowercase.proxy:3128")
    args = run.build_docker_args(
        minimal_config,
        "nvidia_gpu",
        "https://github.com/example/repo.git",
        "master",
        minimal_config["jobs"]["nvidia_gpu"]["stages"],
        "/workspace",
        None,
    )
    assert "HTTP_PROXY=http://lowercase.proxy:3128" in args
    assert "http_proxy=http://lowercase.proxy:3128" in args


# ---------------------------------------------------------------------------
# Tests for `build_docker_args` GPU flags.
# ---------------------------------------------------------------------------


def _make_args(config, gpu_id_override=None):
    return run.build_docker_args(
        config,
        "nvidia_gpu",
        "https://github.com/example/repo.git",
        "master",
        config["jobs"]["nvidia_gpu"]["stages"],
        "/workspace",
        None,
        gpu_id_override=gpu_id_override,
    )


def test_docker_args_gpu_device(minimal_config):
    args = _make_args(minimal_config)
    idx = args.index("--gpus")
    assert "device=0" in args[idx + 1]


def test_docker_args_gpu_auto_no_override(minimal_config):
    minimal_config["jobs"]["nvidia_gpu"]["resources"]["gpu_ids"] = "auto"
    args = _make_args(minimal_config)
    assert "--gpus" not in args


def test_docker_args_gpu_auto_with_override(minimal_config):
    minimal_config["jobs"]["nvidia_gpu"]["resources"]["gpu_ids"] = "auto"
    args = _make_args(minimal_config, gpu_id_override="2")
    idx = args.index("--gpus")
    assert "device=2" in args[idx + 1]


def test_docker_args_gpu_all(minimal_config):
    minimal_config["jobs"]["nvidia_gpu"]["resources"]["gpu_ids"] = "all"
    args = _make_args(minimal_config)
    idx = args.index("--gpus")
    assert args[idx + 1] == "all"


def test_docker_args_no_gpu(minimal_config):
    minimal_config["jobs"]["nvidia_gpu"]["resources"]["gpu_ids"] = ""
    minimal_config["jobs"]["nvidia_gpu"]["resources"].pop("gpu_count", None)
    args = _make_args(minimal_config)
    assert "--gpus" not in args


def test_docker_args_gpu_override(minimal_config):
    args = _make_args(minimal_config, gpu_id_override="2,3")
    idx = args.index("--gpus")
    assert "2,3" in args[idx + 1]


# ---------------------------------------------------------------------------
# Tests for `build_docker_args` platform-specific device env vars.
# ---------------------------------------------------------------------------


def _make_platform_config(platform, gpu_style="none", job_suffix="gpu"):
    from utils import normalize_config

    raw = {
        "platforms": {
            platform: {
                "image": {"dockerfile": f".ci/images/{platform}/"},
                "setup": "pip install .[dev]",
                "jobs": {
                    job_suffix: {
                        "resources": {
                            "ngpus": 1,
                            "gpu_style": gpu_style,
                            "memory": "32GB",
                        },
                        "stages": [{"name": "test", "run": "pytest tests/ -v"}],
                    }
                },
            }
        }
    }

    return normalize_config(raw)


def _make_platform_args(platform, gpu_style="none", job_suffix="gpu"):
    config = _make_platform_config(platform, gpu_style, job_suffix)
    job_name = f"{platform}_{job_suffix}"

    return run.build_docker_args(
        config,
        job_name,
        "https://github.com/example/repo.git",
        "master",
        config["jobs"][job_name]["stages"],
        "/workspace",
        None,
        gpu_id_override="0",
    )


def test_docker_args_moore_mthreads_visible_devices():
    args = _make_platform_args("moore")
    assert "MTHREADS_VISIBLE_DEVICES=0" in args
    assert all("CUDA_VISIBLE_DEVICES" not in a for a in args)


def test_docker_args_iluvatar_cuda_visible_devices():
    args = _make_platform_args("iluvatar")
    assert "CUDA_VISIBLE_DEVICES=0" in args


def test_docker_args_cambricon_mlu_visible_devices():
    args = _make_platform_args("cambricon", gpu_style="mlu")
    assert "MLU_VISIBLE_DEVICES=0" in args


def test_docker_args_ascend_visible_devices():
    args = _make_platform_args("ascend", job_suffix="npu")
    assert "ASCEND_VISIBLE_DEVICES=0" in args


def test_docker_args_metax_cuda_visible_devices():
    args = _make_platform_args("metax")
    assert "CUDA_VISIBLE_DEVICES=0" in args


def test_docker_args_non_nvidia_no_gpus_flag():
    for platform, gpu_style in (
        ("iluvatar", "none"),
        ("metax", "none"),
        ("moore", "none"),
        ("cambricon", "mlu"),
        ("ascend", "none"),
    ):
        args = _make_platform_args(platform, gpu_style=gpu_style)
        assert "--gpus" not in args


# ---------------------------------------------------------------------------
# Tests for `build_docker_args` memory format.
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("32GB", "32g"),
        ("512MB", "512m"),
        ("8", "8g"),
        ("16gb", "16g"),
        ("256mb", "256m"),
    ],
)
def test_docker_args_memory_format(minimal_config, raw, expected):
    minimal_config["jobs"]["nvidia_gpu"]["resources"]["memory"] = raw
    args = _make_args(minimal_config)
    idx = args.index("--memory")
    assert args[idx + 1] == expected


# ---------------------------------------------------------------------------
# Tests for `build_docker_args` stages encoding.
# ---------------------------------------------------------------------------


def test_docker_args_num_stages(minimal_config):
    args = _make_args(minimal_config)
    assert "NUM_STAGES=1" in args


def test_docker_args_stage_name_cmd(minimal_config):
    args = _make_args(minimal_config)
    assert "STAGE_1_NAME=test" in args
    assert any(a.startswith("STAGE_1_CMD=") for a in args)


def test_docker_args_multiple_stages(minimal_config):
    minimal_config["jobs"]["nvidia_gpu"]["stages"] = [
        {"name": "lint", "run": "ruff check ."},
        {"name": "test", "run": "pytest tests/"},
    ]
    args = _make_args(minimal_config)
    assert "NUM_STAGES=2" in args
    assert "STAGE_1_NAME=lint" in args
    assert "STAGE_2_NAME=test" in args


# ---------------------------------------------------------------------------
# Tests for `build_docker_args` `results_dir` mount.
# ---------------------------------------------------------------------------


def test_docker_args_results_dir(minimal_config, tmp_path):
    args = run.build_docker_args(
        minimal_config,
        "nvidia_gpu",
        "https://github.com/example/repo.git",
        "master",
        minimal_config["jobs"]["nvidia_gpu"]["stages"],
        "/workspace",
        None,
        results_dir=tmp_path,
    )
    joined = " ".join(str(a) for a in args)
    assert "-v" in args
    assert "/workspace/results" in joined


# ---------------------------------------------------------------------------
# Tests for `build_results_dir`.
# ---------------------------------------------------------------------------


def test_build_results_dir_contains_platform():
    stages = [{"name": "test", "run": "pytest"}]
    d = run.build_results_dir("ci-results", "nvidia", stages, "abc1234")
    assert "nvidia" in d.name


def test_build_results_dir_contains_commit():
    stages = [{"name": "test", "run": "pytest"}]
    d = run.build_results_dir("ci-results", "nvidia", stages, "abc1234")
    assert "abc1234" in d.name


def test_build_results_dir_contains_stage_names():
    stages = [{"name": "lint", "run": "ruff"}, {"name": "test", "run": "pytest"}]
    d = run.build_results_dir("ci-results", "nvidia", stages, "abc1234")
    assert "lint+test" in d.name


def test_build_results_dir_under_base():
    stages = [{"name": "test", "run": "pytest"}]
    d = run.build_results_dir("/tmp/my-results", "ascend", stages, "def5678")
    assert d.parent == Path("/tmp/my-results")
