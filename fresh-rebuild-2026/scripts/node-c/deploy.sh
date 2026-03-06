#!/usr/bin/env bash
# Fresh Rebuild 2026 — Node C Deploy
# Deploys: Single Open WebUI instance to 192.168.1.6 (Fedora 44)
#
# Usage:
#   ./scripts/node-c/deploy.sh
#   DRYRUN=true ./scripts/node-c/deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DRYRUN="${DRYRUN:-false}"
run() { [[ "$DRYRUN" == "true" ]] && echo "[DRYRUN] $*" || "$@"; }

INVENTORY="${REPO_ROOT}/inventory/node-inventory.env"
[[ -f "$INVENTORY" ]] && source "$INVENTORY"  # shellcheck disable=SC1090
NODE_C_IP="${NODE_C_IP:-192.168.1.6}"
NODE_C_SSH_USER="${NODE_C_SSH_USER:-root}"
NODE_C_TS_IP="${NODE_C_TS_IP:-}"
HOST="$([[ -n "$NODE_C_TS_IP" ]] && echo "$NODE_C_TS_IP" || echo "$NODE_C_IP")"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1"; }

COMPOSE="${REPO_ROOT}/node-c/compose.yml"
ENV_FILE="${REPO_ROOT}/node-c/.env"
REMOTE_DIR="/tmp/fresh-rebuild-node-c"

if [[ ! -f "$ENV_FILE" ]]; then
  err "node-c/.env not found — run: cp node-c/.env.example node-c/.env"
  exit 1
fi

echo ""
echo "Deploying Node C (${NODE_C_SSH_USER}@${HOST})"
echo "────────────────────────────────"

run ssh "${NODE_C_SSH_USER}@${HOST}" "mkdir -p ${REMOTE_DIR}"
run scp "$COMPOSE" "${NODE_C_SSH_USER}@${HOST}:${REMOTE_DIR}/compose.yml"
run scp "$ENV_FILE" "${NODE_C_SSH_USER}@${HOST}:${REMOTE_DIR}/.env"

run ssh "${NODE_C_SSH_USER}@${HOST}" \
  "cd ${REMOTE_DIR} && docker compose -f compose.yml --env-file .env up -d"

ok "Node C Open WebUI deployed"
