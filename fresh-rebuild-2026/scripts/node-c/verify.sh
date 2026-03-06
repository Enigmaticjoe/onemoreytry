#!/usr/bin/env bash
# Fresh Rebuild 2026 — Node C Verify
# Checks Open WebUI health on Node C.
#
# Usage:
#   ./scripts/node-c/verify.sh
#   DRYRUN=true ./scripts/node-c/verify.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DRYRUN="${DRYRUN:-false}"

INVENTORY="${REPO_ROOT}/inventory/node-inventory.env"
[[ -f "$INVENTORY" ]] && source "$INVENTORY"  # shellcheck disable=SC1090
NODE_C_IP="${NODE_C_IP:-192.168.1.6}"
NODE_C_TS_IP="${NODE_C_TS_IP:-}"
HOST="$([[ -n "$NODE_C_TS_IP" ]] && echo "$NODE_C_TS_IP" || echo "$NODE_C_IP")"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; FAIL=$((${FAIL:-0}+1)); }
warn() { echo -e "${YELLOW}!${NC} $1"; }
FAIL=0

echo ""
echo "Verifying Node C (${HOST})"
echo "────────────────────────────────"

if [[ "$DRYRUN" == "true" ]]; then
  warn "DRYRUN — skipping live checks"
  exit 0
fi

if curl -sf --max-time 10 "http://${HOST}:3000/health" &>/dev/null; then
  pass "Open WebUI http://${HOST}:3000 is healthy"
else
  fail "Open WebUI http://${HOST}:3000 not reachable"
fi

[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
