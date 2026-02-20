# Homelab Deployment Skill

> Skill ID: `skill-deploy` | File: `openclaw/skill-deploy.md`

Deploy, manage, and monitor all nodes in the Grand Unified AI Home Lab.

## Overview

This skill enables agents to:
1. Check the health of all nodes and services
2. Deploy or restart Docker stacks via SSH
3. Manage Portainer stacks on Node B
4. Run validation and preflight scripts
5. Tail logs from any container
6. Coordinate full-stack deployments in the correct order

## Prerequisites

1. SSH keys configured for all nodes (see GUIDEBOOK.md §0.4)
2. KVM Operator running on Node A (for GUI-based remote actions)
3. Portainer token set (if managing stacks via Portainer API)

## Environment Variables

| Variable | Example | Purpose |
|---|---|---|
| `PORTAINER_URL` | `http://192.168.1.222:9000` | Portainer API base URL |
| `PORTAINER_TOKEN` | `ptr_xxx...` | Portainer API access token |
| `LITELLM_KEY` | `sk-master-key` | LiteLLM API key for health checks |
| `KVM_OPERATOR_URL` | `http://192.168.1.9:5000` | KVM Operator service URL |
| `KVM_OPERATOR_TOKEN` | `abc123...` | KVM Operator bearer token |

## Service Health Endpoints

Check if a service is running by hitting its health endpoint:

```
GET http://192.168.1.222:4000/health           → LiteLLM Gateway
GET http://192.168.1.X:11434/api/version       → Ollama (Node C)
GET http://192.168.1.X:3000                    → Chimera Face UI
GET http://192.168.1.9:3099/api/status         → Node A Dashboard
GET http://192.168.1.9:5000/health             → KVM Operator
GET http://192.168.1.222:18789/                → OpenClaw Gateway
GET http://192.168.1.222:9000/api/status       → Portainer
GET http://localhost:9999/api/status           → Deploy GUI
```

All services return HTTP 200 when healthy.

## Portainer Stack Management API

Base URL: `$PORTAINER_URL/api`
Auth header: `X-API-Key: $PORTAINER_TOKEN`

### List all stacks
```
GET /api/stacks
```
Returns array of stack objects with fields: `Id`, `Name`, `Status` (1=running, 2=stopped).

### Start a stack
```
POST /api/stacks/{id}/start
```

### Stop a stack
```
POST /api/stacks/{id}/stop
```

### Get stack services / containers
```
GET /api/stacks/{id}
```

### Redeploy from git
```
PUT /api/stacks/{id}/git/redeploy
Content-Type: application/json
{"prune": false}
```

### Get container logs
```
GET /api/endpoints/1/docker/containers/{container_id}/logs?stdout=1&stderr=1&tail=100
```

## SSH Deployment Commands

Use `ssh` to run commands on remote nodes. All nodes should have key-based auth configured.

### Deploy Node C (Intel Arc)
```bash
ssh root@192.168.1.X "cd ~/homelab/node-c-arc && docker compose pull && docker compose up -d"
```

### Deploy Node B LiteLLM
```bash
ssh root@192.168.1.222 "cd /mnt/user/appdata/homelab/node-b-litellm && \
  docker compose -f litellm-stack.yml pull && \
  docker compose -f litellm-stack.yml up -d"
```

### Check running containers on any node
```bash
ssh root@192.168.1.222 "docker ps --format 'table {{.Names}}\t{{.Status}}'"
```

### View last 50 lines of a container log
```bash
ssh root@192.168.1.222 "docker logs --tail=50 litellm_gateway"
```

### Restart a specific container
```bash
ssh root@192.168.1.222 "docker restart litellm_gateway"
```

### Pull latest images and recreate
```bash
ssh root@192.168.1.222 "cd /path/to/stack && docker compose pull && docker compose up -d --force-recreate"
```

## Deploy GUI API

The Deploy GUI (port 9999) provides a REST API you can call:

### Check all service statuses
```
GET http://localhost:9999/api/status
```
Returns JSON array of all services with `ok`, `latencyMs`, and `error` fields.

### Trigger a deployment
```
POST http://localhost:9999/api/deploy
Content-Type: application/json

{"target": "nodeC"}
```
Valid targets: `nodeC`, `nodeB`, `openclaw`, `kvmOperator`, `nodeADash`

### Execute SSH command via Deploy GUI
```
POST http://localhost:9999/api/ssh
Content-Type: application/json

{"target": "nodeB", "command": "docker ps -a"}
```

## Full Deployment Workflow

When asked to "deploy the full lab" or "set up everything", follow this order:

1. **Validate config**: Run `cd /homelab && ./validate.sh`
2. **Node C first** (Vision AI — other services depend on it):
   ```bash
   cd /homelab/node-c-arc && docker compose up -d
   # Wait for Ollama: curl http://localhost:11434/api/version
   docker exec ollama_intel_arc ollama pull llava
   ```
3. **Node B LiteLLM** (after Node C is healthy):
   ```bash
   ssh root@192.168.1.222 "cd /mnt/user/appdata/homelab/node-b-litellm && docker compose -f litellm-stack.yml up -d"
   # Wait for health: curl http://192.168.1.222:4000/health
   ```
4. **Node A Dashboard**:
   ```bash
   pkill -f node-a-command-center.js || true
   nohup node /homelab/node-a-command-center/node-a-command-center.js &
   ```
5. **KVM Operator**:
   ```bash
   sudo systemctl restart ai-kvm-operator
   # or: cd /homelab/kvm-operator && ./run_dev.sh
   ```
6. **Deploy GUI**:
   ```bash
   cd /homelab/deploy-gui && docker compose up -d --build
   ```
7. **Verify all**:
   ```bash
   cd /homelab && ./scripts/preflight-check.sh --health-only
   ```

## Troubleshooting Workflows

### Service is down — generic workflow
1. Check if container is running: `docker ps -a | grep <container_name>`
2. If exited: `docker logs <container_name> | tail -20`
3. If missing volume/config: check docker-compose.yml for required files
4. Restart: `docker restart <container_name>`
5. Full recreate: `docker compose up -d --force-recreate`

### LiteLLM returning 503
1. Check backend endpoints in config.yaml are reachable
2. `curl http://192.168.1.9:8000/health` (Node A vLLM)
3. `curl http://192.168.1.X:11434/api/version` (Node C Ollama)
4. Restart LiteLLM: `docker restart litellm_gateway`

### OpenClaw not connecting to vLLM
1. Get current model ID: `curl http://NODE_B_IP:8880/v1/models | jq '.data[].id'`
2. Update openclaw.json: set `agents.defaults.model.primary` to the actual model ID
3. Restart: `docker restart openclaw-gateway`

## Example Prompts

```
"Check the health of all my AI services"
"Restart the litellm_gateway container on Node B"
"Show me the last 20 log lines from openclaw-gateway"
"Deploy Node C — make sure Ollama and llava are running"
"List all Portainer stacks and their status"
"Run the preflight check and tell me if anything is broken"
"Give me a full status report of the homelab"
```
