#!/usr/bin/env python3
"""
Brothers Keeper — Core Orchestrator
=====================================
Manages install state, dispatches tasks, and enforces human-in-the-loop
confirmation for destructive actions.

RuntimeContext tracks the current install phase and every task's result.
State is persisted to a JSON file so progress survives restarts.

Usage (CLI):
    python3 core_orchestrator.py [--state-file /path/to/state.json]
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Callable, Dict, List, Optional

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger("brothers-keeper")

DEFAULT_STATE_FILE = Path(os.getenv("BK_STATE_FILE", "/tmp/bk_state.json"))
REQUIRE_APPROVAL = os.getenv("REQUIRE_APPROVAL", "true").lower() in ("1", "true", "yes", "y")


# ---------------------------------------------------------------------------
# RuntimeContext — the single source of truth for install progress
# ---------------------------------------------------------------------------

@dataclass
class TaskResult:
    name: str
    status: str = "pending"   # pending | running | done | failed | skipped
    message: str = ""
    started_at: float = 0.0
    finished_at: float = 0.0


@dataclass
class RuntimeContext:
    phase: str = "idle"                  # idle | setup | running | done | error
    current_task: str = ""
    tasks: List[TaskResult] = field(default_factory=list)
    log: List[str] = field(default_factory=list)
    pending_confirm: Optional[str] = None  # action waiting for approval
    error: str = ""

    def append_log(self, msg: str) -> None:
        ts = time.strftime("%H:%M:%S")
        entry = f"[{ts}] {msg}"
        self.log.append(entry)
        logger.info(msg)

    def find_task(self, name: str) -> Optional[TaskResult]:
        for t in self.tasks:
            if t.name == name:
                return t
        return None

    def upsert_task(self, name: str) -> TaskResult:
        t = self.find_task(name)
        if t is None:
            t = TaskResult(name=name)
            self.tasks.append(t)
        return t


# ---------------------------------------------------------------------------
# State persistence helpers
# ---------------------------------------------------------------------------

def load_state(path: Path = DEFAULT_STATE_FILE) -> RuntimeContext:
    """Load RuntimeContext from JSON file; return fresh context if absent."""
    if path.exists():
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
            tasks = [TaskResult(**t) for t in raw.pop("tasks", [])]
            ctx = RuntimeContext(**raw)
            ctx.tasks = tasks
            return ctx
        except Exception as exc:
            logger.warning("Could not load state file %s: %s — starting fresh", path, exc)
    return RuntimeContext()


def save_state(ctx: RuntimeContext, path: Path = DEFAULT_STATE_FILE) -> None:
    """Persist RuntimeContext to JSON atomically."""
    tmp = path.with_suffix(".tmp")
    try:
        tmp.write_text(json.dumps(asdict(ctx), indent=2), encoding="utf-8")
        tmp.replace(path)
    except Exception as exc:
        logger.error("Failed to save state: %s", exc)


# ---------------------------------------------------------------------------
# Action implementations
# ---------------------------------------------------------------------------

def _run(cmd: List[str], ctx: RuntimeContext) -> tuple[int, str]:
    """Run a shell command, stream output to ctx.log, return (returncode, output)."""
    ctx.append_log(f"$ {' '.join(cmd)}")
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=600,
        )
        for line in proc.stdout.splitlines():
            ctx.append_log(line)
        return proc.returncode, proc.stdout
    except subprocess.TimeoutExpired:
        msg = f"Command timed out: {' '.join(cmd)}"
        ctx.append_log(msg)
        return 1, msg
    except Exception as exc:
        msg = f"Command error: {exc}"
        ctx.append_log(msg)
        return 1, msg


def _task_check_network(ctx: RuntimeContext) -> None:
    rc, _ = _run(["ping", "-c", "1", "-W", "3", "8.8.8.8"], ctx)
    if rc != 0:
        raise RuntimeError("Network unreachable — check internet connection")


def _task_install_deps(ctx: RuntimeContext) -> None:
    pkgs = [
        "git", "curl", "python3", "python3-pip",
        "docker-ce", "docker-ce-cli", "containerd.io",
        "docker-buildx-plugin", "docker-compose-plugin",
    ]
    try:
        _which = subprocess.run(["which", "dnf5"], capture_output=True, timeout=5)
        ctx.append_log(f"dnf5 {'found' if _which.returncode == 0 else 'not found'}")
        dnf = "dnf5" if _which.returncode == 0 else "dnf"
    except Exception as exc:
        ctx.append_log(f"which dnf5 check failed: {exc} — using dnf")
        dnf = "dnf"
    rc, _ = _run(["sudo", dnf, "install", "-y"] + pkgs, ctx)
    if rc != 0:
        raise RuntimeError("Package installation failed")
    # Enable and start docker
    _run(["sudo", "systemctl", "enable", "--now", "docker"], ctx)


def _task_clone_repo(ctx: RuntimeContext) -> None:
    dest = Path("/opt/homelab")
    repo_url = os.getenv("BK_REPO_URL", "https://github.com/Enigmaticjoe/onemoreytry.git")
    if dest.exists():
        ctx.append_log(f"Repo already cloned at {dest}, pulling latest…")
        rc, _ = _run(["git", "-C", str(dest), "pull", "--ff-only"], ctx)
    else:
        rc, _ = _run(["git", "clone", repo_url, str(dest)], ctx)
    if rc != 0:
        raise RuntimeError("Repository clone/pull failed")


def _task_generate_env(ctx: RuntimeContext) -> None:
    dest = Path("/opt/homelab")
    script = dest / "scripts" / "setup-env.sh"
    if not script.exists():
        ctx.append_log("setup-env.sh not found — skipping env generation")
        return
    rc, _ = _run(["bash", str(script), "--non-interactive"], ctx)
    if rc != 0:
        raise RuntimeError("Env generation failed")


def _task_install_portainer(ctx: RuntimeContext) -> None:
    """Install Portainer CE on the local machine."""
    dest = Path("/opt/homelab")
    script = dest / "scripts" / "portainer-install.sh"
    if not script.exists():
        ctx.append_log("portainer-install.sh not found — skipping Portainer install")
        return
    rc, _ = _run(["bash", str(script), "--local"], ctx)
    if rc != 0:
        raise RuntimeError("Portainer install failed — check Docker is running")


def _task_start_services(ctx: RuntimeContext) -> None:
    """Start all homelab node services via docker compose."""
    dest = Path("/opt/homelab")
    # All compose files in deployment order
    compose_files = [
        dest / "node-a-vllm" / "docker-compose.yml",
        dest / "node-b-litellm" / "litellm-stack.yml",
        dest / "node-b-litellm" / "stacks" / "ai-orchestration-stack.yml",
        dest / "node-c-arc" / "docker-compose.yml",
        dest / "node-d-home-assistant" / "docker-compose.yml",
        dest / "node-e-sentinel" / "docker-compose.yml",
        dest / "unraid" / "docker-compose.yml",
        dest / "deploy-gui" / "docker-compose.yml",
    ]
    started = 0
    for cf in compose_files:
        if cf.exists():
            rc, _ = _run(
                ["docker", "compose", "-f", str(cf), "up", "-d", "--remove-orphans"],
                ctx,
            )
            if rc != 0:
                ctx.append_log(f"WARNING: compose up failed for {cf.name} — continuing")
            else:
                started += 1
        else:
            ctx.append_log(f"Compose file not found: {cf} — skipping")
    ctx.append_log(f"Started {started} of {len(compose_files)} node stacks")


def _task_verify(ctx: RuntimeContext) -> None:
    rc, _ = _run(["docker", "ps", "--format", "table {{.Names}}\t{{.Status}}"], ctx)
    if rc != 0:
        raise RuntimeError("Docker verification failed")


# ---------------------------------------------------------------------------
# Action dispatcher — maps action names to callables
# ---------------------------------------------------------------------------

TASK_REGISTRY: Dict[str, Callable[[RuntimeContext], None]] = {
    "check_network": _task_check_network,
    "install_deps": _task_install_deps,
    "install_portainer": _task_install_portainer,
    "clone_repo": _task_clone_repo,
    "generate_env": _task_generate_env,
    "start_services": _task_start_services,
    "verify": _task_verify,
}

# Actions that require human approval when REQUIRE_APPROVAL=true
APPROVAL_REQUIRED_ACTIONS = {"install_deps", "install_portainer", "generate_env", "start_services"}

# Ordered sequence for a full install
FULL_INSTALL_SEQUENCE = [
    "check_network",
    "install_deps",
    "install_portainer",
    "clone_repo",
    "generate_env",
    "start_services",
    "verify",
]


def dispatch_action(action: str, ctx: RuntimeContext, state_file: Path) -> None:
    """Run a single registered action, updating ctx task list and state file."""
    if action not in TASK_REGISTRY:
        ctx.append_log(f"Unknown action: {action}")
        ctx.error = f"Unknown action: {action}"
        save_state(ctx, state_file)
        return

    # Gate on approval for destructive actions
    if REQUIRE_APPROVAL and action in APPROVAL_REQUIRED_ACTIONS:
        if ctx.pending_confirm != action:
            ctx.append_log(f"Action '{action}' requires approval — awaiting confirmation")
            ctx.pending_confirm = action
            save_state(ctx, state_file)
            return

    # Clear the pending confirm now that approval has been granted
    ctx.pending_confirm = None

    task = ctx.upsert_task(action)
    task.status = "running"
    task.started_at = time.time()
    ctx.current_task = action
    ctx.phase = "running"
    save_state(ctx, state_file)

    try:
        TASK_REGISTRY[action](ctx)
        task.status = "done"
        task.message = "Completed successfully"
        ctx.append_log(f"✓ {action} completed")
    except Exception as exc:
        task.status = "failed"
        task.message = str(exc)
        ctx.error = str(exc)
        ctx.phase = "error"
        ctx.append_log(f"✗ {action} failed: {exc}")
    finally:
        task.finished_at = time.time()
        ctx.current_task = ""
        save_state(ctx, state_file)


def confirm_action(action: str, approved: bool, ctx: RuntimeContext, state_file: Path) -> None:
    """Accept or reject a pending confirmation request."""
    if ctx.pending_confirm != action:
        ctx.append_log(f"No pending confirmation for action: {action}")
        return
    if approved:
        ctx.append_log(f"Action '{action}' approved — dispatching")
        dispatch_action(action, ctx, state_file)
    else:
        ctx.pending_confirm = None
        task = ctx.upsert_task(action)
        task.status = "skipped"
        task.message = "Rejected by operator"
        ctx.append_log(f"Action '{action}' rejected by operator")
        save_state(ctx, state_file)


# ---------------------------------------------------------------------------
# CLI entrypoint
# ---------------------------------------------------------------------------

def main_cli() -> None:
    """Interactive CLI orchestrator — can also be called from bos.py."""
    parser = argparse.ArgumentParser(
        description="Brothers Keeper — Homelab install orchestrator",
    )
    parser.add_argument(
        "--state-file",
        default=str(DEFAULT_STATE_FILE),
        help="Path to JSON state file (default: %(default)s)",
    )
    parser.add_argument(
        "--action",
        choices=list(TASK_REGISTRY.keys()) + ["full_install"],
        help="Run a single action instead of the interactive menu",
    )
    parser.add_argument(
        "--non-interactive",
        action="store_true",
        help="Run full install without prompts (implies --action=full_install)",
    )
    args = parser.parse_args()
    state_file = Path(args.state_file)
    ctx = load_state(state_file)

    if args.non_interactive or args.action == "full_install":
        ctx.phase = "setup"
        ctx.append_log("Starting full install sequence (non-interactive)")
        save_state(ctx, state_file)
        for step in FULL_INSTALL_SEQUENCE:
            dispatch_action(step, ctx, state_file)
            if ctx.phase == "error":
                print(f"\nInstall failed at step '{step}': {ctx.error}", file=sys.stderr)
                sys.exit(1)
        ctx.phase = "done"
        ctx.append_log("Full install completed successfully")
        save_state(ctx, state_file)
        print("✓ Installation complete.")
        return

    if args.action:
        dispatch_action(args.action, ctx, state_file)
        if ctx.phase == "error":
            print(f"Action failed: {ctx.error}", file=sys.stderr)
            sys.exit(1)
        return

    # Interactive menu
    print("\n=== Brothers Keeper — Install Orchestrator ===")
    print("State file:", state_file)
    print("Phase:", ctx.phase)
    print()
    while True:
        print("\nAvailable actions:")
        for i, action in enumerate(FULL_INSTALL_SEQUENCE, 1):
            task = ctx.find_task(action)
            status = task.status if task else "pending"
            print(f"  [{i}] {action:20s}  ({status})")
        print("  [f] full install")
        print("  [q] quit")
        choice = input("\nChoose action: ").strip().lower()
        if choice == "q":
            break
        elif choice == "f":
            for step in FULL_INSTALL_SEQUENCE:
                dispatch_action(step, ctx, state_file)
                if ctx.phase == "error":
                    print(f"Install failed: {ctx.error}")
                    break
        elif choice.isdigit():
            idx = int(choice) - 1
            if 0 <= idx < len(FULL_INSTALL_SEQUENCE):
                action = FULL_INSTALL_SEQUENCE[idx]
                if ctx.pending_confirm == action:
                    ans = input(f"Approve '{action}'? (y/N): ").strip().lower()
                    confirm_action(action, ans == "y", ctx, state_file)
                else:
                    dispatch_action(action, ctx, state_file)
            else:
                print("Invalid selection")
        else:
            print("Invalid input")

    print("\nState saved to", state_file)


if __name__ == "__main__":
    main_cli()
