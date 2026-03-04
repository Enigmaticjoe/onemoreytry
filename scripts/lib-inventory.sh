#!/usr/bin/env bash
set -euo pipefail

load_inventory() {
  local repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  local inventory_file="${NODE_INVENTORY_FILE:-${repo_root}/config/node-inventory.env}"

  if [ -f "$inventory_file" ]; then
    # shellcheck disable=SC1090
    source "$inventory_file"
  fi

  NODE_A_IP="${NODE_A_IP:-192.168.1.9}"
  NODE_B_IP="${NODE_B_IP:-192.168.1.222}"
  NODE_C_IP="${NODE_C_IP:-192.168.1.6}"
  NODE_D_IP="${NODE_D_IP:-192.168.1.149}"
  NODE_E_IP="${NODE_E_IP:-192.168.1.116}"
  KVM_IP="${KVM_IP:-192.168.1.130}"

  NODE_A_SSH_USER="${NODE_A_SSH_USER:-root}"
  NODE_B_SSH_USER="${NODE_B_SSH_USER:-root}"
  NODE_C_SSH_USER="${NODE_C_SSH_USER:-root}"
  NODE_D_SSH_USER="${NODE_D_SSH_USER:-root}"
  NODE_E_SSH_USER="${NODE_E_SSH_USER:-root}"

  # Tailscale IPs — preferred over LAN IPs for remote connections
  # Set these in config/node-inventory.env to match your Tailscale network.
  NODE_A_TS_IP="${NODE_A_TS_IP:-}"
  NODE_B_TS_IP="${NODE_B_TS_IP:-}"
  NODE_C_TS_IP="${NODE_C_TS_IP:-}"
  NODE_D_TS_IP="${NODE_D_TS_IP:-}"
  NODE_E_TS_IP="${NODE_E_TS_IP:-}"
  KVM_TS_IP="${KVM_TS_IP:-}"
  NANOKVM_TS_IP="${NANOKVM_TS_IP:-}"

  # Portainer defaults
  PORTAINER_PORT="${PORTAINER_PORT:-9000}"
  PORTAINER_TOKEN="${PORTAINER_TOKEN:-}"
}

is_missing_or_placeholder_ip() {
  local ip="${1:-}"
  [[ -z "$ip" || "$ip" == *"192.168.1.X"* || "$ip" == *"192.168.1.Y"* || "$ip" == *"192.168.1.Z"* ]]
}

# resolve_node_ip NODE_TS_IP NODE_LAN_IP
# Returns the Tailscale IP if non-empty, otherwise falls back to the LAN IP.
resolve_node_ip() {
  local ts_ip="${1:-}" lan_ip="${2:-}"
  if [ -n "$ts_ip" ]; then
    echo "$ts_ip"
  else
    echo "$lan_ip"
  fi
}

# tailscale_available
# Returns 0 if the tailscale CLI is present and the daemon is running.
tailscale_available() {
  command -v tailscale &>/dev/null && tailscale status &>/dev/null 2>&1
}
