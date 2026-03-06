#!/usr/bin/env bash
# Fresh Rebuild 2026 — Pre-flight Check
#
# Validates system readiness before deploying any node.
# Reads node IPs from inventory/node-inventory.env (or falls back to defaults).
#
# Usage:
#   ./scripts/preflight.sh                  # full check
#   DRYRUN=true ./scripts/preflight.sh      # print checks without executing
#
# Exit code: 0 = all required checks pass, 1 = one or more failures

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ─── Dry-run support ──────────────────────────────────────────────────────────
DRYRUN="${DRYRUN:-false}"
run() {
  if [[ "$DRYRUN" == "true" ]]; then
    echo "[DRYRUN] $*"
  else
    "$@"
  fi
}

# ─── Load inventory ──────────────────────────────────────────────────────────
INVENTORY="${REPO_ROOT}/inventory/node-inventory.env"
if [[ -f "$INVENTORY" ]]; then
  # shellcheck disable=SC1090
  source "$INVENTORY"
fi
NODE_A_IP="${NODE_A_IP:-192.168.1.9}"
NODE_B_IP="${NODE_B_IP:-192.168.1.222}"
NODE_C_IP="${NODE_C_IP:-192.168.1.6}"
NODE_A_SSH_USER="${NODE_A_SSH_USER:-root}"
NODE_B_SSH_USER="${NODE_B_SSH_USER:-root}"
NODE_C_SSH_USER="${NODE_C_SSH_USER:-root}"
NODE_A_TS_IP="${NODE_A_TS_IP:-}"
NODE_B_TS_IP="${NODE_B_TS_IP:-}"
NODE_C_TS_IP="${NODE_C_TS_IP:-}"

# Prefer Tailscale IPs when set
resolve_ip() { local ts="${1:-}" lan="${2:-}"; [[ -n "$ts" ]] && echo "$ts" || echo "$lan"; }
REACH_A="$(resolve_ip "$NODE_A_TS_IP" "$NODE_A_IP")"
REACH_B="$(resolve_ip "$NODE_B_TS_IP" "$NODE_B_IP")"
REACH_C="$(resolve_ip "$NODE_C_TS_IP" "$NODE_C_IP")"

# ─── Colours & counters ───────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
PASS=0; FAIL=0; WARN=0

pass() { echo -e "${GREEN}✓${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}✗${NC} $1"; ((FAIL++)); }
warn() { echo -e "${YELLOW}!${NC} $1"; ((WARN++)); }
info() { echo -e "${CYAN}→${NC} $1"; }

# ─── Header ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}   Fresh Rebuild 2026 — Pre-flight Check${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
[[ "$DRYRUN" == "true" ]] && echo -e "  ${YELLOW}DRYRUN mode — no checks will actually be executed${NC}"
echo ""

# ─── 1. Local tooling ─────────────────────────────────────────────────────────
echo -e "${BOLD}1. Local Tooling${NC}"
echo "──────────────────────────────"

if command -v docker &>/dev/null && (docker info &>/dev/null 2>&1 || sudo docker info &>/dev/null 2>&1); then
  pass "Docker is running ($(docker --version | cut -d' ' -f3 | tr -d ','))"
else
  fail "Docker not running — install docker-ce and start the daemon"
fi

if docker compose version &>/dev/null 2>&1; then
  pass "Docker Compose plugin available"
elif command -v docker-compose &>/dev/null; then
  warn "Legacy docker-compose found — prefer the Compose v2 plugin"
else
  fail "Docker Compose not found"
fi

if command -v ssh &>/dev/null; then
  pass "ssh available"
else
  fail "ssh not found — install openssh-clients"
fi

if command -v curl &>/dev/null; then
  pass "curl available"
else
  warn "curl not found — install curl for healthcheck verification"
fi

echo ""

# ─── 2. .env files ───────────────────────────────────────────────────────────
echo -e "${BOLD}2. Environment Files${NC}"
echo "──────────────────────────────"

for node_env in node-a node-b node-c; do
  env_file="${REPO_ROOT}/${node_env}/.env"
  example_file="${REPO_ROOT}/${node_env}/.env.example"
  if [[ -f "$env_file" ]]; then
    pass "${node_env}/.env exists"
    # Check for placeholder insecure values
    if grep -q "CHANGE_ME_INSECURE" "$env_file" 2>/dev/null; then
      warn "${node_env}/.env still has CHANGE_ME_INSECURE placeholder — update before deploy"
    fi
  elif [[ -f "$example_file" ]]; then
    fail "${node_env}/.env missing — run: cp ${node_env}/.env.example ${node_env}/.env"
  fi
done

if [[ -f "${REPO_ROOT}/inventory/node-inventory.env" ]]; then
  pass "inventory/node-inventory.env exists"
else
  warn "inventory/node-inventory.env not found — using default IPs. Run: cp inventory/node-inventory.env.example inventory/node-inventory.env"
fi

echo ""

# ─── 3. Network reachability ─────────────────────────────────────────────────
echo -e "${BOLD}3. Network Reachability (ping + SSH)${NC}"
echo "──────────────────────────────"

check_node() {
  local name="$1" ip="$2" user="$3"
  if [[ "$DRYRUN" == "true" ]]; then
    info "[DRYRUN] Would ping $ip and test SSH ${user}@${ip}"
    return
  fi
  if ping -c 1 -W 2 "$ip" &>/dev/null 2>&1; then
    pass "${name} (${ip}) is reachable via ping"
  else
    fail "${name} (${ip}) is NOT reachable — check network/power"
    return
  fi
  if ssh -o ConnectTimeout=5 -o BatchMode=yes "${user}@${ip}" "echo ok" &>/dev/null 2>&1; then
    pass "${name} SSH ${user}@${ip} OK (key-based auth)"
  else
    warn "${name} SSH failed — set up key-based auth: ssh-copy-id ${user}@${ip}"
  fi
}

check_node "Node A" "$REACH_A" "$NODE_A_SSH_USER"
check_node "Node B" "$REACH_B" "$NODE_B_SSH_USER"
check_node "Node C" "$REACH_C" "$NODE_C_SSH_USER"

echo ""

# ─── 4. Ollama reachability (if nodes are up) ─────────────────────────────────
echo -e "${BOLD}4. Ollama API Health${NC}"
echo "──────────────────────────────"

check_ollama() {
  local name="$1" ip="$2" port="$3"
  if [[ "$DRYRUN" == "true" ]]; then
    info "[DRYRUN] Would check http://${ip}:${port}/api/version"
    return
  fi
  if curl -sf --max-time 5 "http://${ip}:${port}/api/version" &>/dev/null 2>&1; then
    pass "${name} Ollama API http://${ip}:${port} is healthy"
  else
    warn "${name} Ollama API http://${ip}:${port} not reachable — deploy node first"
  fi
}

check_ollama "Node A" "$REACH_A" "11435"
check_ollama "Node B" "$REACH_B" "11434"

echo ""

# ─── Summary ──────────────────────────────────────────────────────────────────
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "  Results:  ${GREEN}${PASS} passed${NC}  ${YELLOW}${WARN} warnings${NC}  ${RED}${FAIL} failed${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo -e "  ${RED}Pre-flight FAILED — resolve the above errors before deploying.${NC}"
  echo ""
  exit 1
else
  echo -e "  ${GREEN}Pre-flight PASSED — ready to deploy.${NC}"
  echo ""
fi
