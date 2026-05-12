from pathlib import Path


WORKFLOW = Path(".github/workflows/infiniops-ci.yml")


def test_nvidia_unit_runs_directly_without_scheduler():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "Run nvidia Unit Test directly" in text
    assert "${{ matrix.platform == 'nvidia' }}" in text
    assert "eval \"docker run ${DOCKER_ARGS}\"" in text


def test_scheduler_unit_step_skips_nvidia():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "Trigger ${{ matrix.platform }} Unit Test Task" in text
    assert "${{ matrix.platform != 'nvidia' }}" in text
