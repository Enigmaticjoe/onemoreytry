#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  SSH Pre-Auditor — Homelab Node Connectivity & Hardware Audit
# ══════════════════════════════════════════════════════════════════════════════
#
#  PURPOSE: Before running any deploy script, this auditor:
#    1. Discovers the best SSH route to every node (LAN → Tailscale fallback)
#    2. Tests and auto-fixes SSH connectivity issues
#    3. Checks/adjusts firewall rules on both sides
#    4. Installs Tailscale if LAN SSH is unavailable and Tailscale isn't setup
#    5. Inventories hardware (CPU/RAM/GPU/storage) on every reachable node
#    6. Checks what software is already installed (Docker, Portainer, containers)
#    7. Writes a connection map to /tmp/homelab-connmap.env for deploy scripts
#
#  USAGE:
#    ./scripts/ssh-auditor.sh                  # full audit all nodes
#    ./scripts/ssh-auditor.sh --node NODE_B    # audit a specific node
#    ./scripts/ssh-auditor.sh --fix-firewall   # auto-apply firewall fixes
#    ./scripts/ssh-auditor.sh --install-keys   # push SSH keys to all nodes
#    ./scripts/ssh-auditor.sh --tailscale      # force Tailscale path discovery
#    ./scripts/ssh-auditor.sh --report         # show last report only
#
#  OUTPUT:
#    /tmp/homelab-connmap.env   — connection map consumed by portainer-install.sh
#    /tmp/homelab-audit.md      — human-readable audit report
# ══════════════════════════════════════════════════════════════════════════════
set -uo pipefail
# Do NOT set -e — we want to continue past failures and report them

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONNMAP_FILE="/tmp/homelab-connmap.env"
REPORT_FILE="/tmp/homelab-audit.md"
SSH_TIMEOUT=6
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"
BATCH_SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=${SSH_TIMEOUT} -o BatchMode=yes -o LogLevel=ERROR"

# ── Flags ─────────────────────────────────────────────────────────────────────
FLAG_FIX_FIREWALL=false
FLAG_INSTALL_KEYS=false
FLAG_FORCE_TAILSCALE=false
FLAG_REPORT_ONLY=false
TARGET_NODE=""

for arg in "$@"; do
  case "$arg" in
    --fix-firewall)    FLAG_FIX_FIREWALL=true ;;
    --install-keys)    FLAG_INSTALL_KEYS=true ;;
    --tailscale)       FLAG_FORCE_TAILSCALE=true ;;
    --report)          FLAG_REPORT_ONLY=true ;;
    --node)            : ;;  # next arg is value
    *)
      # capture node name after --node
      if [[ "${prev_arg:-}" == "--node" ]]; then
        TARGET_NODE="${arg^^}"  # uppercase
      fi
      ;;
  esac
  prev_arg="$arg"
done

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'

ok()    { echo -e "  ${GREEN}✓${NC} $*"; }
fail()  { echo -e "  ${RED}✗${NC} $*"; }
warn()  { echo -e "  ${YELLOW}!${NC} $*"; }
info()  { echo -e "  ${CYAN}→${NC} $*"; }
step()  { echo ""; echo -e "${BOLD}${CYAN}── $* ──${NC}"; }
header(){ echo -e "${BOLD}${MAGENTA}$*${NC}"; }
sep()   { echo -e "${CYAN}────────────────────────────────────────────────────${NC}"; }

# ── Report buffer ─────────────────────────────────────────────────────────────
REPORT_LINES=()
rpt() { REPORT_LINES+=("$*"); }

# ── Load node inventory ───────────────────────────────────────────────────────
load_inventory() {
  local inv="${REPO_ROOT}/config/node-inventory.env"
  local example="${REPO_ROOT}/config/node-inventory.env.example"
  if [[ -f "$inv" ]]; then
    # shellcheck disable=SC1090
    source "$inv"
  elif [[ -f "$example" ]]; then
    warn "No config/node-inventory.env found — loading example defaults"
    warn "Copy and edit: cp config/node-inventory.env.example config/node-inventory.env"
    # shellcheck disable=SC1090
    source "$example"
  fi
  # Apply defaults
  NODE_A_IP="${NODE_A_IP:-}"; NODE_A_SSH_USER="${NODE_A_SSH_USER:-root}"
  NODE_B_IP="${NODE_B_IP:-}"; NODE_B_SSH_USER="${NODE_B_SSH_USER:-root}"
  NODE_C_IP="${NODE_C_IP:-}"; NODE_C_SSH_USER="${NODE_C_SSH_USER:-root}"
  NODE_D_IP="${NODE_D_IP:-}"; NODE_D_SSH_USER="${NODE_D_SSH_USER:-root}"
  NODE_E_IP="${NODE_E_IP:-}"; NODE_E_SSH_USER="${NODE_E_SSH_USER:-root}"
  # Tailscale IPs (optional — set in inventory if you have Tailscale)
  NODE_A_TS_IP="${NODE_A_TS_IP:-}"; NODE_B_TS_IP="${NODE_B_TS_IP:-}"
  NODE_C_TS_IP="${NODE_C_TS_IP:-}"; NODE_D_TS_IP="${NODE_D_TS_IP:-}"
  NODE_E_TS_IP="${NODE_E_TS_IP:-}"
  # Portainer
  PORTAINER_PORT="${PORTAINER_PORT:-9000}"
  PORTAINER_TOKEN="${PORTAINER_TOKEN:-}"
}

load_inventory

# ── Report-only mode ──────────────────────────────────────────────────────────
if [[ "$FLAG_REPORT_ONLY" == "true" ]]; then
  if [[ -f "$REPORT_FILE" ]]; then
    cat "$REPORT_FILE"
  else
    echo "No audit report found. Run: ./scripts/ssh-auditor.sh"
  fi
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   SSH Pre-Auditor — Homelab Node Connectivity & Inventory   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  This auditor checks every node before deployment."
echo "  It finds the best SSH route, audits hardware, checks software."
echo ""

rpt "# Homelab SSH Audit Report"
rpt ""
rpt "Generated: $(date)"
rpt ""

# ── Section 1: Local System ───────────────────────────────────────────────────
sep; header "SECTION 1 — LOCAL SYSTEM CHECKS"
rpt "## Section 1 — Local System"
rpt ""

step "SSH Key Setup"
if [[ -f "${SSH_KEY}.pub" ]]; then
  ok "SSH public key: ${SSH_KEY}.pub"
  rpt "- SSH key: \`${SSH_KEY}.pub\` ✓"
else
  warn "No SSH key at ${SSH_KEY} — generating one now..."
  ssh-keygen -t rsa -b 4096 -N "" -f "$SSH_KEY" 2>/dev/null && {
    ok "Generated new SSH key at ${SSH_KEY}"
    rpt "- SSH key generated at \`${SSH_KEY}\`"
  } || {
    fail "Could not generate SSH key — check permissions on ${HOME}/.ssh"
    rpt "- SSH key: MISSING ✗"
  }
fi

step "Local Firewall Check"
LOCAL_FW="none"
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  LOCAL_FW="ufw"
  ok "Local firewall: ufw (active)"
  rpt "- Local firewall: ufw (active)"
elif command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q running; then
  LOCAL_FW="firewalld"
  ok "Local firewall: firewalld (running)"
  rpt "- Local firewall: firewalld (running)"
elif command -v iptables &>/dev/null && iptables -L INPUT 2>/dev/null | grep -q "Chain INPUT"; then
  LOCAL_FW="iptables"
  warn "Local firewall: iptables (manual rules — review manually)"
  rpt "- Local firewall: iptables (manual)"
else
  info "No active local firewall detected"
  rpt "- Local firewall: none detected"
fi

step "Tailscale Status"
TAILSCALE_LOCAL=false
TAILSCALE_IP=""
if command -v tailscale &>/dev/null; then
  TS_STATUS=$(tailscale status 2>/dev/null || echo "")
  if echo "$TS_STATUS" | grep -q "^100\."; then
    TAILSCALE_LOCAL=true
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | head -1 || echo "")
    ok "Tailscale is active (local IP: ${TAILSCALE_IP})"
    rpt "- Tailscale: active, local IP \`${TAILSCALE_IP}\`"
  else
    warn "Tailscale installed but not connected (run: sudo tailscale up)"
    rpt "- Tailscale: installed but not connected"
  fi
else
  warn "Tailscale not installed locally"
  info "  If LAN SSH fails, Tailscale is the fallback — see Section 4 for install instructions"
  rpt "- Tailscale: not installed"
fi

step "Required Local Tools"
TOOLS_OK=true
for tool in ssh ssh-copy-id curl sshpass; do
  if command -v "$tool" &>/dev/null; then
    ok "$tool"
  else
    if [[ "$tool" == "sshpass" ]]; then
      warn "sshpass not found — password-based SSH fallback unavailable"
      warn "  Install: sudo apt install sshpass  or  sudo dnf install sshpass"
    else
      fail "$tool not found"
      TOOLS_OK=false
    fi
  fi
done
[[ "$TOOLS_OK" == "false" ]] && warn "Some required tools missing — install before continuing"

# ══════════════════════════════════════════════════════════════════════════════
# Connection Map — will be written at end
declare -A CONN_HOST
declare -A CONN_USER
declare -A CONN_METHOD
declare -A CONN_OK

# ══════════════════════════════════════════════════════════════════════════════
# ── Node audit function ────────────────────────────────────────────────────────
# audit_node <label> <lan_ip> <ssh_user> <ts_ip>
# Sets: CONN_HOST[label], CONN_USER[label], CONN_METHOD[label], CONN_OK[label]
# ══════════════════════════════════════════════════════════════════════════════
audit_node() {
  local label="$1" lan_ip="$2" ssh_user="$3" ts_ip="${4:-}"
  local connected=false conn_host="" conn_method="" conn_user="$ssh_user"

  echo ""
  sep
  header "NODE: ${label}  (LAN: ${lan_ip:-unset}  TS: ${ts_ip:-unset})"
  rpt ""
  rpt "### ${label}"
  rpt ""

  if [[ -z "$lan_ip" ]] || [[ "$lan_ip" == *"192.168.1.X"* ]]; then
    warn "IP not configured — skipping ${label}"
    rpt "- Status: skipped (IP not configured)"
    CONN_OK["$label"]="false"
    return
  fi

  # ── 1. Ping test ─────────────────────────────────────────────────────────
  step "Ping test"
  if ping -c1 -W3 "$lan_ip" &>/dev/null 2>&1; then
    ok "Ping ${lan_ip} — reachable"
    rpt "- Ping (LAN ${lan_ip}): reachable ✓"
    LAN_REACHABLE=true
  else
    warn "Ping ${lan_ip} — unreachable (host down or ICMP blocked)"
    rpt "- Ping (LAN ${lan_ip}): unreachable"
    LAN_REACHABLE=false
  fi

  # ── 2. Try SSH via LAN (multiple users and ports) ─────────────────────────
  if [[ "$LAN_REACHABLE" == "true" ]] && [[ "$FLAG_FORCE_TAILSCALE" == "false" ]]; then
    step "SSH via LAN"
    local lan_users=("$ssh_user" "root" "ubuntu" "pi" "admin" "user")
    local lan_ports=(22 2222 222)
    local dedup=()
    for u in "${lan_users[@]}"; do
      [[ " ${dedup[*]} " == *" $u "* ]] || dedup+=("$u")
    done

    for port in "${lan_ports[@]}"; do
      for user in "${dedup[@]}"; do
        if ssh ${BATCH_SSH_OPTS} -p "$port" "${user}@${lan_ip}" "true" 2>/dev/null; then
          ok "SSH connected: ${user}@${lan_ip}:${port}"
          connected=true; conn_host="$lan_ip"; conn_user="$user"
          conn_method="lan:${port}"
          rpt "- SSH (LAN): ${user}@${lan_ip}:${port} ✓"
          break 2
        fi
      done
    done

    if [[ "$connected" == "false" ]]; then
      warn "SSH via LAN failed for all user/port combinations"
      rpt "- SSH (LAN): failed"
      _diagnose_ssh_failure "$lan_ip" "$ssh_user"
    fi
  fi

  # ── 3. Try Tailscale fallback ─────────────────────────────────────────────
  if [[ "$connected" == "false" ]]; then
    local ts_target=""
    if [[ -n "$ts_ip" ]]; then
      ts_target="$ts_ip"
    elif [[ "$TAILSCALE_LOCAL" == "true" ]]; then
      # Try to discover node in tailscale peer list
      ts_target=$(tailscale status 2>/dev/null | grep -i "${label,,}" | awk '{print $1}' | head -1 || echo "")
    fi

    if [[ -n "$ts_target" ]]; then
      step "SSH via Tailscale (fallback)"
      if ssh ${BATCH_SSH_OPTS} "${ssh_user}@${ts_target}" "true" 2>/dev/null; then
        ok "SSH connected via Tailscale: ${ssh_user}@${ts_target}"
        connected=true; conn_host="$ts_target"; conn_user="$ssh_user"
        conn_method="tailscale"
        rpt "- SSH (Tailscale): ${ssh_user}@${ts_target} ✓"
      else
        warn "SSH via Tailscale also failed: ${ssh_user}@${ts_target}"
        rpt "- SSH (Tailscale): failed"
      fi
    fi
  fi

  # ── 4. Offer to push SSH keys ─────────────────────────────────────────────
  if [[ "$connected" == "false" ]]; then
    echo ""
    fail "Could not establish SSH connection to ${label}"
    echo ""
    echo -e "  ${YELLOW}Troubleshooting options:${NC}"
    echo -e "    a) Push SSH key (requires password once):"
    echo -e "       ssh-copy-id -i ${SSH_KEY}.pub ${ssh_user}@${lan_ip}"
    echo ""
    echo -e "    b) Open SSH port on remote firewall:"
    echo -e "       # On remote (Ubuntu/Debian): sudo ufw allow 22/tcp"
    echo -e "       # On remote (Fedora/RHEL):   sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload"
    echo ""
    echo -e "    c) Install Tailscale for tunnel access:"
    echo -e "       curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up"
    echo ""
    echo -e "    d) Run with --install-keys to auto-push keys (will prompt for password)"
    echo ""

    if [[ "$FLAG_INSTALL_KEYS" == "true" ]]; then
      info "Attempting to push SSH key to ${ssh_user}@${lan_ip} (will prompt for password)..."
      if ssh-copy-id -i "${SSH_KEY}.pub" "${ssh_user}@${lan_ip}" 2>/dev/null; then
        ok "SSH key pushed — retrying connection..."
        if ssh ${BATCH_SSH_OPTS} "${ssh_user}@${lan_ip}" "true" 2>/dev/null; then
          ok "SSH now working: ${ssh_user}@${lan_ip}"
          connected=true; conn_host="$lan_ip"; conn_user="$ssh_user"
          conn_method="lan:22 (key just pushed)"
          rpt "- SSH (after key push): ${ssh_user}@${lan_ip} ✓"
        fi
      else
        warn "ssh-copy-id failed — try manually or use Tailscale"
      fi
    fi
  fi

  CONN_OK["$label"]="$connected"
  CONN_HOST["$label"]="${conn_host:-}"
  CONN_USER["$label"]="${conn_user:-}"
  CONN_METHOD["$label"]="${conn_method:-none}"

  [[ "$connected" == "false" ]] && return

  # ══════════════════════════════════════════════════════════════════════════
  # Remote audit — runs on each connected node
  # ══════════════════════════════════════════════════════════════════════════
  step "Remote Hardware Audit"
  local ssh_target="${conn_user}@${conn_host}"
  local port_flag=""
  if [[ "$conn_method" == lan:* ]]; then
    local pnum="${conn_method#lan:}"
    [[ "$pnum" != "22" ]] && port_flag="-p $pnum"
  fi

  # Run a comprehensive remote audit in a single SSH session
  local remote_data
  remote_data=$(ssh ${BATCH_SSH_OPTS} ${port_flag} "$ssh_target" bash <<'ENDSSH' 2>/dev/null || echo "REMOTE_AUDIT_FAILED"
set -uo pipefail
echo "=== HARDWARE ==="
echo "HOSTNAME=$(hostname 2>/dev/null || echo unknown)"
echo "OS=$(grep -m1 PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || uname -a | cut -d' ' -f1-4)"
echo "KERNEL=$(uname -r 2>/dev/null)"
echo "CPU=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo unknown)"
echo "CORES=$(nproc 2>/dev/null || echo ?)"
echo "RAM_TOTAL=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo unknown)"
echo "RAM_FREE=$(free -h 2>/dev/null | awk '/^Mem:/{print $4}' || echo unknown)"
echo "DISK=$(df -h / 2>/dev/null | awk 'NR==2{print $4" free of "$2}' || echo unknown)"
echo "UPTIME=$(uptime -p 2>/dev/null || uptime 2>/dev/null | head -c60)"

echo "=== GPU ==="
# NVIDIA
if command -v nvidia-smi &>/dev/null; then
  GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total,memory.free,driver_version --format=csv,noheader 2>/dev/null | head -3)
  echo "NVIDIA_GPU=${GPU_INFO:-detected but query failed}"
else
  echo "NVIDIA_GPU=none"
fi
# AMD ROCm
if command -v rocm-smi &>/dev/null; then
  echo "AMD_GPU=$(rocm-smi --showproductname 2>/dev/null | head -1 | xargs || echo detected)"
elif lspci 2>/dev/null | grep -qi 'amd\|radeon'; then
  echo "AMD_GPU=AMD GPU detected (ROCm not installed)"
else
  echo "AMD_GPU=none"
fi
# Intel Arc
if lspci 2>/dev/null | grep -qi 'intel.*arc\|intel.*dg2\|xe graphics'; then
  echo "INTEL_GPU=Intel Arc detected"
elif ls /dev/dri/renderD* &>/dev/null 2>&1; then
  echo "INTEL_GPU=$(ls /dev/dri/renderD* 2>/dev/null | head -1) render device found"
else
  echo "INTEL_GPU=none"
fi

echo "=== DOCKER ==="
if command -v docker &>/dev/null; then
  DOCKER_VER=$(docker --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
  echo "DOCKER_VERSION=${DOCKER_VER}"
  if docker info &>/dev/null 2>&1; then
    echo "DOCKER_RUNNING=true"
  elif sudo docker info &>/dev/null 2>&1; then
    echo "DOCKER_RUNNING=sudo"
  else
    echo "DOCKER_RUNNING=false"
  fi
  # Running containers
  RUNNING=$(docker ps --format '{{.Names}}:{{.Status}}' 2>/dev/null || sudo docker ps --format '{{.Names}}:{{.Status}}' 2>/dev/null || echo "")
  echo "CONTAINERS_RUNNING=${RUNNING//$'\n'/|}"
  # Portainer specifically
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qi portainer; then
    PT_VER=$(docker inspect portainer 2>/dev/null | grep -o '"portainer/portainer[^"]*"' | head -1 | tr -d '"' || echo "portainer")
    echo "PORTAINER_RUNNING=true:${PT_VER}"
  elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qi portainer; then
    echo "PORTAINER_RUNNING=stopped"
  else
    echo "PORTAINER_RUNNING=false"
  fi
else
  echo "DOCKER_VERSION=not_installed"
  echo "DOCKER_RUNNING=false"
  echo "CONTAINERS_RUNNING="
  echo "PORTAINER_RUNNING=false"
fi

echo "=== NETWORK ==="
# Portainer port check
for p in 9000 9443 8000; do
  if ss -tlnp 2>/dev/null | grep -q ":${p} " || netstat -tlnp 2>/dev/null | grep -q ":${p} "; then
    echo "PORT_${p}=open"
  else
    echo "PORT_${p}=closed"
  fi
done
# Firewall status
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  echo "FIREWALL=ufw:active"
elif command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q "running"; then
  echo "FIREWALL=firewalld:running"
else
  echo "FIREWALL=none"
fi
# Tailscale
if command -v tailscale &>/dev/null; then
  TS_IP=$(tailscale ip -4 2>/dev/null | head -1 || echo "")
  echo "TAILSCALE_IP=${TS_IP}"
else
  echo "TAILSCALE_IP=not_installed"
fi

echo "=== SOFTWARE ==="
# Docker Compose
if docker compose version &>/dev/null 2>&1; then
  echo "DOCKER_COMPOSE=plugin"
elif command -v docker-compose &>/dev/null; then
  echo "DOCKER_COMPOSE=legacy"
else
  echo "DOCKER_COMPOSE=not_installed"
fi
# Ollama
if command -v ollama &>/dev/null; then
  echo "OLLAMA=$(ollama --version 2>/dev/null | head -1 || echo installed)"
else
  echo "OLLAMA=not_installed"
fi
# Node.js
if command -v node &>/dev/null; then
  echo "NODEJS=$(node --version 2>/dev/null)"
else
  echo "NODEJS=not_installed"
fi
# Python
if command -v python3 &>/dev/null; then
  echo "PYTHON=$(python3 --version 2>/dev/null)"
else
  echo "PYTHON=not_installed"
fi
echo "DONE"
ENDSSH
)

  if [[ "$remote_data" == "REMOTE_AUDIT_FAILED" ]] || [[ -z "$remote_data" ]]; then
    warn "Remote audit script failed on ${label} — manual check required"
    rpt "- Remote audit: failed"
    return
  fi

  # ── Parse and display remote audit data ──────────────────────────────────
  _parse_section() { echo "$remote_data" | sed -n "/^=== $1 ===/,/^=== /p" | grep -v "^===" || true; }
  _val() { echo "$remote_data" | grep "^${1}=" | cut -d= -f2- | head -1 || echo ""; }

  echo ""
  echo -e "  ${BOLD}Hardware:${NC}"
  info "Hostname:     $(_val HOSTNAME)"
  info "OS:           $(_val OS)"
  info "Kernel:       $(_val KERNEL)"
  info "CPU:          $(_val CPU) ($(_val CORES) cores)"
  info "RAM:          $(_val RAM_TOTAL) total, $(_val RAM_FREE) free"
  info "Disk:         $(_val DISK)"
  info "Uptime:       $(_val UPTIME)"

  echo ""
  echo -e "  ${BOLD}GPU:${NC}"
  local nvidia_gpu; nvidia_gpu=$(_val NVIDIA_GPU)
  local amd_gpu;    amd_gpu=$(_val AMD_GPU)
  local intel_gpu;  intel_gpu=$(_val INTEL_GPU)
  [[ "$nvidia_gpu" != "none" ]] && ok "NVIDIA: ${nvidia_gpu}" && rpt "  - NVIDIA GPU: ${nvidia_gpu}"
  [[ "$amd_gpu"   != "none" ]] && ok "AMD:    ${amd_gpu}"    && rpt "  - AMD GPU: ${amd_gpu}"
  [[ "$intel_gpu" != "none" ]] && ok "Intel:  ${intel_gpu}"  && rpt "  - Intel GPU: ${intel_gpu}"
  [[ "$nvidia_gpu" == "none" && "$amd_gpu" == "none" && "$intel_gpu" == "none" ]] && info "No discrete GPU detected (CPU-only)"

  echo ""
  echo -e "  ${BOLD}Docker & Containers:${NC}"
  local docker_ver; docker_ver=$(_val DOCKER_VERSION)
  local docker_run; docker_run=$(_val DOCKER_RUNNING)
  local pt_status;  pt_status=$(_val PORTAINER_RUNNING)
  local containers; containers=$(_val CONTAINERS_RUNNING)

  if [[ "$docker_ver" == "not_installed" ]]; then
    warn "Docker: NOT INSTALLED"
    rpt "  - Docker: not installed"
  else
    ok "Docker ${docker_ver} (daemon: ${docker_run})"
    rpt "  - Docker: ${docker_ver}, daemon: ${docker_run}"
  fi

  if [[ "$pt_status" == true:* ]]; then
    ok "Portainer: ALREADY RUNNING (${pt_status#true:})"
    rpt "  - Portainer: running (${pt_status#true:})"
  elif [[ "$pt_status" == "stopped" ]]; then
    warn "Portainer: installed but STOPPED"
    rpt "  - Portainer: stopped"
  else
    info "Portainer: not installed (will be deployed)"
    rpt "  - Portainer: not installed"
  fi

  if [[ -n "$containers" ]]; then
    echo ""
    info "Running containers:"
    IFS='|' read -ra clist <<< "$containers"
    for c in "${clist[@]}"; do
      [[ -n "$c" ]] && echo "      • $c"
    done
    rpt "  - Containers: ${containers}"
  fi

  echo ""
  echo -e "  ${BOLD}Network & Firewall:${NC}"
  local fw; fw=$(_val FIREWALL)
  local ts_ip; ts_ip=$(_val TAILSCALE_IP)
  info "Firewall: ${fw}"
  rpt "  - Firewall: ${fw}"
  if [[ "$ts_ip" != "not_installed" ]] && [[ -n "$ts_ip" ]]; then
    ok "Tailscale: active (${ts_ip})"
    rpt "  - Tailscale: ${ts_ip}"
  else
    info "Tailscale: ${ts_ip}"
    rpt "  - Tailscale: ${ts_ip}"
  fi

  # Port status
  for p in 9000 9443 8000; do
    local pstatus; pstatus=$(_val "PORT_${p}")
    if [[ "$pstatus" == "open" ]]; then
      info "Port ${p}: open (already in use)"
    fi
  done

  # ── Firewall fix for SSH and Portainer ────────────────────────────────────
  if [[ "$FLAG_FIX_FIREWALL" == "true" ]] && [[ "$fw" != "none" ]]; then
    step "Applying firewall rules on ${label}"
    local fw_type="${fw%%:*}"
    if [[ "$fw_type" == "ufw" ]]; then
      ssh ${BATCH_SSH_OPTS} ${port_flag} "$ssh_target" bash <<ENDSSH 2>/dev/null && ok "ufw rules applied" || warn "ufw fix failed (may need sudo)"
sudo ufw allow 22/tcp comment 'SSH' 2>/dev/null || true
sudo ufw allow 9000/tcp comment 'Portainer' 2>/dev/null || true
sudo ufw allow 9443/tcp comment 'Portainer HTTPS' 2>/dev/null || true
sudo ufw --force enable 2>/dev/null || true
echo "UFW rules OK"
ENDSSH
    elif [[ "$fw_type" == "firewalld" ]]; then
      ssh ${BATCH_SSH_OPTS} ${port_flag} "$ssh_target" bash <<ENDSSH 2>/dev/null && ok "firewalld rules applied" || warn "firewalld fix failed"
sudo firewall-cmd --permanent --add-service=ssh 2>/dev/null || true
sudo firewall-cmd --permanent --add-port=9000/tcp 2>/dev/null || true
sudo firewall-cmd --permanent --add-port=9443/tcp 2>/dev/null || true
sudo firewall-cmd --reload 2>/dev/null || true
echo "firewalld rules OK"
ENDSSH
    fi
  elif [[ "$fw" != "none" ]] && [[ "$FLAG_FIX_FIREWALL" == "false" ]]; then
    info "Firewall detected on ${label} — run with --fix-firewall to auto-open ports 22,9000,9443"
    rpt "  - Firewall note: run --fix-firewall to open ports 22/9000/9443"
  fi

  echo ""
  echo -e "  ${BOLD}Software Inventory:${NC}"
  info "Docker Compose: $(_val DOCKER_COMPOSE)"
  info "Ollama:         $(_val OLLAMA)"
  info "Node.js:        $(_val NODEJS)"
  info "Python:         $(_val PYTHON)"
  rpt "  - Docker Compose: $(_val DOCKER_COMPOSE)"
  rpt "  - Ollama: $(_val OLLAMA)"
  rpt "  - Node.js: $(_val NODEJS)"
  rpt "  - Python: $(_val PYTHON)"
}

# ── SSH failure diagnosis helper ───────────────────────────────────────────────
_diagnose_ssh_failure() {
  local ip="$1" user="$2"
  echo ""
  echo -e "  ${YELLOW}SSH Diagnosis for ${ip}:${NC}"

  # Check if port 22 is at least TCP reachable
  if timeout 4 bash -c "echo >/dev/tcp/${ip}/22" 2>/dev/null; then
    info "  Port 22 is TCP reachable — SSH daemon is running"
    echo -e "    ${YELLOW}→ Likely cause: SSH key not authorized on remote${NC}"
    echo -e "    Fix: ssh-copy-id -i ${SSH_KEY}.pub ${user}@${ip}"
    echo -e "    Or:  ./scripts/ssh-auditor.sh --install-keys"
  else
    info "  Port 22 is NOT reachable — firewall is blocking or SSH daemon is down"
    echo -e "    ${YELLOW}→ Possible causes:${NC}"
    echo -e "      1. Remote firewall blocking port 22"
    echo -e "         Fix (Ubuntu): ssh to console → sudo ufw allow 22"
    echo -e "         Fix (Fedora): ssh to console → sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload"
    echo -e "      2. SSH daemon not running"
    echo -e "         Fix: sudo systemctl enable --now sshd"
    echo -e "      3. Wrong IP address — check config/node-inventory.env"
    if [[ "$TAILSCALE_LOCAL" == "false" ]]; then
      echo ""
      echo -e "    ${CYAN}→ Consider Tailscale for secure tunnel access:${NC}"
      echo -e "      Local:  curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up"
      echo -e "      Remote: same command on the target node"
      echo -e "      Then add NODE_X_TS_IP to config/node-inventory.env"
    fi
  fi
  echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
# Section 2: Node Audits
# ══════════════════════════════════════════════════════════════════════════════
sep
header "SECTION 2 — NODE CONNECTIVITY & INVENTORY"
rpt ""
rpt "## Section 2 — Node Connectivity & Inventory"

# Build list of nodes to audit
declare -A NODES_IP=()
declare -A NODES_USER=()
declare -A NODES_TS=()

NODES_IP["NODE_A"]="$NODE_A_IP"
NODES_IP["NODE_B"]="$NODE_B_IP"
NODES_IP["NODE_C"]="$NODE_C_IP"
NODES_IP["NODE_D"]="$NODE_D_IP"
NODES_IP["NODE_E"]="$NODE_E_IP"

NODES_USER["NODE_A"]="$NODE_A_SSH_USER"
NODES_USER["NODE_B"]="$NODE_B_SSH_USER"
NODES_USER["NODE_C"]="$NODE_C_SSH_USER"
NODES_USER["NODE_D"]="$NODE_D_SSH_USER"
NODES_USER["NODE_E"]="$NODE_E_SSH_USER"

NODES_TS["NODE_A"]="${NODE_A_TS_IP:-}"
NODES_TS["NODE_B"]="${NODE_B_TS_IP:-}"
NODES_TS["NODE_C"]="${NODE_C_TS_IP:-}"
NODES_TS["NODE_D"]="${NODE_D_TS_IP:-}"
NODES_TS["NODE_E"]="${NODE_E_TS_IP:-}"

for label in NODE_A NODE_B NODE_C NODE_D NODE_E; do
  # Skip if filtering to specific node
  if [[ -n "$TARGET_NODE" ]] && [[ "$TARGET_NODE" != "$label" ]]; then
    continue
  fi
  # Skip if IP not configured
  local_ip="${NODES_IP[$label]:-}"
  if [[ -z "$local_ip" ]] || [[ "$local_ip" == *".X"* ]] || [[ "$local_ip" == *".Y"* ]]; then
    info "Skipping ${label} — IP not configured"
    CONN_OK["$label"]="false"
    continue
  fi
  audit_node "$label" "$local_ip" "${NODES_USER[$label]}" "${NODES_TS[$label]:-}"
done

# ══════════════════════════════════════════════════════════════════════════════
# Section 3: Write Connection Map
# ══════════════════════════════════════════════════════════════════════════════
echo ""
sep
header "SECTION 3 — CONNECTION MAP"
rpt ""
rpt "## Section 3 — Connection Map"
rpt ""
rpt "\`\`\`"

echo "# Homelab SSH Connection Map" > "$CONNMAP_FILE"
echo "# Generated by ssh-auditor.sh on $(date)" >> "$CONNMAP_FILE"
echo "" >> "$CONNMAP_FILE"

CONNECTED_COUNT=0
FAILED_NODES=()

for label in NODE_A NODE_B NODE_C NODE_D NODE_E; do
  if [[ "${CONN_OK[$label]:-false}" == "true" ]]; then
    {
      echo "${label}_CONN_HOST=${CONN_HOST[$label]:-}"
      echo "${label}_CONN_USER=${CONN_USER[$label]:-}"
      echo "${label}_CONN_METHOD=${CONN_METHOD[$label]:-}"
      echo "${label}_CONN_OK=true"
    } >> "$CONNMAP_FILE"
    ok "${label}: ${CONN_USER[$label]:-?}@${CONN_HOST[$label]:-?} via ${CONN_METHOD[$label]:-?}"
    rpt "${label}_CONN_HOST=${CONN_HOST[$label]:-}"
    rpt "${label}_CONN_OK=true"
    ((CONNECTED_COUNT++)) || true
  else
    {
      echo "${label}_CONN_HOST="
      echo "${label}_CONN_USER="
      echo "${label}_CONN_METHOD=none"
      echo "${label}_CONN_OK=false"
    } >> "$CONNMAP_FILE"
    fail "${label}: not reachable via SSH"
    FAILED_NODES+=("$label")
    rpt "${label}_CONN_OK=false"
  fi
done

rpt "\`\`\`"

# Tailscale install instructions if any nodes failed
if [[ ${#FAILED_NODES[@]} -gt 0 ]]; then
  echo ""
  sep
  header "SECTION 4 — TAILSCALE SETUP (for unreachable nodes)"
  echo ""
  warn "These nodes were not reachable: ${FAILED_NODES[*]}"
  echo ""
  echo -e "  ${CYAN}Option A — Fix SSH (preferred if on same LAN):${NC}"
  echo "    1. Physical/console access to the node"
  echo "    2. Run: sudo systemctl enable --now sshd"
  echo "    3. Run: sudo ufw allow 22/tcp  (or firewall-cmd equivalent)"
  echo "    4. Run: ssh-copy-id ${SSH_KEY}.pub <user>@<ip>"
  echo ""
  echo -e "  ${CYAN}Option B — Tailscale (secure tunnel, cross-network):${NC}"
  echo "    On THIS machine (if not done):"
  echo "      curl -fsSL https://tailscale.com/install.sh | sh"
  echo "      sudo tailscale up"
  echo ""
  echo "    On EACH unreachable node (via console/KVM):"
  echo "      curl -fsSL https://tailscale.com/install.sh | sh"
  echo "      sudo tailscale up"
  echo ""
  echo "    After all nodes are on Tailscale:"
  echo "      tailscale status   # see all node Tailscale IPs (100.x.x.x)"
  echo ""
  echo "    Add Tailscale IPs to config/node-inventory.env:"
  for n in "${FAILED_NODES[@]}"; do
    echo "      ${n}_TS_IP=100.x.x.x    # replace with actual Tailscale IP for ${n}"
  done
  echo ""
  echo "    Re-run this auditor:"
  echo "      ./scripts/ssh-auditor.sh"
  echo ""

  rpt ""
  rpt "## Section 4 — Unreachable Nodes"
  rpt ""
  rpt "Nodes not reachable: \`${FAILED_NODES[*]}\`"
  rpt ""
  rpt "### Tailscale Setup"
  rpt "\`\`\`bash"
  rpt "# On each unreachable node (via console/KVM/physical access):"
  rpt "curl -fsSL https://tailscale.com/install.sh | sh"
  rpt "sudo tailscale up"
  rpt ""
  rpt "# Get Tailscale IPs:"
  rpt "tailscale status"
  rpt ""
  rpt "# Add to config/node-inventory.env:"
  for n in "${FAILED_NODES[@]}"; do
    rpt "${n}_TS_IP=100.x.x.x"
  done
  rpt "\`\`\`"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Final Summary
# ══════════════════════════════════════════════════════════════════════════════
echo ""
sep
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Audit Summary                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo -e "  Nodes reachable via SSH: ${GREEN}${CONNECTED_COUNT}${NC}"
if [[ ${#FAILED_NODES[@]} -gt 0 ]]; then
  echo -e "  Nodes unreachable:       ${RED}${#FAILED_NODES[@]} (${FAILED_NODES[*]})${NC}"
fi
echo ""
echo -e "  Connection map written:  ${CYAN}${CONNMAP_FILE}${NC}"
echo -e "  Audit report written:    ${CYAN}${REPORT_FILE}${NC}"
echo ""

if [[ "$CONNECTED_COUNT" -gt 0 ]]; then
  echo -e "  ${GREEN}Next step:${NC}"
  echo "    ./scripts/portainer-install.sh"
  echo ""
else
  echo -e "  ${YELLOW}No nodes reachable — fix SSH access first, then re-run:${NC}"
  echo "    ./scripts/ssh-auditor.sh [--install-keys] [--fix-firewall]"
  echo ""
fi

# Write markdown report
printf '%s\n' "${REPORT_LINES[@]}" > "$REPORT_FILE"

echo "  Audit report: cat ${REPORT_FILE}"
echo "  Full details: ./scripts/ssh-auditor.sh --report"
echo ""
