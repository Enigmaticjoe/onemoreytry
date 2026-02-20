# Unified Installation + Operations Guidebook (2026)

This document is the operational source for this repository. It is intentionally step-by-step for first-time operators.

## 0) Scope and evidence policy
- This guide is based on the files in this repo and verified local script checks.
- No undocumented assumptions are required: set your own node IPs in `config/node-inventory.env` before deployment.

## 1) Build your node inventory first (required)
1. Copy inventory template:
   ```bash
   cp config/node-inventory.env.example config/node-inventory.env
   ```
2. Edit it and set real values for Node C/D/E, tokens, and any custom ports.
3. This inventory is read by deployment scripts.

---

## 2) Chapter: Node A (Brain / Command Center)
Install on Node A:
1. Node.js 20+
2. Python 3.11+
3. Clone repo
4. Start dashboard:
   ```bash
   node node-a-command-center/node-a-command-center.js
   ```
5. Optional KVM operator service:
   ```bash
   cp kvm-operator/.env.example kvm-operator/.env
   # edit .env
   cd kvm-operator && ./run_dev.sh
   ```

Primary ports:
- 3099 (Node A dashboard)
- 5000 (KVM operator)

---

## 3) Chapter: Node B (Unraid / LiteLLM / OpenClaw / Portainer)
Install sequence on Node B:
1. LiteLLM:
   ```bash
   cd node-b-litellm
   docker compose -f litellm-stack.yml up -d
   ```
2. OpenClaw:
   ```bash
   cd openclaw
   docker compose up -d
   ```
3. Use Portainer for stack lifecycle as needed.

Primary ports:
- 4000 LiteLLM
- 18789 OpenClaw
- 9000 Portainer

---

## 4) Chapter: Node C (Intel Arc / Ollama / Chimera Face)
Install sequence on Node C:
```bash
cd node-c-arc
docker compose up -d
```

Then pull model:
```bash
docker exec ollama_intel_arc ollama pull llava
```

Primary ports:
- 11434 Ollama
- 3000 Open WebUI (Chimera Face)

---

## 5) Chapter: Node D (Home Assistant)
- Merge `home-assistant/configuration.yaml.snippet` into Home Assistant `configuration.yaml`.
- Point it to LiteLLM on Node B (`/v1` endpoint).

---

## 6) Chapter: Node E (Sentinel)
- Start `node-e-sentinel/node-e-sentinel.js` on Node E.
- Set env vars for Node C/Ollama and any camera/NVR endpoints before production.

---

## 7) Chapter: OpenClaw integration
- Config files: `openclaw/docker-compose.yml`, `openclaw/openclaw.json`.
- Skills included:
  - `openclaw/skill-deploy.md`
  - `openclaw/skill-kvm.md`
- Automated installer:
  ```bash
  ./scripts/install-openclaw-deployer.sh
  ```
This script provisions OpenClaw on Node B and wires skill files + generated tokens.

---

## 8) Chapter: KVM integration (where to install)
**Install `kvm-operator` on Node A** (the command center), not on Node B.
Rationale in this repo:
- Node A dashboard and orchestration logic already reference KVM operator at Node A port 5000.
- OpenClaw on Node B consumes KVM over HTTP via `KVM_OPERATOR_URL`.

Install:
```bash
cp kvm-operator/.env.example kvm-operator/.env
# set KVM_TARGETS_JSON + token
cd kvm-operator
./run_dev.sh
```

Health check:
```bash
curl http://<node-a-ip>:5000/health
```

---

## 9) Chapter: Visual deployment GUI (Command Center)
A deploy GUI is included at `deploy-gui/`.

Run it:
```bash
cd deploy-gui
docker compose up -d --build
```

Open:
- `http://<node-a-ip>:9999`

Capabilities included in code:
- Multi-node health/status checks
- Deployment trigger endpoints
- Portainer operation endpoint
- OpenClaw task endpoint
- Persisted GUI settings

---

## 10) Full-sequence deployment command flow
From repo root:
```bash
# 1) validate configs
./validate.sh

# 2) preflight
./scripts/preflight-check.sh

# 3) deploy all
./scripts/deploy-all.sh
```

---

## 11) User Manual (daily operations)
### 11.1 Check health
- Dashboard: `http://<node-a-ip>:3099`
- Deploy GUI: `http://<node-a-ip>:9999`
- LiteLLM: `http://<node-b-ip>:4000/health`
- Ollama: `http://<node-c-ip>:11434/api/version`

### 11.2 Send model request via unified gateway
```bash
curl -X POST http://<node-b-ip>:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-master-key" \
  -H "Content-Type: application/json" \
  -d '{"model":"brain-heavy","messages":[{"role":"user","content":"status"}]}'
```

### 11.3 Restart services
- Local compose stack:
  ```bash
  docker compose restart
  ```
- Full orchestrated flow:
  ```bash
  ./scripts/deploy-all.sh
  ```

### 11.4 Troubleshoot quickly
1. Run `./validate.sh`
2. Run `./scripts/preflight-check.sh --health-only`
3. Check container logs for failing service
4. Verify inventory file has real IPs/tokens

---

## 12) API/token hygiene
- Keep real tokens out of tracked files.
- Use environment files (`config/node-inventory.env`, `kvm-operator/.env`).
- Rotate any token found in plaintext chat/docs after setup.

