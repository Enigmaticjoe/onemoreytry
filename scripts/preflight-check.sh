#!/usr/bin/env bash
# Grand Unified AI Home Lab — Pre-flight Check Script
# Validates system readiness before deploying any nodes.
#
# Usage:
#   ./scripts/preflight-check.sh              # full check
#   ./scripts/preflight-check.sh --health-only  # only check running services

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
source "${REPO_ROOT}/scripts/lib-inventory.sh"
load_inventory "$REPO_ROOT"

HEALTH_ONLY=false
for arg in "$@"; do
  [[ "$arg" == "--health-only" ]] && HEALTH_ONLY=true
done

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0; WARN=0

pass() { echo -e "${GREEN}✓${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}✗${NC} $1"; ((FAIL++)); }
warn() { echo -e "${YELLOW}!${NC} $1"; ((WARN++)); }
info() { echo -e "${CYAN}→${NC} $1"; }

echo "═══════════════════════════════════════════════════"
echo "   Homelab Pre-Flight Check"
echo "═══════════════════════════════════════════════════"
echo ""

# ── Load node IPs from inventory/settings ─────────────────────────────────────
LITELLM_KEY="${LITELLM_API_KEY:-sk-master-key}"

# Try to read from deploy-gui settings
if [ -f "deploy-gui/data/settings.json" ]; then
  NODE_A_IP=$(python3 -c "import json,sys; s=json.load(open('deploy-gui/data/settings.json')); print(s['nodes']['nodeA']['ip'])" 2>/dev/null || echo "$NODE_A_IP")
  NODE_B_IP=$(python3 -c "import json,sys; s=json.load(open('deploy-gui/data/settings.json')); print(s['nodes']['nodeB']['ip'])" 2>/dev/null || echo "$NODE_B_IP")
  NODE_C_IP=$(python3 -c "import json,sys; s=json.load(open('deploy-gui/data/settings.json')); print(s['nodes']['nodeC']['ip'])" 2>/dev/null || echo "$NODE_C_IP")
fi

# Detect docker command (with sudo fallback)
DOCKER_CMD="docker"
detect_docker_cmd() {
  if command -v docker &>/dev/null; then
    if docker info &>/dev/null 2>&1; then
      DOCKER_CMD="docker"
      return 0
    elif sudo docker info &>/dev/null 2>&1; then
      DOCKER_CMD="sudo docker"
      return 0
    fi
  fi
  return 1
}

if [ "$HEALTH_ONLY" = false ]; then
  echo "1. System Requirements"
  echo "──────────────────────"

  # Docker — try without sudo first, then with sudo
  if command -v docker &>/dev/null; then
    if docker info &>/dev/null 2>&1; then
      pass "Docker is running ($(docker --version | cut -d' ' -f3 | tr -d ','))"
    elif sudo docker info &>/dev/null 2>&1; then
      warn "Docker requires sudo — running as $(whoami) without docker group"
      info "  Fix: sudo usermod -aG docker $(whoami) && newgrp docker"
      pass "Docker is running via sudo ($(docker --version | cut -d' ' -f3 | tr -d ','))"
    else
      fail "Docker is installed but the daemon is not running (sudo systemctl start docker)"
    fi
  else
    fail "Docker is not installed (see GUIDEBOOK.md §0.3)"
  fi

  detect_docker_cmd

  # Docker Compose
  if docker compose version &>/dev/null 2>&1 || $DOCKER_CMD compose version &>/dev/null 2>&1; then
    pass "Docker Compose plugin available"
  elif command -v docker-compose &>/dev/null; then
    warn "Legacy docker-compose found; prefer the compose plugin"
  else
    fail "Docker Compose not found"
  fi

  # Node.js
  if command -v node &>/dev/null; then
    NODE_VER=$(node --version | sed 's/v//')
    NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
    if [ "$NODE_MAJOR" -ge 20 ]; then
      pass "Node.js v${NODE_VER} (>= 20 required)"
    else
      fail "Node.js v${NODE_VER} is too old — need >= 20"
    fi
  else
    fail "Node.js not found (sudo dnf install nodejs -y)"
  fi

  # Python 3
  if command -v python3 &>/dev/null; then
    PY_VER=$(python3 --version 2>&1 | cut -d' ' -f2)
    pass "Python ${PY_VER}"
  else
    fail "Python 3 not found"
  fi

  # SSH client
  if command -v ssh &>/dev/null; then
    pass "SSH client available"
  else
    fail "SSH client not found (sudo dnf install openssh-clients -y)"
  fi

  # jq
  if command -v jq &>/dev/null; then
    pass "jq available"
  else
    warn "jq not found — install with: sudo dnf install jq -y"
  fi

  # curl
  if command -v curl &>/dev/null; then
    pass "curl available"
  else
    fail "curl not found — install with: sudo dnf install curl -y"
  fi

  echo ""
  echo "2. Configuration Files"
  echo "──────────────────────"

  # YAML syntax
  for f in node-b-litellm/config.yaml node-b-litellm/litellm-stack.yml node-c-arc/docker-compose.yml; do
    if python3 -c "import yaml; yaml.safe_load(open('$f'))" 2>/dev/null; then
      pass "YAML syntax OK: $f"
    else
      fail "YAML syntax error: $f"
    fi
  done

  # Required files
  for f in GUIDEBOOK.md validate.sh scripts/deploy-all.sh deploy-gui/deploy-gui.js openclaw/skill-kvm.md openclaw/skill-deploy.md; do
    if [ -f "$f" ]; then
      pass "File exists: $f"
    else
      fail "Missing file: $f"
    fi
  done

  # Executable scripts
  for f in validate.sh scripts/deploy-all.sh scripts/preflight-check.sh scripts/install-openclaw-deployer.sh; do
    if [ -x "$f" ]; then
      pass "Executable: $f"
    elif [ -f "$f" ]; then
      warn "Not executable (run: chmod +x $f): $f"
    fi
  done

  echo ""
  echo "3. Port Availability (local)"
  echo "─────────────────────────────"
  for port in 9999 3099 5000 3000 11434; do
    if ss -tlnp "sport = :$port" 2>/dev/null | grep -q LISTEN || \
       netstat -tlnp 2>/dev/null | grep -q ":$port "; then
      warn "Port ${port} is already in use (may be expected if service is running)"
    else
      pass "Port ${port} is free"
    fi
  done

  echo ""
  echo "4. Network & SSH Connectivity"
  echo "──────────────────────────────"

  # Ping all configured nodes
  for pair in "Node A:${NODE_A_IP}" "Node B:${NODE_B_IP}" "Node C:${NODE_C_IP}" "Node D:${NODE_D_IP:-}" "Node E:${NODE_E_IP:-}" "KVM:${KVM_IP:-}"; do
    label="${pair%%:*}"
    ip="${pair#*:}"
    if [ -z "$ip" ] || is_missing_or_placeholder_ip "$ip"; then
      continue
    fi
    if ping -c1 -W2 "$ip" &>/dev/null; then
      pass "Ping ${label} (${ip}) -- reachable"
    else
      warn "Ping ${label} (${ip}) -- unreachable"
    fi
  done

  echo ""

  # SSH to remote nodes
  for triple in "Node B:${NODE_B_IP}:${NODE_B_SSH_USER}" "Node C:${NODE_C_IP}:${NODE_C_SSH_USER:-root}"; do
    label="${triple%%:*}"
    rest="${triple#*:}"
    ip="${rest%%:*}"
    user="${rest#*:}"

    if is_missing_or_placeholder_ip "$ip"; then
      continue
    fi
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
         "${user}@${ip}" true &>/dev/null 2>&1; then
      pass "SSH ${label} (${user}@${ip}) -- connected"
    else
      warn "SSH ${label} (${user}@${ip}) -- failed (set up: ssh-copy-id ${user}@${ip})"
    fi
  done
  echo ""
fi

echo "5. Service Health (running services)"
echo "─────────────────────────────────────"

check_service() {
  local label="$1" url="$2" auth_header="${3:-}"
  local code
  if [ -n "$auth_header" ]; then
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -H "$auth_header" "$url" 2>/dev/null || echo "000")
  else
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
  fi
  if [[ "$code" =~ ^2 ]] || [[ "$code" =~ ^3 ]]; then
    pass "${label} -- HTTP ${code}"
  elif [ "$code" = "000" ]; then
    info "${label} -- not reachable (may not be running yet)"
  elif [ "$code" = "401" ]; then
    warn "${label} -- HTTP 401 (auth required, service is running)"
  else
    warn "${label} -- HTTP ${code}"
  fi
}

# Use /health/readiness for LiteLLM (doesn't require auth)
check_service "LiteLLM Gateway"    "http://${NODE_B_IP}:4000/health/readiness"
check_service "Ollama (Node C)"    "http://${NODE_C_IP}:11434/api/version"
check_service "Chimera Face UI"    "http://${NODE_C_IP}:3000"
check_service "Node A Dashboard"   "http://${NODE_A_IP}:3099/api/status"
check_service "KVM Operator"       "http://${NODE_A_IP}:5000/health"
check_service "OpenClaw"           "http://${NODE_B_IP}:18789/"
check_service "Portainer"          "http://${NODE_B_IP}:9000/api/status"
check_service "Deploy GUI"         "http://localhost:9999/api/status"

echo ""
echo "═══════════════════════════════════════════════════"
echo -e "   Results: ${GREEN}${PASS} passed${NC}  |  ${RED}${FAIL} failed${NC}  |  ${YELLOW}${WARN} warnings${NC}"
echo "═══════════════════════════════════════════════════"
echo ""

if [ $FAIL -gt 0 ]; then
  echo -e "${RED}Pre-flight FAILED — fix the errors above before deploying.${NC}"
  echo "See GUIDEBOOK.md for setup instructions."
  exit 1
elif [ $WARN -gt 0 ]; then
  echo -e "${YELLOW}Pre-flight PASSED with warnings.${NC}"
  echo "Review warnings above — some may block deployment."
  exit 0
else
  echo -e "${GREEN}Pre-flight PASSED — all checks OK.${NC}"
  echo ""
  echo "Next step: ./scripts/deploy-all.sh"
  exit 0
fi
