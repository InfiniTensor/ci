from pathlib import Path

import yaml


WORKFLOW = Path(".github/workflows/infiniops-ci-v2-shadow.yml")


def test_shadow_workflow_uses_agent_cli():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "CI v2 Shadow" in text
    assert "agent_unavailable" in text
    assert "systemctl is-active --quiet ci-agent" in text
    assert "using transient ci-agent state dir" in text
    assert "started transient ci-agent daemon with state dir" in text
    assert 'local probe="${candidate}/locks/${{ matrix.platform }}.lock"' in text
    assert "ci_agent.py submit" in text
    assert "ci_agent.py wait" in text
    assert "ci_agent.py collect" in text
    assert "ci_agent.py cancel" in text
    assert "Fail failed CI v2 shadow task" in text


def test_shadow_workflow_requires_explicit_runner_labels():
    workflow = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    convert_step = workflow["jobs"]["prepare"]["steps"][-1]

    assert "--require-runner-label" in convert_step["run"]
    assert "--execution-mode agent_local" in convert_step["run"]


def test_shadow_workflow_fails_queued_jobs_after_ten_minutes():
    workflow = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    jobs = workflow["jobs"]

    assert "queue-watchdog" in jobs
    watchdog = jobs["queue-watchdog"]
    assert watchdog["runs-on"] == "ubuntu-latest"

    step = watchdog["steps"][0]
    assert step["env"]["QUEUE_TIMEOUT_SECONDS"] == 600
    assert 'job.get("status") == "queued"' in step["run"]


def test_shadow_matrix_job_is_strict_except_wait_step_for_artifact_collection():
    workflow = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    job = workflow["jobs"]["run-unittest-shadow"]

    assert "continue-on-error" not in job
    wait_step = next(
        step for step in job["steps"] if step["name"] == "Wait for CI v2 shadow task"
    )
    assert wait_step["continue-on-error"] is True
