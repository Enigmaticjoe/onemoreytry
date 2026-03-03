#!/bin/bash
# ==============================================================================
# Homelab Assistant — Local Bootstrap for Fedora 44 (cosmic nightly)
# ==============================================================================
# Usage:
#   sudo bash install.sh [--non-interactive] [--auto-start-chat]
#
# This script:
#   1. Verifies Fedora 44 (cosmic nightly) + dnf5
#   2. Installs minimal deps (python3, curl)
#   3. Runs boss_multi_agent_install.py from the local repo directory
#
# SELinux stays Enforcing. No X11 tools. DNF5 only.
# ==============================================================================

set -euo pipefail

# --- Constants ----------------------------------------------------------------
INSTALL_DIR="/opt/homelab"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
    if [[ "$ver" != "44" ]]; then
        log_warn "Expected Fedora 44, detected version: $ver"
        log_warn "Proceeding anyway — some commands may differ."
    else
        log_ok "Fedora 44 confirmed."
    fi
}

check_dnf5() {
    if ! command -v dnf5 &>/dev/null; then
        # On Fedora 44, 'dnf' should be dnf5
        if command -v dnf &>/dev/null; then
            local dnf_ver
            dnf_ver=$(dnf --version 2>/dev/null | head -1)
            if [[ "$dnf_ver" == dnf5* ]]; then
                log_ok "dnf is dnf5 ($dnf_ver)."
                return 0
            fi
        fi
        die "dnf5 not found. Is this Fedora 44?"
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

install_bootstrap_deps() {
    log_info "Installing bootstrap dependencies via dnf5..."
    local pkgs=()
    for pkg in curl python3 python3-pip; do
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

stage_installer() {
    log_info "Staging installer to $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
    # Find the installer script relative to this script's directory
    local src="$SCRIPT_DIR/$SCRIPT_NAME"
    if [[ ! -f "$src" ]]; then
        # Search within the repo directory
        src=$(find "$SCRIPT_DIR" -name "$SCRIPT_NAME" -type f | head -1)
    fi
    if [[ -z "$src" || ! -f "$src" ]]; then
        die "Cannot find $SCRIPT_NAME in $SCRIPT_DIR"
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
    echo -e "${CYAN}║  Homelab Assistant — Local Bootstrap (Fedora 44 cosmic)      ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_root
    check_fedora
    check_dnf5
    check_selinux
    install_bootstrap_deps
    stage_installer
    run_installer "$@"
}

main "$@"
