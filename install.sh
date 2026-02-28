#!/bin/bash
# ==============================================================================
# Homelab Assistant — One-Click Bootstrap for Fedora 43
# ==============================================================================
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Enigmaticjoe/onemoreytry/main/install.sh | sudo bash
#
# Or locally:
#   sudo bash install.sh [--non-interactive] [--auto-start-chat]
#
# This script:
#   1. Verifies Fedora 43 + dnf5
#   2. Installs minimal deps (git, python3, curl)
#   3. Clones the repo
#   4. Hands off to boss_multi_agent_install.py
#
# SELinux stays Enforcing. No X11 tools. DNF5 only.
# ==============================================================================

set -euo pipefail

# --- Constants ----------------------------------------------------------------
REPO_URL="https://github.com/Enigmaticjoe/onemoreytry.git"
INSTALL_DIR="/opt/homelab"
CLONE_DIR="${HOME}/onemoreytry"
SCRIPT_NAME="boss_multi_agent_install.py"
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Functions ----------------------------------------------------------------

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

die() { log_err "$*"; exit 1; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root. Use: sudo bash install.sh"
    fi
}

check_fedora() {
    if [[ ! -f /etc/fedora-release ]]; then
        die "This script targets Fedora. /etc/fedora-release not found."
    fi
    local ver
    ver=$(rpm -E %fedora 2>/dev/null || echo "unknown")
    if [[ "$ver" != "43" ]]; then
        log_warn "Expected Fedora 43, detected version: $ver"
        log_warn "Proceeding anyway — some commands may differ."
    else
        log_ok "Fedora 43 confirmed."
    fi
}

check_dnf5() {
    if ! command -v dnf5 &>/dev/null; then
        # On Fedora 43, 'dnf' should be dnf5
        if command -v dnf &>/dev/null; then
            local dnf_ver
            dnf_ver=$(dnf --version 2>/dev/null | head -1)
            if [[ "$dnf_ver" == dnf5* ]]; then
                log_ok "dnf is dnf5 ($dnf_ver)."
                return 0
            fi
        fi
        die "dnf5 not found. Is this Fedora 43?"
    fi
    log_ok "dnf5 available."
}

check_selinux() {
    if command -v getenforce &>/dev/null; then
        local mode
        mode=$(getenforce 2>/dev/null || echo "unknown")
        if [[ "$mode" == "Enforcing" ]]; then
            log_ok "SELinux: Enforcing (good)."
        elif [[ "$mode" == "Permissive" ]]; then
            log_warn "SELinux is Permissive. Enforcing recommended."
        else
            log_warn "SELinux status: $mode"
        fi
    fi
}

check_network() {
    log_info "Checking network connectivity..."
    if curl -sf --max-time 8 --head https://github.com >/dev/null 2>&1; then
        log_ok "Network OK (github.com reachable)."
    else
        die "Cannot reach github.com. Check DNS and firewall."
    fi
}

install_bootstrap_deps() {
    log_info "Installing bootstrap dependencies via dnf5..."
    local pkgs=()
    for pkg in git curl python3 python3-pip; do
        if ! rpm -q "$pkg" &>/dev/null; then
            pkgs+=("$pkg")
        fi
    done
    if [[ ${#pkgs[@]} -gt 0 ]]; then
        dnf5 install -y --setopt=install_weak_deps=False "${pkgs[@]}"
        log_ok "Installed: ${pkgs[*]}"
    else
        log_ok "Bootstrap deps already present."
    fi
}

clone_repo() {
    if [[ -d "$CLONE_DIR/.git" ]]; then
        log_info "Repository exists at $CLONE_DIR — updating..."
        git -C "$CLONE_DIR" pull --ff-only || log_warn "git pull failed, using existing."
    else
        log_info "Cloning $REPO_URL..."
        git clone --depth=1 "$REPO_URL" "$CLONE_DIR"
    fi
    log_ok "Repository ready at $CLONE_DIR"
}

stage_installer() {
    log_info "Staging installer to $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
    # Copy the installer script
    local src="$CLONE_DIR/$SCRIPT_NAME"
    if [[ ! -f "$src" ]]; then
        # Might be in a subdirectory — search
        src=$(find "$CLONE_DIR" -name "$SCRIPT_NAME" -type f | head -1)
    fi
    if [[ -z "$src" || ! -f "$src" ]]; then
        die "Cannot find $SCRIPT_NAME in $CLONE_DIR"
    fi
    cp -f "$src" "$INSTALL_DIR/$SCRIPT_NAME"
    chmod 755 "$INSTALL_DIR/$SCRIPT_NAME"
    log_ok "Installer staged at $INSTALL_DIR/$SCRIPT_NAME"
}

run_installer() {
    log_info "Launching Boss AI installer..."
    echo ""
    # Pass through any arguments
    python3 "$INSTALL_DIR/$SCRIPT_NAME" "$@"
}

# --- Main ---------------------------------------------------------------------

main() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Homelab Assistant — One-Click Bootstrap (Fedora 43)      ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_root
    check_fedora
    check_dnf5
    check_selinux
    check_network
    install_bootstrap_deps
    clone_repo
    stage_installer
    run_installer "$@"
}

main "$@"
