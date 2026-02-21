# OpenClaw Installation & KVM Integration Guidebook

This guide walks you through installing OpenClaw on Unraid (Node B), wiring it to the
AI KVM Operator, and connecting the rest of your lab ecosystem (vLLM, Ollama, Home
Assistant, SearXNG, Open WebUI).

---

## 1. What Is OpenClaw?

OpenClaw is a self-hosted AI personal assistant that runs as a single Docker container.
It provides:

- A **web Control UI** at `http://<UNRAID_IP>:18789/?token=<GATEWAY_TOKEN>`
- An **OpenAI-compatible API** (`POST /v1/chat/completions`) for Open WebUI and other clients
- **Webhook endpoints** (`POST /hooks/agent`) for automation from Unraid User Scripts,
  Home Assistant, and any HTTP client
- **Skills** — Markdown files that extend what agents can do (KVM control, deployment, etc.)
- Built-in connectors for local models (vLLM, Ollama) and cloud providers
  (Anthropic, OpenAI, Google, OpenRouter, and more)

---

## 2. Prerequisites

| Requirement | Notes |
|---|---|
| Unraid 6.12+ (Node B) | Where the container runs |
| Portainer CE installed | Optional but recommended for stack management |
| `hf-vllm` container on port 8880 | Primary local model — any OpenAI-compat server works |
| KVM Operator deployed (port 5000) | See `docs/04_DEPLOY_KVM_OPERATOR.md` |
| `openssl` available on Unraid | For token generation |

---

## 3. Step 1 — Prepare Data Directories

SSH into Unraid and create the three persistent data directories:

```bash
mkdir -p /mnt/user/appdata/openclaw/config
mkdir -p /mnt/user/appdata/openclaw/workspace
mkdir -p /mnt/user/appdata/openclaw/homebrew
```

---

## 4. Step 2 — Configure `openclaw.json`

Copy the example config from this repository and set your local model ID:

```bash
# Copy the example config from the cloned repository (~/homelab)
cp ~/homelab/openclaw/openclaw.json \
   /mnt/user/appdata/openclaw/config/openclaw.json

# Verify vLLM is running first, then find the model ID it is serving
# (replace localhost with the vLLM container IP if needed)
curl -fsS http://localhost:8880/v1/models | jq '.data[].id'
# Example output: "meta-llama/Meta-Llama-3-8B-Instruct"

# Edit the config and replace every "your-model-id-here" with the actual ID
nano /mnt/user/appdata/openclaw/config/openclaw.json
```

Key fields to review in `openclaw.json`:

| Field | What to change |
|---|---|
| `agents.defaults.model.primary` | `"vllm/<your-actual-model-id>"` |
| `models.providers.vllm.models[0].id` | same model ID |
| `models.providers.vllm.models[0].contextWindow` | match your vLLM `--max-model-len` |
| `tools.searxng.baseUrl` | `"http://host.docker.internal:8082"` (default) |
| `tools.browser.wsEndpoint` | `"ws://host.docker.internal:3005"` if you have browserless |

> **Hot-reload:** All `openclaw.json` changes except `gateway.*` apply without a
> container restart. Gateway bind/port changes require a restart.

---

## 5. Step 3 — Generate Tokens

Generate a gateway token (used to access the Control UI and API):

```bash
openssl rand -hex 24
# Example: a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6
```

If you do not already have a KVM Operator token, generate one now and set it in
the KVM Operator's `.env` file (see `docs/04_DEPLOY_KVM_OPERATOR.md`).

---

## 6. Step 4 — Create the Environment File

Create `/mnt/user/appdata/openclaw/.env`:

```bash
# ── Required ────────────────────────────────────────────────────────────────
OPENCLAW_GATEWAY_TOKEN=<token from Step 3>

# ── Local AI (vLLM on port 8880) ────────────────────────────────────────────
VLLM_API_KEY=vllm-local        # any non-empty value activates the provider

# ── KVM Operator (required for KVM control) ─────────────────────────────────
KVM_OPERATOR_URL=http://192.168.1.9:5000
KVM_OPERATOR_TOKEN=<token from kvm-operator/.env>

# ── Cloud AI fallbacks (optional) ───────────────────────────────────────────
# ANTHROPIC_API_KEY=sk-ant-...
# OPENAI_API_KEY=sk-...
# GEMINI_API_KEY=...
# OPENROUTER_API_KEY=...
# GROQ_API_KEY=...

# ── Home Assistant (optional) ───────────────────────────────────────────────
# HOME_ASSISTANT_URL=http://192.168.1.149:8123
# HOME_ASSISTANT_TOKEN=<HA long-lived access token>

# ── Unraid server control (optional) ────────────────────────────────────────
# UNRAID_API_KEY=<from Unraid Settings → Management Access → API Keys>

# ── Messaging (optional) ────────────────────────────────────────────────────
# TELEGRAM_BOT_TOKEN=...
# DISCORD_BOT_TOKEN=...
```

---

## 7. Step 5 — Deploy the Container

### Option A — Portainer (recommended)

1. Open Portainer: `http://<NODE_B_IP>:9000`
2. Go to **Stacks → Add Stack → Upload**
3. Upload `openclaw/docker-compose.yml` from this repository
4. Expand **Environment variables** and paste in the contents of your `.env` file
5. Click **Deploy the stack**

### Option B — Docker Compose CLI (SSH into Unraid)

```bash
# The repository is assumed to be at ~/homelab on the Unraid host.
# docker-compose.yml lives in openclaw/ inside that repo.
cd ~/homelab/openclaw
docker compose --env-file /mnt/user/appdata/openclaw/.env up -d
```

### Option C — Minimal one-liner (no openclaw.json pre-written)

```bash
docker run -d \
  --name openclaw-gateway \
  --restart unless-stopped \
  -p 18789:18789 \
  -e OPENCLAW_GATEWAY_TOKEN=<your-token> \
  -e VLLM_API_KEY=vllm-local \
  -v /mnt/user/appdata/openclaw/config:/root/.openclaw \
  -v /mnt/user/appdata/openclaw/workspace:/home/node/clawd \
  --add-host=host.docker.internal:host-gateway \
  ghcr.io/openclaw/openclaw:latest \
  sh -c 'node dist/index.js gateway --bind lan'
```

---

## 8. Step 6 — First-Time Verification

Wait about 45 seconds for the container to start, then verify:

```bash
# Health check
curl -fsS http://localhost:18789/

# Open the Control UI in your browser
# http://<UNRAID_IP>:18789/?token=<OPENCLAW_GATEWAY_TOKEN>
```

Inside the container console (Portainer → openclaw-gateway → Console, or
`docker exec -it openclaw-gateway sh`):

```bash
# List all detected models
node dist/index.js models list
# → "vllm/your-model-id" should appear under "vllm" provider

# If your device pairing shows error 1008, approve the Control UI device:
node dist/index.js devices list
node dist/index.js devices approve <DEVICE_ID>
```

---

## 9. Step 7 — Install the KVM Skill

The KVM skill teaches OpenClaw how to call the KVM Operator API.

```bash
# On Unraid, copy skill files into the OpenClaw workspace
# (assumes the repository is cloned to ~/homelab)
cp ~/homelab/openclaw/skill-kvm.md \
   /mnt/user/appdata/openclaw/workspace/skill-kvm.md

cp ~/homelab/openclaw/skill-deploy.md \
   /mnt/user/appdata/openclaw/workspace/skill-deploy.md

# Create AGENTS.md so the agent loads the skills automatically
cat > /mnt/user/appdata/openclaw/workspace/AGENTS.md <<'EOF'
# OpenClaw Agent Context

You are an AI assistant managing a multi-node home AI lab.

Read these skill files to understand your capabilities:
- skill-kvm.md      — KVM-over-IP control via NanoKVM Cube + kvm-operator service
- skill-deploy.md   — Docker stack deployment via Portainer and SSH
EOF
```

No container restart is required — changes to the workspace are picked up on the next
conversation turn.

---

## 10. Step 8 — Connect Open WebUI to OpenClaw

If you run `hf-openwebui` (port 3002) and want to chat through it:

1. Open WebUI → **Settings → Connections**
2. Click **Add OpenAI-compatible API**
3. Fill in:
   - **URL:** `http://<UNRAID_IP>:18789/v1`
   - **API Key:** `<OPENCLAW_GATEWAY_TOKEN>`
4. **Save** and select **openclaw:main** (or **agent:main**) as the model

Ensure the `http.endpoints.chatCompletions` block is `enabled: true` in your
`openclaw.json` (it is by default).

---

## 11. KVM Integration — How It Works

```
OpenClaw Control UI / API / Webhook
        │
        │  HTTPS/HTTP  Bearer <OPENCLAW_GATEWAY_TOKEN>
        ▼
   OpenClaw Gateway (Node B :18789)
        │
        │  HTTP  Bearer <KVM_OPERATOR_TOKEN>
        ▼
   KVM Operator — FastAPI (Node A :5000)
        │
        │  HTTP  NanoKVM REST API
        ▼
   NanoKVM Cube hardware
        │
        │  HDMI + USB
        ▼
   Target machine (Node C, Node B, any physical host)
```

### Safety gates

| Path | Approval required? |
|---|---|
| Read (`/kvm/snapshot`, `/kvm/status`, `/kvm/power` GET) | **No** — instant |
| Write (`/kvm/power` POST, `/kvm/keyboard`, `/kvm/mouse`, `/kvm/task`) | **Yes** — held until you approve when `REQUIRE_APPROVAL=true` |

Keep `REQUIRE_APPROVAL=true` (the default) for routine operation. Only disable it for
well-tested, fully automated pipelines.

---

## 12. KVM Integration — Example Prompts

Paste these into the OpenClaw chat UI (or send via webhook / API):

```
"Is node-c powered on? Take a screenshot and tell me what's on screen."

"node-c looks frozen. Reset it and verify it boots successfully."

"Log into node-c over KVM, open a terminal, and run: docker ps -a"

"Use KVM to deploy the latest homelab stack on node-c:
 cd ~/homelab/node-c-arc && docker compose pull && docker compose up -d"

"Check array health and disk temperatures on Node B, then send me a summary."
```

---

## 13. Webhook Automation

Trigger OpenClaw from any HTTP client without opening the chat UI:

```bash
# From a cron job or Unraid User Scripts
curl -s -X POST http://<UNRAID_IP>:18789/hooks/agent \
  -H "Authorization: Bearer $OPENCLAW_GATEWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message":"Run the preflight health check and report any failures."}'
```

Home Assistant `rest_command` (add to `configuration.yaml`):

```yaml
rest_command:
  ask_openclaw:
    url: "http://192.168.1.222:18789/hooks/agent"
    method: POST
    headers:
      Authorization: "Bearer {{ openclaw_token }}"
      Content-Type: "application/json"
    payload: '{"message":"{{ message }}"}'
```

---

## 14. Ecosystem Integration Summary

| Service | How OpenClaw connects | Port |
|---|---|---|
| vLLM (hf-vllm) | `openclaw.json` `models.providers.vllm` | 8880 |
| Ollama (Node C) | `openclaw.json` `models.providers.ollama` | 11434 |
| SearXNG (hf-searxng) | `openclaw.json` `tools.searxng` | 8082 |
| Browserless | `openclaw.json` `tools.browser.wsEndpoint` | 3005 |
| Open WebUI | Add `http://<IP>:18789/v1` as an OpenAI API | 3002 |
| Home Assistant | `HOME_ASSISTANT_URL` + `HOME_ASSISTANT_TOKEN` env vars | 8123 |
| Unraid API | `UNRAID_API_KEY` + `UNRAID_URL` env vars | 80/graphql |
| KVM Operator | `KVM_OPERATOR_URL` + `KVM_OPERATOR_TOKEN` env vars | 5000 |
| Portainer | `skill-deploy.md` `PORTAINER_URL` + `PORTAINER_TOKEN` | 9000 |

---

## 15. Security Hardening

- **Do not expose port 18789 to the internet.** Use Tailscale or a reverse proxy with
  HTTPS and additional auth if you need remote access.
- **Rotate `OPENCLAW_GATEWAY_TOKEN` and `KVM_OPERATOR_TOKEN`** whenever you suspect
  either may have been exposed.
- The container runs as root (required by the official template). Keep the token secret.
- `REQUIRE_APPROVAL=true` is the default for the KVM Operator. Never disable it unless
  you are running a vetted automated pipeline.
- The NanoKVM AES key is hardcoded in firmware (see [NanoKVM GitHub Issue #270](https://github.com/sipeed/NanoKVM/issues/270)). Treat the KVM
  network segment as a trusted LAN-only path.
- The KVM `policy_denylist.txt` blocks destructive commands (`rm -rf /`, `mkfs`, `dd if=`,
  fork bombs, etc.) even in headless mode, but this list is not exhaustive.

---

## 16. Troubleshooting

### OpenClaw does not show vLLM models

```bash
# Confirm vLLM is running and reachable from the container
docker exec openclaw-gateway \
  wget -qO- http://host.docker.internal:8880/v1/models

# If empty or 000 — vLLM container is down or not on port 8880
# Fix: check hf-vllm container, then restart openclaw-gateway

# If you get models but they don't appear in "models list":
# → Update agents.defaults.model.primary in openclaw.json with the actual model ID
```

### Control UI shows 1008 / device not approved

```bash
docker exec -it openclaw-gateway sh
node dist/index.js devices list
node dist/index.js devices approve <DEVICE_ID>
```

### KVM Operator returns 401

- Confirm `KVM_OPERATOR_TOKEN` in OpenClaw's env matches `KVM_OPERATOR_TOKEN` in the
  operator's `.env`
- Restart both services after any token change

### KVM write commands return 202 (pending approval)

This is the expected behaviour when `REQUIRE_APPROVAL=true`. Check the KVM Operator
logs for the pending request and approve it, or set `REQUIRE_APPROVAL=false` in the
operator's `.env` for headless operation.

```bash
# View pending approvals
curl -s http://192.168.1.9:5000/health \
  -H "Authorization: Bearer $KVM_OPERATOR_TOKEN"
```

### Container not starting — check logs

```bash
docker logs openclaw-gateway --tail 50
```

Common causes: missing `OPENCLAW_GATEWAY_TOKEN`, syntax error in `openclaw.json`,
volume path does not exist.

---

## 17. Quick Reference

```
Control UI:    http://<NODE_B_IP>:18789/?token=<OPENCLAW_GATEWAY_TOKEN>
API:           http://<NODE_B_IP>:18789/v1
Webhook:       POST http://<NODE_B_IP>:18789/hooks/agent
Health:        GET  http://<NODE_B_IP>:18789/
KVM Operator:  http://192.168.1.9:5000/health
```

For the full multi-node deployment order and day-to-day operations guide, see
[`GUIDEBOOK.md`](../GUIDEBOOK.md) — especially Chapters 4 (KVM Operator), 5 (OpenClaw),
and 6 (OpenClaw × KVM Integration).
