#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  Portainer Install Script — Auto-deploys Portainer to all homelab nodes
# ══════════════════════════════════════════════════════════════════════════════
#
#  PURPOSE: Reads the connection map from ssh-auditor.sh and installs
#  Portainer CE on every reachable node. Skips nodes where Portainer
#  is already running. Handles Docker install if missing.
#
#  USAGE:
#    # Step 1 (required first run):
#    ./scripts/ssh-auditor.sh
#
#    # Step 2:
#    ./scripts/portainer-install.sh                    # install CE on all nodes
#    ./scripts/portainer-install.sh --business         # install BE (licensed) on all nodes
#    ./scripts/portainer-install.sh --node NODE_B      # single node
#    ./scripts/portainer-install.sh --force            # reinstall even if running
#    ./scripts/portainer-install.sh --status           # check status only
#    ./scripts/portainer-install.sh --update           # pull latest portainer image
#
#  PORTAINER EDITIONS:
#    CE (Community Edition): portainer/portainer-ce:latest  — free, single environment
#    BE (Business Edition):  portainer/portainer-ee:latest  — licensed, multi-environment,
#      Swarm support, RBAC, GitOps, centralized admin across all nodes.
#      Use --business if you have a Portainer BE license key.
#      After install: Settings → Licenses → paste your key.
#
#  WHAT IT DOES PER NODE:
#    1. Checks if Docker is installed — installs if missing
#    2. Checks if Portainer is already running — skips or reinstalls
#    3. Deploys Portainer CE or BE with persistent data volume
#    4. Opens required firewall ports (9000, 9443)
#    5. Waits for Portainer to become healthy
#    6. Prints the admin URL and first-login instructions
#
# ══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONNMAP_FILE="/tmp/homelab-connmap.env"
SSH_TIMEOUT=10
PORTAINER_CE_IMAGE="portainer/portainer-ce:latest"
PORTAINER_BE_IMAGE="portainer/portainer-ee:latest"
PORTAINER_IMAGE="$PORTAINER_CE_IMAGE"   # overridden by --business flag
PORTAINER_DATA_VOL="portainer_data"
PORTAINER_HTTP_PORT="${PORTAINER_PORT:-9000}"
PORTAINER_HTTPS_PORT="9443"
PORTAINER_AGENT_PORT="8000"

# ── Flags ─────────────────────────────────────────────────────────────────────
FLAG_FORCE=false
FLAG_STATUS=false
FLAG_UPDATE=false
FLAG_BUSINESS=false
TARGET_NODE=""

for arg in "$@"; do
  case "$arg" in
    --force)    FLAG_FORCE=true ;;
    --status)   FLAG_STATUS=true ;;
    --business) FLAG_BUSINESS=true; PORTAINER_IMAGE="$PORTAINER_BE_IMAGE" ;;
    --update)  FLAG_UPDATE=true ;;
    --node)    : ;;
    *)
      if [[ "${prev_arg:-}" == "--node" ]]; then
        TARGET_NODE="${arg^^}"
      fi
      ;;
  esac
  prev_arg="$arg"
done

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'

ok()     { echo -e "  ${GREEN}✓${NC} $*"; }
fail()   { echo -e "  ${RED}✗${NC} $*"; }
warn()   { echo -e "  ${YELLOW}!${NC} $*"; }
info()   { echo -e "  ${CYAN}→${NC} $*"; }
step()   { echo ""; echo -e "${BOLD}${CYAN}── $* ──${NC}"; }
header() { echo -e "${BOLD}${MAGENTA}$*${NC}"; }
sep()    { echo -e "${CYAN}────────────────────────────────────────────────────${NC}"; }

# ── Load inventory + connection map ───────────────────────────────────────────
load_inventory() {
  local inv="${REPO_ROOT}/config/node-inventory.env"
  local example="${REPO_ROOT}/config/node-inventory.env.example"
  if [[ -f "$inv" ]]; then
    # shellcheck disable=SC1090
    source "$inv"
  elif [[ -f "$example" ]]; then
    # shellcheck disable=SC1090
    source "$example"
  fi
  PORTAINER_PORT="${PORTAINER_PORT:-9000}"
  PORTAINER_HTTP_PORT="$PORTAINER_PORT"
}
load_inventory

# Load connection map from auditor
if [[ -f "$CONNMAP_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONNMAP_FILE"
else
  if [[ "$FLAG_STATUS" == "false" ]]; then
    echo ""
    warn "No connection map found at ${CONNMAP_FILE}"
    warn "Run the SSH auditor first:"
    echo ""
    echo "    ./scripts/ssh-auditor.sh"
    echo ""
    exit 1
  fi
fi

# SSH helper
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=${SSH_TIMEOUT} -o BatchMode=yes -o LogLevel=ERROR"

ssh_run() {
  local host="$1" user="$2"; shift 2
  ssh ${SSH_OPTS} "${user}@${host}" "$@" 2>&1
}

ssh_script() {
  local host="$1" user="$2" script="$3"
  ssh ${SSH_OPTS} "${user}@${host}" bash <<< "$script" 2>&1
}

# Wait for HTTP endpoint with backoff
wait_for_url() {
  local label="$1" url="$2" max="${3:-20}" delay="${4:-3}"
  local i=0 code
  info "Waiting for ${label} to become available..."
  while [[ $i -lt $max ]]; do
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    if [[ "$code" =~ ^(200|301|302|307|308|401|403) ]]; then
      ok "${label} is up (HTTP ${code})"
      return 0
    fi
    i=$((i+1))
    info "  Attempt ${i}/${max} — HTTP ${code} — retrying in ${delay}s..."
    sleep "$delay"
    delay=$(( delay < 30 ? delay + 3 : 30 ))
  done
  warn "${label} did not respond after ${max} attempts (last: HTTP ${code:-000})"
  return 1
}

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Portainer Install — Homelab Multi-Node Deployment          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
if [[ "$FLAG_BUSINESS" == "true" ]]; then
  echo -e "  ${BOLD}Edition:${NC} ${MAGENTA}Portainer Business Edition (BE)${NC}"
  echo -e "  ${CYAN}Image:${NC}   ${PORTAINER_BE_IMAGE}"
  echo ""
  echo -e "  ${YELLOW}After install → Settings → Licenses → paste your key${NC}"
else
  echo -e "  ${BOLD}Edition:${NC} Portainer Community Edition (CE)"
  echo -e "  ${CYAN}Image:${NC}   ${PORTAINER_CE_IMAGE}"
  echo ""
  echo -e "  ${YELLOW}Tip: Use --business if you have a Portainer BE license.${NC}"
  echo -e "  ${YELLOW}BE adds multi-environment central admin, Swarm, RBAC, GitOps.${NC}"
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# STATUS MODE — just check all Portainer endpoints
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$FLAG_STATUS" == "true" ]]; then
  header "Portainer Status Check"
  echo ""

  for label in NODE_A NODE_B NODE_C NODE_D NODE_E; do
    local_ip_var="${label}_IP"
    local_ip="${!local_ip_var:-}"
    [[ -z "$local_ip" ]] || [[ "$local_ip" == *".X"* ]] && continue

    conn_host_var="${label}_CONN_HOST"
    conn_host="${!conn_host_var:-$local_ip}"
    [[ -z "$conn_host" ]] && conn_host="$local_ip"

    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
      "http://${conn_host}:${PORTAINER_HTTP_PORT}/api/status" 2>/dev/null || echo "000")
    if [[ "$code" =~ ^2 ]]; then
      ok "${label} (${conn_host}:${PORTAINER_HTTP_PORT}) — Portainer UP (HTTP ${code})"
      # Show version if API accessible
      VER=$(curl -sk --max-time 5 "http://${conn_host}:${PORTAINER_HTTP_PORT}/api/status" 2>/dev/null \
        | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Version','?'))" 2>/dev/null || echo "?")
      info "  Version: ${VER}"
    elif [[ "$code" == "000" ]]; then
      info "${label} (${conn_host}:${PORTAINER_HTTP_PORT}) — not reachable"
    else
      warn "${label} (${conn_host}:${PORTAINER_HTTP_PORT}) — HTTP ${code}"
    fi
  done
  echo ""
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# INSTALL / UPDATE per node
# ══════════════════════════════════════════════════════════════════════════════

# The remote install script runs on each target node
# Arguments passed: PORTAINER_IMAGE PORTAINER_HTTP_PORT PORTAINER_HTTPS_PORT
#                   PORTAINER_AGENT_PORT PORTAINER_DATA_VOL FLAG_FORCE FLAG_UPDATE
portainer_remote_script() {
  local pt_image="$1" http_port="$2" https_port="$3"
  local agent_port="$4" data_vol="$5" force="$6" update="$7"
  cat <<SCRIPT
#!/bin/bash
set -uo pipefail
PT_IMAGE="${pt_image}"
HTTP_PORT="${http_port}"
HTTPS_PORT="${https_port}"
AGENT_PORT="${agent_port}"
DATA_VOL="${data_vol}"
FLAG_FORCE="${force}"
FLAG_UPDATE="${update}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  \${GREEN}✓\${NC} \$*"; }
warn() { echo -e "  \${YELLOW}!\${NC} \$*"; }
fail() { echo -e "  \${RED}✗\${NC} \$*"; }
info() { echo -e "  \${CYAN}→\${NC} \$*"; }

# ── 1. Ensure Docker is installed ──────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  info "Docker not found — installing..."
  if command -v apt-get &>/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    ok "Docker installed via apt"
  elif command -v dnf &>/dev/null; then
    dnf install -y docker docker-compose-plugin 2>/dev/null || \
      dnf install -y docker-ce docker-compose-plugin
    systemctl enable --now docker
    ok "Docker installed via dnf"
  elif command -v yum &>/dev/null; then
    yum install -y docker
    systemctl enable --now docker
    ok "Docker installed via yum"
  else
    fail "Cannot install Docker — unsupported package manager"
    fail "Install Docker manually: https://docs.docker.com/engine/install/"
    exit 1
  fi
fi

# Ensure Docker daemon is running
if ! docker info &>/dev/null 2>&1; then
  info "Starting Docker daemon..."
  systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
  sleep 3
  if ! docker info &>/dev/null 2>&1; then
    fail "Docker daemon could not be started"
    exit 1
  fi
fi
ok "Docker is running (\$(docker --version | grep -o '[0-9.]*' | head-1))"

# ── 2. Check existing Portainer ────────────────────────────────────────────
PT_EXISTS=false
PT_RUNNING=false
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qi "^portainer$"; then
  PT_EXISTS=true
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qi "^portainer$"; then
    PT_RUNNING=true
  fi
fi

if [[ "\$PT_RUNNING" == "true" ]] && [[ "\$FLAG_FORCE" == "false" ]] && [[ "\$FLAG_UPDATE" == "false" ]]; then
  PT_VER=\$(docker exec portainer /bin/sh -c 'cat /app/VERSION 2>/dev/null || echo unknown' 2>/dev/null || echo unknown)
  ok "Portainer is already running (version: \${PT_VER})"
  info "Portainer HTTP:  http://\$(hostname -I | awk '{print \$1}'):\${HTTP_PORT}"
  info "Portainer HTTPS: https://\$(hostname -I | awk '{print \$1}'):\${HTTPS_PORT}"
  info "Use --force to reinstall or --update to pull latest image"
  echo "PORTAINER_STATUS=already_running"
  exit 0
fi

if [[ "\$FLAG_UPDATE" == "true" ]] && [[ "\$PT_RUNNING" == "true" ]]; then
  info "Updating Portainer to latest image..."
  docker pull "\${PT_IMAGE}" 2>/dev/null
  docker stop portainer 2>/dev/null && docker rm portainer 2>/dev/null || true
  ok "Stopped old Portainer for update"
elif [[ "\$FLAG_FORCE" == "true" ]] && [[ "\$PT_EXISTS" == "true" ]]; then
  warn "Force reinstalling Portainer..."
  docker stop portainer 2>/dev/null || true
  docker rm portainer 2>/dev/null || true
fi

# ── 3. Pull Portainer image ────────────────────────────────────────────────
info "Pulling Portainer image: \${PT_IMAGE}"
docker pull "\${PT_IMAGE}" 2>&1 | tail -3

# ── 4. Create/ensure data volume ──────────────────────────────────────────
docker volume create "\${DATA_VOL}" 2>/dev/null || true
ok "Portainer data volume: \${DATA_VOL}"

# ── 5. Run Portainer ──────────────────────────────────────────────────────
info "Starting Portainer..."
docker run -d \\
  --name portainer \\
  --restart=always \\
  --security-opt no-new-privileges \\
  -p "\${AGENT_PORT}:\${AGENT_PORT}" \\
  -p "\${HTTP_PORT}:9000" \\
  -p "\${HTTPS_PORT}:9443" \\
  -v /var/run/docker.sock:/var/run/docker.sock \\
  -v "\${DATA_VOL}:/data" \\
  "\${PT_IMAGE}" 2>&1

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qi "^portainer$"; then
  ok "Portainer container started"
else
  fail "Portainer failed to start"
  echo "Container logs:"
  docker logs portainer --tail 20 2>&1 || true
  exit 1
fi

# ── 6. Open firewall ports ────────────────────────────────────────────────
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow \${HTTP_PORT}/tcp comment 'Portainer HTTP' 2>/dev/null || true
  ufw allow \${HTTPS_PORT}/tcp comment 'Portainer HTTPS' 2>/dev/null || true
  ufw allow \${AGENT_PORT}/tcp comment 'Portainer Agent' 2>/dev/null || true
  ok "ufw rules added for Portainer ports"
elif command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q running; then
  firewall-cmd --permanent --add-port=\${HTTP_PORT}/tcp 2>/dev/null || true
  firewall-cmd --permanent --add-port=\${HTTPS_PORT}/tcp 2>/dev/null || true
  firewall-cmd --permanent --add-port=\${AGENT_PORT}/tcp 2>/dev/null || true
  firewall-cmd --reload 2>/dev/null || true
  ok "firewalld rules added for Portainer ports"
fi

NODE_IP=\$(hostname -I | awk '{print \$1}')
echo "PORTAINER_STATUS=installed"
echo "PORTAINER_URL_HTTP=http://\${NODE_IP}:\${HTTP_PORT}"
echo "PORTAINER_URL_HTTPS=https://\${NODE_IP}:\${HTTPS_PORT}"
SCRIPT
}

# ── Per-node deploy function ───────────────────────────────────────────────────
deploy_portainer_node() {
  local label="$1"

  sep
  header "NODE: ${label}"
  echo ""

  # Get connection details from map
  local conn_ok_var="${label}_CONN_OK"
  local conn_host_var="${label}_CONN_HOST"
  local conn_user_var="${label}_CONN_USER"
  local conn_method_var="${label}_CONN_METHOD"

  local conn_ok="${!conn_ok_var:-false}"
  local conn_host="${!conn_host_var:-}"
  local conn_user="${!conn_user_var:-root}"
  local conn_method="${!conn_method_var:-none}"

  if [[ "$conn_ok" != "true" ]] || [[ -z "$conn_host" ]]; then
    warn "No SSH connection available for ${label}"
    info "Run: ./scripts/ssh-auditor.sh  to discover connections"
    info "Or:  ./scripts/portainer-install.sh --status  to check current state"
    return 1
  fi

  # Extract port from method string (e.g. "lan:2222" → "-p 2222")
  local port_flag=""
  if [[ "$conn_method" == lan:* ]]; then
    local pnum="${conn_method#lan:}"
    [[ "$pnum" != "22" ]] && port_flag="-p $pnum"
  fi

  ok "Using connection: ${conn_user}@${conn_host} via ${conn_method}"

  step "Deploying Portainer to ${label}"

  local remote_script
  remote_script=$(portainer_remote_script \
    "$PORTAINER_IMAGE" "$PORTAINER_HTTP_PORT" "$PORTAINER_HTTPS_PORT" \
    "$PORTAINER_AGENT_PORT" "$PORTAINER_DATA_VOL" "$FLAG_FORCE" "$FLAG_UPDATE")

  local output
  output=$(ssh ${SSH_OPTS} ${port_flag} "${conn_user}@${conn_host}" bash <<< "$remote_script" 2>&1)
  local exit_code=$?

  # Print remote output
  while IFS= read -r line; do
    echo "    ${line}"
  done <<< "$output"

  if [[ $exit_code -ne 0 ]]; then
    fail "Portainer deploy failed on ${label} (exit code: ${exit_code})"
    return 1
  fi

  # Extract Portainer URL from output
  local pt_url_http pt_url_https pt_status
  pt_url_http=$(echo "$output"  | grep "^PORTAINER_URL_HTTP="  | cut -d= -f2-)
  pt_url_https=$(echo "$output" | grep "^PORTAINER_URL_HTTPS=" | cut -d= -f2-)
  pt_status=$(echo "$output"    | grep "^PORTAINER_STATUS="    | cut -d= -f2-)

  if [[ "$pt_status" == "already_running" ]]; then
    ok "${label}: Portainer already running — skipping"
    return 0
  fi

  if [[ -n "$pt_url_http" ]]; then
    step "Waiting for Portainer to become healthy"
    if wait_for_url "Portainer on ${label}" "${pt_url_http}/api/status" 20 4; then
      echo ""
      echo -e "  ${GREEN}╔══════════════════════════════════════════════════╗${NC}"
      echo -e "  ${GREEN}║  Portainer is READY on ${label}${NC}"
      echo -e "  ${GREEN}╚══════════════════════════════════════════════════╝${NC}"
      echo ""
      echo -e "  ${BOLD}Admin URL (HTTP):${NC}  ${CYAN}${pt_url_http}${NC}"
      echo -e "  ${BOLD}Admin URL (HTTPS):${NC} ${CYAN}${pt_url_https}${NC}"
      echo ""
      echo -e "  ${YELLOW}IMPORTANT — First Login:${NC}"
      echo "    1. Open the URL above in your browser"
      echo "    2. Create an admin account (username + password)"
      echo "    3. Select 'Get Started' → choose 'local' environment"
      echo ""
      echo "    NOTE: You have 5 minutes on first start to set admin password."
      echo "    If the page says 'timeout', restart Portainer:"
      echo "      On remote: docker restart portainer"
      echo ""
    else
      warn "Portainer may still be starting. Check manually:"
      info "  curl http://${conn_host}:${PORTAINER_HTTP_PORT}/api/status"
      info "  ssh ${conn_user}@${conn_host} docker logs portainer --tail 20"
    fi
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
# Main — iterate over nodes
# ══════════════════════════════════════════════════════════════════════════════
DEPLOYED=0
SKIPPED=0
FAILED=0

for label in NODE_A NODE_B NODE_C NODE_D NODE_E; do
  # Skip if filtering to specific node
  if [[ -n "$TARGET_NODE" ]] && [[ "$TARGET_NODE" != "$label" ]]; then
    continue
  fi

  # Check if IP configured
  local_ip_var="${label}_IP"
  local_ip="${!local_ip_var:-}"
  if [[ -z "$local_ip" ]] || [[ "$local_ip" == *".X"* ]]; then
    continue
  fi

  conn_ok_var="${label}_CONN_OK"
  conn_ok="${!conn_ok_var:-false}"
  if [[ "$conn_ok" != "true" ]]; then
    info "Skipping ${label} — not reachable via SSH"
    ((SKIPPED++)) || true
    continue
  fi

  if deploy_portainer_node "$label"; then
    ((DEPLOYED++)) || true
  else
    ((FAILED++)) || true
  fi
done

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo ""
sep
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Portainer Install Summary                                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo -e "  Deployed/verified: ${GREEN}${DEPLOYED}${NC} node(s)"
[[ "$SKIPPED" -gt 0 ]] && echo -e "  Skipped (no SSH):  ${YELLOW}${SKIPPED}${NC} node(s)"
[[ "$FAILED" -gt 0 ]]  && echo -e "  Failed:            ${RED}${FAILED}${NC} node(s)"
echo ""

if [[ "$DEPLOYED" -gt 0 ]]; then
  echo -e "  ${GREEN}Next steps:${NC}"
  echo "    1. Log in to each Portainer instance (URLs shown above)"
  echo "    2. Create your admin account on first login"
  echo ""
  if [[ "$FLAG_BUSINESS" == "true" ]]; then
    echo -e "  ${MAGENTA}Portainer BE — Central Admin Setup:${NC}"
    echo "    3. Apply license: Settings → Licenses → Add License"
    echo "    4. Add environments: Home → Add Environment"
    echo "       → Docker Standalone → Agent → enter each node's IP:9001"
    echo "    5. Initialize Swarm (optional):"
    echo "       ./scripts/swarm-init.sh"
    echo "    6. Deploy stacks from Portainer UI or:"
    echo "       ./scripts/deploy-all.sh"
  else
    echo "    3. Deploy your stacks via Portainer or:"
    echo "       ./scripts/deploy-all.sh"
    echo ""
    echo -e "  ${YELLOW}Have a Portainer BE license? Upgrade:${NC}"
    echo "    ./scripts/portainer-install.sh --business --force"
    echo "    Then: ./scripts/swarm-init.sh   (for Swarm + central admin)"
  fi
  echo ""
  echo "    To generate Portainer API tokens (for automation):"
  echo "    → top-right username → My Account → Access Tokens → Add"
  echo "    → Add to config/node-inventory.env as PORTAINER_TOKEN=ptr_..."
  echo ""
fi

if [[ "$FAILED" -gt 0 ]]; then
  echo -e "  ${YELLOW}To retry failed nodes:${NC}"
  echo "    ./scripts/ssh-auditor.sh         # re-audit SSH"
  echo "    ./scripts/portainer-install.sh   # retry install"
  echo ""
fi

echo "  Check status anytime:"
echo "    ./scripts/portainer-install.sh --status"
echo ""
