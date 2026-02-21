#!/usr/bin/env bash
# Grand Unified AI Home Lab — Master Deploy Script
# Deploys all nodes in the correct order with health checks between steps.
#
# This script runs from Node C (Fedora 43, Intel Arc) and deploys:
#   1. Node C — Ollama + Chimera Face (local)
#   2. Node B — LiteLLM Gateway (remote via SSH to Unraid)
#   3. Node A — Command Center Dashboard (local)
#   4. KVM Operator (local)
#   5. OpenClaw (remote via SSH to Unraid)
#   6. Deploy GUI (local Docker)
#
# Usage:
#   ./scripts/deploy-all.sh              # deploy everything
#   ./scripts/deploy-all.sh stop         # stop all services
#   ./scripts/deploy-all.sh status       # show status only
#   ./scripts/deploy-all.sh --skip-ssh   # deploy local-only services

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
source "${REPO_ROOT}/scripts/lib-inventory.sh"
load_inventory "$REPO_ROOT"

ACTION="${1:-deploy}"
SKIP_SSH=false
for arg in "$@"; do
  [[ "$arg" == "--skip-ssh" ]] && SKIP_SSH=true
done

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

step()  { echo ""; echo -e "${CYAN}══════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}══════════════════════════════════${NC}"; }
ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
err()   { echo -e "  ${RED}✗${NC} $1"; }
warn()  { echo -e "  ${YELLOW}!${NC} $1"; }
info()  { echo -e "    $1"; }
header(){ echo -e "${BOLD}$1${NC}"; }

DEPLOY_ERRORS=0
note_error() { ((DEPLOY_ERRORS++)) || true; }

# ── Docker command helper ─────────────────────────────────────────────────────
# Detect whether we need sudo for docker
DOCKER_CMD="docker"
detect_docker() {
  if command -v docker &>/dev/null; then
    if docker info &>/dev/null 2>&1; then
      DOCKER_CMD="docker"
      return 0
    elif sudo docker info &>/dev/null 2>&1; then
      DOCKER_CMD="sudo docker"
      warn "Docker requires sudo — running with sudo"
      warn "To fix: sudo usermod -aG docker \$USER && newgrp docker"
      return 0
    else
      err "Docker daemon is not running"
      info "Start it with: sudo systemctl start docker"
      return 1
    fi
  else
    err "Docker is not installed"
    return 1
  fi
}

docker_compose() {
  if [[ "$DOCKER_CMD" == "sudo docker" ]]; then
    sudo docker compose "$@"
  else
    docker compose "$@"
  fi
}

docker_exec() {
  $DOCKER_CMD exec "$@"
}

# ── Load node IPs ─────────────────────────────────────────────────────────────
# Try to read from deploy-gui settings if present
if [ -f "deploy-gui/data/settings.json" ] && command -v python3 &>/dev/null; then
  NODE_A_IP=$(python3 -c "import json; s=json.load(open('deploy-gui/data/settings.json')); print(s['nodes']['nodeA']['ip'])" 2>/dev/null || echo "$NODE_A_IP")
  NODE_B_IP=$(python3 -c "import json; s=json.load(open('deploy-gui/data/settings.json')); print(s['nodes']['nodeB']['ip'])" 2>/dev/null || echo "$NODE_B_IP")
  NODE_C_IP=$(python3 -c "import json; s=json.load(open('deploy-gui/data/settings.json')); print(s['nodes']['nodeC']['ip'])" 2>/dev/null || echo "$NODE_C_IP")
fi

LITELLM_KEY="${LITELLM_API_KEY:-sk-master-key}"

# ── Health check with auth support ────────────────────────────────────────────
wait_for_health() {
  local label="$1" url="$2" max_attempts="${3:-12}" delay="${4:-5}"
  local auth_header="${5:-}"
  info "Waiting for ${label} to be healthy..."
  local i=0
  while [ $i -lt "$max_attempts" ]; do
    local code
    if [ -n "$auth_header" ]; then
      code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -H "$auth_header" "$url" 2>/dev/null || echo "000")
    else
      code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    fi
    if [[ "$code" =~ ^2 ]] || [[ "$code" =~ ^3 ]]; then
      ok "${label} is healthy (HTTP ${code})"
      return 0
    fi
    i=$((i+1))
    info "  Attempt $i/${max_attempts} -- HTTP ${code}, retrying in ${delay}s..."
    sleep "$delay"
  done
  err "${label} did not become healthy after ${max_attempts} attempts (last HTTP ${code:-000})"
  return 1
}

# ── SSH helpers ───────────────────────────────────────────────────────────────
ssh_cmd() {
  local host="$1" user="$2"; shift 2
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes "${user}@${host}" "$@" 2>&1
}

test_ssh() {
  local label="$1" host="$2" user="$3"
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes "${user}@${host}" true &>/dev/null; then
    ok "SSH to ${label} (${user}@${host}) -- connected"
    return 0
  else
    err "SSH to ${label} (${user}@${host}) -- FAILED"
    echo ""
    info "  ${YELLOW}Troubleshooting:${NC}"
    info "  1. Check the host is reachable:  ping -c1 ${host}"
    info "  2. Set up SSH key auth:          ssh-copy-id ${user}@${host}"
    info "  3. Test manually:                ssh ${user}@${host}"
    info "  4. For Unraid, ensure SSH is enabled in Settings > Management Access"
    echo ""
    return 1
  fi
}

test_ping() {
  local label="$1" host="$2"
  if ping -c1 -W2 "$host" &>/dev/null; then
    ok "Ping ${label} (${host}) -- reachable"
    return 0
  else
    err "Ping ${label} (${host}) -- unreachable"
    return 1
  fi
}

# ── Show container logs on failure ────────────────────────────────────────────
show_container_logs() {
  local container="$1" lines="${2:-15}"
  info "  Last ${lines} lines from ${container}:"
  $DOCKER_CMD logs --tail "$lines" "$container" 2>&1 | while IFS= read -r line; do
    info "    ${line}"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# STOP action
# ─────────────────────────────────────────────────────────────────────────────
if [ "$ACTION" = "stop" ]; then
  echo "Stopping all services..."
  detect_docker || exit 1

  step "Stop Deploy GUI (local)"
  docker_compose -f deploy-gui/docker-compose.yml down 2>/dev/null && ok "Deploy GUI stopped" || warn "Deploy GUI not running"

  step "Stop Node C (local)"
  docker_compose -f node-c-arc/docker-compose.yml down 2>/dev/null && ok "Node C stopped" || warn "Node C not running"

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
echo "╔════════════════════════════════════════════════════╗"
echo "║   Grand Unified AI Home Lab — Full Deploy          ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "  Node A (Brain):       ${NODE_A_IP}"
echo "  Node B (Unraid):      ${NODE_B_IP}"
echo "  Node C (Intel Arc):   ${NODE_C_IP} (this machine)"
echo "  Node D (HA):          ${NODE_D_IP:-not set}"
echo "  Node E (Sentinel):    ${NODE_E_IP:-not set}"
echo "  KVM:                  ${KVM_IP:-not set}"
echo ""

# ── Step 0: Preflight — Docker, Network, SSH ─────────────────────────────────
step "Step 0 — Preflight Checks"

# Docker
header "  Docker:"
if ! detect_docker; then
  err "Cannot proceed without Docker. Exiting."
  exit 1
fi
ok "Docker is available ($($DOCKER_CMD --version 2>/dev/null | head -1))"

# Docker Compose
if docker_compose version &>/dev/null 2>&1; then
  ok "Docker Compose plugin available"
else
  err "Docker Compose not available — install with: sudo dnf install docker-compose-plugin"
  exit 1
fi

# Node.js (needed for Node A dashboard and Deploy GUI)
if command -v node &>/dev/null; then
  ok "Node.js $(node --version)"
else
  warn "Node.js not found — Node A dashboard and Deploy GUI won't work"
  info "Install with: sudo dnf install nodejs -y"
fi

echo ""
header "  Network Connectivity:"

# Ping local nodes first
test_ping "Node A (Brain)" "$NODE_A_IP" || note_error

if ! is_missing_or_placeholder_ip "$NODE_B_IP"; then
  test_ping "Node B (Unraid)" "$NODE_B_IP" || note_error
fi

if [ -n "${KVM_IP:-}" ] && ! is_missing_or_placeholder_ip "$KVM_IP"; then
  test_ping "NanoKVM" "$KVM_IP" || true
fi

echo ""
header "  SSH Access (remote nodes):"
SSH_TO_B=false

if [ "$SKIP_SSH" = true ]; then
  warn "Skipping SSH checks (--skip-ssh flag)"
elif is_missing_or_placeholder_ip "$NODE_B_IP"; then
  warn "Node B IP not configured — skipping SSH test"
else
  if test_ssh "Node B (Unraid)" "$NODE_B_IP" "$NODE_B_SSH_USER"; then
    SSH_TO_B=true
  else
    note_error
    warn "Remote deploys to Node B will be skipped"
  fi
fi

# ── Step 1: Validate config files ────────────────────────────────────────────
step "Step 1 — Validate configuration"
if ./validate.sh; then
  ok "Configuration validation passed"
else
  err "Configuration validation failed — fix errors before deploying"
  exit 1
fi

# ── Step 2: Node C — Intel Arc + Ollama ──────────────────────────────────────
step "Step 2 — Node C (Intel Arc + Ollama)"
info "Pulling latest images..."
docker_compose -f node-c-arc/docker-compose.yml pull 2>&1 | tail -5 || true

info "Starting Node C services..."
docker_compose -f node-c-arc/docker-compose.yml up -d
ok "Node C containers started"

if ! wait_for_health "Ollama API" "http://localhost:11434/api/version" 18 5; then
  warn "Ollama may still be starting — checking container status..."
  show_container_logs "ollama_intel_arc" 10
  note_error
fi

info "Pulling llava model (this may take a few minutes on first run)..."
docker_exec ollama_intel_arc ollama pull llava 2>&1 | tail -3 || warn "Model pull failed — retry manually: docker exec ollama_intel_arc ollama pull llava"
ok "Node C ready"

# ── Step 3: Node B — LiteLLM Gateway ─────────────────────────────────────────
step "Step 3 — Node B LiteLLM Gateway (Unraid)"
if [ "$SSH_TO_B" = true ]; then
  info "Deploying LiteLLM stack on Node B (${NODE_B_IP})..."
  ssh_cmd "$NODE_B_IP" "$NODE_B_SSH_USER" \
    "cd /mnt/user/appdata/homelab/node-b-litellm 2>/dev/null || cd ~/homelab/node-b-litellm && docker compose -f litellm-stack.yml pull && docker compose -f litellm-stack.yml up -d" || {
    err "LiteLLM deploy command failed"
    note_error
  }

  # LiteLLM /health returns 401 when master_key is set — use /health/readiness instead
  if ! wait_for_health "LiteLLM Gateway" "http://${NODE_B_IP}:4000/health/readiness" 12 5; then
    warn "LiteLLM health check failed"
    info "  Try checking directly: curl -H 'x-api-key: ${LITELLM_KEY}' http://${NODE_B_IP}:4000/health"
    info "  Or use readiness endpoint: curl http://${NODE_B_IP}:4000/health/readiness"
    info "  Check container logs: ssh ${NODE_B_SSH_USER}@${NODE_B_IP} docker logs litellm_gateway --tail 20"
    note_error
  else
    ok "Node B LiteLLM Gateway ready"
  fi
elif ! is_missing_or_placeholder_ip "$NODE_B_IP"; then
  warn "SSH to Node B not available — skipping remote deploy"
  info "Deploy manually: ssh ${NODE_B_SSH_USER}@${NODE_B_IP} 'cd /mnt/user/appdata/homelab/node-b-litellm && docker compose -f litellm-stack.yml up -d'"

  # Still check if it's already running
  info "Checking if LiteLLM is already running..."
  wait_for_health "LiteLLM Gateway (existing)" "http://${NODE_B_IP}:4000/health/readiness" 2 3 || true
else
  warn "Node B IP not configured — skipping LiteLLM deploy"
fi

# ── Step 4: Node A Dashboard ──────────────────────────────────────────────────
step "Step 4 — Node A Command Center Dashboard"
if command -v node &>/dev/null; then
  pkill -f node-a-command-center.js 2>/dev/null || true
  sleep 1
  nohup node node-a-command-center/node-a-command-center.js \
    > /tmp/node-a-dashboard.log 2>&1 &
  NODE_A_PID=$!
  info "Started Node A dashboard (PID ${NODE_A_PID})"
  sleep 3
  if ! wait_for_health "Node A Dashboard" "http://localhost:3099/api/status" 6 3; then
    warn "Node A Dashboard may have failed to start"
    info "  Check log: cat /tmp/node-a-dashboard.log"
    note_error
  else
    ok "Node A Dashboard ready at http://localhost:3099"
  fi
else
  warn "Node.js not installed — skipping Node A Dashboard"
fi

# ── Step 5: KVM Operator ───────────────────────────────────────────────────────
step "Step 5 — KVM Operator"

# Auto-create .env from .env.example if missing
if [ ! -f "kvm-operator/.env" ] && [ -f "kvm-operator/.env.example" ]; then
  info "Creating kvm-operator/.env from .env.example..."
  cp kvm-operator/.env.example kvm-operator/.env
  ok "kvm-operator/.env created — edit tokens before production use"
fi

if [ -f "kvm-operator/.env" ]; then
  if systemctl is-enabled ai-kvm-operator &>/dev/null 2>&1; then
    sudo systemctl restart ai-kvm-operator
    sleep 3
    if ! wait_for_health "KVM Operator" "http://localhost:5000/health" 6 3; then
      warn "KVM Operator may have failed — check: sudo journalctl -u ai-kvm-operator --no-pager -n 20"
      note_error
    else
      ok "KVM Operator started via systemd"
    fi
  else
    pkill -f "uvicorn app:app" 2>/dev/null || true
    sleep 1
    (cd kvm-operator && nohup ./run_dev.sh > /tmp/kvm-operator.log 2>&1 &)
    sleep 5
    if ! wait_for_health "KVM Operator" "http://localhost:5000/health" 6 3; then
      warn "KVM Operator may have failed to start"
      info "  Check log: cat /tmp/kvm-operator.log"
      note_error
    else
      ok "KVM Operator started (log: /tmp/kvm-operator.log)"
    fi
  fi
else
  warn "kvm-operator/.env not found and no .env.example available"
  info "See GUIDEBOOK.md Chapter 6 for KVM Operator setup"
fi

# ── Step 6: OpenClaw (Node B) ─────────────────────────────────────────────────
step "Step 6 — OpenClaw AI Gateway (Node B)"
if [ "$SSH_TO_B" = true ]; then
  info "Deploying OpenClaw on Node B (${NODE_B_IP})..."
  ssh_cmd "$NODE_B_IP" "$NODE_B_SSH_USER" \
    "cd /mnt/user/appdata/homelab/openclaw 2>/dev/null || cd ~/homelab/openclaw && docker compose pull && docker compose up -d" || {
    err "OpenClaw deploy command failed"
    note_error
  }
  if ! wait_for_health "OpenClaw" "http://${NODE_B_IP}:18789/" 15 5; then
    warn "OpenClaw health check failed"
    info "  Check container logs: ssh ${NODE_B_SSH_USER}@${NODE_B_IP} docker logs openclaw-gateway --tail 20"
    info "  OpenClaw can take 30-60s to start — check again in a minute"
    note_error
  else
    ok "OpenClaw ready at http://${NODE_B_IP}:18789"
  fi
elif ! is_missing_or_placeholder_ip "$NODE_B_IP"; then
  warn "SSH to Node B not available — skipping OpenClaw deploy"
  info "Deploy manually or use: ./scripts/prepare-openclaw.sh"

  # Still check if already running
  info "Checking if OpenClaw is already running..."
  wait_for_health "OpenClaw (existing)" "http://${NODE_B_IP}:18789/" 2 3 || true
else
  warn "Node B IP not configured — skipping OpenClaw deploy"
fi

# ── Step 7: Deploy GUI ─────────────────────────────────────────────────────────
step "Step 7 — Deploy GUI"

# Ensure ~/.ssh exists (needed for volume mount)
mkdir -p "${HOME}/.ssh" 2>/dev/null || true

info "Building and starting Deploy GUI..."
docker_compose -f deploy-gui/docker-compose.yml up -d --build 2>&1 | tail -10

sleep 5
if ! wait_for_health "Deploy GUI" "http://localhost:9999/api/status" 8 3; then
  warn "Deploy GUI health check failed — checking container..."
  if $DOCKER_CMD ps --format '{{.Names}}' 2>/dev/null | grep -q homelab-deploy-gui; then
    show_container_logs "homelab-deploy-gui" 15
  else
    err "Deploy GUI container is not running"
    info "  Check build output: docker compose -f deploy-gui/docker-compose.yml logs"
  fi
  note_error
else
  ok "Deploy GUI ready at http://localhost:9999"
fi

# ── Final summary ──────────────────────────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║   Deployment Complete                              ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo -e "  ${GREEN}LOCAL SERVICES:${NC}"
echo -e "    Ollama API           ${CYAN}http://localhost:11434${NC}"
echo -e "    Chimera Face UI      ${CYAN}http://localhost:3000${NC}"
echo -e "    Node A Dashboard     ${CYAN}http://localhost:3099${NC}"
echo -e "    KVM Operator         ${CYAN}http://localhost:5000${NC}"
echo -e "    Deploy GUI           ${CYAN}http://localhost:9999${NC}"

if ! is_missing_or_placeholder_ip "$NODE_B_IP"; then
  echo ""
  echo -e "  ${GREEN}REMOTE SERVICES (Node B):${NC}"
  echo -e "    LiteLLM Gateway      ${CYAN}http://${NODE_B_IP}:4000${NC}"
  echo -e "    OpenClaw             ${CYAN}http://${NODE_B_IP}:18789${NC}"
  echo -e "    Portainer            ${CYAN}http://${NODE_B_IP}:9000${NC}"
fi

echo ""
if [ "$DEPLOY_ERRORS" -gt 0 ]; then
  echo -e "  ${YELLOW}Completed with ${DEPLOY_ERRORS} warning(s) — review output above.${NC}"
  echo ""
  echo "  Troubleshooting tips:"
  echo "    - Check SSH access:   ssh ${NODE_B_SSH_USER}@${NODE_B_IP}"
  echo "    - View container logs: docker logs <container_name>"
  echo "    - Run preflight:      ./scripts/preflight-check.sh"
  echo "    - Run validation:     ./validate.sh"
else
  echo -e "  ${GREEN}All services deployed successfully!${NC}"
fi

echo ""
echo "  Full docs: ./GUIDEBOOK.md"
echo "  Validate:  ./validate.sh"
echo ""
