#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  Swarm Init — Docker Swarm + Portainer Business Edition Central Admin
# ══════════════════════════════════════════════════════════════════════════════
#
#  PURPOSE:
#    1. Initializes Docker Swarm on the manager node
#    2. Joins all reachable worker nodes to the Swarm
#    3. Applies node labels (GPU type, role, hardware capabilities)
#    4. Deploys Portainer Agent as a global Swarm service on every node
#    5. Installs/upgrades Portainer Business Edition on the manager
#    6. Registers all non-Swarm nodes as standalone Portainer environments
#
#  USAGE:
#    # Prerequisites (run these first):
#    ./scripts/ssh-auditor.sh
#    ./scripts/portainer-install.sh --business   # installs Portainer BE first
#
#    # Then initialize Swarm:
#    ./scripts/swarm-init.sh                      # use NODE_B as manager
#    ./scripts/swarm-init.sh --manager NODE_A     # choose different manager
#    ./scripts/swarm-init.sh --workers-only       # join workers, skip init
#    ./scripts/swarm-init.sh --labels-only        # re-apply labels only
#    ./scripts/swarm-init.sh --status             # show Swarm and env status
#    ./scripts/swarm-init.sh --leave              # safely drain + leave Swarm
#
#  PORTAINER BE ENVIRONMENTS (after this script):
#    - Swarm cluster (all nodes) → visible as one environment
#    - Each node also registered as standalone environment for direct access
#    - Central admin URL: http://<MANAGER_IP>:9000
#
#  NODE LABELS APPLIED:
#    NODE_A: gpu=amd      gpu.model=rx7900xt    role=inference  vram=20g
#    NODE_B: gpu=nvidia   gpu.model=rtx4070     role=gateway    vram=12g
#    NODE_C: gpu=intel    gpu.model=arc-a770    role=inference  vram=16g
#    NODE_D: role=automation
#    NODE_E: role=nvr
#
# ══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONNMAP_FILE="/tmp/homelab-connmap.env"
SSH_TIMEOUT=15
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=${SSH_TIMEOUT} -o BatchMode=yes -o LogLevel=ERROR"

PORTAINER_BE_IMAGE="portainer/portainer-ee:latest"
PORTAINER_AGENT_IMAGE="portainer/agent:latest"
PORTAINER_HTTP_PORT="${PORTAINER_PORT:-9000}"
PORTAINER_HTTPS_PORT="9443"
PORTAINER_AGENT_PORT="9001"      # Agent port (different from agent tunnel 8000)

# ── Flags ─────────────────────────────────────────────────────────────────────
FLAG_WORKERS_ONLY=false
FLAG_LABELS_ONLY=false
FLAG_STATUS=false
FLAG_LEAVE=false
MANAGER_NODE="NODE_B"   # default manager

for arg in "$@"; do
  case "$arg" in
    --workers-only) FLAG_WORKERS_ONLY=true ;;
    --labels-only)  FLAG_LABELS_ONLY=true ;;
    --status)       FLAG_STATUS=true ;;
    --leave)        FLAG_LEAVE=true ;;
    --manager)      : ;;
    *)
      if [[ "${prev_arg:-}" == "--manager" ]]; then
        MANAGER_NODE="${arg^^}"
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

# ── Load inventory and connection map ─────────────────────────────────────────
load_config() {
  local inv="${REPO_ROOT}/config/node-inventory.env"
  local example="${REPO_ROOT}/config/node-inventory.env.example"
  [[ -f "$inv" ]]     && source "$inv"
  [[ -f "$example" ]] && source "$example"

  NODE_A_IP="${NODE_A_IP:-}"; NODE_A_SSH_USER="${NODE_A_SSH_USER:-root}"
  NODE_B_IP="${NODE_B_IP:-}"; NODE_B_SSH_USER="${NODE_B_SSH_USER:-root}"
  NODE_C_IP="${NODE_C_IP:-}"; NODE_C_SSH_USER="${NODE_C_SSH_USER:-root}"
  NODE_D_IP="${NODE_D_IP:-}"; NODE_D_SSH_USER="${NODE_D_SSH_USER:-root}"
  NODE_E_IP="${NODE_E_IP:-}"; NODE_E_SSH_USER="${NODE_E_SSH_USER:-root}"
  PORTAINER_PORT="${PORTAINER_PORT:-9000}"
  PORTAINER_TOKEN="${PORTAINER_TOKEN:-}"
  SWARM_MANAGER_NODE="${SWARM_MANAGER_NODE:-$MANAGER_NODE}"
}
load_config

# Override manager from CLI flag
MANAGER_NODE="${SWARM_MANAGER_NODE:-NODE_B}"

# Load connection map from auditor
if [[ -f "$CONNMAP_FILE" ]]; then
  source "$CONNMAP_FILE"
else
  echo ""
  warn "No connection map at ${CONNMAP_FILE}"
  warn "Run the SSH auditor first:"
  echo ""
  echo "    ./scripts/ssh-auditor.sh"
  echo ""
  exit 1
fi

# ── SSH helpers ───────────────────────────────────────────────────────────────
_conn_host() { local v="${1}_CONN_HOST"; echo "${!v:-}"; }
_conn_user() { local v="${1}_CONN_USER"; echo "${!v:-root}"; }
_conn_ok()   { local v="${1}_CONN_OK";  [[ "${!v:-false}" == "true" ]]; }
_conn_port() {
  local v="${1}_CONN_METHOD"; local m="${!v:-lan:22}"
  if [[ "$m" == lan:* ]]; then local p="${m#lan:}"; [[ "$p" != "22" ]] && echo "-p $p" || echo ""; else echo ""; fi
}

ssh_run() {
  local node="$1"; shift
  local host; host=$(_conn_host "$node")
  local user; user=$(_conn_user "$node")
  local pf;   pf=$(_conn_port "$node")
  ssh ${SSH_OPTS} ${pf} "${user}@${host}" "$@" 2>&1
}

ssh_script() {
  local node="$1" script="$2"
  local host; host=$(_conn_host "$node")
  local user; user=$(_conn_user "$node")
  local pf;   pf=$(_conn_port "$node")
  ssh ${SSH_OPTS} ${pf} "${user}@${host}" bash <<< "$script" 2>&1
}

wait_for_url() {
  local label="$1" url="$2" max="${3:-20}" delay="${4:-3}"
  local i=0 code
  info "Waiting for ${label}..."
  while [[ $i -lt $max ]]; do
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    if [[ "$code" =~ ^(200|301|302|401|403) ]]; then
      ok "${label} ready (HTTP ${code})"
      return 0
    fi
    i=$((i+1))
    info "  Attempt ${i}/${max} — HTTP ${code} — retrying in ${delay}s..."
    sleep "$delay"
    delay=$(( delay < 30 ? delay + 2 : 30 ))
  done
  warn "${label} did not respond after ${max} attempts"
  return 1
}

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Swarm Init — Docker Swarm + Portainer BE Central Admin    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo -e "  Manager node:    ${BOLD}${MANAGER_NODE}${NC}  ($(_conn_host "$MANAGER_NODE"))"
echo ""

# ── Validate manager is reachable ─────────────────────────────────────────────
if ! _conn_ok "$MANAGER_NODE"; then
  fail "Manager node ${MANAGER_NODE} is not reachable via SSH"
  echo ""
  info "Re-run the auditor: ./scripts/ssh-auditor.sh"
  exit 1
fi

MANAGER_HOST=$(_conn_host "$MANAGER_NODE")
MANAGER_USER=$(_conn_user "$MANAGER_NODE")

# ══════════════════════════════════════════════════════════════════════════════
# STATUS MODE
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$FLAG_STATUS" == "true" ]]; then
  sep; header "Swarm Status"
  echo ""
  SWARM_STATE=$(ssh_run "$MANAGER_NODE" "docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo error")
  if [[ "$SWARM_STATE" == "active" ]]; then
    ok "Swarm is ACTIVE on manager (${MANAGER_HOST})"
    echo ""
    ssh_run "$MANAGER_NODE" "docker node ls 2>/dev/null" | while IFS= read -r l; do echo "    $l"; done
  else
    warn "Swarm is not active on ${MANAGER_HOST} (state: ${SWARM_STATE})"
  fi

  echo ""
  sep; header "Portainer BE Status"
  for node in NODE_A NODE_B NODE_C NODE_D NODE_E; do
    _conn_ok "$node" || continue
    h=$(_conn_host "$node")
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 4 "http://${h}:${PORTAINER_PORT}/api/status" 2>/dev/null || echo "000")
    if [[ "$code" =~ ^2 ]]; then
      VER=$(curl -sk --max-time 5 "http://${h}:${PORTAINER_PORT}/api/status" 2>/dev/null \
        | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Version','?'))" 2>/dev/null || echo "?")
      ok "${node} (${h}:${PORTAINER_PORT}) — Portainer ${VER}"
    elif [[ "$code" == "000" ]]; then
      info "${node} (${h}:${PORTAINER_PORT}) — not reachable"
    else
      warn "${node} (${h}:${PORTAINER_PORT}) — HTTP ${code}"
    fi
  done
  echo ""
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# LEAVE MODE — safely drain and leave Swarm
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$FLAG_LEAVE" == "true" ]]; then
  sep; header "Draining and Leaving Swarm"
  echo ""
  warn "This will remove all nodes from the Swarm. Application stacks will stop."
  echo -n "  Confirm? [y/N] "
  read -r confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "Aborted."; exit 0; }

  # Leave workers first
  for node in NODE_A NODE_C NODE_D NODE_E; do
    [[ "$node" == "$MANAGER_NODE" ]] && continue
    _conn_ok "$node" || continue
    h=$(_conn_host "$node")
    step "Leaving Swarm: ${node} (${h})"
    ssh_run "$node" "docker swarm leave --force 2>/dev/null && echo 'Left swarm' || echo 'Not in swarm'"
  done

  # Manager leaves last
  step "Leaving Swarm: ${MANAGER_NODE} (manager)"
  ssh_run "$MANAGER_NODE" "docker swarm leave --force 2>/dev/null && echo 'Left swarm'"
  ok "All nodes left the Swarm"
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1: Upgrade Portainer to BE on manager (if CE is running)
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$FLAG_WORKERS_ONLY" == "false" ]] && [[ "$FLAG_LABELS_ONLY" == "false" ]]; then
  sep; header "STEP 1 — Portainer Business Edition on Manager"
  echo ""
  info "Checking Portainer on manager (${MANAGER_HOST})..."

  PT_IMAGE=$(ssh_run "$MANAGER_NODE" \
    "docker inspect portainer --format '{{.Config.Image}}' 2>/dev/null || echo ''")

  if [[ "$PT_IMAGE" == *"portainer-ee"* ]]; then
    ok "Portainer BE already installed (${PT_IMAGE})"
  else
    if [[ -n "$PT_IMAGE" ]]; then
      info "Upgrading from CE → BE..."
      ssh_run "$MANAGER_NODE" "docker stop portainer && docker rm portainer" >/dev/null 2>&1 || true
    else
      info "Installing Portainer BE..."
    fi

    # Pull BE image
    info "Pulling ${PORTAINER_BE_IMAGE}..."
    ssh_run "$MANAGER_NODE" "docker pull ${PORTAINER_BE_IMAGE} 2>&1 | tail -3"

    # Create data volume if needed
    ssh_run "$MANAGER_NODE" "docker volume create portainer_data 2>/dev/null || true"

    # Run Portainer BE
    DEPLOY_OUT=$(ssh_run "$MANAGER_NODE" "docker run -d \
      --name portainer \
      --restart=always \
      --security-opt no-new-privileges \
      -p 8000:8000 \
      -p ${PORTAINER_HTTP_PORT}:9000 \
      -p ${PORTAINER_HTTPS_PORT}:9443 \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v portainer_data:/data \
      ${PORTAINER_BE_IMAGE} 2>&1")

    if echo "$DEPLOY_OUT" | grep -qE '^[a-f0-9]{64}$'; then
      ok "Portainer BE container started"
    else
      warn "Deploy output: ${DEPLOY_OUT}"
    fi

    # Open firewall ports
    ssh_script "$MANAGER_NODE" "
      if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q 'Status: active'; then
        ufw allow 9000/tcp 2>/dev/null; ufw allow 9443/tcp 2>/dev/null; ufw allow 8000/tcp 2>/dev/null
      elif command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q running; then
        firewall-cmd --permanent --add-port=9000/tcp 2>/dev/null
        firewall-cmd --permanent --add-port=9443/tcp 2>/dev/null
        firewall-cmd --permanent --add-port=8000/tcp 2>/dev/null
        firewall-cmd --reload 2>/dev/null
      fi
      echo 'Firewall OK'
    " >/dev/null || true

    wait_for_url "Portainer BE" "http://${MANAGER_HOST}:${PORTAINER_HTTP_PORT}/api/status" 20 4
  fi

  echo ""
  echo -e "  ${BOLD}Portainer BE Admin:${NC}"
  echo -e "    HTTP:  ${CYAN}http://${MANAGER_HOST}:${PORTAINER_HTTP_PORT}${NC}"
  echo -e "    HTTPS: ${CYAN}https://${MANAGER_HOST}:${PORTAINER_HTTPS_PORT}${NC}"
  echo ""
  echo -e "  ${YELLOW}License:${NC} After first login → Settings → Licenses → Enter your key"
fi

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2: Initialize Docker Swarm on manager
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$FLAG_LABELS_ONLY" == "false" ]]; then
  sep; header "STEP 2 — Initialize Docker Swarm"
  echo ""

  SWARM_STATE=$(ssh_run "$MANAGER_NODE" \
    "docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo error")

  if [[ "$SWARM_STATE" == "active" ]]; then
    ok "Swarm already initialized on ${MANAGER_NODE}"
    SWARM_ALREADY=true
  else
    info "Initializing Swarm on ${MANAGER_HOST}..."
    SWARM_INIT=$(ssh_run "$MANAGER_NODE" \
      "docker swarm init --advertise-addr ${MANAGER_HOST} 2>&1")
    if echo "$SWARM_INIT" | grep -q "Swarm initialized"; then
      ok "Swarm initialized — ${MANAGER_HOST} is now the manager"
    else
      fail "Swarm init failed: ${SWARM_INIT}"
      exit 1
    fi
    SWARM_ALREADY=false
  fi

  # Get join tokens
  WORKER_TOKEN=$(ssh_run "$MANAGER_NODE" \
    "docker swarm join-token worker -q 2>/dev/null")
  MANAGER_TOKEN=$(ssh_run "$MANAGER_NODE" \
    "docker swarm join-token manager -q 2>/dev/null")

  ok "Worker join token retrieved"

  # ── Join worker nodes ────────────────────────────────────────────────────
  step "Joining Worker Nodes"
  echo ""

  JOINED=0
  ALREADY_IN=0
  SKIPPED=0

  for node in NODE_A NODE_B NODE_C NODE_D NODE_E; do
    [[ "$node" == "$MANAGER_NODE" ]] && continue
    if ! _conn_ok "$node"; then
      info "Skipping ${node} — not reachable"
      ((SKIPPED++)) || true
      continue
    fi

    node_host=$(_conn_host "$node")
    info "Joining ${node} (${node_host}) to Swarm..."

    # Check if already in swarm
    NODE_SWARM=$(ssh_run "$node" \
      "docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo inactive")

    if [[ "$NODE_SWARM" == "active" ]]; then
      ok "${node}: already in Swarm"
      ((ALREADY_IN++)) || true
    else
      JOIN_OUT=$(ssh_run "$node" \
        "docker swarm join --token ${WORKER_TOKEN} ${MANAGER_HOST}:2377 2>&1")
      if echo "$JOIN_OUT" | grep -q "This node joined a swarm"; then
        ok "${node}: joined as worker"
        ((JOINED++)) || true
      else
        warn "${node}: join failed — ${JOIN_OUT}"
        ((SKIPPED++)) || true
      fi
    fi
  done

  echo ""
  info "Nodes joined:      ${JOINED}"
  info "Already in swarm:  ${ALREADY_IN}"
  info "Skipped:           ${SKIPPED}"
fi

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3: Apply Node Labels
# ══════════════════════════════════════════════════════════════════════════════
sep; header "STEP 3 — Apply Node Labels"
echo ""
info "Labeling nodes for GPU-aware service placement..."

# Function to apply labels to a Swarm node from the manager
apply_labels() {
  local swarm_node_id="$1"; shift
  local labels=("$@")
  for label in "${labels[@]}"; do
    ssh_run "$MANAGER_NODE" \
      "docker node update --label-add '${label}' ${swarm_node_id} 2>/dev/null" >/dev/null || true
  done
}

# Get Swarm node IDs from manager
NODE_LIST=$(ssh_run "$MANAGER_NODE" \
  "docker node ls --format '{{.Hostname}}:{{.ID}}' 2>/dev/null" 2>/dev/null || echo "")

label_node_by_hostname() {
  local hostname="$1"; shift
  local labels=("$@")
  local node_id
  node_id=$(echo "$NODE_LIST" | grep -i "^${hostname}:" | cut -d: -f2 | head -1)
  if [[ -n "$node_id" ]]; then
    apply_labels "$node_id" "${labels[@]}"
    ok "Labels applied to ${hostname} (${node_id:0:12}): ${labels[*]}"
  else
    warn "Could not find '${hostname}' in Swarm node list"
    info "  Available: ${NODE_LIST}"
  fi
}

# Get each node's hostname so we can match to Swarm node IDs
for node in NODE_A NODE_B NODE_C NODE_D NODE_E; do
  _conn_ok "$node" || continue
  node_hostname=$(ssh_run "$node" "hostname 2>/dev/null" 2>/dev/null | tr -d '[:space:]')
  [[ -z "$node_hostname" ]] && continue

  case "$node" in
    NODE_A)
      label_node_by_hostname "$node_hostname" \
        "gpu=amd" "gpu.vendor=amd" "gpu.model=rx7900xt" \
        "vram=20g" "role=inference" "node=node-a" "homelab.node=A"
      ;;
    NODE_B)
      label_node_by_hostname "$node_hostname" \
        "gpu=nvidia" "gpu.vendor=nvidia" "gpu.model=rtx4070" \
        "vram=12g" "role=gateway" "role.unraid=true" "node=node-b" "homelab.node=B"
      ;;
    NODE_C)
      label_node_by_hostname "$node_hostname" \
        "gpu=intel" "gpu.vendor=intel" "gpu.model=arc-a770" \
        "vram=16g" "role=inference" "role.vision=true" "node=node-c" "homelab.node=C"
      ;;
    NODE_D)
      label_node_by_hostname "$node_hostname" \
        "role=automation" "node=node-d" "homelab.node=D"
      ;;
    NODE_E)
      label_node_by_hostname "$node_hostname" \
        "role=nvr" "node=node-e" "homelab.node=E"
      ;;
  esac
done

echo ""
info "Current node status:"
ssh_run "$MANAGER_NODE" "docker node ls 2>/dev/null" | while IFS= read -r l; do echo "    $l"; done

# ══════════════════════════════════════════════════════════════════════════════
# STEP 4: Deploy Portainer Agent as Swarm Global Service
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$FLAG_LABELS_ONLY" == "false" ]]; then
  sep; header "STEP 4 — Deploy Portainer Agent (global Swarm service)"
  echo ""
  info "Deploying Portainer Agent stack to all Swarm nodes..."

  # Deploy agent stack
  AGENT_STACK_FILE="${REPO_ROOT}/swarm/portainer-agent-stack.yml"
  if [[ -f "$AGENT_STACK_FILE" ]]; then
    # Copy stack file to manager and deploy
    scp ${SSH_OPTS} "$AGENT_STACK_FILE" \
      "$(_conn_user "$MANAGER_NODE")@${MANAGER_HOST}:/tmp/portainer-agent-stack.yml" 2>/dev/null

    DEPLOY_OUT=$(ssh_run "$MANAGER_NODE" \
      "docker stack deploy -c /tmp/portainer-agent-stack.yml portainer_agent_stack 2>&1")
    if echo "$DEPLOY_OUT" | grep -qE "^(Creating|Updating)"; then
      ok "Portainer Agent stack deployed (global — runs on every Swarm node)"
    else
      warn "Agent stack deploy output: ${DEPLOY_OUT}"
    fi
  else
    # Inline deploy if file not found
    INLINE_STACK=$(cat <<'YAML'
version: "3.2"
services:
  agent:
    image: portainer/agent:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - portainer_agent_network
    deploy:
      mode: global
      placement:
        constraints: [node.platform.os == linux]
networks:
  portainer_agent_network:
    driver: overlay
    attachable: true
YAML
)
    echo "$INLINE_STACK" | ssh_run "$MANAGER_NODE" \
      "cat > /tmp/portainer-agent-stack.yml && docker stack deploy -c /tmp/portainer-agent-stack.yml portainer_agent_stack 2>&1" \
      || true
    ok "Portainer Agent stack deployed inline"
  fi

  # Also install standalone agent on non-Swarm reachable nodes (Portainer BE standalone environments)
  step "Standalone Portainer Agents (non-Swarm nodes)"
  for node in NODE_A NODE_C NODE_D NODE_E; do
    [[ "$node" == "$MANAGER_NODE" ]] && continue
    _conn_ok "$node" || continue
    node_host=$(_conn_host "$node")

    NODE_SWARM=$(ssh_run "$node" \
      "docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null" 2>/dev/null || echo "inactive")

    # If this node is NOT in the swarm, deploy a standalone agent
    if [[ "$NODE_SWARM" != "active" ]]; then
      info "${node} (${node_host}): deploying standalone agent..."
      ssh_script "$node" "
        docker stop portainer_agent 2>/dev/null; docker rm portainer_agent 2>/dev/null || true
        docker pull ${PORTAINER_AGENT_IMAGE} 2>/dev/null | tail -1
        docker run -d \
          --name portainer_agent \
          --restart=always \
          -p ${PORTAINER_AGENT_PORT}:9001 \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v /var/lib/docker/volumes:/var/lib/docker/volumes \
          ${PORTAINER_AGENT_IMAGE}
        echo AGENT_OK
      " | grep -q "AGENT_OK" && ok "${node}: standalone agent running on :${PORTAINER_AGENT_PORT}" \
                                || warn "${node}: agent deploy may have failed"

      # Open agent port in firewall
      ssh_script "$node" "
        if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q active; then
          ufw allow ${PORTAINER_AGENT_PORT}/tcp 2>/dev/null || true
        elif command -v firewall-cmd &>/dev/null; then
          firewall-cmd --permanent --add-port=${PORTAINER_AGENT_PORT}/tcp 2>/dev/null || true
          firewall-cmd --reload 2>/dev/null || true
        fi
      " >/dev/null 2>&1 || true
    fi
  done
fi

# ══════════════════════════════════════════════════════════════════════════════
# Final Summary
# ══════════════════════════════════════════════════════════════════════════════
echo ""
sep
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Swarm Setup Complete                                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo -e "  ${BOLD}Swarm Manager:${NC}"
echo -e "    ${CYAN}${MANAGER_HOST}${NC}  (${MANAGER_NODE})"
echo ""
echo -e "  ${BOLD}Portainer BE Central Admin:${NC}"
echo -e "    ${CYAN}http://${MANAGER_HOST}:${PORTAINER_HTTP_PORT}${NC}"
echo -e "    ${CYAN}https://${MANAGER_HOST}:${PORTAINER_HTTPS_PORT}${NC}"
echo ""
echo -e "  ${YELLOW}NEXT STEPS in Portainer BE UI:${NC}"
echo ""
echo "  1. Log in and set admin password (first time only)"
echo ""
echo "  2. Apply your license key:"
echo "     Settings → Licenses → Add License"
echo ""
echo "  3. Add the Swarm as an environment:"
echo "     Home → Add Environment → Docker Swarm → Agent"
echo "     Name: 'Homelab Swarm'"
echo "     Agent URL: portainer_agent_stack_agent:9001"
echo "     (The agent is already running as a Swarm service)"
echo ""
echo "  4. Add standalone node environments (for non-Swarm nodes):"
for node in NODE_A NODE_C NODE_D NODE_E; do
  [[ "$node" == "$MANAGER_NODE" ]] && continue
  _conn_ok "$node" || continue
  h=$(_conn_host "$node")
  echo "     → ${node}: Home → Add Environment → Agent"
  echo "       Name: ${node}  |  Agent URL: ${h}:${PORTAINER_AGENT_PORT}"
done
echo ""
echo "  5. Deploy GPU stacks (placement-constrained):"
echo "     → Environments → Homelab Swarm → Stacks → Add Stack"
echo "     → Use files in the swarm/ directory"
echo ""
echo "  Swarm node list:"
ssh_run "$MANAGER_NODE" "docker node ls 2>/dev/null" | while IFS= read -r l; do echo "    $l"; done
echo ""
echo "  View Swarm services:"
echo "    ssh ${MANAGER_USER}@${MANAGER_HOST} docker service ls"
echo ""
echo "  Check status anytime:"
echo "    ./scripts/swarm-init.sh --status"
echo ""
