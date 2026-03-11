#!/usr/bin/env bash
# =============================================================================
# Project Chimera — Health Verification Script
# Checks all services are running and responding correctly.
#
# Usage:
#   bash scripts/verify-all.sh              # check all services
#   bash scripts/verify-all.sh --media      # check media stack only
#   bash scripts/verify-all.sh --ai         # check AI stack only
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed
# =============================================================================

set -uo pipefail

NODE_B="${NODE_B_IP:-192.168.1.222}"
HA="${HA_IP:-192.168.1.149}"
PASS=0; FAIL=0

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓${NC} $*"; (( PASS++ )) || true; }
fail() { echo -e "  ${RED}✗${NC} $*"; (( FAIL++ )) || true; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
hdr()  { echo -e "\n${BOLD}${CYAN}$*${NC}"; }

# ─── HTTP check helper ────────────────────────────────────────────────────────
check_http() {
  local label="$1"; local url="$2"; local expected="${3:-200}"
  local code
  code=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "${url}" 2>/dev/null || echo "000")
  if [[ "${code}" == "${expected}" || "${code}" =~ ^[23] ]]; then
    ok "${label} (HTTP ${code})"
  else
    fail "${label} — HTTP ${code} from ${url}"
  fi
}

# ─── Docker container check helper ───────────────────────────────────────────
check_container() {
  local name="$1"
  local state
  state=$(docker inspect --format='{{.State.Status}}' "${name}" 2>/dev/null || echo "missing")
  local health
  health=$(docker inspect --format='{{.State.Health.Status}}' "${name}" 2>/dev/null || echo "none")
  if [[ "${state}" == "running" ]]; then
    if [[ "${health}" == "healthy" || "${health}" == "none" ]]; then
      ok "${name} running${health:+ (${health})}"
    elif [[ "${health}" == "starting" ]]; then
      warn "${name} running (health: starting — may need more time)"
    else
      fail "${name} running but unhealthy (${health})"
    fi
  elif [[ "${state}" == "missing" ]]; then
    warn "${name} not found (not deployed yet?)"
  else
    fail "${name} — state: ${state}"
  fi
}

# ─── Mount check ─────────────────────────────────────────────────────────────
check_mount() {
  local path="$1"; local label="$2"
  if mountpoint -q "${path}" 2>/dev/null; then
    ok "${label} (${path})"
  else
    fail "${label} not mounted: ${path}"
  fi
}

echo -e "\n${BOLD}Project Chimera — Service Health Check${NC}"
echo "=========================================="
echo "  Node B: ${NODE_B}  |  HA: ${HA}"

# ─── Parse args ───────────────────────────────────────────────────────────────
CHECK_ALL=true; CHECK_MEDIA=false; CHECK_AI=false
for arg in "$@"; do
  case "$arg" in
    --media) CHECK_MEDIA=true; CHECK_ALL=false ;;
    --ai)    CHECK_AI=true;    CHECK_ALL=false ;;
  esac
done
[[ "${CHECK_ALL}" == true ]] && CHECK_MEDIA=true && CHECK_AI=true

# ─── Infrastructure ──────────────────────────────────────────────────────────
if [[ "${CHECK_ALL}" == true ]]; then
  hdr "Stack 01 — Infrastructure"
  check_container "portainer"
  check_container "homepage"
  check_container "uptime-kuma"
  check_container "dozzle"
  check_container "watchtower"

  check_http "Portainer API"      "http://${NODE_B}:9000/api/status"
  check_http "Homepage"           "http://${NODE_B}:8010/api/healthcheck"
  check_http "Uptime Kuma"        "http://${NODE_B}:3010"
  check_http "Dozzle"             "http://${NODE_B}:8888/healthcheck"
fi

# ─── AI Core ─────────────────────────────────────────────────────────────────
if [[ "${CHECK_AI}" == true ]]; then
  hdr "Stack 02 — AI Core"
  check_container "ollama"
  check_container "n8n"
  check_container "whisper-api"
  check_container "wyoming-whisper"
  check_container "wyoming-piper"
  check_container "searxng"
  check_container "open-webui"

  check_http "Ollama API"         "http://${NODE_B}:11434/api/version"
  check_http "n8n"                "http://${NODE_B}:5678/healthz"
  check_http "Whisper API"        "http://${NODE_B}:9191/health"
  check_http "Open WebUI"         "http://${NODE_B}:3002"
  check_http "SearXNG"            "http://${NODE_B}:8082"
fi

# ─── DUMB Core ────────────────────────────────────────────────────────────────
if [[ "${CHECK_MEDIA}" == true ]]; then
  hdr "Stack 03 — DUMB Core (Real-Debrid)"
  check_container "zurg"
  check_container "rclone-zurg"
  check_container "riven-db"
  check_container "riven"
  check_container "riven-frontend"
  check_container "zilean"

  check_http "Zurg WebDAV"        "http://${NODE_B}:9999/dav/"
  check_http "Riven backend"      "http://${NODE_B}:8080/health"
  check_http "Riven frontend"     "http://${NODE_B}:3001"
  check_http "Zilean"             "http://${NODE_B}:8181/healthz/ping"

  check_mount "/mnt/debrid"       "DEBRID_MOUNT (/mnt/debrid)"

  # Check symlinks directory has content
  if [[ -d "/mnt/debrid/riven_symlinks" ]]; then
    count=$(find /mnt/debrid/riven_symlinks -maxdepth 2 -type l 2>/dev/null | wc -l)
    if [[ "${count}" -gt 0 ]]; then
      ok "Riven symlinks: ${count} found in /mnt/debrid/riven_symlinks"
    else
      warn "Riven symlinks: none yet (expected after first content request)"
    fi
  else
    fail "Riven symlinks directory missing: /mnt/debrid/riven_symlinks"
  fi
fi

# ─── Media *arr ───────────────────────────────────────────────────────────────
if [[ "${CHECK_MEDIA}" == true ]]; then
  hdr "Stack 04 — Media *arr"
  check_container "prowlarr"
  check_container "sonarr"
  check_container "radarr"
  check_container "lidarr"
  check_container "readarr"
  check_container "bazarr"
  check_container "flaresolverr"
  check_container "decypharr"
  check_container "decluttarr"

  check_http "Prowlarr"           "http://${NODE_B}:9696/api/v1/health"
  check_http "Sonarr"             "http://${NODE_B}:8989/api/v3/health"
  check_http "Radarr"             "http://${NODE_B}:7878/api/v3/health"
  check_http "Lidarr"             "http://${NODE_B}:8686/api/v1/health"
  check_http "Readarr"            "http://${NODE_B}:8787/api/v1/health"
  check_http "Bazarr"             "http://${NODE_B}:6767/api/system/status"
  check_http "FlareSolverr"       "http://${NODE_B}:8191/v1"
  check_http "Decypharr"          "http://${NODE_B}:8282"
fi

# ─── Media Servers ────────────────────────────────────────────────────────────
if [[ "${CHECK_MEDIA}" == true ]]; then
  hdr "Stack 05 — Media Servers"
  check_container "plex"
  check_container "jellyfin"
  check_container "navidrome"
  check_container "audiobookshelf"

  check_http "Plex identity"      "http://${NODE_B}:32400/identity"
  check_http "Jellyfin"           "http://${NODE_B}:8096/health"
  check_http "Navidrome"          "http://${NODE_B}:4533/ping"
  check_http "Audiobookshelf"     "http://${NODE_B}:13378/ping"
fi

# ─── Media Management ────────────────────────────────────────────────────────
if [[ "${CHECK_MEDIA}" == true ]]; then
  hdr "Stack 07 — Media Management"
  check_container "overseerr"
  check_container "tautulli"
  check_container "maintainerr"
  check_container "huntarr"
  check_container "notifiarr"
  check_container "kometa"

  check_http "Overseerr"          "http://${NODE_B}:5055/api/v1/status"
  check_http "Tautulli"           "http://${NODE_B}:8181/status"
  check_http "Maintainerr"        "http://${NODE_B}:6246"
  check_http "Huntarr"            "http://${NODE_B}:9705"
fi

# ─── Books & Games ────────────────────────────────────────────────────────────
if [[ "${CHECK_MEDIA}" == true ]]; then
  hdr "Stack 06 — Books & Games"
  check_container "calibre-web"
  check_container "kavita"
  check_container "gamevault"
  check_container "romm"

  check_http "Calibre-Web"        "http://${NODE_B}:8083"
  check_http "Kavita"             "http://${NODE_B}:5000/api/health"
  check_http "GameVault"          "http://${NODE_B}:8998"
  check_http "Romm"               "http://${NODE_B}:9083"
fi

# ─── Home Assistant ──────────────────────────────────────────────────────────
if [[ "${CHECK_ALL}" == true ]]; then
  hdr "Node D — Home Assistant"
  check_http "Home Assistant"     "http://${HA}:8123/api/"
fi

# ─── Result ───────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────"
echo -e "  ${GREEN}Passed:${NC} ${PASS}  |  ${RED}Failed:${NC} ${FAIL}"
echo "────────────────────────────────────────"
if [[ "${FAIL}" -eq 0 ]]; then
  echo -e "\n  ${GREEN}${BOLD}All checks passed.${NC} Chimera is healthy.\n"
  exit 0
else
  echo -e "\n  ${RED}${BOLD}${FAIL} check(s) failed.${NC} Review output above.\n"
  echo "  Debug tips:"
  echo "    docker logs <container_name> --tail 50"
  echo "    docker inspect <container_name>"
  echo "    Open Dozzle at http://${NODE_B}:8888 for a live log view"
  exit 1
fi
