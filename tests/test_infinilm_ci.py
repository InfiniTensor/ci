import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "infinilm-ci.yml"
DOCKERFILE = ROOT / "images" / "nvidia" / "Dockerfile.deploy"
BASHRC = ROOT / "images" / "nvidia" / ".bashrc"


class InfiniLMWorkflowContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")

    def test_workflow_uses_infinilm_shared_stack_contract(self):
        self.assertIn("name: InfiniLM Reusable CI", self.workflow)
        self.assertIn(
            'description: "InfiniCore branch to build with the shared Infini stack"',
            self.workflow,
        )
        self.assertNotIn("infinicore_third_party", self.workflow)
        self.assertNotIn("infinicore_nlohmann_json_sha", self.workflow)
        self.assertNotIn("infinicore_spdlog_sha", self.workflow)
        self.assertNotIn("INFINICORE_NLOHMANN_JSON_SHA", self.workflow)
        self.assertNotIn("INFINICORE_SPDLOG_SHA", self.workflow)

    def test_workflow_keeps_core_revision_and_lm_dependency_build_args(self):
        for build_arg in (
            "InfiniCore_BRANCH=${INFINICORE_BRANCH}",
            "InfiniCore_SHA=${INFINICORE_SHA}",
            "INFINILM_JSON_SHA=${INFINILM_JSON_SHA}",
            "INFINILM_SPDLOG_SHA=${INFINILM_SPDLOG_SHA}",
        ):
            with self.subTest(build_arg=build_arg):
                self.assertIn(build_arg, self.workflow)


class NvidiaDeployImageContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dockerfile = DOCKERFILE.read_text(encoding="utf-8")
        cls.bashrc = BASHRC.read_text(encoding="utf-8")

    def test_image_builds_the_shared_stack_from_the_caller_checkout(self):
        self.assertIn("COPY . /workspace/InfiniLM", self.dockerfile)
        self.assertIn("ENV INFINI_BUILD_ROOT=/opt/infini-stack", self.dockerfile)
        self.assertIn("INFINI_ROOT=/opt/infini-stack/prefix", self.dockerfile)
        self.assertIn(
            'LD_LIBRARY_PATH="$INFINI_ROOT/lib:$LD_LIBRARY_PATH"', self.dockerfile
        )
        command = (
            "python3 scripts/build_infini_stack.py "
            "--infinicore-root /workspace/InfiniCore "
            '--build-root "$INFINI_BUILD_ROOT" '
            '--cuda-arch "$CUDA_ARCH" '
            '--jobs "$(nproc)"'
        )
        self.assertIn(f"RUN {command}", self.dockerfile)
        self.assertNotIn("--test", self.dockerfile)

    def test_image_initializes_only_the_shared_stack_submodules(self):
        submodule_lines = [
            line.strip()
            for line in self.dockerfile.splitlines()
            if "git submodule update" in line
        ]
        self.assertEqual(
            submodule_lines,
            [
                "git_with_retry git submodule update --init --recursive --depth 1 "
                "submodules/InfiniRT submodules/InfiniOps submodules/InfiniCCL"
            ],
        )

    def test_each_source_fetch_is_shallow_and_cleans_partial_state(self):
        marker = "git_fetch_commit_with_retry() {"
        sections = self.dockerfile.split(marker)
        self.assertEqual(len(sections) - 1, 2)
        bodies = [section.split("    }; \\", 1)[0] for section in sections[1:]]

        for index, body in enumerate(bodies, start=1):
            with self.subTest(helper=index):
                loop = 'while [ "$i" -le "$attempts" ]; do'
                cleanup = 'rm -rf "$dest";'
                for contract in (
                    'url="$1"; dest="$2"; revision="$3";',
                    'attempts="${GIT_NETWORK_RETRIES:-5}";',
                    "i=1;",
                    loop,
                    cleanup,
                    'git init "$dest"',
                    'git -C "$dest" remote add origin "$url"',
                    'git -C "$dest" fetch --depth 1 origin "$revision"',
                    'git -C "$dest" checkout --detach FETCH_HEAD',
                    'echo "git fetch failed (attempt ${i}/${attempts}): '
                    '$url@$revision -> $dest" >&2;',
                    "sleep $((i * 10));",
                    "i=$((i + 1));",
                    "return 1;",
                ):
                    self.assertIn(contract, body)
                self.assertLess(body.index(loop), body.index(cleanup))
                self.assertLess(body.index(cleanup), body.index('git init "$dest"'))

        self.assertNotIn("git_clone_with_retry", self.dockerfile)
        self.assertNotIn("git clone https://", self.dockerfile)

    def test_image_caches_lm_dependencies_at_the_supplied_gitlink_shas(self):
        for contract in (
            "ARG INFINILM_JSON_SHA",
            "ARG INFINILM_SPDLOG_SHA",
            "git_fetch_commit_with_retry https://github.com/nlohmann/json.git "
            '/opt/third_party_cache/json "$INFINILM_JSON_SHA"',
            "git_fetch_commit_with_retry https://github.com/gabime/spdlog.git "
            '/opt/third_party_cache/spdlog "$INFINILM_SPDLOG_SHA"',
            'git -C third_party/json checkout --detach "$INFINILM_JSON_SHA"',
            'git -C third_party/spdlog checkout --detach "$INFINILM_SPDLOG_SHA"',
        ):
            with self.subTest(contract=contract):
                self.assertIn(contract, self.dockerfile)

    def test_pybind11_cache_is_installed_from_the_lm_project(self):
        workdir = self.dockerfile.index("WORKDIR /workspace/InfiniLM")
        project_copy = self.dockerfile.index(
            "COPY xmake.lua /workspace/InfiniLM/xmake.lua"
        )
        caller_copy = self.dockerfile.index("COPY . /workspace/InfiniLM")
        cache_install = self.dockerfile.index(
            "RUN chmod +x /usr/local/bin/install_xmake_pybind11.sh "
            "&& install_xmake_pybind11.sh"
        )

        self.assertLess(workdir, cache_install)
        self.assertLess(project_copy, cache_install)
        self.assertLess(cache_install, caller_copy)

    def test_image_removes_the_legacy_core_build_path(self):
        for legacy in (
            "flash-attention",
            "CUTLASS",
            "third_party/nlohmann_json",
            "/workspace/InfiniCore/third_party",
            "WORKDIR /workspace/InfiniCore",
            "--nv-gpu",
            "_infinicore",
        ):
            with self.subTest(legacy=legacy):
                self.assertNotIn(legacy, self.dockerfile)
        self.assertEqual(self.dockerfile.count("pip install -e ."), 1)

    def test_lm_build_uses_the_shared_install_prefix(self):
        self.assertIn("WORKDIR /workspace/InfiniLM", self.dockerfile)
        self.assertIn("xmake repo -u", self.dockerfile)
        self.assertIn("install_xmake_pybind11.sh", self.dockerfile)
        self.assertIn("xmake build -y _infinilm", self.dockerfile)
        self.assertIn("xmake install _infinilm", self.dockerfile)
        self.assertIn("pip install -e .", self.dockerfile)

    def test_interactive_shell_preserves_the_image_stack_environment(self):
        for legacy in (
            "/root/.infinici",
            "/root/.infini",
            "InfiniCore/third_party/cutlass",
        ):
            with self.subTest(legacy=legacy):
                self.assertNotIn(legacy, self.bashrc)


if __name__ == "__main__":
    unittest.main()
