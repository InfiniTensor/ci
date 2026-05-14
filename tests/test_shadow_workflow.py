from pathlib import Path

import yaml


WORKFLOW = Path(".github/workflows/infiniops-ci-v2-shadow.yml")


def test_shadow_workflow_uses_agent_cli():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "CI v2 Shadow" in text
    assert "ci_agent.py submit" in text
    assert "ci_agent.py wait" in text
    assert "ci_agent.py collect" in text
    assert "ci_agent.py cancel" in text
    assert "continue-on-error: true" in text


def test_shadow_workflow_requires_explicit_runner_labels():
    workflow = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    convert_step = workflow["jobs"]["prepare"]["steps"][-1]

    assert "--require-runner-label" in convert_step["run"]
    assert "--execution-mode agent_local" in convert_step["run"]
