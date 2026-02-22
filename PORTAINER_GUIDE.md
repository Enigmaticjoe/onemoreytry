# Portainer Deployment Guide — Grand Unified AI Homelab

> **Portainer-first workflow**: Install Portainer on every node first,
> then use it as the central control plane for all container stacks.

---

## Quick Start (3 Steps)

```bash
# 1 — Set your node IPs
cp config/node-inventory.env.example config/node-inventory.env
nano config/node-inventory.env

# 2 — Audit SSH connectivity + hardware (run once per setup)
./scripts/ssh-auditor.sh

# 3 — Install Portainer on all reachable nodes
./scripts/portainer-install.sh
```

That's it. The auditor handles SSH key issues, firewalls, and Tailscale
automatically. Portainer installs Docker if it's missing.

---

## Table of Contents

1. [What is Portainer?](#1-what-is-portainer)
2. [Architecture Overview](#2-architecture-overview)
3. [Step-by-Step: Configure Inventory](#3-step-by-step-configure-inventory)
4. [Step-by-Step: SSH Auditor](#4-step-by-step-ssh-auditor)
5. [Step-by-Step: Portainer Install](#5-step-by-step-portainer-install)
6. [First Login & Initial Setup](#6-first-login--initial-setup)
7. [Deploying Stacks via Portainer](#7-deploying-stacks-via-portainer)
8. [Portainer API & Automation](#8-portainer-api--automation)
9. [SSH Troubleshooting Reference](#9-ssh-troubleshooting-reference)
10. [Firewall Reference](#10-firewall-reference)
11. [Tailscale Setup](#11-tailscale-setup)
12. [Uninstall / Reset](#12-uninstall--reset)

---

## 1. What is Portainer?

Portainer is a web-based container management GUI that runs as a Docker
container. Once installed on a node, it lets you:

- Deploy and manage Docker containers and Compose stacks from a browser
- Monitor container logs, resource usage, and health in real time
- Manage multiple nodes from a single Portainer instance (via Portainer Agents)
- Trigger stack redeployments via REST API (used by deploy-all.sh)

**Why Portainer-first?**
Installing Portainer before anything else gives you a visual dashboard to
watch deployments in progress, debug container issues without SSH, and
redeploy stacks with one click if something goes wrong.

---

## 2. Architecture Overview

```
Your browser
     │
     ▼
Portainer CE (per node)          ← installed by portainer-install.sh
     │                              port 9000 (HTTP) / 9443 (HTTPS)
     ├── Docker daemon
     │     ├── litellm_gateway    (Node B)
     │     ├── ollama_intel_arc   (Node C)
     │     ├── homelab-deploy-gui (Node B)
     │     └── ...
     │
     └── Portainer Agent          ← optional, for multi-node management
           port 8000

Node inventory (config/node-inventory.env)
     │
     ├── ssh-auditor.sh           ← discovers best SSH route per node
     │     └── /tmp/homelab-connmap.env
     │
     └── portainer-install.sh    ← uses connmap to install Portainer
```

**Ports used by Portainer:**

| Port | Protocol | Purpose                    |
|------|----------|----------------------------|
| 9000 | HTTP     | Web UI & REST API          |
| 9443 | HTTPS    | Web UI & REST API (TLS)    |
| 8000 | TCP      | Portainer Agent tunnel     |

---

## 3. Step-by-Step: Configure Inventory

### 3.1 Copy the example file

```bash
cp config/node-inventory.env.example config/node-inventory.env
```

### 3.2 Edit with your IPs

```bash
nano config/node-inventory.env
```

Key fields to set:

```bash
# LAN IPs — set the actual IP for nodes you have
NODE_A_IP=192.168.1.9        # your brain/GPU node
NODE_B_IP=192.168.1.222      # your Unraid or main server
NODE_C_IP=192.168.1.6        # Intel Arc vision node

# SSH users — match the login user on each OS
NODE_A_SSH_USER=root         # Fedora/RHEL → root or your username
NODE_B_SSH_USER=root         # Unraid → root
NODE_C_SSH_USER=root         # Fedora → root

# Tailscale IPs — only needed if LAN SSH doesn't work
NODE_A_TS_IP=                # 100.x.x.x from `tailscale status`
NODE_B_TS_IP=
```

**Tip:** Leave nodes you don't have with `.X`/`.Y`/`.Z` in the IP — all
scripts automatically skip unconfigured nodes.

---

## 4. Step-by-Step: SSH Auditor

The SSH auditor is the pre-flight step that discovers how to reach each
node, inventories hardware, and checks what software is installed.

### 4.1 Basic audit

```bash
./scripts/ssh-auditor.sh
```

**What it does:**
1. Tests SSH to each node (LAN, multiple ports, multiple users)
2. Falls back to Tailscale if LAN fails
3. Audits hardware: CPU, RAM, GPU, storage
4. Checks software: Docker, Portainer, running containers
5. Checks firewall status on each node
6. Writes `/tmp/homelab-connmap.env` for portainer-install.sh

### 4.2 Auto-fix firewall ports

```bash
./scripts/ssh-auditor.sh --fix-firewall
```

Opens ports 22 (SSH), 9000 and 9443 (Portainer) on each node's firewall.
Works with ufw (Ubuntu/Debian) and firewalld (Fedora/RHEL).

### 4.3 Push SSH keys to all nodes

```bash
./scripts/ssh-auditor.sh --install-keys
```

Uses `ssh-copy-id` to push your public key. Will prompt for each node's
password once, then SSH becomes passwordless for all future operations.

### 4.4 Audit a specific node

```bash
./scripts/ssh-auditor.sh --node NODE_B
```

### 4.5 View last report

```bash
./scripts/ssh-auditor.sh --report
# or:
cat /tmp/homelab-audit.md
```

### 4.6 Understanding the output

```
── NODE: NODE_B  (LAN: 192.168.1.222  TS: unset) ──

  ✓ Ping 192.168.1.222 — reachable
  ✓ SSH connected: root@192.168.1.222:22

  Hardware:
  → Hostname:  unraid-server
  → OS:        Unraid 7.0
  → CPU:       Intel Core i9-13900K (24 cores)
  → RAM:       64GB total, 48GB free
  → Disk:      8.0T free of 10T

  GPU:
  ✓ NVIDIA: NVIDIA GeForce RTX 4070, 12282 MiB total

  Docker & Containers:
  ✓ Docker 26.1.3 (daemon: true)
  ! Portainer: not installed (will be deployed)     ← will be installed
  → Running containers:
      • litellm_gateway:Up 3 hours

  Network & Firewall:
  → Firewall: ufw:active
  ! Firewall detected on NODE_B — run with --fix-firewall to auto-open ports
```

---

## 5. Step-by-Step: Portainer Install

### 5.1 Install on all reachable nodes

```bash
./scripts/portainer-install.sh
```

**What it does per node:**
1. Checks if Docker is installed — installs automatically if missing
2. Checks if Portainer is already running — skips if so
3. Pulls `portainer/portainer-ce:latest`
4. Creates `portainer_data` Docker volume for persistence
5. Runs Portainer with the standard port bindings
6. Opens firewall rules for ports 9000, 9443, 8000
7. Waits for the API to become healthy
8. Prints the login URL

### 5.2 Check current status

```bash
./scripts/portainer-install.sh --status
```

Quick HTTP check of all Portainer endpoints — no SSH needed.

### 5.3 Force reinstall

```bash
./scripts/portainer-install.sh --force
```

Stops and removes existing container, then reinstalls from scratch.

### 5.4 Update to latest version

```bash
./scripts/portainer-install.sh --update
```

Pulls the latest image, replaces the container, preserves data volume.

### 5.5 Single node

```bash
./scripts/portainer-install.sh --node NODE_C
```

---

## 6. First Login & Initial Setup

After Portainer installs, you see output like:

```
╔══════════════════════════════════════════════════╗
║  Portainer is READY on NODE_B
╚══════════════════════════════════════════════════╝

  Admin URL (HTTP):  http://192.168.1.222:9000
  Admin URL (HTTPS): https://192.168.1.222:9443

  IMPORTANT — First Login:
    1. Open the URL above in your browser
    2. Create an admin account (username + password)
    3. Select 'Get Started' → choose 'local' environment
```

### 6.1 Steps on first open

1. **Set admin password** — choose a strong password, username defaults to `admin`
2. **Select environment** — choose **"Get Started"** then select **"local"**
   (This connects Portainer to the local Docker daemon on that node)
3. You're in the Portainer dashboard

> **Timeout warning:** Portainer requires you to set the admin password
> within 5 minutes of first start. If you see a timeout page, run:
> ```bash
> # On the node (via SSH):
> docker restart portainer
> ```
> Then open the URL again immediately.

### 6.2 Connect additional nodes (optional)

To manage multiple nodes from one Portainer, install Portainer Agent on
other nodes and add them as Environments:

```bash
# On Node A (run this on NODE A via SSH):
docker run -d \
  --name portainer_agent \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/lib/docker/volumes:/var/lib/docker/volumes \
  -p 9001:9001 \
  portainer/agent:latest
```

Then in Portainer UI on Node B:
**Settings → Environments → Add Environment → Agent → Enter NODE_A_IP:9001**

---

## 7. Deploying Stacks via Portainer

### 7.1 Deploy a Compose stack via UI

1. Open Portainer → **Stacks** → **Add stack**
2. Name it (e.g., `litellm`)
3. Paste or upload the `docker-compose.yml` content
4. Click **Deploy the stack**

### 7.2 Deploy using the script (API-backed)

The deploy-all.sh script uses Portainer's REST API when `PORTAINER_TOKEN`
is set. To enable this:

**Generate a Portainer API token:**
1. In Portainer → top-right username → **My Account**
2. Scroll to **Access tokens** → **Add access token**
3. Copy the `ptr_...` token

**Add to inventory:**
```bash
# In config/node-inventory.env:
PORTAINER_TOKEN=ptr_xxxxxxxxxxxxxxxxxxxxx
```

**Then run:**
```bash
./scripts/deploy-all.sh   # uses Portainer API automatically
```

### 7.3 Available stacks in this repo

| Stack name    | File                              | Node  | Purpose             |
|---------------|-----------------------------------|-------|---------------------|
| `litellm`     | `node-b-litellm/litellm-stack.yml`| B     | LLM gateway         |
| `openclaw`    | `openclaw/docker-compose.yml`     | B     | AI agent gateway    |
| `node-c`      | `node-c-arc/docker-compose.yml`   | C     | Ollama + WebUI      |
| `deploy-gui`  | `deploy-gui/docker-compose.yml`   | B     | Web control panel   |

---

## 8. Portainer API & Automation

The deploy scripts use the Portainer API to trigger stack redeployments
without SSH. Key endpoints:

```bash
PORTAINER_URL="http://192.168.1.222:9000"
TOKEN="ptr_xxxx"

# List stacks
curl -H "X-API-Key: $TOKEN" "$PORTAINER_URL/api/stacks"

# Get stack ID by name
curl -s -H "X-API-Key: $TOKEN" "$PORTAINER_URL/api/stacks" \
  | python3 -c "import json,sys; s=json.load(sys.stdin); \
    [print(x['Id']) for x in s if x['Name']=='litellm']"

# Redeploy a stack (pull latest + restart)
curl -X PUT \
  -H "X-API-Key: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"pullImage":true,"prune":false}' \
  "$PORTAINER_URL/api/stacks/1/git/redeploy"

# Check Portainer version/status
curl "$PORTAINER_URL/api/status"
```

---

## 9. SSH Troubleshooting Reference

### Problem: "Permission denied (publickey)"

SSH key not authorized on remote. Fix:

```bash
# Push your key (prompts for password once):
ssh-copy-id -i ~/.ssh/id_rsa.pub root@192.168.1.222

# Or use the auditor:
./scripts/ssh-auditor.sh --install-keys
```

### Problem: "Connection refused" or "No route to host"

The SSH daemon isn't running or firewall is blocking port 22.

```bash
# Check if port 22 is reachable:
nc -zv 192.168.1.222 22

# If not reachable — access via KVM console or physical keyboard:
sudo systemctl enable --now sshd           # start SSH daemon
sudo ufw allow 22/tcp                      # Ubuntu/Debian
sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload  # Fedora/RHEL
```

### Problem: "Host key verification failed"

Old or mismatched host key in known_hosts.

```bash
# Remove the old key:
ssh-keygen -R 192.168.1.222

# Or add StrictHostKeyChecking=no (auditor does this automatically):
ssh -o StrictHostKeyChecking=no root@192.168.1.222
```

### Problem: Unraid SSH not working

Unraid disables SSH by default.

```
Unraid GUI → Settings → Management Access → SSH → Enable → Apply
```

Then from your local machine:
```bash
ssh-copy-id -i ~/.ssh/id_rsa.pub root@192.168.1.222
```

### Problem: SSH works locally but not via script

Usually a PATH or environment issue. Test with:

```bash
ssh -o BatchMode=yes root@192.168.1.222 'docker ps'
```

---

## 10. Firewall Reference

### Ubuntu/Debian (ufw)

```bash
# Check status
sudo ufw status numbered

# Allow ports for Portainer
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow 9000/tcp comment 'Portainer HTTP'
sudo ufw allow 9443/tcp comment 'Portainer HTTPS'
sudo ufw allow 8000/tcp comment 'Portainer Agent'

# Apply
sudo ufw --force enable
```

### Fedora/RHEL/Unraid (firewalld)

```bash
# Check status
sudo firewall-cmd --state
sudo firewall-cmd --list-all

# Allow ports
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-port=9000/tcp
sudo firewall-cmd --permanent --add-port=9443/tcp
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-ports
```

### Auto-fix via auditor

```bash
# Run auditor with --fix-firewall to apply rules automatically:
./scripts/ssh-auditor.sh --fix-firewall
```

---

## 11. Tailscale Setup

Use Tailscale when nodes are on different networks, behind NAT, or when
LAN SSH keeps failing and you need a reliable fallback.

### 11.1 Install Tailscale on each node

```bash
# Linux (all distros):
curl -fsSL https://tailscale.com/install.sh | sh

# Connect to your Tailscale account:
sudo tailscale up
# Follow the browser link to authenticate
```

### 11.2 Find Tailscale IPs

```bash
tailscale status
# Output shows each device with its 100.x.x.x IP address
```

### 11.3 Add Tailscale IPs to inventory

```bash
# config/node-inventory.env:
NODE_A_TS_IP=100.64.0.5
NODE_B_TS_IP=100.64.0.12
NODE_C_TS_IP=100.64.0.18
```

### 11.4 Re-run auditor

```bash
./scripts/ssh-auditor.sh
```

The auditor tries LAN SSH first. If that fails, it automatically tries the
Tailscale IP. The best working route is saved to the connection map.

### 11.5 Subnet routing (access whole LAN via Tailscale)

If you want all homelab devices accessible via Tailscale (not just Tailscale
nodes), enable subnet routing on one node:

```bash
# On your "hub" node (e.g., Node B):
sudo tailscale up --advertise-routes=192.168.1.0/24

# In Tailscale admin console → approve the subnet route
```

---

## 12. Uninstall / Reset

### Remove Portainer from a node

```bash
# Via SSH to the node:
docker stop portainer && docker rm portainer

# To also delete all Portainer data (stacks, users, settings):
docker volume rm portainer_data
```

### Reset Portainer admin password

If you've forgotten the password:

```bash
# On the node via SSH:
docker stop portainer
docker run --rm \
  -v portainer_data:/data \
  portainer/helper-reset-password
# Note the new temporary password from the output
docker start portainer
# Log in with admin / <new-temp-password>, then change it
```

### Full cleanup (remove Docker + Portainer)

```bash
# Stop and remove all containers:
docker stop $(docker ps -aq) 2>/dev/null; docker rm $(docker ps -aq) 2>/dev/null

# Remove Portainer data:
docker volume rm portainer_data 2>/dev/null

# Remove Portainer image:
docker rmi portainer/portainer-ce 2>/dev/null
```

---

## Cheat Sheet

```bash
# === Initial Setup ===
cp config/node-inventory.env.example config/node-inventory.env
nano config/node-inventory.env        # set IPs, SSH users

# === SSH Auditor ===
./scripts/ssh-auditor.sh              # full audit
./scripts/ssh-auditor.sh --fix-firewall  # open ports automatically
./scripts/ssh-auditor.sh --install-keys  # push SSH keys (prompts passwords)
./scripts/ssh-auditor.sh --node NODE_B   # audit one node
./scripts/ssh-auditor.sh --report     # show last report

# === Portainer Install ===
./scripts/portainer-install.sh        # install on all reachable nodes
./scripts/portainer-install.sh --status   # HTTP check all Portainer URLs
./scripts/portainer-install.sh --update   # pull latest image
./scripts/portainer-install.sh --force    # reinstall from scratch
./scripts/portainer-install.sh --node NODE_C   # one node only

# === Application Deploy ===
./scripts/deploy-all.sh               # deploy full stack (uses Portainer API)
./scripts/deploy-all.sh status        # health check all services
./scripts/preflight-check.sh          # validate everything pre-deploy

# === Portainer API ===
curl http://192.168.1.222:9000/api/status   # check Portainer is up
curl -H "X-API-Key: $PORTAINER_TOKEN" \
     http://192.168.1.222:9000/api/stacks   # list stacks

# === Recovery ===
docker restart portainer              # fix timeout on first login
docker logs portainer --tail 50       # debug issues
./scripts/portainer-install.sh --force   # full reinstall
```
