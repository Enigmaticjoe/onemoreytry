#!/usr/bin/env bash
# Grand Unified AI Home Lab — Portainer CE Installer
#
# Installs Portainer CE on a target node via SSH.
# Installs Docker first if it is not present.
# Idempotent — safe to re-run if Portainer is already running.
#
# Usage:
#   ./scripts/portainer-install.sh --ip 192.168.1.222 --user root
#   ./scripts/portainer-install.sh --ip 192.168.1.222 --user root --port 9000
#   ./scripts/portainer-install.sh --local    # install on this machine
#
# Environment variables (override flags):
#   PORTAINER_IP, PORTAINER_USER, PORTAINER_PORT

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Argument parsing ──────────────────────────────────────────────────────────
TARGET_IP="${PORTAINER_IP:-}"
TARGET_USER="${PORTAINER_USER:-root}"
TARGET_PORT="${PORTAINER_PORT:-9000}"
LOCAL_INSTALL=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip)    TARGET_IP="$2";    shift ;;
    --user)  TARGET_USER="$2";  shift ;;
    --port)  TARGET_PORT="$2";  shift ;;
    --local) LOCAL_INSTALL=true ;;
    --json)  JSON_OUTPUT=true  ;;
    *) ;;
  esac
  shift
done

# ── Colors ────────────────────────────────────────────────────────────────────
source "${REPO_ROOT}/scripts/lib-colors.sh"
$JSON_OUTPUT && disable_colors

pass()   { $JSON_OUTPUT || echo -e "  ${GREEN}✓${NC} $1"; }
fail()   { $JSON_OUTPUT || echo -e "  ${RED}✗${NC} $1"; }
warn()   { $JSON_OUTPUT || echo -e "  ${YELLOW}!${NC} $1"; }
info()   { $JSON_OUTPUT || echo -e "    ${CYAN}→${NC} $1"; }
header() { $JSON_OUTPUT || echo -e "\n${BOLD}$1${NC}"; }

# ── Validate required args ────────────────────────────────────────────────────
if ! $LOCAL_INSTALL && [ -z "$TARGET_IP" ]; then
  echo "Usage: $0 --ip <IP> [--user <USER>] [--port <PORT>]" >&2
  echo "   or: $0 --local" >&2
  exit 1
fi

# ── Portainer install script (runs on the target) ─────────────────────────────
# This heredoc is shipped over SSH (or run locally) — all $ must be escaped
# except those we want evaluated on the *target*.
PORTAINER_INSTALL_SCRIPT='#!/usr/bin/env bash
set -euo pipefail

PORTAINER_PORT="${1:-9000}"
GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; NC="\033[0m"
pass() { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }

# 1. Ensure Docker is installed
if ! command -v docker &>/dev/null; then
  echo "Docker not found — installing Docker CE..."
  # Detect OS and install accordingly
  if command -v apt-get &>/dev/null; then
    apt-get update -qq
    apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  elif command -v dnf &>/dev/null; then
    dnf install -y docker docker-compose-plugin
    systemctl enable --now docker
  elif command -v yum &>/dev/null; then
    yum install -y docker docker-compose-plugin
    systemctl enable --now docker
  else
    fail "Unsupported OS — please install Docker manually: https://docs.docker.com/engine/install/"
  fi
  systemctl enable --now docker
  pass "Docker installed"
else
  DOCKER_VER=$(docker --version 2>/dev/null | grep -oP "\d+\.\d+\.\d+" | head -1 || echo "?")
  pass "Docker already installed (${DOCKER_VER})"
fi

# Ensure Docker daemon is running
if ! docker info &>/dev/null 2>&1; then
  echo "Starting Docker daemon..."
  systemctl start docker
  sleep 3
fi

# 2. Check if Portainer is already running
if docker inspect --format "{{.State.Status}}" portainer 2>/dev/null | grep -q running; then
  warn "Portainer is already running — skipping install"
  PORTAINER_IP=$(hostname -I 2>/dev/null | awk "{print \$1}" || echo "localhost")
  echo "PORTAINER_URL=http://${PORTAINER_IP}:${PORTAINER_PORT}"
  exit 0
fi

# 3. Remove stopped/failed portainer container if it exists
docker rm -f portainer 2>/dev/null || true

# 4. Create Portainer data volume
docker volume create portainer_data 2>/dev/null || true
pass "Portainer data volume ready"

# 5. Run Portainer CE
echo "Starting Portainer CE on port ${PORTAINER_PORT}..."
docker run -d \
  --name portainer \
  --restart always \
  -p "${PORTAINER_PORT}:9000" \
  -p 8000:8000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest

# 6. Wait for Portainer to become healthy
echo "Waiting for Portainer to start..."
MAX=20; I=0
while [ $I -lt $MAX ]; do
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
         "http://localhost:${PORTAINER_PORT}/api/status" 2>/dev/null || echo "000")
  if [[ "$HTTP" =~ ^2 ]]; then
    pass "Portainer is healthy (HTTP ${HTTP})"
    break
  fi
  I=$((I+1))
  echo "  Attempt ${I}/${MAX} (HTTP ${HTTP}) — retrying..."
  sleep 3
done

if [ $I -eq $MAX ]; then
  warn "Portainer may still be starting — check: docker logs portainer"
fi

PORTAINER_IP=$(hostname -I 2>/dev/null | awk "{print \$1}" || echo "localhost")
pass "Portainer CE installed!"
echo ""
echo "  Admin UI:  http://${PORTAINER_IP}:${PORTAINER_PORT}"
echo "  API:       http://${PORTAINER_IP}:${PORTAINER_PORT}/api"
echo ""
echo "  IMPORTANT: Open the Admin UI immediately to set your admin password."
echo "  The initial setup must be completed within 5 minutes or Portainer will lock."
echo ""
echo "PORTAINER_URL=http://${PORTAINER_IP}:${PORTAINER_PORT}"
'

# ── Execute install (local or remote) ────────────────────────────────────────
if ! $JSON_OUTPUT; then
  echo ""
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║   Portainer CE Installer                             ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""
fi

if $LOCAL_INSTALL; then
  header "Installing Portainer CE locally..."
  # Run the install script locally as root (or with sudo if needed)
  if [ "$(id -u)" -ne 0 ]; then
    echo "$PORTAINER_INSTALL_SCRIPT" | sudo bash -s -- "$TARGET_PORT"
  else
    echo "$PORTAINER_INSTALL_SCRIPT" | bash -s -- "$TARGET_PORT"
  fi
  EXIT_CODE=$?
else
  header "Installing Portainer CE on ${TARGET_USER}@${TARGET_IP}..."

  # Verify SSH connectivity first
  if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes \
           "${TARGET_USER}@${TARGET_IP}" true &>/dev/null 2>&1; then
    fail "Cannot connect via SSH to ${TARGET_USER}@${TARGET_IP}"
    info "Run ./scripts/ssh-auditor.sh --node ${TARGET_IP} --user ${TARGET_USER} to diagnose"
    if $JSON_OUTPUT; then
      echo "{\"ok\":false,\"error\":\"SSH connection failed\",\"url\":\"\"}"
    fi
    exit 1
  fi
  pass "SSH connection to ${TARGET_IP} verified"

  # Ship and execute the install script on the remote host
  OUTPUT=$(echo "$PORTAINER_INSTALL_SCRIPT" | \
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes \
        "${TARGET_USER}@${TARGET_IP}" \
        "bash -s -- ${TARGET_PORT}" 2>&1) || EXIT_CODE=$?
  EXIT_CODE=${EXIT_CODE:-0}

  if ! $JSON_OUTPUT; then
    echo "$OUTPUT"
  fi
fi

# ── Extract Portainer URL from output ────────────────────────────────────────
PORTAINER_URL=$(echo "${OUTPUT:-}" | grep "^PORTAINER_URL=" | cut -d= -f2 || echo "")
if [ -z "$PORTAINER_URL" ]; then
  PORTAINER_URL="http://${TARGET_IP:-localhost}:${TARGET_PORT}"
fi

if $JSON_OUTPUT; then
  if [ "${EXIT_CODE:-0}" -eq 0 ]; then
    echo "{\"ok\":true,\"url\":\"${PORTAINER_URL}\",\"output\":$(echo -n "${OUTPUT:-done}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}"
  else
    echo "{\"ok\":false,\"url\":\"\",\"error\":$(echo -n "${OUTPUT:-failed}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}"
  fi
else
  if [ "${EXIT_CODE:-0}" -eq 0 ]; then
    echo ""
    pass "Portainer install complete at ${PORTAINER_URL}"
  fi
fi
