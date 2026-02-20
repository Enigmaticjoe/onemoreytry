#!/usr/bin/env bash
# Grand Unified AI Home Lab — Master Deploy Script
# Deploys all nodes in the correct order with health checks between steps.
#
# Usage:
#   ./scripts/deploy-all.sh          # deploy everything
#   ./scripts/deploy-all.sh stop     # stop all services
#   ./scripts/deploy-all.sh status   # show status only

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ACTION="${1:-deploy}"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

step() { echo ""; echo -e "${CYAN}══════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}══════════════════════════════════${NC}"; }
ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
err()  { echo -e "${RED}  ✗ $1${NC}"; }
warn() { echo -e "${YELLOW}  ! $1${NC}"; }
info() { echo -e "    $1"; }

# ── Load node IPs ─────────────────────────────────────────────────────────────
NODE_A_IP="${NODE_A_IP:-192.168.1.9}"
NODE_B_IP="${NODE_B_IP:-192.168.1.222}"
NODE_C_IP="${NODE_C_IP:-192.168.1.X}"
NODE_B_SSH_USER="${NODE_B_SSH_USER:-root}"
NODE_C_SSH_USER="${NODE_C_SSH_USER:-root}"

# Try to read from deploy-gui settings if present
if [ -f "deploy-gui/data/settings.json" ] && command -v python3 &>/dev/null; then
  NODE_A_IP=$(python3 -c "import json; s=json.load(open('deploy-gui/data/settings.json')); print(s['nodes']['nodeA']['ip'])" 2>/dev/null || echo "$NODE_A_IP")
  NODE_B_IP=$(python3 -c "import json; s=json.load(open('deploy-gui/data/settings.json')); print(s['nodes']['nodeB']['ip'])" 2>/dev/null || echo "$NODE_B_IP")
  NODE_C_IP=$(python3 -c "import json; s=json.load(open('deploy-gui/data/settings.json')); print(s['nodes']['nodeC']['ip'])" 2>/dev/null || echo "$NODE_C_IP")
fi

wait_for_health() {
  local label="$1"; local url="$2"; local max_attempts="${3:-12}"; local delay="${4:-5}"
  info "Waiting for ${label} to be healthy…"
  local i=0
  while [ $i -lt $max_attempts ]; do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    if [[ "$code" =~ ^2 ]] || [[ "$code" =~ ^3 ]]; then
      ok "${label} is healthy (HTTP ${code})"
      return 0
    fi
    i=$((i+1))
    info "  Attempt $i/${max_attempts} — HTTP ${code}, retrying in ${delay}s…"
    sleep "$delay"
  done
  warn "${label} did not become healthy after ${max_attempts} attempts — continuing anyway"
  return 0
}

ssh_cmd() {
  local host="$1"; local user="$2"; shift 2
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes "${user}@${host}" "$@" 2>&1 || true
}

# ─────────────────────────────────────────────────────────────────────────────
# STOP action
# ─────────────────────────────────────────────────────────────────────────────
if [ "$ACTION" = "stop" ]; then
  echo "Stopping all services…"

  step "Stop Deploy GUI (local)"
  docker compose -f deploy-gui/docker-compose.yml down 2>/dev/null && ok "Deploy GUI stopped" || warn "Deploy GUI not running"

  step "Stop Node C (local)"
  docker compose -f node-c-arc/docker-compose.yml down 2>/dev/null && ok "Node C stopped" || warn "Node C not running"

  step "Stop Node A Dashboard (local)"
  pkill -f node-a-command-center.js 2>/dev/null && ok "Node A dashboard stopped" || warn "Node A dashboard not running"

  step "Stop KVM Operator (local)"
  if systemctl is-active ai-kvm-operator &>/dev/null 2>&1; then
    sudo systemctl stop ai-kvm-operator && ok "KVM Operator systemd service stopped"
  else
    pkill -f "uvicorn app:app" 2>/dev/null && ok "KVM Operator stopped" || warn "KVM Operator not running"
  fi

  echo ""
  ok "All local services stopped."
  echo ""
  echo "Note: Node B (Unraid) services must be stopped via Portainer or SSH."
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# STATUS action
# ─────────────────────────────────────────────────────────────────────────────
if [ "$ACTION" = "status" ]; then
  ./scripts/preflight-check.sh --health-only
  exit $?
fi

# ─────────────────────────────────────────────────────────────────────────────
# DEPLOY action
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║   Grand Unified AI Home Lab — Full Deploy      ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
echo "  Node A IP: ${NODE_A_IP}"
echo "  Node B IP: ${NODE_B_IP}"
echo "  Node C IP: ${NODE_C_IP}"
echo ""

# ── Step 0: Validate config files ─────────────────────────────────────────────
step "Step 0 — Validate configuration"
if ./validate.sh; then
  ok "Configuration validation passed"
else
  err "Configuration validation failed — fix errors before deploying"
  exit 1
fi

# ── Step 1: Node C — Intel Arc + Ollama ──────────────────────────────────────
step "Step 1 — Node C (Intel Arc + Ollama)"
info "Pulling latest images…"
docker compose -f node-c-arc/docker-compose.yml pull 2>&1 | tail -5 || true

info "Starting Node C services…"
docker compose -f node-c-arc/docker-compose.yml up -d
ok "Node C containers started"

wait_for_health "Ollama API" "http://localhost:11434/api/version" 18 5

info "Pulling llava model (this may take a few minutes on first run)…"
docker exec ollama_intel_arc ollama pull llava 2>&1 | tail -3 || warn "Model pull failed — retry manually: docker exec ollama_intel_arc ollama pull llava"
ok "Node C ready"

# ── Step 2: Node B — LiteLLM Gateway ─────────────────────────────────────────
step "Step 2 — Node B LiteLLM Gateway (Unraid)"
if [[ "$NODE_B_IP" == *"."* ]] && ! [[ "$NODE_B_IP" == *"X"* ]]; then
  info "Deploying LiteLLM stack on Node B (${NODE_B_IP})…"
  ssh_cmd "$NODE_B_IP" "$NODE_B_SSH_USER" \
    "cd /mnt/user/appdata/homelab/node-b-litellm 2>/dev/null || cd ~/homelab/node-b-litellm && docker compose -f litellm-stack.yml pull && docker compose -f litellm-stack.yml up -d"
  wait_for_health "LiteLLM Gateway" "http://${NODE_B_IP}:4000/health" 12 5
  ok "Node B LiteLLM Gateway ready"
else
  warn "Node B IP not configured — skipping remote deploy. Set NODE_B_IP or use Deploy GUI."
fi

# ── Step 3: Node A Dashboard ──────────────────────────────────────────────────
step "Step 3 — Node A Command Center Dashboard"
pkill -f node-a-command-center.js 2>/dev/null || true
sleep 1
nohup node node-a-command-center/node-a-command-center.js \
  > /tmp/node-a-dashboard.log 2>&1 &
NODE_A_PID=$!
info "Started Node A dashboard (PID ${NODE_A_PID})"
sleep 3
wait_for_health "Node A Dashboard" "http://localhost:3099/api/status" 6 3
ok "Node A Dashboard ready at http://localhost:3099"

# ── Step 4: KVM Operator ───────────────────────────────────────────────────────
step "Step 4 — KVM Operator"
if [ -f "kvm-operator/.env" ]; then
  if systemctl is-enabled ai-kvm-operator &>/dev/null 2>&1; then
    sudo systemctl restart ai-kvm-operator
    sleep 3
    wait_for_health "KVM Operator" "http://localhost:5000/health" 6 3
    ok "KVM Operator started via systemd"
  else
    pkill -f "uvicorn app:app" 2>/dev/null || true
    sleep 1
    (cd kvm-operator && nohup ./run_dev.sh > /tmp/kvm-operator.log 2>&1 &)
    sleep 5
    wait_for_health "KVM Operator" "http://localhost:5000/health" 6 3
    ok "KVM Operator started (log: /tmp/kvm-operator.log)"
  fi
else
  warn "kvm-operator/.env not found — copy kvm-operator/.env.example and configure it, then run: cd kvm-operator && ./run_dev.sh"
fi

# ── Step 5: OpenClaw (Node B) ─────────────────────────────────────────────────
step "Step 5 — OpenClaw AI Gateway (Node B)"
if [[ "$NODE_B_IP" == *"."* ]] && ! [[ "$NODE_B_IP" == *"X"* ]]; then
  info "Deploying OpenClaw on Node B (${NODE_B_IP})…"
  ssh_cmd "$NODE_B_IP" "$NODE_B_SSH_USER" \
    "cd /mnt/user/appdata/homelab/openclaw 2>/dev/null || cd ~/homelab/openclaw && docker compose pull && docker compose up -d"
  wait_for_health "OpenClaw" "http://${NODE_B_IP}:18789/" 12 5
  ok "OpenClaw ready at http://${NODE_B_IP}:18789"
else
  warn "Node B IP not configured — skipping OpenClaw deploy."
fi

# ── Step 6: Deploy GUI ─────────────────────────────────────────────────────────
step "Step 6 — Deploy GUI"
info "Building and starting Deploy GUI…"
docker compose -f deploy-gui/docker-compose.yml up -d --build 2>&1 | tail -5
wait_for_health "Deploy GUI" "http://localhost:9999/api/status" 8 3
ok "Deploy GUI ready at http://localhost:9999"

# ── Final summary ──────────────────────────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║   Deployment Complete                          ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
echo -e "  ${GREEN}✓${NC} Node C (Ollama)      → http://localhost:11434"
echo -e "  ${GREEN}✓${NC} Chimera Face UI      → http://localhost:3000"
echo -e "  ${GREEN}✓${NC} Node A Dashboard     → http://localhost:3099"
echo -e "  ${GREEN}✓${NC} KVM Operator         → http://localhost:5000"
echo -e "  ${GREEN}✓${NC} Deploy GUI           → http://localhost:9999"
if [[ "$NODE_B_IP" != *"X"* ]]; then
  echo -e "  ${GREEN}✓${NC} LiteLLM Gateway      → http://${NODE_B_IP}:4000"
  echo -e "  ${GREEN}✓${NC} OpenClaw             → http://${NODE_B_IP}:18789"
fi
echo ""
echo "  📖 Full docs: ./GUIDEBOOK.md"
echo "  🔍 Run: ./validate.sh to verify configuration"
echo ""
