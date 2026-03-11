#!/usr/bin/env bash
# =============================================================================
# Project Chimera — Ordered Full Deploy Script
# Deploys all new-system stacks in the correct dependency order.
#
# Usage:
#   bash scripts/deploy-all.sh            # deploy all stacks
#   bash scripts/deploy-all.sh --dry-run  # print commands without running
#   bash scripts/deploy-all.sh --stack 03 # deploy only stack 03
#
# Prerequisites:
#   1. bash scripts/setup-mounts.sh (run once as root)
#   2. cp .env.example .env && fill in all secrets
#   3. Edit /mnt/user/appdata/DUMB/zurg/config.yaml (add RD API key)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_DIR="${SCRIPT_DIR}/../stacks"
ENV_FILE="${SCRIPT_DIR}/../.env"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
info() { echo -e "${CYAN}→${NC}  $*"; }
die()  { echo -e "${RED}✗${NC}  $*" >&2; exit 1; }
step() { echo -e "\n${BOLD}${CYAN}[$*]${NC}"; }

# ─── Args ─────────────────────────────────────────────────────────────────────
DRY_RUN=false
ONLY_STACK=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --stack) shift; ONLY_STACK="${1:-}" ;;
    --stack=*) ONLY_STACK="${arg#--stack=}" ;;
  esac
done

# ─── Pre-flight ───────────────────────────────────────────────────────────────
step "Pre-flight checks"

[[ -f "${ENV_FILE}" ]] || die ".env file not found. Run: cp .env.example .env && nano .env"
[[ -f "${STACKS_DIR}/01-infra.yml" ]] || die "Stacks directory not found: ${STACKS_DIR}"

# Check for insecure placeholder values in .env
INSECURE_VALS=("CHANGE_ME_INSECURE" "your-" "YOUR_")
for val in "${INSECURE_VALS[@]}"; do
  if grep -q "${val}" "${ENV_FILE}" 2>/dev/null; then
    warn ".env still contains placeholder value: '${val}'"
    warn "Check .env carefully before proceeding."
    # Not fatal — allow deploy with warning
  fi
done

# Check Docker is running
docker info &>/dev/null || die "Docker is not running. Enable Docker in Unraid: Settings → Docker"
ok "Docker is running"

# Check DEBRID_MOUNT is rshared
DEBRID_MOUNT="${DEBRID_MOUNT:-/mnt/debrid}"
if ! mountpoint -q "${DEBRID_MOUNT}" 2>/dev/null; then
  warn "${DEBRID_MOUNT} is not mounted yet. Run: sudo bash scripts/setup-mounts.sh"
  warn "Stack 03 (DUMB Core) will fail without this mount."
fi

# ─── Deploy function ──────────────────────────────────────────────────────────
run_stack() {
  local stack_num="$1"
  local stack_name="$2"
  local stack_file="${STACKS_DIR}/${stack_num}-${stack_name}.yml"

  # Skip if --stack filter is set and doesn't match
  if [[ -n "${ONLY_STACK}" && "${ONLY_STACK}" != "${stack_num}" ]]; then
    return 0
  fi

  [[ -f "${stack_file}" ]] || { warn "Stack file not found, skipping: ${stack_file}"; return 0; }

  step "Stack ${stack_num}: ${stack_name}"
  local cmd="docker compose --env-file ${ENV_FILE} -f ${stack_file} up -d"

  if [[ "${DRY_RUN}" == true ]]; then
    echo "  [DRY RUN] ${cmd}"
    return 0
  fi

  info "Running: ${cmd}"
  if eval "${cmd}"; then
    ok "Stack ${stack_num} deployed"
  else
    die "Stack ${stack_num} failed. Check logs: docker compose -f ${stack_file} logs"
  fi
}

wait_healthy() {
  local container="$1"
  local max_wait="${2:-120}"
  local waited=0

  info "Waiting for ${container} to be healthy (max ${max_wait}s)..."
  while true; do
    status=$(docker inspect --format='{{.State.Health.Status}}' "${container}" 2>/dev/null || echo "missing")
    if [[ "${status}" == "healthy" ]]; then
      ok "${container} is healthy"
      return 0
    fi
    if [[ "${waited}" -ge "${max_wait}" ]]; then
      warn "${container} did not become healthy in ${max_wait}s. Check: docker logs ${container}"
      return 1
    fi
    sleep 5
    (( waited += 5 ))
    echo -n "."
  done
}

# ─── Deploy sequence ──────────────────────────────────────────────────────────
echo -e "\n${BOLD}Project Chimera — Full Deploy${NC}"
echo "==============================="
[[ "${DRY_RUN}" == true ]] && echo -e "${YELLOW}DRY RUN MODE — no changes will be made${NC}\n"

# Stack 01: Infrastructure (must be first — Portainer manages everything else)
run_stack "01" "infra"

# Stack 02: AI Core (Ollama takes ~30s to start; n8n depends on it)
run_stack "02" "ai"
if [[ "${DRY_RUN}" == false && (-z "${ONLY_STACK}" || "${ONLY_STACK}" == "02") ]]; then
  wait_healthy "ollama" 120 || true
fi

# Stack 03: DUMB Core (Riven needs Zurg healthy; rclone needs Zurg first)
# This is the most critical stack. Zurg must connect to Real-Debrid successfully.
run_stack "03" "dumb-core"
if [[ "${DRY_RUN}" == false && (-z "${ONLY_STACK}" || "${ONLY_STACK}" == "03") ]]; then
  wait_healthy "zurg" 60 || warn "Zurg unhealthy — check your Real-Debrid API key in zurg/config.yaml"
  wait_healthy "riven" 90 || warn "Riven unhealthy — check: docker logs riven"
fi

# Stack 04: Media *arr (depends on media network from Stack 03)
run_stack "04" "media-arr"

# Stack 05: Media Servers (Plex/Jellyfin read from Riven symlinks)
run_stack "05" "media-servers"

# Stack 06: Books & Games (standalone, no dependencies)
run_stack "06" "media-books-games"

# Stack 07: Media Management (Overseerr connects to Plex + Radarr + Sonarr)
run_stack "07" "media-mgmt"

# ─── Summary ──────────────────────────────────────────────────────────────────
if [[ "${DRY_RUN}" == false ]]; then
  step "Deploy complete — running containers"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | \
    grep -E "(portainer|ollama|n8n|zurg|riven|plex|jellyfin|sonarr|radarr|overseerr|kometa|maintainerr)" || true

  echo ""
  echo -e "${BOLD}Next steps:${NC}"
  echo "  1. Open Portainer:     https://192.168.1.222:9443"
  echo "  2. Pull Ollama models: docker exec ollama ollama pull llama3.1:8b"
  echo "  3. Verify mounts:      ls /mnt/debrid/"
  echo "  4. Run health check:   bash scripts/verify-all.sh"
  echo "  5. Import n8n workflow: http://192.168.1.222:5678 → Import from file"
  echo "     File: n8n-workflows/media-voice-request.json"
  echo "  6. Configure HA:       Add home-assistant/configuration-snippet.yaml"
  echo ""
fi
