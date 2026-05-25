from pathlib import Path


WORKFLOW = Path(".github/workflows/infiniops-ci.yml")


def test_local_unit_runs_through_run_py_without_scheduler():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "Run local Unit Test with host device lease" in text
    assert "${{ matrix.execution_mode == 'agent_local' }}" in text
    assert "PYTHONDONTWRITEBYTECODE=1 python3 .ci/run.py" in text
    assert 'eval "docker run ${DOCKER_ARGS}"' not in text


def test_scheduler_unit_step_skips_local_unit_platforms():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "Trigger ${{ matrix.platform }} Unit Test Task" in text
    assert "${{ matrix.execution_mode != 'agent_local' }}" in text


def test_local_unit_platforms_defer_device_selection_to_run_py():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert 'uses_local_runner = env_opt("EXECUTION_MODE") == "agent_local"' in text
    assert "EXECUTION_MODE: ${{ matrix.execution_mode }}" in text
    assert "if not uses_local_runner:" in text
    assert 'gpu_id_override = "all"' in text
    assert '--job "${{ matrix.id }}"' in text
    assert '--results-dir "${RESULT_DIR}"' in text


def test_workflow_does_not_create_queue_watchdog_check():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "queue-watchdog" not in text
    assert "Fail queued CI jobs after 30 minutes" not in text
    assert "QUEUE_TIMEOUT_SECONDS" not in text
    assert "POLL_INTERVAL_SECONDS" not in text


def test_prepare_preflights_runner_availability_before_matrix_jobs_start():
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
    assert "No registered self-hosted runner label before starting CI jobs:" in text
    assert (
        "No online self-hosted runner currently available; "
        "matching CI jobs will remain queued:" in text
    )
    assert "job=run-unittest" in text
