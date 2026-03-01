# Brothers Keeper — Plain-Language Guide

**Brothers Keeper** is the smart home-lab install wizard that ships with this
repository.  It sets up your entire AI home lab — software, services, and
environment files — in one go, either from the command line or through a
touch-friendly browser interface.

---

## What Is Brothers Keeper?

Think of Brothers Keeper as a helpful robot that:

1. Checks that your computer can reach the internet.
2. Installs all the software packages your home lab needs.
3. Downloads the home-lab code to your machine.
4. Creates the configuration files that each service needs.
5. Starts all the Docker containers.
6. Checks that everything is running correctly.

It remembers where it left off (even after a power cut) and will never
overwrite work it has already done.

---

## Quick Start

### Option A — Browser / Kiosk (easiest)

1. Open a terminal on your home-lab machine.
2. Navigate to this folder:
   ```bash
   cd ~/homelab/brothers-keeper
   ```
3. Start the API server:
   ```bash
   ./run_dev.sh
   ```
4. Open a browser and go to **http://localhost:7070**
5. Tap **Start Setup** — Brothers Keeper does the rest.

### Option B — Command Line

Run a full automated install:
```bash
python3 brothers-keeper/core_orchestrator.py --non-interactive
```

Run the interactive menu:
```bash
python3 brothers-keeper/core_orchestrator.py
```

Use from the existing bos.py installer:
```bash
python3 bos.py --brothers-keeper
```

---

## The Kiosk Screen

When you open the browser interface you will see:

| Area | What it does |
|------|--------------|
| **Left sidebar** | Shows every install step and whether it passed ✓, failed ✗, or is still waiting. |
| **Main area** | Shows large "task tiles" — one tile per install step. Tap a tile to run just that step. |
| **Log panel** | Shows a live scroll of every command Brothers Keeper runs. |
| **Yellow approval bar** | Appears when a step needs your permission before it can proceed. Tap **Approve** or **Reject** — no PIN required. |
| **Voice button** (bottom-right 🎙️) | Let you speak commands instead of tapping. Say "start setup", "status", "approve", or "reject". |

---

## Approving or Rejecting a Step

Some steps — like installing system software or starting containers — pause
and show a yellow bar before running.

To approve or reject:
1. Tap **Approve** or **Reject** in the yellow bar.

That's it — no PIN needed.

---

## Voice Commands

Tap the purple microphone button (🎙️) and speak:

| What you say | What happens |
|---|---|
| "start setup" or "begin" | Starts the full install |
| "approve" or "yes" | Approves the pending step (no PIN) |
| "reject", "deny", or "no" | Rejects the pending step (no PIN) |
| "status" or "progress" | Reads aloud how many steps are complete |

---

## Install Steps Explained

| Step | Plain-English Description |
|------|--------------------------|
| **check_network** | Pings Google to make sure the internet is reachable. |
| **install_deps** | Installs Git, Docker, Python, and other required packages via `dnf`/`dnf5`. |
| **install_portainer** | Installs Portainer CE on the local machine so you can manage all containers via a web UI. |
| **clone_repo** | Downloads the home-lab code to `/opt/homelab` (or updates it if already present). |
| **generate_env** | Runs the setup wizard that creates `.env` files for every service. |
| **start_services** | Starts ALL node stacks (Node A–E, Unraid, Deploy GUI) with Docker Compose. |
| **verify** | Lists running Docker containers so you can confirm everything is up. |

---

## Running as a Permanent Background Service

To have the API server start automatically on boot, copy and enable the
included systemd unit files:

```bash
# Copy the app to its permanent location
sudo cp -r ~/homelab/brothers-keeper /opt/brothers-keeper

# Install and enable the API service
sudo cp /opt/brothers-keeper/systemd/homelab-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now homelab-api.service

# (Optional) Enable the kiosk browser on a dedicated screen
sudo cp /opt/brothers-keeper/systemd/homelab-kiosk.service /etc/systemd/system/
sudo systemctl enable --now homelab-kiosk.service
```

To check the service status:
```bash
sudo systemctl status homelab-api.service
```

---

## Environment Variables

Create a file called `.env` in the `brothers-keeper/` folder to customise
behaviour.  All variables are optional.

| Variable | Default | Description |
|---|---|---|
| `BK_API_TOKEN` | *(none)* | If set, every API request must include `Authorization: Bearer <token>`. |
| `BK_STATE_FILE` | `/tmp/bk_state.json` | Where install progress is saved. |
| `BK_REPO_URL` | This repo on GitHub | Repository to clone during install. |
| `REQUIRE_APPROVAL` | `true` | Set to `false` to skip the approval step entirely (installs run immediately). |
| `LOG_LEVEL` | `INFO` | Set to `DEBUG` for verbose output. |
| `BK_CORS_ORIGINS` | `*` | Comma-separated origins allowed to call the API (e.g. `http://192.168.1.9:7070`). |

---

## API Reference

The API server exposes these endpoints on port **7070**:

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Serves the kiosk HMI web page. |
| `GET` | `/health` | Returns `{"status":"ok"}` — useful for monitoring. |
| `GET` | `/state` | Returns the full install state as JSON. |
| `POST` | `/action` | Queues an install action.  Body: `{"action":"install_deps"}`. |
| `POST` | `/confirm` | Approves or rejects a pending action.  Body: `{"action":"install_deps","approved":true}`. |

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Network unreachable" | Check your internet connection and try again. |
| "Package installation failed" | Make sure you are running as root (`sudo`). |
| Tiles stay "pending" after pressing Start | Make sure the API server is running (`./run_dev.sh`) and reload the page. |
| Browser shows "HMI template not found" | Make sure `templates/index.html` exists inside the `brothers-keeper/` folder. |
| Approval bar doesn't appear | Check that `REQUIRE_APPROVAL=true` in your `.env` file. |

---

## Security Notes

* Set `BK_API_TOKEN` to a strong random string when exposing the API outside
  your home network.
* `REQUIRE_APPROVAL=true` (the default) ensures no software is installed or
  reconfigured without a human tapping Approve.
* The API server validates every action name against an allowlist before
  executing it — arbitrary commands cannot be injected through the API.

---

*For the full technical guide, see the [deployment docs](../docs/).*
