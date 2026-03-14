#!/usr/bin/env bash
# Grand Unified AI Home Lab — Master Deploy Script
# Deploys all nodes in the correct order with health checks between steps.
#
# This script runs from Node C (Fedora 44 cosmic nightly, Intel Arc) and deploys:
#   1. Node C — Ollama + Chimera Face (local)
#   2. Node B — LiteLLM Gateway (remote via Tailscale to Unraid)
#   3. Node A — Command Center Dashboard (local)
#   4. KVM Operator (local)
#   5. OpenClaw (remote via Tailscale to Unraid)
#   6. Deploy GUI (local Docker)
#
# Usage:
#   ./scripts/deploy-all.sh              # deploy everything
#   ./scripts/deploy-all.sh stop         # stop all services
#   ./scripts/deploy-all.sh status       # show status only
#   ./scripts/deploy-all.sh --skip-remote  # deploy local-only services

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
source "${REPO_ROOT}/scripts/lib-inventory.sh"
load_inventory "$REPO_ROOT"
source "${REPO_ROOT}/scripts/lib-colors.sh"

ACTION="${1:-deploy}"
SKIP_REMOTE=false
for arg in "$@"; do
  # Accept both --skip-remote and the previous --skip-ssh name for backward compatibility
  [[ "$arg" == "--skip-remote" || "$arg" == "--skip-ssh" ]] && SKIP_REMOTE=true
done

# Resolve effective remote IPs — prefer Tailscale over LAN
NODE_B_REMOTE_IP="$(resolve_node_ip "${NODE_B_TS_IP:-}" "$NODE_B_IP")"
NODE_C_REMOTE_IP="$(resolve_node_ip "${NODE_C_TS_IP:-}" "$NODE_C_IP")"


step()  { echo ""; echo -e "${CYAN}══════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}══════════════════════════════════${NC}"; }
ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
err()   { echo -e "  ${RED}✗${NC} $1"; }
warn()  { echo -e "  ${YELLOW}!${NC} $1"; }
info()  { echo -e "    $1"; }
header(){ echo -e "${BOLD}$1${NC}"; }

DEPLOY_ERRORS=0
note_error() { ((DEPLOY_ERRORS++)) || true; }

# ── Global error handler with state tracking ──────────────────────────────────
declare -A DEPLOY_STATE
DEPLOY_STATE[phase]="init"
DEPLOY_STATE[node]="none"

handle_error() {
  local line="$1" exit_code="$2"
  echo ""
  echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║  DEPLOYMENT ERROR                                    ║${NC}"
  echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
  echo -e "  ${RED}Phase:${NC}     ${DEPLOY_STATE[phase]}"
  echo -e "  ${RED}Node:${NC}      ${DEPLOY_STATE[node]}"
  echo -e "  ${RED}Line:${NC}      ${line}"
  echo -e "  ${RED}Exit code:${NC} ${exit_code}"
  echo ""
  # Capture recent container logs if a container name is tracked
  if [[ -n "${DEPLOY_STATE[container]:-}" ]] && command -v docker &>/dev/null; then
    echo -e "  ${YELLOW}Last 20 lines from container '${DEPLOY_STATE[container]}':${NC}"
    docker logs --tail 20 "${DEPLOY_STATE[container]}" 2>&1 | while IFS= read -r l; do
      echo "    $l"
    done 2>/dev/null || true
    echo ""
  fi
  echo -e "  ${YELLOW}Tip:${NC} Run ./scripts/preflight-check.sh to diagnose the environment."
  echo ""
}

cleanup() {
  local exit_code=$?
  # Restore terminal attributes in case they were changed
  tput sgr0 2>/dev/null || true
  if [[ $exit_code -ne 0 ]] && [[ "${DEPLOY_STATE[phase]}" != "complete" ]]; then
    handle_error "${BASH_LINENO[0]:-0}" "$exit_code"
  fi
}

trap 'handle_error ${LINENO} $?' ERR
trap 'cleanup' EXIT
trap 'echo ""; warn "Interrupted — cleaning up..."; exit 130' INT TERM

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

# ── Health check with exponential backoff ────────────────────────────────────
wait_for_health() {
  local label="$1" url="$2" max_attempts="${3:-12}" initial_delay="${4:-2}"
  local auth_header="${5:-}"
  local extra_ok_codes="${6:-}"
  info "Waiting for ${label} to be healthy (exponential backoff)..."
  local i=0 delay="$initial_delay" code
  while [ $i -lt "$max_attempts" ]; do
    if [ -n "$auth_header" ]; then
      code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -H "$auth_header" "$url" 2>/dev/null || echo "000")
    else
      code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    fi
    if [[ "$code" =~ ^2 ]] || [[ "$code" =~ ^3 ]] || [[ ",${extra_ok_codes}," == *",${code},"* ]]; then
      ok "${label} is healthy (HTTP ${code})"
      return 0
    fi
    i=$((i+1))
    info "  Attempt $i/${max_attempts} — HTTP ${code}, retrying in ${delay}s..."
    sleep "$delay"
    # Double the delay on each attempt, cap at 60 seconds
    delay=$(( delay * 2 > 60 ? 60 : delay * 2 ))
  done
  err "${label} did not become healthy after ${max_attempts} attempts (last HTTP ${code:-000})"
  return 1
}

# ── Remote connection helpers (Tailscale SSH) ─────────────────────────────────
ssh_cmd() {
  local host="$1" user="$2"; shift 2
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes "${user}@${host}" "$@" 2>&1
}

test_ssh() {
  local label="$1" host="$2" user="$3"
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes "${user}@${host}" true &>/dev/null; then
    ok "SSH via Tailscale to ${label} (${user}@${host}) -- connected"
    return 0
  else
    err "SSH via Tailscale to ${label} (${user}@${host}) -- FAILED"
    echo ""
    info "  ${YELLOW}Troubleshooting:${NC}"
    info "  1. Verify Tailscale is running:  tailscale status"
    info "  2. Check the host is reachable:  ping -c1 ${host}"
    info "  3. Set up SSH key auth:          ssh-copy-id ${user}@${host}"
    info "  4. Test manually:                ssh ${user}@${host}"
    info "  5. For Unraid, ensure SSH is enabled in Settings > Management Access"
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

# ── Systemd user service generator ───────────────────────────────────────────
# Creates and enables a systemd user service for a long-running process.
# Uses atomic file placement (write to tmp, then mv) to avoid race conditions.
# Arguments: service_name description exec_start working_dir
install_systemd_service() {
  local svc_name="$1" description="$2" exec_start="$3" working_dir="$4"
  local svc_dir="${HOME}/.config/systemd/user"
  local svc_file="${svc_dir}/${svc_name}.service"
  local tmp_file
  tmp_file="$(mktemp)"

  mkdir -p "$svc_dir"

  cat > "$tmp_file" <<EOF
[Unit]
Description=${description}
After=network.target

[Service]
Type=simple
WorkingDirectory=${working_dir}
ExecStart=${exec_start}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

  # Validate the unit file before placing it (best-effort; warn if unavailable)
  if ! systemd-analyze verify "$tmp_file" &>/dev/null; then
    warn "systemd-analyze verify skipped or reported issues for '${svc_name}' — proceeding anyway"
  fi
  mv "$tmp_file" "$svc_file"

  systemctl --user daemon-reload
  systemctl --user enable "${svc_name}" --now 2>/dev/null || \
    systemctl --user restart "${svc_name}" 2>/dev/null || true
  ok "Systemd user service '${svc_name}' installed and started"
}

# ── Portainer API orchestration ───────────────────────────────────────────────
# Triggers a Portainer stack redeploy via its REST API.
# Arguments: stack_id portainer_url portainer_token
portainer_redeploy_stack() {
  local stack_id="$1" portainer_url="$2" portainer_token="$3"
  local endpoint="${portainer_url}/api/stacks/${stack_id}/git/redeploy"
  info "Redeploying Portainer stack ${stack_id} via API..."
  local response http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 30 \
    -X PUT \
    -H "X-API-Key: ${portainer_token}" \
    -H "Content-Type: application/json" \
    -d '{"pullImage":true,"prune":false}' \
    "${endpoint}" 2>/dev/null || echo "000")
  if [[ "$http_code" =~ ^2 ]]; then
    ok "Portainer stack ${stack_id} redeployed (HTTP ${http_code})"
    return 0
  else
    warn "Portainer stack redeploy returned HTTP ${http_code} — falling back to SSH"
    return 1
  fi
}

# ── Portainer stack deploy (create or update) via API ────────────────────────
# Looks up the stack by name and redeploys it, or falls back to SSH over Tailscale.
# Arguments: stack_name portainer_url portainer_token ssh_fallback_cmd node_ip ssh_user
portainer_deploy_stack() {
  local stack_name="$1" portainer_url="$2" portainer_token="$3"
  local ssh_fallback="$4" node_ip="$5" ssh_user="$6"

  if [ -z "$portainer_token" ]; then
    info "PORTAINER_TOKEN not set — using Tailscale SSH fallback"
    ssh_cmd "$node_ip" "$ssh_user" "$ssh_fallback" && return 0 || return 1
  fi

  # Fetch the stack list and find our stack's ID
  local stacks_json
  stacks_json=$(curl -s --max-time 10 \
    -H "X-API-Key: ${portainer_token}" \
    "${portainer_url}/api/stacks" 2>/dev/null || echo "[]")

  local stack_id
  stack_id=$(echo "$stacks_json" | \
    python3 -c "import json,sys; stacks=json.load(sys.stdin); \
      match=[s['Id'] for s in stacks if s.get('Name')=='${stack_name}']; \
      print(match[0] if match else '')" 2>/dev/null || true)

  if [ -n "$stack_id" ]; then
    portainer_redeploy_stack "$stack_id" "$portainer_url" "$portainer_token" && return 0
  else
    info "Stack '${stack_name}' not found in Portainer — using Tailscale SSH fallback"
  fi

  # Tailscale SSH fallback if Portainer API unavailable or stack not found
  ssh_cmd "$node_ip" "$ssh_user" "$ssh_fallback"
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
echo "  Node A (Brain):       ${NODE_A_IP}  (Tailscale: ${NODE_A_TS_IP:-not set})"
echo "  Node B (Unraid):      ${NODE_B_IP}  (Tailscale: ${NODE_B_TS_IP:-not set})"
echo "  Node C (Intel Arc):   ${NODE_C_IP} (this machine, Tailscale: ${NODE_C_TS_IP:-not set})"
echo "  Node D (HA):          ${NODE_D_IP:-not set}  (Tailscale: ${NODE_D_TS_IP:-not set})"
echo "  Node E (Sentinel):    ${NODE_E_IP:-not set}  (Tailscale: ${NODE_E_TS_IP:-not set})"
echo "  KVM:                  ${KVM_IP:-not set}  (Tailscale: ${KVM_TS_IP:-not set})"
echo ""

# ── Step 0: Preflight — Docker, Network, Tailscale ───────────────────────────
DEPLOY_STATE[phase]="preflight"; DEPLOY_STATE[node]="local"
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
header "  Tailscale:"
if tailscale_available; then
  ok "Tailscale is running ($(tailscale version 2>/dev/null | head -1))"
  MY_TS_IP=$(tailscale ip -4 2>/dev/null | head -1 || echo "")
  [ -n "$MY_TS_IP" ] && info "  This machine's Tailscale IP: ${MY_TS_IP}"
else
  warn "Tailscale not detected — remote connections will use LAN IPs as fallback"
  info "  Install: curl -fsSL https://tailscale.com/install.sh | sh"
fi

echo ""
header "  Network Connectivity (via Tailscale):"

# Ping remote nodes using their resolved (Tailscale) IPs
test_ping "Node A (Brain)" "$(resolve_node_ip "${NODE_A_TS_IP:-}" "$NODE_A_IP")" || note_error

if ! is_missing_or_placeholder_ip "$NODE_B_REMOTE_IP"; then
  test_ping "Node B (Unraid)" "$NODE_B_REMOTE_IP" || note_error
fi

if [ -n "${KVM_TS_IP:-}" ]; then
  test_ping "KVM" "$KVM_TS_IP" || true
elif [ -n "${KVM_IP:-}" ] && ! is_missing_or_placeholder_ip "$KVM_IP"; then
  test_ping "NanoKVM" "$KVM_IP" || true
fi

echo ""
header "  Tailscale SSH Access (remote nodes):"
SSH_TO_B=false

if [ "$SKIP_REMOTE" = true ]; then
  warn "Skipping remote checks (--skip-remote flag)"
elif is_missing_or_placeholder_ip "$NODE_B_REMOTE_IP"; then
  warn "Node B remote IP not configured — skipping connection test"
else
  if test_ssh "Node B (Unraid)" "$NODE_B_REMOTE_IP" "$NODE_B_SSH_USER"; then
    SSH_TO_B=true
  else
    note_error
    warn "Remote deploys to Node B will be skipped"
  fi
fi

# ── Step 1: Validate config files ────────────────────────────────────────────
DEPLOY_STATE[phase]="validation"; DEPLOY_STATE[node]="local"
step "Step 1 — Validate configuration"
if ./validate.sh; then
  ok "Configuration validation passed"
else
  err "Configuration validation failed — fix errors before deploying"
  exit 1
fi

# ── Step 2: Node C — Intel Arc + Ollama ──────────────────────────────────────
DEPLOY_STATE[phase]="node-c-deploy"; DEPLOY_STATE[node]="Node C (Intel Arc)"
DEPLOY_STATE[container]="ollama_intel_arc"
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
DEPLOY_STATE[phase]="node-b-litellm"; DEPLOY_STATE[node]="Node B (Unraid)"
DEPLOY_STATE[container]="litellm_gateway"
step "Step 3 — Node B LiteLLM Gateway (Unraid)"

PORTAINER_URL="${PORTAINER_URL:-http://${NODE_B_REMOTE_IP}:9000}"
PORTAINER_TOKEN="${PORTAINER_TOKEN:-}"

if [ "$SSH_TO_B" = true ] || [ -n "$PORTAINER_TOKEN" ]; then
  info "Deploying LiteLLM stack on Node B (${NODE_B_REMOTE_IP})..."
  local_ssh_cmd="cd /mnt/user/appdata/homelab/node-b-litellm 2>/dev/null || cd ~/homelab/node-b-litellm && docker compose -f litellm-stack.yml pull && docker compose -f litellm-stack.yml up -d"
  if portainer_deploy_stack "litellm" "$PORTAINER_URL" "$PORTAINER_TOKEN" \
      "$local_ssh_cmd" "$NODE_B_REMOTE_IP" "$NODE_B_SSH_USER" || {
    err "LiteLLM deploy command failed"
    note_error
    false
  }; then
    # Some deployments return 401 on readiness when auth middleware is enabled.
    if ! wait_for_health "LiteLLM Gateway" "http://${NODE_B_REMOTE_IP}:4000/health/readiness" 12 2 "" "401"; then
      warn "LiteLLM health check failed"
      info "  Try checking directly: curl -H 'x-api-key: ${LITELLM_KEY}' http://${NODE_B_REMOTE_IP}:4000/health"
      info "  Or use readiness endpoint: curl http://${NODE_B_REMOTE_IP}:4000/health/readiness"
      info "  Check container logs: ssh ${NODE_B_SSH_USER}@${NODE_B_REMOTE_IP} docker logs litellm_gateway --tail 20"
      note_error
    else
      ok "Node B LiteLLM Gateway ready"
    fi
  else
    warn "Skipping LiteLLM health check because remote deploy command failed"
  fi
elif ! is_missing_or_placeholder_ip "$NODE_B_REMOTE_IP"; then
  warn "Tailscale SSH to Node B not available and PORTAINER_TOKEN not set — skipping remote deploy"
  info "Deploy manually: ssh ${NODE_B_SSH_USER}@${NODE_B_REMOTE_IP} 'cd /mnt/user/appdata/homelab/node-b-litellm && docker compose -f litellm-stack.yml up -d'"
  info "Or set PORTAINER_TOKEN to deploy via Portainer API"

  # Still check if it's already running
  info "Checking if LiteLLM is already running..."
  wait_for_health "LiteLLM Gateway (existing)" "http://${NODE_B_REMOTE_IP}:4000/health/readiness" 2 2 || true
else
  warn "Node B remote IP not configured — skipping LiteLLM deploy"
fi

# ── Step 4: Node A Dashboard ──────────────────────────────────────────────────
DEPLOY_STATE[phase]="node-a-dashboard"; DEPLOY_STATE[node]="Node A (local)"; DEPLOY_STATE[container]=""
step "Step 4 — Node A Command Center Dashboard"
if command -v node &>/dev/null; then
  # Prefer systemd user service for reliable auto-restart on failure
  if systemctl --user cat node-a-dashboard.service &>/dev/null; then
    # Service already exists — reload and restart it
    systemctl --user daemon-reload
    systemctl --user restart node-a-dashboard 2>/dev/null && ok "Node A Dashboard restarted via systemd" || note_error
  elif command -v systemctl &>/dev/null && systemctl --user status &>/dev/null; then
    # Install as a systemd user service for auto-restart on crash
    info "Installing Node A Dashboard as a systemd user service..."
    install_systemd_service \
      "node-a-dashboard" \
      "Node A Central Brain Command Center" \
      "$(command -v node) ${REPO_ROOT}/node-a-command-center/node-a-command-center.js" \
      "${REPO_ROOT}/node-a-command-center"
  else
    # Fallback: kill existing instance by PID file, then launch in background
    if [ -f /tmp/node-a-dashboard.pid ]; then
      old_pid=$(cat /tmp/node-a-dashboard.pid 2>/dev/null || true)
      if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        kill "$old_pid" 2>/dev/null || true
        sleep 1
      fi
      rm -f /tmp/node-a-dashboard.pid
    fi
    node node-a-command-center/node-a-command-center.js \
      > /tmp/node-a-dashboard.log 2>&1 &
    echo $! > /tmp/node-a-dashboard.pid
    info "Started Node A dashboard (PID $(cat /tmp/node-a-dashboard.pid))"
  fi
  sleep 3
  if ! wait_for_health "Node A Dashboard" "http://localhost:3099/api/status" 6 2; then
    warn "Node A Dashboard may have failed to start"
    info "  Check log: cat /tmp/node-a-dashboard.log"
    info "  Or systemd: journalctl --user -u node-a-dashboard --no-pager -n 20"
    note_error
  else
    ok "Node A Dashboard ready at http://localhost:3099"
  fi
else
  warn "Node.js not installed — skipping Node A Dashboard"
fi

# ── Step 5: KVM Operator ───────────────────────────────────────────────────────
DEPLOY_STATE[phase]="kvm-operator"; DEPLOY_STATE[node]="local"
step "Step 5 — KVM Operator"

# Auto-create .env from .env.example if missing
if [ ! -f "kvm-operator/.env" ] && [ -f "kvm-operator/.env.example" ]; then
  info "Creating kvm-operator/.env from .env.example..."
  cp kvm-operator/.env.example kvm-operator/.env
  ok "kvm-operator/.env created — edit tokens before production use"
fi

if [ -f "kvm-operator/.env" ]; then
  if systemctl is-enabled ai-kvm-operator &>/dev/null; then
    sudo systemctl restart ai-kvm-operator
    sleep 3
    if ! wait_for_health "KVM Operator" "http://localhost:5000/health" 6 2; then
      warn "KVM Operator may have failed — check: sudo journalctl -u ai-kvm-operator --no-pager -n 20"
      note_error
    else
      ok "KVM Operator started via systemd"
    fi
  elif command -v systemctl &>/dev/null && systemctl --user status &>/dev/null && \
       command -v python3 &>/dev/null; then
    # Install as a systemd user service for auto-restart on crash
    info "Installing KVM Operator as a systemd user service..."
    venv_python="${REPO_ROOT}/kvm-operator/.venv/bin/python"
    if [ ! -x "$venv_python" ]; then
      venv_python="$(command -v python3)"
    fi
    install_systemd_service \
      "ai-kvm-operator" \
      "AI KVM Operator (FastAPI)" \
      "${venv_python} -m uvicorn app:app --host 0.0.0.0 --port 5000" \
      "${REPO_ROOT}/kvm-operator"
    sleep 5
    if ! wait_for_health "KVM Operator" "http://localhost:5000/health" 6 2; then
      warn "KVM Operator may have failed to start"
      info "  Check: journalctl --user -u ai-kvm-operator --no-pager -n 20"
      note_error
    else
      ok "KVM Operator ready at http://localhost:5000"
    fi
  else
    # Fallback: kill existing instance by PID file, then launch in background
    if [ -f /tmp/kvm-operator.pid ]; then
      old_pid=$(cat /tmp/kvm-operator.pid 2>/dev/null || true)
      if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        kill "$old_pid" 2>/dev/null || true
        sleep 1
      fi
      rm -f /tmp/kvm-operator.pid
    fi
    (cd kvm-operator && ./run_dev.sh > /tmp/kvm-operator.log 2>&1 &
     echo $! > /tmp/kvm-operator.pid)
    sleep 5
    if ! wait_for_health "KVM Operator" "http://localhost:5000/health" 6 2; then
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

# Verify NanoKVM device is reachable from the operator
if [ -n "${KVM_IP:-}" ] && ! is_missing_or_placeholder_ip "$KVM_IP"; then
  info "Verifying NanoKVM device at ${KVM_IP} is reachable..."
  kvm_http=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${KVM_IP}" 2>/dev/null || echo "000")
  if [[ "$kvm_http" =~ ^[23] ]]; then
    ok "NanoKVM device at ${KVM_IP} is responding (HTTP ${kvm_http})"
  elif ping -c1 -W2 "$KVM_IP" &>/dev/null; then
    warn "NanoKVM at ${KVM_IP} is pingable but web UI not responding (may need power-on)"
  else
    warn "NanoKVM at ${KVM_IP} is not reachable — check network connection"
    info "  The KVM Operator will still start, but KVM commands will fail until the device is online"
  fi
fi

# ── Step 6: OpenClaw (Node B) ─────────────────────────────────────────────────
DEPLOY_STATE[phase]="openclaw"; DEPLOY_STATE[node]="Node B (Unraid)"; DEPLOY_STATE[container]=""
step "Step 6 — OpenClaw AI Gateway (Node B)"
if [ "$SSH_TO_B" = true ] || [ -n "$PORTAINER_TOKEN" ]; then
  info "Deploying OpenClaw on Node B (${NODE_B_REMOTE_IP})..."
  local_ssh_cmd="cd /mnt/user/appdata/homelab/openclaw 2>/dev/null || cd ~/homelab/openclaw && docker compose pull && docker compose up -d"
  if portainer_deploy_stack "openclaw" "$PORTAINER_URL" "$PORTAINER_TOKEN" \
      "$local_ssh_cmd" "$NODE_B_REMOTE_IP" "$NODE_B_SSH_USER" || {
    err "OpenClaw deploy command failed"
    note_error
    false
  }; then
    if ! wait_for_health "OpenClaw" "http://${NODE_B_REMOTE_IP}:18789/" 15 2; then
      warn "OpenClaw health check failed"
      info "  Check container logs: ssh ${NODE_B_SSH_USER}@${NODE_B_REMOTE_IP} docker logs openclaw-gateway --tail 20"
      info "  OpenClaw can take 30-60s to start — check again in a minute"
      note_error
    else
      ok "OpenClaw ready at http://${NODE_B_REMOTE_IP}:18789"
    fi
  else
    warn "Skipping OpenClaw health check because remote deploy command failed"
  fi
elif ! is_missing_or_placeholder_ip "$NODE_B_REMOTE_IP"; then
  warn "Tailscale SSH to Node B not available and PORTAINER_TOKEN not set — skipping OpenClaw deploy"
  info "Deploy manually or use: ./scripts/prepare-openclaw.sh"

  # Still check if already running
  info "Checking if OpenClaw is already running..."
  wait_for_health "OpenClaw (existing)" "http://${NODE_B_REMOTE_IP}:18789/" 2 2 || true
else
  warn "Node B remote IP not configured — skipping OpenClaw deploy"
fi

# ── Step 7: Deploy GUI ─────────────────────────────────────────────────────────
DEPLOY_STATE[phase]="deploy-gui"; DEPLOY_STATE[node]="local"; DEPLOY_STATE[container]="homelab-deploy-gui"
step "Step 7 — Deploy GUI"

# Ensure ~/.ssh exists (needed for volume mount)
mkdir -p "${HOME}/.ssh" 2>/dev/null || true

info "Building and starting Deploy GUI..."
docker_compose -f deploy-gui/docker-compose.yml up -d --build 2>&1 | tail -10

sleep 5
if ! wait_for_health "Deploy GUI" "http://localhost:9999/api/health" 8 2; then
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
DEPLOY_STATE[phase]="complete"
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

if ! is_missing_or_placeholder_ip "$NODE_B_REMOTE_IP"; then
  echo ""
  echo -e "  ${GREEN}REMOTE SERVICES (Node B via Tailscale ${NODE_B_REMOTE_IP}):${NC}"
  echo -e "    LiteLLM Gateway      ${CYAN}http://${NODE_B_REMOTE_IP}:4000${NC}"
  echo -e "    OpenClaw             ${CYAN}http://${NODE_B_REMOTE_IP}:18789${NC}"
  echo -e "    Portainer            ${CYAN}http://${NODE_B_REMOTE_IP}:9000${NC}"
fi

echo ""
if [ "$DEPLOY_ERRORS" -gt 0 ]; then
  echo -e "  ${YELLOW}Completed with ${DEPLOY_ERRORS} warning(s) — review output above.${NC}"
  echo ""
  echo "  Troubleshooting tips:"
  echo "    - Verify Tailscale:   tailscale status"
  echo "    - Check SSH access:   ssh ${NODE_B_SSH_USER}@${NODE_B_REMOTE_IP}"
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
