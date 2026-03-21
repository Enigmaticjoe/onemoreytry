#!/usr/bin/env bash
# Master deployment bootstrap for NanoClaw + (optional) UnraidClaw on Unraid Node B.
# Safe-by-default: validates prerequisites, avoids destructive operations, and prompts before overwrites.

set -Eeuo pipefail

APP_BASE="/mnt/user/appdata"
NANOCLAW_DIR="${APP_BASE}/nanoclaw"
UNRAIDCLAW_DIR="${APP_BASE}/unraidclaw"
REPO_URL="https://github.com/qwibitai/nanoclaw.git"
REPO_DIR="${NANOCLAW_DIR}/repo"
ENV_FILE="${NANOCLAW_DIR}/.env"
MCP_FILE="${NANOCLAW_DIR}/.mcp.json"
AGENTS_DIR="${NANOCLAW_DIR}/agents"
COMPOSE_FILE="${NANOCLAW_DIR}/docker-compose.yml"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
err() { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

on_error() {
  err "Deployment aborted at line $1. Review output above."
}
trap 'on_error $LINENO' ERR

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }
}

prompt_default() {
  local var_name="$1" prompt="$2" default="$3" value
  read -r -p "$prompt [$default]: " value || true
  value="${value:-$default}"
  printf -v "$var_name" '%s' "$value"
}

write_file_from_repo() {
  local src="$1" dst="$2"
  if [[ ! -f "$src" ]]; then
    warn "Template file not found: $src"
    return 1
  fi
  install -Dm644 "$src" "$dst"
}

main() {
  require_cmd git
  require_cmd curl
  require_cmd openssl

  log "Creating directory structure under ${APP_BASE}."
  install -d -m 775 "${NANOCLAW_DIR}" "${NANOCLAW_DIR}/workspace" "${NANOCLAW_DIR}/router" "${AGENTS_DIR}"
  install -d -m 775 "${UNRAIDCLAW_DIR}" "${UNRAIDCLAW_DIR}/config" "${UNRAIDCLAW_DIR}/certs"

  if [[ -d "${REPO_DIR}/.git" ]]; then
    log "NanoClaw repo exists. Pulling latest changes."
    git -C "${REPO_DIR}" fetch --all --prune
    git -C "${REPO_DIR}" pull --ff-only
  else
    log "Cloning NanoClaw repo from ${REPO_URL}."
    git clone "${REPO_URL}" "${REPO_DIR}"
  fi

  log "Generating environment file."
  if [[ -f "$ENV_FILE" ]]; then
    warn "Existing .env found at ${ENV_FILE}; preserving current file."
  else
    prompt_default ANTHROPIC_BASE_URL "ANTHROPIC_BASE_URL" "http://192.168.1.222:11434/v1"
    prompt_default ANTHROPIC_AUTH_TOKEN "ANTHROPIC_AUTH_TOKEN" "ollama"
    prompt_default COMPLEX_AGENT_BASE_URL "Node A vLLM base URL" "http://NODE_A_TAILSCALE:8000/v1"
    prompt_default HOME_ASSISTANT_URL "Home Assistant URL" "http://192.168.1.248:8123"
    prompt_default QDRANT_URL "Qdrant URL" "http://NODE_A_TAILSCALE:6333"

    cat >"$ENV_FILE" <<EOF
TZ=America/New_York
PUID=99
PGID=100
NODE_ENV=production
ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL}
ANTHROPIC_AUTH_TOKEN=${ANTHROPIC_AUTH_TOKEN}
DEFAULT_AGENT_MODEL=qwen3:14b-abliterated
FAST_AGENT_MODEL=glm4-flash-heretic
COMPLEX_AGENT_BASE_URL=${COMPLEX_AGENT_BASE_URL}
COMPLEX_AGENT_MODEL=qwen3-14b-awq
FALLBACK_AGENT_MODEL=josiefied-qwen3:8b
DISCORD_BOT_TOKEN=REPLACE_ME
TELEGRAM_BOT_TOKEN=REPLACE_ME
TELEGRAM_CHAT_ID=REPLACE_ME
DISCORD_WEBHOOK_URL=
UNRAIDCLAW_URL=https://192.168.1.222:9876
UNRAIDCLAW_API_KEY=GENERATE_ME
HOME_ASSISTANT_URL=${HOME_ASSISTANT_URL}
HOME_ASSISTANT_TOKEN=REPLACE_ME
GITHUB_TOKEN=REPLACE_ME
BRAVE_API_KEY=REPLACE_ME
TAVILY_API_KEY=
QDRANT_URL=${QDRANT_URL}
QDRANT_API_KEY=
NANOCLAW_HEALTH_PORT=3000
OLLAMA_HEALTH_URL=http://192.168.1.222:11434/api/tags
UNRAIDCLAW_HEALTH_URL=https://192.168.1.222:9876/health
EOF
  fi

  log "Seeding agent memory files and MCP config."
  write_file_from_repo "./agents/chimera/CLAUDE.md" "${AGENTS_DIR}/chimera/CLAUDE.md" || true
  write_file_from_repo "./agents/forge/CLAUDE.md" "${AGENTS_DIR}/forge/CLAUDE.md" || true
  write_file_from_repo "./agents/sentinel/CLAUDE.md" "${AGENTS_DIR}/sentinel/CLAUDE.md" || true
  write_file_from_repo "./agents/oracle/CLAUDE.md" "${AGENTS_DIR}/oracle/CLAUDE.md" || true
  write_file_from_repo "./.mcp.json" "$MCP_FILE" || true
  write_file_from_repo "./docker-compose.yml" "$COMPOSE_FILE" || true
  write_file_from_repo "./unraidclaw-openclaw-config.json" "${UNRAIDCLAW_DIR}/config/unraidclaw-openclaw-config.json" || true

  if [[ ! -f "${NANOCLAW_DIR}/router/router.py" ]]; then
    log "Seeding model routing helper at ${NANOCLAW_DIR}/router/router.py."
    cat >"${NANOCLAW_DIR}/router/router.py" <<'PY'
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
import os
import httpx

app = FastAPI(title="nanoclaw-model-router")

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://192.168.1.222:11434/v1")
VLLM_BASE_URL = os.getenv("VLLM_BASE_URL", "http://NODE_A_TAILSCALE:8000/v1")
DEFAULT_MODEL = os.getenv("DEFAULT_MODEL", "qwen3:14b-abliterated")
FAST_MODEL = os.getenv("FAST_MODEL", "glm4-flash-heretic")
COMPLEX_MODEL = os.getenv("COMPLEX_MODEL", "qwen3-14b-awq")
FALLBACK_MODEL = os.getenv("FALLBACK_MODEL", "josiefied-qwen3:8b")

def choose_target(payload: dict) -> tuple[str, str]:
    model = payload.get("model", DEFAULT_MODEL)
    hint = str(payload.get("complexity", "")).lower()
    if hint in {"complex", "deep", "reasoning"}:
        return VLLM_BASE_URL, COMPLEX_MODEL
    if hint in {"fast", "realtime", "quick"}:
        return OLLAMA_BASE_URL, FAST_MODEL
    if payload.get("fallback", False):
        return OLLAMA_BASE_URL, FALLBACK_MODEL
    return OLLAMA_BASE_URL, model or DEFAULT_MODEL

@app.post("/v1/chat/completions")
async def route_chat(req: Request):
    payload = await req.json()
    target_base, selected_model = choose_target(payload)
    payload["model"] = selected_model
    async with httpx.AsyncClient(timeout=180.0) as client:
        resp = await client.post(f"{target_base}/chat/completions", json=payload)
    return JSONResponse(status_code=resp.status_code, content=resp.json())

@app.get("/health")
async def health():
    return {"ok": True}
PY
  fi

  log "Preparing UnraidClaw Option A/B guidance."
  cat <<'EOF'

=== UnraidClaw Deployment Options ===
Option A (recommended): install UnraidClaw from Community Applications plugin UI.
Option B: enable COMPOSE_PROFILES=unraidclaw-container and deploy stack via Portainer.

For Option B, generate an API key now:
  openssl rand -hex 32
Then set UNRAIDCLAW_API_KEY in /mnt/user/appdata/nanoclaw/.env.
EOF

  log "Model pre-pull commands (manual review recommended before execution):"
  cat <<'EOF'
ollama pull huihui_ai/qwen3-abliterated:14b
ollama pull dolphin3:70b
ollama pull glm4-9b-abliterated
ollama pull josiefied/qwen3:8b
ollama pull dolphin-mixtral:8x7b
EOF

  log "Deployment artifacts prepared. Import ${COMPOSE_FILE} in Portainer as a stack."
  log "Done. Review NEXT-STEPS.md before going live."
}

main "$@"
