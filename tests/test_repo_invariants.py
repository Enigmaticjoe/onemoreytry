"""
Lightweight repo-invariant tests for the Grand Unified AI Home Lab.

These tests encode safety and reproducibility invariants without requiring
extra dependencies beyond the Python standard library. They complement
validate.sh: validate.sh runs shell-level checks; these tests exercise
structural invariants from Python.

Run with:  python -m unittest discover -s tests -p "test_*.py" -v
"""

import unittest
import glob as _glob
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


class TestAgentGovernanceInvariants(unittest.TestCase):
    """Guard the Agent Instruction Framework configuration and hooks."""

    def test_agent_config_exists(self):
        self.assertTrue(
            (REPO_ROOT / "agent-governance" / "agent-config.yml").exists(),
            "agent-governance/agent-config.yml must exist"
        )

    def test_agent_config_yaml_valid(self):
        if not _YAML_AVAILABLE:
            self.skipTest("pyyaml not installed")
        text = _read("agent-governance/agent-config.yml")
        self.assertIsNotNone(_yaml.safe_load(text), "agent-config.yml must be valid YAML")

    def test_agent_config_has_required_keys(self):
        if not _YAML_AVAILABLE:
            self.skipTest("pyyaml not installed")
        data = _yaml.safe_load(_read("agent-governance/agent-config.yml"))
        required = ["schema_version", "execution_modes", "roles", "quality_gates", "hard_blocks"]
        for key in required:
            self.assertIn(key, data, f"agent-config.yml must contain '{key}'")

    def test_agent_config_defines_all_roles(self):
        if not _YAML_AVAILABLE:
            self.skipTest("pyyaml not installed")
        data = _yaml.safe_load(_read("agent-governance/agent-config.yml"))
        roles = data.get("roles", {})
        for role in ("planner", "operator", "auditor"):
            self.assertIn(role, roles, f"agent-config.yml must define the '{role}' role")

    def test_agent_config_defines_all_execution_modes(self):
        if not _YAML_AVAILABLE:
            self.skipTest("pyyaml not installed")
        data = _yaml.safe_load(_read("agent-governance/agent-config.yml"))
        modes = data.get("execution_modes", {}).get("allowed", [])
        for mode in ("SAFE", "DRYRUN", "ARMED"):
            self.assertIn(mode, modes, f"agent-config.yml must allow execution mode '{mode}'")

    def test_agent_config_has_hard_blocks(self):
        if not _YAML_AVAILABLE:
            self.skipTest("pyyaml not installed")
        data = _yaml.safe_load(_read("agent-governance/agent-config.yml"))
        blocks = data.get("hard_blocks", [])
        self.assertGreaterEqual(
            len(blocks), 5,
            "agent-config.yml must define at least 5 hard blocks"
        )

    def test_agent_config_escalation_requires_approval(self):
        if not _YAML_AVAILABLE:
            self.skipTest("pyyaml not installed")
        data = _yaml.safe_load(_read("agent-governance/agent-config.yml"))
        self.assertTrue(
            data.get("execution_modes", {}).get("escalation_requires_human_approval"),
            "execution mode escalation must require human approval"
        )

    def test_pre_commit_hook_exists(self):
        self.assertTrue(
            (REPO_ROOT / "agent-governance" / "hooks" / "pre-commit").exists(),
            "agent-governance/hooks/pre-commit must exist"
        )

    def test_pre_commit_hook_is_shell(self):
        text = _read("agent-governance/hooks/pre-commit")
        self.assertTrue(
            text.startswith("#!/"),
            "pre-commit hook must start with a shebang line"
        )

    def test_pre_commit_hook_calls_destructive_check(self):
        text = _read("agent-governance/hooks/pre-commit")
        self.assertIn("destructive", text.lower(), "pre-commit hook must call destructive change detection")

    def test_pre_commit_hook_checks_yaml(self):
        text = _read("agent-governance/hooks/pre-commit")
        self.assertIn("yaml", text.lower(), "pre-commit hook must validate YAML syntax")

    def test_pre_commit_hook_checks_security(self):
        text = _read("agent-governance/hooks/pre-commit")
        self.assertTrue(
            "bandit" in text or "ruff" in text or "flake8" in text,
            "pre-commit hook must invoke a Python linter or security scanner"
        )

    def test_destructive_check_script_exists(self):
        self.assertTrue(
            (REPO_ROOT / "agent-governance" / "hooks" / "destructive-check.sh").exists(),
            "agent-governance/hooks/destructive-check.sh must exist"
        )

    def test_destructive_check_blocks_force_push(self):
        text = _read("agent-governance/hooks/destructive-check.sh")
        self.assertIn("force", text.lower(), "destructive-check.sh must block force-push")

    def test_destructive_check_blocks_rm_rf(self):
        text = _read("agent-governance/hooks/destructive-check.sh")
        self.assertIn("rm", text, "destructive-check.sh must detect rm -rf patterns")

    def test_pre_commit_config_exists(self):
        self.assertTrue(
            (REPO_ROOT / ".pre-commit-config.yaml").exists(),
            ".pre-commit-config.yaml must exist"
        )

    def test_pre_commit_config_yaml_valid(self):
        if not _YAML_AVAILABLE:
            self.skipTest("pyyaml not installed")
        text = _read(".pre-commit-config.yaml")
        self.assertIsNotNone(_yaml.safe_load(text), ".pre-commit-config.yaml must be valid YAML")

    def test_pre_commit_config_includes_destructive_detection(self):
        text = _read(".pre-commit-config.yaml")
        self.assertIn("destructive", text.lower(), ".pre-commit-config.yaml must include destructive-change-detection")

    def test_pre_commit_config_includes_security_hook(self):
        text = _read(".pre-commit-config.yaml")
        self.assertTrue(
            "bandit" in text or "ruff" in text,
            ".pre-commit-config.yaml must include a Python security or linting hook"
        )


class TestSovereignAIStackInvariants(unittest.TestCase):
    """Guard the sovereign AI homelab stack files."""

    def test_brain_compose_exists(self):
        self.assertTrue(
            (REPO_ROOT / "agent-governance" / "sovereign-brain-compose.yml").exists(),
            "agent-governance/sovereign-brain-compose.yml must exist"
        )

    def test_brain_compose_yaml_valid(self):
        if not _YAML_AVAILABLE:
            self.skipTest("pyyaml not installed")
        text = _read("agent-governance/sovereign-brain-compose.yml")
        self.assertIsNotNone(_yaml.safe_load(text), "sovereign-brain-compose.yml must be valid YAML")

    def test_brain_compose_defines_ollama(self):
        text = _read("agent-governance/sovereign-brain-compose.yml")
        self.assertIn("brain-ollama", text, "sovereign-brain-compose.yml must define brain-ollama")

    def test_brain_compose_defines_qdrant(self):
        text = _read("agent-governance/sovereign-brain-compose.yml")
        self.assertIn("brain-qdrant", text, "sovereign-brain-compose.yml must define brain-qdrant")

    def test_brain_compose_defines_openwebui(self):
        text = _read("agent-governance/sovereign-brain-compose.yml")
        self.assertIn("brain-openwebui", text, "sovereign-brain-compose.yml must define brain-openwebui")

    def test_brain_compose_defines_governance(self):
        text = _read("agent-governance/sovereign-brain-compose.yml")
        self.assertIn("brain-governance", text, "sovereign-brain-compose.yml must define brain-governance sidecar")

    def test_brain_compose_no_hardcoded_secrets(self):
        text = _read("agent-governance/sovereign-brain-compose.yml")
        import re
        # Check that secret values use variable substitution, not literal strings
        self.assertNotRegex(
            text,
            r'SECRET_KEY:\s+[a-zA-Z0-9]{16,}',
            "sovereign-brain-compose.yml must not contain hardcoded secret values"
        )

    def test_unraid_sovereign_stack_exists(self):
        self.assertTrue(
            (REPO_ROOT / "unraid" / "sovereign-ai-stack.yml").exists(),
            "unraid/sovereign-ai-stack.yml must exist"
        )

    def test_unraid_sovereign_stack_yaml_valid(self):
        if not _YAML_AVAILABLE:
            self.skipTest("pyyaml not installed")
        text = _read("unraid/sovereign-ai-stack.yml")
        self.assertIsNotNone(_yaml.safe_load(text), "unraid/sovereign-ai-stack.yml must be valid YAML")

    def test_unraid_sovereign_stack_defines_anythingllm(self):
        text = _read("unraid/sovereign-ai-stack.yml")
        self.assertIn("anythingllm", text, "unraid/sovereign-ai-stack.yml must define anythingllm")

    def test_unraid_sovereign_stack_defines_qdrant(self):
        text = _read("unraid/sovereign-ai-stack.yml")
        self.assertIn("qdrant", text, "unraid/sovereign-ai-stack.yml must define qdrant")

    def test_unraid_sovereign_stack_defines_unraid_mcp(self):
        text = _read("unraid/sovereign-ai-stack.yml")
        self.assertIn("unraid-mcp", text, "unraid/sovereign-ai-stack.yml must define unraid-mcp")

    def test_unraid_sovereign_stack_requires_approval(self):
        text = _read("unraid/sovereign-ai-stack.yml")
        self.assertIn("REQUIRE_APPROVAL", text, "unraid/sovereign-ai-stack.yml must enforce REQUIRE_APPROVAL")


class TestDeployRenegadeNodeScript(unittest.TestCase):
    """Guard the Brain Node deployment script."""

    def test_deploy_script_exists(self):
        self.assertTrue(
            (REPO_ROOT / "scripts" / "deploy-renegade-node.sh").exists(),
            "scripts/deploy-renegade-node.sh must exist"
        )

    def test_deploy_script_is_shell(self):
        text = _read("scripts/deploy-renegade-node.sh")
        self.assertTrue(text.startswith("#!/"), "deploy-renegade-node.sh must start with a shebang")

    def test_deploy_script_has_try_and_verify(self):
        text = _read("scripts/deploy-renegade-node.sh")
        self.assertIn("try_and_verify", text, "deploy-renegade-node.sh must define try_and_verify")

    def test_deploy_script_supports_dry_run(self):
        text = _read("scripts/deploy-renegade-node.sh")
        self.assertIn("dry-run", text, "deploy-renegade-node.sh must support --dry-run")

    def test_deploy_script_configures_max_retries(self):
        text = _read("scripts/deploy-renegade-node.sh")
        self.assertIn("MAX_RETRIES", text, "deploy-renegade-node.sh must define MAX_RETRIES")

    def test_deploy_script_does_not_hardcode_secrets(self):
        text = _read("scripts/deploy-renegade-node.sh")
        import re
        self.assertNotRegex(
            text,
            r'(password|secret|api_key)\s*=\s*["\'][^"\']{8,}',
            "deploy-renegade-node.sh must not contain hardcoded secrets"
        )


class TestAgentGovernanceDocs(unittest.TestCase):
    """Guard the Agent Governance and Sovereign AI Architecture documentation."""

    def test_agent_governance_doc_exists(self):
        self.assertTrue(
            (REPO_ROOT / "docs" / "AGENT_GOVERNANCE.md").exists(),
            "docs/AGENT_GOVERNANCE.md must exist"
        )

    def test_agent_governance_doc_covers_execution_modes(self):
        text = _read("docs/AGENT_GOVERNANCE.md")
        for mode in ("SAFE", "DRYRUN", "ARMED"):
            self.assertIn(mode, text, f"AGENT_GOVERNANCE.md must document execution mode '{mode}'")

    def test_agent_governance_doc_covers_roles(self):
        text = _read("docs/AGENT_GOVERNANCE.md")
        for role in ("planner", "operator", "auditor"):
            self.assertIn(role, text, f"AGENT_GOVERNANCE.md must document role '{role}'")

    def test_agent_governance_doc_covers_hard_blocks(self):
        text = _read("docs/AGENT_GOVERNANCE.md")
        self.assertIn("Hard Block", text, "AGENT_GOVERNANCE.md must document hard blocks")

    def test_agent_governance_doc_covers_isolation(self):
        text = _read("docs/AGENT_GOVERNANCE.md")
        self.assertIn("isolation", text.lower(), "AGENT_GOVERNANCE.md must cover per-agent isolation")

    def test_agent_governance_doc_covers_memory_layer(self):
        text = _read("docs/AGENT_GOVERNANCE.md")
        self.assertIn("Memory", text, "AGENT_GOVERNANCE.md must cover the agent memory layer")

    def test_sovereign_architecture_doc_exists(self):
        self.assertTrue(
            (REPO_ROOT / "docs" / "SOVEREIGN_AI_ARCHITECTURE.md").exists(),
            "docs/SOVEREIGN_AI_ARCHITECTURE.md must exist"
        )

    def test_sovereign_architecture_doc_has_mermaid(self):
        text = _read("docs/SOVEREIGN_AI_ARCHITECTURE.md")
        self.assertIn("```mermaid", text, "SOVEREIGN_AI_ARCHITECTURE.md must contain a Mermaid diagram")

    def test_sovereign_architecture_doc_covers_brain_and_brawn(self):
        text = _read("docs/SOVEREIGN_AI_ARCHITECTURE.md")
        for node in ("Brain Node", "Brawn Node"):
            self.assertIn(node, text, f"SOVEREIGN_AI_ARCHITECTURE.md must cover {node}")

    def test_sovereign_architecture_doc_covers_codeact(self):
        text = _read("docs/SOVEREIGN_AI_ARCHITECTURE.md")
        self.assertIn("CodeAct", text, "SOVEREIGN_AI_ARCHITECTURE.md must cover the CodeAct loop")

    def test_sovereign_architecture_doc_covers_qdrant(self):
        text = _read("docs/SOVEREIGN_AI_ARCHITECTURE.md")
        self.assertIn("Qdrant", text, "SOVEREIGN_AI_ARCHITECTURE.md must reference Qdrant")


class TestFreshRebuild2026Invariants(unittest.TestCase):
    """Guard the Phase-1 Fresh Rebuild 2026 blueprint.

    Rules:
    - Exactly one Open WebUI compose file exists in fresh-rebuild-2026/.
    - No forbidden Phase-1 services appear in any compose file under fresh-rebuild-2026/.
    - Each node directory has a .env.example file.
    - Core scripts exist and are executable.
    - Architecture and layman's guide docs exist.
    """

    BASE = REPO_ROOT / "fresh-rebuild-2026"

    # Services that must NOT appear in Phase-1 compose files.
    FORBIDDEN = ("litellm", "openclaw", "vllm", "kvm-operator", "kvm_operator")

    def _all_compose_texts(self):
        """Return list of (path, text) for every compose YAML under fresh-rebuild-2026."""
        results = []
        for p in _glob.glob(str(self.BASE / "**" / "*.yml"), recursive=True):
            results.append((p, Path(p).read_text()))
        return results

    # ── Structural checks ──────────────────────────────────────────────────────

    def test_node_a_compose_exists(self):
        self.assertTrue(
            (self.BASE / "node-a" / "compose.yml").exists(),
            "fresh-rebuild-2026/node-a/compose.yml must exist"
        )

    def test_node_b_infra_stack_exists(self):
        self.assertTrue(
            (self.BASE / "node-b" / "stacks" / "01-infra.yml").exists(),
            "fresh-rebuild-2026/node-b/stacks/01-infra.yml must exist"
        )

    def test_node_b_ai_stack_exists(self):
        self.assertTrue(
            (self.BASE / "node-b" / "stacks" / "02-ai.yml").exists(),
            "fresh-rebuild-2026/node-b/stacks/02-ai.yml must exist"
        )

    def test_node_c_compose_exists(self):
        self.assertTrue(
            (self.BASE / "node-c" / "compose.yml").exists(),
            "fresh-rebuild-2026/node-c/compose.yml must exist"
        )

    # ── .env.example per node ──────────────────────────────────────────────────

    def test_node_a_env_example_exists(self):
        self.assertTrue(
            (self.BASE / "node-a" / ".env.example").exists(),
            "fresh-rebuild-2026/node-a/.env.example must exist"
        )

    def test_node_b_env_example_exists(self):
        self.assertTrue(
            (self.BASE / "node-b" / ".env.example").exists(),
            "fresh-rebuild-2026/node-b/.env.example must exist"
        )

    def test_node_c_env_example_exists(self):
        self.assertTrue(
            (self.BASE / "node-c" / ".env.example").exists(),
            "fresh-rebuild-2026/node-c/.env.example must exist"
        )

    def test_inventory_env_example_exists(self):
        self.assertTrue(
            (self.BASE / "inventory" / "node-inventory.env.example").exists(),
            "fresh-rebuild-2026/inventory/node-inventory.env.example must exist"
        )

    # ── Exactly one Open WebUI instance ───────────────────────────────────────

    def test_exactly_one_open_webui_compose(self):
        webui_files = [
            p for p, text in self._all_compose_texts()
            if "open-webui" in text or "openwebui" in text.lower()
        ]
        self.assertEqual(
            len(webui_files), 1,
            f"Phase 1 must have exactly one Open WebUI compose; found {len(webui_files)}: {webui_files}"
        )

    def test_open_webui_is_on_node_c(self):
        node_c_compose = self.BASE / "node-c" / "compose.yml"
        text = node_c_compose.read_text()
        self.assertIn(
            "open-webui", text,
            "Open WebUI must be defined in node-c/compose.yml"
        )

    # ── No forbidden services ──────────────────────────────────────────────────

    def test_no_litellm_in_phase1(self):
        for path, text in self._all_compose_texts():
            self.assertNotIn(
                "litellm", text.lower(),
                f"Phase 1 must NOT include litellm; found in {path}"
            )

    def test_no_openclaw_in_phase1(self):
        for path, text in self._all_compose_texts():
            self.assertNotIn(
                "openclaw", text.lower(),
                f"Phase 1 must NOT include openclaw; found in {path}"
            )

    def test_no_vllm_in_phase1(self):
        for path, text in self._all_compose_texts():
            self.assertNotIn(
                "vllm", text.lower(),
                f"Phase 1 must NOT include vllm; found in {path}"
            )

    def test_no_kvm_operator_in_phase1(self):
        for path, text in self._all_compose_texts():
            for forbidden in ("kvm-operator", "kvm_operator"):
                self.assertNotIn(
                    forbidden, text.lower(),
                    f"Phase 1 must NOT include kvm-operator; found in {path}"
                )

    # ── YAML validity ─────────────────────────────────────────────────────────

    def test_all_phase1_composes_are_valid_yaml(self):
        for path, text in self._all_compose_texts():
            try:
                _yaml.safe_load(text)
            except (_yaml.YAMLError if _yaml else Exception) as exc:
                self.fail(f"YAML parse error in {path}: {exc}")

    # ── No hardcoded secrets ──────────────────────────────────────────────────

    def test_no_hardcoded_postgres_password_in_composes(self):
        """Compose files must use env-var substitution, not literal 'postgres' passwords."""
        for path, text in self._all_compose_texts():
            self.assertNotIn(
                "POSTGRES_PASSWORD=postgres", text,
                f"Hardcoded postgres:postgres password found in {path} — use ${{POSTGRES_PASSWORD}}"
            )

    # ── Scripts ───────────────────────────────────────────────────────────────

    def test_preflight_script_exists(self):
        self.assertTrue(
            (self.BASE / "scripts" / "preflight.sh").exists(),
            "fresh-rebuild-2026/scripts/preflight.sh must exist"
        )

    def test_deploy_all_script_exists(self):
        self.assertTrue(
            (self.BASE / "scripts" / "deploy-all.sh").exists(),
            "fresh-rebuild-2026/scripts/deploy-all.sh must exist"
        )

    def test_scripts_support_dryrun(self):
        for script in ("preflight.sh", "deploy-all.sh"):
            text = (self.BASE / "scripts" / script).read_text()
            self.assertIn(
                "DRYRUN", text,
                f"fresh-rebuild-2026/scripts/{script} must support DRYRUN mode"
            )

    def test_per_node_deploy_scripts_exist(self):
        for node in ("node-a", "node-b", "node-c"):
            p = self.BASE / "scripts" / node / "deploy.sh"
            self.assertTrue(p.exists(), f"fresh-rebuild-2026/scripts/{node}/deploy.sh must exist")

    def test_per_node_verify_scripts_exist(self):
        for node in ("node-a", "node-b", "node-c"):
            p = self.BASE / "scripts" / node / "verify.sh"
            self.assertTrue(p.exists(), f"fresh-rebuild-2026/scripts/{node}/verify.sh must exist")

    def test_scripts_read_inventory(self):
        for script in ("preflight.sh", "deploy-all.sh"):
            text = (self.BASE / "scripts" / script).read_text()
            self.assertIn(
                "node-inventory.env", text,
                f"fresh-rebuild-2026/scripts/{script} must read inventory/node-inventory.env"
            )

    # ── Docs ──────────────────────────────────────────────────────────────────

    def test_architecture_doc_exists(self):
        self.assertTrue(
            (self.BASE / "docs" / "ARCHITECTURE_FRESH_REBUILD_2026.md").exists(),
            "fresh-rebuild-2026/docs/ARCHITECTURE_FRESH_REBUILD_2026.md must exist"
        )

    def test_architecture_doc_has_port_map(self):
        text = (self.BASE / "docs" / "ARCHITECTURE_FRESH_REBUILD_2026.md").read_text()
        self.assertIn("11435", text, "Architecture doc must include Node A Ollama port 11435")
        self.assertIn("11434", text, "Architecture doc must include Node B Ollama port 11434")
        self.assertIn("3000", text, "Architecture doc must include Node C Open WebUI port 3000")

    def test_node_setup_guide_exists(self):
        self.assertTrue(
            (self.BASE / "docs" / "NODE_SETUP_GUIDE.md").exists(),
            "fresh-rebuild-2026/docs/NODE_SETUP_GUIDE.md (layman's setup guide) must exist"
        )

    def test_apps_and_services_guide_exists(self):
        self.assertTrue(
            (self.BASE / "docs" / "APPS_AND_SERVICES_GUIDE.md").exists(),
            "fresh-rebuild-2026/docs/APPS_AND_SERVICES_GUIDE.md (apps config guide) must exist"
        )

    def test_node_setup_guide_covers_all_nodes(self):
        text = (self.BASE / "docs" / "NODE_SETUP_GUIDE.md").read_text()
        for node in ("Node A", "Node B", "Node C", "Node D"):
            self.assertIn(node, text, f"NODE_SETUP_GUIDE.md must cover {node}")

    def test_apps_guide_covers_key_services(self):
        text = (self.BASE / "docs" / "APPS_AND_SERVICES_GUIDE.md").read_text()
        for service in ("Portainer", "Ollama", "Open WebUI", "n8n", "Uptime Kuma", "Watchtower", "Dozzle"):
            self.assertIn(service, text, f"APPS_AND_SERVICES_GUIDE.md must cover {service}")


if __name__ == "__main__":
    unittest.main()
