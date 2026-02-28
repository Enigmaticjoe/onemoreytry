#!/usr/bin/env python3
"""
Boss‑Driven Homelab Install Assistant for Fedora 43
===================================================

This script reimagines the original single‑process homelab installer as
an orchestrated, multi‑agent system.  A central **Boss AI** coordinates
several **Minion** agents, each responsible for a discrete part of the
installation workflow.  The architecture emphasises idempotence,
robust error handling and self‑correction: if a task fails, the Boss
attempts to learn from the error by performing a web search and
presenting possible solutions.  The script supports Fedora 43 systems
and honours RPM package management best practices without disabling
SELinux.

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

* **Fedora 43 aware:** The installer prefers the `dnf5` command when
  available (falling back to `dnf` if not) and installs Docker
  Engine components using the officially recommended packages
  (`docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`,
  `docker-compose-plugin`)【90012162061105†L1019-L1083】.  It also
  installs Node.js via the Fedora‑provided `nodejs` package【783299041434477†L29-L33】,
  along with Git, curl, pip and wheel【898572563346427†L184-L188】.

* **Chat service:** After setup, the assistant optionally launches a
  lightweight Flask web server exposing a HTML chat interface and a
  JSON `/ask` endpoint, enabling browser‑based interaction.

To use this script, run it as root on a Fedora 43 machine.  Answer
the prompts when asked; the Boss AI will handle the rest.  At the
end, a chat server listens on port 8008 (by default), and the
repository and configuration files are ready for deployment.
"""

from __future__ import annotations

import os
import sys
import subprocess
import getpass
import shutil
import time
import textwrap
import argparse
from pathlib import Path
from typing import Callable, Dict, Any, Optional, List

try:
    import urllib.parse as urlparse
    import urllib.request as urlrequest
    from html import unescape
except ImportError:
    # Python 2 fallback (unlikely on Fedora 43)
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


def run_command(cmd: List[str], timeout: int = 60) -> (int, str):
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


def check_network_connectivity(boss: 'BossAI', host: str = "github.com") -> None:
    """Ensure the system has network connectivity by pinging a host.

    Args:
        boss: The boss instance for logging.
        host: Hostname to test connectivity against. Defaults to github.com.

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
    github_token = prompt_input("GitHub Personal Access Token", "", secret=True)
    openai_key = prompt_input("OpenAI or other AI service API key", "", secret=True)
    extras: Dict[str, str] = {}
    if github_token:
        extras["GITHUB_TOKEN"] = github_token
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
    """Configure the Docker repository for Fedora using dnf config manager."""
    # Ensure dnf-plugins-core for config‑manager
    if not check_package_installed("dnf-plugins-core"):
        dnf_install(["dnf-plugins-core"], boss)
    boss.log("Adding Docker repository configuration…")
    dnf_cmd = choose_dnf()
    repo_cmd = [dnf_cmd, "config-manager", "addrepo", "--from-repofile",
               "https://download.docker.com/linux/fedora/docker-ce.repo"]
    code, out = run_command(repo_cmd)
    if code != 0 and "already exists" not in out and "File exists" not in out:
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
    """Install Node.js, Python pip/wheel, Git and curl."""
    core = ["git", "curl", "python3-pip", "python3-wheel", "nodejs"]
    dnf_install(core, boss)
    boss.log("Installing Python modules via pip…")
    pip_cmd = ["python3", "-m", "pip", "install", "--quiet", "flask", "beautifulsoup4"]
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
    cfg["NODE_A_IP"] = prompt_input("Node A IP (Brain / AMD GPU)", "192.168.1.9")
    cfg["NODE_B_IP"] = prompt_input("Node B IP (Unraid / Gateway)", "192.168.1.222")
    cfg["NODE_C_IP"] = prompt_input("Node C IP (Intel Arc)", "192.168.1.6")
    cfg["NODE_D_IP"] = prompt_input("Node D IP (Home Assistant)", "192.168.1.149")
    cfg["NODE_E_IP"] = prompt_input("Node E IP (Sentinel/NVR)", "192.168.1.116")
    cfg["KVM_IP"] = prompt_input("NanoKVM IP", "192.168.1.130")
    cfg["KVM_HOSTNAME"] = prompt_input("NanoKVM hostname", "kvm-d829.local")
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
    # Compose the welcome message.  The first message introduces the assistant
    # with a friendly, neutral personality and explains its role.  Subsequent
    # lines list available commands and encourage the user to either click a
    # button or type a question.  Plain language and short sentences improve
    # comprehension for users with cognitive impairments【131686025932182†L263-L265】.
    # Compose a cyberpunk‑inspired welcome.  Use short sentences and plain language
    # to remain accessible to users with cognitive impairments【131686025932182†L263-L265】.  A
    # friendly tone invites the user into a neon‑lit world while
    # reassuring them of step‑by‑step guidance.
    welcome_lines = [
        "Greetings, traveller of the neon grid. I’m your cyberpunk AI companion.",
        "I’m here to guide you, step by step, through the homelab installation.",
    ]
    if commands:
        # Create a user‑friendly list of commands.  List them in a single
        # sentence so the user knows what’s possible at a glance【740382120809859†L86-L90】.
        cmd_list = ', '.join(commands)
        welcome_lines.append(
            "You can click a button or type one of these commands: " + cmd_list + "."
        )
        welcome_lines.append(
            "If you’re not sure, type ‘help’ to see your options."
        )
    # Provide reassurance and guidance on how to restart or seek help.  This
    # follows conversational design best practices: remind the user they can
    # restart and that support is available【740382120809859†L95-L104】.
    welcome_lines.append(
        "You can restart the session at any time by refreshing the page."
    )
    welcome_lines.append(
        "If you need extra help, ask a caregiver or reach out to support."
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
                /* Voice toggle styling */
                #voice-toggle label {{ color: #e0eaff; font-size: 0.9em; }}
                #voice-toggle input[type="checkbox"] {{ margin-right: 6px; }}
                /* Command buttons area */
                #command-buttons button {{ margin-right: 6px; margin-bottom: 6px; }}
            </style>
        </head>
        <body>
            <div id="chat-container">
                <!-- Avatar with descriptive alt text for screen readers【131686025932182†L220-L222】 -->
                <img id="avatar" src="{AVATAR_DATA_URI}" alt="Cyberpunk AI avatar">
                <h2 style="margin-top: 0; color: #00ffc8;">Homelab Assistant</h2>
                <div id="messages"></div>
                <!-- Voice feedback toggle -->
                <div id="voice-toggle" style="margin-bottom:10px;">
                    <label>
                        <input type="checkbox" id="voiceToggle" onchange="toggleVoice()"> Enable voice feedback
                    </label>
                </div>
                <!-- Command buttons will be injected here by JS -->
                <div id="command-buttons" style="margin-bottom:10px;"></div>
                <input type="text" id="user-input" placeholder="Enter a command or ask a question..." onkeydown="if(event.key==='Enter') send();">
                <button onclick="send()">Send</button>
            </div>
            <script>
                // Voice settings
                let voiceEnabled = false;
                function toggleVoice() {{
                    voiceEnabled = document.getElementById('voiceToggle').checked;
                }}
                function speak(text) {{
                    if (!voiceEnabled) return;
                    if (!('speechSynthesis' in window)) return;
                    const utter = new SpeechSynthesisUtterance(text);
                    speechSynthesis.speak(utter);
                }}
                function appendMessage(text, cls) {{
                    const div = document.createElement('div');
                    div.className = 'msg ' + cls;
                    div.textContent = text;
                    document.getElementById('messages').appendChild(div);
                    document.getElementById('messages').scrollTop = document.getElementById('messages').scrollHeight;
                    if (cls === 'bot') {{ speak(text); }}
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


def main() -> None:
    print(
        """
╔═══════════════════════════════════════════════════════════════╗
║   Cyberpunk Homelab Install Companion – Boss‑Driven Edition    ║
╚═══════════════════════════════════════════════════════════════╝

Welcome to the neon‑lit world of your homelab.
This AI will orchestrate the installation of your stack on Fedora 43
using multiple agents.  It will install Docker, Node.js and Python
dependencies, clone your repository, collect configuration, generate
environment files and launch a web‑based interface.  If a step fails,
the Boss will search the web for fixes and offer a retry.
"""
    )
    # Parse command‑line arguments for unattended mode
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--non-interactive", action="store_true", help="Run unattended installation using defaults or environment variables.")
    parser.add_argument("--config-file", help="Path to a JSON or .env config file for non-interactive mode.")
    parser.add_argument("--auto-start-chat", action="store_true", help="Automatically start the chat server after unattended installation.")
    parser.add_argument("--help", action="store_true", help="Show this help message and exit.")
    args, unknown = parser.parse_known_args()
    if args.help:
        parser.print_help()
        sys.exit(0)
    ensure_root()
    # Determine repository URL and destination depending on interactive or non‑interactive mode
    default_repo = "https://github.com/Enigmaticjoe/onemoreytry.git"
    default_dest = str(Path.home() / "onemoreytry")
    if args.non_interactive:
        repo_url = os.environ.get("REPOSITORY_URL", default_repo)
        dest_dir = os.environ.get("DESTINATION_DIR", default_dest)
    else:
        repo_url = prompt_input(
            "Repository URL to clone", default_repo
        )
        dest_dir = prompt_input(
            "Destination directory", default_dest
        )
    clone_path = Path(dest_dir).expanduser()
    # Create the boss and minions
    boss: BossAI
    # To capture configuration across minions, we use a dictionary
    config: Dict[str, Any] = {}

    def minion_deps(boss: BossAI) -> None:
        install_nodejs_python(boss)
        set_up_docker_repository(boss)
        install_docker_engine(boss)

    def minion_repo(boss: BossAI) -> None:
        clone_repository(boss, repo_url, clone_path)

    def minion_config(boss: BossAI) -> None:
        nonlocal config
        config = collect_configuration(boss)

    def minion_env(boss: BossAI) -> None:
        generate_env_files(boss, config, clone_path)

    # Build a dictionary of chat commands and their corresponding actions.  Each
    # action returns a user‑facing summary string.  Commands are matched
    # case‑insensitively.
    def task_install_deps(b: BossAI) -> str:
        install_nodejs_python(b)
        set_up_docker_repository(b)
        install_docker_engine(b)
        return "Dependencies installed successfully."

    def task_clone_repo(b: BossAI) -> str:
        clone_repository(b, repo_url, clone_path)
        return f"Repository cloned or updated at {clone_path}."

    def task_generate_env(b: BossAI) -> str:
        # Ensure configuration exists
        if not config:
            return "No configuration loaded. Please run the CLI configuration step first."
        generate_env_files(b, config, clone_path)
        return "Environment files generated."

    def task_configure_api_keys(b: BossAI) -> str:
        if not config:
            return "No configuration loaded. Please run the CLI configuration step first."
        configure_api_keys(b, config, clone_path)
        return "API tokens configured."

    def task_verify(b: BossAI) -> str:
        verify_installation(b)
        return "Installation verification completed."

    def task_help(b: BossAI) -> str:
        return "Available commands: " + ", ".join(sorted(tasks.keys()))

    def task_install_homeassistant(b: BossAI) -> str:
        if not config:
            return "No configuration loaded. Please run the configuration step first."
        return install_homeassistant(b, clone_path, config)

    def task_setup_cloudflare(b: BossAI) -> str:
        if not config:
            return "No configuration loaded. Please run the configuration step first."
        return configure_cloudflare(b, clone_path, config)

    def task_setup_nabucasa(b: BossAI) -> str:
        if not config:
            return "No configuration loaded. Please run the configuration step first."
        return configure_nabu_casa(b, clone_path, config)

    # Perform a full installation by sequentially executing the primary tasks.
    def task_full_install(b: BossAI) -> str:
        messages: List[str] = []
        try:
            messages.append(task_install_deps(b))
            messages.append(task_clone_repo(b))
            # Ensure configuration has been collected via CLI
            if not config:
                return "No configuration loaded. Please run the configuration step from the CLI before using full install."
            messages.append(task_generate_env(b))
            messages.append(task_configure_api_keys(b))
            # Automatically install Home Assistant and Cloudflare after generating env
            messages.append(task_install_homeassistant(b))
            messages.append(task_setup_cloudflare(b))
            messages.append(task_setup_nabucasa(b))
            messages.append(task_verify(b))
            return "\n".join(messages)
        except Exception as exc:
            return f"Error during full install: {exc}"

    # Placeholder; will assign tasks mapping after definitions
    tasks: Dict[str, Callable[[BossAI], str]] = {}

    def minion_chat(boss: BossAI) -> None:
        # Ask user if they want to start chat server now
        start = prompt_input("Start chat server after installation? (y/N)", "N").lower()
        if start == "y":
            start_chat_server(boss, clone_path, tasks)

    # Now assign tasks mapping (after functions are defined).
    tasks = {
        "install dependencies": task_install_deps,
        "clone repository": task_clone_repo,
        "generate env files": task_generate_env,
        "configure api keys": task_configure_api_keys,
        "verify installation": task_verify,
        "install homeassistant": task_install_homeassistant,
        "configure cloudflare": task_setup_cloudflare,
        "configure nabu casa": task_setup_nabucasa,
        "help": task_help,
        "full install": task_full_install,
    }

    # Decide minions based on interactive or non‑interactive mode
    if args.non_interactive:
        # Load configuration without prompting.  Use file if provided.
        config = load_non_interactive_config(args.config_file)
        # Define minions for unattended mode
        unattended_minions = [
            Minion("Network Connectivity Check", lambda b: check_network_connectivity(b)),
            Minion("Install Dependencies", minion_deps),
            Minion("Clone Repository", minion_repo),
            Minion("Generate Env Files", lambda b: generate_env_files(b, config, clone_path)),
            Minion("Install Home Assistant", lambda b: install_homeassistant(b, clone_path, config)),
            Minion("Configure Cloudflare", lambda b: configure_cloudflare(b, clone_path, config)),
            Minion("Configure Nabu Casa", lambda b: configure_nabu_casa(b, clone_path, config)),
            Minion("Verification", lambda b: verify_installation(b)),
        ]
        # Run unattended minions
        boss = BossAI(unattended_minions)
        boss.run_all()
        # Optionally start the chat server if auto flag is set
        if args.auto_start_chat:
            # Build tasks mapping for chat server
            tasks = {
                "install dependencies": task_install_deps,
                "clone repository": task_clone_repo,
                "generate env files": task_generate_env,
                "configure api keys": task_configure_api_keys,
                "verify installation": task_verify,
                "install homeassistant": task_install_homeassistant,
                "configure cloudflare": task_setup_cloudflare,
                "configure nabu casa": task_setup_nabucasa,
                "help": task_help,
                "full install": task_full_install,
            }
            start_chat_server(boss, clone_path, tasks)
    else:
        # Interactive mode: gather configuration via prompts and run all minions
        boss = BossAI([
            Minion("Network Connectivity Check", lambda b: check_network_connectivity(b)),
            Minion("Install Dependencies", minion_deps),
            Minion("Clone Repository", minion_repo),
            Minion("Collect Configuration", minion_config),
            # Configure API keys using the config and clone path captured above
            Minion("Configure API Keys", lambda b: configure_api_keys(b, config, clone_path)),
            Minion("Generate Env Files", minion_env),
            Minion("Launch Chat Server", minion_chat),
            Minion("Verification", lambda b: verify_installation(b)),
        ])
        boss.run_all()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nInterrupted. Exiting.")