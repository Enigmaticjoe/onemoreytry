# Grand Unified AI Homelab — Canonical 2026 Deployment

A multi-node homelab with a canonical baseline: Ollama on Nodes A/B/C, one Open WebUI on Node C, Portainer + n8n on Node B, and Home Assistant connected directly to Ollama.

**Architecture authority:** [docs/ARCHITECTURE_CANONICAL_2026.md](docs/ARCHITECTURE_CANONICAL_2026.md).

---

## 🚀 Fresh Rebuild 2026 — Recommended Baseline

Starting from scratch or want a clean, minimal setup? Use the **Fresh Rebuild 2026** blueprint:

> **[fresh-rebuild-2026/](fresh-rebuild-2026/)** — Phase 1 multi-node stack · No LiteLLM · No vLLM · No OpenClaw · Just Ollama + Open WebUI + n8n + monitoring

| What | Where |
|------|-------|
| Architecture diagram & port map | [fresh-rebuild-2026/docs/ARCHITECTURE_FRESH_REBUILD_2026.md](fresh-rebuild-2026/docs/ARCHITECTURE_FRESH_REBUILD_2026.md) |
| **Step-by-step node setup guide** (non-technical) | [fresh-rebuild-2026/docs/NODE_SETUP_GUIDE.md](fresh-rebuild-2026/docs/NODE_SETUP_GUIDE.md) |
| **Configuring every app & service** (non-technical) | [fresh-rebuild-2026/docs/APPS_AND_SERVICES_GUIDE.md](fresh-rebuild-2026/docs/APPS_AND_SERVICES_GUIDE.md) |
| Node A compose (Ollama ROCm + Portainer Agent) | [fresh-rebuild-2026/node-a/compose.yml](fresh-rebuild-2026/node-a/compose.yml) |
| Node B stacks (Portainer + infra + Ollama CUDA + n8n) | [fresh-rebuild-2026/node-b/stacks/](fresh-rebuild-2026/node-b/stacks/) |
| Node C compose (Single Open WebUI) | [fresh-rebuild-2026/node-c/compose.yml](fresh-rebuild-2026/node-c/compose.yml) |
| Node D docs (Home Assistant → Ollama direct) | [fresh-rebuild-2026/node-d/README.md](fresh-rebuild-2026/node-d/README.md) |
| Deploy & verify scripts | [fresh-rebuild-2026/scripts/](fresh-rebuild-2026/scripts/) |

Quick start:
```bash
# 1. Copy inventory and fill in your node IPs
cp fresh-rebuild-2026/inventory/node-inventory.env.example fresh-rebuild-2026/inventory/node-inventory.env
nano fresh-rebuild-2026/inventory/node-inventory.env

# 2. Pre-flight check
cd fresh-rebuild-2026 && bash scripts/preflight.sh

# 3. Deploy all nodes
bash scripts/deploy-all.sh
```

---

## New-User Quickstart — BOS Installer

For a guided, OS-like installation experience run `bos.py`:

```bash
# Requires Python 3.8+. No extra packages needed to launch the menu.
python3 bos.py
```

The menu-driven TUI gives you:

| Option | What it does |
|--------|-------------|
| **[1] System Health Check** | Checks Docker, Python, Node.js, .venv, Ollama, network |
| **[2] Install Prerequisites** | Installs Docker, Node.js, Git, pip (Fedora/dnf based) |
| **[3] Setup Virtual Environment** | Creates `.venv` and installs all Python requirements |
| **[4] Configure Environment Files** | Collects node IPs/tokens and writes all `.env` files |
| **[5] Node / Service Operations** | Start · Stop · Status · Restart any homelab node |
| **[6] AI Assistant Setup & Test** | Tests local Ollama and LiteLLM gateway connectivity |
| **[7] Help Assistant (chat)** | Interactive chat with local AI (Ollama) or web fallback |
| **[8] Logs & Troubleshooting** | Show docker ps / docker info / systemd journal |
| **[9] Full Guided Install** | Runs all steps above in order with prompts |

### Virtual environment

```bash
# Option A – let bos.py create and populate .venv (menu option [3])
python3 bos.py   # then choose [3]

# Option B – manual
python3 -m venv .venv
source .venv/bin/activate
pip install -r kvm-operator/requirements.txt
```

### Local AI assistant prerequisites

The chat assistant (menu option [7]) uses [Ollama](https://ollama.ai) for
fully-local AI responses with no cloud API required.

```bash
# Install Ollama (Linux one-liner)
curl -fsSL https://ollama.ai/install.sh | sh

# Pull a model (e.g. llama3.2 ~2 GB)
ollama pull llama3.2

# Override the default URL or model via environment variables
export OLLAMA_URL=http://localhost:11434
export OLLAMA_MODEL=llama3.2
python3 bos.py
```

If Ollama is not available the assistant automatically falls back to a
DuckDuckGo web-search answer.

### Unattended / CI mode

```bash
# Run fully non-interactive using env vars or a config file
python3 bos.py --non-interactive [--config-file path/to/config.env]

# Unattended install then auto-start the Flask chat server
python3 bos.py --non-interactive --auto-start-chat

# Use the Brothers Keeper API orchestrator instead
python3 bos.py --brothers-keeper

# Use the original sequential installer (pre-v2 behaviour)
sudo python3 bos.py --legacy
```

---

## Quick Start (canonical)

```bash
# 1 — Set your node IPs and SSH users
cp config/node-inventory.env.example config/node-inventory.env
nano config/node-inventory.env

# 2 — Audit SSH connectivity and hardware on all nodes
./scripts/ssh-auditor.sh

# 3 — Install canonical operations services on Node B
#     Portainer + n8n
./scripts/portainer-install.sh

# 4 — Deploy canonical stacks
#     - Ollama on Nodes A/B/C
#     - Single Open WebUI on Node C
#     - Home Assistant direct to an Ollama endpoint
./scripts/deploy-all.sh
```

Canonical architecture: **[docs/ARCHITECTURE_CANONICAL_2026.md](docs/ARCHITECTURE_CANONICAL_2026.md)**

---

| Node | Canonical role | Key canonical services |
|------|----------------|------------------------|
| A    | Inference node | Ollama :11434 |
| B    | Operations node | Portainer :9000, n8n :5678, Ollama :11434 |
| C    | User interface node | Open WebUI :3000, Ollama :11434 |
| D    | Home automation | Home Assistant :8123 (direct to Ollama) |
| E    | Surveillance / extras | Optional workloads |

---

## Legacy / Advanced paths

The following are retained for compatibility and advanced operators, but are **not** the default flow:

- LiteLLM gateway deployments
- vLLM-based inference routes
- OpenClaw orchestration patterns

Use these only when you explicitly need legacy/advanced behavior.

---

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `scripts/ssh-auditor.sh` | SSH pre-auditor: tests connectivity, audits hardware, maps firewall, discovers Tailscale |
| `scripts/portainer-install.sh` | Installs Portainer CE on all reachable nodes |
| `scripts/deploy-all.sh` | Deploys all application stacks (uses Portainer API when token set) |
| `scripts/preflight-check.sh` | Validates system requirements before deploy |
| `validate.sh` | 36-test configuration validation suite |

---

## Documentation

| File | Contents |
|------|----------|
| [PORTAINER_GUIDE.md](PORTAINER_GUIDE.md) | **Start here** — Portainer install, SSH troubleshooting, Tailscale, API |
| [GUIDEBOOK.md](GUIDEBOOK.md) | Full architecture and per-node deployment details |
| [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) | Step-by-step deployment reference |
| [QUICK_REFERENCE.md](QUICK_REFERENCE.md) | Copy-paste commands for common operations |

---

## Connectivity Options

The SSH auditor tries three methods to reach each node, in order:

1. **LAN SSH** — direct connection via local network (fastest)
2. **Tailscale** — encrypted mesh tunnel (fallback for remote nodes or firewall issues)
3. **Key push** — `ssh-copy-id` with `--install-keys` flag (one-time setup)

Set Tailscale IPs in `config/node-inventory.env` as `NODE_X_TS_IP=100.x.x.x`
if LAN SSH is unreliable.

---

## Inventory Template

```bash
# config/node-inventory.env
NODE_A_IP=192.168.1.9          # your actual IPs
NODE_B_IP=192.168.1.222
NODE_C_IP=192.168.1.6
NODE_A_SSH_USER=root
NODE_B_SSH_USER=root
NODE_A_TS_IP=                  # Tailscale 100.x.x.x (optional)
PORTAINER_TOKEN=               # ptr_... (from Portainer → My Account → Access Tokens)
```

---

## References

- Portainer CE docs: https://docs.portainer.io/
- Open WebUI: https://docs.openwebui.com/
- LiteLLM proxy: https://docs.litellm.ai/docs/proxy/docker_quick_start
- Tailscale: https://tailscale.com/kb/1017/install
