#!/usr/bin/env bash
# =============================================================================
# Project Chimera — DUMB AIO Mount Setup
# Run ONCE on the Unraid host before deploying Stack 03 (DUMB Core).
#
# What this does:
#   1. Creates /mnt/debrid and /mnt/debrid/riven_symlinks on the host
#   2. Bind-mounts /mnt/debrid on itself with rshared propagation
#      This is REQUIRED so that rclone's FUSE mount inside the container
#      is visible to OTHER containers that also bind-mount /mnt/debrid.
#   3. Creates /mnt/user/appdata/DUMB and /mnt/user/DUMB directory trees
#   4. Generates stub config files for Zurg and rclone
#
# Usage:
#   bash scripts/setup-mounts.sh
#
# Idempotent: safe to re-run. Will not overwrite existing config files.
# =============================================================================

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
info() { echo -e "${CYAN}→${NC}  $*"; }
die()  { echo -e "${RED}✗ FATAL:${NC} $*" >&2; exit 1; }

# ─── Config ───────────────────────────────────────────────────────────────────
DEBRID_MOUNT="${DEBRID_MOUNT:-/mnt/debrid}"
RIVEN_SYMLINKS="${RIVEN_SYMLINKS:-/mnt/debrid/riven_symlinks}"
APPDATA_PATH="${APPDATA_PATH:-/mnt/user/appdata/DUMB}"
MEDIA_PATH="${MEDIA_PATH:-/mnt/user/DUMB}"

echo -e "\n${BOLD}Project Chimera — DUMB AIO Mount Setup${NC}"
echo "==========================================="
echo "DEBRID_MOUNT  : ${DEBRID_MOUNT}"
echo "RIVEN_SYMLINKS: ${RIVEN_SYMLINKS}"
echo "APPDATA_PATH  : ${APPDATA_PATH}"
echo "MEDIA_PATH    : ${MEDIA_PATH}"
echo ""

# ─── 1. Check root ────────────────────────────────────────────────────────────
if [[ "${EUID}" -ne 0 ]]; then
  die "This script must run as root (use: sudo bash scripts/setup-mounts.sh)"
fi

# ─── 2. Create host directories ───────────────────────────────────────────────
info "Creating host directories..."

for dir in \
  "${DEBRID_MOUNT}" \
  "${RIVEN_SYMLINKS}" \
  "${APPDATA_PATH}/zurg" \
  "${APPDATA_PATH}/zurg/data" \
  "${APPDATA_PATH}/rclone" \
  "${APPDATA_PATH}/riven" \
  "${APPDATA_PATH}/riven-frontend" \
  "${APPDATA_PATH}/zilean" \
  "${APPDATA_PATH}/plex" \
  "${APPDATA_PATH}/jellyfin" \
  "${APPDATA_PATH}/navidrome" \
  "${APPDATA_PATH}/audiobookshelf" \
  "${APPDATA_PATH}/sonarr" \
  "${APPDATA_PATH}/radarr" \
  "${APPDATA_PATH}/lidarr" \
  "${APPDATA_PATH}/readarr" \
  "${APPDATA_PATH}/bazarr" \
  "${APPDATA_PATH}/prowlarr" \
  "${APPDATA_PATH}/overseerr" \
  "${APPDATA_PATH}/tautulli" \
  "${APPDATA_PATH}/maintainerr" \
  "${APPDATA_PATH}/recyclarr" \
  "${APPDATA_PATH}/huntarr" \
  "${APPDATA_PATH}/notifiarr" \
  "${APPDATA_PATH}/kometa" \
  "${APPDATA_PATH}/n8n" \
  "${APPDATA_PATH}/ollama" \
  "${APPDATA_PATH}/whisper" \
  "${APPDATA_PATH}/wyoming-whisper" \
  "${APPDATA_PATH}/wyoming-piper" \
  "${APPDATA_PATH}/searxng" \
  "${APPDATA_PATH}/open-webui" \
  "${APPDATA_PATH}/portainer" \
  "${APPDATA_PATH}/homepage/config" \
  "${APPDATA_PATH}/uptime-kuma" \
  "${APPDATA_PATH}/wizarr/data" \
  "${APPDATA_PATH}/tailscale" \
  "${APPDATA_PATH}/decypharr" \
  "${APPDATA_PATH}/gluetun" \
  "${APPDATA_PATH}/stremio" \
  "${APPDATA_PATH}/calibre-web" \
  "${APPDATA_PATH}/kavita" \
  "${APPDATA_PATH}/komga" \
  "${APPDATA_PATH}/gamevault/images" \
  "${APPDATA_PATH}/gamevault/db" \
  "${APPDATA_PATH}/romm" \
  "${APPDATA_PATH}/romm/db" \
  "${MEDIA_PATH}/movies" \
  "${MEDIA_PATH}/tv" \
  "${MEDIA_PATH}/music" \
  "${MEDIA_PATH}/audiobooks" \
  "${MEDIA_PATH}/podcasts" \
  "${MEDIA_PATH}/books" \
  "${MEDIA_PATH}/comics" \
  "${MEDIA_PATH}/manga" \
  "${MEDIA_PATH}/games" \
  "${MEDIA_PATH}/roms" \
  "${MEDIA_PATH}/bios" \
  "${MEDIA_PATH}/downloads"; do
  if [[ ! -d "${dir}" ]]; then
    mkdir -p "${dir}"
    ok "Created ${dir}"
  else
    echo "  (exists) ${dir}"
  fi
done

# ─── 3. Apply correct ownership ───────────────────────────────────────────────
info "Setting ownership to 99:100 (Unraid nobody:users)..."
chown -R 99:100 "${APPDATA_PATH}" "${MEDIA_PATH}"
ok "Ownership set"

# ─── 4. Configure rshared bind mount for DEBRID_MOUNT ─────────────────────────
# This is the critical step that allows rclone's FUSE mount (inside a container)
# to propagate to other containers that also bind-mount /mnt/debrid.
# Without this, Plex, Riven, etc. see an empty /mnt/debrid.
info "Configuring rshared bind mount at ${DEBRID_MOUNT}..."

if mountpoint -q "${DEBRID_MOUNT}"; then
  # Check if it's already rshared
  if findmnt -n -o PROPAGATION "${DEBRID_MOUNT}" 2>/dev/null | grep -q "shared"; then
    ok "${DEBRID_MOUNT} is already an rshared bind mount"
  else
    mount --make-rshared "${DEBRID_MOUNT}"
    ok "Applied rshared propagation to existing mount"
  fi
else
  mount --bind "${DEBRID_MOUNT}" "${DEBRID_MOUNT}"
  mount --make-rshared "${DEBRID_MOUNT}"
  ok "Bind-mounted and set rshared: ${DEBRID_MOUNT}"
fi

# ─── 5. Make the mount persistent (Unraid user script approach) ───────────────
PERSIST_SCRIPT="/boot/config/plugins/user.scripts/scripts/chimera-mounts/script"
if [[ ! -f "${PERSIST_SCRIPT}" ]]; then
  warn "Unraid user script not yet created."
  warn "To make the bind mount survive reboots:"
  warn "  1. Install the 'User Scripts' plugin from Unraid Community Apps"
  warn "  2. Add a new script named 'chimera-mounts'"
  warn "  3. Set schedule to: At Startup of Array"
  warn "  4. Paste these commands into the script:"
  echo ""
  echo "  #!/bin/bash"
  echo "  mkdir -p ${DEBRID_MOUNT} ${RIVEN_SYMLINKS}"
  echo "  mountpoint -q ${DEBRID_MOUNT} || mount --bind ${DEBRID_MOUNT} ${DEBRID_MOUNT}"
  echo "  mount --make-rshared ${DEBRID_MOUNT}"
  echo ""
fi

# ─── 6. Generate Zurg config.yaml stub ────────────────────────────────────────
ZURG_CONFIG="${APPDATA_PATH}/zurg/config.yaml"
if [[ ! -f "${ZURG_CONFIG}" ]]; then
  info "Generating Zurg config stub at ${ZURG_CONFIG}..."
  # Atomic write: mktemp → write → mv
  TMPFILE=$(mktemp)
  cat > "${TMPFILE}" << 'EOF'
# Zurg configuration — Project Chimera
# Replace YOUR_REAL_DEBRID_API_KEY with your token from https://real-debrid.com/apitoken
zurg: v1
token: YOUR_REAL_DEBRID_API_KEY

host: "[::]"
port: 9999
concurrent_workers: 20
check_for_changes_every_secs: 10
retain_folder_name_extension: true
retain_rd_torrent_name: true
auto_delete_rar_torrents: false

directories:
  shows:
    group: media
    group_order: 1
    filters:
      - regex: "(?i)(s\\d{2}e\\d{2}|season|series|complete|episode)"
  movies:
    group: media
    group_order: 2
    filters:
      - regex: "(?i)(1080p|2160p|720p|4k|bluray|bdrip|webrip|hdtv|hdrip)"
  anime:
    group: media
    group_order: 3
    filters:
      - regex: "(?i)(anime|\\[subsplease\\]|\\[erai\\]|\\[nyaa\\])"
  other:
    group_order: 99
    group: media
    only_show_the_biggest_file: false
EOF
  mv "${TMPFILE}" "${ZURG_CONFIG}"
  chown 99:100 "${ZURG_CONFIG}"
  ok "Created ${ZURG_CONFIG}"
  warn "EDIT ${ZURG_CONFIG} and replace YOUR_REAL_DEBRID_API_KEY before starting Stack 03!"
else
  ok "Zurg config already exists: ${ZURG_CONFIG}"
fi

# ─── 7. Generate rclone.conf stub ─────────────────────────────────────────────
RCLONE_CONF="${APPDATA_PATH}/rclone/rclone.conf"
if [[ ! -f "${RCLONE_CONF}" ]]; then
  info "Generating rclone.conf stub at ${RCLONE_CONF}..."
  TMPFILE=$(mktemp)
  cat > "${TMPFILE}" << EOF
[zurg]
type = webdav
url = http://zurg:9999/dav
vendor = other
pacer_min_sleep = 0
EOF
  mv "${TMPFILE}" "${RCLONE_CONF}"
  chown 99:100 "${RCLONE_CONF}"
  ok "Created ${RCLONE_CONF}"
else
  ok "rclone.conf already exists: ${RCLONE_CONF}"
fi

# ─── 8. Summary ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Setup complete!${NC}"
echo "==============="
echo ""
echo -e "Before deploying Stack 03 (DUMB Core):"
echo "  1. Edit ${ZURG_CONFIG}"
echo "     Replace: YOUR_REAL_DEBRID_API_KEY"
echo ""
echo "  2. Copy .env.example → .env and fill in all secrets"
echo "     cp .env.example .env && nano .env"
echo ""
echo "  3. Deploy in order:"
echo "     docker compose -f stacks/01-infra.yml up -d"
echo "     docker compose -f stacks/02-ai.yml up -d"
echo "     docker compose -f stacks/03-dumb-core.yml up -d"
echo "     (wait for Riven to be healthy, then continue)"
echo "     docker compose -f stacks/04-media-arr.yml up -d"
echo "     docker compose -f stacks/05-media-servers.yml up -d"
echo ""
echo "  4. Verify the mount is working:"
echo "     ls ${DEBRID_MOUNT}/"
echo "     (should show 'shows', 'movies', 'anime', 'other' after Zurg + rclone start)"
echo ""
