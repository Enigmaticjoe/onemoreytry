#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# deploy-renegade-node.sh — Sovereign AI Brain Node Installer
# Grand Unified AI Home Lab / Project Chimera
#
# Deploys the Brain Node (Ubuntu Server 25.10 / RTX 4070 / 192.168.1.9).
# This script is IDEMPOTENT: safe to run multiple times.
#
# Usage:
#   ./scripts/deploy-renegade-node.sh [--dry-run] [--skip-gpu] [--skip-mount]
#
# Options:
#   --dry-run     Print actions without executing them
#   --skip-gpu    Skip NVIDIA driver installation (already installed)
#   --skip-mount  Skip Unraid NFS mount configuration
#
# Prerequisites:
#   Ubuntu Server 25.10, internet access, SSH access to target node
#   Unraid NFS share at 192.168.1.222:/mnt/user/knowledge_base
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration — override with environment variables
# ─────────────────────────────────────────────────────────────────────────────
BRAIN_IP="${BRAIN_IP:-192.168.1.9}"
UNRAID_IP="${UNRAID_IP:-192.168.1.222}"
UNRAID_SHARE="${UNRAID_SHARE:-/mnt/user/knowledge_base}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/brain_memory}"
NFS_OPTS="${NFS_OPTS:-nfs defaults,_netdev,nofail 0 0}"
COMPOSE_DIR="${COMPOSE_DIR:-/home/renegade/compose}"
NVIDIA_PKG="${NVIDIA_PKG:-nvidia-headless-580-server}"
DOCKER_NETWORK="${DOCKER_NETWORK:-ai_internal}"
MAX_RETRIES=3

# ─────────────────────────────────────────────────────────────────────────────
# Parse CLI flags
# ─────────────────────────────────────────────────────────────────────────────
DRY_RUN=0
SKIP_GPU=0
SKIP_MOUNT=0
for arg in "$@"; do
    case $arg in
        --dry-run)   DRY_RUN=1 ;;
        --skip-gpu)  SKIP_GPU=1 ;;
        --skip-mount) SKIP_MOUNT=1 ;;
        -h|--help)
            sed -n '4,20p' "$0" | sed 's/^# //'
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            exit 1
            ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Colours & helpers
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[deploy]${NC} $*"; }
ok()    { echo -e "${GREEN}[deploy] ✓${NC} $*"; }
warn()  { echo -e "${YELLOW}[deploy] ⚠${NC} $*"; }
err()   { echo -e "${RED}[deploy] ✗${NC} $*" >&2; }
run()   {
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "${YELLOW}[dry-run]${NC} $*"
    else
        eval "$@"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# try_and_verify — retry wrapper with exponential back-off
# Usage: try_and_verify "description" "command" "check_command"
# ─────────────────────────────────────────────────────────────────────────────
try_and_verify() {
    local description="$1"
    local command="$2"
    local check_command="$3"
    local attempt=1

    info "Phase: ${description}"
    while [ $attempt -le $MAX_RETRIES ]; do
        run "$command"
        if [ "$DRY_RUN" = "1" ] || eval "$check_command"; then
            ok "$description"
            return 0
        fi
        warn "Failure (Attempt ${attempt}/${MAX_RETRIES}). Retrying in $((attempt * 2))s…"
        sleep $((attempt * 2))
        ((attempt++))
    done
    err "Failed to ${description} after ${MAX_RETRIES} attempts. Aborting."
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Preflight checks
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║   Sovereign AI Brain Node Installer — Project Chimera                   ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  Brain IP  : $BRAIN_IP"
echo "  Unraid IP : $UNRAID_IP"
echo "  Mount     : $MOUNT_POINT"
echo "  DRY RUN   : $DRY_RUN"
echo ""

if [ "$(id -u)" -ne 0 ] && [ "$DRY_RUN" = "0" ]; then
    err "This script must be run as root (or with sudo) on the target node."
    exit 1
fi

# Check for Rust-based coreutils and alias POSIX variants if needed
# Ubuntu 25.10 ships uutils (Rust coreutils); some flags differ.
if command -v uutils-ls >/dev/null 2>&1; then
    warn "Rust coreutils (uutils) detected.  Aliasing to POSIX variants."
    alias ls='ls --color=auto' 2>/dev/null || true
fi

# ─────────────────────────────────────────────────────────────────────────────
# Phase 1: Environmental Prep & GPU Configuration
# ─────────────────────────────────────────────────────────────────────────────
echo ""
info "═══ Phase 1: Environmental Prep & GPU Configuration ═══"

if [ "$SKIP_GPU" = "0" ]; then
    # Detect NVIDIA GPU presence
    if lspci 2>/dev/null | grep -qi nvidia; then
        try_and_verify \
            "Install NVIDIA headless drivers (${NVIDIA_PKG})" \
            "apt-get install -y ${NVIDIA_PKG} && apt-mark hold ${NVIDIA_PKG}" \
            "dpkg -l ${NVIDIA_PKG} 2>/dev/null | grep -q '^ii'"

        try_and_verify \
            "Blacklist nouveau driver" \
            "echo 'blacklist nouveau' | tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null && update-initramfs -u" \
            "grep -q 'blacklist nouveau' /etc/modprobe.d/blacklist-nouveau.conf"
    else
        warn "No NVIDIA GPU detected — skipping driver installation."
    fi
fi

try_and_verify \
    "Install Docker and docker-compose-plugin" \
    "apt-get install -y docker.io docker-compose-plugin && systemctl enable --now docker" \
    "docker info >/dev/null 2>&1"

try_and_verify \
    "Install NFS client utilities" \
    "apt-get install -y nfs-common" \
    "dpkg -l nfs-common 2>/dev/null | grep -q '^ii'"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 2: Storage Handshake (Unraid NFS mount)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
info "═══ Phase 2: Storage Handshake ═══"

if [ "$SKIP_MOUNT" = "0" ]; then
    FSTAB_ENTRY="${UNRAID_IP}:${UNRAID_SHARE} ${MOUNT_POINT} ${NFS_OPTS}"

    try_and_verify \
        "Create mount point ${MOUNT_POINT}" \
        "mkdir -p ${MOUNT_POINT}" \
        "[ -d ${MOUNT_POINT} ]"

    if ! grep -q "${UNRAID_IP}:${UNRAID_SHARE}" /etc/fstab 2>/dev/null; then
        try_and_verify \
            "Add NFS share to /etc/fstab" \
            "echo '${FSTAB_ENTRY}' | tee -a /etc/fstab > /dev/null" \
            "grep -q '${UNRAID_IP}:${UNRAID_SHARE}' /etc/fstab"
    else
        ok "NFS share already in /etc/fstab"
    fi

    try_and_verify \
        "Mount NFS share" \
        "mount -a" \
        "mountpoint -q ${MOUNT_POINT}"

    try_and_verify \
        "Write-test the NFS share" \
        "touch ${MOUNT_POINT}/.brain_write_test && rm -f ${MOUNT_POINT}/.brain_write_test" \
        "true"
fi

# Create required subdirectories
for d in ollama webui/config qdrant searxng scripts; do
    run "mkdir -p ${MOUNT_POINT}/${d}"
done
ok "Brain memory subdirectories created"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3: Container Orchestration & Model Seeding
# ─────────────────────────────────────────────────────────────────────────────
echo ""
info "═══ Phase 3: Container Orchestration & Model Seeding ═══"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/agent-governance/sovereign-brain-compose.yml"

# Generate a secure random secret, falling back to /dev/urandom if openssl is unavailable
generate_secret() {
    openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p -c 64
}

# Generate WEBUI_SECRET_KEY if not already set
if [ ! -f "${COMPOSE_DIR}/.env" ]; then
    run "mkdir -p ${COMPOSE_DIR}"
    WEBUI_SECRET=$(generate_secret)
    SEARXNG_SECRET=$(generate_secret)
    run "cat > ${COMPOSE_DIR}/.env << 'ENVEOF'
WEBUI_SECRET_KEY=${WEBUI_SECRET}
SEARXNG_SECRET_KEY=${SEARXNG_SECRET}
AGENT_MODE=SAFE
LOG_LEVEL=INFO
ENVEOF"
    ok "Generated ${COMPOSE_DIR}/.env with random secrets"
else
    ok "${COMPOSE_DIR}/.env already exists — skipping generation"
fi

try_and_verify \
    "Pull Docker images" \
    "docker compose -f ${COMPOSE_FILE} pull --quiet" \
    "true"

try_and_verify \
    "Start container stack" \
    "docker compose -f ${COMPOSE_FILE} up -d --remove-orphans" \
    "docker ps --filter 'name=brain-ollama' --filter 'status=running' | grep -q brain-ollama"

# Seed models (runs in background; ollama pull is idempotent)
info "Seeding LLM models (background)…"
MODELS=("dolphin-mixtral:8x7b-v2.7-q4_K_M" "nomic-embed-text:latest")
for model in "${MODELS[@]}"; do
    run "docker exec brain-ollama ollama pull '${model}' &" || \
        warn "Could not seed model ${model} — pull it manually later"
done
ok "Model seeding initiated"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 4: Governance & Evolution Deployment
# ─────────────────────────────────────────────────────────────────────────────
echo ""
info "═══ Phase 4: Governance & Evolution Deployment ═══"

# Install governance hooks
HOOKS_SRC="${REPO_ROOT}/agent-governance/hooks"
HOOKS_DST="${REPO_ROOT}/.git/hooks"
if [ -d "$HOOKS_DST" ]; then
    for hook in pre-commit; do
        if [ -f "${HOOKS_SRC}/${hook}" ]; then
            run "cp '${HOOKS_SRC}/${hook}' '${HOOKS_DST}/${hook}' && chmod +x '${HOOKS_DST}/${hook}'"
            ok "Installed git hook: ${hook}"
        fi
    done
    run "cp '${HOOKS_SRC}/destructive-check.sh' '${HOOKS_DST}/destructive-check.sh' && chmod +x '${HOOKS_DST}/destructive-check.sh'"
    ok "Installed destructive-check.sh"
fi

# Create log directory
run "mkdir -p /var/log/agent-governance"
run "chmod 750 /var/log/agent-governance 2>/dev/null || true"
ok "Audit log directory created: /var/log/agent-governance"

# Install systemd evolution service
EVOLUTION_SERVICE="/etc/systemd/system/brain-evolution.service"
if [ ! -f "$EVOLUTION_SERVICE" ]; then
    # Use unquoted heredoc delimiter so ${COMPOSE_FILE} is expanded into the unit file
    if [ "$DRY_RUN" = "0" ]; then
        cat > "${EVOLUTION_SERVICE}" << SVCEOF
[Unit]
Description=Brain Node - Agent Memory Pruning and Self-Evolution
After=network.target docker.service

[Service]
Type=oneshot
ExecStart=docker compose -f ${COMPOSE_FILE} run --rm brain-evolution
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

        TIMER_FILE="/etc/systemd/system/brain-evolution.timer"
        cat > "${TIMER_FILE}" << 'TIMEREOF'
[Unit]
Description=Run brain-evolution daily at 03:00

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
TIMEREOF
        systemctl daemon-reload && systemctl enable --now brain-evolution.timer
    else
        echo -e "${YELLOW}[dry-run]${NC} Would install brain-evolution.service and brain-evolution.timer"
    fi
    ok "Installed brain-evolution.timer (daily at 03:00)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Verification
# ─────────────────────────────────────────────────────────────────────────────
echo ""
info "═══ Verification ═══"

if [ "$DRY_RUN" = "0" ]; then
    echo ""
    echo "  Checking service health…"
    sleep 5

    SERVICES=("brain-ollama:11434" "brain-openwebui:3000" "brain-qdrant:6333")
    ALL_OK=1
    for svc in "${SERVICES[@]}"; do
        name="${svc%%:*}"
        port="${svc##*:}"
        if curl -sf "http://localhost:${port}/" >/dev/null 2>&1; then
            ok "${name} is reachable on :${port}"
        else
            warn "${name} not yet reachable on :${port} (may still be starting)"
            ALL_OK=0
        fi
    done

    if [ "$ALL_OK" = "1" ]; then
        echo ""
        echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}${BOLD}║  Brain Node deployed successfully!                               ║${NC}"
        echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    fi
fi

echo ""
echo "  Quick access:"
echo "    Open WebUI   : http://${BRAIN_IP}:3000"
echo "    Ollama API   : http://${BRAIN_IP}:11434"
echo "    Qdrant UI    : http://${BRAIN_IP}:6333/dashboard"
echo "    SearXNG      : http://${BRAIN_IP}:8082"
echo ""
echo "  View logs:"
echo "    docker compose -f ${COMPOSE_FILE} logs -f"
echo ""
