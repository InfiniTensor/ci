from pathlib import Path


WORKFLOW = Path(".github/workflows/infiniops-ci.yml")


def test_nvidia_unit_runs_directly_without_scheduler():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "Run local Unit Test directly" in text
    assert "${{ matrix.platform == 'nvidia' || matrix.platform == 'iluvatar' || matrix.platform == 'ascend' }}" in text
    assert "eval \"docker run ${DOCKER_ARGS}\"" in text


def test_scheduler_unit_step_skips_local_unit_platforms():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "Trigger ${{ matrix.platform }} Unit Test Task" in text
    assert "${{ matrix.platform != 'nvidia' && matrix.platform != 'iluvatar' && matrix.platform != 'ascend' }}" in text


def test_local_unit_platforms_use_resource_pool_for_auto_gpus():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert 'uses_local_runner = platform in {"nvidia", "iluvatar", "ascend"}' in text
    assert 'if not gpu_id_override and not uses_local_runner:' in text
    assert 'gpu_id_override = "all"' in text
    assert 'if not gpu_id_override and raw_gpu_ids == "auto":' in text


def test_workflow_fails_queued_jobs_after_ten_minutes():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "queue-watchdog" in text
    assert "Fail queued CI jobs after 10 minutes" in text
    assert "MATRIX_JSON: ${{ needs.prepare.outputs.matrix_json_for_unittest }}" in text
    assert "POLL_INTERVAL_SECONDS: 15" in text
    assert "/actions/runs/{run_id}/jobs?per_page=100" in text
    assert "/actions/runners?per_page=100" in text
    assert "CI queued jobs have no online self-hosted runner:" in text
    assert "CI jobs still queued after 10 minutes:" in text
    assert "All expected CI platform jobs completed." in text


def test_prepare_preflights_runner_availability_before_matrix_jobs_start():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "Preflight self-hosted runner availability" in text
    assert "MATRIX_JSON: ${{ steps.generate.outputs.matrix_json_for_unittest }}" in text
    assert "/actions/runners?per_page=100" in text
    assert "No online self-hosted runner before starting CI jobs:" in text
    assert "job=run-unittest" in text
