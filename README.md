# Grand Unified AI Homelab — Portainer-First Deployment

A multi-node homelab with unified LLM access, vision AI, KVM automation,
and a web-based control panel. Portainer is installed on every node first
to give you full visibility and control before deploying application stacks.

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

## Quick Start (advanced / Portainer-first)

```bash
# 1 — Set your node IPs and SSH users
cp config/node-inventory.env.example config/node-inventory.env
nano config/node-inventory.env

# 2 — Audit SSH connectivity and hardware on all nodes
./scripts/ssh-auditor.sh
#     ↳ add --fix-firewall to auto-open ports
#     ↳ add --install-keys to push SSH keys

# 3 — Install Portainer on every reachable node
./scripts/portainer-install.sh

# 4 — Deploy application stacks
./scripts/deploy-all.sh
```

Full guide: **[PORTAINER_GUIDE.md](PORTAINER_GUIDE.md)**

---

| Node | Role                  | Hardware          | Key Services           |
|------|-----------------------|-------------------|------------------------|
| A    | Brain — heavy LLM     | AMD RX 7900 XT    | vLLM :8000, Dashboard :3099 |
| B    | Gateway — Unraid      | RTX 4070 12GB     | LiteLLM :4000, Portainer :9000 |
| C    | Vision AI             | Intel Arc A770    | Ollama :11434, Open WebUI :3000 |
| D    | Home Automation       | —                 | Home Assistant :8123   |
| E    | Surveillance          | —                 | Blue Iris :81, Sentinel :3005 |

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
| [docs/25_STACK_ANALYSIS_AND_ALTERNATIVES.md](docs/25_STACK_ANALYSIS_AND_ALTERNATIVES.md) | **Overwhelmed?** — Stack review, simpler alternatives, beginner quick-win path |
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
