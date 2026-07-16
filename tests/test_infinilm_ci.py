import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "infinilm-ci.yml"
DOCKERFILE = ROOT / "images" / "nvidia" / "Dockerfile.deploy"


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
                "git_with_retry git submodule update --init --recursive "
                "submodules/InfiniRT submodules/InfiniOps submodules/InfiniCCL"
            ],
        )

    def test_each_clone_retry_cleans_destination_before_every_attempt(self):
        marker = "git_clone_with_retry() {"
        sections = self.dockerfile.split(marker)
        self.assertEqual(len(sections) - 1, 2)
        bodies = [section.split("    }; \\", 1)[0] for section in sections[1:]]

        for index, body in enumerate(bodies, start=1):
            with self.subTest(helper=index):
                loop = 'while [ "$i" -le "$attempts" ]; do'
                cleanup = 'rm -rf "$dest";'
                clone = 'if git clone "$url" "$dest"; then return 0; fi;'
                for contract in (
                    'attempts="${GIT_NETWORK_RETRIES:-5}";',
                    "i=1;",
                    loop,
                    cleanup,
                    clone,
                    'echo "git clone failed (attempt ${i}/${attempts}): '
                    '$url -> $dest" >&2;',
                    "sleep $((i * 10));",
                    "i=$((i + 1));",
                    "return 1;",
                ):
                    self.assertIn(contract, body)
                self.assertLess(body.index(loop), body.index(cleanup))
                self.assertLess(body.index(cleanup), body.index(clone))

    def test_image_caches_lm_dependencies_at_the_supplied_gitlink_shas(self):
        for contract in (
            "ARG INFINILM_JSON_SHA",
            "ARG INFINILM_SPDLOG_SHA",
            'git -C /opt/third_party_cache/json checkout "$INFINILM_JSON_SHA"',
            'git -C /opt/third_party_cache/spdlog checkout "$INFINILM_SPDLOG_SHA"',
            'git -C third_party/json checkout --detach "$INFINILM_JSON_SHA"',
            'git -C third_party/spdlog checkout --detach "$INFINILM_SPDLOG_SHA"',
        ):
            with self.subTest(contract=contract):
                self.assertIn(contract, self.dockerfile)

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


if __name__ == "__main__":
    unittest.main()
