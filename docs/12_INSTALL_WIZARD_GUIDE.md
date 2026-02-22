# Chapter 12 — Installation Wizard & Portainer-First Setup Guide

## Overview

The **Installation Wizard** walks you through the complete homelab setup in six steps:

1. **Configure Nodes** — Enter IP addresses and SSH credentials for each node.
2. **SSH Audit** — Automatically tests connectivity, detects firewall issues, and suggests fixes.
3. **Pre-Install Inventory** — Checks what software is already installed on each node.
4. **Install Portainer** — One-click Portainer CE deployment on every node.
5. **Deploy Stacks** — Push all AI services via Portainer or direct Docker Compose.
6. **Verify** — Final health check of every service.

---

## Quick Start

```bash
# 1. Start the Deploy GUI
cd deploy-gui
docker compose up -d --build

# 2. Open the wizard
open http://localhost:9999   # then click 🧙 Setup Wizard tab
```

---

## Why Portainer First?

Portainer gives you a **visual Docker management UI** that makes it easy to:

- Monitor container health without SSHing into each node.
- Manage Docker Compose stacks with a single click (start / stop / update).
- View container logs, resource usage, and environment variables from a browser.
- Roll back or redeploy any service without editing files on the remote machine.

The wizard installs Portainer **before** deploying any application stacks so that all subsequent deployments can be managed through its UI.

---

## Step-by-Step Guide

### Step 1 — Configure Nodes

Enter the LAN IP address and SSH username for each node.  
Use the **Test SSH** button beside each row to verify connectivity before proceeding.

| Node | Default IP | Purpose |
|------|-----------|---------|
| Node A (Brain) | 192.168.1.9 | Command Center Dashboard + KVM Operator |
| Node B (Unraid) | 192.168.1.222 | LiteLLM Gateway + OpenClaw |
| Node C (Intel Arc) | 192.168.1.6 | Ollama + Chimera Face UI |
| Node D (Home Assistant) | 192.168.1.149 | Optional — HA integration |
| Node E (Sentinel) | 192.168.1.116 | Optional — Blue Iris / monitoring |

---

### Step 2 — SSH Audit

The wizard runs `ssh-auditor.sh` behind the scenes for each enabled node and shows:

| Check | What it means |
|-------|--------------|
| ✓ Ping | Host is reachable on the network |
| ✓ Port 22 open | SSH daemon is listening |
| ✓ SSH key auth | Your SSH key is trusted on the remote host |
| ⚠ Port 22 closed | Firewall is blocking SSH |
| ✗ Unreachable | Network/DNS issue or machine is off |

**Automatic fix suggestions** are displayed when a check fails.

#### Common fixes

**Firewall blocking SSH — Ubuntu/Debian (ufw):**
```bash
sudo ufw allow ssh
sudo ufw reload
```

**Firewall blocking SSH — Fedora/CentOS (firewalld):**
```bash
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --reload
```

**No SSH key set up:**
```bash
# From this machine (Node C):
ssh-keygen -t ed25519 -C "homelab"    # if you don't have a key yet
ssh-copy-id root@192.168.1.222        # copy to Node B (Unraid)
ssh-copy-id root@192.168.1.9          # copy to Node A
```

**Use Tailscale when direct SSH is not possible:**
```bash
# Install on each node:
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Get the Tailscale IP:
tailscale ip -4
```

You can also run the auditor standalone:
```bash
./scripts/ssh-auditor.sh               # audit all configured nodes
./scripts/ssh-auditor.sh --auto-fix    # attempt firewall fixes automatically
./scripts/ssh-auditor.sh --json        # machine-readable output
./scripts/ssh-auditor.sh --node 192.168.1.222 --user root   # single node
```

---

### Step 3 — Pre-Install Inventory

The wizard SSH-connects to each reachable node and reports:

- **OS** version (Ubuntu, Fedora, Unraid, etc.)
- **Docker** version
- **Docker Compose** plugin version
- **Portainer** container status (running / stopped / not found)
- **Key containers** — litellm_gateway, ollama_intel_arc, chimera_face, openclaw-gateway
- **Tailscale** IP (if installed)
- **Firewall** type (ufw / firewalld / iptables / none)
- **Node.js** and **Python 3** versions

This lets you see at a glance what needs to be installed before you proceed.

---

### Step 4 — Install Portainer CE

For each reachable node, click **▶ Install Portainer**.  
The wizard will:

1. Verify SSH connectivity.
2. Skip if Portainer is already running.
3. Install Docker CE if not present (Ubuntu/Debian/Fedora/CentOS).
4. Start `portainer/portainer-ce:latest` on port 9000.
5. Display a direct link to the Portainer admin UI.

> **Important**: Open the Portainer UI immediately after install and create an admin password.  
> Portainer will lock itself after 5 minutes if the initial setup is not completed.

You can also run the installer standalone:
```bash
./scripts/portainer-install.sh --ip 192.168.1.222 --user root
./scripts/portainer-install.sh --ip 192.168.1.9   --user root
./scripts/portainer-install.sh --local              # install on this machine
```

---

### Step 5 — Deploy Stacks

Two options:

**Option A — Full automated deploy** (recommended for first-time setup):  
Click **▶ Run Full Deploy** to run `scripts/deploy-all.sh` which deploys every service in sequence.

**Option B — Individual deploys** (for targeted updates):  
Use the per-service buttons to deploy only the service you want.

After Portainer is installed, you can also deploy directly through the Portainer UI:

1. Open `http://<node-ip>:9000`
2. Go to **Stacks** → **Add Stack**
3. Paste or upload the relevant `docker-compose.yml`
4. Click **Deploy the stack**

---

### Step 6 — Verify

The wizard runs a live health check against all configured services and shows:

- Green dot (✓): Service is responding normally.
- Gray dot: Service is not configured or URL is unreachable.
- Red dot (✗): Service is down — check container logs.

View logs for a failing service:
```bash
# On the node where the container runs:
docker logs litellm_gateway --tail 50
docker logs ollama_intel_arc --tail 50

# Or use the Terminal tab in the Deploy GUI
```

---

## Using Portainer for Ongoing Management

After setup, use Portainer for day-to-day operations:

| Task | How |
|------|-----|
| Restart a container | Portainer → Containers → click container → Restart |
| Update a stack | Portainer → Stacks → select stack → Pull & Redeploy |
| View logs | Portainer → Containers → click container → Logs |
| Check resource usage | Portainer → Containers → Stats column |
| Add environment variables | Portainer → Stacks → Edit stack |

You can also manage Portainer stacks from the **📦 Portainer** tab in the Deploy GUI,
which connects to Portainer's REST API using your `PORTAINER_TOKEN` from Settings.

---

## SSH Auditor Reference

```
Usage: ./scripts/ssh-auditor.sh [OPTIONS]

Options:
  --node <IP>       Audit a single IP address (default: all configured nodes)
  --user <USER>     SSH username (default: root)
  --auto-fix        Attempt to fix firewall rules automatically
  --json            Output results as JSON (used by the web wizard)

Checks performed:
  1. ICMP ping
  2. TCP port 22 connectivity
  3. SSH key-based authentication
  4. Tailscale availability
  5. Remote software inventory (docker, portainer, containers, firewall)

Exit codes:
  0  All checks passed
  1  One or more checks failed
```

## Portainer Installer Reference

```
Usage: ./scripts/portainer-install.sh [OPTIONS]

Options:
  --ip <IP>        Target node IP address
  --user <USER>    SSH username (default: root)
  --port <PORT>    Portainer port (default: 9000)
  --local          Install on this machine instead of a remote node
  --json           Output result as JSON

What it does:
  1. Verifies SSH connectivity
  2. Installs Docker CE if not present
  3. Starts Portainer CE (portainer/portainer-ce:latest)
  4. Waits for health check to pass
  5. Prints the admin UI URL

Idempotent: safe to re-run if Portainer is already installed.
```
