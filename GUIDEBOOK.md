# Grand Unified AI Home Lab — Master Guidebook (2026)

> **This is the single canonical reference for deploying, operating, and administering your complete AI home-lab stack.**  
> Every chapter is self-contained and installation-ordered. Read sequentially for a first deploy; jump to any chapter for ongoing operations.

---

## Table of Contents

| # | Chapter | What you will accomplish |
|---|---------|--------------------------|
| 0 | [Pre-Flight & Network Map](#chapter-0--pre-flight--network-map) | Verify hardware, set IP plan, install Ansible & prereqs on Fedora 43 |
| 1 | [Node C — Intel Arc Command Center](#chapter-1--node-c--intel-arc-command-center-fedora-43) | Ollama + Chimera Face UI on your Fedora 43 / Intel Arc A770 |
| 2 | [Node B — LiteLLM Gateway](#chapter-2--node-b--litellm-gateway-unraid) | Unified AI API gateway on Unraid (Node B) |
| 3 | [Node A — Command Center Dashboard](#chapter-3--node-a--command-center-dashboard) | Node.js status dashboard + chat proxy |
| 4 | [KVM Operator](#chapter-4--kvm-operator) | FastAPI AI-controlled KVM over IP (NanoKVM Cube) |
| 5 | [OpenClaw AI Gateway](#chapter-5--openclaw-ai-gateway) | OpenClaw personal AI assistant + deployment skills |
| 6 | [OpenClaw × KVM Integration](#chapter-6--openclaw--kvm-integration) | Wire OpenClaw to KVM Operator for full AI-driven control |
| 7 | [Deploy GUI](#chapter-7--deploy-gui--visual-deployment-console) | Visual web GUI to deploy & administer all nodes from Fedora 43 |
| 8 | [Home Assistant Integration](#chapter-8--home-assistant-integration) | Smart-home voice control via LiteLLM |
| 9 | [Node E — Sentinel / NVR](#chapter-9--node-e--sentinel--nvr) | AI-assisted NVR webhook integration |
| 10 | [Portainer Stack Administration](#chapter-10--portainer-stack-administration) | Manage all Docker stacks from one UI |
| 11 | [User Manual — Day-to-Day Operations](#chapter-11--user-manual--day-to-day-operations) | How to use everything once it is running |
| 12 | [Security & Hardening](#chapter-12--security--hardening) | Keys, tokens, network isolation, denylist |
| 13 | [Troubleshooting](#chapter-13--troubleshooting) | Failure modes, log locations, diagnostic commands |

---

## Chapter 0 — Pre-Flight & Network Map

### 0.1 Hardware Reference

| Node | Machine | Role | Key hardware |
|------|---------|------|-------------|
| Node A | Fedora 43 workstation | Brain / heavy reasoning | RX 7900 XT 20 GB |
| Node B | Unraid server | LiteLLM gateway + Brawn | i5-13600K, 96 GB, RTX 4070 12 GB |
| Node C | Fedora 43 workstation | Vision AI + Command Center UI | Ryzen 7 7700X, 32 GB, Intel Arc A770 16 GB |
| Node D | Any machine | Home Assistant | – |
| Node E | Any machine | Sentinel NVR | – |
| KVM Host | Any machine | NanoKVM Cube physical attachment | – |

> **Note:** Node A and Node C may be the same Fedora 43 machine if you have both GPUs installed.

### 0.2 Network Address Plan

Fill this table before starting. All configuration files reference these values:

```
NODE_A_IP=192.168.1.9        # Brain / vLLM
NODE_B_IP=192.168.1.222      # Unraid / LiteLLM gateway
NODE_C_IP=192.168.1.6        # Intel Arc / Ollama
NODE_D_IP=192.168.1.149      # Home Assistant
NODE_E_IP=192.168.1.116      # Blue Iris / Sentinel (Windows VM on Proxmox)
PROXMOX_IP=192.168.1.174     # Proxmox server
KVM_IP=192.168.1.130         # NanoKVM kvm-d829.local
KVM_HOSTNAME=kvm-d829.local  # NanoKVM hostname
CLOUDFLARE_DOMAIN=happystrugglebus.us
```

### 0.3 Required Software on Fedora 43 (Command Center)

```bash
# Docker (official repo — NOT the Fedora package)
sudo dnf remove docker docker-engine docker.io -y 2>/dev/null || true
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install docker-ce docker-ce-cli containerd.io docker-compose-plugin -y
sudo systemctl enable --now docker
sudo usermod -aG docker $USER   # log out + back in

# Node.js 22 LTS
sudo dnf install nodejs npm -y

# OpenSSH client (for remote deploys)
sudo dnf install openssh-clients sshpass -y

# jq (for JSON parsing in scripts)
sudo dnf install jq -y

# Python 3 + pip (for KVM operator)
sudo dnf install python3 python3-pip -y

# Ansible (for multi-node automation)
sudo dnf install ansible -y

# Git
sudo dnf install git -y
```

### 0.4 SSH Key Setup

```bash
# Generate key if you don't already have one
ssh-keygen -t ed25519 -C "homelab-deployer" -f ~/.ssh/homelab

# Copy to each node (repeat for NODE_B, NODE_D, NODE_E)
ssh-copy-id -i ~/.ssh/homelab.pub user@$NODE_B_IP
ssh-copy-id -i ~/.ssh/homelab.pub user@$NODE_C_IP

# Add to SSH config
cat >> ~/.ssh/config <<'EOF'
Host node-b
  HostName 192.168.1.222
  User YOUR_USERNAME
  IdentityFile ~/.ssh/homelab

Host node-c
  HostName 192.168.1.6
  User YOUR_USERNAME
  IdentityFile ~/.ssh/homelab
EOF
```

### 0.5 Clone the Repository

```bash
git clone https://github.com/Enigmaticjoe/onemoreytry.git ~/homelab
cd ~/homelab
```

### 0.6 Run Pre-Flight Check

```bash
./scripts/preflight-check.sh
```

This script verifies:
- Docker daemon running
- Node.js ≥ 20
- SSH connectivity to all nodes
- Required ports not already in use
- YAML config syntax

---

## Chapter 1 — Node C — Intel Arc Command Center (Fedora 43)

> **Install first.** This provides the local Vision AI endpoint that LiteLLM (Node B) routes to.

### 1.1 Install Intel GPU Drivers

```bash
# Intel compute runtime for Arc GPUs
sudo dnf install intel-compute-runtime intel-level-zero-gpu intel-opencl -y
sudo dnf install mesa-libGL mesa-dri-drivers -y

# Verify GPU is visible
ls /dev/dri/render*     # should show /dev/dri/renderD128 or similar
clinfo | grep -A2 "Device Name"
```

### 1.2 Deploy Ollama + Chimera Face

```bash
cd ~/homelab/node-c-arc

# Review and edit docker-compose.yml if needed
# Node C IP: 192.168.1.6

docker compose up -d

# Wait for Ollama to become healthy (~30 s)
docker compose ps

# Pull the vision model (llava 7B, ~4.5 GB)
docker exec ollama_intel_arc ollama pull llava

# Optional: pull a coding/chat model
docker exec ollama_intel_arc ollama pull mistral
docker exec ollama_intel_arc ollama pull codellama
```

### 1.3 Verify

```bash
# Ollama API
curl http://localhost:11434/api/version
# → {"version":"..."}

# List models
curl http://localhost:11434/api/tags | jq '.models[].name'

# Chimera Face UI
xdg-open http://localhost:3000  # Opens Open WebUI in browser
```

### 1.4 Troubleshooting Arc GPU

```bash
# Check GPU device nodes
ls -la /dev/dri/

# Confirm Level Zero sees the GPU
/usr/bin/clinfo | grep "Intel(R) Arc"

# If Ollama can't find the GPU:
docker logs ollama_intel_arc 2>&1 | grep -i "gpu\|arc\|level"
# Ensure ZES_ENABLE_SYSMAN=1 is set in docker-compose.yml (it is by default)
```

---

## Chapter 2 — Node B — LiteLLM Gateway (Unraid)

> **Install second.** Routes all AI requests to the appropriate backend.

### 2.1 Prerequisites on Unraid

- Unraid 6.12+ with Docker enabled
- Portainer CE installed (Community Applications → Portainer)
- SSH access enabled (Unraid Settings → SSH)

### 2.2 Configure LiteLLM

```bash
# SSH into Unraid from your Fedora machine
ssh node-b

cd /mnt/user/appdata  # Unraid appdata location
git clone https://github.com/Enigmaticjoe/onemoreytry.git homelab
cd homelab/node-b-litellm
```

Edit `config.yaml` and replace placeholder IPs:
- Node A (Brain/vLLM): `192.168.1.9`
- Node C (Ollama): `192.168.1.6`
- Node B (Gateway): `192.168.1.222`

### 2.3 Deploy via Portainer

1. Open Portainer at `http://<NODE_B_IP>:9000`
2. Go to **Stacks → Add Stack**
3. Paste the contents of `node-b-litellm/litellm-stack.yml`
4. Set environment variables:
   - `LITELLM_MASTER_KEY` = `sk-master-key` (change this!)
5. Deploy

Or deploy via CLI:
```bash
# On Unraid (SSH)
cd /mnt/user/appdata/homelab/node-b-litellm
docker compose -f litellm-stack.yml up -d
```

### 2.4 Verify

```bash
# From Node B or any machine on LAN
curl http://192.168.1.222:4000/health
# → {"status":"healthy"}

# List available models
curl http://192.168.1.222:4000/v1/models \
  -H "Authorization: Bearer sk-master-key" | jq '.data[].id'
```

### 2.5 Postgres (Optional — for LiteLLM history)

Already included in `litellm-stack.yml`. Postgres runs as a sidecar container and provides spend tracking, audit logs, and key management.

---

## Chapter 3 — Node A — Command Center Dashboard

> **Install third.** Provides the web dashboard and status/chat proxy.

### 3.1 Start the Dashboard

```bash
cd ~/homelab/node-a-command-center

# Set environment variables (or export them in ~/.bashrc)
export LITELLM_BASE_URL=http://192.168.1.222:4000
export BRAIN_BASE_URL=http://192.168.1.9:8000
export NODE_C_BASE_URL=http://192.168.1.6
export NODE_E_BASE_URL=http://192.168.1.116:3005

node node-a-command-center.js
```

### 3.2 Access the Dashboard

- **Main Dashboard:** `http://localhost:3099`
- **Status API:** `http://localhost:3099/api/status`
- **Chat Proxy:** `POST http://localhost:3099/api/chat`
- **Install Wizard:** `http://localhost:3099/install-wizard`

### 3.3 Install as a Desktop Icon (Fedora 43)

```bash
chmod +x ~/homelab/node-a-command-center/install-desktop-icon.sh
~/homelab/node-a-command-center/install-desktop-icon.sh
```

This creates a `.desktop` launcher on your Fedora desktop.

### 3.4 Run as a systemd Service

```bash
# Create a systemd user service
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/node-a-dashboard.service <<'EOF'
[Unit]
Description=Node A Command Center Dashboard
After=network.target

[Service]
WorkingDirectory=%h/homelab/node-a-command-center
ExecStart=/usr/bin/node node-a-command-center.js
Restart=on-failure
Environment=LITELLM_BASE_URL=http://192.168.1.222:4000
Environment=BRAIN_BASE_URL=http://192.168.1.9:8000

[Install]
WantedBy=default.target
EOF

systemctl --user enable --now node-a-dashboard
```

---

## Chapter 4 — KVM Operator

> **Install on Node A (Fedora 43) — the machine that will manage other machines via NanoKVM.**

### 4.1 What Is the KVM Operator?

The KVM Operator is a FastAPI service that:
1. Accepts **REST API calls** from OpenClaw (or any client)
2. Connects to one or more **NanoKVM Cube** devices on your LAN
3. Can capture screenshots, control power (on/off/reset), and simulate keyboard/mouse
4. Enforces a **human-in-the-loop approval gate** (`REQUIRE_APPROVAL=true`)
5. Blocks destructive commands via `policy_denylist.txt`

**Why on Node A / Fedora 43?**  
The KVM Operator is a Python service, not a Docker container. It runs natively on the command center machine where the operator (you) can approve or reject AI actions. It can reach all NanoKVM devices on your LAN from this central location.

### 4.2 Install & Configure

```bash
cd ~/homelab/kvm-operator

# Copy and edit environment file
cp .env.example .env
nano .env
```

Edit `.env`:
```bash
KVM_OPERATOR_TOKEN=<generate with: openssl rand -hex 24>
NANOKVM_USERNAME=admin
NANOKVM_PASSWORD=admin           # change to your NanoKVM password
NANOKVM_AUTH_MODE=auto
KVM_TARGETS_JSON={"kvm-d829":"192.168.1.130"}
LITELLM_URL=http://192.168.1.222:4000/v1/chat/completions
LITELLM_KEY=sk-master-key
VISION_MODEL=intel-vision
REQUIRE_APPROVAL=true            # KEEP true unless fully automated pipeline
ALLOW_DANGEROUS=false            # NEVER set true in production
```

### 4.3 Start the KVM Operator

```bash
./run_dev.sh
# → Uvicorn running on http://0.0.0.0:5000
```

Or as a systemd service:
```bash
sudo cp systemd/ai-kvm-operator.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now ai-kvm-operator
```

### 4.4 Verify

```bash
curl http://localhost:5000/health
# → {"ok":true,"targets":["node-c","node-b"]}

# Take a screenshot of a KVM target
curl -H "Authorization: Bearer <YOUR_TOKEN>" \
  http://localhost:5000/kvm/snapshot/node-c
# → {"ok":true,"jpeg_b64":"..."}

# Check power state
curl -H "Authorization: Bearer <YOUR_TOKEN>" \
  http://localhost:5000/kvm/power/node-c
# → {"ok":true,"state":"on"}
```

### 4.5 NanoKVM Cube — Physical Setup

1. Connect NanoKVM Cube HDMI output to the target machine's HDMI input
2. Connect NanoKVM USB to the target machine's USB port (for HID)
3. Connect NanoKVM Ethernet to your LAN
4. Note the IP address (check your router or NanoKVM's display)
5. Default credentials: `admin` / `admin` — **change these immediately**

---

## Chapter 5 — OpenClaw AI Gateway

> **Install on Node B (Unraid).** OpenClaw is the AI personal assistant that uses your local models and cloud fallbacks.

### 5.1 What Is OpenClaw?

OpenClaw is a self-hosted AI gateway that:
- Runs as a Docker container on Unraid
- Connects to local AI models (vLLM, Ollama) and cloud providers
- Provides a web Control UI, OpenAI-compatible API, and webhooks
- Can be extended with **skills** (markdown files that give agents new capabilities)
- Integrates with Home Assistant, Unraid server management, KVM control, and more

### 5.2 Prerequisites on Unraid

```bash
# SSH into Unraid and create data directories
mkdir -p /mnt/user/appdata/openclaw/{config,workspace,homebrew}

# Copy and configure openclaw.json
cp ~/homelab/openclaw/openclaw.json \
   /mnt/user/appdata/openclaw/config/

# Get your vLLM model ID (run from Unraid if vLLM is on port 8880)
curl http://localhost:8880/v1/models | jq '.data[].id'
# → "meta-llama/Meta-Llama-3-8B-Instruct" or similar

# Edit openclaw.json: replace "your-model-id-here" with the actual model ID
nano /mnt/user/appdata/openclaw/config/openclaw.json
```

### 5.3 Generate Gateway Token

```bash
openssl rand -hex 24
# → abc123def456...   ← copy this value
```

### 5.4 Create Environment File

Create `/mnt/user/appdata/openclaw/.env`:
```bash
OPENCLAW_GATEWAY_TOKEN=<token from above>
VLLM_API_KEY=vllm-local

# Optional cloud fallbacks
# ANTHROPIC_API_KEY=sk-ant-...
# OPENAI_API_KEY=sk-...
# GEMINI_API_KEY=...

# Home Assistant (optional)
# HOME_ASSISTANT_URL=http://192.168.1.149:8123
# HOME_ASSISTANT_TOKEN=<HA long-lived token>

# Unraid control (optional)
# UNRAID_API_KEY=<from Unraid Settings → Management Access>

# KVM Operator (see Chapter 6)
KVM_OPERATOR_URL=http://192.168.1.9:5000
KVM_OPERATOR_TOKEN=<kvm operator token from Chapter 4>
```

### 5.5 Deploy OpenClaw via Portainer

1. Open Portainer at `http://<NODE_B_IP>:9000`
2. **Stacks → Add Stack → Upload**
3. Upload `openclaw/docker-compose.yml` from this repository
4. Set environment variables from your `.env` file above
5. Click **Deploy the stack**

Or via CLI:
```bash
# On Unraid (SSH)
cd /mnt/user/appdata/homelab/openclaw
docker compose --env-file /mnt/user/appdata/openclaw/.env up -d
```

### 5.6 Access OpenClaw

```
Control UI:    http://<NODE_B_IP>:18789/?token=<OPENCLAW_GATEWAY_TOKEN>
API endpoint:  http://<NODE_B_IP>:18789/v1
Webhook:       POST http://<NODE_B_IP>:18789/hooks/agent
```

### 5.7 First-Time Setup

```bash
# Access container console (Portainer → openclaw-gateway → Console, or:)
docker exec -it openclaw-gateway sh

# Verify vLLM is detected
node dist/index.js models list

# Switch to your local model
# (in OpenClaw chat UI, type:)
/model vllm/your-model-id-here

# Install the KVM skill (see Chapter 6)
# Copy skill file to workspace
cp /home/node/clawd/skill-kvm.md /home/node/clawd/AGENTS.md  # or include in AGENTS.md
```

### 5.8 Install Deployment Skill

The deployment skill lets OpenClaw deploy and manage your entire lab:

```bash
# On Unraid, copy skill files to OpenClaw workspace
cp ~/homelab/openclaw/skill-deploy.md \
   /mnt/user/appdata/openclaw/workspace/skill-deploy.md
cp ~/homelab/openclaw/skill-kvm.md \
   /mnt/user/appdata/openclaw/workspace/skill-kvm.md

# Create or update AGENTS.md to reference the skills
cat > /mnt/user/appdata/openclaw/workspace/AGENTS.md <<'EOF'
# OpenClaw Agent Context

You are an AI assistant managing a multi-node home AI lab.
Read these skill files to understand your capabilities:
- skill-kvm.md — KVM control via NanoKVM Cube
- skill-deploy.md — Node deployment and Portainer stack management
EOF
```

---

## Chapter 6 — OpenClaw × KVM Integration

> This chapter explains the complete integration between OpenClaw (Chapter 5) and the KVM Operator (Chapter 4).

### 6.1 Architecture

```
OpenClaw (Node B :18789)
    │
    │  HTTP  Bearer <KVM_OPERATOR_TOKEN>
    ▼
KVM Operator (Node A :5000)
    │
    │  HTTP  NanoKVM API
    ▼
NanoKVM Cube device(s)
    │
    │  HDMI+USB
    ▼
Target machine (Node C, Node B, etc.)
```

### 6.2 What OpenClaw Can Do via KVM

| Capability | API call | Safety gate |
|-----------|---------|-------------|
| See the screen | `GET /kvm/snapshot/{target}` | None (read-only) |
| Check power state | `GET /kvm/power/{target}` | None (read-only) |
| Get device info | `GET /kvm/status/{target}` | None (read-only) |
| Power on/off/reset | `POST /kvm/power/{target}` | `REQUIRE_APPROVAL` |
| Type text / key combos | `POST /kvm/keyboard/{target}` | `REQUIRE_APPROVAL` |
| Move mouse / click | `POST /kvm/mouse/{target}` | `REQUIRE_APPROVAL` |
| Run AI vision task | `POST /kvm/task/{target}` | `REQUIRE_APPROVAL` |

### 6.3 Example: Ask OpenClaw to Restart a Node

In the OpenClaw chat UI (or via API/webhook):

```
"Check if node-c is powered on, take a screenshot, then restart it if it shows a frozen screen."
```

OpenClaw will:
1. Call `GET /kvm/power/node-c` → check power state
2. Call `GET /kvm/snapshot/node-c` → capture and analyze screen
3. If frozen: call `POST /kvm/power/node-c` `{"action":"reset"}` — **paused for your approval if `REQUIRE_APPROVAL=true`**
4. Wait for approval → execute reset

### 6.4 Example: Deploy Docker Stack on Node C via KVM

```
"Use KVM to log into node-c and run: cd ~/homelab && docker compose up -d"
```

This runs the AI vision task loop:
1. Screenshot the screen
2. Identify what's on screen (login prompt? Desktop? Terminal?)
3. If login prompt: type credentials
4. Open terminal → type the command → press Enter
5. Screenshot again to verify success

### 6.5 Configuring OpenClaw for KVM

Ensure these are set in OpenClaw's environment (they are already in `openclaw/docker-compose.yml`):

```bash
KVM_OPERATOR_URL=http://192.168.1.9:5000    # Node A KVM Operator
KVM_OPERATOR_TOKEN=<your token>
```

The `skill-kvm.md` file documents all available API endpoints and their parameters for the AI agent.

### 6.6 Security Considerations

- **Never set `REQUIRE_APPROVAL=false`** unless you are running a fully automated, well-tested pipeline
- The `policy_denylist.txt` blocks: `rm -rf`, `mkfs`, `dd if=`, `:(){ :|:& }`, `chmod 777 /`, and similar destructive commands
- OpenClaw's `OPENCLAW_GATEWAY_TOKEN` is separate from `KVM_OPERATOR_TOKEN` — rotate both regularly
- The NanoKVM AES key is hardcoded in firmware (see GitHub issue #270) — treat KVM network as a trusted LAN segment only
- Never expose KVM Operator port 5000 to the internet; use Tailscale if you need remote access

---

## Chapter 7 — Deploy GUI — Visual Deployment Console

> **Runs on Node A / Fedora 43.** A full-featured web GUI for deploying and administering all nodes.

### 7.1 What the Deploy GUI Does

The Deploy GUI is a Docker container running a Node.js web application. From your Fedora 43 browser you can:

- **Deploy** any node's Docker stack with one click
- **View real-time logs** via streaming terminal output
- **Manage Portainer stacks** on Node B (start/stop/recreate)
- **Run smoke tests** against each node's health endpoint
- **SSH execute** commands on remote nodes
- **Trigger OpenClaw** deployment tasks
- **Administer** all services from one place

### 7.2 Deploy the GUI

```bash
cd ~/homelab/deploy-gui

# Build and start
docker compose up -d --build

# Access at:
xdg-open http://localhost:9999
```

### 7.3 GUI Overview

| Tab | Purpose |
|-----|---------|
| **Overview** | Live status of all nodes and services |
| **Deploy** | Deploy/redeploy any node's stack |
| **Logs** | Stream logs from any container on any node |
| **Portainer** | Manage Portainer stacks (Node B) |
| **Terminals** | SSH terminal to any node in-browser |
| **OpenClaw** | Trigger OpenClaw tasks, view responses |
| **Settings** | Configure node IPs, tokens |

### 7.4 First-Time Setup

When you open the GUI for the first time:
1. Go to **Settings** tab
2. Enter your node IPs (Node A–E, KVM)
3. Enter your tokens (LiteLLM key, KVM Operator token, OpenClaw token)
4. Click **Save** — settings are persisted in `deploy-gui/data/settings.json`
5. Return to **Overview** to see all node statuses

---

## Chapter 8 — Home Assistant Integration

> Install after Node B is running. Node D is the Home Assistant machine.

### 8.1 Configure HA

Copy the snippet into your `configuration.yaml`:

```bash
# On your HA machine
cat ~/homelab/home-assistant/configuration.yaml.snippet >> /path/to/ha/configuration.yaml
```

Or paste manually. The relevant section:

```yaml
openai_conversation:
  api_key: sk-master-key
  base_url: "http://192.168.1.222:4000/v1"
  chat_model: brain-heavy
```

### 8.2 Reload HA Configuration

```bash
# Via HA API
curl -X POST http://192.168.1.149:8123/api/config/core/check_config \
  -H "Authorization: Bearer <HA_TOKEN>"
# Then: Developer Tools → YAML → Reload All YAML
```

### 8.3 Test Voice Control

Say or type in HA:
- "Turn off the living room lights"
- "What's my AI lab status?"

### 8.4 OpenClaw + Home Assistant

If you set `HOME_ASSISTANT_URL` and `HOME_ASSISTANT_TOKEN` in OpenClaw, you can control HA directly from OpenClaw:

```
"Turn off the garage lights and set the thermostat to 68°F"
```

---

## Chapter 9 — Node E — Sentinel / NVR

**Node E: Blue Iris NVR at `192.168.1.116` (Windows VM on Proxmox `192.168.1.174`)**

### 9.1 Webhook Integration

Node E runs Blue Iris NVR. Connect its motion-detection webhooks to the AI stack:

```bash
# In your NVR software, set a webhook for motion events:
POST http://192.168.1.222:4000/v1/chat/completions
Authorization: Bearer sk-master-key
Content-Type: application/json
{
  "model": "intel-vision",
  "messages": [
    {"role": "user", "content": [
      {"type": "text", "text": "Describe what is happening in this image."},
      {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,<B64_IMAGE>"}}
    ]}
  ]
}
```

### 9.2 Node E Dashboard

```bash
cd ~/homelab/node-e-sentinel
node node-e-sentinel.js
# Dashboard at http://localhost:3005
```

---

## Chapter 10 — Portainer Stack Administration

### 10.1 Access Portainer

- Node B: `http://192.168.1.222:9000`
- Default admin: create on first login

### 10.2 Add Node A as a Portainer Agent

On Node A (Fedora 43):
```bash
docker run -d \
  -p 9001:9001 \
  --name portainer-agent \
  --restart always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/lib/docker/volumes:/var/lib/docker/volumes \
  portainer/agent:latest
```

In Portainer (Node B) → **Environments → Add Environment → Docker Standalone → Agent**:
- URL: `http://192.168.1.9:9001`
- Name: `Node-A`

Repeat for Node C.

### 10.3 Managing Stacks via Portainer

1. **View all stacks:** Home → Select environment → Stacks
2. **Update a stack:** Click stack name → Editor → Paste updated compose YAML → Update
3. **View logs:** Select stack → Services → Click service → Logs
4. **Restart a service:** Select stack → Services → Click service → Recreate

### 10.4 OpenClaw Stack Management

Ask OpenClaw (once `UNRAID_API_KEY` is set):
```
"List all running Docker stacks on Node B"
"Restart the litellm_gateway container"
"Show me the logs from the last 50 lines of openclaw-gateway"
```

---

## Chapter 11 — User Manual — Day-to-Day Operations

### 11.1 Starting Everything (Full Stack)

Use the master deploy script for a clean start:

```bash
cd ~/homelab
./scripts/deploy-all.sh
```

Or start services individually:

```bash
# Node C (Intel Arc) — start Ollama + Chimera Face
cd ~/homelab/node-c-arc && docker compose up -d

# Node B (LiteLLM) — on Unraid (SSH)
ssh node-b "cd /mnt/user/appdata/homelab/node-b-litellm && \
  docker compose -f litellm-stack.yml up -d"

# Node A Dashboard
cd ~/homelab/node-a-command-center
node node-a-command-center.js &

# KVM Operator
cd ~/homelab/kvm-operator
./run_dev.sh &

# Deploy GUI
cd ~/homelab/deploy-gui
docker compose up -d
```

### 11.2 Stopping Everything

```bash
./scripts/deploy-all.sh stop
# Or individually:
cd ~/homelab/node-c-arc && docker compose down
cd ~/homelab/deploy-gui && docker compose down
```

### 11.3 Checking Status

**Quick health check (all nodes):**
```bash
./scripts/preflight-check.sh --health-only
```

**Individual checks:**
```bash
# Node B LiteLLM
curl http://192.168.1.222:4000/health

# Node C Ollama
curl http://localhost:11434/api/version

# KVM Operator
curl -H "Authorization: Bearer <TOKEN>" http://localhost:5000/health

# OpenClaw
curl http://192.168.1.222:18789/
```

### 11.4 Chatting with Your AI

**Via Node A Dashboard:**
1. Open `http://localhost:3099`
2. Type in the chat box → select model → Send

**Via Chimera Face UI (local):**
1. Open `http://localhost:3000`
2. Select a model (llava, mistral, etc.)
3. Chat, upload images, etc.

**Via OpenClaw:**
1. Open `http://192.168.1.222:18789/?token=<TOKEN>`
2. Chat with your local models, trigger automations

**Via API (direct):**
```bash
curl http://192.168.1.222:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-master-key" \
  -H "Content-Type: application/json" \
  -d '{"model":"brain-heavy","messages":[{"role":"user","content":"Hello"}]}'
```

### 11.5 Using OpenClaw for Automation

**Check cluster status:**
```
"Give me a status report of all my AI nodes"
```

**Deploy or restart a service:**
```
"Restart the litellm_gateway container on Node B"
```

**KVM tasks:**
```
"Take a screenshot of node-c and tell me what's on the screen"
"Reboot node-c gently (via OS shutdown if possible, power reset as fallback)"
```

**Home automation:**
```
"It's getting dark outside — turn on the outdoor lights and set the thermostat to 70°F"
```

### 11.6 Updating Models

```bash
# Pull a new model on Node C
docker exec ollama_intel_arc ollama pull llama3.2-vision

# Update LiteLLM config to add the new model
nano ~/homelab/node-b-litellm/config.yaml
# Add new model entry, then:
ssh node-b "cd /mnt/user/appdata/homelab/node-b-litellm && \
  docker compose -f litellm-stack.yml restart"
```

### 11.7 Viewing Logs

```bash
# Node C Ollama logs
docker logs -f ollama_intel_arc

# Node C UI logs
docker logs -f chimera_face

# LiteLLM logs (on Node B)
ssh node-b "docker logs -f litellm_gateway"

# KVM Operator logs
journalctl -u ai-kvm-operator -f
# or: look at the terminal running ./run_dev.sh

# OpenClaw logs
ssh node-b "docker logs -f openclaw-gateway"
```

### 11.8 Backup

```bash
# Backup all appdata (run on each node)
# Node C
docker run --rm \
  -v ollama-models:/data/ollama-models \
  -v open-webui-data:/data/open-webui-data \
  -v $(pwd)/backup:/backup \
  alpine tar czf /backup/node-c-$(date +%Y%m%d).tar.gz /data

# Node B (Unraid) — use Unraid's built-in backup or:
rsync -av node-b:/mnt/user/appdata/openclaw ~/backups/openclaw-$(date +%Y%m%d)
```

---

## Chapter 12 — Security & Hardening

### 12.1 Secrets Management

**Never commit secrets to git.** All tokens are in `.env` files or environment variables.

```bash
# Add all .env files to .gitignore
echo "**/.env" >> ~/.gitignore_global
git config --global core.excludesfile ~/.gitignore_global

# Rotate the LiteLLM master key
# 1. Generate new key
openssl rand -hex 24
# 2. Update node-b-litellm/config.yaml
# 3. Update all clients (HA, Node A dashboard, KVM Operator)
# 4. Restart LiteLLM: docker compose -f litellm-stack.yml restart
```

### 12.2 Network Segmentation

- AI services (LiteLLM, Ollama, OpenClaw) should be on your **trusted LAN only**
- Never expose port 4000, 5000, 11434, or 18789 to the internet
- Use **Tailscale** for remote access:

```bash
# Install Tailscale on Fedora 43
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

### 12.3 KVM Denylist Management

Review and update `kvm-operator/policy_denylist.txt`:

```bash
cat ~/homelab/kvm-operator/policy_denylist.txt
```

Add new patterns:
```bash
echo "new-dangerous-pattern" >> ~/homelab/kvm-operator/policy_denylist.txt
# Restart KVM Operator to reload the list
sudo systemctl restart ai-kvm-operator
```

### 12.4 OpenClaw Token Rotation

```bash
# 1. Generate new token
NEW_TOKEN=$(openssl rand -hex 24)
echo "New token: $NEW_TOKEN"

# 2. Update environment on Node B
# Edit /mnt/user/appdata/openclaw/.env
# Change OPENCLAW_GATEWAY_TOKEN=<new token>

# 3. Restart OpenClaw
ssh node-b "docker restart openclaw-gateway"

# 4. Update any clients that use the Control UI URL
```

### 12.5 Container Security

- OpenClaw runs as `root` (required by official template) — do not expose to internet
- KVM Operator: runs as the current user — no special privileges needed
- Deploy GUI: runs as a non-root user inside the container

---

## Chapter 13 — Troubleshooting

### 13.1 Node C — Ollama Issues

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `ollama list` empty | Models not pulled | `docker exec ollama_intel_arc ollama pull llava` |
| GPU not detected | Level Zero missing | `sudo dnf install intel-level-zero-gpu -y` + restart container |
| OOM / crash | VRAM full | Use smaller model or reduce `OLLAMA_NUM_GPU` |
| Chimera Face can't reach Ollama | `host.docker.internal` not resolving | Add `extra_hosts: - "host.docker.internal:host-gateway"` (already in compose) |

### 13.2 Node B — LiteLLM Issues

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `/health` returns 503 | Backend unreachable | Check Node A / Node C are running |
| 401 Unauthorized | Wrong API key | Check `LITELLM_MASTER_KEY` matches all clients |
| Model not found | Config not loaded | `docker restart litellm_gateway` |
| Postgres connection error | DB not ready | `docker compose -f litellm-stack.yml restart` |

### 13.3 KVM Operator Issues

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `{"ok":false,"error":"NanoKVM login failed"}` | Wrong credentials | Update `NANOKVM_PASSWORD` in `.env` |
| Snapshot returns black image | NanoKVM HDMI disconnected | Check HDMI cable on NanoKVM device |
| 202 on every write | `REQUIRE_APPROVAL=true` | This is by design — approve in the terminal running the operator |
| `KeyError: 'node-c'` | Target not in `KVM_TARGETS_JSON` | Add the target to `.env` |

### 13.4 OpenClaw Issues

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| 1008 error on Control UI | Device not approved | `docker exec openclaw-gateway node dist/index.js devices list` then approve |
| vLLM model not found | Model ID mismatch | `curl http://<NODE_B_IP>:8880/v1/models` and update `openclaw.json` |
| KVM skill not working | Skills not in AGENTS.md | Copy `skill-kvm.md` to workspace and reference in AGENTS.md |
| Container exits on start | Config file missing | Check `/mnt/user/appdata/openclaw/config/openclaw.json` exists |

### 13.5 Deploy GUI Issues

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Can't reach remote nodes | SSH not configured | Run `ssh-copy-id user@<node-ip>` |
| Port 9999 in use | Another service on same port | Change `ports` in `deploy-gui/docker-compose.yml` |
| Settings not saved | Volume not mounted | Check `deploy-gui/docker-compose.yml` volume mount |

### 13.6 Diagnostic Script

```bash
# Run full diagnostics
./scripts/preflight-check.sh

# Check all container logs for errors (run on each node)
docker ps -a --format "table {{.Names}}\t{{.Status}}"
for c in $(docker ps -q); do
  echo "=== $(docker inspect --format '{{.Name}}' $c) ==="
  docker logs --tail=10 $c 2>&1 | grep -i "error\|fatal\|exception" || echo "(no errors)"
done
```

---

## Appendix A — Quick Reference

```
Service          | Node  | URL                              | Port
-----------------|-------|----------------------------------|------
LiteLLM Gateway  | B     | http://192.168.1.222:4000        | 4000
Ollama API       | C     | http://192.168.1.6:11434         | 11434
Chimera Face UI  | C     | http://192.168.1.6:3000          | 3000
Node A Dashboard | A     | http://192.168.1.9:3099          | 3099
KVM Operator     | A     | http://192.168.1.9:5000          | 5000
OpenClaw UI      | B     | http://192.168.1.222:18789       | 18789
Deploy GUI       | A     | http://localhost:9999            | 9999
Portainer        | B     | http://192.168.1.222:9000        | 9000
Home Assistant   | D     | http://192.168.1.149:8123        | 8123
Blue Iris NVR    | E     | http://192.168.1.116             | 80
Proxmox          | -     | http://192.168.1.174:8006        | 8006
NanoKVM          | -     | http://192.168.1.130 (kvm-d829)  | 80
```

## Appendix B — Install Order Cheat Sheet

```
1.  Pre-flight    → ./scripts/preflight-check.sh
2.  Node C        → cd node-c-arc && docker compose up -d
3.  Node B        → ssh node-b; docker compose -f litellm-stack.yml up -d
4.  Node A dash   → cd node-a-command-center && node node-a-command-center.js
5.  KVM Operator  → cd kvm-operator && ./run_dev.sh
6.  OpenClaw      → Portainer stacks on Node B
7.  Deploy GUI    → cd deploy-gui && docker compose up -d --build
8.  Home Asst     → merge configuration.yaml.snippet
9.  Node E        → cd node-e-sentinel && node node-e-sentinel.js
10. Validate      → ./validate.sh
```

## Appendix C — One-Shot Full Deploy

```bash
cd ~/homelab
./scripts/deploy-all.sh
# Deploys all nodes in sequence, with health checks between each step
```

---

*Guidebook maintained in `GUIDEBOOK.md` — update when adding new nodes or changing configuration.*
