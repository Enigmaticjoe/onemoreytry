"""
Lightweight repo-invariant tests for the Grand Unified AI Home Lab.

These tests encode safety and reproducibility invariants without requiring
extra dependencies beyond the Python standard library. They complement
validate.sh: validate.sh runs shell-level checks; these tests exercise
structural invariants from Python.

Run with:  python -m unittest discover -s tests -p "test_*.py" -v
"""

import unittest
from pathlib import Path

try:
    import yaml as _yaml
    _YAML_AVAILABLE = True
except ImportError:
    _yaml = None  # type: ignore[assignment]
    _YAML_AVAILABLE = False


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(rel: str) -> str:
    """Return file contents; fail test if file is missing."""
    p = REPO_ROOT / rel
    if not p.exists():
        raise AssertionError(f"Expected file to exist: {rel}")
    return p.read_text(encoding="utf-8", errors="replace")


class TestValidateScript(unittest.TestCase):
    """validate.sh is the primary test suite; guard it from accidental removal."""

    def test_validate_script_exists(self):
        self.assertTrue((REPO_ROOT / "validate.sh").exists(), "validate.sh must exist at repo root")

    def test_validate_script_is_shell(self):
        text = _read("validate.sh")
        self.assertTrue(text.startswith("#!/bin/bash"), "validate.sh must start with #!/bin/bash")

    def test_validate_script_has_test_result_function(self):
        text = _read("validate.sh")
        self.assertIn("test_result()", text, "validate.sh must define test_result()")


class TestKVMOperatorInvariants(unittest.TestCase):
    """Guard safety properties of the KVM operator."""

    def test_app_py_exists(self):
        self.assertTrue((REPO_ROOT / "kvm-operator" / "app.py").exists())

    def test_policy_denylist_has_enough_entries(self):
        text = _read("kvm-operator/policy_denylist.txt")
        active_lines = [
            ln.strip()
            for ln in text.splitlines()
            if ln.strip() and not ln.strip().startswith("#")
        ]
        self.assertGreaterEqual(
            len(active_lines), 20,
            "policy_denylist.txt should have >= 20 active entries to remain meaningful"
        )

    def test_app_py_exposes_paste_endpoint(self):
        text = _read("kvm-operator/app.py")
        self.assertIn("/kvm/paste/{target}", text, "paste endpoint must exist in app.py")

    def test_app_py_exposes_targets_endpoint(self):
        text = _read("kvm-operator/app.py")
        self.assertIn("/kvm/targets", text, "targets endpoint must exist in app.py")

    def test_env_example_documents_required_settings(self):
        text = _read("kvm-operator/.env.example")
        required_keys = [
            "SESSION_TTL",
            "NANOKVM_AUTH_MODE",
            "VISION_MODEL",
            "ALLOW_DANGEROUS",
            "LOG_LEVEL",
        ]
        for key in required_keys:
            self.assertIn(key, text, f"{key} must be documented in kvm-operator/.env.example")

    def test_require_approval_default_is_true(self):
        text = _read("kvm-operator/.env.example")
        self.assertIn("REQUIRE_APPROVAL=true", text, "REQUIRE_APPROVAL must default to true in .env.example")

    def test_app_py_has_max_payload_length_guard(self):
        text = _read("kvm-operator/app.py")
        self.assertIn("MAX_PAYLOAD_LENGTH", text, "app.py must enforce MAX_PAYLOAD_LENGTH")


class TestNodeAComposeInvariants(unittest.TestCase):
    """Guard the Node A Brain stack compose structure."""

    def test_compose_exists(self):
        self.assertTrue((REPO_ROOT / "node-a-vllm" / "docker-compose.yml").exists())

    def test_compose_yaml_valid(self):
        self.skipTest("pyyaml not installed") if not _YAML_AVAILABLE else None
        text = _read("node-a-vllm/docker-compose.yml")
        self.assertIsNotNone(_yaml.safe_load(text), "node-a-vllm/docker-compose.yml must be valid YAML")

    def test_compose_defines_brain_vllm(self):
        text = _read("node-a-vllm/docker-compose.yml")
        self.assertIn("brain-vllm", text, "brain-vllm service must be defined")

    def test_compose_defines_brain_qdrant(self):
        text = _read("node-a-vllm/docker-compose.yml")
        self.assertIn("brain-qdrant", text)

    def test_compose_defines_brain_openwebui(self):
        text = _read("node-a-vllm/docker-compose.yml")
        self.assertIn("brain-openwebui", text)

    def test_env_example_exists(self):
        self.assertTrue((REPO_ROOT / "node-a-vllm" / ".env.example").exists())


class TestUnraidStackInvariants(unittest.TestCase):
    """Guard the Unraid management + media + AI stacks."""

    def test_management_compose_exists(self):
        self.assertTrue((REPO_ROOT / "unraid" / "docker-compose.yml").exists())

    def test_management_compose_yaml_valid(self):
        self.skipTest("pyyaml not installed") if not _YAML_AVAILABLE else None
        text = _read("unraid/docker-compose.yml")
        self.assertIsNotNone(_yaml.safe_load(text))

    def test_media_stack_exists(self):
        self.assertTrue(
            (REPO_ROOT / "unraid" / "media-stack.yml").exists(),
            "unraid/media-stack.yml must exist (DUMB AIO media stack)"
        )

    def test_media_stack_yaml_valid(self):
        self.skipTest("pyyaml not installed") if not _YAML_AVAILABLE else None
        text = _read("unraid/media-stack.yml")
        self.assertIsNotNone(_yaml.safe_load(text))

    def test_ai_stack_exists(self):
        self.assertTrue(
            (REPO_ROOT / "unraid" / "ai-stack.yml").exists(),
            "unraid/ai-stack.yml must exist (Ollama + Open WebUI)"
        )

    def test_ai_stack_yaml_valid(self):
        self.skipTest("pyyaml not installed") if not _YAML_AVAILABLE else None
        text = _read("unraid/ai-stack.yml")
        self.assertIsNotNone(_yaml.safe_load(text))

    def test_env_example_documents_media_vars(self):
        text = _read("unraid/.env.example")
        for key in ("PUID", "PGID", "APPDATA_PATH", "TZ"):
            self.assertIn(key, text, f"{key} must be in unraid/.env.example")

    def test_env_example_documents_real_debrid(self):
        text = _read("unraid/.env.example")
        self.assertIn("REAL_DEBRID_API_KEY", text, "REAL_DEBRID_API_KEY must be documented in unraid/.env.example")


class TestCIWorkflowInvariants(unittest.TestCase):
    """Guard the GitHub Actions CI configuration."""

    def test_validate_workflow_exists(self):
        self.assertTrue(
            (REPO_ROOT / ".github" / "workflows" / "validate.yml").exists(),
            ".github/workflows/validate.yml must exist"
        )

    def test_validate_workflow_yaml_valid(self):
        self.skipTest("pyyaml not installed") if not _YAML_AVAILABLE else None
        text = _read(".github/workflows/validate.yml")
        self.assertIsNotNone(_yaml.safe_load(text))

    def test_validate_workflow_runs_validate_sh(self):
        text = _read(".github/workflows/validate.yml")
        self.assertIn("validate.sh", text, "CI workflow must invoke validate.sh")

    def test_validate_workflow_runs_python_tests(self):
        text = _read(".github/workflows/validate.yml")
        self.assertIn("unittest", text, "CI workflow must invoke Python unittest discovery")


class TestArchitectureDoc(unittest.TestCase):
    """Guard the canonical architecture document."""

    def test_architecture_doc_exists(self):
        self.assertTrue(
            (REPO_ROOT / "docs" / "ARCHITECTURE.md").exists(),
            "docs/ARCHITECTURE.md must exist"
        )

    def test_architecture_doc_has_mermaid(self):
        text = _read("docs/ARCHITECTURE.md")
        self.assertIn("```mermaid", text, "ARCHITECTURE.md must contain a Mermaid diagram")

    def test_architecture_doc_covers_all_nodes(self):
        text = _read("docs/ARCHITECTURE.md")
        for node in ("Node A", "Node B", "Node C", "Node D", "Unraid"):
            self.assertIn(node, text, f"ARCHITECTURE.md must cover {node}")


if __name__ == "__main__":
    unittest.main()
