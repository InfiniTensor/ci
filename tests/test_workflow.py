from pathlib import Path


WORKFLOW = Path(".github/workflows/infiniops-ci.yml")


def test_nvidia_unit_runs_directly_without_scheduler():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "Run local Unit Test directly" in text
    assert "${{ matrix.platform == 'nvidia' || matrix.platform == 'ascend' }}" in text
    assert "eval \"docker run ${DOCKER_ARGS}\"" in text


def test_scheduler_unit_step_skips_local_unit_platforms():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "Trigger ${{ matrix.platform }} Unit Test Task" in text
    assert "${{ matrix.platform != 'nvidia' && matrix.platform != 'ascend' }}" in text


def test_local_unit_platforms_use_resource_pool_for_auto_gpus():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert 'uses_local_runner = platform in {"nvidia", "ascend"}' in text
    assert 'if not gpu_id_override and not uses_local_runner:' in text
    assert 'gpu_id_override = "all"' in text
    assert 'if not gpu_id_override and raw_gpu_ids == "auto":' in text
