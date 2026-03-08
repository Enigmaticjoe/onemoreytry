#!/usr/bin/env bash
set -euo pipefail

# Safe defaults
MODE="${MODE:-dry-run}"   # dry-run | apply
DEPLOY="${DEPLOY:-0}"      # 1 to deploy stacks after cleanup
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }; }
require docker

KEEP_CONTAINERS=(
  tailscale portainer-be homepage uptime-kuma dozzle watchtower cloudflared
  ollama browserless hf-openwebui hf-qdrant hf-redis hf-searxng hf-tei-embed
  gluetun zurg rclone-zurg rdt-client prowlarr sonarr radarr bazarr overseerr tautulli plex jellyfin flaresolverr
  n8n recommendarr wyoming-whisper wyoming-piper lidarr audiobookshelf
  nextcloud nextcloud-db stremio-server
)

# Known legacy duplicates/not-needed when moving to the consolidated nodebfinal stacks.
PRUNE_FIRST=(hf-browserless binhex-krusader qbittorrent stremio stremio-server-old)

echo "[INFO] Mode: $MODE"
echo "[INFO] Root: $ROOT_DIR"

mapfile -t ALL_CONTAINERS < <(docker ps -a --format '{{.Names}}' | sort -u)

if [[ ${#ALL_CONTAINERS[@]} -eq 0 ]]; then
  echo "[WARN] No containers found."
fi

is_keep() {
  local c="$1"
  for k in "${KEEP_CONTAINERS[@]}"; do
    [[ "$c" == "$k" ]] && return 0
  done
  return 1
}

TO_REMOVE=()
for c in "${ALL_CONTAINERS[@]}"; do
  if ! is_keep "$c"; then
    TO_REMOVE+=("$c")
  fi
done

# force include known legacy/duplicate names if present
for c in "${PRUNE_FIRST[@]}"; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$c"; then
    if ! printf '%s\n' "${TO_REMOVE[@]:-}" | grep -qx "$c"; then
      TO_REMOVE+=("$c")
    fi
  fi
done

echo "[INFO] Keep count: ${#KEEP_CONTAINERS[@]}"
echo "[INFO] Existing containers: ${#ALL_CONTAINERS[@]}"
echo "[INFO] Remove candidates: ${#TO_REMOVE[@]}"
printf '  - %s\n' "${TO_REMOVE[@]:-<none>}"

if [[ "$MODE" == "apply" ]]; then
  for c in "${TO_REMOVE[@]}"; do
    [[ -n "$c" ]] || continue
    echo "[APPLY] Removing $c"
    docker rm -f "$c" || true
  done

  echo "[APPLY] Pruning dangling networks/images"
  docker network prune -f || true
  docker image prune -f || true

  if [[ "$DEPLOY" == "1" ]]; then
    cd "$ROOT_DIR"
    echo "[APPLY] Deploying canonical stacks"
    docker compose -f stacks/01-infra-stack.yml up -d
    docker compose -f stacks/02-ai-stack.yml up -d
    docker compose -f stacks/07-ai-orchestration-stack.yml up -d
    docker compose -f stacks/03-media-stack.yml up -d
    docker compose -f stacks/04-automation-stack.yml up -d
    docker compose -f stacks/05-voice-stack.yml up -d
    docker compose -f stacks/06-conditional-stack.yml up -d
    docker compose -f stacks/08-cloud-apps-stack.yml up -d
  fi
else
  echo "[DRY-RUN] No destructive actions executed."
  echo "[DRY-RUN] To apply cleanup only: MODE=apply $0"
  echo "[DRY-RUN] To apply + deploy stacks: MODE=apply DEPLOY=1 $0"
fi
