# Multi-Node “onemoreytry” Topology Translation Into a Deployment-Ready `/la` Repository

## System constraints that drive the implementation

A deployment-ready design for your topology must treat **network mode** and **port semantics** as hard constraints, because they alter what *Compose is allowed to express* and what the Linux host will actually do.

When a service uses **host networking** (`network_mode: host`), **port publishing is invalid** (Compose will reject or the runtime will discard published ports), because the container already shares the host’s network namespace. This is explicitly called out in the Compose spec docs and the Docker host networking docs. citeturn0search0turn5search3

This is particularly relevant to your rules for **entity["company","Unraid","nas os by lime technology"]**, **entity["organization","Home Assistant","open source home automation"]**, and Frigate:
- **Unraid node**: host networking is allowed and commonly used, but you must actively avoid port collisions because *every container binds directly on the Unraid host IP* (and the platform docs warn about this). citeturn4search1turn5search3  
- **Home Assistant node**: host networking is widely used specifically to improve discovery behavior (mDNS/Zeroconf), aligning with your “zero-config auto-discovery” goal. However, containerized mDNS name resolution can still have edge-case limitations depending on underlying OS/image constraints; the Home Assistant project has documented real-world Docker discovery caveats in historical discussions. citeturn4search0turn4search4  
- **Frigate node**: the official docs emphasize bare-metal/Docker performance characteristics (shared memory sizing, ports, etc.). Your explicit “host network to prevent RTSP packet drops” requirement implies prioritizing low overhead and avoiding complex NAT/conntrack paths; in host mode you must not publish ports in Compose, but Frigate will still bind its own listening ports directly on the host IP. citeturn7search0turn5search3  

A second architectural constraint is **Swarm vs Compose**. If Node B is **actually deployed via Swarm** (`docker stack deploy`), then key Compose fields (including `network_mode`) can be ignored or behave differently in “stack” mode, and Swarm uses the routing mesh unless you explicitly bypass it (publish mode `host`). This matters if you ever try to combine Swarm and “host networking assumptions” from your other nodes. citeturn5search0turn5search2  

Finally, the most important AI-plane constraint is that **AMD ROCm GPU containers require specific device mappings and privileges**. The vLLM project’s Docker guidance for ROCm explicitly calls out `/dev/kfd` and `/dev/dri` device access plus related runtime flags to operate correctly. citeturn1search0turn1search1turn1search4  

## Repository reality check for `/la` and what needs to be added

From the `/la` repository metadata, `/la` already contains a significant “Brain/Brawn” baseline, including:
- A Brain stack file (`brain-stack.yml`) and Brain setup scripts (`brain-setup.sh`, ROCm validation scripts). fileciteturn24file0 fileciteturn24file7 fileciteturn24file13  
- A LiteLLM configuration file (`litellm_config.yaml`) consistent with your Node B “AI Gateway” role. fileciteturn25file19  
- Home Assistant configuration snippet(s) already present (`homeassistant-configuration.yaml.snippet`). fileciteturn25file12  
- Existing automation scripts under `scripts/automation/` (e.g., deploy scripts for “brain”). fileciteturn7file9 fileciteturn25file17  
- Documentation and recent work specifically about Brain stack deploy stability (healthcheck start periods for model downloads) in PR context. fileciteturn22file0  

Separately, the files you uploaded include:
- A Node A–style “Brain Project” Compose that already expresses a multi-service AI node (vLLM + OpenWebUI + Qdrant + embeddings + SearXNG + agents). fileciteturn0file1  
- A Node A setup playbook aimed at installing ROCm/Docker/services. fileciteturn0file2  
- A prior deep research draft that references multi-repo evolution and validates the idea that `validate.sh` is intended as a “central test suite” in this ecosystem. fileciteturn0file0  

What is missing to satisfy *your* explicit operating rules and topology is not “more stacks,” but a **single, canonical multi-node deployment surface**:
- `./validate.sh` as the central test suite (your rule), even if other validation scripts exist today. fileciteturn25file2 fileciteturn24file13  
- Idempotent node deploy scripts named `scripts/deploy-node-*.sh` that use `rsync` + `docker compose up -d`, and generate secrets via `openssl rand -hex 24` into `.env` files.  
- A predictable directory convention that makes Node A–E + Unraid deployable without human interpretation (and without hardcoded secrets).  

## Node-by-node service contract and inter-node traffic flows

This section translates your stated topology into **enforceable contracts** (ports, endpoints, environment variables) that `validate.sh` can test.

**Unraid node (192.168.1.222)**
- Runs the media stack (Plex + Riven + Decypharr) with **host networking** and **PUID=99 / PGID=100**, and mounts `/mnt/user/DUMB/downloads` to keep ingest on cache before mover. Your “host networking always” constraint must also imply **no Compose `ports:` blocks** for these services. citeturn0search0turn5search3turn4search1  
- Decypharr must enforce cached-only behavior via your `REQUIRE_CACHED=true` rule (validated structurally by checking env entries).
- Hosts Ollama fallback on port 11434 via host network (meaning the service is reachable at `http://192.168.1.222:11434`). (This is a local rule you defined; the repo should encode it as a default route target in Node B’s gateway config.)

Riven note: Riven’s upstream docs indicate that modern Riven deployments have moved from “symlink-based” patterns to a FUSE virtual filesystem approach (RivenVFS). If your operational requirement remains “symlink generation,” the repo should either pin a compatible Riven version or document the migration implications. citeturn15search1turn15search0  

**Node A (Boss Brain, 192.168.1.9)**
- vLLM must run on ROCm with `/dev/kfd` and `/dev/dri` device mappings and AMD-recommended container flags. citeturn1search0turn1search4  
- OpenWebUI should be configured with a **persistent `WEBUI_SECRET_KEY`** to avoid token decryption failures after restarts; this requirement is explicitly documented by Open WebUI. citeturn6search4turn13view0  
- Open WebUI supports MCP (streamable HTTP) natively from v0.6.31+, and the docs recommend OpenAPI as the more enterprise-stable integration path when possible. This matters because your “minions” can be implemented as hardened OpenAPI tool servers first, then optionally bridged into MCP if needed. citeturn2search1turn10search0  
- KVM operator must listen on **port 5000** and enforce **write-approval gating** (`REQUIRE_APPROVAL=true`). Your chosen hardware (NanoKVM) has an identifiable HTTP API surface (e.g., GPIO power/reset control endpoints) that the operator can wrap. citeturn17search0turn17search3  

**Node B (AI Gateway & Media Expansion)**
- LiteLLM should listen on **port 4000**, and provide an **OpenAI-compatible base URL** for internal callers (e.g., `http://nodeb:4000/v1`). LiteLLM’s docs show standard OpenAI client usage with `base_url="http://0.0.0.0:4000"`, validating your plan to route “OpenAI-style” traffic to multiple backends. citeturn6search5turn6search0  
- If Node B is really Swarm-deployed, publishing behavior differs (routing mesh vs host mode). If you want deterministic “node-local” port binding, you must explicitly bypass routing mesh for published ports. citeturn5search0turn5search2  

**Node C (Command Center, 192.168.1.6)**
- Runs a dashboard (3099) and `code-server` (8443). LinuxServer’s code-server docs specify the image, key environment variables (PUID/PGID/TZ), and default port behavior. citeturn14search0turn14search1  

**Node D (Smart Home, 192.168.1.149)**
- Runs Home Assistant with `network_mode: host` to optimize discovery (your rule). citeturn4search0turn0search0  
- Your requirement “connect voice to LiteLLM via openai_conversation” conflicts with upstream Home Assistant’s official OpenAI integration behavior: the official `openai_conversation` integration documentation describes OpenAI-only configuration and does not expose a base URL override in its UI config flow, and the Home Assistant core issue tracker documents that base URL support was closed as “not planned.” citeturn3search0turn3search4  
  Practical implication: to route voice to LiteLLM, the repo must adopt a custom integration that supports an OpenAI-compatible base URL (e.g., “Extended OpenAI Conversation” or “Custom OpenAI API Conversation”). citeturn3search3turn3search1  

**Node E (Security, 192.168.1.116)**
- Runs Frigate with `network_mode: host` (your rule). Frigate’s official installation docs define the key ports and container expectations (UI/API ports and shared memory behavior). citeturn7search0turn7search1  

## Validation framework design for `./validate.sh`

Your “Validation is Law” rule implies the repository must treat `./validate.sh` as a **policy engine**, not a linter. The most robust pattern for your environment is “structural validation” that is:
- deterministic (no network I/O),
- idempotent (can run on CI),
- and enforceable across nodes (fails fast if a stack violates a hard constraint like host networking + ports).

The following checks are directly implied by official Compose + Docker semantics and by your topology rules:
- **Host networking stacks must not publish ports**. This is enforced by Compose/Docker: host networking and port publishing are incompatible. citeturn0search0turn5search3  
- **Swarm caveat**: if any node is deployed by Swarm stack mode, `network_mode` may be ignored and published ports may route via the mesh unless host publish mode is used. `validate.sh` should therefore treat “Swarm mode” as an explicit opt-in (a different validation profile), not an accidental runtime behavior. citeturn5search0turn5search2  
- **ROCm/vLLM container contract**: `validate.sh` should confirm vLLM services include `/dev/kfd` and `/dev/dri`. This requirement is explicitly described in vLLM’s Docker instructions. citeturn1search0turn1search4  
- **OpenWebUI persistence contract**: confirm `WEBUI_SECRET_KEY` is present (not blank) in the environment wiring whenever tools/auth are used, because Open WebUI documents that missing persistence breaks encryption and sessions after restarts. citeturn6search4turn13view0  

## Security model for agentic actions, MCP tooling, and NanoKVM control

Your topology intentionally enables **agentic operations** (AI triggers scripts across the network). That increases the need for explicit “blast-radius boundaries.”

**NanoKVM control plane hardening**
NanoKVM is a real remote-control device with a documented API surface, including endpoints for GPIO power/reset control. Your KVM operator should operate as the *only* component allowed to talk to NanoKVM, so that you can centralize audit logging and approval gating. citeturn17search0turn17search3  

There is also active public discussion of NanoKVM security posture concerns, including issues like defaults and outbound communications, with notes that many issues were addressed over time. The repo should treat NanoKVM as **untrusted-by-default**: isolate it (VLAN if possible), block outbound traffic if your firmware allows, and require explicit approval for power/reset actions. citeturn17news37  

**MCP and tool server risk**
Open WebUI documents MCP support and calls out that OpenAPI is often preferred for enterprise readiness; for a homelab automation plane, this translates cleanly to:
- implement your “minions” as **OpenAPI tool servers** with strict allowlists,
- only enable MCP where you truly need streamable tool semantics,
- and never give a tool server raw filesystem access to your whole node. citeturn2search1turn10search0  

This caution is reinforced by real-world MCP server vulnerability disclosures: the MCP “git server” ecosystem had multiple CVEs (path validation bypass, argument injection) that demonstrate how tool composition can yield unintended capabilities. A safer repo design assumes **prompt injection will happen**, and therefore enforces: repository allowlists, argument validation, and approval gates for write operations. citeturn9search4turn9search5  

## Deployment-ready scaffolding for `/la`

The remainder of this report provides a **copy/pasteable scaffolding script** that:
- creates a deterministic `nodes/` layout,
- generates `.env` secrets via `openssl rand -hex 24`,
- installs idempotent `scripts/deploy-node-*.sh` wrappers using `rsync` + `docker compose up -d`,
- and writes a `./validate.sh` that enforces the host-network + ROCm + secret rules described above.

This is designed to coexist with your current `/la` contents (e.g., existing `brain-stack.yml`, `litellm_config.yaml`, and automation scripts) while giving you a single canonical multi-node deployment interface. fileciteturn24file0 fileciteturn25file19 fileciteturn25file17  

```bash
#!/usr/bin/env bash
# scripts/bootstrap-la-multinode.sh
#
# Creates a deployment-ready multi-node layout under ./nodes
# and installs validate.sh + deploy scripts.
#
# Safe defaults:
#   - No hardcoded secrets. Secrets generated into node-local .env files.
#   - Host-network nodes MUST NOT have ports: blocks (validated).
#   - Unraid media stack enforces PUID=99 PGID=100 and decypharr REQUIRE_CACHED=true.
#
# Usage:
#   bash scripts/bootstrap-la-multinode.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "${ROOT}/nodes" "${ROOT}/inventory" "${ROOT}/scripts/lib" "${ROOT}/scripts"

# -----------------------------------------------------------------------------
# Inventory (no secrets)
# -----------------------------------------------------------------------------
cat > "${ROOT}/inventory/nodes.env" <<'EOF'
# inventory/nodes.env
#
# Node addressing (edit if needed)
UNRAID_HOST=192.168.1.222
NODE_A_HOST=192.168.1.9
NODE_B_HOST=192.168.1.222
NODE_C_HOST=192.168.1.6
NODE_D_HOST=192.168.1.149
NODE_E_HOST=192.168.1.116

# Remote install root (where rsync pushes node payloads)
REMOTE_BASE_DIR=/opt/la

# SSH user (ensure keys configured)
SSH_USER=root
EOF

# -----------------------------------------------------------------------------
# Common library
# -----------------------------------------------------------------------------
cat > "${ROOT}/scripts/lib/common.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

load_inventory() {
  local inv="${1:-./inventory/nodes.env}"
  [[ -f "$inv" ]] || die "inventory file not found: $inv"
  # shellcheck disable=SC1090
  source "$inv"
  : "${REMOTE_BASE_DIR:?missing REMOTE_BASE_DIR in inventory}"
  : "${SSH_USER:?missing SSH_USER in inventory}"
}

rand_hex_24() {
  need_cmd openssl
  openssl rand -hex 24
}

ensure_env_kv() {
  # ensure_env_kv <envfile> <KEY> <VALUE>
  local envfile="$1" key="$2" val="$3"
  touch "$envfile"
  if grep -qE "^${key}=" "$envfile"; then
    return 0
  fi
  printf '%s=%s\n' "$key" "$val" >> "$envfile"
}

rsync_push_dir() {
  # rsync_push_dir <local_dir> <host> <remote_dir>
  local local_dir="$1" host="$2" remote_dir="$3"
  need_cmd rsync
  need_cmd ssh

  ssh -o BatchMode=yes "${SSH_USER}@${host}" "mkdir -p '${remote_dir}'"
  rsync -az --delete \
    --exclude '.git/' \
    --exclude '**/.env' \
    "${local_dir}/" "${SSH_USER}@${host}:${remote_dir}/"
}

remote_compose_up() {
  # remote_compose_up <host> <remote_dir> <compose_file> <env_file>
  local host="$1" remote_dir="$2" compose_file="$3" env_file="$4"
  need_cmd ssh

  ssh -o BatchMode=yes "${SSH_USER}@${host}" \
    "cd '${remote_dir}' && docker compose --env-file '${env_file}' -f '${compose_file}' up -d"
}
EOF
chmod +x "${ROOT}/scripts/lib/common.sh"

# -----------------------------------------------------------------------------
# Node payload directories
# -----------------------------------------------------------------------------
mkdir -p \
  "${ROOT}/nodes/unraid" \
  "${ROOT}/nodes/node-a" \
  "${ROOT}/nodes/node-b" \
  "${ROOT}/nodes/node-c" \
  "${ROOT}/nodes/node-d" \
  "${ROOT}/nodes/node-e" \
  "${ROOT}/nodes/node-a/services/kvm-operator"

# -----------------------------------------------------------------------------
# Unraid (host networking) - Plex + Riven + Decypharr + Ollama fallback
#
# NOTE: In host network mode, DO NOT publish ports.
# Containers must bind on host IP directly.
# -----------------------------------------------------------------------------
cat > "${ROOT}/nodes/unraid/docker-compose.yml" <<'EOF'
services:
  plex:
    image: lscr.io/linuxserver/plex:latest
    container_name: unraid-plex
    network_mode: host
    restart: unless-stopped
    environment:
      - PUID=99
      - PGID=100
      - TZ=America/New_York
      - VERSION=docker
      # Optional - claim token (do NOT commit)
      - PLEX_CLAIM=${PLEX_CLAIM:-}
    volumes:
      - /mnt/user/appdata/DUMB/plex:/config
      - /mnt/user/DUMB/media:/data

  riven:
    # Upstream quick install example uses spoked/riven:dev
    image: spoked/riven:dev
    container_name: unraid-riven
    network_mode: host
    restart: unless-stopped
    environment:
      - TZ=America/New_York
      # Riven specifics vary by version; keep config on cache/appdata.
    volumes:
      - /mnt/user/appdata/DUMB/riven:/riven/data
      - /mnt/user/DUMB:/mnt/user/DUMB
      - /mnt/debrid/riven_symlinks:/mnt/debrid/riven_symlinks

  decypharr:
    # Docs list ghcr.io/sirrobot01/decypharr and cy01/blackhole variants.
    image: ghcr.io/sirrobot01/decypharr:latest
    container_name: unraid-decypharr
    network_mode: host
    restart: unless-stopped
    environment:
      - PUID=99
      - PGID=100
      - TZ=America/New_York
      # REQUIRED by your operating rules:
      - REQUIRE_CACHED=true
    volumes:
      - /mnt/:/mnt:rshared
      - /mnt/user/appdata/DUMB/decypharr:/app
      # REQUIRED by your operating rules:
      - /mnt/user/DUMB/downloads:/mnt/user/DUMB/downloads
    devices:
      - /dev/fuse:/dev/fuse:rwm
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

  ollama:
    image: ollama/ollama:latest
    container_name: unraid-ollama
    network_mode: host
    restart: unless-stopped
    environment:
      - OLLAMA_HOST=0.0.0.0:11434
    volumes:
      - /mnt/user/appdata/DUMB/ollama:/root/.ollama
EOF

# -----------------------------------------------------------------------------
# Node A (Boss Brain) - vLLM ROCm + OpenWebUI + KVM operator
# -----------------------------------------------------------------------------
cat > "${ROOT}/nodes/node-a/docker-compose.yml" <<'EOF'
networks:
  brain_net:
    driver: bridge

volumes:
  openwebui_data: {}
  hf_cache: {}

services:
  vllm:
    image: vllm/vllm-openai-rocm:latest
    container_name: node-a-vllm
    restart: unless-stopped
    networks: [brain_net]
    environment:
      - HSA_OVERRIDE_GFX_VERSION=11.0.0
      - HF_HOME=/root/.cache/huggingface
      - HF_TOKEN=${HF_TOKEN:-}
    devices:
      - /dev/kfd:/dev/kfd
      - /dev/dri:/dev/dri
    group_add:
      - video
    cap_add:
      - SYS_PTRACE
    security_opt:
      - seccomp=unconfined
    ipc: host
    shm_size: 8gb
    volumes:
      - hf_cache:/root/.cache/huggingface
    command:
      - --model
      - ${VLLM_MODEL:-Qwen/Qwen3-0.6B}
      - --host
      - 0.0.0.0
      - --port
      - "8000"
    ports:
      - "8000:8000"
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 10
      start_period: 300s

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: node-a-openwebui
    restart: unless-stopped
    networks: [brain_net]
    environment:
      - WEBUI_NAME=BossBrain
      - WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}
      # OpenAI-compatible upstream (vLLM)
      - OPENAI_API_BASE_URLS=http://vllm:8000/v1
      - OPENAI_API_KEYS=${OPENAI_API_KEY:-sk-local}
      # Keep direct tool connections enabled
      - ENABLE_DIRECT_CONNECTIONS=true
    volumes:
      - openwebui_data:/app/backend/data
    ports:
      - "3000:8080"
    depends_on:
      vllm:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 10
      start_period: 120s

  kvm-operator:
    build:
      context: ./services/kvm-operator
    container_name: node-a-kvm-operator
    restart: unless-stopped
    networks: [brain_net]
    environment:
      - PORT=5000
      - REQUIRE_APPROVAL=true
      - APPROVAL_TOKEN=${KVM_APPROVAL_TOKEN}
      # Define NanoKVM targets as JSON:
      # {"node_c":{"base_url":"http://nanokvm-nodec","api_key":"..."}}
      - NANOKVM_TARGETS_JSON=${NANOKVM_TARGETS_JSON:-{}}
    ports:
      - "5000:5000"
EOF

# -----------------------------------------------------------------------------
# KVM Operator skeleton: FastAPI wrapper with approval gating
# -----------------------------------------------------------------------------
cat > "${ROOT}/nodes/node-a/services/kvm-operator/Dockerfile" <<'EOF'
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN pip install --no-cache-dir fastapi uvicorn httpx

WORKDIR /app
COPY app.py /app/app.py

EXPOSE 5000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "5000"]
EOF

cat > "${ROOT}/nodes/node-a/services/kvm-operator/app.py" <<'EOF'
import json
import os
from typing import Dict, Any

import httpx
from fastapi import FastAPI, HTTPException, Header

app = FastAPI(title="kvm-operator", version="0.1.0")

REQUIRE_APPROVAL = os.getenv("REQUIRE_APPROVAL", "true").lower() == "true"
APPROVAL_TOKEN = os.getenv("APPROVAL_TOKEN", "")
TARGETS_JSON = os.getenv("NANOKVM_TARGETS_JSON", "{}")

try:
    TARGETS: Dict[str, Any] = json.loads(TARGETS_JSON)
except Exception as e:
    raise RuntimeError(f"Invalid NANOKVM_TARGETS_JSON: {e}")

def must_approve(x_approval_token: str | None):
    if not REQUIRE_APPROVAL:
        return
    if not APPROVAL_TOKEN:
        raise HTTPException(status_code=500, detail="REQUIRE_APPROVAL=true but APPROVAL_TOKEN is unset")
    if x_approval_token != APPROVAL_TOKEN:
        raise HTTPException(status_code=409, detail="Approval required (missing/invalid X-Approval-Token)")

@app.get("/health")
def health():
    return {"ok": True, "require_approval": REQUIRE_APPROVAL, "targets": list(TARGETS.keys())}

@app.get("/targets")
def targets():
    return {"targets": TARGETS}

@app.post("/targets/{name}/power")
async def power_control(
    name: str,
    action: str,  # "on" | "off" | "reset"
    x_approval_token: str | None = Header(default=None, alias="X-Approval-Token"),
):
    """
    Minimal wrapper around NanoKVM API concepts.
    This is intentionally conservative: all write actions require approval token when REQUIRE_APPROVAL=true.
    """
    must_approve(x_approval_token)

    target = TARGETS.get(name)
    if not target:
        raise HTTPException(status_code=404, detail=f"Unknown target: {name}")

    base_url = target.get("base_url")
    if not base_url:
        raise HTTPException(status_code=500, detail=f"Target missing base_url: {name}")

    # NanoKVM API reference commonly exposes GPIO control via /api/vm/gpio (POST).
    # The exact payload may differ by firmware; keep it generic and configurable.
    endpoint = f"{base_url.rstrip('/')}/api/vm/gpio"
    payload = {"action": action}

    async with httpx.AsyncClient(timeout=10.0) as client:
        r = await client.post(endpoint, json=payload)
        if r.status_code >= 400:
            raise HTTPException(status_code=502, detail={"upstream_status": r.status_code, "body": r.text})
        return {"ok": True, "upstream": r.json() if r.headers.get("content-type", "").startswith("application/json") else r.text}
EOF

# -----------------------------------------------------------------------------
# Node B (LiteLLM gateway)
# -----------------------------------------------------------------------------
cat > "${ROOT}/nodes/node-b/docker-compose.yml" <<'EOF'
services:
  db:
    image: postgres:16
    container_name: node-b-litellm-db
    restart: unless-stopped
    environment:
      - POSTGRES_DB=litellm
      - POSTGRES_USER=litellm
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - ./data/postgres:/var/lib/postgresql/data

  litellm:
    image: docker.litellm.ai/berriai/litellm:main-latest
    container_name: node-b-litellm
    restart: unless-stopped
    depends_on:
      - db
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - DATABASE_URL=postgresql://litellm:${POSTGRES_PASSWORD}@db:5432/litellm
    volumes:
      - ./litellm_config.yaml:/app/config.yaml:ro
    command: ["--config", "/app/config.yaml", "--port", "4000"]
    ports:
      - "4000:4000"
EOF

cat > "${ROOT}/nodes/node-b/litellm_config.yaml" <<'EOF'
model_list:
  # Route to Node A vLLM
  - model_name: bossbrain-vllm
    litellm_params:
      model: openai/bossbrain-vllm
      api_base: http://192.168.1.9:8000/v1
      api_key: sk-local

  # Route to Unraid Ollama fallback
  - model_name: unraid-ollama
    litellm_params:
      model: ollama/llama3
      api_base: http://192.168.1.222:11434
      api_key: sk-local

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY

litellm_settings:
  drop_params: true
EOF

# -----------------------------------------------------------------------------
# Node C (dashboard + code-server)
# -----------------------------------------------------------------------------
cat > "${ROOT}/nodes/node-c/docker-compose.yml" <<'EOF'
services:
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: node-c-dashboard
    restart: unless-stopped
    ports:
      - "3099:3000"
    volumes:
      - ./homepage:/app/config

  code-server:
    image: lscr.io/linuxserver/code-server:latest
    container_name: node-c-code-server
    restart: unless-stopped
    environment:
      - PUID=99
      - PGID=100
      - TZ=America/New_York
      - PASSWORD=${CODE_SERVER_PASSWORD}
      - DEFAULT_WORKSPACE=/config/workspace
    volumes:
      - ./code-server:/config
    ports:
      - "8443:8443"
EOF

# -----------------------------------------------------------------------------
# Node D (Home Assistant) - host network
# -----------------------------------------------------------------------------
cat > "${ROOT}/nodes/node-d/docker-compose.yml" <<'EOF'
services:
  homeassistant:
    image: ghcr.io/home-assistant/home-assistant:stable
    container_name: node-d-homeassistant
    restart: unless-stopped
    network_mode: host
    environment:
      - TZ=America/New_York
    volumes:
      - ./config:/config
      - /etc/localtime:/etc/localtime:ro
EOF

# -----------------------------------------------------------------------------
# Node E (Frigate) - host network
# -----------------------------------------------------------------------------
cat > "${ROOT}/nodes/node-e/docker-compose.yml" <<'EOF'
services:
  frigate:
    image: ghcr.io/blakeblackshear/frigate:stable
    container_name: node-e-frigate
    restart: unless-stopped
    network_mode: host
    shm_size: "512mb"
    privileged: true
    environment:
      - FRIGATE_RTSP_PASSWORD=${FRIGATE_RTSP_PASSWORD}
      - TZ=America/New_York
    volumes:
      - ./config:/config
      - ./storage:/media/frigate
      - type: tmpfs
        target: /tmp/cache
        tmpfs:
          size: 1000000000
EOF

# -----------------------------------------------------------------------------
# Node-local .env generation (NO secrets committed)
# -----------------------------------------------------------------------------
for n in unraid node-a node-b node-c node-d node-e; do
  env="${ROOT}/nodes/${n}/.env"
  [[ -f "$env" ]] || touch "$env"
done

# Unraid secrets placeholders
"${ROOT}/scripts/lib/common.sh" >/dev/null 2>&1 || true
# shellcheck disable=SC1090
source "${ROOT}/scripts/lib/common.sh"

ensure_env_kv "${ROOT}/nodes/unraid/.env" "PLEX_CLAIM" ""
ensure_env_kv "${ROOT}/nodes/unraid/.env" "TZ" "America/New_York"

# Node A secrets
ensure_env_kv "${ROOT}/nodes/node-a/.env" "WEBUI_SECRET_KEY" "$(rand_hex_24)"
ensure_env_kv "${ROOT}/nodes/node-a/.env" "KVM_APPROVAL_TOKEN" "$(rand_hex_24)"
ensure_env_kv "${ROOT}/nodes/node-a/.env" "HF_TOKEN" ""
ensure_env_kv "${ROOT}/nodes/node-a/.env" "VLLM_MODEL" "Qwen/Qwen3-0.6B"

# Node B secrets
ensure_env_kv "${ROOT}/nodes/node-b/.env" "LITELLM_MASTER_KEY" "sk-$(rand_hex_24)"
ensure_env_kv "${ROOT}/nodes/node-b/.env" "POSTGRES_PASSWORD" "$(rand_hex_24)"

# Node C secrets
ensure_env_kv "${ROOT}/nodes/node-c/.env" "CODE_SERVER_PASSWORD" "$(rand_hex_24)"

# Node E secrets
ensure_env_kv "${ROOT}/nodes/node-e/.env" "FRIGATE_RTSP_PASSWORD" "$(rand_hex_24)"

# -----------------------------------------------------------------------------
# Deploy scripts (rsync + docker compose up -d), idempotent
# -----------------------------------------------------------------------------
cat > "${ROOT}/scripts/deploy-node-unraid.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Deploy Unraid media stack
source ./scripts/lib/common.sh
load_inventory

host="${UNRAID_HOST:?missing UNRAID_HOST}"
local_dir="./nodes/unraid"
remote_dir="${REMOTE_BASE_DIR}/unraid"

rsync_push_dir "$local_dir" "$host" "$remote_dir"
# push env separately to avoid accidental overwrite
rsync -az "./nodes/unraid/.env" "${SSH_USER}@${host}:${remote_dir}/.env"

remote_compose_up "$host" "$remote_dir" "docker-compose.yml" ".env"
EOF
chmod +x "${ROOT}/scripts/deploy-node-unraid.sh"

cat > "${ROOT}/scripts/deploy-node-a.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Deploy Node A (Boss Brain)
source ./scripts/lib/common.sh
load_inventory

host="${NODE_A_HOST:?missing NODE_A_HOST}"
local_dir="./nodes/node-a"
remote_dir="${REMOTE_BASE_DIR}/node-a"

rsync_push_dir "$local_dir" "$host" "$remote_dir"
rsync -az "./nodes/node-a/.env" "${SSH_USER}@${host}:${remote_dir}/.env"

remote_compose_up "$host" "$remote_dir" "docker-compose.yml" ".env"
EOF
chmod +x "${ROOT}/scripts/deploy-node-a.sh"

cat > "${ROOT}/scripts/deploy-node-b.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Deploy Node B (LiteLLM Gateway)
source ./scripts/lib/common.sh
load_inventory

host="${NODE_B_HOST:?missing NODE_B_HOST}"
local_dir="./nodes/node-b"
remote_dir="${REMOTE_BASE_DIR}/node-b"

rsync_push_dir "$local_dir" "$host" "$remote_dir"
rsync -az "./nodes/node-b/.env" "${SSH_USER}@${host}:${remote_dir}/.env"

remote_compose_up "$host" "$remote_dir" "docker-compose.yml" ".env"
EOF
chmod +x "${ROOT}/scripts/deploy-node-b.sh"

cat > "${ROOT}/scripts/deploy-node-c.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Deploy Node C (Dashboard + code-server)
source ./scripts/lib/common.sh
load_inventory

host="${NODE_C_HOST:?missing NODE_C_HOST}"
local_dir="./nodes/node-c"
remote_dir="${REMOTE_BASE_DIR}/node-c"

rsync_push_dir "$local_dir" "$host" "$remote_dir"
rsync -az "./nodes/node-c/.env" "${SSH_USER}@${host}:${remote_dir}/.env"

remote_compose_up "$host" "$remote_dir" "docker-compose.yml" ".env"
EOF
chmod +x "${ROOT}/scripts/deploy-node-c.sh"

cat > "${ROOT}/scripts/deploy-node-d.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Deploy Node D (Home Assistant)
source ./scripts/lib/common.sh
load_inventory

host="${NODE_D_HOST:?missing NODE_D_HOST}"
local_dir="./nodes/node-d"
remote_dir="${REMOTE_BASE_DIR}/node-d"

rsync_push_dir "$local_dir" "$host" "$remote_dir"
# Node D env currently minimal; still sync
rsync -az "./nodes/node-d/.env" "${SSH_USER}@${host}:${remote_dir}/.env"

remote_compose_up "$host" "$remote_dir" "docker-compose.yml" ".env"
EOF
chmod +x "${ROOT}/scripts/deploy-node-d.sh"

cat > "${ROOT}/scripts/deploy-node-e.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Deploy Node E (Frigate)
source ./scripts/lib/common.sh
load_inventory

host="${NODE_E_HOST:?missing NODE_E_HOST}"
local_dir="./nodes/node-e"
remote_dir="${REMOTE_BASE_DIR}/node-e"

rsync_push_dir "$local_dir" "$host" "$remote_dir"
rsync -az "./nodes/node-e/.env" "${SSH_USER}@${host}:${remote_dir}/.env"

remote_compose_up "$host" "$remote_dir" "docker-compose.yml" ".env"
EOF
chmod +x "${ROOT}/scripts/deploy-node-e.sh"

cat > "${ROOT}/scripts/deploy-all.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
./validate.sh
./scripts/deploy-node-unraid.sh
./scripts/deploy-node-a.sh
./scripts/deploy-node-b.sh
./scripts/deploy-node-c.sh
./scripts/deploy-node-d.sh
./scripts/deploy-node-e.sh
EOF
chmod +x "${ROOT}/scripts/deploy-all.sh"

# -----------------------------------------------------------------------------
# validate.sh (central test suite)
# -----------------------------------------------------------------------------
cat > "${ROOT}/validate.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

fail() { echo "VALIDATION FAILED: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

need_file() { [[ -f "$1" ]] || fail "missing required file: $1"; }
need_dir() { [[ -d "$1" ]] || fail "missing required dir: $1"; }

need_file "./inventory/nodes.env"
need_file "./scripts/lib/common.sh"

for d in ./nodes/unraid ./nodes/node-a ./nodes/node-b ./nodes/node-c ./nodes/node-d ./nodes/node-e; do
  need_dir "$d"
  need_file "$d/docker-compose.yml"
  need_file "$d/.env"
done
pass "node directories and required files exist"

# Host-network stacks MUST NOT publish ports (Compose/Docker incompatibility)
check_no_ports_when_hostnet() {
  local f="$1"
  if grep -qE 'network_mode:\s*host' "$f"; then
    if grep -qE '^\s*ports:\s*$' "$f"; then
      fail "host network stack must not declare ports: $f"
    fi
  fi
}

check_no_ports_when_hostnet ./nodes/unraid/docker-compose.yml
check_no_ports_when_hostnet ./nodes/node-d/docker-compose.yml
check_no_ports_when_hostnet ./nodes/node-e/docker-compose.yml
pass "host-network stacks do not declare ports"

# Unraid rules: host network + PUID/PGID + downloads mount + decypharr REQUIRE_CACHED=true
UNRAID_F=./nodes/unraid/docker-compose.yml
grep -qE 'plex:\s*$' "$UNRAID_F" || fail "unraid stack missing plex service"
grep -qE 'network_mode:\s*host' "$UNRAID_F" || fail "unraid stack must use network_mode: host"
grep -qE 'PUID=99' "$UNRAID_F" || fail "unraid stack must set PUID=99"
grep -qE 'PGID=100' "$UNRAID_F" || fail "unraid stack must set PGID=100"
grep -qE 'REQUIRE_CACHED=true' "$UNRAID_F" || fail "decypharr must set REQUIRE_CACHED=true"
grep -qE '/mnt/user/DUMB/downloads' "$UNRAID_F" || fail "must mount /mnt/user/DUMB/downloads in unraid stack"
pass "unraid media rules satisfied"

# Node A ROCm rules: vLLM must map /dev/kfd and /dev/dri and set HSA_OVERRIDE_GFX_VERSION=11.0.0
NODEA_F=./nodes/node-a/docker-compose.yml
grep -qE 'vllm:' "$NODEA_F" || fail "node-a stack missing vllm service"
grep -qE '/dev/kfd' "$NODEA_F" || fail "node-a vllm must map /dev/kfd"
grep -qE '/dev/dri' "$NODEA_F" || fail "node-a vllm must map /dev/dri"
grep -qE 'HSA_OVERRIDE_GFX_VERSION=11\.0\.0' "$NODEA_F" || fail "node-a vllm must set HSA_OVERRIDE_GFX_VERSION=11.0.0"
pass "node-a ROCm/vLLM rules satisfied"

# Node A OpenWebUI: must wire WEBUI_SECRET_KEY
grep -qE 'WEBUI_SECRET_KEY=\$\{WEBUI_SECRET_KEY\}' "$NODEA_F" || fail "node-a openwebui must reference WEBUI_SECRET_KEY from .env"
pass "node-a OpenWebUI secret key wiring satisfied"

# KVM operator approval gate required
grep -qE 'kvm-operator:' "$NODEA_F" || fail "node-a stack missing kvm-operator service"
grep -qE 'REQUIRE_APPROVAL=true' "$NODEA_F" || fail "kvm-operator must set REQUIRE_APPROVAL=true"
grep -qE 'KVM_APPROVAL_TOKEN' "$NODEA_F" || fail "kvm-operator must wire KVM_APPROVAL_TOKEN from .env"
pass "kvm operator approval gating satisfied"

echo "ALL VALIDATIONS PASSED"
EOF
chmod +x "${ROOT}/validate.sh"

echo "Bootstrap complete."
echo "Next:"
echo "  ./validate.sh"
echo "  ./scripts/deploy-all.sh"
EOF
```

The scaffolding above encodes and validates the highest-risk “non-negotiables” from the upstream docs:
- host networking rules (no `ports:` when `network_mode: host`) citeturn0search0turn5search3  
- ROCm/vLLM device access expectations citeturn1search0turn1search4  
- Open WebUI secret persistence to prevent decryption/session failures citeturn6search4turn13view0  
- LiteLLM’s OpenAI-compatible proxy pattern for routing between Node A vLLM and Unraid Ollama citeturn6search5turn6search0  
- NanoKVM API surface being “real” and therefore appropriate to wrap behind an approval-gated operator instead of exposing directly citeturn17search0turn17search3  

It also encodes the key operational correction for Node D: the official Home Assistant OpenAI agent does not provide a base URL override, so “voice to LiteLLM via openai_conversation” requires a custom agent integration that supports OpenAI-compatible endpoints. citeturn3search0turn3search4turn3search3
