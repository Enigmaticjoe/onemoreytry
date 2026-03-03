#!/usr/bin/env bash
# Turnkey local installer for OpenClaw on Node C (Fedora 44+)
# Also prepares Node A KVM Operator + OpenClaw prompt/config bundles.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
source "${REPO_ROOT}/scripts/lib-inventory.sh"
load_inventory "$REPO_ROOT"

OPENCLAW_DIR="${OPENCLAW_DIR:-/opt/openclaw}"
HOMELAB_DIR="${HOMELAB_DIR:-${OPENCLAW_DIR}/homelab}"
BUNDLE_DIR="${REPO_ROOT}/turnkey"
DRY_RUN=false
NO_DEPLOY=false
CHECK_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --no-deploy) NO_DEPLOY=true ;;
    --check-only) CHECK_ONLY=true ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok(){ echo -e "${GREEN}✓${NC} $*"; }
warn(){ echo -e "${YELLOW}!${NC} $*"; }
err(){ echo -e "${RED}✗${NC} $*"; }
info(){ echo -e "${CYAN}→${NC} $*"; }
step(){ echo; echo -e "${BOLD}$*${NC}"; echo; }

run(){
  if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

require_cmd(){
  command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }
}

json_escape(){
  python3 - <<'PY' "$1"
import json,sys
print(json.dumps(sys.argv[1]))
PY
}

latest_github_release(){
  local repo="$1"
  curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' || true
}

latest_ghcr_digest(){
  local image="$1"
  skopeo inspect "docker://${image}" 2>/dev/null | jq -r '.Digest // empty' || true
}

step "Step 1 — Host validation (Fedora local install)"

if [ "$(id -u)" -ne 0 ]; then
  err "Run as root: sudo $0 [--dry-run] [--no-deploy]"
  exit 1
fi

if ! [ -f /etc/fedora-release ]; then
  err "This installer is for Fedora hosts only."
  exit 1
fi

FEDORA_VERSION="$(rpm -E %fedora)"
if [ "$FEDORA_VERSION" -lt 44 ]; then
  warn "Fedora ${FEDORA_VERSION} detected. Script is tuned for Fedora 44+; continuing."
else
  ok "Fedora ${FEDORA_VERSION} detected"
fi

for bin in curl jq openssl python3; do require_cmd "$bin"; done

step "Step 2 — Install/verify dependencies"
run "dnf -y install docker docker-compose-plugin git curl jq openssl python3 python3-pip intel-compute-runtime intel-level-zero intel-gpu-tools"
run "systemctl enable --now docker"

if command -v skopeo >/dev/null 2>&1; then
  ok "skopeo already present"
else
  run "dnf -y install skopeo"
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  ok "Docker + compose plugin ready"
else
  err "Docker or compose plugin not functional"
  exit 1
fi

step "Step 3 — Query latest upstream versions"
OPENCLAW_RELEASE="$(latest_github_release openclaw/openclaw)"
OPENCLAW_DIGEST="$(latest_ghcr_digest ghcr.io/openclaw/openclaw:latest)"
KVM_FASTAPI_RELEASE="$(latest_github_release fastapi/fastapi)"

[ -n "$OPENCLAW_RELEASE" ] && ok "Latest OpenClaw release tag: ${OPENCLAW_RELEASE}" || warn "Could not resolve OpenClaw release tag"
[ -n "$OPENCLAW_DIGEST" ] && ok "Latest OpenClaw image digest: ${OPENCLAW_DIGEST}" || warn "Could not resolve OpenClaw image digest"
[ -n "$KVM_FASTAPI_RELEASE" ] && ok "Latest FastAPI release tag (KVM operator dependency): ${KVM_FASTAPI_RELEASE}" || warn "Could not resolve FastAPI release"

if [ "$CHECK_ONLY" = true ]; then
  ok "Check-only complete"
  exit 0
fi

step "Step 4 — Generate secure tokens"
OPENCLAW_TOKEN="$(openssl rand -hex 24)"
KVM_OPERATOR_TOKEN="$(openssl rand -hex 24)"
ok "Generated OPENCLAW_GATEWAY_TOKEN"
ok "Generated KVM_OPERATOR_TOKEN"

step "Step 5 — Build turnkey package (Node A + Node C)"
run "mkdir -p '${BUNDLE_DIR}/node-a' '${BUNDLE_DIR}/node-c' '${BUNDLE_DIR}/stacks' '${OPENCLAW_DIR}/config' '${OPENCLAW_DIR}/workspace' '${HOMELAB_DIR}'"

cat > "${BUNDLE_DIR}/node-c/agent-prompt.json" <<JSON
{
  "name": "node-c-arc-openclaw",
  "role": "edge-inference-and-automation",
  "host": "${NODE_C_IP}",
  "models": {
    "primary": "ollama/qwen2.5-coder:latest",
    "vision": "ollama/llava:latest",
    "fallback": "litellm/openai/gpt-4o-mini"
  },
  "constraints": {
    "require_preflight": true,
    "approval_required_for_destructive": true,
    "max_parallel_actions": 3
  },
  "automation": {
    "on_boot": ["healthcheck", "models_list", "kvm_ping"],
    "cron": {
      "nightly_maintenance": "0 3 * * *",
      "security_audit": "30 3 * * 0"
    }
  }
}
JSON

cat > "${BUNDLE_DIR}/node-a/agent-prompt.json" <<JSON
{
  "name": "node-a-brain-kvm",
  "role": "orchestrator-and-kvm-operator",
  "host": "${NODE_A_IP}",
  "models": {
    "primary": "vllm/dolphin-2.9.3-llama-3.1-8b",
    "fallback": "litellm/anthropic/claude-sonnet-4-6"
  },
  "kvm": {
    "base_url": "http://${NODE_A_IP}:5000",
    "require_approval": true,
    "denylist_enforced": true
  },
  "automation": {
    "startup_sequence": ["kvm_operator_health", "openclaw_hooks_test", "inventory_sync"],
    "incident_mode": "safe-revert"
  }
}
JSON

cat > "${BUNDLE_DIR}/stacks/node-c-openclaw-compose.yml" <<'YAML'
services:
  openclaw-gateway:
    image: ghcr.io/openclaw/openclaw:latest
    container_name: openclaw-gateway
    user: root
    init: true
    restart: unless-stopped
    ports:
      - "18789:18789"
    env_file:
      - /opt/openclaw/.env
    volumes:
      - /opt/openclaw/config:/root/.openclaw
      - /opt/openclaw/workspace:/home/node/clawd
      - /var/run/docker.sock:/var/run/docker.sock
    extra_hosts:
      - host.docker.internal:host-gateway
    command: ["sh", "-c", "exec node dist/index.js gateway --bind lan"]
YAML

cat > "${BUNDLE_DIR}/stacks/node-a-kvm-operator-compose.yml" <<'YAML'
services:
  kvm-operator:
    image: python:3.12-slim
    container_name: kvm-operator
    restart: unless-stopped
    working_dir: /app
    command: >
      bash -lc "pip install --no-cache-dir -r requirements.txt &&
      uvicorn app:app --host 0.0.0.0 --port 5000"
    env_file:
      - ./kvm-operator.env
    volumes:
      - ../../kvm-operator:/app:ro
    ports:
      - "5000:5000"
YAML

cat > "${BUNDLE_DIR}/node-c/.env.template" <<'ENV'
OPENCLAW_GATEWAY_TOKEN=change-me-openclaw-gateway-token
OLLAMA_API_KEY=ollama
LITELLM_API_KEY=change-me-litellm-api-key
KVM_OPERATOR_URL=http://NODE_A_IP:5000
KVM_OPERATOR_TOKEN=change-me-kvm-operator-token
ENV

cat > "${BUNDLE_DIR}/node-a/kvm-operator.env.template" <<'ENV'
KVM_OPERATOR_TOKEN=change-me-kvm-operator-token
REQUIRE_APPROVAL=true
ALLOW_DANGEROUS=false
KVM_TARGETS_JSON={"kvm-d829":"192.168.1.130"}
NANOKVM_USERNAME=admin
NANOKVM_PASSWORD=change-me
NANOKVM_AUTH_MODE=auto
SESSION_TTL=300
LITELLM_URL=http://NODE_B_IP:4000/v1/chat/completions
LITELLM_API_KEY=sk-master-key
VISION_MODEL=kvm-vision
LOG_LEVEL=INFO
ENV

ok "Turnkey package created at ${BUNDLE_DIR}"

step "Step 6 — Install OpenClaw runtime files"
run "install -m 0644 node-c-arc/openclaw.json '${OPENCLAW_DIR}/config/openclaw.json'"
run "install -m 0644 openclaw/skill-kvm.md '${OPENCLAW_DIR}/workspace/skill-kvm.md'"
run "install -m 0644 openclaw/skill-deploy.md '${OPENCLAW_DIR}/workspace/skill-deploy.md'"
run "install -m 0644 '${BUNDLE_DIR}/stacks/node-c-openclaw-compose.yml' '${HOMELAB_DIR}/openclaw.yml'"

# Write secret-bearing env files only to the runtime directory (never to tracked bundle paths)
if [ "$DRY_RUN" = true ]; then
  echo "[dry-run] write ${OPENCLAW_DIR}/.env with generated secrets"
  echo "[dry-run] write ${OPENCLAW_DIR}/kvm-operator.env with generated secrets"
else
  _litellm_key="$(openssl rand -hex 24)"
  _tmp="$(mktemp)" || { err "Failed to create temp file"; exit 1; }
  cat > "$_tmp" <<ENV
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_TOKEN}
OLLAMA_API_KEY=ollama
LITELLM_API_KEY=${_litellm_key}
KVM_OPERATOR_URL=http://${NODE_A_IP}:5000
KVM_OPERATOR_TOKEN=${KVM_OPERATOR_TOKEN}
ENV
  install -m 0600 "$_tmp" "${OPENCLAW_DIR}/.env"
  rm -f "$_tmp"
  ok "Runtime .env written to ${OPENCLAW_DIR}/.env"

  _tmp2="$(mktemp)" || { err "Failed to create temp file"; exit 1; }
  cat > "$_tmp2" <<ENV
KVM_OPERATOR_TOKEN=${KVM_OPERATOR_TOKEN}
REQUIRE_APPROVAL=true
ALLOW_DANGEROUS=false
KVM_TARGETS_JSON={"kvm-d829":"192.168.1.130"}
NANOKVM_USERNAME=admin
NANOKVM_PASSWORD=change-me
NANOKVM_AUTH_MODE=auto
SESSION_TTL=300
LITELLM_URL=http://${NODE_B_IP}:4000/v1/chat/completions
LITELLM_API_KEY=sk-master-key
VISION_MODEL=kvm-vision
LOG_LEVEL=INFO
ENV
  install -m 0600 "$_tmp2" "${OPENCLAW_DIR}/kvm-operator.env"
  rm -f "$_tmp2"
  ok "Runtime kvm-operator.env written to ${OPENCLAW_DIR}/kvm-operator.env"
fi

cat > "${OPENCLAW_DIR}/workspace/AGENTS.md" <<EOF2
# Node C OpenClaw Runtime Context

Read these local skills before acting:
- skill-kvm.md
- skill-deploy.md

Operational defaults:
- Verify state before write actions.
- Use KVM operator on Node A: http://${NODE_A_IP}:5000
- Use Ollama local-first at http://host.docker.internal:11434/v1
- Fall back to LiteLLM on Node B: http://${NODE_B_IP}:4000/v1
EOF2
ok "Runtime workspace context written"

if [ "$NO_DEPLOY" = true ]; then
  warn "--no-deploy set, skipping container start"
else
  step "Step 7 — Deploy OpenClaw on local Node C"
  run "docker compose -f '${HOMELAB_DIR}/openclaw.yml' --env-file '${OPENCLAW_DIR}/.env' pull"
  run "docker compose -f '${HOMELAB_DIR}/openclaw.yml' --env-file '${OPENCLAW_DIR}/.env' up -d"

  if [ "$DRY_RUN" = false ]; then
    for _ in $(seq 1 24); do
      if curl -fsS "http://127.0.0.1:18789/" >/dev/null 2>&1; then
        ok "OpenClaw healthy on localhost:18789"
        break
      fi
      sleep 5
    done
  fi
fi

step "Complete"
echo "Control UI: http://${NODE_C_IP}:18789/?token=${OPENCLAW_TOKEN}"
echo "Turnkey docs: ${BUNDLE_DIR}/TURNKEY_RELEASE.md"
echo "Node A prompt JSON: ${BUNDLE_DIR}/node-a/agent-prompt.json"
echo "Node C prompt JSON: ${BUNDLE_DIR}/node-c/agent-prompt.json"
