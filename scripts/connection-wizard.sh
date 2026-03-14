#!/usr/bin/env bash
# Grand Unified AI Home Lab — Interactive Connection Wizard
#
# Tests, troubleshoots, and fixes all node connections through a menu-driven
# interface covering SSH, Tailscale, and Cloudflare Tunnels.
#
# Usage:
#   ./scripts/connection-wizard.sh            # interactive menu
#   ./scripts/connection-wizard.sh --ssh      # jump directly to SSH menu
#   ./scripts/connection-wizard.sh --tailscale  # jump to Tailscale menu
#   ./scripts/connection-wizard.sh --cloudflare # jump to Cloudflare menu
#   ./scripts/connection-wizard.sh --all-checks # run all checks non-interactively

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

source "${REPO_ROOT}/scripts/lib-inventory.sh"
load_inventory "$REPO_ROOT"
source "${REPO_ROOT}/scripts/lib-colors.sh"

# ── Colors ────────────────────────────────────────────────────────────────────
pass()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail()   { echo -e "  ${RED}✗${NC} $1"; }
warn()   { echo -e "  ${YELLOW}!${NC} $1"; }
info()   { echo -e "    ${CYAN}→${NC} $1"; }
header() { echo -e "\n${BOLD}${BLUE}$1${NC}"; }
sep()    { echo -e "${CYAN}──────────────────────────────────────────────────────${NC}"; }
title()  { echo -e "\n${BOLD}${MAGENTA}$1${NC}\n"; }

# ── Node list (populated from lib-inventory.sh defaults) ──────────────────────
declare -a ALL_NODES=(
  "Node A (Brain):${NODE_A_IP}:${NODE_A_SSH_USER:-root}"
  "Node B (Unraid/LiteLLM):${NODE_B_IP}:${NODE_B_SSH_USER:-root}"
  "Node C (Intel Arc):${NODE_C_IP}:${NODE_C_SSH_USER:-root}"
)
[[ -n "${NODE_D_IP:-}" ]] && ! is_missing_or_placeholder_ip "$NODE_D_IP" && \
  ALL_NODES+=("Node D (Home Assistant):${NODE_D_IP}:root")
[[ -n "${NODE_E_IP:-}" ]] && ! is_missing_or_placeholder_ip "$NODE_E_IP" && \
  ALL_NODES+=("Node E (Sentinel):${NODE_E_IP}:root")

# ── Helper: test TCP port ─────────────────────────────────────────────────────
test_port() {
  local host="$1" port="$2"
  if (echo >/dev/tcp/"$host"/"$port") &>/dev/null 2>&1; then
    return 0
  elif command -v nc &>/dev/null; then
    nc -z -w3 "$host" "$port" &>/dev/null 2>&1 && return 0
  fi
  return 1
}

# ── Helper: prompt yes/no ─────────────────────────────────────────────────────
confirm() {
  local prompt="${1:-Continue?}"
  local answer
  printf "  %b%s [y/N]: %b" "${YELLOW}" "$prompt" "${NC}"
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

# ── Helper: press any key ─────────────────────────────────────────────────────
pause() {
  printf "\n  %bPress Enter to continue…%b" "${CYAN}" "${NC}"
  read -r _
}

# ── Helper: pick a node interactively ────────────────────────────────────────
pick_node() {
  echo ""
  echo -e "  ${BOLD}Select a node:${NC}"
  local i=1
  for entry in "${ALL_NODES[@]}"; do
    IFS=':' read -r label ip user <<< "$entry"
    printf "  %b%d)%b %s  %b(%s)%b\n" "${CYAN}" "$i" "${NC}" "$label" "${YELLOW}" "$ip" "${NC}"
    ((i++))
  done
  echo ""
  printf "  Enter number (or 0 to cancel): "
  read -r choice
  if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -eq 0 ]; then
    return 1
  fi
  local idx=$(( choice - 1 ))
  if [ "$idx" -ge "${#ALL_NODES[@]}" ]; then
    warn "Invalid selection"
    return 1
  fi
  IFS=':' read -r PICKED_LABEL PICKED_IP PICKED_USER <<< "${ALL_NODES[$idx]}"
  return 0
}

# ═════════════════════════════════════════════════════════════════════════════
#  SSH SECTION
# ═════════════════════════════════════════════════════════════════════════════

ssh_menu() {
  while true; do
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║   🔑  SSH Connection Manager                         ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    echo -e "  ${CYAN}1)${NC} Audit all nodes (SSH connectivity check)"
    echo -e "  ${CYAN}2)${NC} Test a single node"
    echo -e "  ${CYAN}3)${NC} Generate SSH key pair (if missing)"
    echo -e "  ${CYAN}4)${NC} Copy SSH key to a node (ssh-copy-id)"
    echo -e "  ${CYAN}5)${NC} Copy SSH key to ALL nodes"
    echo -e "  ${CYAN}6)${NC} Fix firewall on a node (open port 22)"
    echo -e "  ${CYAN}7)${NC} Show SSH key fingerprint / public key"
    echo -e "  ${CYAN}8)${NC} Run ssh-auditor.sh --auto-fix"
    echo -e "  ${CYAN}0)${NC} ← Back to main menu"
    echo ""
    printf "  Choose: "
    read -r opt
    case "$opt" in
      1) ssh_audit_all ;;
      2) ssh_test_single ;;
      3) ssh_generate_key ;;
      4) ssh_copy_key_one ;;
      5) ssh_copy_key_all ;;
      6) ssh_fix_firewall ;;
      7) ssh_show_key ;;
      8) ssh_autofix ;;
      0) return ;;
      *) warn "Invalid option" ;;
    esac
  done
}

ssh_audit_all() {
  header "SSH Audit — All Nodes"
  sep
  bash "${REPO_ROOT}/scripts/ssh-auditor.sh"
  pause
}

ssh_test_single() {
  header "Test SSH — Single Node"
  if ! pick_node; then return; fi
  sep
  echo ""
  echo -e "  Testing ${BOLD}${PICKED_LABEL}${NC}  (${PICKED_USER}@${PICKED_IP})"
  echo ""

  # Ping
  if ping -c1 -W2 "$PICKED_IP" &>/dev/null 2>&1; then
    pass "Ping ${PICKED_IP} — reachable"
  else
    fail "Ping ${PICKED_IP} — unreachable"
    info "Check that the machine is powered on and on the same network"
    pause; return
  fi

  # Port 22
  if test_port "$PICKED_IP" 22; then
    pass "Port 22 — open"
  else
    fail "Port 22 — closed or filtered"
    warn "SSH daemon may not be running, or a firewall is blocking port 22"
    info "Fix: select option 6 from the SSH menu to open port 22"
    pause; return
  fi

  # SSH key auth
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
       "${PICKED_USER}@${PICKED_IP}" true &>/dev/null 2>&1; then
    pass "SSH key auth — OK"
    info "You can connect with: ssh ${PICKED_USER}@${PICKED_IP}"
  else
    fail "SSH key auth — FAILED"
    info "Copy your SSH key: ssh-copy-id ${PICKED_USER}@${PICKED_IP}"
    info "Or select option 4 from the SSH menu"
  fi
  pause
}

ssh_generate_key() {
  header "Generate SSH Key Pair"
  sep
  local key_file="${HOME}/.ssh/id_ed25519"
  if [ -f "$key_file" ]; then
    pass "SSH key already exists: ${key_file}"
    info "Public key:"
    cat "${key_file}.pub" 2>/dev/null || warn "Public key file not found"
  else
    warn "No SSH key found at ${key_file}"
    if confirm "Generate a new ed25519 SSH key?"; then
      mkdir -p "${HOME}/.ssh"
      chmod 700 "${HOME}/.ssh"
      printf "  Comment (press Enter for default 'homelab'): "
      read -r comment
      comment="${comment:-homelab}"
      ssh-keygen -t ed25519 -C "$comment" -f "$key_file" -N ""
      pass "SSH key generated: ${key_file}"
      info "Public key:"
      cat "${key_file}.pub"
    fi
  fi
  pause
}

ssh_copy_key_one() {
  header "Copy SSH Key to a Node"
  if ! pick_node; then return; fi
  sep
  echo ""
  echo -e "  Copying your SSH public key to ${BOLD}${PICKED_LABEL}${NC}  (${PICKED_USER}@${PICKED_IP})"
  warn "You may be prompted for a password — this is the only time it's needed."
  echo ""
  if confirm "Proceed with ssh-copy-id ${PICKED_USER}@${PICKED_IP}?"; then
    ssh-copy-id -o StrictHostKeyChecking=no "${PICKED_USER}@${PICKED_IP}"
    echo ""
    # Verify
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
         "${PICKED_USER}@${PICKED_IP}" true &>/dev/null 2>&1; then
      pass "SSH key auth now works for ${PICKED_USER}@${PICKED_IP}"
    else
      warn "Key copy may have succeeded but auth test still failed"
      info "Check that sshd allows PubkeyAuthentication on the remote host"
    fi
  fi
  pause
}

ssh_copy_key_all() {
  header "Copy SSH Key to ALL Nodes"
  sep
  warn "You will be prompted for a password for each node."
  warn "Skip nodes where you already have key auth by pressing Ctrl+C once per node."
  echo ""
  for entry in "${ALL_NODES[@]}"; do
    IFS=':' read -r label ip user <<< "$entry"
    is_missing_or_placeholder_ip "$ip" && continue
    echo -e "\n  ${BOLD}${label}${NC}  (${user}@${ip})"
    if ping -c1 -W2 "$ip" &>/dev/null 2>&1; then
      if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
           "${user}@${ip}" true &>/dev/null 2>&1; then
        pass "Already have key auth for ${user}@${ip} — skipping"
        continue
      fi
      if confirm "Copy key to ${user}@${ip}?"; then
        ssh-copy-id -o StrictHostKeyChecking=no "${user}@${ip}" || true
      fi
    else
      warn "${ip} is unreachable — skipping"
    fi
  done
  pause
}

ssh_fix_firewall() {
  header "Fix Firewall — Open Port 22"
  if ! pick_node; then return; fi
  sep
  echo ""
  echo -e "  Target: ${BOLD}${PICKED_LABEL}${NC}  (${PICKED_USER}@${PICKED_IP})"
  echo ""

  # Detect firewall type via SSH (need existing access — may be passworded)
  local fw_type="unknown"
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
       "${PICKED_USER}@${PICKED_IP}" true &>/dev/null 2>&1; then
    fw_type=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
      "${PICKED_USER}@${PICKED_IP}" \
      "command -v ufw &>/dev/null && ufw status 2>/dev/null|grep -q active && echo ufw && exit; command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null|grep -q running && echo firewalld && exit; echo none" \
      2>/dev/null || echo "unknown")
  else
    warn "No SSH key access to ${PICKED_IP} — cannot detect firewall automatically"
    info "Connect to the machine via console and run one of:"
    info "  sudo ufw allow ssh && sudo ufw reload"
    info "  sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload"
    info "  sudo iptables -I INPUT -p tcp --dport 22 -j ACCEPT"
    pause; return
  fi

  echo -e "  Detected firewall: ${BOLD}${fw_type}${NC}"
  echo ""

  local fix_cmd=""
  case "$fw_type" in
    ufw)       fix_cmd="sudo ufw allow ssh && sudo ufw reload" ;;
    firewalld) fix_cmd="sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload" ;;
    none)      fix_cmd="systemctl enable --now sshd" ;;
    *)
      warn "Could not determine firewall type"
      info "Manually run on ${PICKED_IP}:"
      info "  sudo ufw allow ssh  OR  sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload"
      pause; return
      ;;
  esac

  info "Will run: ${fix_cmd}"
  if confirm "Apply firewall fix on ${PICKED_IP}?"; then
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes \
         "${PICKED_USER}@${PICKED_IP}" "$fix_cmd"; then
      pass "Firewall rule applied on ${PICKED_IP}"
    else
      fail "Firewall fix command failed"
      info "Try running it manually on ${PICKED_IP}"
    fi
  fi
  pause
}

ssh_show_key() {
  header "Your SSH Public Key"
  sep
  echo ""
  local found=false
  for key in "${HOME}/.ssh/id_ed25519.pub" "${HOME}/.ssh/id_rsa.pub" "${HOME}/.ssh/id_ecdsa.pub"; do
    if [ -f "$key" ]; then
      pass "Found: ${key}"
      echo ""
      cat "$key"
      echo ""
      found=true
    fi
  done
  $found || warn "No SSH public key found. Use option 3 to generate one."
  pause
}

ssh_autofix() {
  header "SSH Auditor — Auto-Fix Mode"
  sep
  bash "${REPO_ROOT}/scripts/ssh-auditor.sh" --auto-fix
  pause
}

# ═════════════════════════════════════════════════════════════════════════════
#  TAILSCALE SECTION
# ═════════════════════════════════════════════════════════════════════════════

tailscale_menu() {
  while true; do
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║   🌐  Tailscale VPN Manager                          ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    echo -e "  ${CYAN}1)${NC} Check Tailscale status (local)"
    echo -e "  ${CYAN}2)${NC} Install Tailscale (local)"
    echo -e "  ${CYAN}3)${NC} Connect / authenticate Tailscale (local)"
    echo -e "  ${CYAN}4)${NC} Show Tailscale peers (all known machines)"
    echo -e "  ${CYAN}5)${NC} Test connectivity to a node via Tailscale IP"
    echo -e "  ${CYAN}6)${NC} Install Tailscale on a remote node (via SSH)"
    echo -e "  ${CYAN}7)${NC} Connect a remote node to Tailscale (via SSH)"
    echo -e "  ${CYAN}0)${NC} ← Back to main menu"
    echo ""
    printf "  Choose: "
    read -r opt
    case "$opt" in
      1) ts_status ;;
      2) ts_install_local ;;
      3) ts_connect_local ;;
      4) ts_show_peers ;;
      5) ts_test_node ;;
      6) ts_install_remote ;;
      7) ts_connect_remote ;;
      0) return ;;
      *) warn "Invalid option" ;;
    esac
  done
}

ts_status() {
  header "Tailscale Status — Local Machine"
  sep
  if ! command -v tailscale &>/dev/null; then
    warn "Tailscale is not installed on this machine"
    info "Use option 2 to install it"
    pause; return
  fi
  local my_ip
  my_ip=$(tailscale ip -4 2>/dev/null | head -1 || echo "")
  if [ -n "$my_ip" ]; then
    pass "Tailscale is running"
    info "This machine's Tailscale IP: ${my_ip}"
  else
    warn "Tailscale is installed but not connected"
    info "Use option 3 to authenticate"
  fi
  echo ""
  tailscale status 2>/dev/null || warn "Could not get tailscale status"
  pause
}

ts_install_local() {
  header "Install Tailscale — Local Machine"
  sep
  if command -v tailscale &>/dev/null; then
    pass "Tailscale is already installed ($(tailscale version 2>/dev/null | head -1))"
  else
    if confirm "Install Tailscale on this machine?"; then
      echo ""
      curl -fsSL https://tailscale.com/install.sh | sh
      pass "Tailscale installation complete"
      info "Run option 3 to connect to your Tailscale network"
    fi
  fi
  pause
}

ts_connect_local() {
  header "Connect Tailscale — Local Machine"
  sep
  if ! command -v tailscale &>/dev/null; then
    warn "Tailscale is not installed. Use option 2 first."
    pause; return
  fi
  local my_ip
  my_ip=$(tailscale ip -4 2>/dev/null | head -1 || echo "")
  if [ -n "$my_ip" ]; then
    pass "Already connected. Tailscale IP: ${my_ip}"
    if confirm "Re-authenticate (useful if auth expired)?"; then
      sudo tailscale up --reset
    fi
  else
    info "Connecting to Tailscale network…"
    echo ""
    printf "  Extra flags for 'tailscale up' (e.g. --advertise-exit-node) or Enter to skip: "
    read -ra ts_flags
    sudo tailscale up "${ts_flags[@]+"${ts_flags[@]}"}"
    echo ""
    my_ip=$(tailscale ip -4 2>/dev/null | head -1 || echo "")
    if [ -n "$my_ip" ]; then
      pass "Connected! Tailscale IP: ${my_ip}"
    else
      warn "Not yet connected — check browser for auth link if prompted"
    fi
  fi
  pause
}

ts_show_peers() {
  header "Tailscale Peers"
  sep
  if ! command -v tailscale &>/dev/null; then
    warn "Tailscale is not installed on this machine"
    pause; return
  fi
  echo ""
  tailscale status 2>/dev/null || warn "Cannot retrieve Tailscale peer list"
  pause
}

ts_test_node() {
  header "Test Node via Tailscale IP"
  if ! pick_node; then return; fi
  sep
  echo ""
  echo -e "  Target: ${BOLD}${PICKED_LABEL}${NC}  (${PICKED_USER}@${PICKED_IP})"
  echo ""

  # Try to find this node's Tailscale IP from remote inventory
  local ts_ip=""
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
       "${PICKED_USER}@${PICKED_IP}" true &>/dev/null 2>&1; then
    ts_ip=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
      "${PICKED_USER}@${PICKED_IP}" \
      "command -v tailscale &>/dev/null && tailscale ip -4 2>/dev/null | head -1 || echo ''" \
      2>/dev/null || echo "")
    ts_ip="${ts_ip//[[:space:]]/}"
  fi

  if [ -z "$ts_ip" ]; then
    warn "No Tailscale IP found for ${PICKED_IP}"
    info "Check that Tailscale is installed and running on ${PICKED_IP}"
    info "Use option 6 to install Tailscale on the remote node"
    printf "  Enter Tailscale IP manually to test (or Enter to skip): "
    read -r ts_ip_manual
    ts_ip="${ts_ip_manual//[[:space:]]/}"
    if [ -z "$ts_ip" ]; then
      pause; return
    fi
  fi

  pass "Tailscale IP for ${PICKED_LABEL}: ${ts_ip}"
  echo ""

  if ping -c1 -W2 "$ts_ip" &>/dev/null 2>&1; then
    pass "Ping ${ts_ip} — reachable via Tailscale"
  else
    fail "Ping ${ts_ip} — not reachable via Tailscale"
    info "Make sure both machines are authenticated to the same Tailscale network"
  fi

  if test_port "$ts_ip" 22; then
    pass "Port 22 — open on Tailscale IP"
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
         "${PICKED_USER}@${ts_ip}" true &>/dev/null 2>&1; then
      pass "SSH via Tailscale — OK (${PICKED_USER}@${ts_ip})"
      info "You can now use Tailscale IP in your inventory: NODE_X_IP=${ts_ip}"
    else
      warn "SSH key auth failed on Tailscale IP — copy key: ssh-copy-id ${PICKED_USER}@${ts_ip}"
    fi
  fi
  pause
}

ts_install_remote() {
  header "Install Tailscale on a Remote Node"
  if ! pick_node; then return; fi
  sep
  echo ""
  echo -e "  Target: ${BOLD}${PICKED_LABEL}${NC}  (${PICKED_USER}@${PICKED_IP})"
  echo ""

  if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
       "${PICKED_USER}@${PICKED_IP}" true &>/dev/null 2>&1; then
    fail "SSH not available to ${PICKED_IP} — set up SSH key access first"
    pause; return
  fi

  # Check if already installed
  local already
  already=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
    "${PICKED_USER}@${PICKED_IP}" \
    "command -v tailscale &>/dev/null && echo installed || echo missing" 2>/dev/null || echo "missing")
  if [ "$already" = "installed" ]; then
    pass "Tailscale is already installed on ${PICKED_IP}"
    pause; return
  fi

  if confirm "Install Tailscale on ${PICKED_IP}?"; then
    info "Installing Tailscale on ${PICKED_IP}…"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=60 -o BatchMode=yes \
      "${PICKED_USER}@${PICKED_IP}" \
      "curl -fsSL https://tailscale.com/install.sh | sh"
    pass "Tailscale installation complete on ${PICKED_IP}"
    info "Use option 7 to connect it to your Tailscale network"
  fi
  pause
}

ts_connect_remote() {
  header "Connect Remote Node to Tailscale"
  if ! pick_node; then return; fi
  sep
  echo ""
  echo -e "  Target: ${BOLD}${PICKED_LABEL}${NC}  (${PICKED_USER}@${PICKED_IP})"
  echo ""

  if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
       "${PICKED_USER}@${PICKED_IP}" true &>/dev/null 2>&1; then
    fail "SSH not available to ${PICKED_IP}"
    pause; return
  fi

  local installed
  installed=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
    "${PICKED_USER}@${PICKED_IP}" \
    "command -v tailscale &>/dev/null && echo installed || echo missing" 2>/dev/null || echo "missing")
  if [ "$installed" != "installed" ]; then
    warn "Tailscale not installed on ${PICKED_IP}. Use option 6 first."
    pause; return
  fi

  local ts_ip
  ts_ip=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
    "${PICKED_USER}@${PICKED_IP}" \
    "tailscale ip -4 2>/dev/null | head -1 || echo ''" 2>/dev/null || echo "")
  ts_ip="${ts_ip//[[:space:]]/}"

  if [ -n "$ts_ip" ]; then
    pass "Already connected. Tailscale IP: ${ts_ip}"
    pause; return
  fi

  warn "Tailscale is installed but not connected on ${PICKED_IP}"
  info "Running 'sudo tailscale up' on ${PICKED_IP}…"
  info "A browser auth URL will appear — open it on any device to authorize this node."
  echo ""
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=60 \
    "${PICKED_USER}@${PICKED_IP}" \
    "sudo tailscale up" || true
  pause
}

# ═════════════════════════════════════════════════════════════════════════════
#  CLOUDFLARE SECTION
# ═════════════════════════════════════════════════════════════════════════════

cloudflare_menu() {
  while true; do
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║   ☁️  Cloudflare Tunnel Manager                      ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    echo -e "  ${CYAN}1)${NC} Check cloudflared status (local)"
    echo -e "  ${CYAN}2)${NC} Install cloudflared (local)"
    echo -e "  ${CYAN}3)${NC} Login to Cloudflare (authorize cloudflared)"
    echo -e "  ${CYAN}4)${NC} Create a new Cloudflare Tunnel"
    echo -e "  ${CYAN}5)${NC} List existing Cloudflare Tunnels"
    echo -e "  ${CYAN}6)${NC} Route a hostname through a tunnel"
    echo -e "  ${CYAN}7)${NC} Test Cloudflare tunnel URLs"
    echo -e "  ${CYAN}8)${NC} Show quick-start guide"
    echo -e "  ${CYAN}0)${NC} ← Back to main menu"
    echo ""
    printf "  Choose: "
    read -r opt
    case "$opt" in
      1) cf_status ;;
      2) cf_install ;;
      3) cf_login ;;
      4) cf_create_tunnel ;;
      5) cf_list_tunnels ;;
      6) cf_route_hostname ;;
      7) cf_test_urls ;;
      8) cf_quickstart ;;
      0) return ;;
      *) warn "Invalid option" ;;
    esac
  done
}

cf_status() {
  header "cloudflared Status"
  sep
  echo ""
  if command -v cloudflared &>/dev/null; then
    pass "cloudflared is installed ($(cloudflared version 2>/dev/null | head -1))"
    echo ""
    # Check for running tunnels
    if systemctl is-active cloudflared &>/dev/null 2>&1; then
      pass "cloudflared service is running (systemd)"
    else
      warn "cloudflared service is not running as a systemd service"
      info "You may have tunnel processes started manually"
    fi
    # List configured tunnels
    cloudflared tunnel list 2>/dev/null || warn "Not logged in — use option 3 to login"
  else
    warn "cloudflared is not installed"
    info "Use option 2 to install it"
  fi
  pause
}

cf_install() {
  header "Install cloudflared"
  sep
  if command -v cloudflared &>/dev/null; then
    pass "cloudflared is already installed ($(cloudflared version 2>/dev/null | head -1))"
    pause; return
  fi
  if confirm "Install cloudflared?"; then
    echo ""
    # Detect package manager
    if command -v apt-get &>/dev/null; then
      info "Installing via apt (Debian/Ubuntu)…"
      curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /tmp/cloudflare-main.gpg
      info "GPG key downloaded. Verify fingerprint manually if needed."
      sudo mv /tmp/cloudflare-main.gpg /usr/share/keyrings/cloudflare-main.gpg
      echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs 2>/dev/null || echo bullseye) main" \
        | sudo tee /etc/apt/sources.list.d/cloudflared.list
      sudo apt-get update -qq && sudo apt-get install -y cloudflared
    elif command -v dnf &>/dev/null; then
      info "Installing via dnf (Fedora/CentOS)…"
      sudo dnf install -y cloudflared || warn "dnf install failed. Install cloudflared manually from https://pkg.cloudflare.com/"
    else
      warn "No supported package manager found."
      warn "Install cloudflared manually: https://pkg.cloudflare.com/"
      pause; return
    fi
    if command -v cloudflared &>/dev/null; then
      pass "cloudflared installed: $(cloudflared version 2>/dev/null | head -1)"
    else
      warn "cloudflared installation could not be verified."
    fi
  fi
  pause
}

cf_login() {
  header "Login to Cloudflare"
  sep
  if ! command -v cloudflared &>/dev/null; then
    warn "cloudflared is not installed. Use option 2 first."
    pause; return
  fi
  echo ""
  info "A browser window will open to authorize cloudflared with your Cloudflare account."
  info "If running headlessly, copy and open the URL manually."
  echo ""
  if confirm "Start Cloudflare login?"; then
    cloudflared tunnel login
  fi
  pause
}

cf_create_tunnel() {
  header "Create a New Cloudflare Tunnel"
  sep
  if ! command -v cloudflared &>/dev/null; then
    warn "cloudflared is not installed. Use option 2 first."
    pause; return
  fi
  echo ""
  printf "  Tunnel name (e.g. homelab): "
  read -r tunnel_name
  if [ -z "$tunnel_name" ]; then
    warn "No tunnel name provided"
    pause; return
  fi
  cloudflared tunnel create "$tunnel_name"
  echo ""
  pass "Tunnel '${tunnel_name}' created"
  info "Next steps:"
  info "  1. Use option 6 to route a hostname to a local service"
  info "  2. Run: cloudflared tunnel run ${tunnel_name}"
  info "     Or install as a service: cloudflared service install"
  pause
}

cf_list_tunnels() {
  header "List Cloudflare Tunnels"
  sep
  if ! command -v cloudflared &>/dev/null; then
    warn "cloudflared is not installed."
    pause; return
  fi
  echo ""
  cloudflared tunnel list 2>/dev/null || warn "Could not list tunnels — are you logged in? (option 3)"
  pause
}

cf_route_hostname() {
  header "Route Hostname Through Tunnel"
  sep
  if ! command -v cloudflared &>/dev/null; then
    warn "cloudflared is not installed."
    pause; return
  fi
  echo ""
  printf "  Tunnel name: "
  read -r tunnel_name
  printf "  Hostname (e.g. litellm.yourdomain.com): "
  read -r hostname
  printf "  Local URL (e.g. http://localhost:4000): "
  read -r local_url
  if [ -z "$tunnel_name" ] || [ -z "$hostname" ] || [ -z "$local_url" ]; then
    warn "All fields are required"
    pause; return
  fi
  cloudflared tunnel route dns "$tunnel_name" "$hostname"
  echo ""
  info "Creating tunnel config for ${hostname} → ${local_url}"
  local config_dir="${HOME}/.cloudflared"
  mkdir -p "$config_dir"
  local config_file="${config_dir}/config.yml"
  if [ -f "$config_file" ]; then
    info "Adding ingress rule to existing config: ${config_file}"
    # Append before the catch-all; use printf to avoid sed injection from user input
    if grep -q "http_status:404" "$config_file"; then
      local tmp_file
      tmp_file=$(mktemp)
      while IFS= read -r line; do
        if [[ "$line" == *"http_status:404"* ]]; then
          printf '  - hostname: %s\n    service: %s\n' "$hostname" "$local_url" >> "$tmp_file"
        fi
        printf '%s\n' "$line" >> "$tmp_file"
      done < "$config_file"
      mv "$tmp_file" "$config_file"
    else
      printf '  - hostname: %s\n    service: %s\n' "$hostname" "$local_url" >> "$config_file"
    fi
  else
    local tunnel_id=""
    tunnel_id=$(cloudflared tunnel list 2>/dev/null | awk -v name="$tunnel_name" '$0 ~ name {print $1}' | head -1 || echo "")
    local cred_file="${config_dir}/${tunnel_id:-<TUNNEL_ID>}.json"
    cat > "$config_file" <<CFEOF
tunnel: ${tunnel_name}
credentials-file: ${cred_file}
ingress:
  - hostname: ${hostname}
    service: ${local_url}
  - service: http_status:404
CFEOF
    pass "Config written to ${config_file}"
    [ -z "$tunnel_id" ] && warn "Update credentials-file path with your actual tunnel ID (check: cloudflared tunnel list)"
  fi
  echo ""
  info "Start the tunnel with:  cloudflared tunnel run ${tunnel_name}"
  info "Or install as a service: sudo cloudflared service install && sudo systemctl start cloudflared"
  pause
}

cf_test_urls() {
  header "Test Cloudflare Tunnel URLs"
  sep
  echo ""
  info "Reading Cloudflare URLs from deploy-gui settings (if configured)…"
  local settings_file="${REPO_ROOT}/deploy-gui/data/settings.json"
  if [ -f "$settings_file" ] && command -v python3 &>/dev/null; then
    local cf_urls
    cf_urls=$(python3 -c "
import json
s = json.load(open('${settings_file}'))
cf = s.get('cloudflare', {})
for k, v in cf.items():
    if v:
        print(f'{k}={v}')
" 2>/dev/null || echo "")
    if [ -n "$cf_urls" ]; then
      while IFS='=' read -r key url; do
        [ -z "$url" ] && continue
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")
        if [[ "$code" =~ ^[23] ]]; then
          pass "${key}: ${url}  [HTTP ${code}]"
        elif [ "$code" = "000" ]; then
          fail "${key}: ${url}  [unreachable]"
        else
          warn "${key}: ${url}  [HTTP ${code}]"
        fi
      done <<< "$cf_urls"
    else
      warn "No Cloudflare URLs configured in deploy-gui settings"
      info "Add them in the Deploy GUI → Settings → Cloudflare Public URLs"
    fi
  else
    warn "Deploy GUI settings not found or python3 unavailable"
    echo ""
    printf "  Enter a Cloudflare URL to test (or Enter to skip): "
    read -r test_url
    if [ -n "$test_url" ]; then
      local code
      code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$test_url" 2>/dev/null || echo "000")
      [[ "$code" =~ ^[23] ]] && pass "Reachable: ${test_url}  [HTTP ${code}]" || \
        fail "Not reachable: ${test_url}  [HTTP ${code}]"
    fi
  fi
  pause
}

cf_quickstart() {
  header "Cloudflare Tunnel Quick-Start Guide"
  sep
  cat << 'GUIDE'

  ────────────────────────────────────────────────────────

  STEP 1 — Install cloudflared
    Option 2 in this menu  OR  manually via your package manager:
      sudo dnf install -y cloudflared        # Fedora/CentOS
      sudo apt-get install -y cloudflared    # Debian/Ubuntu
  STEP 2 — Login to Cloudflare
    cloudflared tunnel login
    (Opens browser / prints a URL to authorize your account)

  STEP 3 — Create a tunnel
    cloudflared tunnel create homelab

  STEP 4 — Route hostnames
    cloudflared tunnel route dns homelab litellm.yourdomain.com
    cloudflared tunnel route dns homelab openclaw.yourdomain.com
    cloudflared tunnel route dns homelab dashboard.yourdomain.com

  STEP 5 — Create config  (~/.cloudflared/config.yml)
    tunnel: homelab
    credentials-file: /root/.cloudflared/<TUNNEL_ID>.json
    ingress:
      - hostname: litellm.yourdomain.com
        service: http://192.168.1.222:4000
      - hostname: openclaw.yourdomain.com
        service: http://192.168.1.222:18789
      - hostname: dashboard.yourdomain.com
        service: http://localhost:3099
      - service: http_status:404

  STEP 6 — Start the tunnel
    cloudflared tunnel run homelab
    # or as a persistent service:
    sudo cloudflared service install
    sudo systemctl enable --now cloudflared

  STEP 7 — Save the public URLs in Deploy GUI → Settings
    Add your Cloudflare hostnames to the Cloudflare URLs section
    so the Ecosystem Links card shows them.

  ────────────────────────────────────────────────────────
GUIDE
  pause
}

# ═════════════════════════════════════════════════════════════════════════════
#  ALL CHECKS (non-interactive mode + menu option)
# ═════════════════════════════════════════════════════════════════════════════

run_all_checks() {
  clear
  echo ""
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║   🔍  Full Connection + Preflight Check              ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""

  header "1/3 — SSH Connectivity Audit"
  sep
  bash "${REPO_ROOT}/scripts/ssh-auditor.sh" || true
  echo ""

  header "2/3 — System Pre-Flight Check"
  sep
  bash "${REPO_ROOT}/scripts/preflight-check.sh" --health-only || true
  echo ""

  header "3/3 — Tailscale Status"
  sep
  if command -v tailscale &>/dev/null; then
    local my_ip
    my_ip=$(tailscale ip -4 2>/dev/null | head -1 || echo "")
    if [ -n "$my_ip" ]; then
      pass "Tailscale running — this machine's IP: ${my_ip}"
      tailscale status 2>/dev/null | head -20 || true
    else
      warn "Tailscale installed but not connected"
      info "Run: sudo tailscale up"
    fi
  else
    warn "Tailscale is not installed"
    info "Install: curl -fsSL https://tailscale.com/install.sh | sh"
  fi
  echo ""

  sep
  echo ""
  echo -e "  ${BOLD}All checks complete.${NC}"
  echo ""
  echo "  • Fix SSH issues:        select 1 → SSH menu → option 4 or 5 (copy keys)"
  echo "  • Fix Tailscale issues:  select 2 → Tailscale menu"
  echo "  • Set up Cloudflare:     select 3 → Cloudflare menu → option 8 (guide)"
  echo ""
}

# ═════════════════════════════════════════════════════════════════════════════
#  MAIN MENU
# ═════════════════════════════════════════════════════════════════════════════

main_menu() {
  while true; do
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║   🏠  Homelab Connection Wizard                      ║"
    echo "╠══════════════════════════════════════════════════════╣"
    echo "║   Fix SSH, Tailscale & Cloudflare for all nodes      ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    # Show a quick status summary
    local ts_status_line="not installed"
    command -v tailscale &>/dev/null && \
      ts_status_line=$(tailscale ip -4 2>/dev/null | head -1 || echo "not connected")
    echo -e "  Tailscale: ${CYAN}${ts_status_line}${NC}"
    local cf_status_line="not installed"
    command -v cloudflared &>/dev/null && cf_status_line="installed"
    echo -e "  cloudflared: ${CYAN}${cf_status_line}${NC}"
    echo ""
    echo -e "  ${BOLD}${GREEN}1)${NC} 🔑  SSH  — test, fix, copy keys"
    echo -e "  ${BOLD}${BLUE}2)${NC} 🌐  Tailscale — VPN mesh networking"
    echo -e "  ${BOLD}${YELLOW}3)${NC} ☁️   Cloudflare — public tunnel setup"
    echo -e "  ${BOLD}${CYAN}4)${NC} 🔍  Run ALL checks (SSH + Preflight + Tailscale)"
    echo -e "  ${BOLD}${MAGENTA}5)${NC} 📊  Open Deploy GUI (http://localhost:9999)"
    echo -e "  ${BOLD}0)${NC} 🚪  Exit"
    echo ""
    printf "  Choose: "
    read -r opt
    case "$opt" in
      1) ssh_menu ;;
      2) tailscale_menu ;;
      3) cloudflare_menu ;;
      4) run_all_checks; pause ;;
      5)
        info "Starting Deploy GUI…"
        if command -v xdg-open &>/dev/null; then
          xdg-open "http://localhost:9999" &>/dev/null & disown
          pass "Opened http://localhost:9999 in browser"
        else
          info "Open: http://localhost:9999"
        fi
        ;;
      0)
        echo ""
        echo -e "  ${GREEN}Goodbye!${NC}  All connection info saved."
        echo ""
        exit 0
        ;;
      *) warn "Invalid option — please enter 0–5" ;;
    esac
  done
}

# ═════════════════════════════════════════════════════════════════════════════
#  Entry Point
# ═════════════════════════════════════════════════════════════════════════════

# Parse direct-jump flags
case "${1:-}" in
  --ssh)        ssh_menu;        exit 0 ;;
  --tailscale)  tailscale_menu;  exit 0 ;;
  --cloudflare) cloudflare_menu; exit 0 ;;
  --all-checks) run_all_checks;  exit 0 ;;
  --help|-h)
    echo "Usage: $0 [--ssh|--tailscale|--cloudflare|--all-checks]"
    echo "       Run without arguments for interactive menu."
    exit 0
    ;;
esac

main_menu
