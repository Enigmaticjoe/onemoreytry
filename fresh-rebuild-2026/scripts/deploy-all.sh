#!/usr/bin/env bash
# Fresh Rebuild 2026 — Master Deploy Script
#
# Deploys all Phase 1 nodes in the correct order.
# Reads node IPs and SSH users from inventory/node-inventory.env.
#
# Usage:
#   ./scripts/deploy-all.sh               # deploy all nodes
#   ./scripts/deploy-all.sh --node-b-only # deploy Node B only (local Unraid)
#   DRYRUN=true ./scripts/deploy-all.sh   # print commands without executing
#
# Deploy order: Node A → Node B → Node C
# (Node D is manual HA configuration — see node-d/README.md)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ─── Dry-run support ──────────────────────────────────────────────────────────
DRYRUN="${DRYRUN:-false}"
run() {
  if [[ "$DRYRUN" == "true" ]]; then
    echo "[DRYRUN] $*"
  else
    "$@"
  fi
}

# ─── Flags ────────────────────────────────────────────────────────────────────
NODE_B_ONLY=false
SKIP_VERIFY=false
for arg in "$@"; do
  case "$arg" in
    --node-b-only) NODE_B_ONLY=true ;;
    --skip-verify) SKIP_VERIFY=true ;;
  esac
done

# ─── Load inventory ──────────────────────────────────────────────────────────
INVENTORY="${REPO_ROOT}/inventory/node-inventory.env"
if [[ -f "$INVENTORY" ]]; then
  # shellcheck disable=SC1090
  source "$INVENTORY"
fi
NODE_A_IP="${NODE_A_IP:-192.168.1.9}"
NODE_B_IP="${NODE_B_IP:-192.168.1.222}"
NODE_C_IP="${NODE_C_IP:-192.168.1.6}"
NODE_A_SSH_USER="${NODE_A_SSH_USER:-root}"
NODE_B_SSH_USER="${NODE_B_SSH_USER:-root}"
NODE_C_SSH_USER="${NODE_C_SSH_USER:-root}"
NODE_A_TS_IP="${NODE_A_TS_IP:-}"
NODE_B_TS_IP="${NODE_B_TS_IP:-}"
NODE_C_TS_IP="${NODE_C_TS_IP:-}"

resolve_ip() { local ts="${1:-}" lan="${2:-}"; [[ -n "$ts" ]] && echo "$ts" || echo "$lan"; }
REACH_A="$(resolve_ip "$NODE_A_TS_IP" "$NODE_A_IP")"
REACH_B="$(resolve_ip "$NODE_B_TS_IP" "$NODE_B_IP")"
REACH_C="$(resolve_ip "$NODE_C_TS_IP" "$NODE_C_IP")"

# ─── Colours ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

step()  { echo ""; echo -e "${CYAN}══════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}══════════════════════════════════${NC}"; }
ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}!${NC} $1"; }
info()  { echo -e "    $1"; }

ERRORS=0
note_error() { ((ERRORS++)) || true; }

# ─── SSH deploy helper ────────────────────────────────────────────────────────
# remote_compose USER HOST COMPOSE_FILE [extra args]
# Copies the compose file + its .env to the remote host, then runs `docker compose up -d`.
remote_compose() {
  local user="$1" host="$2" compose_file="$3"
  shift 3
  local extra_args=("$@")
  local remote_dir="/tmp/fresh-rebuild-2026-deploy"
  local env_file
  env_file="$(dirname "$compose_file")/.env"

  info "Syncing compose file to ${user}@${host}:${remote_dir}"
  if [[ "$DRYRUN" == "true" ]]; then
    echo "[DRYRUN] ssh ${user}@${host} mkdir -p ${remote_dir}"
    echo "[DRYRUN] scp ${compose_file} ${user}@${host}:${remote_dir}/compose.yml"
    [[ -f "$env_file" ]] && echo "[DRYRUN] scp ${env_file} ${user}@${host}:${remote_dir}/.env"
    echo "[DRYRUN] ssh ${user}@${host} docker compose -f ${remote_dir}/compose.yml up -d ${extra_args[*]:-}"
    return
  fi

  ssh "${user}@${host}" "mkdir -p ${remote_dir}"
  scp "$compose_file" "${user}@${host}:${remote_dir}/compose.yml"
  if [[ -f "$env_file" ]]; then
    scp "$env_file" "${user}@${host}:${remote_dir}/.env"
  fi
  ssh "${user}@${host}" "cd ${remote_dir} && docker compose -f compose.yml up -d ${extra_args[*]:-}"
}

# ─── Header ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   Fresh Rebuild 2026 — Master Deploy              ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════╝${NC}"
[[ "$DRYRUN" == "true" ]] && echo -e "  ${YELLOW}DRYRUN mode — no changes will be made${NC}"
[[ "$NODE_B_ONLY" == "true" ]] && echo -e "  ${YELLOW}--node-b-only: skipping Node A and Node C${NC}"
echo ""

# ─── Step 1: Node A ───────────────────────────────────────────────────────────
if [[ "$NODE_B_ONLY" == "false" ]]; then
  step "1/3  Node A — Ollama ROCm + Portainer Agent (${REACH_A})"
  if run bash "${SCRIPT_DIR}/node-a/deploy.sh"; then
    ok "Node A deployed"
  else
    warn "Node A deploy failed — continuing (non-fatal in --node-b-only scenario)"
    note_error
  fi
fi

# ─── Step 2: Node B ───────────────────────────────────────────────────────────
step "2/3  Node B — Infra + AI stack (${REACH_B})"
if run bash "${SCRIPT_DIR}/node-b/deploy.sh"; then
  ok "Node B deployed"
else
  warn "Node B deploy reported errors"
  note_error
fi

# ─── Step 3: Node C ───────────────────────────────────────────────────────────
if [[ "$NODE_B_ONLY" == "false" ]]; then
  step "3/3  Node C — Open WebUI (${REACH_C})"
  if run bash "${SCRIPT_DIR}/node-c/deploy.sh"; then
    ok "Node C deployed"
  else
    warn "Node C deploy reported errors"
    note_error
  fi
fi

# ─── Post-deploy verification ─────────────────────────────────────────────────
if [[ "$SKIP_VERIFY" == "false" && "$DRYRUN" == "false" ]]; then
  step "Verifying deployments"
  [[ "$NODE_B_ONLY" == "false" ]] && bash "${SCRIPT_DIR}/node-a/verify.sh" || true
  bash "${SCRIPT_DIR}/node-b/verify.sh" || note_error
  [[ "$NODE_B_ONLY" == "false" ]] && bash "${SCRIPT_DIR}/node-c/verify.sh" || true
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
if [[ "$ERRORS" -eq 0 ]]; then
  echo -e "  ${GREEN}All deployments completed successfully.${NC}"
  echo ""
  echo "  Next steps:"
  echo "  • Node D (Home Assistant): see fresh-rebuild-2026/node-d/README.md"
  echo "  • Open WebUI: http://${REACH_C}:3000"
  echo "  • Homepage:   http://${REACH_B}:8010"
  echo "  • Portainer:  http://${REACH_B}:9000"
else
  echo -e "  ${RED}Deploy completed with ${ERRORS} error(s).${NC}"
  echo "  Review the output above and re-run the failed node scripts."
fi
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo ""

[[ "$ERRORS" -gt 0 ]] && exit 1 || exit 0
