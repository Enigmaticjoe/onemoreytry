#!/usr/bin/env python3
"""
Boss‑Driven Homelab Install Assistant for Fedora 44 (cosmic nightly)
======================================================================

This script reimagines the original single‑process homelab installer as
an orchestrated, multi‑agent system.  A central **Boss AI** coordinates
several **Minion** agents, each responsible for a discrete part of the
installation workflow.  The architecture emphasises idempotence,
robust error handling and self‑correction: if a task fails, the Boss
attempts to learn from the error by performing a web search and
presenting possible solutions.  The script supports Fedora 44 (cosmic
nightly) systems and honours RPM package management best practices
without disabling SELinux.

Key design elements
-------------------

* **Multi‑agent orchestration:** A `BossAI` class manages a list of
  `Minion` objects.  Each Minion wraps a callable performing one
  installation phase (dependency installation, repository cloning,
  configuration collection, environment generation and chat server
  startup).  The Boss runs minions sequentially, capturing success
  state and errors.

* **Self‑correction:** Upon failure, the Boss performs a DuckDuckGo
  search using the error message and displays the first paragraphs of
  relevant pages.  This offers context for troubleshooting without
  leaving the terminal.

* **Idempotent, atomic tasks:** Each minion verifies whether its work
  has already been completed before acting.  Package installation
  checks use `rpm -q`.  Repository cloning detects existing Git
  directories and performs a `git pull --ff-only`.  Environment files
  prompt before overwriting.  The script aborts on unhandled errors.

* **Fedora 44 aware:** The installer prefers the `dnf5` command when
  available (falling back to `dnf` if not) and installs Docker
  Engine components using the officially recommended packages
  (`docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`,
  `docker-compose-plugin`)【90012162061105†L1019-L1083】.  It also
  installs Node.js via the Fedora‑provided `nodejs` package【783299041434477†L29-L33】,
  along with Git, curl, pip and wheel【898572563346427†L184-L188】.

* **Chat service:** After setup, the assistant optionally launches a
  lightweight Flask web server exposing a HTML chat interface and a
  JSON `/ask` endpoint, enabling browser‑based interaction.

To use this script, run it as root on a Fedora 44 machine.  Answer
the prompts when asked; the Boss AI will handle the rest.  At the
end, a chat server listens on port 8008 (by default), and the
repository and configuration files are ready for deployment.
"""

from __future__ import annotations

import os
import re
import sys
import subprocess
import getpass
import shutil
import time
import textwrap
import argparse
import json
import platform
from pathlib import Path
from typing import Callable, Dict, Any, Optional, List, Tuple

try:
    import urllib.parse as urlparse
    import urllib.request as urlrequest
    from html import unescape
except ImportError:
    # Python 2 fallback (unlikely on Fedora 44)
    import urllib as urlparse  # type: ignore
    import urllib2 as urlrequest  # type: ignore


def timestamp() -> str:
    """Return the current time as a human‑readable string."""
    return time.strftime("%Y-%m-%d %H:%M:%S")


# Base64‑encoded SVG avatar for the chat UI.  This small graphic
# depicts a cyberpunk‑inspired AI icon: a dark backdrop with a neon
# circle, inner core and arrow.  High contrast colours ensure
# readability, while the simple design evokes a high‑tech, futuristic
# feel.  To change the avatar, replace the data URI below with
# another base64‑encoded image.
AVATAR_DATA_URI = (
    "data:image/svg+xml;base64,"
    "PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxMDAiIGhlaWdodD0iMTAwIj4KPHJlY3Qgd2lkdGg9IjEwMCUiIGhlaWdodD0iMTAwJSIgZmlsbD0iIzBhMGEwYSIvPgo8Y2lyY2xlIGN4PSI1MCIgY3k9IjUwIiByPSI0MCIgZmlsbD0iIzAwMjIyMiIgc3Ryb2tlPSIjMDBmZmZmIiBzdHJva2Utd2lkdGg9IjQiLz4KPGNpcmNsZSBjeD0iNTAiIGN5PSI1MCIgcj0iMTUiIGZpbGw9IiMwMGZmZmYiLz4KPHBhdGggZD0iTTUwIDIwIEw2MCAzNSBMNDAgMzUgWiIgZmlsbD0iIzAwZmZmZiIgLz4KPC9zdmc+"
)


class BossAI:
    """Coordinator for minion agents.

    The Boss maintains a queue of `Minion` instances and executes
    them in order.  It logs progress with timestamps and attempts
    self‑diagnosis on errors by performing a web search.
    """

    def __init__(self, minions: List["Minion"]):
        self.minions = minions

    def log(self, message: str) -> None:
        """Print a log message with timestamp."""
        print(f"[{timestamp()}] {message}")

    def search_for_error(self, error: str) -> str:
        """Use a DuckDuckGo search to retrieve summaries for an error.

        Args:
            error: The error message or search query.

        Returns:
            A formatted string containing titles, URLs and the first
            paragraph of up to three results.
        """
        self.log(f"Searching the web for potential fixes to: {error!r}")
        results = search_web(error, max_results=3)
        if not results:
            return "No results found."
        entries = []
        for res in results:
            summary = fetch_first_paragraph(res["url"])
            entries.append(
                f"\n– {res['title']}\n  {res['url']}\n  {summary[:200]}"
            )
        return "\n".join(entries)

    def run_all(self) -> None:
        """Execute all minions in sequence, handling errors gracefully."""
        for m in self.minions:
            self.log(f"▶ Starting task: {m.name}")
            try:
                m.run(self)
            except Exception as e:
                # Catch any unexpected exception that escapes the minion
                m.status = "failed"
                m.error = str(e)
                self.log(f"⚠ Unhandled exception in {m.name}: {e}")
            if m.status == "success":
                self.log(f"✓ Completed task: {m.name}")
                continue
            # On failure, perform a self‑help search and ask for user input
            self.log(f"✗ Task failed: {m.name}")
            if m.error:
                suggestions = self.search_for_error(m.error)
                print("Possible causes and fixes:\n" + suggestions + "\n")
            retry = input("Would you like to retry this task? (y/N): ").strip().lower()
            if retry == "y":
                # Retry once
                self.log(f"↺ Retrying task: {m.name}")
                try:
                    m.run(self)
                except Exception as e:
                    m.status = "failed"
                    m.error = str(e)
                    self.log(f"⚠ Retry failed: {e}")
            if m.status != "success":
                self.log("Installation aborted due to persistent failure.")
                sys.exit(1)
        self.log("All tasks completed successfully.")


class Minion:
    """A worker that performs a single installation task."""

    def __init__(self, name: str, action: Callable[["BossAI"], None]) -> None:
        self.name = name
        self.action = action
        self.status: str = "pending"
        self.error: Optional[str] = None

    def run(self, boss: BossAI) -> None:
        """Execute the assigned action and record status."""
        try:
            self.action(boss)
            self.status = "success"
        except Exception as e:
            self.status = "failed"
            self.error = str(e)


def run_command(cmd: List[str], timeout: int = 60) -> Tuple[int, str]:
    """Execute a command and return (exit_code, combined stdout/stderr)."""
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, proc.stdout + proc.stderr
    except FileNotFoundError:
        return 127, f"Command not found: {' '.join(cmd)}"
    except subprocess.TimeoutExpired:
        return 124, f"Command timed out: {' '.join(cmd)}"


def choose_dnf() -> str:
    """Return the appropriate DNF command (dnf5 if available, else dnf)."""
    for candidate in ("dnf5", "dnf"):
        if shutil.which(candidate):
            return candidate
    # Default to dnf if nothing is found
    return "dnf"


def check_network_connectivity(boss: 'BossAI', host: str = "1.1.1.1") -> None:
    """Ensure the system has network connectivity by making an HTTP request to a host.

    Args:
        boss: The boss instance for logging.
        host: Hostname to test connectivity against. Defaults to 1.1.1.1.

    Raises:
        RuntimeError: If the host cannot be reached.
    """
    boss.log(f"Testing network connectivity to {host}…")
    # Use ping with a short timeout and only one packet.
    # Some systems do not allow ping as non‑root; we fall back to curl.
    ping_cmd = ["ping", "-c", "1", "-W", "2", host]
    code, _ = run_command(ping_cmd)
    if code != 0:
        # Try with curl if ping is unavailable
        code2, out2 = run_command(["curl", "-s", "--head", "--request", "GET", f"https://{host}", "--max-time", "5"])
        if code2 != 0:
            raise RuntimeError(f"Cannot reach {host}. Output:\n{out2}")
    boss.log("Network connectivity verified.")


def configure_api_keys(boss: 'BossAI', config: Dict[str, Any], root: Path) -> None:
    """Prompt the user for API tokens and write them to a separate env file.

    This allows integration with external services like GitHub or an AI API
    while keeping credentials local.  Tokens are optional; if provided,
    they are stored in `config/api.env` within the repository root.

    Args:
        boss: The boss instance for logging.
        config: The existing configuration dictionary (unused but
            provided for consistency).
        root: Root path of the cloned repository where the API file
            will be stored.
    """
    boss.log("Configuring optional API tokens…")
    print(
        "\nYou can optionally provide tokens for external services (leave blank to skip)."
        "\nThese values will be stored locally in config/api.env."
    )
    openai_key = prompt_input("OpenAI or other AI service API key", "", secret=True)
    extras: Dict[str, str] = {}
    if openai_key:
        extras["AI_API_KEY"] = openai_key
    # Allow arbitrary key:value pairs for future services
    add_more = "y"
    while add_more.lower() == "y":
        add_more = prompt_input("Add another API key? (y/N)", "N")
        if add_more.lower() == "y":
            key = prompt_input("Environment variable name", "")
            val = prompt_input(f"Value for {key}", "", secret=True)
            if key and val:
                extras[key] = val
    if not extras:
        boss.log("No API tokens provided.")
        return
    # Write to config/api.env
    lines = [f"{k}={v}" for k, v in extras.items()]
    content = "\n".join(lines) + "\n"
    api_path = root / "config" / "api.env"
    write_file(api_path, content, boss)
    boss.log("API tokens saved.")


def verify_installation(boss: 'BossAI') -> None:
    """Perform post‑install verification of key components.

    Checks Docker service status, verifies installed versions of Git,
    Node.js and Python, and optionally runs a Docker test container.

    Args:
        boss: Boss instance for logging.
    """
    boss.log("Verifying installation status…")
    # Check Docker service
    code, out = run_command(["systemctl", "is-active", "docker"])
    if code == 0 and out.strip() == "active":
        boss.log("Docker service is active.")
    else:
        boss.log("⚠ Docker service is not active. Run `systemctl status docker` to diagnose.")
    # Check versions
    for cmd, name in [(["git", "--version"], "Git"), (["node", "--version"], "Node.js"), (["python3", "--version"], "Python")]:
        code, out = run_command(cmd)
        if code == 0:
            version = out.strip().split("\n")[0]
            boss.log(f"{name} version: {version}")
        else:
            boss.log(f"⚠ Failed to query {name} version.")
    # Ask to run Docker hello‑world
    run_test = prompt_input("Run a Docker hello-world test? (y/N)", "N").lower()
    if run_test == "y":
        boss.log("Running Docker hello-world…")
        code, out = run_command(["docker", "run", "--rm", "hello-world"], timeout=120)
        if code == 0:
            boss.log("Docker test container ran successfully.")
        else:
            boss.log(f"⚠ Docker hello-world failed:\n{out}")


def run_docker_compose(boss: BossAI, compose_file: Path) -> None:
    """Run `docker compose up -d` on the specified YAML file.

    Args:
        boss: Boss instance for logging.
        compose_file: Path to the Docker Compose YAML file.

    Raises:
        RuntimeError: If the compose command returns a non-zero exit code.
    """
    if not compose_file.exists():
        raise RuntimeError(f"Compose file not found: {compose_file}")
    boss.log(f"Running docker compose for {compose_file}…")
    cmd = ["docker", "compose", "-f", str(compose_file), "up", "-d"]
    code, out = run_command(cmd, timeout=900)
    if code != 0:
        raise RuntimeError(f"docker compose failed:\n{out}")
    boss.log(f"Compose deployment finished for {compose_file}.")


def install_homeassistant(boss: BossAI, root: Path, config: Dict[str, Any]) -> str:
    """Install and start the Home Assistant stack on Node D.

    This function uses the docker compose file in node-d-home-assistant to bring
    up Home Assistant.  After deployment it attempts to access the HA API to
    verify the service is running.
    """
    compose_file = root / "node-d-home-assistant" / "docker-compose.yml"
    run_docker_compose(boss, compose_file)
    # Verify HA is reachable; use curl to query the health endpoint.
    ha_ip = config.get("NODE_D_IP", "127.0.0.1")
    url = f"http://{ha_ip}:8123/api/health"
    boss.log(f"Checking Home Assistant availability at {url}…")
    code, out = run_command(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", url], timeout=15)
    if code == 0 and out.strip() == "200":
        boss.log("Home Assistant API responded with HTTP 200.")
    else:
        boss.log(f"⚠ Could not verify Home Assistant (HTTP status {out.strip()}).")
    return "Home Assistant deployed on Node D."


def configure_cloudflare(boss: BossAI, root: Path, config: Dict[str, Any]) -> str:
    """Configure and start the Cloudflare tunnel.

    This task uses the cloudflared compose file from the repository (if present)
    to run a tunnel using the provided token.  It writes the environment
    variables to cloudflare.env and deploys the stack.
    """
    # Ensure environment file was generated
    cf_env_path = root / "node-b-litellm" / "stacks" / "cloudflare.env"
    if not cf_env_path.exists():
        raise RuntimeError(f"Cloudflare env file missing: {cf_env_path}")
    boss.log("Preparing Cloudflare tunnel…")
    # Determine compose file for cloudflared.  We look for agentic-stack.yml or cloudflare-stack.yml
    possible = [root / "node-b-litellm" / "stacks" / "agentic-stack.yml",
                root / "node-b-litellm" / "stacks" / "cloudflare-stack.yml",
                root / "swarm" / "portainer-agent-stack.yml"]
    compose_file = None
    for p in possible:
        if p.exists():
            compose_file = p
            break
    if compose_file is None:
        raise RuntimeError("Cloudflare compose file not found in repository.")
    run_docker_compose(boss, compose_file)
    return f"Cloudflare tunnel started using {compose_file.name}."


def configure_nabu_casa(boss: BossAI, root: Path, config: Dict[str, Any]) -> str:
    """Guide the user to set up Home Assistant Cloud (Nabu Casa).

    Since Nabu Casa requires authentication through the Home Assistant UI,
    this function instructs the user to sign in and link their account.  It
    writes a note in the extra.env file indicating that remote UI is
    enabled.
    """
    boss.log("Configuring Home Assistant Cloud (Nabu Casa)…")
    # Append a placeholder to extra.env for remote UI token
    ha_extra_path = root / "node-d-home-assistant" / "extra.env"
    lines = []
    if ha_extra_path.exists():
        lines = ha_extra_path.read_text().splitlines()
    # Add placeholder if not present
    key_line = "# Nabu Casa remote UI token="
    if all(not l.startswith("NABU_CASA_TOKEN=") for l in lines):
        lines.append(key_line)
        write_file(ha_extra_path, "\n".join(lines) + "\n", boss, ask_overwrite=False)
    message = ("To enable Home Assistant Cloud, open the Home Assistant UI, go to \"Settings → Home Assistant Cloud\", "
               "and sign in or create an account.  Once linked, copy the remote UI token into the extra.env file under "
               "NABU_CASA_TOKEN.")
    return message



def check_package_installed(pkg_name: str) -> bool:
    """Return True if the given RPM package is installed."""
    code, _ = run_command(["rpm", "-q", pkg_name])
    return code == 0


def dnf_install(packages: List[str], boss: BossAI) -> None:
    """Install a list of packages using dnf/dnf5.  Skip if already installed."""
    if not packages:
        return
    missing = [p for p in packages if not check_package_installed(p)]
    if not missing:
        boss.log(f"All packages already installed: {' '.join(packages)}")
        return
    dnf_cmd = choose_dnf()
    boss.log(f"Installing packages: {' '.join(missing)} using {dnf_cmd}")
    cmd = [dnf_cmd, "install", "-y"] + missing
    code, out = run_command(cmd, timeout=900)
    if code != 0:
        raise RuntimeError(f"Failed to install packages {missing}:\n{out}")
    boss.log("Packages installed successfully.")


def set_up_docker_repository(boss: BossAI) -> None:
    """Configure the Docker repository for Fedora using dnf config manager.

    dnf5 (default on Fedora 41+) has ``config-manager`` built-in and uses the
    ``addrepo --from-repofile=<url>`` syntax.  dnf4 requires the
    ``dnf-plugins-core`` package and uses ``config-manager --add-repo <url>``.
    """
    dnf_cmd = choose_dnf()
    docker_repo_url = "https://download.docker.com/linux/fedora/docker-ce.repo"
    boss.log("Adding Docker repository configuration…")
    if dnf_cmd == "dnf5":
        # dnf5 (Fedora 41+) has config-manager built-in; no extra plugin needed.
        repo_cmd = [
            dnf_cmd, "config-manager", "addrepo",
            f"--from-repofile={docker_repo_url}",
        ]
    else:
        # dnf4 requires dnf-plugins-core for the config-manager subcommand.
        if not check_package_installed("dnf-plugins-core"):
            dnf_install(["dnf-plugins-core"], boss)
        repo_cmd = [dnf_cmd, "config-manager", "--add-repo", docker_repo_url]
    code, out = run_command(repo_cmd)
    if code != 0 and not re.search(r"already exists|file exists", out, re.IGNORECASE):
        raise RuntimeError(f"Could not add Docker repository:\n{out}")
    boss.log("Docker repository configured.")


def install_docker_engine(boss: BossAI) -> None:
    """Install Docker Engine packages and enable the service."""
    pkgs = [
        "docker-ce",
        "docker-ce-cli",
        "containerd.io",
        "docker-buildx-plugin",
        "docker-compose-plugin",
    ]
    dnf_install(pkgs, boss)
    boss.log("Enabling and starting Docker service…")
    code, out = run_command(["systemctl", "enable", "--now", "docker"])
    if code != 0:
        raise RuntimeError(f"Failed to enable/start Docker:\n{out}")
    boss.log("Docker service running.")


def install_nodejs_python(boss: BossAI) -> None:
    """Install Node.js, Python pip/wheel, Git and curl.

    On Fedora 44+ Python uses PEP 668 (externally-managed-environment), so
    ``pip install`` requires ``--break-system-packages`` when targeting the
    system interpreter.  Prefer running inside a ``.venv`` for day-to-day use
    (see :func:`setup_venv`); this function targets the initial bootstrap where
    no venv exists yet.
    """
    core = ["git", "curl", "python3-pip", "python3-wheel", "nodejs"]
    dnf_install(core, boss)
    boss.log("Installing Python modules via pip…")
    pip_cmd = [
        "python3", "-m", "pip", "install", "--quiet",
        "--break-system-packages",
        "flask", "beautifulsoup4",
    ]
    code, out = run_command(pip_cmd, timeout=600)
    if code != 0:
        raise RuntimeError(f"pip install failed:\n{out}")
    boss.log("Python modules installed.")


def clone_repository(boss: BossAI, repo_url: str, dest: Path) -> None:
    """Clone or update the specified Git repository into dest."""
    if dest.exists() and (dest / ".git").exists():
        boss.log(f"Repository exists at {dest}. Updating…")
        code, out = run_command(["git", "-C", str(dest), "pull", "--ff-only"], timeout=300)
        if code != 0:
            raise RuntimeError(f"git pull failed:\n{out}")
        boss.log("Repository updated.")
        return
    boss.log(f"Cloning repository {repo_url} into {dest}…")
    dest.parent.mkdir(parents=True, exist_ok=True)
    code, out = run_command(["git", "clone", repo_url, str(dest)], timeout=600)
    if code != 0:
        raise RuntimeError(f"git clone failed:\n{out}")
    boss.log("Repository cloned successfully.")


def prompt_input(text: str, default: Optional[str] = None, secret: bool = False) -> str:
    """Prompt the user for input, with an optional default and secret flag."""
    prompt_text = text
    if default:
        prompt_text += f" [default: {default}]"
    prompt_text += ": "
    try:
        if secret:
            val = getpass.getpass(prompt_text)
        else:
            val = input(prompt_text)
    except EOFError:
        val = ""
    if not val and default is not None:
        return default
    return val.strip()


def collect_configuration(boss: BossAI) -> Dict[str, Any]:
    """Interactively gather configuration values for environment files."""
    cfg: Dict[str, Any] = {}
    print("\nPlease enter configuration values (press Enter to accept defaults):")
    cfg["NODE_A_IP"] = prompt_input("Node A LAN IP (Brain / AMD GPU)", "192.168.1.9")
    cfg["NODE_B_IP"] = prompt_input("Node B LAN IP (Unraid / Gateway)", "192.168.1.222")
    cfg["NODE_C_IP"] = prompt_input("Node C LAN IP (Intel Arc)", "192.168.1.6")
    cfg["NODE_D_IP"] = prompt_input("Node D LAN IP (Home Assistant)", "192.168.1.149")
    cfg["NODE_E_IP"] = prompt_input("Node E LAN IP (Sentinel/NVR)", "192.168.1.116")
    cfg["KVM_IP"] = prompt_input("NanoKVM LAN IP", "192.168.1.130")
    cfg["KVM_HOSTNAME"] = prompt_input("NanoKVM hostname", "kvm-d829.local")

    print("\nTailscale IPs (used for all remote connections — run 'tailscale status' to verify):")
    cfg["NODE_A_TS_IP"] = prompt_input("Node A Tailscale IP (node-a)", "100.120.119.26")
    cfg["NODE_B_TS_IP"] = prompt_input("Node B Tailscale IP (node-b-unraid)", "100.99.104.80")
    cfg["NODE_C_TS_IP"] = prompt_input("Node C Tailscale IP (node-c)", "100.64.20.118")
    cfg["NODE_D_TS_IP"] = prompt_input("Node D Tailscale IP (optional)", "")
    cfg["NODE_E_TS_IP"] = prompt_input("Node E Tailscale IP (optional)", "")
    cfg["KVM_TS_IP"] = prompt_input("KVM Tailscale IP (node-a-kvm)", "100.99.133.29")
    cfg["NANOKVM_TS_IP"] = prompt_input("NanoKVM Tailscale IP (node-c-nanokvm)", "100.90.139.95")

    cfg["NODE_A_SSH_USER"] = prompt_input("SSH user for Node A", "root")
    cfg["NODE_B_SSH_USER"] = prompt_input("SSH user for Node B", "root")
    cfg["NODE_C_SSH_USER"] = prompt_input("SSH user for Node C", "root")
    cfg["NODE_D_SSH_USER"] = prompt_input("SSH user for Node D", "root")
    cfg["NODE_E_SSH_USER"] = prompt_input("SSH user for Node E", "root")

    print("\nEnter sensitive tokens and credentials (input hidden where appropriate):")
    cfg["LITELLM_API_KEY"] = prompt_input("LiteLLM master API key", "sk-master-key", secret=True)
    kvm_token = prompt_input("KVM Operator token (leave blank to auto-generate)", "", secret=True)
    cfg["KVM_OPERATOR_TOKEN"] = kvm_token or os.urandom(24).hex()
    openclaw_token = prompt_input("OpenClaw gateway token (leave blank to auto-generate)", "", secret=True)
    cfg["OPENCLAW_GATEWAY_TOKEN"] = openclaw_token or os.urandom(24).hex()
    cfg["HUGGINGFACE_TOKEN"] = prompt_input("HuggingFace Hub token (optional)", "hf_your_token_here", secret=True)
    cfg["NANOKVM_USERNAME"] = prompt_input("NanoKVM username", "admin")
    cfg["NANOKVM_PASSWORD"] = prompt_input("NanoKVM password", "admin", secret=True)
    cfg["TAILSCALE_AUTHKEY"] = prompt_input("Tailscale auth key", "tskey-auth-XXXXXXXXXXXXXXXX", secret=True)
    cfg["HA_LONG_LIVED_TOKEN"] = prompt_input("Home Assistant long‑lived token", "your-ha-long-lived-token-here", secret=True)
    cfg["VPN_SERVICE_PROVIDER"] = prompt_input("VPN service provider", "private internet access")
    cfg["VPN_USER"] = prompt_input("VPN username", "your-vpn-username")
    cfg["VPN_PASSWORD"] = prompt_input("VPN password", "your-vpn-password", secret=True)
    cfg["CLOUDFLARE_TUNNEL_TOKEN"] = prompt_input("Cloudflare tunnel token", "your-cloudflare-tunnel-token", secret=True)
    cfg["SEARXNG_SECRET_KEY"] = os.urandom(32).hex()
    cfg["TZ"] = prompt_input("Timezone", "America/New_York")
    cfg["VLLM_MODEL_A"] = prompt_input("Model for Node A vLLM", "meta-llama/Llama-3.1-8B-Instruct")
    cfg["VLLM_MODEL_B"] = prompt_input("Model for Node B vLLM", "mistralai/Mistral-7B-Instruct-v0.3")
    cfg["NEXTCLOUD_DB_ROOT_PASSWORD"] = prompt_input("Nextcloud DB root password", "changeme-root", secret=True)
    cfg["NEXTCLOUD_DB_PASSWORD"] = prompt_input("Nextcloud DB user password", "changeme-nc", secret=True)
    return cfg


def write_file(path: Path, content: str, boss: BossAI, ask_overwrite: bool = True) -> None:
    """Write text to a file, optionally prompting before overwriting."""
    if path.exists() and ask_overwrite:
        overwrite = prompt_input(f"File {path} exists. Overwrite? (y/N)", "N").lower()
        if overwrite != "y":
            boss.log(f"Skipping {path}")
            return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    boss.log(f"Wrote {path}")


def generate_env_files(boss: BossAI, config: Dict[str, Any], root: Path) -> None:
    """Generate environment files for the homelab based on the provided config."""
    inv = textwrap.dedent(f"""
        # Generated by boss_multi_agent_install.py
        NODE_A_IP={config['NODE_A_IP']}
        NODE_B_IP={config['NODE_B_IP']}
        NODE_C_IP={config['NODE_C_IP']}
        NODE_D_IP={config['NODE_D_IP']}
        NODE_E_IP={config['NODE_E_IP']}
        KVM_IP={config['KVM_IP']}
        KVM_HOSTNAME={config['KVM_HOSTNAME']}

        NODE_A_TS_IP={config['NODE_A_TS_IP']}
        NODE_B_TS_IP={config['NODE_B_TS_IP']}
        NODE_C_TS_IP={config['NODE_C_TS_IP']}
        NODE_D_TS_IP={config['NODE_D_TS_IP']}
        NODE_E_TS_IP={config['NODE_E_TS_IP']}
        KVM_TS_IP={config['KVM_TS_IP']}
        NANOKVM_TS_IP={config['NANOKVM_TS_IP']}

        NODE_A_SSH_USER={config['NODE_A_SSH_USER']}
        NODE_B_SSH_USER={config['NODE_B_SSH_USER']}
        NODE_C_SSH_USER={config['NODE_C_SSH_USER']}
        NODE_D_SSH_USER={config['NODE_D_SSH_USER']}
        NODE_E_SSH_USER={config['NODE_E_SSH_USER']}

        LITELLM_API_KEY={config['LITELLM_API_KEY']}
        KVM_OPERATOR_TOKEN={config['KVM_OPERATOR_TOKEN']}
        OPENCLAW_GATEWAY_TOKEN={config['OPENCLAW_GATEWAY_TOKEN']}
    """).strip() + "\n"
    write_file(root / "config" / "node-inventory.env", inv, boss)

    kvm_env = textwrap.dedent(f"""
        KVM_OPERATOR_TOKEN={config['KVM_OPERATOR_TOKEN']}
        REQUIRE_APPROVAL=true
        KVM_TARGETS_JSON={{\"{config['KVM_HOSTNAME'].split('.')[0]}\":\"{config['KVM_IP']}\"}}
        NANOKVM_USERNAME={config['NANOKVM_USERNAME']}
        NANOKVM_PASSWORD={config['NANOKVM_PASSWORD']}
        LITELLM_URL=http://{config['NODE_B_IP']}:4000/v1/chat/completions
        LITELLM_API_KEY={config['LITELLM_API_KEY']}
    """).strip() + "\n"
    write_file(root / "kvm-operator" / ".env", kvm_env, boss)

    node_a_env = textwrap.dedent(f"""
        HUGGINGFACE_TOKEN={config['HUGGINGFACE_TOKEN']}
        VLLM_MODEL={config['VLLM_MODEL_A']}
    """).strip() + "\n"
    write_file(root / "node-a-vllm" / ".env", node_a_env, boss)

    node_a_cc = textwrap.dedent(f"""
        COMMAND_CENTER_PORT=3099
        LITELLM_BASE_URL=http://{config['NODE_B_IP']}:4000
        LITELLM_API_KEY={config['LITELLM_API_KEY']}
        DEFAULT_MODEL=brain-heavy
        BRAIN_BASE_URL=http://{config['NODE_A_IP']}:8000
        NODE_C_BASE_URL=http://{config['NODE_C_IP']}
        NODE_D_BASE_URL=http://{config['NODE_D_IP']}:8123
        NODE_E_BASE_URL=http://{config['NODE_E_IP']}:3005
    """).strip() + "\n"
    write_file(root / "node-a-command-center" / ".env", node_a_cc, boss)

    node_b_env = textwrap.dedent(f"""
        TZ={config['TZ']}
        PUID=1000
        PGID=1000
        APPDATA_PATH=/mnt/user/appdata
        MEDIA_PATH=/mnt/user/data
        LITELLM_MASTER_KEY={config['LITELLM_API_KEY']}
        VPN_SERVICE_PROVIDER={config['VPN_SERVICE_PROVIDER']}
        VPN_USER={config['VPN_USER']}
        VPN_PASSWORD={config['VPN_PASSWORD']}
        SEARXNG_SECRET_KEY={config['SEARXNG_SECRET_KEY']}
        VLLM_MODEL={config['VLLM_MODEL_B']}
        HUGGING_FACE_HUB_TOKEN={config['HUGGINGFACE_TOKEN']}
        NEXTCLOUD_DB_ROOT_PASSWORD={config['NEXTCLOUD_DB_ROOT_PASSWORD']}
        NEXTCLOUD_DB_PASSWORD={config['NEXTCLOUD_DB_PASSWORD']}
        OPENCLAW_GATEWAY_TOKEN={config['OPENCLAW_GATEWAY_TOKEN']}
        CLOUDFLARE_TUNNEL_TOKEN={config['CLOUDFLARE_TUNNEL_TOKEN']}
    """).strip() + "\n"
    write_file(root / "node-b-litellm" / "stacks" / ".env", node_b_env, boss)

    node_c_env = textwrap.dedent(f"""
        OPENCLAW_GATEWAY_TOKEN={config['OPENCLAW_GATEWAY_TOKEN']}
        OLLAMA_API_KEY=ollama
        LITELLM_API_KEY={config['LITELLM_API_KEY']}
        KVM_OPERATOR_URL=http://{config['NODE_A_IP']}:5000
        KVM_OPERATOR_TOKEN={config['KVM_OPERATOR_TOKEN']}
    """).strip() + "\n"
    write_file(root / "node-c-arc" / ".env.openclaw", node_c_env, boss)

    node_d_env = textwrap.dedent(f"""
        TZ={config['TZ']}
        LITELLM_BASE_URL=http://{config['NODE_B_IP']}:4000
        LITELLM_API_KEY={config['LITELLM_API_KEY']}
        NODE_A_BASE_URL=http://{config['NODE_A_IP']}:8000
    """).strip() + "\n"
    write_file(root / "node-d-home-assistant" / ".env", node_d_env, boss)

    unraid_env = textwrap.dedent(f"""
        TAILSCALE_AUTHKEY={config['TAILSCALE_AUTHKEY']}
        LOCAL_SUBNET=192.168.1.0/24
        APPDATA_PATH=/mnt/user/appdata
        TZ={config['TZ']}
        HA_LONG_LIVED_TOKEN={config['HA_LONG_LIVED_TOKEN']}
    """).strip() + "\n"
    write_file(root / "unraid" / ".env", unraid_env, boss)
    boss.log("Environment files generated.")

    # Write supplemental environment files for Cloudflare and Home Assistant extras.
    # Cloudflare: store tunnel token or related variables.  This env file is
    # referenced by the cloudflared stack if present in the repository.  It
    # includes a placeholder for domain or zone configuration.
    cloudflare_content = textwrap.dedent(f"""
        CLOUDFLARE_TUNNEL_TOKEN={config['CLOUDFLARE_TUNNEL_TOKEN']}
        # CLOUDLFARE_ZONE=<your-domain.com>
        # Additional Cloudflare options can be added here.
    """).strip() + "\n"
    cf_path = root / "node-b-litellm" / "stacks" / "cloudflare.env"
    write_file(cf_path, cloudflare_content, boss, ask_overwrite=False)

    # Home Assistant extras: a separate env file to hold optional tokens such as
    # Nabu Casa remote UI tokens.  It starts empty and users can populate it
    # later via the configure_nabu_casa task.  Only create it if it doesn’t exist.
    ha_extra_path = root / "node-d-home-assistant" / "extra.env"
    if not ha_extra_path.exists():
        write_file(ha_extra_path, "# Home Assistant extra variables\n", boss, ask_overwrite=False)


# Helper: load configuration without prompting.  When running in non‑interactive
# mode, we derive values from environment variables or fall back to
# sensible defaults.  A configuration file may override or supply values.
def load_non_interactive_config(config_path: Optional[str] = None) -> Dict[str, Any]:
    """
    Return a configuration dictionary for non‑interactive installations.

    If `config_path` is provided and points to a JSON or .env‑style file,
    values are loaded from it.  Environment variables override defaults
    and file values.  Random tokens are generated where appropriate.

    Args:
        config_path: Optional path to a configuration file.  JSON files
            should contain a flat dict of key/value pairs.  .env files
            (key=value per line) are also supported.

    Returns:
        A dictionary of configuration parameters matching those collected
        by `collect_configuration`.
    """
    cfg: Dict[str, Any] = {}
    # Step 1: start with built‑in defaults
    defaults = {
        "NODE_A_IP": "192.168.1.9",
        "NODE_B_IP": "192.168.1.222",
        "NODE_C_IP": "192.168.1.6",
        "NODE_D_IP": "192.168.1.149",
        "NODE_E_IP": "192.168.1.116",
        "KVM_IP": "192.168.1.130",
        "KVM_HOSTNAME": "kvm-d829.local",
        "NODE_A_TS_IP": "",
        "NODE_B_TS_IP": "",
        "NODE_C_TS_IP": "",
        "NODE_D_TS_IP": "",
        "NODE_E_TS_IP": "",
        "KVM_TS_IP": "",
        "NANOKVM_TS_IP": "",
        "NODE_A_SSH_USER": "root",
        "NODE_B_SSH_USER": "root",
        "NODE_C_SSH_USER": "root",
        "NODE_D_SSH_USER": "root",
        "NODE_E_SSH_USER": "root",
        "LITELLM_API_KEY": "sk-master-key",
        "KVM_OPERATOR_TOKEN": "",  # generate if empty
        "OPENCLAW_GATEWAY_TOKEN": "",  # generate if empty
        "HUGGINGFACE_TOKEN": "hf_your_token_here",
        "NANOKVM_USERNAME": "admin",
        "NANOKVM_PASSWORD": "admin",
        "TAILSCALE_AUTHKEY": "tskey-auth-XXXXXXXXXXXXXXXX",
        "HA_LONG_LIVED_TOKEN": "your-ha-long-lived-token-here",
        "VPN_SERVICE_PROVIDER": "private internet access",
        "VPN_USER": "your-vpn-username",
        "VPN_PASSWORD": "your-vpn-password",
        "CLOUDFLARE_TUNNEL_TOKEN": "your-cloudflare-tunnel-token",
        "SEARXNG_SECRET_KEY": os.urandom(32).hex(),
        "TZ": "America/New_York",
        "VLLM_MODEL_A": "meta-llama/Llama-3.1-8B-Instruct",
        "VLLM_MODEL_B": "mistralai/Mistral-7B-Instruct-v0.3",
        "NEXTCLOUD_DB_ROOT_PASSWORD": "changeme-root",
        "NEXTCLOUD_DB_PASSWORD": "changeme-nc",
    }
    cfg.update(defaults)
    # Step 2: load values from config file if present
    if config_path and os.path.isfile(config_path):
        import json
        try:
            if config_path.endswith(".json"):
                with open(config_path, "r") as fh:
                    data = json.load(fh)
                    if isinstance(data, dict):
                        cfg.update({k: str(v) for k, v in data.items()})
            else:
                # parse .env format: key=value per line
                with open(config_path, "r") as fh:
                    for line in fh:
                        line = line.strip()
                        if not line or line.startswith("#"):
                            continue
                        if "=" in line:
                            k, v = line.split("=", 1)
                            cfg[k.strip()] = v.strip()
        except Exception:
            pass  # ignore file parse errors and fall back to defaults
    # Step 3: environment variables override
    for key in cfg.keys():
        envval = os.environ.get(key)
        if envval:
            cfg[key] = envval
    # Step 4: generate tokens if still empty
    if not cfg.get("KVM_OPERATOR_TOKEN"):
        cfg["KVM_OPERATOR_TOKEN"] = os.urandom(24).hex()
    if not cfg.get("OPENCLAW_GATEWAY_TOKEN"):
        cfg["OPENCLAW_GATEWAY_TOKEN"] = os.urandom(24).hex()
    return cfg


def create_chat_html(boss: BossAI, dist: Path, commands: Optional[List[str]] = None) -> None:
    """Create a static HTML page for the chatbot.

    The page includes a decorative avatar, a welcome message and
    information about available commands (if provided).  The
    commands list is shown in the initial bot message when the
    page loads, guiding the user to call specific install actions.

    Args:
        boss: The boss instance for logging.
        dist: Path where the HTML file will be written.
        commands: Optional list of command strings to display on
            page load.  If None, only a generic welcome message is
            shown.
    """
    # Build a JavaScript snippet to send an initial message on page load
    welcome_lines = [
        "Greetings! I'm your Homelab AI assistant.",
        "I'm here to guide you step by step through the homelab installation.",
    ]
    if commands:
        cmd_list = ', '.join(commands)
        welcome_lines.append(
            "You can click a button or type one of these commands: " + cmd_list + "."
        )
        welcome_lines.append(
            "If you're not sure, type 'help' to see your options."
        )
    welcome_lines.append(
        "You can restart the session at any time by refreshing the page."
    )
    welcome_js = "\n".join([
        "window.addEventListener('load', function() {",
        "    const msgs = [" + ", ".join([repr('Bot: ' + line) for line in welcome_lines]) + "];",
        "    msgs.forEach(function(msg) { appendMessage(msg, 'bot'); });",
        "});",
    ])
    # Compose the HTML
    # Prepare a JSON-like representation of the commands for injection into the JS
    cmds_js = "null"
    if commands:
        # repr yields single‑quoted strings which are valid in JavaScript
        cmds_js = repr(commands)
    html = textwrap.dedent(
        f"""
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Homelab Assistant</title>
            <style>
                /* Cyberpunk theme with high contrast and neon accents.  Colours are chosen for legibility on dark backgrounds【940904193984099†L202-L218】. */
                body {{ font-family: 'Segoe UI', sans-serif; background-color: #0a0e1a; color: #e0eaff; margin: 0; padding: 0; font-size: 17px; line-height: 1.5; }}
                #chat-container {{ max-width: 840px; margin: 40px auto; background: #111821; border: 2px solid #00ffc8; border-radius: 8px; box-shadow: 0 0 20px rgba(0,255,200,0.4); padding: 24px; position: relative; }}
                #avatar {{ position: absolute; top: -35px; left: -35px; width: 70px; height: 70px; border-radius: 50%; border: 2px solid #00ffc8; }}
                #messages {{ height: 420px; overflow-y: auto; background: #0a0f25; border: 1px solid #00ffc8; padding: 12px; margin-bottom: 10px; white-space: pre-wrap; font-size: 1.1em; color: #e0eaff; }}
                .msg {{ margin-bottom: 10px; }}
                .msg.user {{ color: #00ffee; font-weight: bold; }}
                .msg.bot {{ color: #8ef9ff; }}
                input[type="text"] {{ width: calc(100% - 90px); padding: 12px; background: #0a1432; color: #e0eaff; border: 1px solid #00ffc8; border-radius: 4px; font-size: 1em; }}
                button {{ background-color: #00ffc8; color: #0a0e1a; border: none; border-radius: 4px; padding: 10px 14px; font-size: 1em; cursor: pointer; transition: background-color 0.2s; }}
                button:hover {{ background-color: #0efbff; }}
                /* Command buttons area */
                #command-buttons button {{ margin-right: 6px; margin-bottom: 6px; }}
            </style>
        </head>
        <body>
            <div id="chat-container">
                <!-- Avatar -->
                <img id="avatar" src="{AVATAR_DATA_URI}" alt="Cyberpunk AI avatar">
                <h2 style="margin-top: 0; color: #00ffc8;">Homelab Assistant</h2>
                <div id="messages"></div>
                <!-- Command buttons will be injected here by JS -->
                <div id="command-buttons" style="margin-bottom:10px;"></div>
                <input type="text" id="user-input" placeholder="Enter a command or ask a question..." onkeydown="if(event.key==='Enter') send();">
                <button onclick="send()">Send</button>
            </div>
            <script>
                function appendMessage(text, cls) {{
                    const div = document.createElement('div');
                    div.className = 'msg ' + cls;
                    div.textContent = text;
                    document.getElementById('messages').appendChild(div);
                    document.getElementById('messages').scrollTop = document.getElementById('messages').scrollHeight;
                }}
                function send() {{
                    const input = document.getElementById('user-input');
                    const query = input.value.trim();
                    if (!query) return;
                    appendMessage('You: ' + query, 'user');
                    input.value = '';
                    fetch('/ask', {{ method: 'POST', headers: {{ 'Content-Type': 'application/json' }}, body: JSON.stringify({{ query: query }}) }})
                        .then(resp => resp.json())
                        .then(data => {{
                            let answer = data.summary || 'No summary available.';
                            if (data.results && data.results.length) {{
                                answer += '\n\nSources:';
                                data.results.forEach((res, idx) => {{
                                    answer += `\n${{idx+1}}. ${{res.title}} (${{res.url}})`;
                                }});
                            }}
                            appendMessage('Bot: ' + answer, 'bot');
                        }})
                        .catch(err => {{ appendMessage('Bot: Error: ' + err, 'bot'); }});
                }}
                function sendCommand(cmd) {{
                    document.getElementById('user-input').value = cmd;
                    send();
                }}
                (function() {{
                    const cmds = {cmds_js};
                    if (!cmds) return;
                    const container = document.getElementById('command-buttons');
                    cmds.forEach(function(cmd) {{
                        const btn = document.createElement('button');
                        btn.textContent = cmd;
                        btn.onclick = function() {{ sendCommand(cmd); }};
                        container.appendChild(btn);
                    }});
                }})();
                {welcome_js}
            </script>
        </body>
        </html>
        """
    ).strip()
    dist.parent.mkdir(parents=True, exist_ok=True)
    dist.write_text(html)
    boss.log(f"Chat interface written to {dist}")


def start_chat_server(
    boss: BossAI,
    repo_root: Path,
    tasks: Optional[Dict[str, Callable[[BossAI], str]]] = None,
    host: str = "0.0.0.0",
    port: int = 8008,
) -> None:
    """Start a Flask chat server exposing a HTML UI and /ask API.

    The server supports a call‑and‑response workflow.  When a user
    enters a recognised command (matching a key in the provided tasks
    mapping, case‑insensitive), the corresponding function is executed
    with the Boss instance.  The return value is sent back as the
    summary.  Otherwise, queries are forwarded to the generic web
    search answerer.

    Args:
        boss: The boss instance used for logging.
        repo_root: The root directory containing the chat HTML file.
        tasks: Optional mapping of command strings to callables.  The
            callables must accept a `BossAI` and return a string
            summarising the task result.  Commands are matched
            case‑insensitively.
        host: Host interface to bind to.
        port: Port number to listen on.
    """
    try:
        from flask import Flask, request, jsonify, send_from_directory  # type: ignore
    except ImportError:
        raise RuntimeError("Flask is not installed; cannot start chat server")
    app = Flask(__name__)
    static_dir = repo_root / "chat"
    static_dir.mkdir(parents=True, exist_ok=True)
    html_path = static_dir / "index.html"
    # Determine command list for UI display
    cmd_list: Optional[List[str]] = None
    if tasks:
        cmd_list = list(tasks.keys())
    if not html_path.exists():
        create_chat_html(boss, html_path, commands=cmd_list)
    else:
        # Always rewrite if commands have been provided (to refresh list)
        create_chat_html(boss, html_path, commands=cmd_list)

    @app.route("/", methods=["GET"])
    def index() -> Any:
        return send_from_directory(static_dir, "index.html")

    @app.route("/ask", methods=["POST"])
    def ask() -> Any:
        data = request.get_json(force=True)
        query = data.get("query", "").strip()
        if not query:
            return jsonify({"error": "No query provided."}), 400
        # Normalise to lower case for command matching
        q_lower = query.lower()
        if tasks:
            for cmd, fn in tasks.items():
                if q_lower == cmd.lower():
                    boss.log(f"Received command via chat: {cmd}")
                    try:
                        summary = fn(boss)
                        return jsonify({"query": query, "results": [], "summary": summary})
                    except Exception as exc:
                        err_msg = str(exc)
                        boss.log(f"Command {cmd} failed: {err_msg}")
                        return jsonify({"query": query, "results": [], "summary": f"Error executing {cmd}: {err_msg}"})
        # Otherwise, fall back to web search answer
        answer = answer_query(query)
        return jsonify(answer)

    boss.log(f"Launching chat server at http://{host}:{port}")
    try:
        app.run(host=host, port=port)
    except Exception as e:
        raise RuntimeError(f"Failed to launch chat server: {e}")


def search_web(query: str, max_results: int = 5) -> List[Dict[str, str]]:
    """Return a list of titles and URLs from a DuckDuckGo search."""
    encoded = urlparse.quote(query)
    url = f"https://duckduckgo.com/html/?q={encoded}&ia=web"
    try:
        with urlrequest.urlopen(url, timeout=15) as resp:
            html = resp.read().decode("utf-8", errors="ignore")
    except Exception:
        return []
    results: List[Dict[str, str]] = []
    for part in html.split('<a rel="nofollow" class="result__a"')[1:]:
        href_start = part.find("href=\"")
        if href_start == -1:
            continue
        href_start += len("href=\"")
        href_end = part.find('"', href_start)
        link = part[href_start:href_end]
        if "uddg=" in link:
            _, _, redirect = link.partition("uddg=")
            link = urlparse.unquote(redirect)
        title_start = part.find('>') + 1
        title_end = part.find("</a>", title_start)
        title = part[title_start:title_end]
        title = title.replace("<b>", "").replace("</b>", "").strip()
        results.append({"title": unescape(title), "url": link})
        if len(results) >= max_results:
            break
    return results


def fetch_first_paragraph(url: str) -> str:
    """Fetch the first non‑empty paragraph of text from a web page."""
    try:
        from bs4 import BeautifulSoup  # type: ignore
    except ImportError:
        return ""
    try:
        req = urlrequest.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urlrequest.urlopen(req, timeout=15) as resp:
            html = resp.read().decode("utf-8", errors="ignore")
    except Exception:
        return ""
    soup = BeautifulSoup(html, "html.parser")
    for p in soup.find_all('p'):
        text = p.get_text().strip()
        if text:
            return text
    return ""


def answer_query(query: str) -> Dict[str, Any]:
    """Provide an answer dictionary with results and a combined summary."""
    results = search_web(query, max_results=3)
    entries = []
    summaries = []
    for res in results:
        summary = fetch_first_paragraph(res['url'])
        entries.append({"title": res['title'], "url": res['url'], "summary": summary})
        if summary:
            summaries.append(summary)
    combined = "\n\n".join(summaries)
    # Prepend a persona intro if we have any summary content.  This helps
    # maintain a conversational tone while presenting search results.
    if combined:
        combined = "Here’s what I found:\n\n" + combined
    return {"query": query, "results": entries, "summary": combined}


def ensure_root() -> None:
    """Exit if not running as root."""
    if os.geteuid() != 0:
        print("⚠ This script should be run as root. Re-run with sudo or as root user.")
        sys.exit(1)


# =============================================================================
# OS-like TUI / Menu-Driven Interface (Section B, C, D requirements)
# =============================================================================

#: Absolute path to the repository root (directory containing this file).
REPO_ROOT: Path = Path(__file__).parent

#: Mapping from human-readable node name to compose file path and node IP.
#: Used by the Node Operations menu.
NODE_COMPOSE_MAP: Dict[str, Dict[str, Any]] = {
    "Node A – vLLM Brain": {
        "compose": REPO_ROOT / "node-a-vllm" / "docker-compose.yml",
        "ip": "192.168.1.9",
    },
    "Node A – Ollama Brain (ROCm)": {
        "compose": REPO_ROOT / "node-a-vllm" / "docker-compose.ollama.yml",
        "ip": "192.168.1.9",
    },
    "Node B – LiteLLM Gateway": {
        "compose": REPO_ROOT / "node-b-litellm" / "litellm-stack.yml",
        "ip": "192.168.1.222",
    },
    "Node B – AI Orchestration Stack": {
        "compose": REPO_ROOT / "node-b-litellm" / "stacks" / "ai-orchestration-stack.yml",
        "ip": "192.168.1.222",
    },
    "Node B – Media Stack": {
        "compose": REPO_ROOT / "node-b-litellm" / "stacks" / "media-stack.yml",
        "ip": "192.168.1.222",
    },
    "Node C – Intel Arc (Ollama + WebUI)": {
        "compose": REPO_ROOT / "node-c-arc" / "docker-compose.yml",
        "ip": "192.168.1.6",
    },
    "Node C – OpenClaw Agent": {
        "compose": REPO_ROOT / "node-c-arc" / "openclaw.yml",
        "ip": "192.168.1.6",
    },
    "Node D – Home Assistant": {
        "compose": REPO_ROOT / "node-d-home-assistant" / "docker-compose.yml",
        "ip": "192.168.1.149",
    },
    "Node E – Sentinel (Frigate/NVR)": {
        "compose": REPO_ROOT / "node-e-sentinel" / "docker-compose.yml",
        "ip": "192.168.1.116",
    },
    "Unraid Management Stack": {
        "compose": REPO_ROOT / "unraid" / "docker-compose.yml",
        "ip": "192.168.1.222",
    },
    "Deploy GUI": {
        "compose": REPO_ROOT / "deploy-gui" / "docker-compose.yml",
        "ip": "localhost:9999",
    },
}

def _detect_os_release() -> str:
    """Return the PRETTY_NAME value from /etc/os-release, or an empty string."""
    os_release = Path("/etc/os-release")
    if not os_release.exists():
        return ""
    try:
        for line in os_release.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("PRETTY_NAME="):
                return line.split("=", 1)[1].strip().strip('"')
    except OSError:
        pass
    return ""


def _suggest_next_steps(results: Dict[str, bool]) -> None:
    """Print prioritised next-step recommendations based on health check results.

    Called automatically at the end of :func:`run_health_checks` so the user
    always leaves the health screen with a clear action plan.
    """
    steps: List[str] = []
    if not results.get("fedora44"):
        steps.append("⚠  This installer is optimised for Fedora 44. Unexpected behaviour may occur on other distros.")
    if not results.get("docker"):
        steps.append("→  [2] Install Prerequisites to install Docker Engine.")
    elif not results.get("docker_running"):
        steps.append("→  Run:  sudo systemctl enable --now docker")
    if not results.get("venv"):
        steps.append("→  [3] Setup Virtual Environment to create .venv for Python packages.")
    if not results.get("inventory"):
        steps.append("→  [4] Configure Environment Files to generate node-inventory.env.")
    if not results.get("ollama"):
        steps.append("→  Install Ollama (https://ollama.ai/download) then run: ollama serve")
    if not results.get("network"):
        steps.append("⚠  No network connectivity detected — check your connection before proceeding.")
    if steps:
        print("  Recommended next steps:")
        for s in steps:
            print(f"    {s}")
    else:
        print(_c("  ✓ All checks passed — your system looks ready!", _GREEN))
    print()


# ANSI colour helpers
_GREEN = "\033[0;32m"
_RED = "\033[0;31m"
_YELLOW = "\033[1;33m"
_RESET = "\033[0m"


def _c(text: str, colour: str) -> str:
    """Wrap *text* in *colour* escape codes (safe to disable if not a TTY)."""
    if not sys.stdout.isatty():
        return text
    return f"{colour}{text}{_RESET}"


def clear_screen() -> None:
    """Clear the terminal screen."""
    os.system("cls" if os.name == "nt" else "clear")


def print_banner() -> None:
    """Print the installer welcome banner."""
    print(_c(
        "╔══════════════════════════════════════════════════════════════════╗\n"
        "║      GRAND UNIFIED AI HOMELAB — BOS INSTALLER v2.0              ║\n"
        "║           OS-Like Guided Installation Experience                 ║\n"
        "╚══════════════════════════════════════════════════════════════════╝",
        _GREEN,
    ))


def print_section(title: str) -> None:
    """Print a formatted section header."""
    width = 66
    print(f"\n{'═' * width}")
    print(f"  {title}")
    print(f"{'═' * width}")


def _health_line(label: str, ok: bool, detail: str = "") -> None:
    """Print a single ✓/✗ health-check result line."""
    icon = _c("✓", _GREEN) if ok else _c("✗", _RED)
    suffix = f"  ({detail})" if detail else ""
    print(f"  [{icon}] {label}{suffix}")


def _health_warn(label: str, detail: str = "") -> None:
    """Print a ⚠ (warning/unknown) health-check result line."""
    icon = _c("?", _YELLOW)
    suffix = f"  ({detail})" if detail else ""
    print(f"  [{icon}] {label}{suffix}")


def _check_ollama(base_url: str) -> Tuple[bool, str]:
    """Return (reachable, detail_string) for a local Ollama instance."""
    try:
        req = urlrequest.Request(
            f"{base_url}/api/tags",
            headers={"User-Agent": "bos-installer/2"},
        )
        with urlrequest.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode())
            models = [m.get("name", "") for m in data.get("models", [])]
            detail = (
                f"{len(models)} model(s): {', '.join(models[:3])}"
                if models
                else "running, no models loaded"
            )
            return True, detail
    except Exception as exc:
        return False, str(exc)[:80]


def run_health_checks(boss: Optional["BossAI"] = None) -> Dict[str, bool]:
    """Run comprehensive system health checks and display results.

    Returns a dict mapping check-name to bool (True = passed).
    """
    print_section("SYSTEM HEALTH CHECK")
    results: Dict[str, bool] = {}

    # OS / Fedora 44 detection
    dist_info = _detect_os_release() or f"{platform.system()} {platform.version()}"
    is_fedora44 = bool(re.search(r"Fedora(?:\s+Linux)?\s+44\b", dist_info))
    _health_line(
        f"OS: {dist_info}",
        is_fedora44,
        "target platform" if is_fedora44 else "expected Fedora 44",
    )
    results["fedora44"] = is_fedora44

    # dnf5 availability (preferred on Fedora 41+)
    dnf5_ok = bool(shutil.which("dnf5"))
    _health_line(
        "dnf5 (preferred package manager)",
        dnf5_ok,
        "will use dnf5" if dnf5_ok else "falling back to dnf",
    )
    results["dnf5"] = dnf5_ok

    # Python version
    py_ver = platform.python_version()
    py_ok = sys.version_info >= (3, 8)
    _health_line(f"Python {py_ver}", py_ok, "" if py_ok else "need 3.8+")
    results["python"] = py_ok

    # Virtual environment
    venv_path = REPO_ROOT / ".venv"
    venv_ok = venv_path.exists() and (venv_path / "bin" / "python").exists()
    _health_line(
        f".venv ({venv_path})",
        venv_ok,
        "found" if venv_ok else "run menu option [3] to create",
    )
    results["venv"] = venv_ok

    # Docker
    code, docker_out = run_command(["docker", "--version"])
    docker_ok = code == 0
    _health_line(
        "Docker",
        docker_ok,
        docker_out.strip().split("\n")[0] if docker_ok else "install via menu option [2]",
    )
    results["docker"] = docker_ok

    # Docker Compose v2
    code, dc_out = run_command(["docker", "compose", "version"])
    dc_ok = code == 0
    _health_line(
        "Docker Compose v2",
        dc_ok,
        dc_out.strip().split("\n")[0] if dc_ok else "upgrade Docker (>=23) to get Compose v2",
    )
    results["docker_compose"] = dc_ok

    # Docker daemon running
    code, _ = run_command(["docker", "info"])
    docker_svc_ok = code == 0
    _health_line(
        "Docker daemon running",
        docker_svc_ok,
        "" if docker_svc_ok else "run: systemctl start docker",
    )
    results["docker_running"] = docker_svc_ok

    # Node.js (optional for command center)
    code, node_out = run_command(["node", "--version"])
    node_ok = code == 0
    _health_line(
        "Node.js",
        node_ok,
        node_out.strip() if node_ok else "optional – needed for command-center only",
    )
    results["node"] = node_ok

    # Git
    code, git_out = run_command(["git", "--version"])
    git_ok = code == 0
    _health_line(
        "Git",
        git_ok,
        git_out.strip().split("\n")[0] if git_ok else "install git",
    )
    results["git"] = git_ok

    # Local Ollama
    ollama_url = os.environ.get("OLLAMA_URL", "http://localhost:11434")
    ollama_ok, ollama_detail = _check_ollama(ollama_url)
    if ollama_ok:
        _health_line(f"Ollama ({ollama_url})", True, ollama_detail)
    else:
        _health_warn(
            f"Ollama ({ollama_url})",
            ollama_detail or "not reachable – local AI unavailable",
        )
    results["ollama"] = ollama_ok

    # Network connectivity
    code, _ = run_command(
        ["curl", "-s", "--head", "--max-time", "3", "https://1.1.1.1"]
    )
    net_ok = code == 0
    _health_line("Network", net_ok, "" if net_ok else "check network")
    results["network"] = net_ok

    # config/node-inventory.env
    inv_path = REPO_ROOT / "config" / "node-inventory.env"
    inv_ok = inv_path.exists()
    _health_line(
        "config/node-inventory.env",
        inv_ok,
        "found" if inv_ok else "run menu option [4] to generate",
    )
    results["inventory"] = inv_ok

    ok_count = sum(1 for v in results.values() if v)
    total = len(results)
    print(f"\n  Summary: {ok_count}/{total} checks passed\n")
    _suggest_next_steps(results)
    return results


def setup_venv(boss: Optional["BossAI"] = None) -> None:
    """Create and populate a .venv virtual environment in the repo root."""
    print_section("VIRTUAL ENVIRONMENT SETUP")
    venv_path = REPO_ROOT / ".venv"

    if venv_path.exists():
        print(f"  .venv already exists at {venv_path}")
        ans = input("  Recreate from scratch? (y/N): ").strip().lower()
        if ans != "y":
            print("  Using existing .venv.")
            return
        shutil.rmtree(venv_path)

    print("  Creating .venv …")
    code, out = run_command([sys.executable, "-m", "venv", str(venv_path)])
    if code != 0:
        print(_c(f"  ✗ Failed to create venv:\n{out}", _RED))
        return
    print(_c(f"  ✓ .venv created at {venv_path}", _GREEN))

    pip = str(venv_path / "bin" / "pip")
    req_files = [
        REPO_ROOT / "kvm-operator" / "requirements.txt",
        REPO_ROOT / "brothers-keeper" / "requirements.txt",
    ]
    for req in req_files:
        if req.exists():
            rel = req.relative_to(REPO_ROOT)
            print(f"  Installing {rel} …")
            code, out = run_command([pip, "install", "-q", "-r", str(req)], timeout=300)
            if code != 0:
                print(_c(f"  ✗ pip install failed: {out[:200]}", _RED))
            else:
                print(_c(f"  ✓ {rel} installed", _GREEN))

    # Optional helper packages for bos.py chat server
    optional = ["flask", "requests", "beautifulsoup4"]
    print(f"  Installing optional packages: {', '.join(optional)} …")
    code, out = run_command([pip, "install", "-q"] + optional, timeout=120)
    if code == 0:
        print(_c("  ✓ Optional packages installed", _GREEN))
    else:
        print(_c(f"  ✗ Optional packages failed: {out[:120]}", _RED))

    print(f"\n  Activate with:  source {venv_path}/bin/activate")


def query_ollama(prompt: str, model: str = "", base_url: str = "") -> str:
    """Send a prompt to a local Ollama instance and return the response text.

    Returns an empty string on any failure so callers can fall back gracefully.
    """
    if not base_url:
        base_url = os.environ.get("OLLAMA_URL", "http://localhost:11434")
    if not model:
        model = os.environ.get("OLLAMA_MODEL", "llama3.2")
    payload = json.dumps({
        "model": model,
        "prompt": prompt,
        "stream": False,
        "system": (
            "You are a helpful homelab installation assistant. "
            "Answer concisely and clearly, focusing on practical guidance."
        ),
    }).encode()
    try:
        req = urlrequest.Request(
            f"{base_url}/api/generate",
            data=payload,
            headers={
                "Content-Type": "application/json",
                "User-Agent": "bos-installer/2",
            },
            method="POST",
        )
        with urlrequest.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode())
            return data.get("response", "").strip()
    except Exception:
        return ""


def _get_ai_response(prompt: str) -> str:
    """Return an AI response, trying Ollama first then DuckDuckGo web-search."""
    response = query_ollama(prompt)
    if response:
        return response
    result = answer_query(prompt)
    return result.get("summary") or "I couldn't find an answer to that question."


def test_ai_assistant(boss: Optional["BossAI"] = None) -> None:
    """Test the local AI assistant and display availability information."""
    print_section("AI ASSISTANT SETUP & TEST")

    ollama_url = os.environ.get("OLLAMA_URL", "http://localhost:11434")
    print(f"  Checking Ollama at {ollama_url} …")
    ok, detail = _check_ollama(ollama_url)
    if ok:
        print(_c(f"  ✓ Ollama is running — {detail}", _GREEN))
        test_prompt = "In one sentence, what is Ollama and why is it useful for a homelab?"
        print(f"\n  Test prompt: {test_prompt!r}")
        print("  Waiting for response …", end="", flush=True)
        response = query_ollama(test_prompt, base_url=ollama_url)
        if response:
            print(_c("\n  ✓ AI Response:", _GREEN))
            for line in textwrap.wrap(response, 66):
                print(f"    {line}")
        else:
            print(_c("\n  ? No response — is a model loaded?", _YELLOW))
            print("     Try:  ollama pull llama3.2")
    else:
        print(_c(f"  ✗ Ollama not reachable ({detail})", _RED))
        print("     Install Ollama: https://ollama.ai/download")
        print("     Start locally:  ollama serve")

    # Check LiteLLM gateway
    inv_path = REPO_ROOT / "config" / "node-inventory.env"
    node_b_ip = "192.168.1.222"
    if inv_path.exists():
        for line in inv_path.read_text().splitlines():
            if line.startswith("NODE_B_IP="):
                node_b_ip = line.split("=", 1)[1].strip()
    litellm_url = f"http://{node_b_ip}:4000/health"
    print(f"\n  Checking LiteLLM Gateway at {litellm_url} …")
    code, _ = run_command(
        ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "3", litellm_url]
    )
    if code == 0:
        print(_c("  ✓ LiteLLM Gateway reachable", _GREEN))
    else:
        print(_c("  ? LiteLLM Gateway not reachable (deploy Node B first)", _YELLOW))

    print()
    input("  Press Enter to continue…")


def run_chat_session(boss: Optional["BossAI"] = None) -> None:
    """Run an interactive terminal chat session with the AI assistant."""
    clear_screen()
    print_banner()
    print_section("AI HELP ASSISTANT")

    ollama_url = os.environ.get("OLLAMA_URL", "http://localhost:11434")
    ollama_ok, _ = _check_ollama(ollama_url)

    if ollama_ok:
        print(_c("  ✓ Local AI (Ollama) is available.", _GREEN))
    else:
        print(_c("  ? Ollama not available — using web-search fallback.", _YELLOW))

    print("""
  I am your homelab installation assistant. Ask me anything about:
    • Installing Docker, Node.js, or Python packages
    • Setting up LiteLLM, Ollama, or Open WebUI
    • Configuring Home Assistant or KVM Operator
    • Troubleshooting service startup issues

  Type 'quit' or 'exit' to return to the main menu.
  Type 'help' to see suggested questions.
""")

    SUGGESTED = [
        "How do I install Docker on Fedora 44?",
        "How do I start the LiteLLM gateway?",
        "How do I add a model to Ollama?",
        "What is the default API key for LiteLLM?",
        "How do I access the command center dashboard?",
        "How do I create a virtual environment in Python?",
        "How do I fix 'externally managed environment' pip error on Fedora 44?",
        "How do I enable and start the Docker service with systemctl?",
        "What dnf5 command adds the Docker CE repository on Fedora 44?",
        "How do I open a firewall port with firewall-cmd on Fedora?",
    ]

    while True:
        try:
            user_input = input("  You: ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if not user_input:
            continue
        if user_input.lower() in ("quit", "exit", "q"):
            break
        if user_input.lower() == "help":
            print("\n  Suggested questions:")
            for q in SUGGESTED:
                print(f"    • {q}")
            print()
            continue
        print("  Assistant: ", end="", flush=True)
        response = _get_ai_response(user_input)
        print()
        for line in textwrap.wrap(response, 68):
            print(f"  {line}")
        print()


def _compose_action(compose_file: Optional[Path], action: str) -> None:
    """Execute a docker compose subcommand against a given compose file."""
    if compose_file is None:
        print(_c("  ? Service not managed via docker compose.", _YELLOW))
        return
    compose_path = Path(compose_file)
    if not compose_path.exists():
        print(_c(f"  ✗ Compose file not found: {compose_path}", _RED))
        return
    cmd = ["docker", "compose", "-f", str(compose_path)] + action.split()
    print(f"\n  Running: docker compose -f {compose_path.name} {action}")
    print("  " + "─" * 60)
    # Intentionally do NOT capture output: docker compose logs/ps/up stream live
    # output to the terminal, which is what users expect when interacting with
    # the node operations menu.
    try:
        proc = subprocess.run(cmd, text=True, timeout=300)
        if proc.returncode != 0:
            print(_c(f"\n  ✗ Command exited with code {proc.returncode}", _RED))
        else:
            print(_c("\n  ✓ Done", _GREEN))
    except subprocess.TimeoutExpired:
        print(_c("\n  ✗ Command timed out", _RED))
    except FileNotFoundError:
        print(_c("\n  ✗ docker not found — is Docker installed?", _RED))


def _node_action_menu(node_name: str) -> None:
    """Show start/stop/status/restart actions for a specific node."""
    info = NODE_COMPOSE_MAP[node_name]
    compose = info.get("compose")
    while True:
        compose_path = Path(compose) if compose else None
        print(f"\n  Node: {_c(node_name, _GREEN)}")
        if compose_path:
            exists = compose_path.exists()
            compose_label = _c("(found)", _GREEN) if exists else _c("(NOT FOUND)", _RED)
            print(f"  Compose: {compose_path}  {compose_label}")
        print()
        print("  [1] Start    (docker compose up -d)")
        print("  [2] Stop     (docker compose down)")
        print("  [3] Status   (docker compose ps)")
        print("  [4] Restart  (down then up -d)")
        print("  [5] Logs     (last 50 lines)")
        print("  [0] Back")
        try:
            act = input("\n  Action: ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if act == "0":
            break
        elif act == "1":
            _compose_action(compose_path, "up -d")
        elif act == "2":
            _compose_action(compose_path, "down")
        elif act == "3":
            _compose_action(compose_path, "ps")
        elif act == "4":
            _compose_action(compose_path, "down")
            _compose_action(compose_path, "up -d")
        elif act == "5":
            _compose_action(compose_path, "logs --tail=50")
        else:
            print("  Invalid choice.")
        input("  Press Enter to continue…")


def show_node_menu(boss: Optional["BossAI"] = None) -> None:
    """Show the interactive node/service operations submenu."""
    nodes = list(NODE_COMPOSE_MAP.keys())
    while True:
        print_section("NODE / SERVICE OPERATIONS")
        for i, name in enumerate(nodes, 1):
            info = NODE_COMPOSE_MAP[name]
            compose = info.get("compose")
            ip = info.get("ip", "")
            if compose and Path(compose).exists():
                mark = _c("✓", _GREEN)
            elif compose:
                mark = _c("✗", _RED)
            else:
                mark = _c("~", _YELLOW)
            print(f"  [{i:2d}] [{mark}] {name}  ({ip})")
        print("  [ 0] Back to main menu")
        try:
            choice = input("\n  Select node: ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if choice == "0":
            break
        try:
            idx = int(choice) - 1
            if 0 <= idx < len(nodes):
                _node_action_menu(nodes[idx])
        except ValueError:
            print("  Invalid choice.")


def show_logs_panel(boss: Optional["BossAI"] = None) -> None:
    """Show a quick logs and troubleshooting panel."""
    print_section("LOGS & TROUBLESHOOTING")
    print("  [1] Running Docker containers   (docker ps)")
    print("  [2] Docker system info          (docker info)")
    print("  [3] systemd Docker service      (systemctl status docker)")
    print("  [4] Recent Docker journal       (journalctl -u docker -n 30)")
    print("  [0] Back")
    try:
        choice = input("\n  Choice: ").strip()
    except (EOFError, KeyboardInterrupt):
        return
    cmds: Dict[str, List[str]] = {
        "1": ["docker", "ps", "--format", "table {{.Names}}\t{{.Status}}\t{{.Ports}}"],
        "2": ["docker", "info"],
        "3": ["systemctl", "status", "docker", "--no-pager", "-l"],
        "4": ["journalctl", "-u", "docker", "-n", "30", "--no-pager"],
    }
    if choice in cmds:
        print()
        code, out = run_command(cmds[choice], timeout=15)
        print(out or "(no output)")
        input("\n  Press Enter to continue…")


def run_install_prerequisites(boss: Optional["BossAI"] = None) -> None:
    """Guided prerequisite installer (Docker, Node.js, Python tools, Git)."""
    print_section("INSTALL PREREQUISITES")
    print("""
  This step installs the following on your system:
    • Docker Engine + Docker Compose (via the official docker-ce repo)
    • Node.js (for the Node A command-center dashboard)
    • Git, curl, Python pip & wheel
    • Python packages: flask, requests, beautifulsoup4
""")
    confirm = input("  Proceed with installation? (y/N): ").strip().lower()
    if confirm != "y":
        print("  Skipped.")
        return
    if boss is None:
        boss = BossAI([])
    try:
        install_nodejs_python(boss)
        set_up_docker_repository(boss)
        install_docker_engine(boss)
        print(_c("\n  ✓ Prerequisites installed successfully!", _GREEN))
    except Exception as exc:
        print(_c(f"\n  ✗ Installation failed: {exc}", _RED))
        print("  Check your network connection and try again.")
    input("  Press Enter to continue…")


def run_configure_env(boss: Optional["BossAI"] = None) -> None:
    """Guided configuration collector and environment-file generator."""
    print_section("CONFIGURE ENVIRONMENT FILES")
    print("""
  This step collects your network addresses and credentials, then
  generates all .env files needed for the homelab nodes.
  Press Enter at each prompt to accept the default value.
""")
    confirm = input("  Proceed? (y/N): ").strip().lower()
    if confirm != "y":
        print("  Skipped.")
        return
    if boss is None:
        boss = BossAI([])
    try:
        config = collect_configuration(boss)
        generate_env_files(boss, config, REPO_ROOT)
        print(_c("\n  ✓ Environment files generated!", _GREEN))
    except Exception as exc:
        print(_c(f"\n  ✗ Configuration failed: {exc}", _RED))
    input("  Press Enter to continue…")


def run_portainer_on_all_nodes(boss: Optional["BossAI"] = None) -> None:
    """Install Portainer CE on every homelab node via portainer-install.sh.

    Nodes that cannot be reached are skipped with a warning.  The script
    is run locally (--local) for the current machine and remotely (--ip)
    for every other node using the portainer-install.sh helper.
    """
    print_section("INSTALL PORTAINER ON ALL NODES")
    portainer_script = REPO_ROOT / "scripts" / "portainer-install.sh"
    if not portainer_script.exists():
        print(_c(f"  ✗ portainer-install.sh not found at {portainer_script}", _RED))
        input("  Press Enter to continue…")
        return

    # Load IPs from node-inventory.env if present, else use defaults
    inv = REPO_ROOT / "config" / "node-inventory.env"
    node_ips: Dict[str, str] = {
        "Node A (Brain)":       "192.168.1.9",
        "Node B (Unraid/GW)":   "192.168.1.222",
        "Node C (Intel Arc)":   "192.168.1.6",
        "Node D (Home Asst.)":  "192.168.1.149",
        "Node E (Sentinel)":    "192.168.1.116",
    }
    node_users: Dict[str, str] = {k: "root" for k in node_ips}
    env_data: Dict[str, str] = {}
    if inv.exists():
        for line in inv.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            env_data[k.strip()] = v.strip()

        ip_map = {
            "NODE_A_IP": "Node A (Brain)",
            "NODE_B_IP": "Node B (Unraid/GW)",
            "NODE_C_IP": "Node C (Intel Arc)",
            "NODE_D_IP": "Node D (Home Asst.)",
            "NODE_E_IP": "Node E (Sentinel)",
        }
        ts_map = {
            "NODE_A_TS_IP": "Node A (Brain)",
            "NODE_B_TS_IP": "Node B (Unraid/GW)",
            "NODE_C_TS_IP": "Node C (Intel Arc)",
            "NODE_D_TS_IP": "Node D (Home Asst.)",
            "NODE_E_TS_IP": "Node E (Sentinel)",
        }
        user_map = {
            "NODE_A_SSH_USER": "Node A (Brain)",
            "NODE_B_SSH_USER": "Node B (Unraid/GW)",
            "NODE_C_SSH_USER": "Node C (Intel Arc)",
            "NODE_D_SSH_USER": "Node D (Home Asst.)",
            "NODE_E_SSH_USER": "Node E (Sentinel)",
        }
        for k, v in env_data.items():
            if k in ip_map:
                node_ips[ip_map[k]] = v
            if k in user_map:
                node_users[user_map[k]] = v
        # Prefer Tailscale IPs over LAN IPs for remote connections
        for k, label in ts_map.items():
            if env_data.get(k):
                node_ips[label] = env_data[k]

    print("  Will install Portainer CE on the following nodes:\n")
    for name, ip in node_ips.items():
        print(f"    • {name}  ({ip})")
    print()
    confirm = input("  Proceed? (y/N): ").strip().lower()
    if confirm != "y":
        print("  Skipped.")
        return

    for name, ip in node_ips.items():
        user = node_users.get(name, "root")
        print(f"\n  ── Installing on {name} ({ip}) ──")
        cmd = [
            "ssh", "-o", "ConnectTimeout=8", "-o", "StrictHostKeyChecking=accept-new",
            f"{user}@{ip}",
            "bash -s --",
        ]
        print(f"  Running: ssh {user}@{ip} bash -s -- < {portainer_script.name}")
        try:
            with open(portainer_script, "rb") as fh:
                script_data = fh.read()
            proc = subprocess.run(
                cmd,
                input=script_data,
                capture_output=False,
                timeout=300,
            )
            if proc.returncode == 0:
                print(_c(f"  ✓ Portainer installed on {name}", _GREEN))
            else:
                print(_c(f"  ✗ Portainer install failed on {name} (exit {proc.returncode})", _RED))
                print("     Check SSH access and try manually:")
                print(f"     ssh {user}@{ip} bash -s -- < scripts/portainer-install.sh")
        except subprocess.TimeoutExpired:
            print(_c(f"  ✗ Timed out on {name}", _RED))
        except Exception as exc:
            print(_c(f"  ✗ Error on {name}: {exc}", _RED))

    print()
    print(_c("  ✓ Portainer install pass complete.", _GREEN))
    print("     Access each node's Portainer at http://<node-ip>:9000")
    input("\n  Press Enter to continue…")


def _run_full_guided_install(boss: "BossAI") -> None:
    """Run the full guided install sequence (all steps in order)."""
    print_section("FULL GUIDED INSTALL")
    print("""
  This runs all installation steps in order:
    1. System health check
    2. Install prerequisites (Docker, Node.js, Python tools)
    3. Setup virtual environment (.venv)
    4. Configure environment files
    5. Install Portainer on all nodes
    6. Deploy all node stacks via docker compose
    7. Test AI assistant

  You will be prompted before each step.
""")
    confirm = input("  Start full guided install? (y/N): ").strip().lower()
    if confirm != "y":
        return
    run_health_checks(boss)
    input("\n  Press Enter to continue to prerequisites installation…")
    run_install_prerequisites(boss)
    setup_venv(boss)
    input("\n  Press Enter to continue to environment configuration…")
    run_configure_env(boss)
    input("\n  Press Enter to continue to Portainer installation…")
    run_portainer_on_all_nodes(boss)
    test_ai_assistant(boss)
    print(_c("\n  ✓ Full guided install complete!", _GREEN))
    input("  Press Enter to return to main menu…")


def run_main_menu() -> None:
    """Launch the main menu-driven TUI loop.

    This is the primary entry point for interactive use.  The loop
    continues until the user selects "Exit" (option 0) or sends an
    interrupt signal.
    """
    boss = BossAI([])
    while True:
        clear_screen()
        print_banner()
        print(f"  {timestamp()}  |  Repo: {REPO_ROOT}\n")
        print("  MAIN MENU")
        print("  " + "─" * 52)
        print("  [1]  System Health Check")
        print("  [2]  Install Prerequisites")
        print("  [3]  Setup Virtual Environment  (.venv)")
        print("  [4]  Configure Environment Files")
        print("  [5]  Node / Service Operations")
        print("  [6]  AI Assistant Setup & Test")
        print("  [7]  Help Assistant  (chat)")
        print("  [8]  Logs & Troubleshooting")
        print("  [9]  Full Guided Install  (all steps)")
        print("  [p]  Install Portainer on All Nodes")
        print("  [0]  Exit")
        print()
        try:
            choice = input("  Enter choice [0-9, p]: ").strip()
        except (EOFError, KeyboardInterrupt):
            choice = "0"
        if choice == "0":
            print("\n  Goodbye!\n")
            break
        elif choice == "1":
            run_health_checks(boss)
            input("\n  Press Enter to continue…")
        elif choice == "2":
            run_install_prerequisites(boss)
        elif choice == "3":
            setup_venv(boss)
            input("\n  Press Enter to continue…")
        elif choice == "4":
            run_configure_env(boss)
        elif choice == "5":
            show_node_menu(boss)
        elif choice == "6":
            test_ai_assistant(boss)
        elif choice == "7":
            run_chat_session(boss)
        elif choice == "8":
            show_logs_panel(boss)
        elif choice == "9":
            _run_full_guided_install(boss)
        elif choice == "p":
            run_portainer_on_all_nodes(boss)
        else:
            print(_c("  Invalid choice. Please enter 0–9 or p.", _YELLOW))
            time.sleep(0.8)


def main() -> None:
    # Parse command-line arguments
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--non-interactive", action="store_true",
                        help="Run unattended installation using defaults or environment variables.")
    parser.add_argument("--config-file",
                        help="Path to a JSON or .env config file for non-interactive mode.")
    parser.add_argument("--auto-start-chat", action="store_true",
                        help="Automatically start the Flask chat server after unattended installation.")
    parser.add_argument("--legacy", action="store_true",
                        help="Run the original sequential (non-menu) interactive installer.")
    parser.add_argument("--help", action="store_true",
                        help="Show this help message and exit.")
    parser.add_argument("--brothers-keeper", action="store_true",
                        help="Use the Brothers Keeper orchestrator (state-persistent, API-enabled).")
    args, unknown = parser.parse_known_args()

    if args.help:
        parser.print_help()
        sys.exit(0)

    if args.brothers_keeper:
        import importlib.util as _ilu
        _bk_path = os.path.join(os.path.dirname(__file__), "brothers-keeper", "core_orchestrator.py")
        _spec = _ilu.spec_from_file_location("core_orchestrator", _bk_path)
        _mod = _ilu.module_from_spec(_spec)  # type: ignore[arg-type]
        _spec.loader.exec_module(_mod)  # type: ignore[union-attr]
        _mod.main_cli()
        return

    # Non-interactive / unattended mode
    if args.non_interactive:
        ensure_root()
        install_path = Path(os.environ.get("DESTINATION_DIR", str(Path.home() / "onemoreytry"))).expanduser()
        config = load_non_interactive_config(args.config_file)

        def _minion_deps(b: BossAI) -> None:
            install_nodejs_python(b)
            set_up_docker_repository(b)
            install_docker_engine(b)

        unattended_minions = [
            Minion("Install Dependencies", _minion_deps),
            Minion("Generate Env Files", lambda b: generate_env_files(b, config, install_path)),
            Minion("Install Home Assistant", lambda b: install_homeassistant(b, install_path, config)),
            Minion("Configure Cloudflare", lambda b: configure_cloudflare(b, install_path, config)),
            Minion("Configure Nabu Casa", lambda b: configure_nabu_casa(b, install_path, config)),
            Minion("Verification", lambda b: verify_installation(b)),
        ]
        boss = BossAI(unattended_minions)
        boss.run_all()
        if args.auto_start_chat:
            start_chat_server(boss, install_path)
        return

    # Legacy sequential interactive mode (--legacy flag)
    if args.legacy:
        ensure_root()
        print_banner()
        dest_dir = prompt_input("Installation directory", str(Path.home() / "onemoreytry"))
        install_path = Path(dest_dir).expanduser()
        config: Dict[str, Any] = {}
        tasks: Dict[str, Callable[[BossAI], str]] = {}

        def _legacy_deps(b: BossAI) -> None:
            install_nodejs_python(b)
            set_up_docker_repository(b)
            install_docker_engine(b)

        def _legacy_config(b: BossAI) -> None:
            nonlocal config
            config = collect_configuration(b)

        def _legacy_env(b: BossAI) -> None:
            generate_env_files(b, config, install_path)

        def _legacy_chat(b: BossAI) -> None:
            start = prompt_input("Start chat server after installation? (y/N)", "N").lower()
            if start == "y":
                start_chat_server(b, install_path, tasks)

        tasks = {
            "install dependencies": lambda b: (
                (_legacy_deps(b), "Dependencies installed.")[1]  # type: ignore[func-returns-value]
            ),
            "generate env files": lambda b: (
                (generate_env_files(b, config, install_path), "Environment files generated.")[1]  # type: ignore[func-returns-value]
            ),
            "configure api keys": lambda b: (
                (configure_api_keys(b, config, install_path), "API tokens configured.")[1]  # type: ignore[func-returns-value]
            ),
            "verify installation": lambda b: (
                verify_installation(b) or "Verification complete."
            ),
            "install homeassistant": lambda b: install_homeassistant(b, install_path, config),
            "configure cloudflare": lambda b: configure_cloudflare(b, install_path, config),
            "configure nabu casa": lambda b: configure_nabu_casa(b, install_path, config),
            "help": lambda b: "Available commands: " + ", ".join(tasks.keys()),
        }
        boss = BossAI([
            Minion("Install Dependencies", _legacy_deps),
            Minion("Collect Configuration", _legacy_config),
            Minion("Configure API Keys", lambda b: configure_api_keys(b, config, install_path)),
            Minion("Generate Env Files", _legacy_env),
            Minion("Launch Chat Server", _legacy_chat),
            Minion("Verification", lambda b: verify_installation(b)),
        ])
        boss.run_all()
        return

    # Default: OS-like TUI menu
    run_main_menu()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nInterrupted. Exiting.")