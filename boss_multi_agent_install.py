#!/usr/bin/env python3
"""
Boss-Driven Homelab Install Assistant for Fedora 44 (cosmic nightly) — Production Release
=========================================================================

Orchestrated, multi-agent installer for the onemoreytry homelab stack.
A central BossAI coordinates Minion agents, each handling a discrete
installation phase.  Self-correcting: on failure the Boss searches for
fixes and offers a retry.

Fedora 44 (cosmic nightly) specifics
--------------------------------------
* DNF5 is the ONLY package manager (no dnf4/yum fallback).
* Docker repo added via ``dnf5 config-manager addrepo --from-repofile=``.
* Python packages installed inside a venv (PEP 668 compliance).
* SELinux stays Enforcing — proper file contexts applied.
* Wayland-only GNOME 50 assumed (no X11 tools).

Usage
-----
Interactive::

    sudo python3 boss_multi_agent_install.py

Non-interactive::

    sudo python3 boss_multi_agent_install.py --non-interactive \\
        --config-file /path/to/config.env --auto-start-chat

One-click with systemd service install::

    sudo python3 boss_multi_agent_install.py --non-interactive \\
        --auto-start-chat --install-service
"""

from __future__ import annotations

import argparse
import getpass
import json
import logging
import os
import shutil
import subprocess
import sys
import textwrap
import time
import urllib.parse as urlparse
import urllib.request as urlrequest
from html import unescape
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

from common_utils import (
    prompt_input,
    search_web,
    fetch_first_paragraph,
    answer_query,
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

VERSION = "2.0.0"

AVATAR_DATA_URI = (
    "data:image/svg+xml;base64,"
    "PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxMDAiIGhlaWdodD0iMTAwIj4K"
    "PHJlY3Qgd2lkdGg9IjEwMCUiIGhlaWdodD0iMTAwJSIgZmlsbD0iIzBhMGEwYSIvPgo8Y2lyY2xlIGN4PSI1MCIg"
    "Y3k9IjUwIiByPSI0MCIgZmlsbD0iIzAwMjIyMiIgc3Ryb2tlPSIjMDBmZmZmIiBzdHJva2Utd2lkdGg9IjQiLz4K"
    "PGNpcmNsZSBjeD0iNTAiIGN5PSI1MCIgcj0iMTUiIGZpbGw9IiMwMGZmZmYiLz4KPHBhdGggZD0iTTUwIDIwIEw2"
    "MCAzNSBMNDAgMzUgWiIgZmlsbD0iIzAwZmZmZiIgLz4KPC9zdmc+"
)

DOCKER_REPO_URL = "https://download.docker.com/linux/fedora/docker-ce.repo"
CHAT_PORT = 8008
VENV_PATH = Path("/opt/homelab/venv")
INSTALL_ROOT = Path("/opt/homelab")

# Logging — structured with timestamps
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("boss")


# ---------------------------------------------------------------------------
# Core utilities
# ---------------------------------------------------------------------------

def run_cmd(
    cmd: List[str],
    timeout: int = 120,
    check: bool = False,
    env: Optional[Dict[str, str]] = None,
) -> Tuple[int, str]:
    """Run a command, return (exit_code, combined_output).

    Args:
        cmd: Command and arguments.
        timeout: Max seconds before killing the process.
        check: If True, raise RuntimeError on non-zero exit.
        env: Optional environment dict (merged with os.environ).

    Returns:
        Tuple of (return_code, stdout+stderr).
    """
    run_env = {**os.environ, **(env or {})}
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=run_env,
        )
        output = (proc.stdout or "") + (proc.stderr or "")
        if check and proc.returncode != 0:
            raise RuntimeError(
                f"Command failed ({proc.returncode}): {' '.join(cmd)}\n{output}"
            )
        return proc.returncode, output
    except FileNotFoundError:
        msg = f"Command not found: {cmd[0]}"
        if check:
            raise RuntimeError(msg)
        return 127, msg
    except subprocess.TimeoutExpired:
        msg = f"Command timed out after {timeout}s: {' '.join(cmd)}"
        if check:
            raise RuntimeError(msg)
        return 124, msg


def ensure_root() -> None:
    """Exit if not running as root."""
    if os.geteuid() != 0:
        sys.exit("ERROR: This script must be run as root (sudo).")


def write_file(
    path: Path,
    content: str,
    ask_overwrite: bool = True,
    mode: int = 0o600,
) -> None:
    """Write content to a file with proper permissions.

    Files containing secrets get 0600 by default.  Parent dirs are
    created automatically.  SELinux context is restored after write.
    """
    if path.exists() and ask_overwrite:
        answer = prompt_input(f"File {path} exists. Overwrite? (y/N)", "N")
        if answer.lower() != "y":
            log.info("Skipping %s", path)
            return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    os.chmod(path, mode)
    # Restore SELinux context (non-fatal if restorecon missing)
    if shutil.which("restorecon"):
        run_cmd(["restorecon", "-v", str(path)])
    log.info("Wrote %s (mode %o)", path, mode)


# ---------------------------------------------------------------------------
# Package management — DNF5 only
# ---------------------------------------------------------------------------

def dnf5_available() -> bool:
    """Verify dnf5 is present (required on Fedora 44)."""
    return shutil.which("dnf5") is not None


def pkg_installed(name: str) -> bool:
    """Check if an RPM package is installed."""
    code, _ = run_cmd(["rpm", "-q", name])
    return code == 0


def dnf_install(packages: List[str]) -> None:
    """Install packages via dnf5, skipping already-installed ones."""
    missing = [p for p in packages if not pkg_installed(p)]
    if not missing:
        log.info("All packages present: %s", " ".join(packages))
        return
    log.info("Installing via dnf5: %s", " ".join(missing))
    run_cmd(["dnf5", "install", "-y", "--setopt=install_weak_deps=False"] + missing,
            timeout=900, check=True)
    log.info("Package install complete.")


# ---------------------------------------------------------------------------
# Web search helpers (DuckDuckGo Lite — best-effort)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Boss / Minion orchestration
# ---------------------------------------------------------------------------

class BossAI:
    """Central orchestrator that runs Minion tasks in sequence."""

    def __init__(self, minions: List["Minion"]) -> None:
        self.minions = minions
        self.completed: List[str] = []

    def search_for_error(self, error: str) -> str:
        """Web-search for potential fixes to an error."""
        log.info("Searching for fixes: %r", error)
        results = search_web(f"Fedora 44 {error}", max_results=3)
        if not results:
            return "No results found."
        lines = []
        for r in results:
            snippet = fetch_first_paragraph(r["url"])
            lines.append(f"  - {r['title']}\n    {r['url']}\n    {snippet[:200]}")
        return "\n".join(lines)

    def run_all(self, interactive: bool = True) -> None:
        """Execute all minions sequentially."""
        total = len(self.minions)
        for idx, m in enumerate(self.minions, 1):
            log.info("▶ [%d/%d] %s", idx, total, m.name)
            try:
                m.run(self)
            except Exception as exc:
                m.status = "failed"
                m.error = str(exc)
                log.error("Unhandled exception in %s: %s", m.name, exc)

            if m.status == "success":
                self.completed.append(m.name)
                log.info("✓ [%d/%d] %s complete", idx, total, m.name)
                continue

            # Failure path
            log.error("✗ Task failed: %s — %s", m.name, m.error)
            if m.error:
                suggestions = self.search_for_error(m.error)
                print(f"\nPossible fixes:\n{suggestions}\n")

            if interactive:
                retry = prompt_input("Retry this task? (y/N)", "N")
                if retry.lower() == "y":
                    log.info("↺ Retrying: %s", m.name)
                    try:
                        m.status = "pending"
                        m.error = None
                        m.run(self)
                    except Exception as exc:
                        m.status = "failed"
                        m.error = str(exc)

            if m.status != "success":
                log.critical("Aborting — persistent failure in: %s", m.name)
                sys.exit(1)

        log.info("All %d tasks completed successfully.", total)


class Minion:
    """Worker that performs a single installation task."""

    def __init__(self, name: str, action: Callable[["BossAI"], None]) -> None:
        self.name = name
        self.action = action
        self.status: str = "pending"
        self.error: Optional[str] = None

    def run(self, boss: BossAI) -> None:
        try:
            self.action(boss)
            self.status = "success"
        except Exception as exc:
            self.status = "failed"
            self.error = str(exc)
            raise


# ---------------------------------------------------------------------------
# Installation tasks
# ---------------------------------------------------------------------------

def task_check_network(boss: BossAI) -> None:
    """Verify internet connectivity."""
    log.info("Testing connectivity...")
    code, out = run_cmd(
        ["curl", "-sf", "--head", "--max-time", "8", "https://download.docker.com"]
    )
    if code != 0:
        raise RuntimeError(f"Cannot reach download.docker.com. Check DNS/firewall.\n{out}")
    log.info("Network OK.")


def task_install_core_packages(boss: BossAI) -> None:
    """Install Git, curl, Python venv, Node.js via dnf5."""
    if not dnf5_available():
        raise RuntimeError("dnf5 not found — is this Fedora 44?")
    # dnf5-plugins ships by default on F44 but verify
    dnf_install(["dnf5-plugins"])
    dnf_install([
        "git", "curl", "python3", "python3-pip", "python3-devel",
        "nodejs", "npm",
    ])
    log.info("Core packages installed.")


def task_setup_python_venv(boss: BossAI) -> None:
    """Create a Python venv and install Flask + bs4 (PEP 668 safe)."""
    if VENV_PATH.exists() and (VENV_PATH / "bin" / "python3").exists():
        log.info("Venv already exists at %s", VENV_PATH)
    else:
        log.info("Creating venv at %s", VENV_PATH)
        VENV_PATH.parent.mkdir(parents=True, exist_ok=True)
        run_cmd([sys.executable, "-m", "venv", str(VENV_PATH)], check=True)
    pip = str(VENV_PATH / "bin" / "pip")
    run_cmd([pip, "install", "--upgrade", "pip"], timeout=120, check=True)
    run_cmd(
        [pip, "install", "flask", "beautifulsoup4", "gunicorn"],
        timeout=300, check=True,
    )
    log.info("Python venv ready.")


def task_setup_docker_repo(boss: BossAI) -> None:
    """Add Docker CE repo via DNF5 config-manager."""
    repo_file = Path("/etc/yum.repos.d/docker-ce.repo")
    if repo_file.exists():
        log.info("Docker repo already configured.")
        return
    log.info("Adding Docker CE repository...")
    run_cmd(
        ["dnf5", "config-manager", "addrepo",
         f"--from-repofile={DOCKER_REPO_URL}"],
        timeout=60, check=True,
    )
    log.info("Docker repo added.")


def task_install_docker(boss: BossAI) -> None:
    """Install Docker Engine and enable the service."""
    pkgs = [
        "docker-ce", "docker-ce-cli", "containerd.io",
        "docker-buildx-plugin", "docker-compose-plugin",
    ]
    dnf_install(pkgs)
    run_cmd(["systemctl", "enable", "--now", "docker"], timeout=60, check=True)
    # Verify
    code, out = run_cmd(["systemctl", "is-active", "docker"])
    if out.strip() != "active":
        raise RuntimeError(f"Docker service not active: {out}")
    log.info("Docker Engine running.")


def task_clone_repo(boss: BossAI, repo_url: str, dest: Path) -> None:
    """Clone or fast-forward the homelab repository."""
    if dest.exists() and (dest / ".git").exists():
        log.info("Repo exists at %s — pulling...", dest)
        run_cmd(["git", "-C", str(dest), "pull", "--ff-only"], timeout=300, check=True)
        return
    log.info("Cloning %s -> %s", repo_url, dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    run_cmd(["git", "clone", "--depth=1", repo_url, str(dest)], timeout=600, check=True)
    log.info("Repository cloned.")


# ---------------------------------------------------------------------------
# Configuration collection
# ---------------------------------------------------------------------------

DEFAULT_CONFIG: Dict[str, str] = {
    "NODE_A_IP": "192.168.1.9",
    "NODE_B_IP": "192.168.1.222",
    "NODE_C_IP": "192.168.1.6",
    "NODE_D_IP": "192.168.1.149",
    "NODE_E_IP": "192.168.1.116",
    "KVM_IP": "192.168.1.130",
    "KVM_HOSTNAME": "kvm-d829.local",
    "NODE_A_SSH_USER": "root",
    "NODE_B_SSH_USER": "root",
    "NODE_C_SSH_USER": "root",
    "NODE_D_SSH_USER": "root",
    "NODE_E_SSH_USER": "root",
    "LITELLM_API_KEY": "sk-master-key",
    "KVM_OPERATOR_TOKEN": "",
    "OPENCLAW_GATEWAY_TOKEN": "",
    "HUGGINGFACE_TOKEN": "hf_your_token_here",
    "NANOKVM_USERNAME": "admin",
    "NANOKVM_PASSWORD": "admin",
    "TAILSCALE_AUTHKEY": "tskey-auth-XXXXXXXXXXXXXXXX",
    "HA_LONG_LIVED_TOKEN": "your-ha-long-lived-token-here",
    "VPN_SERVICE_PROVIDER": "private internet access",
    "VPN_USER": "your-vpn-username",
    "VPN_PASSWORD": "your-vpn-password",
    "CLOUDFLARE_TUNNEL_TOKEN": "your-cloudflare-tunnel-token",
    "SEARXNG_SECRET_KEY": "",
    "TZ": "America/New_York",
    "VLLM_MODEL_A": "meta-llama/Llama-3.1-8B-Instruct",
    "VLLM_MODEL_B": "mistralai/Mistral-7B-Instruct-v0.3",
    "NEXTCLOUD_DB_ROOT_PASSWORD": "changeme-root",
    "NEXTCLOUD_DB_PASSWORD": "changeme-nc",
}

# Fields that should be masked during interactive input
_SECRET_FIELDS = {
    "LITELLM_API_KEY", "KVM_OPERATOR_TOKEN", "OPENCLAW_GATEWAY_TOKEN",
    "HUGGINGFACE_TOKEN", "NANOKVM_PASSWORD", "TAILSCALE_AUTHKEY",
    "HA_LONG_LIVED_TOKEN", "VPN_PASSWORD", "CLOUDFLARE_TUNNEL_TOKEN",
    "NEXTCLOUD_DB_ROOT_PASSWORD", "NEXTCLOUD_DB_PASSWORD",
}


def collect_configuration_interactive() -> Dict[str, Any]:
    """Gather configuration via interactive prompts."""
    cfg: Dict[str, Any] = {}
    print("\n=== Node IP Addresses ===")
    cfg["NODE_A_IP"] = prompt_input("Node A IP (Brain / AMD GPU)", "192.168.1.9")
    cfg["NODE_B_IP"] = prompt_input("Node B IP (Unraid / Gateway)", "192.168.1.222")
    cfg["NODE_C_IP"] = prompt_input("Node C IP (Intel Arc)", "192.168.1.6")
    cfg["NODE_D_IP"] = prompt_input("Node D IP (Home Assistant)", "192.168.1.149")
    cfg["NODE_E_IP"] = prompt_input("Node E IP (Sentinel/NVR)", "192.168.1.116")
    cfg["KVM_IP"] = prompt_input("NanoKVM IP", "192.168.1.130")
    cfg["KVM_HOSTNAME"] = prompt_input("NanoKVM hostname", "kvm-d829.local")

    print("\n=== SSH Users ===")
    for node in ("A", "B", "C", "D", "E"):
        cfg[f"NODE_{node}_SSH_USER"] = prompt_input(f"SSH user for Node {node}", "root")

    print("\n=== Credentials (input hidden) ===")
    cfg["LITELLM_API_KEY"] = prompt_input("LiteLLM master API key", "sk-master-key", secret=True)
    kvm_tok = prompt_input("KVM Operator token (blank = auto-generate)", "", secret=True)
    cfg["KVM_OPERATOR_TOKEN"] = kvm_tok or os.urandom(24).hex()
    oc_tok = prompt_input("OpenClaw gateway token (blank = auto-generate)", "", secret=True)
    cfg["OPENCLAW_GATEWAY_TOKEN"] = oc_tok or os.urandom(24).hex()
    cfg["HUGGINGFACE_TOKEN"] = prompt_input("HuggingFace Hub token", "hf_your_token_here", secret=True)
    cfg["NANOKVM_USERNAME"] = prompt_input("NanoKVM username", "admin")
    cfg["NANOKVM_PASSWORD"] = prompt_input("NanoKVM password", "admin", secret=True)
    cfg["TAILSCALE_AUTHKEY"] = prompt_input("Tailscale auth key", "tskey-auth-XXXXXXXXXXXXXXXX", secret=True)
    cfg["HA_LONG_LIVED_TOKEN"] = prompt_input("Home Assistant long-lived token", "your-ha-long-lived-token-here", secret=True)
    cfg["VPN_SERVICE_PROVIDER"] = prompt_input("VPN service provider", "private internet access")
    cfg["VPN_USER"] = prompt_input("VPN username", "your-vpn-username")
    cfg["VPN_PASSWORD"] = prompt_input("VPN password", "your-vpn-password", secret=True)
    cfg["CLOUDFLARE_TUNNEL_TOKEN"] = prompt_input("Cloudflare tunnel token", "your-cloudflare-tunnel-token", secret=True)
    cfg["SEARXNG_SECRET_KEY"] = os.urandom(32).hex()

    print("\n=== General ===")
    cfg["TZ"] = prompt_input("Timezone", "America/New_York")
    cfg["VLLM_MODEL_A"] = prompt_input("Model for Node A vLLM", "meta-llama/Llama-3.1-8B-Instruct")
    cfg["VLLM_MODEL_B"] = prompt_input("Model for Node B vLLM", "mistralai/Mistral-7B-Instruct-v0.3")
    cfg["NEXTCLOUD_DB_ROOT_PASSWORD"] = prompt_input("Nextcloud DB root password", "changeme-root", secret=True)
    cfg["NEXTCLOUD_DB_PASSWORD"] = prompt_input("Nextcloud DB user password", "changeme-nc", secret=True)
    return cfg


def load_config_non_interactive(config_path: Optional[str] = None) -> Dict[str, Any]:
    """Load configuration from file/env vars without prompts."""
    cfg = dict(DEFAULT_CONFIG)
    # Auto-generate secrets
    cfg["SEARXNG_SECRET_KEY"] = os.urandom(32).hex()

    # Load from file
    if config_path and os.path.isfile(config_path):
        try:
            if config_path.endswith(".json"):
                with open(config_path) as fh:
                    data = json.load(fh)
                    if isinstance(data, dict):
                        cfg.update({k: str(v) for k, v in data.items()})
            else:
                with open(config_path) as fh:
                    for line in fh:
                        line = line.strip()
                        if not line or line.startswith("#"):
                            continue
                        if "=" in line:
                            k, v = line.split("=", 1)
                            cfg[k.strip()] = v.strip()
        except Exception as exc:
            log.warning("Failed to parse config file %s: %s", config_path, exc)

    # Environment overrides
    for key in list(cfg.keys()):
        env_val = os.environ.get(key)
        if env_val:
            cfg[key] = env_val

    # Auto-generate empty tokens
    for token_key in ("KVM_OPERATOR_TOKEN", "OPENCLAW_GATEWAY_TOKEN"):
        if not cfg.get(token_key):
            cfg[token_key] = os.urandom(24).hex()

    return cfg


# ---------------------------------------------------------------------------
# Environment file generation
# ---------------------------------------------------------------------------

def generate_env_files(config: Dict[str, Any], root: Path) -> None:
    """Write all .env files from the config dictionary."""
    c = config  # shorthand

    # Node inventory
    inv = textwrap.dedent(f"""\
        # Generated by boss_multi_agent_install.py v{VERSION}
        NODE_A_IP={c['NODE_A_IP']}
        NODE_B_IP={c['NODE_B_IP']}
        NODE_C_IP={c['NODE_C_IP']}
        NODE_D_IP={c['NODE_D_IP']}
        NODE_E_IP={c['NODE_E_IP']}
        KVM_IP={c['KVM_IP']}
        KVM_HOSTNAME={c['KVM_HOSTNAME']}
        NODE_A_SSH_USER={c['NODE_A_SSH_USER']}
        NODE_B_SSH_USER={c['NODE_B_SSH_USER']}
        NODE_C_SSH_USER={c['NODE_C_SSH_USER']}
        NODE_D_SSH_USER={c['NODE_D_SSH_USER']}
        NODE_E_SSH_USER={c['NODE_E_SSH_USER']}
        LITELLM_API_KEY={c['LITELLM_API_KEY']}
        KVM_OPERATOR_TOKEN={c['KVM_OPERATOR_TOKEN']}
        OPENCLAW_GATEWAY_TOKEN={c['OPENCLAW_GATEWAY_TOKEN']}
    """)
    write_file(root / "config" / "node-inventory.env", inv, ask_overwrite=False)

    # KVM operator
    kvm_host = c["KVM_HOSTNAME"].split(".")[0]
    kvm_env = textwrap.dedent(f"""\
        KVM_OPERATOR_TOKEN={c['KVM_OPERATOR_TOKEN']}
        REQUIRE_APPROVAL=true
        KVM_TARGETS_JSON={{"{kvm_host}":"{c['KVM_IP']}"}}
        NANOKVM_USERNAME={c['NANOKVM_USERNAME']}
        NANOKVM_PASSWORD={c['NANOKVM_PASSWORD']}
        LITELLM_URL=http://{c['NODE_B_IP']}:4000/v1/chat/completions
        LITELLM_API_KEY={c['LITELLM_API_KEY']}
    """)
    write_file(root / "kvm-operator" / ".env", kvm_env, ask_overwrite=False)

    # Node A — vLLM
    write_file(root / "node-a-vllm" / ".env", textwrap.dedent(f"""\
        HUGGINGFACE_TOKEN={c['HUGGINGFACE_TOKEN']}
        VLLM_MODEL={c['VLLM_MODEL_A']}
    """), ask_overwrite=False)

    # Node A — command center
    write_file(root / "node-a-command-center" / ".env", textwrap.dedent(f"""\
        COMMAND_CENTER_PORT=3099
        LITELLM_BASE_URL=http://{c['NODE_B_IP']}:4000
        LITELLM_API_KEY={c['LITELLM_API_KEY']}
        DEFAULT_MODEL=brain-heavy
        BRAIN_BASE_URL=http://{c['NODE_A_IP']}:8000
        NODE_C_BASE_URL=http://{c['NODE_C_IP']}
        NODE_D_BASE_URL=http://{c['NODE_D_IP']}:8123
        NODE_E_BASE_URL=http://{c['NODE_E_IP']}:3005
    """), ask_overwrite=False)

    # Node B — LiteLLM stacks
    write_file(root / "node-b-litellm" / "stacks" / ".env", textwrap.dedent(f"""\
        TZ={c['TZ']}
        PUID=1000
        PGID=1000
        APPDATA_PATH=/mnt/user/appdata
        MEDIA_PATH=/mnt/user/data
        LITELLM_MASTER_KEY={c['LITELLM_API_KEY']}
        VPN_SERVICE_PROVIDER={c['VPN_SERVICE_PROVIDER']}
        VPN_USER={c['VPN_USER']}
        VPN_PASSWORD={c['VPN_PASSWORD']}
        SEARXNG_SECRET_KEY={c['SEARXNG_SECRET_KEY']}
        VLLM_MODEL={c['VLLM_MODEL_B']}
        HUGGING_FACE_HUB_TOKEN={c['HUGGINGFACE_TOKEN']}
        NEXTCLOUD_DB_ROOT_PASSWORD={c['NEXTCLOUD_DB_ROOT_PASSWORD']}
        NEXTCLOUD_DB_PASSWORD={c['NEXTCLOUD_DB_PASSWORD']}
        OPENCLAW_GATEWAY_TOKEN={c['OPENCLAW_GATEWAY_TOKEN']}
        CLOUDFLARE_TUNNEL_TOKEN={c['CLOUDFLARE_TUNNEL_TOKEN']}
    """), ask_overwrite=False)

    # Node C — OpenClaw
    write_file(root / "node-c-arc" / ".env.openclaw", textwrap.dedent(f"""\
        OPENCLAW_GATEWAY_TOKEN={c['OPENCLAW_GATEWAY_TOKEN']}
        OLLAMA_API_KEY=ollama
        LITELLM_API_KEY={c['LITELLM_API_KEY']}
        KVM_OPERATOR_URL=http://{c['NODE_A_IP']}:5000
        KVM_OPERATOR_TOKEN={c['KVM_OPERATOR_TOKEN']}
    """), ask_overwrite=False)

    # Node D — Home Assistant
    write_file(root / "node-d-home-assistant" / ".env", textwrap.dedent(f"""\
        TZ={c['TZ']}
        LITELLM_BASE_URL=http://{c['NODE_B_IP']}:4000
        LITELLM_API_KEY={c['LITELLM_API_KEY']}
        NODE_A_BASE_URL=http://{c['NODE_A_IP']}:8000
    """), ask_overwrite=False)

    # Node D — HA extras (Nabu Casa placeholder)
    ha_extra = root / "node-d-home-assistant" / "extra.env"
    if not ha_extra.exists():
        write_file(ha_extra, "# Home Assistant extra variables\n# NABU_CASA_TOKEN=\n",
                   ask_overwrite=False, mode=0o644)

    # Unraid
    write_file(root / "unraid" / ".env", textwrap.dedent(f"""\
        TAILSCALE_AUTHKEY={c['TAILSCALE_AUTHKEY']}
        LOCAL_SUBNET=192.168.1.0/24
        APPDATA_PATH=/mnt/user/appdata
        TZ={c['TZ']}
        HA_LONG_LIVED_TOKEN={c['HA_LONG_LIVED_TOKEN']}
    """), ask_overwrite=False)

    # Cloudflare env
    write_file(root / "node-b-litellm" / "stacks" / "cloudflare.env", textwrap.dedent(f"""\
        CLOUDFLARE_TUNNEL_TOKEN={c['CLOUDFLARE_TUNNEL_TOKEN']}
        # CLOUDFLARE_ZONE=<your-domain.com>
    """), ask_overwrite=False)

    log.info("All environment files generated.")


# ---------------------------------------------------------------------------
# API keys (optional extras)
# ---------------------------------------------------------------------------

def configure_api_keys(config: Dict[str, Any], root: Path) -> None:
    """Prompt for optional API tokens and write config/api.env."""
    log.info("Configuring optional API tokens...")
    print("\nOptional API tokens (leave blank to skip):")
    extras: Dict[str, str] = {}
    ai = prompt_input("OpenAI / AI service API key", "", secret=True)
    if ai:
        extras["AI_API_KEY"] = ai
    while True:
        more = prompt_input("Add another API key? (y/N)", "N")
        if more.lower() != "y":
            break
        key = prompt_input("Env variable name", "")
        val = prompt_input(f"Value for {key}", "", secret=True)
        if key and val:
            extras[key] = val
    if not extras:
        log.info("No extra API tokens provided.")
        return
    content = "\n".join(f"{k}={v}" for k, v in extras.items()) + "\n"
    write_file(root / "config" / "api.env", content, ask_overwrite=False)
    log.info("API tokens saved.")


# ---------------------------------------------------------------------------
# Docker Compose deployments
# ---------------------------------------------------------------------------

def run_docker_compose(compose_file: Path) -> None:
    """Run ``docker compose up -d`` on a YAML file."""
    if not compose_file.exists():
        raise RuntimeError(f"Compose file not found: {compose_file}")
    log.info("docker compose up -d — %s", compose_file)
    run_cmd(
        ["docker", "compose", "-f", str(compose_file), "up", "-d"],
        timeout=900, check=True,
    )


def deploy_homeassistant(root: Path, config: Dict[str, Any]) -> str:
    """Deploy Home Assistant via docker compose."""
    compose = root / "node-d-home-assistant" / "docker-compose.yml"
    run_docker_compose(compose)
    ha_ip = config.get("NODE_D_IP", "127.0.0.1")
    url = f"http://{ha_ip}:8123/api/health"
    log.info("Checking HA at %s...", url)
    code, out = run_cmd(["curl", "-sf", "-o", "/dev/null", "-w", "%{http_code}", url], timeout=15)
    status = out.strip()
    if status == "200":
        log.info("Home Assistant API OK.")
    else:
        log.warning("HA health check returned %s (may still be starting).", status)
    return "Home Assistant deployed on Node D."


def deploy_cloudflare(root: Path, config: Dict[str, Any]) -> str:
    """Deploy Cloudflare tunnel."""
    cf_env = root / "node-b-litellm" / "stacks" / "cloudflare.env"
    if not cf_env.exists():
        raise RuntimeError(f"Missing {cf_env} — run env generation first.")
    candidates = [
        root / "node-b-litellm" / "stacks" / "agentic-stack.yml",
        root / "node-b-litellm" / "stacks" / "cloudflare-stack.yml",
        root / "swarm" / "portainer-agent-stack.yml",
    ]
    compose = next((p for p in candidates if p.exists()), None)
    if compose is None:
        raise RuntimeError("No Cloudflare compose file found in repo.")
    run_docker_compose(compose)
    return f"Cloudflare tunnel started via {compose.name}."


def configure_nabu_casa(root: Path) -> str:
    """Write Nabu Casa placeholder and return user instructions."""
    ha_extra = root / "node-d-home-assistant" / "extra.env"
    if ha_extra.exists():
        content = ha_extra.read_text()
        if "NABU_CASA_TOKEN=" not in content:
            content += "\n# NABU_CASA_TOKEN=\n"
            write_file(ha_extra, content, ask_overwrite=False, mode=0o644)
    return (
        "To enable Home Assistant Cloud: open HA UI → Settings → "
        "Home Assistant Cloud → sign in. Copy the remote UI token "
        "into extra.env as NABU_CASA_TOKEN=<token>."
    )


# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

def verify_installation(interactive: bool = True) -> None:
    """Post-install sanity checks."""
    log.info("Running verification...")
    checks = [
        (["systemctl", "is-active", "docker"], "Docker service"),
        (["git", "--version"], "Git"),
        (["node", "--version"], "Node.js"),
        (["python3", "--version"], "Python"),
    ]
    for cmd, label in checks:
        code, out = run_cmd(cmd)
        if code == 0:
            log.info("%s: %s", label, out.strip().split("\n")[0])
        else:
            log.warning("%s: NOT OK", label)

    if interactive:
        test = prompt_input("Run Docker hello-world test? (y/N)", "N")
        if test.lower() == "y":
            code, out = run_cmd(["docker", "run", "--rm", "hello-world"], timeout=120)
            if code == 0:
                log.info("Docker hello-world passed.")
            else:
                log.warning("Docker hello-world failed:\n%s", out)


# ---------------------------------------------------------------------------
# Chat UI (accessible, cyberpunk-themed)
# ---------------------------------------------------------------------------

def build_chat_html(commands: Optional[List[str]] = None) -> str:
    """Generate the chat interface HTML string."""
    cmd_buttons_js = "[]"
    if commands:
        cmd_buttons_js = json.dumps(commands)

    welcome_lines = [
        "Greetings, traveller. I'm your homelab AI companion.",
        "I'll guide you step-by-step through the installation.",
    ]
    if commands:
        welcome_lines.append(
            "Click a button below or type a command: " + ", ".join(commands) + "."
        )
        welcome_lines.append("Type 'help' to see all available commands.")
    welcome_lines.append("Refresh the page to restart the session.")

    welcome_msgs_js = json.dumps([f"Bot: {line}" for line in welcome_lines])

    return textwrap.dedent(f"""\
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Homelab Assistant v{VERSION}</title>
        <style>
            *,*::before,*::after{{box-sizing:border-box}}
            body{{font-family:'Segoe UI',system-ui,sans-serif;background:#0a0e1a;color:#e0eaff;margin:0;padding:0;font-size:17px;line-height:1.6}}
            #app{{max-width:860px;margin:40px auto;padding:0 16px}}
            #chat-box{{background:#111821;border:2px solid #00ffc8;border-radius:12px;box-shadow:0 0 24px rgba(0,255,200,0.25);padding:24px;position:relative}}
            #avatar{{position:absolute;top:-30px;left:-30px;width:64px;height:64px;border-radius:50%;border:2px solid #00ffc8}}
            h1{{color:#00ffc8;font-size:1.4em;margin:0 0 12px 0}}
            #messages{{height:440px;overflow-y:auto;background:#0a0f25;border:1px solid #1a3a4a;border-radius:8px;padding:14px;margin-bottom:12px;scroll-behavior:smooth}}
            .msg{{margin-bottom:10px;padding:6px 10px;border-radius:6px;animation:fadeIn .3s ease}}
            .msg.user{{background:#0d2235;color:#00ffee;font-weight:600}}
            .msg.bot{{background:#0f1a2e;color:#8ef9ff}}
            @keyframes fadeIn{{from{{opacity:0;transform:translateY(4px)}}to{{opacity:1;transform:translateY(0)}}}}
            #input-row{{display:flex;gap:8px}}
            #user-input{{flex:1;padding:12px;background:#0a1432;color:#e0eaff;border:1px solid #00ffc8;border-radius:6px;font-size:1em;outline:none}}
            #user-input:focus{{box-shadow:0 0 8px rgba(0,255,200,0.4)}}
            button{{background:#00ffc8;color:#0a0e1a;border:none;border-radius:6px;padding:10px 16px;font-size:1em;font-weight:600;cursor:pointer;transition:all .2s}}
            button:hover{{background:#0efbff;transform:translateY(-1px)}}
            button:active{{transform:translateY(0)}}
            #cmd-btns{{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:12px}}
            #cmd-btns button{{font-size:.9em;padding:8px 12px}}
            #controls{{display:flex;align-items:center;gap:16px;margin-bottom:12px;font-size:.9em}}
            #controls label{{display:flex;align-items:center;gap:4px;cursor:pointer}}
            #progress-bar{{width:100%;height:6px;background:#1a2a3a;border-radius:3px;margin-top:12px;overflow:hidden}}
            #progress-fill{{height:100%;background:linear-gradient(90deg,#00ffc8,#0efbff);width:0%;transition:width .5s ease}}
            .sr-only{{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);border:0}}
        </style>
    </head>
    <body>
        <div id="app">
            <div id="chat-box">
                <img id="avatar" src="{AVATAR_DATA_URI}" alt="Cyberpunk AI assistant avatar" role="img">
                <h1>Homelab Assistant</h1>
                <div id="progress-bar" role="progressbar" aria-valuenow="0" aria-valuemin="0" aria-valuemax="100">
                    <div id="progress-fill"></div>
                </div>
                <div id="messages" role="log" aria-live="polite" aria-label="Chat messages"></div>
                <div id="controls">
                    <label><input type="checkbox" id="voiceToggle" aria-label="Enable voice feedback"> Voice feedback</label>
                </div>
                <div id="cmd-btns" role="toolbar" aria-label="Quick commands"></div>
                <div id="input-row">
                    <label for="user-input" class="sr-only">Enter a command or question</label>
                    <input type="text" id="user-input" placeholder="Enter a command or question..." autocomplete="off">
                    <button onclick="send()" aria-label="Send message">Send</button>
                </div>
            </div>
        </div>
        <script>
        (function(){{
            const cmds={cmd_buttons_js};
            const welcomeMsgs={welcome_msgs_js};
            let voiceOn=false;
            let tasksDone=0;
            const totalTasks=cmds.length||1;

            // Voice
            document.getElementById('voiceToggle').addEventListener('change',function(){{
                voiceOn=this.checked;
            }});
            function speak(t){{
                if(!voiceOn||!('speechSynthesis' in window))return;
                speechSynthesis.cancel();
                speechSynthesis.speak(new SpeechSynthesisUtterance(t));
            }}

            // Messages
            function appendMsg(text,cls){{
                const d=document.createElement('div');
                d.className='msg '+cls;
                d.textContent=text;
                const m=document.getElementById('messages');
                m.appendChild(d);
                m.scrollTop=m.scrollHeight;
                if(cls==='bot')speak(text.replace(/^Bot:\\s*/,''));
            }}

            // Progress
            function updateProgress(){{
                const pct=Math.min(100,Math.round((tasksDone/totalTasks)*100));
                const fill=document.getElementById('progress-fill');
                const bar=document.getElementById('progress-bar');
                fill.style.width=pct+'%';
                bar.setAttribute('aria-valuenow',pct);
            }}

            // Send
            function sendMsg(query){{
                if(!query)return;
                appendMsg('You: '+query,'user');
                document.getElementById('user-input').value='';
                fetch('/ask',{{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{query:query}})
                }}).then(r=>r.json()).then(data=>{{
                    let ans=data.summary||'No response.';
                    if(data.results&&data.results.length){{
                        ans+='\\n\\nSources:';
                        data.results.forEach(function(r,i){{ans+='\\n'+(i+1)+'. '+r.title+' ('+r.url+')'}});
                    }}
                    appendMsg('Bot: '+ans,'bot');
                    if(!ans.toLowerCase().includes('error')){{tasksDone++;updateProgress()}}
                }}).catch(function(e){{appendMsg('Bot: Connection error: '+e,'bot')}});
            }}
            window.send=function(){{sendMsg(document.getElementById('user-input').value.trim())}};

            // Keyboard
            document.getElementById('user-input').addEventListener('keydown',function(e){{
                if(e.key==='Enter')window.send();
            }});

            // Command buttons
            const btnContainer=document.getElementById('cmd-btns');
            cmds.forEach(function(c){{
                const b=document.createElement('button');
                b.textContent=c;
                b.onclick=function(){{sendMsg(c)}};
                btnContainer.appendChild(b);
            }});

            // Welcome
            welcomeMsgs.forEach(function(m){{appendMsg(m,'bot')}});
        }})();
        </script>
    </body>
    </html>
    """)


# ---------------------------------------------------------------------------
# Chat server (Flask + Gunicorn)
# ---------------------------------------------------------------------------

def start_chat_server(
    boss: BossAI,
    repo_root: Path,
    tasks: Dict[str, Callable[[BossAI], str]],
    host: str = "0.0.0.0",
    port: int = CHAT_PORT,
) -> None:
    """Launch the Flask chat server."""
    # Add venv to path so Flask is importable
    venv_site = VENV_PATH / "lib"
    # Find the python3.x directory dynamically
    py_dirs = list(venv_site.glob("python3.*"))
    if py_dirs:
        site_pkg = py_dirs[0] / "site-packages"
        if str(site_pkg) not in sys.path:
            sys.path.insert(0, str(site_pkg))

    try:
        from flask import Flask, request, jsonify, send_from_directory  # type: ignore[import-untyped]
    except ImportError:
        raise RuntimeError(
            "Flask not installed. Run the venv setup task first."
        )

    app = Flask(__name__)
    chat_dir = repo_root / "chat"
    chat_dir.mkdir(parents=True, exist_ok=True)
    html_path = chat_dir / "index.html"

    # Always regenerate HTML with current command list
    cmd_list = list(tasks.keys()) if tasks else []
    html_content = build_chat_html(commands=cmd_list)
    html_path.write_text(html_content)
    log.info("Chat HTML written to %s", html_path)

    @app.route("/")
    def index():  # type: ignore[no-untyped-def]
        return send_from_directory(str(chat_dir), "index.html")

    @app.route("/health")
    def health():  # type: ignore[no-untyped-def]
        return jsonify({"status": "ok", "version": VERSION})

    @app.route("/ask", methods=["POST"])
    def ask():  # type: ignore[no-untyped-def]
        data = request.get_json(force=True)
        query = data.get("query", "").strip()
        if not query:
            return jsonify({"error": "Empty query."}), 400

        q_lower = query.lower()
        if tasks:
            for cmd, fn in tasks.items():
                if q_lower == cmd.lower():
                    log.info("Chat command: %s", cmd)
                    try:
                        result = fn(boss)
                        return jsonify({"query": query, "results": [], "summary": result})
                    except Exception as exc:
                        return jsonify({
                            "query": query, "results": [],
                            "summary": f"Error: {exc}",
                        })

        # Fallback: web search
        return jsonify(answer_query(query))

    log.info("Starting chat server at http://%s:%d", host, port)
    # Use threaded mode for basic concurrency
    app.run(host=host, port=port, threaded=True)


# ---------------------------------------------------------------------------
# Systemd service installation
# ---------------------------------------------------------------------------

SYSTEMD_UNIT = textwrap.dedent("""\
    [Unit]
    Description=Homelab Assistant Chat Server
    After=network-online.target docker.service
    Wants=network-online.target

    [Service]
    Type=simple
    ExecStart={venv}/bin/python3 {script} --non-interactive --auto-start-chat
    WorkingDirectory=/opt/homelab
    Restart=on-failure
    RestartSec=5
    StandardOutput=journal
    StandardError=journal
    Environment=PYTHONUNBUFFERED=1

    [Install]
    WantedBy=multi-user.target
""")


def install_systemd_service(script_path: Path) -> None:
    """Install and enable a systemd service for the chat server."""
    unit_content = SYSTEMD_UNIT.format(
        venv=VENV_PATH,
        script=script_path,
    )
    unit_path = Path("/etc/systemd/system/homelab-assistant.service")
    unit_path.write_text(unit_content)
    os.chmod(unit_path, 0o644)
    if shutil.which("restorecon"):
        run_cmd(["restorecon", "-v", str(unit_path)])
    run_cmd(["systemctl", "daemon-reload"], check=True)
    run_cmd(["systemctl", "enable", "homelab-assistant.service"], check=True)
    log.info("Systemd service installed and enabled.")
    log.info("Start with: systemctl start homelab-assistant")
    log.info("Chat will be at http://localhost:%d", CHAT_PORT)


# ---------------------------------------------------------------------------
# Firewall helper
# ---------------------------------------------------------------------------

def open_firewall_port(port: int) -> None:
    """Open a TCP port in firewalld if available."""
    if not shutil.which("firewall-cmd"):
        log.info("firewall-cmd not found — skipping firewall config.")
        return
    code, _ = run_cmd(["firewall-cmd", "--query-port", f"{port}/tcp"])
    if code == 0:
        log.info("Port %d already open.", port)
        return
    run_cmd(["firewall-cmd", "--add-port", f"{port}/tcp", "--permanent"])
    run_cmd(["firewall-cmd", "--reload"])
    log.info("Opened port %d/tcp in firewalld.", port)


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def main() -> None:
    banner = f"""
╔═══════════════════════════════════════════════════════════════════╗
║  Homelab Install Assistant v{VERSION} — Boss-Driven Multi-Agent     ║
║  Target: Fedora 44 cosmic | DNF5 | SELinux Enforcing | Wayland/GNOME50  ║
╚═══════════════════════════════════════════════════════════════════╝
"""
    print(banner)

    parser = argparse.ArgumentParser(
        description="Boss-Driven Homelab Install Assistant for Fedora 44 (cosmic nightly)",
    )
    parser.add_argument(
        "--non-interactive", action="store_true",
        help="Run unattended using defaults/env vars/config file.",
    )
    parser.add_argument(
        "--config-file",
        help="Path to a JSON or .env config file (non-interactive mode).",
    )
    parser.add_argument(
        "--auto-start-chat", action="store_true",
        help="Automatically launch the chat server after install.",
    )
    parser.add_argument(
        "--install-service", action="store_true",
        help="Install a systemd service for the chat server.",
    )
    parser.add_argument(
        "--chat-only", action="store_true",
        help="Skip installation, only start the chat server.",
    )
    parser.add_argument(
        "--dest-dir",
        help="Installation directory (default: ~/onemoreytry).",
    )
    parser.add_argument(
        "--version", action="version", version=f"%(prog)s {VERSION}",
    )
    args = parser.parse_args()

    ensure_root()

    # Resolve paths
    dest_dir = args.dest_dir or str(Path.home() / "onemoreytry")
    if not args.non_interactive and not args.chat_only:
        dest_dir = prompt_input("Destination directory", dest_dir)
    clone_path = Path(dest_dir).expanduser()

    # Configuration
    config: Dict[str, Any] = {}

    # Copy script to /opt/homelab for service reference
    script_dest = INSTALL_ROOT / "boss_multi_agent_install.py"
    INSTALL_ROOT.mkdir(parents=True, exist_ok=True)
    this_script = Path(__file__).resolve()
    if this_script != script_dest:
        shutil.copy2(this_script, script_dest)
        os.chmod(script_dest, 0o755)

    # ---- Chat-only mode ----
    if args.chat_only:
        config = load_config_non_interactive(args.config_file)
        boss = BossAI([])

        def _build_tasks() -> Dict[str, Callable[[BossAI], str]]:
            return _make_task_map(boss, config, clone_path)

        tasks = _build_tasks()
        open_firewall_port(CHAT_PORT)
        start_chat_server(boss, clone_path, tasks)
        return

    # ---- Non-interactive mode ----
    if args.non_interactive:
        config = load_config_non_interactive(args.config_file)
        minions = [
            Minion("Network Check", task_check_network),
            Minion("Core Packages", task_install_core_packages),
            Minion("Python Venv", task_setup_python_venv),
            Minion("Docker Repo", task_setup_docker_repo),
            Minion("Docker Engine", task_install_docker),
            Minion("Generate Env Files",
                   lambda b: generate_env_files(config, clone_path)),
            Minion("Deploy Home Assistant",
                   lambda b: deploy_homeassistant(clone_path, config)),
            Minion("Deploy Cloudflare",
                   lambda b: deploy_cloudflare(clone_path, config)),
            Minion("Nabu Casa Info",
                   lambda b: log.info(configure_nabu_casa(clone_path))),
            Minion("Verification",
                   lambda b: verify_installation(interactive=False)),
        ]
        boss = BossAI(minions)
        boss.run_all(interactive=False)

        if args.install_service:
            install_systemd_service(script_dest)

        if args.auto_start_chat:
            tasks = _make_task_map(boss, config, clone_path)
            open_firewall_port(CHAT_PORT)
            start_chat_server(boss, clone_path, tasks)
        return

    # ---- Interactive mode ----
    def minion_core(b: BossAI) -> None:
        task_install_core_packages(b)

    def minion_venv(b: BossAI) -> None:
        task_setup_python_venv(b)

    def minion_docker_repo(b: BossAI) -> None:
        task_setup_docker_repo(b)

    def minion_docker(b: BossAI) -> None:
        task_install_docker(b)

    def minion_config(b: BossAI) -> None:
        nonlocal config
        config = collect_configuration_interactive()

    def minion_api_keys(b: BossAI) -> None:
        configure_api_keys(config, clone_path)

    def minion_env(b: BossAI) -> None:
        generate_env_files(config, clone_path)

    def minion_verify(b: BossAI) -> None:
        verify_installation(interactive=True)

    def minion_chat(b: BossAI) -> None:
        start_q = prompt_input("Start chat server now? (y/N)", "N")
        if start_q.lower() == "y":
            tasks = _make_task_map(b, config, clone_path)
            open_firewall_port(CHAT_PORT)
            start_chat_server(b, clone_path, tasks)

    boss = BossAI([
        Minion("Network Check", task_check_network),
        Minion("Core Packages", minion_core),
        Minion("Python Venv", minion_venv),
        Minion("Docker Repo", minion_docker_repo),
        Minion("Docker Engine", minion_docker),
        Minion("Collect Configuration", minion_config),
        Minion("API Keys", minion_api_keys),
        Minion("Generate Env Files", minion_env),
        Minion("Verification", minion_verify),
        Minion("Chat Server", minion_chat),
    ])
    boss.run_all(interactive=True)

    if args.install_service:
        install_systemd_service(script_dest)


def _make_task_map(
    boss: BossAI,
    config: Dict[str, Any],
    clone_path: Path,
) -> Dict[str, Callable[[BossAI], str]]:
    """Build the chat command -> action mapping."""

    def t_deps(b: BossAI) -> str:
        task_install_core_packages(b)
        task_setup_docker_repo(b)
        task_install_docker(b)
        return "Dependencies installed."

    def t_env(b: BossAI) -> str:
        if not config:
            return "No configuration loaded. Run CLI config first."
        generate_env_files(config, clone_path)
        return "Environment files generated."

    def t_ha(b: BossAI) -> str:
        if not config:
            return "No configuration loaded."
        return deploy_homeassistant(clone_path, config)

    def t_cf(b: BossAI) -> str:
        if not config:
            return "No configuration loaded."
        return deploy_cloudflare(clone_path, config)

    def t_nc(b: BossAI) -> str:
        return configure_nabu_casa(clone_path)

    def t_verify(b: BossAI) -> str:
        verify_installation(interactive=False)
        return "Verification complete."

    def t_help(b: BossAI) -> str:
        return "Commands: " + ", ".join(sorted(tasks.keys()))

    def t_full(b: BossAI) -> str:
        msgs = []
        try:
            msgs.append(t_deps(b))
            if config:
                msgs.append(t_env(b))
                msgs.append(t_ha(b))
                msgs.append(t_cf(b))
                msgs.append(t_nc(b))
            msgs.append(t_verify(b))
            return "\n".join(msgs)
        except Exception as exc:
            return f"Full install error: {exc}"

    tasks: Dict[str, Callable[[BossAI], str]] = {
        "install dependencies": t_deps,
        "generate env files": t_env,
        "install homeassistant": t_ha,
        "configure cloudflare": t_cf,
        "configure nabu casa": t_nc,
        "verify installation": t_verify,
        "help": t_help,
        "full install": t_full,
    }
    return tasks


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nInterrupted.")
        sys.exit(130)
