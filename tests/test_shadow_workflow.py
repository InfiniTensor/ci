from pathlib import Path

import yaml


WORKFLOW = Path(".github/workflows/infiniops-ci-v2-shadow.yml")


def test_shadow_workflow_uses_agent_cli():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "CI v2 Shadow" in text
    assert "actions/checkout" not in text
    assert "git checkout --force FETCH_HEAD" in text
    assert (
        "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" in text
    )
    assert "http.https://github.com/.extraheader" not in text
    assert "agent_unavailable" in text
    assert "started transient ci-agent daemon with state dir" in text
    assert 'local probe="${candidate}/locks/${{ matrix.platform }}.lock"' in text
    assert "ci_agent.py submit" in text
    assert "--platform '${{ matrix.platform }}'" in text
    assert "ci_agent.py wait" in text
    assert "ci_agent.py collect" in text
    assert "ci_agent.py cancel" in text
    assert "Fail failed CI v2 shadow task" in text
    assert "continue-on-error: true" in text


def test_shadow_workflow_requires_explicit_runner_labels():
    workflow = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    convert_step = next(
        step
        for step in workflow["jobs"]["prepare"]["steps"]
        if step["name"] == "Convert config to CI v2 shadow matrix JSON"
    )

    assert "--require-runner-label" in convert_step["run"]
    assert "--execution-mode agent_local" in convert_step["run"]


def test_shadow_prepare_preflights_runner_availability_before_matrix_jobs_start():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "Preflight self-hosted runner availability" in text
    assert "MATRIX_JSON: ${{ steps.generate.outputs.matrix_json_for_unittest }}" in text
    assert "CI_RUNNER_STATUS_TOKEN" in text
    assert (
        "CI_RUNNER_STATUS_TOKEN is not configured; skipping preflight runner availability check."
        in text
    )
    assert "GitHub Actions will keep matching jobs queued until a runner is available." in text
    assert "/actions/runners?per_page=100" in text
    assert "No registered self-hosted runner label before starting CI v2 jobs:" in text
    assert (
        "No online self-hosted runner currently available; "
        "matching CI v2 jobs will remain queued:" in text
    )
    assert "job=run-unittest-shadow" in text


def test_shadow_workflow_does_not_create_queue_watchdog_check():
    workflow = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    jobs = workflow["jobs"]
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "queue-watchdog" not in jobs
    assert "Fail queued CI v2 jobs after 30 minutes" not in text
    assert "QUEUE_TIMEOUT_SECONDS" not in text
    assert "POLL_INTERVAL_SECONDS" not in text


def test_shadow_matrix_job_is_strict_except_wait_step_for_artifact_collection():
    workflow = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    job = workflow["jobs"]["run-unittest-shadow"]

    assert "continue-on-error" not in job
    wait_step = next(
        step for step in job["steps"] if step["name"] == "Wait for CI v2 shadow task"
    )
    assert wait_step["continue-on-error"] is True
