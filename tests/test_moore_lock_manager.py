import os
import subprocess
import textwrap
from pathlib import Path


def test_moore_stale_lock_cleanup_removes_locks_without_running_container(tmp_path):
    script = (
        Path(__file__).parents[1]
        / "third-party/scheduler/moore_test_suite/npu_lock_manager_for_ci.sh"
    )
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    docker = fake_bin / "docker"
    docker.write_text("#!/usr/bin/env bash\nexit 0\n")
    docker.chmod(0o755)

    test_script = tmp_path / "test.sh"
    test_script.write_text(
        textwrap.dedent(
            f"""\
            set -euo pipefail
            source "{script}"
            LOCK_DIR="{tmp_path}/locks"
            mkdir -p "$LOCK_DIR"
            mkdir -p "$LOCK_DIR/server_npu_5.lock"
            cat > "$LOCK_DIR/server_npu_5.lock/info" <<'EOF'
            task_id=old
            timestamp=1
            session_id=25838121515
            hostname=runner
            EOF

            cleanup_stale_npu_locks_for_list server "5"
            [ ! -d "$LOCK_DIR/server_npu_5.lock" ]
            """
        )
    )

    env = {**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}"}
    subprocess.run(["bash", str(test_script)], check=True, env=env)


def test_moore_stale_lock_cleanup_keeps_locks_with_running_container(tmp_path):
    script = (
        Path(__file__).parents[1]
        / "third-party/scheduler/moore_test_suite/npu_lock_manager_for_ci.sh"
    )
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    docker = fake_bin / "docker"
    docker.write_text(
        "#!/usr/bin/env bash\n"
        "if [ \"$1\" = \"ps\" ]; then\n"
        "  echo infiniTensor_moore_UnitTest_25838121515_0\n"
        "fi\n"
    )
    docker.chmod(0o755)

    test_script = tmp_path / "test.sh"
    test_script.write_text(
        textwrap.dedent(
            f"""\
            set -euo pipefail
            source "{script}"
            LOCK_DIR="{tmp_path}/locks"
            mkdir -p "$LOCK_DIR"
            mkdir -p "$LOCK_DIR/server_npu_5.lock"
            cat > "$LOCK_DIR/server_npu_5.lock/info" <<'EOF'
            task_id=running
            timestamp=1
            session_id=25838121515
            hostname=runner
            EOF

            cleanup_stale_npu_locks_for_list server "5"
            [ -d "$LOCK_DIR/server_npu_5.lock" ]
            """
        )
    )

    env = {**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}"}
    subprocess.run(["bash", str(test_script)], check=True, env=env)
