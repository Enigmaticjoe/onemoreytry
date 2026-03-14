#!/usr/bin/env bash
# Grand Unified AI Home Lab — Install OpenClaw as Deployment Assistant
#
# This script bootstraps OpenClaw with KVM privileges and deployment skills
# on Node B (Unraid). After running this, OpenClaw can deploy and manage
# all other nodes in the lab.
#
# Usage:
#   ./scripts/install-openclaw-deployer.sh
#
# Prerequisites:
#   - SSH access to Node B (see GUIDEBOOK.md §0.4)
#   - openssl available locally for token generation
#   - vLLM or another model provider running on Node B

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
source "${REPO_ROOT}/scripts/lib-inventory.sh"
load_inventory "$REPO_ROOT"
source "${REPO_ROOT}/scripts/lib-colors.sh"
ok()   { echo -e "${GREEN}✓${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
info() { echo -e "${CYAN}→${NC} $1"; }

# Default placeholder in kvm-operator/.env.example — used to detect unconfigured installs
KVM_TOKEN_PLACEHOLDER="change-me-use-openssl-rand-hex-24"

# ── Configuration ─────────────────────────────────────────────────────────────
APPDATA_DIR="${APPDATA_DIR:-/mnt/user/appdata}"

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║   Install OpenClaw as Deployment Assistant         ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "  Node B (Unraid): ${NODE_B_SSH_USER}@${NODE_B_IP}"
echo "  Appdata:         ${APPDATA_DIR}/openclaw"
echo ""

# ── Step 1: Test SSH access ───────────────────────────────────────────────────
info "Testing SSH access to Node B…"
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
     "${NODE_B_SSH_USER}@${NODE_B_IP}" true 2>/dev/null; then
  ok "SSH access confirmed"
else
  err "SSH to ${NODE_B_SSH_USER}@${NODE_B_IP} failed."
  echo ""
  echo "  Set up key-based SSH auth first:"
  echo "    ssh-copy-id ${NODE_B_SSH_USER}@${NODE_B_IP}"
  exit 1
fi

# ── Step 2: Generate tokens ───────────────────────────────────────────────────
info "Generating gateway token…"
OPENCLAW_TOKEN=$(openssl rand -hex 24)
KVM_OPERATOR_TOKEN=$(openssl rand -hex 24)
ok "Tokens generated"

# ── Step 3: Create appdata directories on Node B ──────────────────────────────
info "Creating appdata directories on Node B…"
ssh -o StrictHostKeyChecking=no "${NODE_B_SSH_USER}@${NODE_B_IP}" \
  "mkdir -p ${APPDATA_DIR}/openclaw/{config,workspace,homebrew}"
ok "Directories created"

# ── Step 4: Copy and configure openclaw.json ─────────────────────────────────
info "Uploading openclaw.json to Node B…"
scp -o StrictHostKeyChecking=no \
  openclaw/openclaw.json \
  "${NODE_B_SSH_USER}@${NODE_B_IP}:${APPDATA_DIR}/openclaw/config/openclaw.json"
ok "openclaw.json uploaded"

# ── Step 5: Copy skill files to workspace ────────────────────────────────────
info "Uploading skill files to Node B workspace…"
scp -o StrictHostKeyChecking=no \
  openclaw/skill-kvm.md \
  openclaw/skill-deploy.md \
  "${NODE_B_SSH_USER}@${NODE_B_IP}:${APPDATA_DIR}/openclaw/workspace/"
ok "Skill files uploaded"

# ── Step 6: Create AGENTS.md ──────────────────────────────────────────────────
info "Creating AGENTS.md in workspace…"
ssh -o StrictHostKeyChecking=no "${NODE_B_SSH_USER}@${NODE_B_IP}" \
  "cat > ${APPDATA_DIR}/openclaw/workspace/AGENTS.md" <<AGENTEOF
# OpenClaw Agent Context — Homelab Deployment Assistant

You are an AI assistant managing a multi-node home AI lab. Your primary job is to help
deploy, administer, and troubleshoot the following nodes:

- **Node A** (${NODE_A_IP}): Brain / vLLM model host, Dashboard (port 3099), KVM Operator (port 5000)
- **Node B** (${NODE_B_IP}): Unraid / LiteLLM gateway (port 4000), OpenClaw (port 18789), Portainer (port 9000)
- **Node C** (${NODE_C_IP:-set-in-inventory}): Fedora 44 (cosmic nightly) / Intel Arc A770, Ollama (port 11434), Chimera Face UI (port 3000)
- **Node D**: Home Assistant
- **Node E**: Sentinel NVR

## Available Skills

Read these files for detailed API documentation:
- `skill-kvm.md` — Control remote machines via NanoKVM Cube devices
- `skill-deploy.md` — Deploy Docker stacks, manage Portainer, run health checks

## Common Tasks

### Check all nodes are healthy
Use the health endpoints from skill-deploy.md to check each node.

### Deploy or restart a service
Use the appropriate Docker Compose command via SSH or the KVM operator.

### KVM task (control a remote machine screen)
Use skill-kvm.md workflows — always take a screenshot first before acting.

## Safety Rules

1. Always verify the current state before making changes (screenshot, health check)
2. Never run commands matching the KVM denylist
3. Request confirmation for destructive actions
4. Keep REQUIRE_APPROVAL=true unless explicitly told otherwise
AGENTEOF
ok "AGENTS.md created"

# ── Step 7: Create .env file ──────────────────────────────────────────────────
info "Creating OpenClaw .env file on Node B…"
ssh -o StrictHostKeyChecking=no "${NODE_B_SSH_USER}@${NODE_B_IP}" \
  "cat > ${APPDATA_DIR}/openclaw/.env" <<ENVEOF
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_TOKEN}
VLLM_API_KEY=vllm-local
KVM_OPERATOR_URL=http://${NODE_A_IP}:5000
KVM_OPERATOR_TOKEN=${KVM_OPERATOR_TOKEN}
# ANTHROPIC_API_KEY=
# OPENAI_API_KEY=
# HOME_ASSISTANT_URL=
# HOME_ASSISTANT_TOKEN=
# UNRAID_API_KEY=
ENVEOF
ok ".env file created"

# ── Step 8: Upload docker-compose.yml ────────────────────────────────────────
info "Uploading OpenClaw docker-compose.yml to Node B…"
ssh -o StrictHostKeyChecking=no "${NODE_B_SSH_USER}@${NODE_B_IP}" \
  "mkdir -p ${APPDATA_DIR}/homelab/openclaw"
scp -o StrictHostKeyChecking=no \
  openclaw/docker-compose.yml \
  "${NODE_B_SSH_USER}@${NODE_B_IP}:${APPDATA_DIR}/homelab/openclaw/docker-compose.yml"
ok "docker-compose.yml uploaded"

# ── Step 9: Deploy OpenClaw container ────────────────────────────────────────
info "Deploying OpenClaw container on Node B…"
ssh -o StrictHostKeyChecking=no "${NODE_B_SSH_USER}@${NODE_B_IP}" \
  "cd ${APPDATA_DIR}/homelab/openclaw && \
   docker compose --env-file ${APPDATA_DIR}/openclaw/.env pull && \
   docker compose --env-file ${APPDATA_DIR}/openclaw/.env up -d"
ok "OpenClaw container deployed"

# ── Step 10: Update KVM Operator token (local) ───────────────────────────────
if [ -f "kvm-operator/.env" ]; then
  info "Updating KVM_OPERATOR_TOKEN in kvm-operator/.env…"
  # Only update if current value is the placeholder
  if grep -q "${KVM_TOKEN_PLACEHOLDER}" kvm-operator/.env; then
    sed -i "s|${KVM_TOKEN_PLACEHOLDER}|${KVM_OPERATOR_TOKEN}|g" kvm-operator/.env
    ok "KVM Operator token updated in kvm-operator/.env"
  else
    warn "kvm-operator/.env already has a custom token — not overwriting"
    info "To connect OpenClaw to KVM Operator, set KVM_OPERATOR_TOKEN=${KVM_OPERATOR_TOKEN} in kvm-operator/.env"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo -e "${GREEN}  OpenClaw deployment complete!${NC}"
echo "═══════════════════════════════════════════════════"
echo ""
echo "  🌐 Control UI:"
echo "     http://${NODE_B_IP}:18789/?token=${OPENCLAW_TOKEN}"
echo ""
echo "  🔑 Save these tokens securely:"
echo "     OPENCLAW_GATEWAY_TOKEN = ${OPENCLAW_TOKEN}"
echo "     KVM_OPERATOR_TOKEN     = ${KVM_OPERATOR_TOKEN}"
echo ""
echo "  📋 Next steps:"
echo "     1. Wait ~30s for OpenClaw to start"
echo "     2. Open the Control UI link above"
echo "     3. In OpenClaw console: node dist/index.js models list"
echo "     4. Set your vLLM model ID in openclaw.json if needed"
echo "     5. Start chatting — try: 'Give me a status report of all my AI nodes'"
echo ""
echo "  📖 See GUIDEBOOK.md Chapter 5 for full setup details"
echo ""
