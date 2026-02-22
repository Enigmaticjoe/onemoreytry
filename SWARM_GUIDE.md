# Docker Swarm + Portainer Business Edition Guide

> Portainer BE turns every node into a managed environment visible from
> one central dashboard. Docker Swarm adds clustering, service scheduling,
> and GPU-aware placement across your whole homelab.

---

## Quick Start (assumes Portainer already installed)

```bash
# Install Portainer BE on all nodes (skip if already done):
./scripts/portainer-install.sh --business

# Initialize Swarm and connect all nodes:
./scripts/swarm-init.sh

# Open Portainer BE central admin:
http://192.168.1.222:9000   # (or your SWARM_MANAGER_NODE IP)
```

---

## Table of Contents

1. [Portainer CE vs BE — What Changes](#1-portainer-ce-vs-be--what-changes)
2. [Architecture with Swarm](#2-architecture-with-swarm)
3. [Step-by-Step: Install Portainer BE](#3-step-by-step-install-portainer-be)
4. [Step-by-Step: Initialize Swarm](#4-step-by-step-initialize-swarm)
5. [Node Labels & GPU Placement](#5-node-labels--gpu-placement)
6. [Central Admin in Portainer BE](#6-central-admin-in-portainer-be)
7. [Deploying Swarm Stacks](#7-deploying-swarm-stacks)
8. [Swarm Stack Reference](#8-swarm-stack-reference)
9. [GPU Services in Swarm](#9-gpu-services-in-swarm)
10. [Portainer BE Features Reference](#10-portainer-be-features-reference)
11. [Swarm Operations Cheat Sheet](#11-swarm-operations-cheat-sheet)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Portainer CE vs BE — What Changes

| Feature | CE (free) | BE (licensed) |
|---------|-----------|---------------|
| Manage local Docker | ✅ | ✅ |
| Multiple environments in one UI | ❌ | ✅ |
| Docker Swarm management | Limited | ✅ Full |
| Role-Based Access Control (RBAC) | ❌ | ✅ |
| GitOps / automatic stack updates | ❌ | ✅ |
| Registry management | ❌ | ✅ |
| Edge agents (remote/air-gapped) | ❌ | ✅ |
| Nomad support | ❌ | ✅ |
| Image: | `portainer-ce` | `portainer-ee` |

**Key difference for your homelab:** With BE, you log into ONE Portainer
and see ALL nodes — containers, stacks, volumes, logs — without switching
browser tabs or SSH sessions.

---

## 2. Architecture with Swarm

```
Browser → Portainer BE (NODE_B :9000)
              │
              ├── Swarm Environment (clustered nodes)
              │     ├── NODE_B (Swarm manager + gateway)
              │     │     ├── litellm          [placement: homelab.node=B]
              │     │     ├── deploy-gui        [placement: homelab.node=B]
              │     │     └── openclaw          [placement: homelab.node=B]
              │     ├── NODE_A (Swarm worker — AMD RX 7900 XT)
              │     │     └── vllm-brain        [placement: gpu=amd]
              │     └── NODE_C (Swarm worker — Intel Arc A770)
              │           └── ollama-vision     [placement: gpu=intel]
              │
              ├── NODE_D Standalone Environment (Home Assistant)
              │     └── Managed via Portainer Agent :9001
              │
              └── NODE_E Standalone Environment (NVR)
                    └── Managed via Portainer Agent :9001

Portainer Agent (global Swarm service → runs on EVERY Swarm node)
  port 9001 — used by Portainer BE to see containers on each node
```

**Why some nodes are "standalone" and some "Swarm":**
- GPU inference nodes (A, C) benefit from Swarm's placement constraints
- Utility nodes (D: Home Assistant, E: NVR) are simpler as standalones
- All environments appear in the same Portainer BE dashboard

---

## 3. Step-by-Step: Install Portainer BE

### 3.1 Run the auditor first (if not done)

```bash
./scripts/ssh-auditor.sh
```

### 3.2 Install Portainer BE on all nodes

```bash
./scripts/portainer-install.sh --business
```

This installs `portainer/portainer-ee:latest` on every reachable node.
If Portainer CE is already running, use `--force` to replace it:

```bash
./scripts/portainer-install.sh --business --force
```

### 3.3 Apply your license key

1. Open Portainer on the manager node:  `http://<NODE_B_IP>:9000`
2. Create admin account (first time only)
3. Go to **Settings** → **Licenses** → **Add License**
4. Paste your BE license key

> The license unlocks multi-environment management, RBAC, GitOps, etc.
> Without the license, Portainer BE runs as CE (still works, just limited).

---

## 4. Step-by-Step: Initialize Swarm

### 4.1 Run the Swarm init script

```bash
./scripts/swarm-init.sh
```

**What this does:**
1. Upgrades the manager node to Portainer BE (if not already BE)
2. Runs `docker swarm init` on the manager (NODE_B by default)
3. Joins all reachable nodes as Swarm workers
4. Applies GPU and role labels to each node
5. Deploys Portainer Agent as a **global service** (runs on every Swarm node)
6. Installs standalone Portainer Agent on non-Swarm nodes

### 4.2 Choose a different manager (optional)

```bash
./scripts/swarm-init.sh --manager NODE_A
```

Or set in `config/node-inventory.env`:
```bash
SWARM_MANAGER_NODE=NODE_A
```

### 4.3 Join workers only (if manager already initialized)

```bash
./scripts/swarm-init.sh --workers-only
```

### 4.4 Re-apply labels only

```bash
./scripts/swarm-init.sh --labels-only
```

### 4.5 Check Swarm status

```bash
./scripts/swarm-init.sh --status
# or directly:
ssh root@192.168.1.222 docker node ls
```

---

## 5. Node Labels & GPU Placement

Labels are key-value tags on each Swarm node. Services use placement
constraints to target specific hardware.

### Labels applied by swarm-init.sh

| Node | Labels |
|------|--------|
| NODE_A | `gpu=amd` `gpu.model=rx7900xt` `vram=20g` `role=inference` `homelab.node=A` |
| NODE_B | `gpu=nvidia` `gpu.model=rtx4070` `vram=12g` `role=gateway` `role.unraid=true` `homelab.node=B` |
| NODE_C | `gpu=intel` `gpu.model=arc-a770` `vram=16g` `role=inference` `role.vision=true` `homelab.node=C` |
| NODE_D | `role=automation` `homelab.node=D` |
| NODE_E | `role=nvr` `homelab.node=E` |

### Using labels in stack files

```yaml
deploy:
  placement:
    constraints:
      # Target NODE_C (Intel Arc A770 vision AI)
      - node.labels.gpu == intel

      # Or target by exact node:
      - node.labels.homelab.node == C

      # Or by role:
      - node.labels.role == inference

      # Or only Unraid (NODE_B):
      - node.labels.role.unraid == true
```

### View labels on all nodes

```bash
# Quick view:
./scripts/swarm-init.sh --status

# Full labels:
docker node ls -q | xargs -I{} docker node inspect {} \
  --format '{{.Description.Hostname}}: {{range $k,$v := .Spec.Labels}}{{$k}}={{$v}} {{end}}'

# Or use the helper script (run on manager):
bash swarm/node-labels.sh view
```

### Add a custom label

```bash
# Get node ID first:
docker node ls

# Apply:
docker node update --label-add myapp.role=primary <node-id>
```

---

## 6. Central Admin in Portainer BE

After `swarm-init.sh` completes, add your environments to Portainer BE:

### 6.1 Add the Swarm environment

1. Open Portainer → **Home** → **Add environment**
2. Choose: **Docker Swarm**
3. Choose: **Portainer Agent**
4. Enter details:
   - **Name:** `Homelab Swarm`
   - **Agent URL:** `tasks.agent:9001`
     *(The agent Swarm service resolves via DNS inside the overlay network)*
5. Click **Connect**

You now see the Swarm as one environment with all nodes visible.

### 6.2 Add standalone environments

For nodes NOT in the Swarm (NODE_D, NODE_E):

1. **Home** → **Add environment** → **Docker Standalone** → **Agent**
2. NODE_D:
   - Name: `Node D — Home Assistant`
   - Agent URL: `192.168.1.149:9001`
3. NODE_E:
   - Name: `Node E — Sentinel`
   - Agent URL: `192.168.1.116:9001`

### 6.3 Navigating environments

- **Home** page lists all environments with their status at a glance
- Click any environment name to switch into it
- The top nav shows which environment you're currently viewing
- **Stacks, containers, volumes** are all scoped to the selected environment

---

## 7. Deploying Swarm Stacks

### 7.1 Via Portainer BE (recommended)

1. Select the **Homelab Swarm** environment
2. Click **Stacks** → **Add stack**
3. Choose one of:
   - **Web editor** — paste the YAML directly
   - **Upload** — upload a file from `swarm/` directory
   - **Repository** — point to a Git repo for GitOps (BE feature)
4. Add any environment variables in the **Environment variables** section
5. Click **Deploy the stack**

### 7.2 Via CLI (on manager node)

```bash
# Deploy LiteLLM stack:
docker stack deploy -c swarm/litellm-swarm.yml litellm

# Deploy OpenClaw:
docker stack deploy -c swarm/openclaw-swarm.yml openclaw

# Deploy Portainer Agent (global, all nodes):
docker stack deploy -c swarm/portainer-agent-stack.yml portainer_agent_stack

# List all running stacks:
docker stack ls

# List services in a stack:
docker stack services litellm

# See where each task is running:
docker service ps litellm_litellm
```

### 7.3 Via deploy-all.sh (API-backed)

Set your Portainer API token in `config/node-inventory.env`:
```bash
PORTAINER_TOKEN=ptr_xxxxxxxxxxxx
```

Then the deploy script uses Portainer's REST API:
```bash
./scripts/deploy-all.sh
```

---

## 8. Swarm Stack Reference

All stack files are in the `swarm/` directory:

| File | Service | Node Placement | Notes |
|------|---------|---------------|-------|
| `portainer-agent-stack.yml` | Portainer Agent | ALL nodes | Deploy first |
| `litellm-swarm.yml` | LiteLLM gateway | NODE_B (Unraid) | Requires config.yaml bind |
| `openclaw-swarm.yml` | OpenClaw AI | NODE_B (Unraid) | Set env vars for HA/tokens |
| `deploy-gui-swarm.yml` | Deploy GUI | NODE_B (Unraid) | SSH key bind mount |
| `node-labels.sh` | — | Run on manager | Apply/view/remove labels |

### Environment variables for Swarm stacks

Add secrets and config in **Portainer → Stack → Environment variables** (never
commit them to files). Key variables for OpenClaw:

```
ANTHROPIC_API_KEY=sk-ant-...
HA_TOKEN=eyJ...
LITELLM_API_KEY=sk-master-key
KVM_OPERATOR_TOKEN=...
OPENCLAW_GATEWAY_TOKEN=...
```

---

## 9. GPU Services in Swarm

Docker Swarm does not natively support NVIDIA Container Toolkit `--gpus` flags.
The recommended approach is **placement constraints + device bind mounts**.

### NVIDIA GPU (NODE_B — RTX 4070)

```yaml
services:
  vllm:
    image: vllm/vllm-openai:latest
    devices:
      - /dev/nvidia0:/dev/nvidia0
      - /dev/nvidiactl:/dev/nvidiactl
      - /dev/nvidia-uvm:/dev/nvidia-uvm
    environment:
      NVIDIA_VISIBLE_DEVICES: all
    deploy:
      placement:
        constraints:
          - node.labels.gpu == nvidia
```

### Intel Arc GPU (NODE_C — Arc A770)

```yaml
services:
  ollama:
    image: ollama/ollama:latest
    devices:
      - /dev/dri:/dev/dri
    environment:
      ZES_ENABLE_SYSMAN: "1"
      ONEAPI_DEVICE_SELECTOR: "level_zero:0"
      OLLAMA_NUM_GPU: "999"
    deploy:
      placement:
        constraints:
          - node.labels.gpu == intel
```

### AMD ROCm GPU (NODE_A — RX 7900 XT)

```yaml
services:
  vllm-amd:
    image: vllm/vllm-openai:rocm
    devices:
      - /dev/kfd:/dev/kfd
      - /dev/dri:/dev/dri
    group_add:
      - video
      - render
    environment:
      HIP_VISIBLE_DEVICES: "0"
      ROCR_VISIBLE_DEVICES: "0"
    deploy:
      placement:
        constraints:
          - node.labels.gpu == amd
```

> **Note on GPU services:** GPU-intensive services (Ollama, vLLM) often
> work best as **standalone containers** managed via standalone Portainer
> environments, rather than Swarm services. This avoids bind-mount
> complexity and lets you use `host` network mode for lower latency.
> Use Swarm for stateless services (LiteLLM, Deploy GUI, OpenClaw).

---

## 10. Portainer BE Features Reference

### GitOps (auto-deploy from Git)

In Portainer → Stacks → Add stack → **Repository**:
- Point to your Git repo and branch
- Set webhook for auto-deploy on push
- Portainer pulls and redeploys on schedule or webhook trigger

### RBAC (Role-Based Access Control)

1. **Settings → Users** → create users
2. **Settings → Teams** → group users
3. **Environments → Access** → assign team access per environment
4. Roles: Administrator, Operator, Helpdesk, Standard User, Read-only

### Registry Management

1. **Registries** → Add registry (Docker Hub, GHCR, private)
2. Portainer caches credentials — containers can pull without re-auth
3. Useful for private images and rate-limit management

### Webhooks for CI/CD

1. Open a stack in Portainer
2. Stack details → **Webhook** → copy the URL
3. Trigger from GitHub Actions, Gitea, or any CI:
   ```bash
   curl -X POST "https://portainer.yourhost.com/api/webhooks/<id>"
   ```

---

## 11. Swarm Operations Cheat Sheet

```bash
# === Swarm Management (run on manager node) ===

# Node status
docker node ls
docker node inspect <node-id> --pretty

# Promote a worker to manager
docker node promote <node-id>

# Drain a node (move all services off before maintenance)
docker node update --availability drain <node-id>
# Bring back:
docker node update --availability active <node-id>

# Remove a node (leave swarm first on the node):
#   On the node:  docker swarm leave
#   On manager:   docker node rm <node-id>

# === Service / Stack Management ===

# List all stacks and services
docker stack ls
docker service ls

# Scale a service
docker service scale litellm_litellm=2

# Rolling update (pull new image)
docker service update --image ghcr.io/berriai/litellm:main-latest litellm_litellm

# Force restart (rolling)
docker service update --force litellm_litellm

# Service logs
docker service logs litellm_litellm --follow --tail 50

# Where are tasks running?
docker service ps litellm_litellm --no-trunc

# === Labels ===

# Add label
docker node update --label-add key=value <node-id>

# Remove label
docker node update --label-rm key <node-id>

# View labels
bash swarm/node-labels.sh view

# === From your workstation (via scripts) ===

./scripts/swarm-init.sh --status   # Swarm + Portainer status
./scripts/swarm-init.sh --leave    # safely leave Swarm (confirms first)
```

---

## 12. Troubleshooting

### Swarm nodes stuck in "Down" state

```bash
# Check if Docker is running on the node:
ssh root@<node-ip> systemctl status docker

# Restart Docker:
ssh root@<node-ip> systemctl restart docker

# Re-join if needed (get token from manager first):
ssh root@192.168.1.222 docker swarm join-token worker
ssh root@<node-ip> docker swarm join --token <token> 192.168.1.222:2377
```

### Portainer Agent not showing in Portainer

```bash
# Check the agent is running (Swarm service):
ssh root@192.168.1.222 docker service ls | grep agent
ssh root@192.168.1.222 docker service ps portainer_agent_stack_agent

# Check agent port is open:
curl http://192.168.1.222:9001/ping

# Redeploy agent stack:
ssh root@192.168.1.222 \
  docker stack deploy -c /tmp/portainer-agent-stack.yml portainer_agent_stack
```

### Services not starting on expected node

```bash
# Check labels are applied:
bash swarm/node-labels.sh view

# Check service placement constraint matches:
docker service inspect <service-name> --format '{{json .Spec.TaskTemplate.Placement}}'

# Check node availability:
docker node ls

# Force reschedule:
docker service update --force <service-name>
```

### Portainer BE shows "No license" after restart

```bash
# License is stored in portainer_data volume — if volume was deleted, re-apply:
# Portainer → Settings → Licenses → Add License
```

### Port 2377 blocked (Swarm node can't join)

Swarm requires port 2377 (TCP) open between all nodes.

```bash
# On manager node (ufw):
sudo ufw allow 2377/tcp comment 'Docker Swarm manager'
sudo ufw allow 7946/tcp comment 'Docker Swarm node comms'
sudo ufw allow 7946/udp comment 'Docker Swarm node comms'
sudo ufw allow 4789/udp comment 'Docker Swarm overlay'

# Firewalld:
sudo firewall-cmd --permanent --add-port=2377/tcp
sudo firewall-cmd --permanent --add-port=7946/tcp
sudo firewall-cmd --permanent --add-port=7946/udp
sudo firewall-cmd --permanent --add-port=4789/udp
sudo firewall-cmd --reload

# Or use the auditor with --fix-firewall (opens SSH + Portainer ports,
# you'll need to add Swarm ports manually as shown above)
```

### "host" network mode not working in Swarm

Swarm services with `network_mode: host` only work with `replicas: 1` and
`--net host` is not supported via Compose `networks:` in Swarm mode.

**Solution:** Use placement constraints to pin to one node and use port
mapping instead:

```yaml
services:
  ollama:
    ports:
      - "11434:11434"    # instead of network_mode: host
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.labels.gpu == intel
```
