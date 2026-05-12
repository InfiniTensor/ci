from __future__ import annotations

import argparse
import copy
import json
import os
import re
import sys
import uuid
from collections import defaultdict
from pathlib import Path
from typing import Any

TEST_PARAM_PLACEHOLDER = "<TEST_PARAM>"

THIS_FILE = Path(__file__).resolve()
CI_DIR = THIS_FILE.parent
if str(CI_DIR) not in sys.path:
    sys.path.insert(0, str(CI_DIR))

from ci_resource import GPU_STYLE_MLU, GPU_STYLE_NVIDIA
from utils import load_config

DEFAULT_JOB_TYPE = "unittest"


def _sanitize_output_suffix(job_type: str) -> str:
    t = str(job_type or DEFAULT_JOB_TYPE).strip().lower() or DEFAULT_JOB_TYPE
    t = re.sub(r"[^a-z0-9_]+", "_", t)
    return t.strip("_") or DEFAULT_JOB_TYPE


def _job_type_from_cfg(job_cfg: dict[str, Any]) -> str:
    return _sanitize_output_suffix(str(job_cfg.get("type", DEFAULT_JOB_TYPE)))


def _normalize_build_args(build_args: dict[str, Any] | None) -> list[str]:
    return [f"{key}={value}" for key, value in (build_args or {}).items()]


def _is_default_test_param(value: Any) -> bool:
    if value is None:
        return True
    return str(value).strip().lower() == "default"


def apply_test_param_to_run(run: str, param_value: Any) -> str:
    """Replace ``<TEST_PARAM>`` in a run line; ``default`` removes the token only."""
    s = str(run or "")
    if TEST_PARAM_PLACEHOLDER not in s:
        return s.strip()
    if _is_default_test_param(param_value):
        replaced = s.replace(TEST_PARAM_PLACEHOLDER, "")
    else:
        replaced = s.replace(TEST_PARAM_PLACEHOLDER, str(param_value).strip())
    return replaced.strip()


def expand_stages_with_test_param(
    stages: list[dict[str, Any]], param_value: Any
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for i, st in enumerate(stages):
        nd = copy.deepcopy(st)
        nd["name"] = f"test_{i + 1}"
        if "run" in nd:
            nd["run"] = apply_test_param_to_run(nd.get("run", ""), param_value)
        out.append(nd)
    return out


def expand_test_param_jobs(config: dict[str, Any]) -> dict[str, Any]:
    """Split jobs whose ``env.TEST_PARAM`` is a list into one job per value (matrix + run.py)."""
    jobs = config.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        return config

    new_jobs: dict[str, Any] = {}
    for job_id, job_cfg in jobs.items():
        env = job_cfg.get("env") or {}
        tp = env.get("TEST_PARAM")
        if not isinstance(tp, list):
            new_jobs[job_id] = job_cfg
            continue

        stages_template = job_cfg.get("stages") or []
        if not stages_template:
            fixed = copy.deepcopy(job_cfg)
            ne = dict(fixed.get("env") or {})
            ne.pop("TEST_PARAM", None)
            fixed["env"] = ne
            new_jobs[job_id] = fixed
            continue

        for idx, raw_param in enumerate(tp):
            new_id = f"{job_id}__tp{idx}"
            new_job = copy.deepcopy(job_cfg)
            new_job["stages"] = expand_stages_with_test_param(stages_template, raw_param)

            new_env = dict(new_job.get("env") or {})
            new_env.pop("TEST_PARAM", None)
            if _is_default_test_param(raw_param):
                new_env["TEST_PARAM"] = ""
            else:
                new_env["TEST_PARAM"] = str(raw_param).strip()
            new_job["env"] = new_env

            base_short = str(new_job.get("short_name", "")).strip() or job_id
            if _is_default_test_param(raw_param):
                label = "default"
            else:
                pv = str(raw_param).strip()
                label = pv[:60] + ("…" if len(pv) > 60 else "")
            new_job["short_name"] = f"{base_short}_{label}"

            new_jobs[new_id] = new_job

    config["jobs"] = new_jobs
    return config


def _collect_test_command(job_cfg: dict[str, Any]) -> str:
    stages = job_cfg.get("stages", [])
    runs = [stage.get("run", "").strip() for stage in stages if stage.get("run")]
    return " && ".join(cmd for cmd in runs if cmd)


def _normalize_gpu_style(value: Any) -> str:
    gpu_style = str(value or GPU_STYLE_NVIDIA).strip().lower()
    if gpu_style in {GPU_STYLE_NVIDIA, "none", GPU_STYLE_MLU}:
        return gpu_style
    return GPU_STYLE_NVIDIA


def _entry_from_flat_job(
    job_id: str, job_cfg: dict[str, Any], image_cfg: dict[str, Any]
) -> dict[str, Any]:
    platform = str(job_cfg.get("platform", "")).strip()
    short_name = str(job_cfg.get("short_name", "")).strip() or job_id
    resources = job_cfg.get("resources", {})

    dockerfile_dir = str(image_cfg.get("dockerfile", "")).rstrip("/")
    dockerfile = f"{dockerfile_dir}/Dockerfile" if dockerfile_dir else ""

    timeout_seconds = int(resources.get("timeout", 3600))
    timeout_minutes = max(1, timeout_seconds // 60)

    return {
        "id": job_id,
        "platform": platform,
        "job_name": short_name,
        "runner_label": platform,
        "dockerfile": dockerfile,
        "build_args": _normalize_build_args(image_cfg.get("build_args")),
        "docker_args": job_cfg.get("docker_args", []),
        "volumes": job_cfg.get("volumes", []),
        "setup": str(job_cfg.get("setup", "")).strip(),
        "test_cmd": _collect_test_command(job_cfg),
        "timeout_minutes": timeout_minutes,
        "memory": resources.get("memory", ""),
        "shm_size": resources.get("shm_size", ""),
        "gpu_ids": str(resources.get("gpu_ids", "")).strip(),
        "ngpus": resources.get("ngpus", ""),
        "gpu_style": _normalize_gpu_style(resources.get("gpu_style")),
        "job_env": job_cfg.get("env", {}),
        "job_type": _job_type_from_cfg(job_cfg),
    }


def convert_combined(config: dict[str, Any]) -> dict[str, Any]:
    """Single matrix with all jobs (backward-compatible default)."""
    include: list[dict[str, Any]] = []
    jobs = config.get("jobs", {})
    images = config.get("images", {})

    for job_id, job_cfg in jobs.items():
        platform = str(job_cfg.get("platform", "")).strip()
        image_cfg = images.get(platform, {})
        include.append(_entry_from_flat_job(job_id, job_cfg, image_cfg))

    if not include:
        raise ValueError("No jobs found in normalized config['jobs']")
    return {"include": include}


def convert_by_job_type(config: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Matrices keyed by sanitized job `type` (e.g. unittest, smoketest)."""
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    jobs = config.get("jobs", {})
    images = config.get("images", {})

    for job_id, job_cfg in jobs.items():
        platform = str(job_cfg.get("platform", "")).strip()
        image_cfg = images.get(platform, {})
        jt = _job_type_from_cfg(job_cfg)
        grouped[jt].append(_entry_from_flat_job(job_id, job_cfg, image_cfg))

    if not grouped:
        raise ValueError("No jobs found in normalized config['jobs']")
    return {k: {"include": v} for k, v in sorted(grouped.items())}


def write_github_matrix_outputs(
    github_output: Path, matrices_by_type: dict[str, dict[str, Any]]
) -> None:
    """Append matrix_json_for_<type> and job_types_with_jobs to GITHUB_OUTPUT."""
    types_ordered = sorted(matrices_by_type.keys())
    payload = json.dumps(types_ordered, ensure_ascii=True)

    with github_output.open("a", encoding="utf-8") as f:
        delim = f"JOB_TYPES_{uuid.uuid4().hex}"
        f.write(f"job_types_with_jobs<<{delim}\n")
        f.write(payload + "\n")
        f.write(f"{delim}\n")

        for job_type in types_ordered:
            matrix = matrices_by_type[job_type]
            key = f"matrix_json_for_{job_type}"
            delim_m = f"M_{uuid.uuid4().hex}"
            body = json.dumps(matrix, ensure_ascii=True)
            f.write(f"{key}<<{delim_m}\n")
            f.write(body + "\n")
            f.write(f"{delim_m}\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert custom CI config to GitHub matrix JSON"
    )
    parser.add_argument(
        "--config", type=Path, default=Path(".ci/config.yml"), help="Path to config file"
    )
    parser.add_argument(
        "--write-github-outputs",
        action="store_true",
        help="Write matrix_json_for_<type> and job_types_with_jobs to $GITHUB_OUTPUT",
    )
    parser.add_argument(
        "--dump-by-type",
        action="store_true",
        help="Print a JSON object mapping job type -> matrix (for local debugging)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    config = load_config(args.config)

    if args.write_github_outputs:
        out = os.environ.get("GITHUB_OUTPUT")
        if not out:
            print("error: GITHUB_OUTPUT is not set", file=sys.stderr)
            return 1
        matrices = convert_by_job_type(config)
        write_github_matrix_outputs(Path(out), matrices)
        return 0

    if args.dump_by_type:
        matrices = convert_by_job_type(config)
        print(json.dumps(matrices, ensure_ascii=True))
        return 0

    matrix = convert_combined(config)
    print(json.dumps(matrix, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
