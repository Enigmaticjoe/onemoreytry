#!/usr/bin/env bash
# Fresh Rebuild 2026 — Node A Verify
# Checks Ollama ROCm API and Portainer Agent on Node A.
#
# Usage:
#   ./scripts/node-a/verify.sh
#   DRYRUN=true ./scripts/node-a/verify.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DRYRUN="${DRYRUN:-false}"

INVENTORY="${REPO_ROOT}/inventory/node-inventory.env"
[[ -f "$INVENTORY" ]] && source "$INVENTORY"  # shellcheck disable=SC1090
NODE_A_IP="${NODE_A_IP:-192.168.1.9}"
NODE_A_TS_IP="${NODE_A_TS_IP:-}"
HOST="$([[ -n "$NODE_A_TS_IP" ]] && echo "$NODE_A_TS_IP" || echo "$NODE_A_IP")"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; FAIL=$((${FAIL:-0}+1)); }
warn() { echo -e "${YELLOW}!${NC} $1"; }
FAIL=0

echo ""
echo "Verifying Node A (${HOST})"
echo "────────────────────────────────"

if [[ "$DRYRUN" == "true" ]]; then
  warn "DRYRUN — skipping live checks"
  exit 0
fi

# Ollama ROCm API
if curl -sf --max-time 10 "http://${HOST}:11435/api/version" &>/dev/null; then
  pass "Ollama ROCm API http://${HOST}:11435 is healthy"
else
  fail "Ollama ROCm API http://${HOST}:11435 not reachable"
fi

# Portainer Agent
if curl -sf --max-time 10 "http://${HOST}:9001" &>/dev/null; then
  pass "Portainer Agent http://${HOST}:9001 is responding"
else
  warn "Portainer Agent http://${HOST}:9001 not reachable (may require auth)"
fi

[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
