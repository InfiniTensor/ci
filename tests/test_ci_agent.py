import os
import signal
import sys

import ci_agent


def test_submit_writes_queued_task(tmp_path):
    task_id = ci_agent.submit_task(
        tmp_path,
        {
            "id": "nvidia-unit",
            "platform": "nvidia",
            "job": "nvidia_gpu",
            "command": "true",
            "workdir": str(tmp_path),
            "result_dir": str(tmp_path / "results"),
            "junit_path": "test-results.xml",
            "queue_timeout": 1800,
            "resources": {"ngpus": 1, "memory": "32GB"},
        },
    )

    task = ci_agent.load_task(tmp_path, task_id)

    assert task["id"] == "nvidia-unit"
    assert task["status"] == "queued"
    assert task["platform"] == "nvidia"
    assert task["junit_path"] == "test-results.xml"
    assert task["queue_timeout"] == 1800


def test_junit_required_for_pass_when_declared(tmp_path):
    result_dir = tmp_path / "results"
    result_dir.mkdir()

    result = ci_agent.evaluate_result(0, result_dir, "test-results.xml")

    assert result["status"] == "failed"
    assert result["reason"] == "missing_junit"


def test_junit_failures_make_task_fail(tmp_path):
    result_dir = tmp_path / "results"
    result_dir.mkdir()
    (result_dir / "test-results.xml").write_text(
        '<testsuite tests="1" failures="1" errors="0"></testsuite>',
        encoding="utf-8",
    )

    result = ci_agent.evaluate_result(0, result_dir, "test-results.xml")

    assert result["status"] == "failed"
    assert result["reason"] == "junit_failed"
    assert result["junit"]["failures"] == 1


def test_exit_code_and_clean_junit_pass(tmp_path):
    result_dir = tmp_path / "results"
    result_dir.mkdir()
    (result_dir / "test-results.xml").write_text(
        '<testsuite tests="2" failures="0" errors="0"></testsuite>',
        encoding="utf-8",
    )

    result = ci_agent.evaluate_result(0, result_dir, "test-results.xml")

    assert result["status"] == "passed"
    assert result["junit"]["tests"] == 2


def test_nested_junit_path_passes_when_declared(tmp_path):
    result_dir = tmp_path / "results"
    nested = result_dir / "nvidia_test_abc"
    nested.mkdir(parents=True)
    (nested / "test-results.xml").write_text(
        '<testsuite tests="2" failures="0" errors="0"></testsuite>',
        encoding="utf-8",
    )

    result = ci_agent.evaluate_result(0, result_dir, "test-results.xml")

    assert result["status"] == "passed"
    assert result["reason"] == "junit_passed"


def test_collect_task_writes_metadata_and_log(tmp_path):
    task_id = ci_agent.submit_task(
        tmp_path,
        {
            "id": "collect-me",
            "platform": "nvidia",
            "command": "true",
            "workdir": str(tmp_path),
            "result_dir": str(tmp_path / "results"),
        },
    )
    log_path = tmp_path / "logs" / f"{task_id}.log"
    log_path.parent.mkdir(exist_ok=True)
    log_path.write_text("hello\n", encoding="utf-8")
    task = ci_agent.load_task(tmp_path, task_id)
    task["status"] = "passed"
    task["log_path"] = str(log_path)
    ci_agent.save_task(tmp_path, task)

    output_dir = tmp_path / "out"
    ci_agent.collect_task(tmp_path, task_id, output_dir)

    assert (output_dir / "task.json").exists()
    assert (output_dir / "agent.log").read_text(encoding="utf-8") == "hello\n"


def test_cancel_marks_queued_task_canceled(tmp_path):
    task_id = ci_agent.submit_task(
        tmp_path,
        {
            "id": "cancel-me",
            "platform": "nvidia",
            "command": "true",
            "workdir": str(tmp_path),
            "result_dir": str(tmp_path / "results"),
        },
    )

    ci_agent.cancel_task(tmp_path, task_id)

    task = ci_agent.load_task(tmp_path, task_id)
    assert task["status"] == "canceled"


def test_daemon_once_runs_queued_task(tmp_path, monkeypatch):
    monkeypatch.setattr(ci_agent, "wait_for_resources", lambda *args, **kwargs: True)
    result_dir = tmp_path / "results"
    task_id = ci_agent.submit_task(
        tmp_path,
        {
            "id": "run-me",
            "platform": "nvidia",
            "command": (
                f"{sys.executable} -c "
                f"\"from pathlib import Path; "
                f"Path({str(result_dir)!r}).mkdir(exist_ok=True); "
                f"Path({str(result_dir / 'test-results.xml')!r}).write_text("
                f"'<testsuite tests=\\\"1\\\" failures=\\\"0\\\" errors=\\\"0\\\"></testsuite>')\""
            ),
            "workdir": str(tmp_path),
            "result_dir": str(result_dir),
            "junit_path": "test-results.xml",
            "queue_timeout": 1,
            "resources": {"ngpus": 0},
        },
    )

    ran = ci_agent.daemon_once(tmp_path)

    task = ci_agent.load_task(tmp_path, task_id)
    assert ran is True
    assert task["status"] == "passed"
    assert task["exit_code"] == 0


def test_run_task_ignores_non_queued_task(tmp_path, monkeypatch):
    monkeypatch.setattr(ci_agent, "wait_for_resources", lambda *args, **kwargs: True)
    task_id = ci_agent.submit_task(
        tmp_path,
        {
            "id": "already-running",
            "platform": "nvidia",
            "command": "false",
            "workdir": str(tmp_path),
            "result_dir": str(tmp_path / "results"),
        },
    )
    task = ci_agent.load_task(tmp_path, task_id)
    task["status"] = "running"
    ci_agent.save_task(tmp_path, task)

    ci_agent.run_task(tmp_path, task, poll_interval=0.01)

    task = ci_agent.load_task(tmp_path, task_id)
    assert task["status"] == "running"
    assert "exit_code" not in task


def test_wait_task_returns_false_for_failed_terminal_state(tmp_path):
    task_id = ci_agent.submit_task(
        tmp_path,
        {
            "id": "failed-task",
            "platform": "nvidia",
            "command": "false",
            "workdir": str(tmp_path),
            "result_dir": str(tmp_path / "results"),
        },
    )
    task = ci_agent.load_task(tmp_path, task_id)
    task["status"] = "failed"
    ci_agent.save_task(tmp_path, task)

    assert ci_agent.wait_task(tmp_path, task_id, poll_interval=0.01, timeout=1) is False


def test_cancel_running_task_sends_signal(tmp_path, monkeypatch):
    killed = {}

    def fake_killpg(pid, sig):
        killed["pid"] = pid
        killed["sig"] = sig

    monkeypatch.setattr(os, "killpg", fake_killpg)
    task_id = ci_agent.submit_task(
        tmp_path,
        {
            "id": "running-task",
            "platform": "nvidia",
            "command": "sleep 60",
            "workdir": str(tmp_path),
            "result_dir": str(tmp_path / "results"),
        },
    )
    task = ci_agent.load_task(tmp_path, task_id)
    task["status"] = "running"
    task["pid"] = 1234
    ci_agent.save_task(tmp_path, task)

    ci_agent.cancel_task(tmp_path, task_id)

    task = ci_agent.load_task(tmp_path, task_id)
    assert task["status"] == "canceling"
    assert killed == {"pid": 1234, "sig": signal.SIGTERM}
