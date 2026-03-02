#!/usr/bin/env bash
# Grand Unified AI Home Lab — Install OpenClaw on Node C (Fedora 44 cosmic nightly / Intel Arc A770)
#
# This script provisions Node C for OpenClaw and deploys the container.
# After running it, OpenClaw is reachable at http://<NODE_C_IP>:18789.
# Ollama (local, port 11434) is used as the primary AI backend.
# LiteLLM on Node B provides cloud model fallbacks.
#
# Usage:
#   ./scripts/install-openclaw-node-c.sh                # full setup + deploy
#   ./scripts/install-openclaw-node-c.sh --no-deploy    # prepare only
#   ./scripts/install-openclaw-node-c.sh --status       # check if running
#
# Prerequisites:
#   - SSH key-based access to Node C (root@192.168.1.6 by default)
#   - openssl available locally for token generation
#   - Node C running Ollama (docker compose -f node-c-arc/docker-compose.yml up -d)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
source "${REPO_ROOT}/scripts/lib-inventory.sh"
load_inventory "$REPO_ROOT"

NO_DEPLOY=false
STATUS_ONLY=false
for arg in "$@"; do
  [[ "$arg" == "--no-deploy" ]] && NO_DEPLOY=true
  [[ "$arg" == "--status" ]]    && STATUS_ONLY=true
done

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }
step() { echo ""; echo -e "${BOLD}$1${NC}"; echo ""; }

# ── Configuration ─────────────────────────────────────────────────────────────
OPENCLAW_DIR="/opt/openclaw"
HOMELAB_DIR="/opt/openclaw/homelab"
SSH_USER="${NODE_C_SSH_USER:-root}"
SSH_HOST="${NODE_C_IP}"

ssh_run() {
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes \
    "${SSH_USER}@${SSH_HOST}" "$@" 2>&1
}

# ── Status check ──────────────────────────────────────────────────────────────
if [ "$STATUS_ONLY" = true ]; then
  echo ""
  echo "Checking OpenClaw status on Node C (${SSH_HOST})..."
  echo ""

  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${SSH_HOST}:18789/" 2>/dev/null || echo "000")
  if [[ "$code" =~ ^2 ]]; then
    ok "OpenClaw is running (HTTP ${code})"
    ok "Control UI: http://${SSH_HOST}:18789/"
  elif [ "$code" = "000" ]; then
    err "OpenClaw is not reachable at http://${SSH_HOST}:18789/"
  else
    warn "OpenClaw returned HTTP ${code}"
  fi

  if ssh_run "docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null | grep -q openclaw-gateway" &>/dev/null; then
    container_status=$(ssh_run "docker ps --format '{{.Status}}' --filter name=openclaw-gateway" 2>/dev/null)
    ok "Container: openclaw-gateway (${container_status})"
  else
    warn "Container openclaw-gateway not found on Node C"
  fi
  exit 0
fi

# ── Main flow ─────────────────────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║   Install OpenClaw on Node C (Intel Arc / Fedora 44 cosmic)   ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "  Target:  ${SSH_USER}@${SSH_HOST}"
echo "  Data:    ${OPENCLAW_DIR}"
echo "  Compose: ${HOMELAB_DIR}/openclaw.yml"
echo ""

# ── Step 1: Validate prerequisites ───────────────────────────────────────────
step "Step 1 — Validate prerequisites"

ERRORS=0

if is_missing_or_placeholder_ip "$SSH_HOST"; then
  err "Node C IP is not configured (currently: ${SSH_HOST})"
  info "Set NODE_C_IP in config/node-inventory.env"
  exit 1
fi
ok "Node C IP: ${SSH_HOST}"

if command -v openssl &>/dev/null; then
  ok "openssl available"
else
  err "openssl not found — needed for token generation"
  exit 1
fi

if command -v ssh &>/dev/null; then
  ok "SSH client available"
else
  err "SSH client not found"
  exit 1
fi

for f in node-c-arc/openclaw.yml node-c-arc/openclaw.json openclaw/skill-kvm.md openclaw/skill-deploy.md; do
  if [ -f "$f" ]; then
    ok "Source file: $f"
  else
    err "Missing source file: $f"
    ((ERRORS++))
  fi
done

if [ "$ERRORS" -gt 0 ]; then
  err "Fix the errors above and try again"
  exit 1
fi

# ── Step 2: Test SSH connectivity ─────────────────────────────────────────────
step "Step 2 — Test SSH to Node C"

if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
     "${SSH_USER}@${SSH_HOST}" true &>/dev/null; then
  ok "SSH to ${SSH_USER}@${SSH_HOST} -- connected"
else
  err "SSH to ${SSH_USER}@${SSH_HOST} -- FAILED"
  echo ""
  echo "  Set up SSH key-based auth:"
  echo ""
  echo "    [ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519"
  echo "    ssh-copy-id ${SSH_USER}@${SSH_HOST}"
  echo ""
  echo "  Then run this script again."
  exit 1
fi

info "Checking Docker on Node C..."
if ssh_run "docker --version" &>/dev/null; then
  DOCKER_VER=$(ssh_run "docker --version 2>/dev/null" | head -1)
  ok "Docker on Node C: ${DOCKER_VER}"
else
  err "Docker not available on Node C"
  exit 1
fi

info "Checking Ollama on Node C..."
if ssh_run "curl -fsS http://localhost:11434/api/version" &>/dev/null; then
  ok "Ollama is running on Node C (port 11434)"
else
  warn "Ollama not responding — make sure Node C Ollama stack is running:"
  warn "  cd node-c-arc && docker compose up -d"
  warn "Continuing anyway (OpenClaw will retry Ollama automatically)..."
fi

# ── Step 3: Generate tokens ──────────────────────────────────────────────────
step "Step 3 — Generate tokens"

EXISTING_TOKEN=""
if ssh_run "test -f ${OPENCLAW_DIR}/.env" &>/dev/null; then
  EXISTING_TOKEN=$(ssh_run "grep OPENCLAW_GATEWAY_TOKEN ${OPENCLAW_DIR}/.env 2>/dev/null" | cut -d= -f2 || true)
fi

if [ -n "$EXISTING_TOKEN" ]; then
  warn "Existing OpenClaw .env found on Node C — reusing tokens"
  OPENCLAW_TOKEN="$EXISTING_TOKEN"
  KVM_OPERATOR_TOKEN=$(ssh_run "grep KVM_OPERATOR_TOKEN ${OPENCLAW_DIR}/.env 2>/dev/null" | cut -d= -f2 || openssl rand -hex 24)
  ok "Reusing existing OPENCLAW_GATEWAY_TOKEN"
else
  OPENCLAW_TOKEN=$(openssl rand -hex 24)
  KVM_OPERATOR_TOKEN=$(openssl rand -hex 24)
  ok "Generated OPENCLAW_GATEWAY_TOKEN"
  ok "Generated KVM_OPERATOR_TOKEN"
fi

# ── Step 4: Create directories on Node C ─────────────────────────────────────
step "Step 4 — Create directories on Node C"

ssh_run "mkdir -p ${OPENCLAW_DIR}/{config,workspace,homebrew} ${HOMELAB_DIR}"
ok "Created ${OPENCLAW_DIR}/{config,workspace,homebrew}"
ok "Created ${HOMELAB_DIR}"

# ── Step 5: Upload configuration files ───────────────────────────────────────
step "Step 5 — Upload config files"

scp -o StrictHostKeyChecking=no \
  node-c-arc/openclaw.json \
  "${SSH_USER}@${SSH_HOST}:${OPENCLAW_DIR}/config/openclaw.json"
ok "Uploaded openclaw.json"

scp -o StrictHostKeyChecking=no \
  openclaw/skill-kvm.md \
  openclaw/skill-deploy.md \
  "${SSH_USER}@${SSH_HOST}:${OPENCLAW_DIR}/workspace/"
ok "Uploaded skill-kvm.md and skill-deploy.md"

scp -o StrictHostKeyChecking=no \
  node-c-arc/openclaw.yml \
  "${SSH_USER}@${SSH_HOST}:${HOMELAB_DIR}/openclaw.yml"
ok "Uploaded openclaw.yml"

# ── Step 6: Create AGENTS.md ─────────────────────────────────────────────────
step "Step 6 — Create workspace AGENTS.md"

ssh_run "cat > ${OPENCLAW_DIR}/workspace/AGENTS.md" <<AGENTEOF
# OpenClaw Agent Context — Node C (Intel Arc A770)

You are an AI assistant running on Node C, the Intel Arc A770 GPU workstation in a
multi-node home AI lab. Your primary model is Ollama (local, port 11434). Use
LiteLLM on Node B as a fallback for tasks that need larger context or cloud models.

## Lab Nodes

- **Node A** (${NODE_A_IP}): Brain / vLLM model host, Dashboard (port 3099), KVM Operator (port 5000)
- **Node B** (${NODE_B_IP}): Unraid / LiteLLM gateway (port 4000), Portainer (port 9000)
- **Node C** (${SSH_HOST}): Fedora 44 (cosmic nightly) / Intel Arc A770 — THIS NODE
  - Ollama: port 11434 (llava, llama3, etc.)
  - Chimera Face (Open WebUI): port 3000
  - OpenClaw: port 18789 (this service)
- **Node D** (${NODE_D_IP:-192.168.1.149}): Home Assistant (port 8123)
- **Node E** (${NODE_E_IP:-192.168.1.116}): Sentinel NVR

## Available Skills

Read these files for detailed API documentation:
- \`skill-kvm.md\` — Control remote machines via NanoKVM Cube devices
- \`skill-deploy.md\` — Deploy Docker stacks, manage Portainer, run health checks

## Local Capabilities

- Vision tasks: use \`ollama/llava:latest\` for image analysis
- Audio transcription: Whisper models available via Ollama
- Docker management: Docker socket is mounted — you can list/start/stop containers

## Safety Rules

1. Always verify the current state before making changes (screenshot, health check)
2. Never run commands matching the KVM denylist
3. Request confirmation for destructive actions
4. Keep REQUIRE_APPROVAL=true unless explicitly told otherwise
AGENTEOF
ok "AGENTS.md created"

# ── Step 7: Create .env file ─────────────────────────────────────────────────
step "Step 7 — Create .env file on Node C"

ssh_run "cat > ${OPENCLAW_DIR}/.env" <<ENVEOF
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_TOKEN}
OLLAMA_API_KEY=ollama
LITELLM_API_KEY=sk-master-key
KVM_OPERATOR_URL=http://${NODE_A_IP}:5000
KVM_OPERATOR_TOKEN=${KVM_OPERATOR_TOKEN}
# HOME_ASSISTANT_URL=http://${NODE_D_IP:-192.168.1.149}:8123
# HOME_ASSISTANT_TOKEN=
# ANTHROPIC_API_KEY=
# OPENAI_API_KEY=
# GEMINI_API_KEY=
# OPENROUTER_API_KEY=
ENVEOF
ok ".env created at ${OPENCLAW_DIR}/.env"

ssh_run "cp ${OPENCLAW_DIR}/.env ${HOMELAB_DIR}/.env"
ok ".env copied to ${HOMELAB_DIR}/.env"

# ── Step 8: Sync KVM Operator token ──────────────────────────────────────────
step "Step 8 — Sync KVM Operator token (local)"

KVM_TOKEN_PLACEHOLDER="change-me-use-openssl-rand-hex-24"

if [ -f "kvm-operator/.env" ]; then
  if grep -q "${KVM_TOKEN_PLACEHOLDER}" kvm-operator/.env; then
    sed -i "s|${KVM_TOKEN_PLACEHOLDER}|${KVM_OPERATOR_TOKEN}|g" kvm-operator/.env
    ok "KVM Operator token updated in kvm-operator/.env"
  else
    warn "kvm-operator/.env already has a custom token — not overwriting"
    info "To sync: set KVM_OPERATOR_TOKEN=${KVM_OPERATOR_TOKEN} in kvm-operator/.env"
  fi
elif [ -f "kvm-operator/.env.example" ]; then
  cp kvm-operator/.env.example kvm-operator/.env
  sed -i "s|${KVM_TOKEN_PLACEHOLDER}|${KVM_OPERATOR_TOKEN}|g" kvm-operator/.env
  ok "Created kvm-operator/.env with synced token"
else
  warn "kvm-operator/.env.example not found — skipping KVM token sync"
fi

# ── Step 9: Deploy (or print Portainer instructions) ─────────────────────────
step "Step 9 — Deploy OpenClaw on Node C"

if [ "$NO_DEPLOY" = true ]; then
  echo ""
  echo "  --no-deploy flag set. To deploy manually on Node C:"
  echo ""
  echo "    ssh ${SSH_USER}@${SSH_HOST}"
  echo "    cd ${HOMELAB_DIR}"
  echo "    docker compose -f openclaw.yml --env-file ${OPENCLAW_DIR}/.env up -d"
  echo ""
else
  info "Pulling OpenClaw image on Node C..."
  ssh_run "cd ${HOMELAB_DIR} && docker compose -f openclaw.yml --env-file ${OPENCLAW_DIR}/.env pull" || {
    err "Docker pull failed"
    info "Check: ssh ${SSH_USER}@${SSH_HOST} 'cd ${HOMELAB_DIR} && docker compose -f openclaw.yml pull'"
    exit 1
  }
  ok "Image pulled"

  info "Starting OpenClaw container..."
  ssh_run "cd ${HOMELAB_DIR} && docker compose -f openclaw.yml --env-file ${OPENCLAW_DIR}/.env up -d" || {
    err "Docker compose up failed"
    exit 1
  }
  ok "Container started"

  info "Waiting for OpenClaw to be ready (can take 30-60s)..."
  MAX_HEALTH_RETRIES=15
  retry_count=0
  while [ $retry_count -lt $MAX_HEALTH_RETRIES ]; do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${SSH_HOST}:18789/" 2>/dev/null || echo "000")
    if [[ "$code" =~ ^2 ]]; then
      ok "OpenClaw is healthy (HTTP ${code})"
      break
    fi
    retry_count=$((retry_count+1))
    info "  Attempt ${retry_count}/${MAX_HEALTH_RETRIES} — HTTP ${code}, waiting 5s..."
    sleep 5
  done

  if [ $retry_count -ge $MAX_HEALTH_RETRIES ]; then
    warn "OpenClaw did not respond in time — it may still be starting"
    info "Check logs: ssh ${SSH_USER}@${SSH_HOST} docker logs openclaw-gateway --tail 30"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "  ${GREEN}OpenClaw on Node C — deployment complete!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Control UI:"
echo "    http://${SSH_HOST}:18789/?token=${OPENCLAW_TOKEN}"
echo ""
echo "  Save these tokens:"
echo "    OPENCLAW_GATEWAY_TOKEN = ${OPENCLAW_TOKEN}"
echo "    KVM_OPERATOR_TOKEN     = ${KVM_OPERATOR_TOKEN}"
echo ""
echo "  Connect Chimera Face (Open WebUI on :3000) to OpenClaw:"
echo "    Settings → Connections → Add OpenAI-compatible API"
echo "    URL:   http://${SSH_HOST}:18789/v1"
echo "    Key:   ${OPENCLAW_TOKEN}"
echo "    Model: openclaw:main"
echo ""
echo "  Next steps:"
echo "    1. Open the Control UI link above"
echo "    2. Verify Ollama: node dist/index.js models list (in container console)"
echo "    3. Set your model: /model ollama/<model-name>  (in chat)"
echo "    4. Try: 'What models are available on Node C?'"
echo ""
echo "  Full docs: docs/11_OPENCLAW_KVM_GUIDEBOOK.md"
echo ""
