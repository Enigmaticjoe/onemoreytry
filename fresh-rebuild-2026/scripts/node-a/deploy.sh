#!/usr/bin/env bash
# Fresh Rebuild 2026 — Node A Deploy
# Deploys: Ollama ROCm + Portainer Agent to 192.168.1.9 (Fedora 44)
#
# Usage:
#   ./scripts/node-a/deploy.sh
#   DRYRUN=true ./scripts/node-a/deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ─── Dry-run support ──────────────────────────────────────────────────────────
DRYRUN="${DRYRUN:-false}"
run() { [[ "$DRYRUN" == "true" ]] && echo "[DRYRUN] $*" || "$@"; }

# ─── Load inventory ──────────────────────────────────────────────────────────
INVENTORY="${REPO_ROOT}/inventory/node-inventory.env"
[[ -f "$INVENTORY" ]] && source "$INVENTORY"  # shellcheck disable=SC1090
NODE_A_IP="${NODE_A_IP:-192.168.1.9}"
NODE_A_SSH_USER="${NODE_A_SSH_USER:-root}"
NODE_A_TS_IP="${NODE_A_TS_IP:-}"
HOST="$([[ -n "$NODE_A_TS_IP" ]] && echo "$NODE_A_TS_IP" || echo "$NODE_A_IP")"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1"; }

COMPOSE="${REPO_ROOT}/node-a/compose.yml"
ENV_FILE="${REPO_ROOT}/node-a/.env"
REMOTE_DIR="/tmp/fresh-rebuild-node-a"

# ─── Guard: .env must exist ───────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  err "node-a/.env not found — run: cp node-a/.env.example node-a/.env"
  exit 1
fi

echo ""
echo "Deploying Node A (${NODE_A_SSH_USER}@${HOST})"
echo "────────────────────────────────"

# 1. Copy files to remote
run ssh "${NODE_A_SSH_USER}@${HOST}" "mkdir -p ${REMOTE_DIR}"
run scp "$COMPOSE" "${NODE_A_SSH_USER}@${HOST}:${REMOTE_DIR}/compose.yml"
run scp "$ENV_FILE" "${NODE_A_SSH_USER}@${HOST}:${REMOTE_DIR}/.env"

# 2. Up (idempotent: docker compose up -d is safe to re-run)
run ssh "${NODE_A_SSH_USER}@${HOST}" \
  "cd ${REMOTE_DIR} && docker compose -f compose.yml --env-file .env up -d"

ok "Node A compose deployed"
