import subprocess
from pathlib import Path


SCRIPT = Path("scripts/install_ci_agent.sh")


def test_install_ci_agent_script_has_valid_bash_syntax():
    subprocess.run(["bash", "-n", str(SCRIPT)], check=True)


def test_install_ci_agent_script_installs_systemd_service():
    text = SCRIPT.read_text(encoding="utf-8")

    assert "systemctl daemon-reload" in text
    assert "systemctl enable --now ci-agent" in text
    assert "CI_AGENT_STATE_DIR" in text
    assert "CI_AGENT_RUNNER_USER" in text
