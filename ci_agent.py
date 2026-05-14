#!/usr/bin/env python3
"""File-backed local CI agent for self-hosted hardware runners."""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import shutil
import signal
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ci_resource import ResourcePool, parse_memory_requirement

TERMINAL_STATUSES = {"passed", "failed", "canceled", "resource_timeout"}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_state_dir(state_dir: Path) -> None:
    for name in ("tasks", "logs", "locks"):
        (Path(state_dir) / name).mkdir(parents=True, exist_ok=True)


def task_path(state_dir: Path, task_id: str) -> Path:
    return Path(state_dir) / "tasks" / f"{task_id}.json"


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(f".{uuid.uuid4().hex}.tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def load_task(state_dir: Path, task_id: str) -> dict[str, Any]:
    path = task_path(Path(state_dir), task_id)
    return json.loads(path.read_text(encoding="utf-8"))


def save_task(state_dir: Path, task: dict[str, Any]) -> None:
    atomic_write_json(task_path(Path(state_dir), task["id"]), task)


@contextlib.contextmanager
def file_lock(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+", encoding="utf-8") as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)


def submit_task(state_dir: Path, task: dict[str, Any]) -> str:
    ensure_state_dir(Path(state_dir))
    task_id = str(task.get("id") or uuid.uuid4().hex)
    now = utc_now()
    payload = {
        **task,
        "id": task_id,
        "status": "queued",
        "submitted_at": now,
        "updated_at": now,
    }
    save_task(Path(state_dir), payload)
    return task_id


def list_tasks(state_dir: Path, status: str | None = None) -> list[dict[str, Any]]:
    ensure_state_dir(Path(state_dir))
    tasks = []
    for path in sorted((Path(state_dir) / "tasks").glob("*.json")):
        try:
            task = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        if status is None or task.get("status") == status:
            tasks.append(task)
    return sorted(tasks, key=lambda t: t.get("submitted_at", ""))


def parse_junit(path: Path) -> dict[str, int]:
    root = ET.parse(path).getroot()
    suites = root.findall("testsuite") if root.tag == "testsuites" else [root]
    summary = {"tests": 0, "failures": 0, "errors": 0, "skipped": 0}
    for suite in suites:
        for key in summary:
            try:
                summary[key] += int(suite.get(key, 0))
            except ValueError:
                summary[key] += 0
    return summary


def evaluate_result(
    exit_code: int, result_dir: Path | str, junit_path: str | None = None
) -> dict[str, Any]:
    result: dict[str, Any] = {"exit_code": exit_code}
    if exit_code != 0:
        result.update({"status": "failed", "reason": "exit_code"})
        return result

    if not junit_path:
        result.update({"status": "passed", "reason": "exit_code"})
        return result

    junit = Path(junit_path)
    if not junit.is_absolute():
        junit = Path(result_dir) / junit

    if not junit.exists():
        result.update({"status": "failed", "reason": "missing_junit"})
        return result

    try:
        summary = parse_junit(junit)
    except (ET.ParseError, OSError):
        result.update({"status": "failed", "reason": "invalid_junit"})
        return result

    result["junit"] = summary
    if summary["failures"] or summary["errors"]:
        result.update({"status": "failed", "reason": "junit_failed"})
    else:
        result.update({"status": "passed", "reason": "junit_passed"})
    return result


def resource_count(resources: dict[str, Any]) -> int:
    try:
        return int(resources.get("ngpus", 0) or 0)
    except (TypeError, ValueError):
        return 0


def wait_for_resources(task: dict[str, Any], deadline: float, poll_interval: float) -> bool:
    resources = task.get("resources", {}) or {}
    gpu_count = resource_count(resources)
    if gpu_count <= 0:
        return True

    pool = ResourcePool(task.get("platform", ""))
    job = {"resources": resources}
    memory_mb = parse_memory_requirement(job)
    while time.monotonic() < deadline:
        allocated, ok = pool.allocate(gpu_count, memory_mb)
        if ok:
            pool.release(allocated)
            return True
        time.sleep(poll_interval)
    return False


def _mark_task(state_dir: Path, task: dict[str, Any], status: str, **updates) -> None:
    task.update(updates)
    task["status"] = status
    task["updated_at"] = utc_now()
    save_task(state_dir, task)


def run_task(state_dir: Path, task: dict[str, Any], poll_interval: float = 1.0) -> None:
    state_dir = Path(state_dir)
    task_id = task["id"]
    log_path = state_dir / "logs" / f"{task_id}.log"
    result_dir = Path(task.get("result_dir") or state_dir / "results" / task_id)
    result_dir.mkdir(parents=True, exist_ok=True)

    queue_timeout = int(task.get("queue_timeout") or 1800)
    deadline = time.monotonic() + queue_timeout
    lock_path = state_dir / "locks" / f"{task.get('platform', 'unknown')}.lock"

    with file_lock(lock_path):
        task = load_task(state_dir, task_id)
        if task.get("status") in {"canceled", "canceling"}:
            _mark_task(state_dir, task, "canceled", finished_at=utc_now())
            return

        if not wait_for_resources(task, deadline, poll_interval):
            _mark_task(
                state_dir,
                task,
                "resource_timeout",
                finished_at=utc_now(),
                reason="resource_timeout",
            )
            return

        _mark_task(
            state_dir,
            task,
            "running",
            started_at=utc_now(),
            log_path=str(log_path),
            result_dir=str(result_dir),
        )

        command = task["command"]
        workdir = Path(task.get("workdir") or ".")
        with log_path.open("ab") as log:
            proc = subprocess.Popen(
                command,
                cwd=workdir,
                shell=True,
                stdout=log,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            task = load_task(state_dir, task_id)
            task["pid"] = proc.pid
            task["updated_at"] = utc_now()
            save_task(state_dir, task)

            while proc.poll() is None:
                current = load_task(state_dir, task_id)
                if current.get("status") == "canceling":
                    with contextlib.suppress(ProcessLookupError):
                        os.killpg(proc.pid, signal.SIGTERM)
                    try:
                        proc.wait(timeout=30)
                    except subprocess.TimeoutExpired:
                        with contextlib.suppress(ProcessLookupError):
                            os.killpg(proc.pid, signal.SIGKILL)
                    _mark_task(state_dir, current, "canceled", finished_at=utc_now())
                    return
                time.sleep(poll_interval)

        exit_code = proc.returncode
        result = evaluate_result(exit_code, result_dir, task.get("junit_path"))
        task = load_task(state_dir, task_id)
        _mark_task(
            state_dir,
            task,
            result["status"],
            exit_code=exit_code,
            finished_at=utc_now(),
            result=result,
        )


def daemon_once(state_dir: Path, poll_interval: float = 1.0) -> bool:
    queued = list_tasks(Path(state_dir), status="queued")
    if not queued:
        return False
    run_task(Path(state_dir), queued[0], poll_interval=poll_interval)
    return True


def daemon_loop(state_dir: Path, poll_interval: float = 5.0) -> None:
    ensure_state_dir(Path(state_dir))
    while True:
        daemon_once(Path(state_dir), poll_interval=poll_interval)
        time.sleep(poll_interval)


def wait_task(
    state_dir: Path, task_id: str, poll_interval: float = 5.0, timeout: int | None = None
) -> bool:
    start = time.monotonic()
    while True:
        task = load_task(Path(state_dir), task_id)
        status = task.get("status")
        if status in TERMINAL_STATUSES:
            return status == "passed"
        if timeout is not None and time.monotonic() - start > timeout:
            return False
        time.sleep(poll_interval)


def collect_task(state_dir: Path, task_id: str, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    task = load_task(Path(state_dir), task_id)
    atomic_write_json(output_dir / "task.json", task)

    log_path = task.get("log_path")
    if log_path and Path(log_path).exists():
        shutil.copy2(log_path, output_dir / "agent.log")

    result_dir = task.get("result_dir")
    if result_dir and Path(result_dir).exists():
        dest = output_dir / "results"
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(result_dir, dest)


def cancel_task(state_dir: Path, task_id: str) -> None:
    task = load_task(Path(state_dir), task_id)
    if task.get("status") in TERMINAL_STATUSES:
        return

    if task.get("status") == "running" and task.get("pid"):
        with contextlib.suppress(ProcessLookupError):
            os.killpg(int(task["pid"]), signal.SIGTERM)
        _mark_task(Path(state_dir), task, "canceling", cancel_requested_at=utc_now())
    else:
        _mark_task(Path(state_dir), task, "canceled", finished_at=utc_now())


def load_payload(args: argparse.Namespace) -> dict[str, Any]:
    if args.payload_file:
        return json.loads(Path(args.payload_file).read_text(encoding="utf-8"))
    payload = {
        "id": args.id,
        "platform": args.platform,
        "job": args.job,
        "command": args.command,
        "workdir": args.workdir,
        "result_dir": args.result_dir,
        "junit_path": args.junit_path,
        "queue_timeout": args.queue_timeout,
        "resources": {"ngpus": args.ngpus, "memory": args.memory},
    }
    return {key: value for key, value in payload.items() if value is not None}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Local file-backed CI agent")
    parser.add_argument(
        "--state-dir",
        type=Path,
        default=Path(os.environ.get("CI_AGENT_STATE_DIR", "/var/lib/ci-agent")),
    )
    sub = parser.add_subparsers(dest="command_name", required=True)

    submit = sub.add_parser("submit", help="Submit a platform job")
    submit.add_argument("--payload-file")
    submit.add_argument("--id")
    submit.add_argument("--platform")
    submit.add_argument("--job")
    submit.add_argument("--command")
    submit.add_argument("--workdir")
    submit.add_argument("--result-dir")
    submit.add_argument("--junit-path")
    submit.add_argument("--queue-timeout", type=int, default=1800)
    submit.add_argument("--ngpus", type=int, default=0)
    submit.add_argument("--memory", default="")

    wait = sub.add_parser("wait", help="Wait for a submitted task")
    wait.add_argument("task_id")
    wait.add_argument("--poll-interval", type=float, default=5.0)
    wait.add_argument("--timeout", type=int)

    collect = sub.add_parser("collect", help="Collect task metadata and artifacts")
    collect.add_argument("task_id")
    collect.add_argument("--output-dir", type=Path, required=True)

    cancel = sub.add_parser("cancel", help="Cancel a queued or running task")
    cancel.add_argument("task_id")

    daemon = sub.add_parser("daemon", help="Run the local agent daemon loop")
    daemon.add_argument("--poll-interval", type=float, default=5.0)
    daemon.add_argument("--once", action="store_true")

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    state_dir = Path(args.state_dir)

    if args.command_name == "submit":
        task_id = submit_task(state_dir, load_payload(args))
        print(task_id)
        return 0
    if args.command_name == "wait":
        return 0 if wait_task(state_dir, args.task_id, args.poll_interval, args.timeout) else 1
    if args.command_name == "collect":
        collect_task(state_dir, args.task_id, args.output_dir)
        return 0
    if args.command_name == "cancel":
        cancel_task(state_dir, args.task_id)
        return 0
    if args.command_name == "daemon":
        if args.once:
            return 0 if daemon_once(state_dir, args.poll_interval) else 1
        daemon_loop(state_dir, args.poll_interval)
        return 0

    parser.error("unknown command")
    return 2


if __name__ == "__main__":
    sys.exit(main())
