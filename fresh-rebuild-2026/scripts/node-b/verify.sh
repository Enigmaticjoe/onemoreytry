#!/usr/bin/env bash
# Fresh Rebuild 2026 — Node B Verify
# Checks all Node B services are healthy.
#
# Usage:
#   ./scripts/node-b/verify.sh
#   DRYRUN=true ./scripts/node-b/verify.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DRYRUN="${DRYRUN:-false}"

INVENTORY="${REPO_ROOT}/inventory/node-inventory.env"
[[ -f "$INVENTORY" ]] && source "$INVENTORY"  # shellcheck disable=SC1090
NODE_B_IP="${NODE_B_IP:-192.168.1.222}"
NODE_B_TS_IP="${NODE_B_TS_IP:-}"
HOST="$([[ -n "$NODE_B_TS_IP" ]] && echo "$NODE_B_TS_IP" || echo "$NODE_B_IP")"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; FAIL=$((${FAIL:-0}+1)); }
warn() { echo -e "${YELLOW}!${NC} $1"; }
FAIL=0

check_http() {
  local name="$1" url="$2"
  if curl -sf --max-time 10 "$url" &>/dev/null; then
    pass "${name} ${url}"
  else
    fail "${name} ${url} not reachable"
  fi
}

echo ""
echo "Verifying Node B (${HOST})"
echo "────────────────────────────────"

if [[ "$DRYRUN" == "true" ]]; then
  warn "DRYRUN — skipping live checks"
  exit 0
fi

check_http "Ollama CUDA API"  "http://${HOST}:11434/api/version"
check_http "Portainer CE"     "http://${HOST}:9000/api/status"
check_http "Homepage"         "http://${HOST}:8010/api/healthcheck"
check_http "Uptime Kuma"      "http://${HOST}:3010"
check_http "Dozzle"           "http://${HOST}:8888/healthcheck"
check_http "n8n"              "http://${HOST}:5678/healthz"

[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
