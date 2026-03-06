#!/usr/bin/env bash
# Fresh Rebuild 2026 — Node B Deploy
# Deploys: Infrastructure stack + AI stack to 192.168.1.222 (Unraid)
#
# Node B is the Unraid host — stacks are deployed via SSH.
# Both stacks share node-b/.env.
#
# Usage:
#   ./scripts/node-b/deploy.sh
#   DRYRUN=true ./scripts/node-b/deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DRYRUN="${DRYRUN:-false}"
run() { [[ "$DRYRUN" == "true" ]] && echo "[DRYRUN] $*" || "$@"; }

INVENTORY="${REPO_ROOT}/inventory/node-inventory.env"
[[ -f "$INVENTORY" ]] && source "$INVENTORY"  # shellcheck disable=SC1090
NODE_B_IP="${NODE_B_IP:-192.168.1.222}"
NODE_B_SSH_USER="${NODE_B_SSH_USER:-root}"
NODE_B_TS_IP="${NODE_B_TS_IP:-}"
HOST="$([[ -n "$NODE_B_TS_IP" ]] && echo "$NODE_B_TS_IP" || echo "$NODE_B_IP")"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1"; }

ENV_FILE="${REPO_ROOT}/node-b/.env"
INFRA_COMPOSE="${REPO_ROOT}/node-b/stacks/01-infra.yml"
AI_COMPOSE="${REPO_ROOT}/node-b/stacks/02-ai.yml"
REMOTE_DIR="/tmp/fresh-rebuild-node-b"

if [[ ! -f "$ENV_FILE" ]]; then
  err "node-b/.env not found — run: cp node-b/.env.example node-b/.env"
  exit 1
fi

echo ""
echo "Deploying Node B (${NODE_B_SSH_USER}@${HOST})"
echo "────────────────────────────────"

# 1. Create remote working directory and sync files
run ssh "${NODE_B_SSH_USER}@${HOST}" "mkdir -p ${REMOTE_DIR}/stacks"
run scp "$ENV_FILE"      "${NODE_B_SSH_USER}@${HOST}:${REMOTE_DIR}/.env"
run scp "$INFRA_COMPOSE" "${NODE_B_SSH_USER}@${HOST}:${REMOTE_DIR}/stacks/01-infra.yml"
run scp "$AI_COMPOSE"    "${NODE_B_SSH_USER}@${HOST}:${REMOTE_DIR}/stacks/02-ai.yml"

# 2. Deploy infra stack (portainer, homepage, uptime-kuma, dozzle, watchtower)
run ssh "${NODE_B_SSH_USER}@${HOST}" \
  "cd ${REMOTE_DIR} && docker compose -f stacks/01-infra.yml --env-file .env up -d"
ok "Node B infra stack deployed"

# 3. Deploy AI stack (ollama CUDA + n8n)
run ssh "${NODE_B_SSH_USER}@${HOST}" \
  "cd ${REMOTE_DIR} && docker compose -f stacks/02-ai.yml --env-file .env up -d"
ok "Node B AI stack deployed"
