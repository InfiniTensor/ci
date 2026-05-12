from pathlib import Path

import yaml


def test_infiniops_workflow_only_defines_unit_ci_job_types():
    workflow_path = Path(".github/workflows/infiniops-ci.yml")
    workflow = yaml.safe_load(workflow_path.read_text(encoding="utf-8"))

    jobs = workflow["jobs"]

    assert "run-unittest" in jobs
    assert "run-smoketest" not in jobs
    assert "run-performancetest" not in jobs

    prepare_outputs = jobs["prepare"]["outputs"]
    assert "matrix_json_for_unittest" in prepare_outputs
    assert "matrix_json_for_smoketest" not in prepare_outputs
    assert "matrix_json_for_performancetest" not in prepare_outputs
