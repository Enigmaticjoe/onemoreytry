#!/usr/bin/env bash
# Grand Unified AI Home Lab — SSH Connection Pre-Auditor
#
# Tests SSH connectivity to each node, diagnoses failures, and attempts or
# recommends the most efficient connection method (direct SSH, firewall fix,
# or Tailscale).  Also inventories pre-installed software on reachable hosts.
#
# Usage:
#   ./scripts/ssh-auditor.sh                      # audit all configured nodes
#   ./scripts/ssh-auditor.sh --node 192.168.1.9   # audit a single IP
#   ./scripts/ssh-auditor.sh --json               # machine-readable JSON output
#   ./scripts/ssh-auditor.sh --auto-fix           # attempt firewall fixes (local sudo)
#
# Output (--json) schema per node:
#   { "label": "Node B", "ip": "192.168.1.222", "user": "root",
#     "ping": true, "port22": true, "ssh": true,
#     "tailscale_ip": "", "recommend": "direct",
#     "inventory": { "docker": "24.0.5", "portainer": "running", ... },
#     "errors": [], "fixes": [] }

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Source inventory for default node IPs
source "${REPO_ROOT}/scripts/lib-inventory.sh"
load_inventory "$REPO_ROOT"

# ── Argument parsing ──────────────────────────────────────────────────────────
JSON_OUTPUT=false
AUTO_FIX=false
SINGLE_NODE_IP=""
SINGLE_NODE_USER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)      JSON_OUTPUT=true  ;;
    --auto-fix)  AUTO_FIX=true     ;;
    --node)      SINGLE_NODE_IP="$2"; shift ;;
    --user)      SINGLE_NODE_USER="$2"; shift ;;
    *) ;;
  esac
  shift
done

# ── Colors (suppressed in JSON mode) ─────────────────────────────────────────
if $JSON_OUTPUT; then
  GREEN=''; RED=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
else
  GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
fi

pass()  { $JSON_OUTPUT || echo -e "  ${GREEN}✓${NC} $1"; }
fail()  { $JSON_OUTPUT || echo -e "  ${RED}✗${NC} $1"; }
warn()  { $JSON_OUTPUT || echo -e "  ${YELLOW}!${NC} $1"; }
info()  { $JSON_OUTPUT || echo -e "    ${CYAN}→${NC} $1"; }
header(){ $JSON_OUTPUT || echo -e "\n${BOLD}$1${NC}"; }
sep()   { $JSON_OUTPUT || echo -e "${CYAN}──────────────────────────────────────────${NC}"; }

# ── Build the list of nodes to audit ─────────────────────────────────────────
declare -a AUDIT_NODES=()
# format: "label:ip:user"
if [ -n "$SINGLE_NODE_IP" ]; then
  AUDIT_NODES+=("Custom:${SINGLE_NODE_IP}:${SINGLE_NODE_USER:-root}")
else
  AUDIT_NODES+=(
    "Node A (Brain):${NODE_A_IP}:${NODE_A_SSH_USER:-root}"
    "Node B (Unraid):${NODE_B_IP}:${NODE_B_SSH_USER:-root}"
    "Node C (Intel Arc):${NODE_C_IP}:${NODE_C_SSH_USER:-root}"
  )
  [[ -n "${NODE_D_IP:-}" && "$NODE_D_IP" != *"192.168.1.X"* ]] && \
    AUDIT_NODES+=("Node D (Home Assistant):${NODE_D_IP}:root")
  [[ -n "${NODE_E_IP:-}" && "$NODE_E_IP" != *"192.168.1.X"* ]] && \
    AUDIT_NODES+=("Node E (Sentinel):${NODE_E_IP}:root")
fi

# ── JSON accumulator ──────────────────────────────────────────────────────────
JSON_RESULTS=()

# ── Helper: test TCP port ─────────────────────────────────────────────────────
test_port() {
  local host="$1" port="$2"
  # Try bash /dev/tcp (most portable); fall back to nc
  if (echo >/dev/tcp/"$host"/"$port") &>/dev/null 2>&1; then
    return 0
  elif command -v nc &>/dev/null; then
    nc -z -w3 "$host" "$port" &>/dev/null 2>&1 && return 0
  fi
  return 1
}

# ── Helper: check Tailscale on local machine ──────────────────────────────────
get_tailscale_ip() {
  local target_hostname="$1"
  if command -v tailscale &>/dev/null; then
    # Try to find the tailscale IP for the peer matching hostname or IP
    tailscale status 2>/dev/null | awk '{print $1}' | grep -v "^#\|^$" | head -20 || true
  fi
}

# ── Helper: inventory what's installed on a remote host ───────────────────────
remote_inventory() {
  local ip="$1" user="$2"
  local inv="{}"

  # Run a comprehensive inventory in one SSH session to minimize round-trips
  local raw
  raw=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
    "${user}@${ip}" bash -s 2>/dev/null <<'ENDINV'
OUT=""
# Docker
if command -v docker &>/dev/null; then
  DOCKER_VER=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "")
  OUT="${OUT}docker=${DOCKER_VER}|"
  # Docker Compose
  if docker compose version &>/dev/null 2>&1; then
    DC_VER=$(docker compose version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "plugin")
    OUT="${OUT}docker_compose=${DC_VER}|"
  fi
  # Portainer
  PORT_ST=$(docker inspect --format '{{.State.Status}}' portainer 2>/dev/null || \
            docker inspect --format '{{.State.Status}}' portainer-ce 2>/dev/null || echo "")
  [ -n "$PORT_ST" ] && OUT="${OUT}portainer=${PORT_ST}|"
  # Key containers
  for cname in litellm_gateway ollama_intel_arc chimera_face openclaw-gateway; do
    ST=$(docker inspect --format '{{.State.Status}}' "$cname" 2>/dev/null || echo "")
    [ -n "$ST" ] && OUT="${OUT}${cname}=${ST}|"
  done
fi
# OS info
OS=$(cat /etc/os-release 2>/dev/null | grep '^PRETTY_NAME' | cut -d= -f2 | tr -d '"' || echo "unknown")
OUT="${OUT}os=${OS}|"
# Tailscale
if command -v tailscale &>/dev/null; then
  TS_IP=$(tailscale ip -4 2>/dev/null | head -1 || echo "")
  OUT="${OUT}tailscale_ip=${TS_IP}|"
fi
# Firewall
FW="none"
command -v ufw     &>/dev/null && ufw status 2>/dev/null | grep -q active && FW="ufw"
command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q running && FW="firewalld"
systemctl is-active iptables 2>/dev/null | grep -q active && [ "$FW" = "none" ] && FW="iptables"
OUT="${OUT}firewall=${FW}|"
# Node.js
if command -v node &>/dev/null; then
  OUT="${OUT}nodejs=$(node --version 2>/dev/null | tr -d v)|"
fi
# Python 3
if command -v python3 &>/dev/null; then
  OUT="${OUT}python3=$(python3 --version 2>/dev/null | awk '{print $2}')|"
fi
echo "$OUT"
ENDINV
  ) || true

  # Parse key=value|key=value format into JSON
  inv="{"
  local first=true
  IFS='|' read -ra pairs <<< "$raw"
  for pair in "${pairs[@]}"; do
    [[ "$pair" == *=* ]] || continue
    local k="${pair%%=*}"
    local v="${pair#*=}"
    $first || inv="${inv},"
    inv="${inv}\"${k}\":\"${v//\"/\\\"}\""
    first=false
  done
  inv="${inv}}"
  echo "$inv"
}

# ── Helper: attempt SSH firewall fix on a remote node ────────────────────────
# This is only applicable when we have some other way to reach the machine
# (e.g. it's the local machine, or we have a console).
attempt_firewall_fix() {
  local ip="$1" user="$2" firewall_type="$3"
  local fixes=()

  case "$firewall_type" in
    ufw)
      if $AUTO_FIX; then
        warn "Attempting ufw SSH fix on ${ip}..."
        if ssh -o ConnectTimeout=10 -o BatchMode=yes "${user}@${ip}" \
              "sudo ufw allow ssh && sudo ufw reload" &>/dev/null 2>&1; then
          fixes+=("Applied: sudo ufw allow ssh && sudo ufw reload")
          pass "UFW SSH rule added on ${ip}"
        else
          fixes+=("Manual fix needed: sudo ufw allow ssh && sudo ufw reload")
        fi
      else
        fixes+=("Run on ${ip}: sudo ufw allow ssh && sudo ufw reload")
      fi
      ;;
    firewalld)
      if $AUTO_FIX; then
        warn "Attempting firewalld SSH fix on ${ip}..."
        if ssh -o ConnectTimeout=10 -o BatchMode=yes "${user}@${ip}" \
              "sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload" &>/dev/null 2>&1; then
          fixes+=("Applied: firewall-cmd --permanent --add-service=ssh && --reload")
          pass "firewalld SSH rule added on ${ip}"
        else
          fixes+=("Manual fix needed: sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload")
        fi
      else
        fixes+=("Run on ${ip}: sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload")
      fi
      ;;
    iptables)
      fixes+=("Run on ${ip}: sudo iptables -I INPUT -p tcp --dport 22 -j ACCEPT && sudo iptables-save > /etc/iptables/rules.v4")
      ;;
    *)
      fixes+=("Check that sshd is installed and running: systemctl status sshd")
      fixes+=("Ensure port 22 is not blocked by a host or network firewall")
      ;;
  esac
  printf '%s\n' "${fixes[@]}"
}

# ── Helper: Tailscale install hint ───────────────────────────────────────────
tailscale_hint() {
  echo "Install Tailscale: curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up"
  echo "Then use the Tailscale IP shown by: tailscale status"
}

# ── Audit a single node ───────────────────────────────────────────────────────
audit_node() {
  local label="$1" ip="$2" user="$3"

  # Skip placeholder IPs
  if [[ -z "$ip" || "$ip" == *"192.168.1.X"* || "$ip" == *"192.168.1.Y"* ]]; then
    $JSON_OUTPUT || warn "Skipping ${label} — IP not configured"
    return
  fi

  sep
  header "  ${label}  (${user}@${ip})"

  local ping_ok=false port22_ok=false ssh_ok=false
  local tailscale_ip="" recommend="direct"
  local errors=() fixes=()
  local inventory="{}"

  # 1. Ping test
  if ping -c1 -W2 "$ip" &>/dev/null 2>&1; then
    ping_ok=true
    pass "Ping ${ip} — reachable"
  else
    fail "Ping ${ip} — unreachable"
    errors+=("Host not reachable via ping")
    recommend="unreachable"
  fi

  # 2. Port 22 test (even if ping failed — might be ICMP blocked)
  if test_port "$ip" 22; then
    port22_ok=true
    pass "Port 22 — open"
  else
    fail "Port 22 — closed or filtered"
    errors+=("Port 22 is not reachable — SSH cannot connect")
    if $ping_ok; then
      warn "Host is up but port 22 is blocked — likely a firewall rule"
      fixes+=("Ensure sshd is running: systemctl enable --now sshd")
      fixes+=("Check firewall: ufw allow ssh  OR  firewall-cmd --add-service=ssh")
    fi
  fi

  # 3. SSH auth test
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
         "${user}@${ip}" true &>/dev/null 2>&1; then
    ssh_ok=true
    pass "SSH auth ${user}@${ip} — key auth OK"
    recommend="direct"
  else
    fail "SSH auth ${user}@${ip} — key auth FAILED"
    errors+=("SSH key authentication failed — no authorized_keys match or SSH is misconfigured")
    if $port22_ok; then
      info "Port 22 is open — try: ssh-copy-id ${user}@${ip}"
      fixes+=("Set up key auth: ssh-copy-id ${user}@${ip}")
      fixes+=("Or use password once: ssh-copy-id -i ~/.ssh/id_rsa.pub ${user}@${ip}")
    fi
  fi

  # 4. Check Tailscale on remote (only if SSH is up)
  if $ssh_ok; then
    local ts_check
    ts_check=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes \
                   "${user}@${ip}" \
                   "command -v tailscale &>/dev/null && tailscale ip -4 2>/dev/null | head -1 || echo ''" \
                   2>/dev/null || echo "")
    tailscale_ip="${ts_check//[[:space:]]/}"
    if [ -n "$tailscale_ip" ]; then
      pass "Tailscale — running (${tailscale_ip})"
    else
      info "Tailscale — not installed on remote"
    fi
  elif ! $ssh_ok && $ping_ok; then
    # SSH broken — suggest Tailscale as an alternative
    warn "SSH is unavailable — Tailscale is a good alternative"
    while IFS= read -r hint; do
      fixes+=("$hint")
    done < <(tailscale_hint)
    recommend="tailscale"
  fi

  # 5. Run inventory if SSH is available
  if $ssh_ok; then
    info "Running remote inventory..."
    inventory=$(remote_inventory "$ip" "$user")
    if [ "$inventory" != "{}" ]; then
      # Pretty-print a few key items
      local docker_ver port_st
      docker_ver=$(echo "$inventory" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('docker','not installed'))" 2>/dev/null || echo "?")
      port_st=$(echo    "$inventory" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('portainer','not found'))" 2>/dev/null || echo "?")
      local fw_type
      fw_type=$(echo    "$inventory" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('firewall','none'))" 2>/dev/null || echo "none")
      local os_info
      os_info=$(echo    "$inventory" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('os','?'))" 2>/dev/null || echo "?")
      local ts_ip
      ts_ip=$(echo      "$inventory" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tailscale_ip',''))" 2>/dev/null || echo "")

      pass "OS: ${os_info}"
      [ "$docker_ver" != "not installed" ] && pass "Docker: ${docker_ver}" || warn "Docker: not installed"
      [ "$port_st" = "running" ] && pass "Portainer: running" || warn "Portainer: ${port_st}"
      [ -n "$ts_ip"   ] && pass "Tailscale IP: ${ts_ip}"
      [ "$fw_type" != "none" ] && warn "Firewall type: ${fw_type}"

      # If firewall is active and SSH just barely worked, suggest confirming SSH is persistent
      if [[ "$fw_type" != "none" && $ssh_ok == true ]]; then
        info "Firewall '${fw_type}' is active — SSH is currently open but verify persistent rules"
      fi
    fi
  fi

  # 6. Final recommendation
  local rec_text
  case "$recommend" in
    direct)     rec_text="✓ Use direct SSH (${user}@${ip})" ;;
    tailscale)  rec_text="Use Tailscale tunnel to reach this node" ;;
    unreachable)rec_text="Node is not reachable — check network/power" ;;
  esac
  info "Recommendation: ${rec_text}"

  # ── Emit JSON ──────────────────────────────────────────────────────────────
  local errors_json fixes_json
  errors_json=$(printf '%s\n' "${errors[@]:-}" | python3 -c "
import json,sys
lines=[l.rstrip() for l in sys.stdin if l.strip()]
print(json.dumps(lines))" 2>/dev/null || echo "[]")
  fixes_json=$(printf '%s\n' "${fixes[@]:-}" | python3 -c "
import json,sys
lines=[l.rstrip() for l in sys.stdin if l.strip()]
print(json.dumps(lines))" 2>/dev/null || echo "[]")

  JSON_RESULTS+=("{\"label\":$(echo -n "$label" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),\"ip\":\"${ip}\",\"user\":\"${user}\",\"ping\":${ping_ok},\"port22\":${port22_ok},\"ssh\":${ssh_ok},\"tailscale_ip\":\"${tailscale_ip}\",\"recommend\":\"${recommend}\",\"inventory\":${inventory},\"errors\":${errors_json},\"fixes\":${fixes_json}}")
}

# ── Main ──────────────────────────────────────────────────────────────────────
if ! $JSON_OUTPUT; then
  echo ""
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║   SSH Connection Pre-Auditor                         ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""
fi

for node_entry in "${AUDIT_NODES[@]}"; do
  IFS=':' read -r label ip user <<< "$node_entry"
  audit_node "$label" "$ip" "$user"
done

# ── JSON output ───────────────────────────────────────────────────────────────
if $JSON_OUTPUT; then
  echo -n "["
  for i in "${!JSON_RESULTS[@]}"; do
    [ "$i" -gt 0 ] && echo -n ","
    echo -n "${JSON_RESULTS[$i]}"
  done
  echo "]"
else
  sep
  echo ""
  echo "Audit complete.  Use --auto-fix to attempt automatic firewall repairs."
  echo "Use --json to get machine-readable output for the web wizard."
  echo ""
fi
