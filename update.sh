#!/usr/bin/env bash
# Safe update helper for NanoClaw stack.
# - Backs up memory/config
# - Pulls latest repo
# - Rebuilds image
# - Restores memory/config
# - Restarts through docker compose (Portainer equivalent can be used manually)

set -Eeuo pipefail

NANOCLAW_DIR="/mnt/user/appdata/nanoclaw"
REPO_DIR="${NANOCLAW_DIR}/repo"
BACKUP_DIR="${NANOCLAW_DIR}/backup/$(date +%Y%m%d-%H%M%S)"
COMPOSE_FILE="${NANOCLAW_DIR}/docker-compose.yml"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

if [[ ! -d "${REPO_DIR}/.git" ]]; then
  echo "Missing repo at ${REPO_DIR}; run deploy.sh first." >&2
  exit 1
fi

log "Creating backup at ${BACKUP_DIR}."
install -d -m 775 "$BACKUP_DIR"
cp -a "${NANOCLAW_DIR}/agents" "$BACKUP_DIR/agents" 2>/dev/null || true
cp -a "${NANOCLAW_DIR}/.mcp.json" "$BACKUP_DIR/.mcp.json" 2>/dev/null || true
cp -a "${NANOCLAW_DIR}/.env" "$BACKUP_DIR/.env" 2>/dev/null || true

log "Updating NanoClaw repository."
git -C "$REPO_DIR" fetch --all --prune
git -C "$REPO_DIR" pull --ff-only

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Compose file missing at ${COMPOSE_FILE}. Aborting." >&2
  exit 1
fi

log "Rebuilding and restarting stack via docker compose."
docker compose -f "$COMPOSE_FILE" build nanoclaw
docker compose -f "$COMPOSE_FILE" up -d nanoclaw

log "Restoring persisted memory/config (if needed)."
cp -a "$BACKUP_DIR/agents" "${NANOCLAW_DIR}/" 2>/dev/null || true
cp -a "$BACKUP_DIR/.mcp.json" "${NANOCLAW_DIR}/.mcp.json" 2>/dev/null || true

log "Update complete. If you rely strictly on Portainer API restarts, re-deploy stack in Portainer now."
