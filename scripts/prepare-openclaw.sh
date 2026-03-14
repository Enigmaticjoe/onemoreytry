#!/usr/bin/env bash
# Grand Unified AI Home Lab — Prepare OpenClaw for Portainer Stack Install
#
# This is the ONE script that fully prepares Node B (Unraid) for OpenClaw.
# It handles SSH connectivity testing, directory creation, config upload,
# token generation, .env creation, and optional Docker deployment.
#
# After running this script you can either:
#   A) Let it auto-deploy via docker compose (default)
#   B) Paste the docker-compose.yml into Portainer > Stacks > Add Stack
#
# Usage:
#   ./scripts/prepare-openclaw.sh                # full setup + deploy
#   ./scripts/prepare-openclaw.sh --no-deploy    # prepare only, deploy via Portainer
#   ./scripts/prepare-openclaw.sh --status       # check if OpenClaw is running
#
# Prerequisites:
#   - SSH key-based access to Node B (Unraid)
#   - openssl available locally for token generation

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
source "${REPO_ROOT}/scripts/lib-inventory.sh"
load_inventory "$REPO_ROOT"
source "${REPO_ROOT}/scripts/lib-colors.sh"

NO_DEPLOY=false
STATUS_ONLY=false
for arg in "$@"; do
  [[ "$arg" == "--no-deploy" ]] && NO_DEPLOY=true
  [[ "$arg" == "--status" ]]    && STATUS_ONLY=true
done


ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }
step() { echo ""; echo -e "${BOLD}$1${NC}"; echo ""; }

# ── Configuration ─────────────────────────────────────────────────────────────
APPDATA_DIR="${APPDATA_DIR:-/mnt/user/appdata}"
OPENCLAW_DIR="${APPDATA_DIR}/openclaw"
HOMELAB_DIR="${APPDATA_DIR}/homelab/openclaw"
SSH_USER="${NODE_B_SSH_USER:-root}"
SSH_HOST="${NODE_B_IP}"

ssh_run() {
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes \
    "${SSH_USER}@${SSH_HOST}" "$@" 2>&1
}

# ── Status check ──────────────────────────────────────────────────────────────
if [ "$STATUS_ONLY" = true ]; then
  echo ""
  echo "Checking OpenClaw status on Node B (${SSH_HOST})..."
  echo ""

  # Check HTTP
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${SSH_HOST}:18789/" 2>/dev/null || echo "000")
  if [[ "$code" =~ ^2 ]]; then
    ok "OpenClaw is running (HTTP ${code})"
    ok "Control UI: http://${SSH_HOST}:18789/"
  elif [ "$code" = "000" ]; then
    err "OpenClaw is not reachable at http://${SSH_HOST}:18789/"
  else
    warn "OpenClaw returned HTTP ${code}"
  fi

  # Check container
  if ssh_run "docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null | grep -q openclaw-gateway"; then
    container_status=$(ssh_run "docker ps --format '{{.Status}}' --filter name=openclaw-gateway" 2>/dev/null)
    ok "Container: openclaw-gateway (${container_status})"
  else
    warn "Container openclaw-gateway not found on Node B"
  fi
  exit 0
fi

# ── Main flow ─────────────────────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║   Prepare OpenClaw for Portainer Stack Install        ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "  Target:    ${SSH_USER}@${SSH_HOST}"
echo "  Appdata:   ${OPENCLAW_DIR}"
echo "  Compose:   ${HOMELAB_DIR}/docker-compose.yml"
echo ""

# ── Step 1: Validate prerequisites ───────────────────────────────────────────
step "Step 1 — Validate prerequisites"

ERRORS=0

# Check Node B IP is set
if is_missing_or_placeholder_ip "$SSH_HOST"; then
  err "Node B IP is not configured (currently: ${SSH_HOST})"
  info "Set NODE_B_IP in config/node-inventory.env or deploy-gui Settings"
  exit 1
fi
ok "Node B IP: ${SSH_HOST}"

# Check openssl
if command -v openssl &>/dev/null; then
  ok "openssl available"
else
  err "openssl not found — needed for token generation"
  exit 1
fi

# Check SSH
if command -v ssh &>/dev/null; then
  ok "SSH client available"
else
  err "SSH client not found"
  exit 1
fi

# Check source files exist
for f in openclaw/docker-compose.yml openclaw/openclaw.json openclaw/skill-kvm.md openclaw/skill-deploy.md; do
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
step "Step 2 — Test SSH to Node B"

if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
     "${SSH_USER}@${SSH_HOST}" true &>/dev/null; then
  ok "SSH to ${SSH_USER}@${SSH_HOST} -- connected"
else
  err "SSH to ${SSH_USER}@${SSH_HOST} -- FAILED"
  echo ""
  echo "  Set up SSH key-based auth:"
  echo ""
  echo "    # Generate a key if you don't have one:"
  echo "    [ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519"
  echo ""
  echo "    # Copy key to Unraid:"
  echo "    ssh-copy-id ${SSH_USER}@${SSH_HOST}"
  echo ""
  echo "    # For Unraid, ensure SSH is enabled:"
  echo "    Settings > Management Access > SSH > Enable"
  echo ""
  echo "  Then run this script again."
  exit 1
fi

# Test Docker access on Node B
info "Checking Docker on Node B..."
if ssh_run "docker --version" &>/dev/null; then
  DOCKER_VER=$(ssh_run "docker --version 2>/dev/null" | head -1)
  ok "Docker on Node B: ${DOCKER_VER}"
else
  err "Docker not available on Node B"
  exit 1
fi

# ── Step 3: Generate tokens ──────────────────────────────────────────────────
step "Step 3 — Generate tokens"

# Check if tokens already exist on Node B
EXISTING_TOKEN=""
if ssh_run "test -f ${OPENCLAW_DIR}/.env" &>/dev/null; then
  EXISTING_TOKEN=$(ssh_run "grep OPENCLAW_GATEWAY_TOKEN ${OPENCLAW_DIR}/.env 2>/dev/null" | cut -d= -f2 || true)
fi

if [ -n "$EXISTING_TOKEN" ] && [ "$EXISTING_TOKEN" != "" ]; then
  warn "Existing OpenClaw .env found on Node B — reusing tokens"
  OPENCLAW_TOKEN="$EXISTING_TOKEN"
  KVM_OPERATOR_TOKEN=$(ssh_run "grep KVM_OPERATOR_TOKEN ${OPENCLAW_DIR}/.env 2>/dev/null" | cut -d= -f2 || openssl rand -hex 24)
  ok "Reusing existing OPENCLAW_GATEWAY_TOKEN"
else
  OPENCLAW_TOKEN=$(openssl rand -hex 24)
  KVM_OPERATOR_TOKEN=$(openssl rand -hex 24)
  ok "Generated OPENCLAW_GATEWAY_TOKEN"
  ok "Generated KVM_OPERATOR_TOKEN"
fi

# ── Step 4: Create directories on Node B ─────────────────────────────────────
step "Step 4 — Create directories on Node B"

ssh_run "mkdir -p ${OPENCLAW_DIR}/{config,workspace,homebrew} ${HOMELAB_DIR}"
ok "Created ${OPENCLAW_DIR}/{config,workspace,homebrew}"
ok "Created ${HOMELAB_DIR}"

# ── Step 5: Upload configuration files ───────────────────────────────────────
step "Step 5 — Upload config files"

# openclaw.json
scp -o StrictHostKeyChecking=no \
  openclaw/openclaw.json \
  "${SSH_USER}@${SSH_HOST}:${OPENCLAW_DIR}/config/openclaw.json"
ok "Uploaded openclaw.json"

# Skill files
scp -o StrictHostKeyChecking=no \
  openclaw/skill-kvm.md \
  openclaw/skill-deploy.md \
  "${SSH_USER}@${SSH_HOST}:${OPENCLAW_DIR}/workspace/"
ok "Uploaded skill-kvm.md and skill-deploy.md"

# docker-compose.yml
scp -o StrictHostKeyChecking=no \
  openclaw/docker-compose.yml \
  "${SSH_USER}@${SSH_HOST}:${HOMELAB_DIR}/docker-compose.yml"
ok "Uploaded docker-compose.yml"

# ── Step 6: Create AGENTS.md ─────────────────────────────────────────────────
step "Step 6 — Create workspace AGENTS.md"

ssh_run "cat > ${OPENCLAW_DIR}/workspace/AGENTS.md" <<AGENTEOF
# OpenClaw Agent Context — Homelab Deployment Assistant

You are an AI assistant managing a multi-node home AI lab. Your primary job is to help
deploy, administer, and troubleshoot the following nodes:

- **Node A** (${NODE_A_IP}): Brain / vLLM model host, Dashboard (port 3099), KVM Operator (port 5000)
- **Node B** (${NODE_B_IP}): Unraid / LiteLLM gateway (port 4000), OpenClaw (port 18789), Portainer (port 9000)
- **Node C** (${NODE_C_IP:-set-in-inventory}): Fedora 44 (cosmic nightly) / Intel Arc A770, Ollama (port 11434), Chimera Face UI (port 3000)
- **Node D** (${NODE_D_IP:-not-set}): Home Assistant
- **Node E** (${NODE_E_IP:-not-set}): Sentinel NVR (Blue Iris)

## Available Skills

Read these files for detailed API documentation:
- \`skill-kvm.md\` — Control remote machines via NanoKVM Cube devices
- \`skill-deploy.md\` — Deploy Docker stacks, manage Portainer, run health checks

## Safety Rules

1. Always verify the current state before making changes (screenshot, health check)
2. Never run commands matching the KVM denylist
3. Request confirmation for destructive actions
4. Keep REQUIRE_APPROVAL=true unless explicitly told otherwise
AGENTEOF
ok "AGENTS.md created"

# ── Step 7: Create .env file ─────────────────────────────────────────────────
step "Step 7 — Create .env file on Node B"

ssh_run "cat > ${OPENCLAW_DIR}/.env" <<ENVEOF
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_TOKEN}
VLLM_API_KEY=vllm-local
KVM_OPERATOR_URL=http://${NODE_A_IP}:5000
KVM_OPERATOR_TOKEN=${KVM_OPERATOR_TOKEN}
# ANTHROPIC_API_KEY=
# OPENAI_API_KEY=
# HOME_ASSISTANT_URL=http://${NODE_D_IP:-192.168.1.149}:8123
# HOME_ASSISTANT_TOKEN=
# UNRAID_API_KEY=
ENVEOF
ok ".env file created at ${OPENCLAW_DIR}/.env"

# Also create a copy for docker compose env-file reference
ssh_run "cp ${OPENCLAW_DIR}/.env ${HOMELAB_DIR}/.env"
ok ".env copied to ${HOMELAB_DIR}/.env"

# ── Step 8: Update local KVM Operator token ──────────────────────────────────
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

# ── Step 9: Deploy (or instruct for Portainer) ───────────────────────────────
step "Step 9 — Deploy OpenClaw"

if [ "$NO_DEPLOY" = true ]; then
  echo ""
  echo "  --no-deploy flag set. To deploy via Portainer:"
  echo ""
  echo "  1. Open Portainer: http://${SSH_HOST}:9000"
  echo "  2. Go to Stacks > Add Stack"
  echo "  3. Name: openclaw"
  echo "  4. Paste contents of: openclaw/docker-compose.yml"
  echo "  5. Add environment variables from: ${OPENCLAW_DIR}/.env"
  echo "  6. Deploy the stack"
  echo ""
else
  info "Pulling OpenClaw image on Node B..."
  ssh_run "cd ${HOMELAB_DIR} && docker compose --env-file ${OPENCLAW_DIR}/.env pull" || {
    err "Docker pull failed"
    info "Check: ssh ${SSH_USER}@${SSH_HOST} 'cd ${HOMELAB_DIR} && docker compose --env-file ${OPENCLAW_DIR}/.env pull'"
    exit 1
  }
  ok "Image pulled"

  info "Starting OpenClaw container..."
  ssh_run "cd ${HOMELAB_DIR} && docker compose --env-file ${OPENCLAW_DIR}/.env up -d" || {
    err "Docker compose up failed"
    exit 1
  }
  ok "Container started"

  # Wait for health
  info "Waiting for OpenClaw to be ready (can take 30-60s)..."
  local_i=0
  while [ $local_i -lt 15 ]; do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${SSH_HOST}:18789/" 2>/dev/null || echo "000")
    if [[ "$code" =~ ^2 ]]; then
      ok "OpenClaw is healthy (HTTP ${code})"
      break
    fi
    local_i=$((local_i+1))
    info "  Attempt ${local_i}/15 -- HTTP ${code}, waiting 5s..."
    sleep 5
  done

  if [ $local_i -ge 15 ]; then
    warn "OpenClaw did not respond in time — it may still be starting"
    info "Check logs: ssh ${SSH_USER}@${SSH_HOST} docker logs openclaw-gateway --tail 30"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "  ${GREEN}OpenClaw preparation complete!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Control UI:"
echo "    http://${SSH_HOST}:18789/?token=${OPENCLAW_TOKEN}"
echo ""
echo "  Save these tokens:"
echo "    OPENCLAW_GATEWAY_TOKEN = ${OPENCLAW_TOKEN}"
echo "    KVM_OPERATOR_TOKEN     = ${KVM_OPERATOR_TOKEN}"
echo ""
echo "  Files on Node B:"
echo "    Config:    ${OPENCLAW_DIR}/config/openclaw.json"
echo "    Workspace: ${OPENCLAW_DIR}/workspace/"
echo "    Env:       ${OPENCLAW_DIR}/.env"
echo "    Compose:   ${HOMELAB_DIR}/docker-compose.yml"
echo ""
echo "  Next steps:"
echo "    1. Open the Control UI link above"
echo "    2. Verify vLLM: node dist/index.js models list (in container console)"
echo "    3. Try: 'Give me a status report of all my AI nodes'"
echo ""
echo "  Full docs: GUIDEBOOK.md Chapter 5"
echo ""
