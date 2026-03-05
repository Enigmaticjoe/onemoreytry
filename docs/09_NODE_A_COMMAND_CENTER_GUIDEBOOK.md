# Node A Central Brain + Command Center Guidebook

> Canonical architecture authority: [`docs/ARCHITECTURE_CANONICAL_2026.md`](ARCHITECTURE_CANONICAL_2026.md).


> **Scope and evidence policy**
>
> This guidebook is based on the current repository state (compose files, config files, and docs) and is designed to avoid guessing. Real network values: Node C=`192.168.1.6`, Home Assistant=`192.168.1.149`, Proxmox=`192.168.1.174`, Brawn/Unraid=`192.168.1.222`, domain=`happystrugglebus.us`.

---

## Page 1 — Executive Introduction

This system is a **multi-node home AI ecosystem** with three major AI service layers:

1. **Node A (Brain):** heavy reasoning model host (`brain-heavy` route)
2. **Node B (Gateway/Brawn):** LiteLLM API router and unified endpoint (`:4000`)
3. **Node C (Command Center/Eyes):** Intel Arc Ollama + UI (`:11434`, `:3000`)

Supporting layers:
- **Node D:** Home Assistant voice integration client
- **Node E:** NVR/Sentinel integration target
- **KVM Operator:** policy-gated hardware/automation control service

The intent of this guide is to turn **Node A into the central brain** while still keeping **Node C as user-facing command center UI**, connected by Node B routing. This document includes:

- A current-state audit
- An optimization and extension plan
- A central command-center frontend workflow
- Hardware and network topology visuals
- Operational playbooks and practical use cases

---

## Page 2 — Current-State Audit (from repository evidence)

### 2.1 Source files reviewed

- `DEPLOYMENT_GUIDE.md`
- `QUICK_REFERENCE.md`
- `node-b-litellm/config.yaml`
- `node-b-litellm/litellm-stack.yml`
- `node-c-arc/docker-compose.yml`
- `home-assistant/configuration.yaml.snippet`
- `kvm-operator/app.py`

### 2.2 Confirmed architecture behaviors

- Node B exposes unified API endpoint at `http://192.168.1.222:4000`
- LiteLLM model aliases include:
  - `brain-heavy` → Node A `192.168.1.9:8000`
  - `brawn-fast` → Node B local fast model `192.168.1.222:8002`
  - `intel-vision` → Node C Ollama `192.168.1.6:11434`
- Node C Compose includes:
  - `ollama` service with Intel Arc-enabling variables
  - `chimera_face` Open WebUI service
- Home Assistant snippet targets Node B `/v1` API endpoint.

### 2.3 Audit findings (action-oriented)

| Area | Current state | Risk/Gap | Optimization |
|---|---|---|---|
| Central observability | Distributed checks, no single control pane | Slow incident triage | Add Node A command-center dashboard with status polling |
| Brain access path | Routed via Node B | Good, but no dedicated operator console | Add built-in chat panel on Node A dashboard |
| Documentation distribution | Multiple docs, no dedicated Node A guidebook | Onboarding complexity | Add one deep guidebook + links from root docs |
| IP address management | Node C=`192.168.1.6`, HA=`192.168.1.149`, Blue Iris=`192.168.1.116`, KVM=`192.168.1.130` | All IPs configured | Node E Sentinel webhook integration next |
| Security defaults | Shared static key in examples | Acceptable for lab, weak for production | Add key rotation and network segmentation guidance |

---

## Page 3 — Node A as Central Brain: Target Role

Node A should coordinate system intelligence in four ways:

1. **Primary reasoning endpoint:** handle complex tasks (`brain-heavy`)
2. **Decision broker:** evaluate whether task should route to fast chat (`brawn-fast`) or vision (`intel-vision`)
3. **Operator console host:** serve command dashboard + health status + chat interface
4. **Policy-aware orchestration:** integrate with the KVM Operator under denylist constraints

### 3.1 Responsibilities split

- **Node A:** planning, complex reasoning, control-plane dashboard
- **Node B:** standardized API ingress, model alias router
- **Node C:** multimodal execution and human-facing web UI
- **Node D/E:** domain clients (voice, video/NVR)

This split preserves performance and allows minimal churn to existing compose deployment artifacts.

---

## Page 4 — Hardware Topology Breakdown

### 4.1 Hardware matrix (from existing docs)

| Node | CPU/RAM summary | Accelerator | Primary duty |
|---|---|---|---|
| Node A | Core Ultra 7 265KF, 128 GB DDR5 | RX 7900 XT 20 GB | Heavy reasoning |
| Node B | i5-13600K, 96 GB DDR5 | RTX 4070 12 GB | Gateway + fast chat |
| Node C | Ryzen 7 7700X, 32 GB | Intel Arc A770 16 GB | Vision + Open WebUI |
| Node D | Ryzen 7 7430U, 32 GB DDR4 | N/A | Home Assistant voice client |
| Node E | i5-13500, 32 GB | N/A | Sentinel/NVR |

### 4.2 Resource planning suggestions

- **Node A memory headroom:** reserve stable model cache and avoid frequent model swaps.
- **Node B gateway resiliency:** keep health checks and restart policy strict.
- **Node C GPU accessibility:** ensure `/dev/dri` mappings and Intel runtime health remain green.

---

## Page 5 — Network Topology (visual)

```text
                           LAN (192.168.1.0/24)

   ┌──────────────────────────────────────────────────────────────────┐
   │                    Node B (192.168.1.222)                       │
   │                    LiteLLM Gateway :4000                        │
   │                                                                  │
   │  Routes:                                                         │
   │   - brain-heavy  -> Node A :8000                                 │
   │   - brawn-fast   -> Node B :8002                                 │
   │   - intel-vision -> Node C :11434                                │
   └───────────────┬───────────────────────────┬──────────────────────┘
                   │                           │
        ┌──────────▼─────────┐       ┌────────▼──────────┐
        │ Node A (Brain)      │       │ Node C (Eyes/UI)  │
        │ 192.168.1.9:8000    │       │ 192.168.1.6       │
        │ Central Reasoning    │       │ Ollama :11434     │
        │ + New Dashboard      │       │ Chimera Face :3000│
        └──────────┬───────────┘       └────────┬──────────┘
                   │                             │
             ┌─────▼─────┐                 ┌─────▼─────┐
             │ Node D     │                 │ Node E     │
             │ Home Asst  │                 │ Sentinel   │
             │ 192.168.1.149│               │ 192.168.1.116│
             └────────────┘                 └────────────┘
```

### 5.1 Port map (minimum required)

| Node | Port | Service |
|---|---|---|
| Node A | 8000 | Brain model endpoint |
| Node B | 4000 | LiteLLM unified endpoint |
| Node B | 8002 | Fast model backend |
| Node C | 11434 | Ollama API |
| Node C | 3000 | Command-center UI |

---

## Page 6 — New Command Center Script (What it adds)

The new file:

- `node-a-command-center/node-a-command-center.js`

Capabilities added:

1. **Dashboard home page (`/`)**
   - Quick links to gateway, UI, deployment docs, and guidebook
2. **Status API (`/api/status`)**
   - Polls fixed services and reports availability + latency
3. **Chat API (`/api/chat`)**
   - Proxies user prompt to LiteLLM using `brain-heavy` default model
   - Keeps API key server-side (not exposed to browser JS)
4. **Security guardrails**
   - Request size limit
   - Message length cap
   - Fixed endpoint checks (not an open SSRF proxy)

### 6.1 Runtime environment variables

| Variable | Default | Purpose |
|---|---|---|
| `COMMAND_CENTER_PORT` | `3099` | Dashboard listener port |
| `LITELLM_BASE_URL` | `http://192.168.1.222:4000` | Unified gateway URL |
| `NODE_C_BASE_URL` | `http://192.168.1.6` | Node C base URL for UI + Ollama status checks |
| `LITELLM_API_KEY` | `sk-master-key` | Gateway auth key |
| `DEFAULT_MODEL` | `brain-heavy` | Chat model alias |
| `REQUEST_TIMEOUT_MS` | `7000` | Upstream request timeout |

---

## Page 7 — Deployment and Validation Runbook

### 7.1 Start the command center

```bash
cd <repository-root>/node-a-command-center
node node-a-command-center.js
```

Open:
- `http://<node-a-ip>:3099/`

### 7.2 Validate core endpoints

```bash
curl -s http://127.0.0.1:3099/api/status | jq
curl -s -X POST http://127.0.0.1:3099/api/chat \
  -H 'content-type: application/json' \
  -d '{"message":"Give me a one-sentence ecosystem health summary."}'
```

### 7.3 Existing repository validation

```bash
cd <repository-root>
./validate.sh
```

### 7.4 Operational SLO example (lab profile)

- Gateway health check success: **>= 99%** over 24h
- Command center `/api/status` response p95: **< 2 sec**
- Chat proxy success rate: **>= 98%** for short prompts

---

## Page 8 — Node A Optimization and Extension Plan

### 8.1 Performance optimization checklist

- [ ] Pin model server process priority on Node A
- [ ] Reserve fixed hugepages only if model framework benefits
- [ ] Keep Node A reasoning workload separate from UI rendering workload
- [ ] Set request timeout budgets based on real latency percentiles
- [ ] Enable structured logs for command-center API requests

### 8.2 Capability extension checklist

- [ ] Add role-based access for dashboard write operations
- [ ] Add per-service custom health probes and degraded states
- [ ] Add audit trail export (`jsonl`) for operations center events
- [ ] Add planner mode that suggests model alias by task type
- [ ] Add Home Assistant webhook actions for accepted automations

### 8.3 Security hardening checklist

- [ ] Replace static API key with environment-injected secret
- [ ] Restrict dashboard exposure by subnet or reverse proxy auth
- [ ] Enable TLS at ingress (Caddy/Nginx/Traefik)
- [ ] Apply outbound egress controls to reduce lateral movement
- [ ] Rotate credentials and validate denylist policy monthly

---

## Page 9 — Sample Use Cases

### Use case 1: Incident triage from one pane

- Operator opens dashboard and refreshes status.
- Sees Node C vision endpoint timeout.
- Uses links to jump directly to Node C UI and recovery runbook.

### Use case 2: Planning + execution split

- User asks chatbot for a multi-step automation plan.
- Node A `brain-heavy` produces plan.
- Operator manually executes approved steps through existing services.

### Use case 3: Voice assistant fallback path

- Node D sends normal requests to Node B.
- During Node B degradation, operator uses Node A dashboard status and chat to continue controlled operation.

### Use case 4: Vision-assisted decision workflow

- User asks for image interpretation path.
- Node A reasoning determines `intel-vision` path should be used.
- Operator validates Node C status and triggers downstream prompt.

### Use case 5: Security audit day

- Review fixed status endpoints and denylist policy.
- Confirm no unrestricted URL fetch paths in command center.
- Rotate key and validate chat endpoint still healthy.

---

## Page 10 — Visual Operations Playbook + Cutover Guide

### 10.1 Service-state legend

```text
[GREEN]   reachable and healthy
[YELLOW]  reachable but slow/degraded
[RED]     unreachable, timeout, or error
```

### 10.2 Operator flowchart

```text
User report -> Open Node A dashboard -> Refresh status
            -> Gateway red? ---- yes -> troubleshoot Node B first
            -> Brain red? ------ yes -> troubleshoot Node A model server
            -> Vision red? ----- yes -> troubleshoot Node C (Ollama/UI)
            -> all green? ------ yes -> reproduce issue with chatbot test prompt
```

### 10.3 Production cutover prerequisites

- Replace placeholder IPs in all configs/docs.
- Confirm all node clocks are NTP-synced.
- Validate service restart policies.
- Add centralized log sink before exposing remote access.
- Confirm at least one tested rollback path per node.

### 10.4 Quick rollback pattern

1. Stop new dashboard process.
2. Continue serving AI traffic via Node B directly.
3. Revert only command-center file/docs commit if needed.
4. Revalidate with `./validate.sh`.

---

## Appendix A — Exact file changes introduced by this update

- Added: `node-a-command-center/node-a-command-center.js`
- Added: `docs/09_NODE_A_COMMAND_CENTER_GUIDEBOOK.md`
- Updated references to include this guidebook and script.

## Appendix B — Reality checks before declaring completion

- [x] Network IPs configured: Node C=`192.168.1.6`, HA=`192.168.1.149`, Proxmox=`192.168.1.174`, Brawn=`192.168.1.222`, Blue Iris=`192.168.1.116`, KVM=`192.168.1.130` (kvm-d829.local)
- [ ] Confirm Node A model server is available at configured endpoint
- [ ] Confirm LiteLLM key and model aliases are valid
- [ ] Confirm operator access controls for dashboard exposure
- [ ] Confirm screenshot evidence for UI baseline after deployment
