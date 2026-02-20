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
  NODE_E_IP="${NODE_E_IP:-}"

  NODE_A_SSH_USER="${NODE_A_SSH_USER:-root}"
  NODE_B_SSH_USER="${NODE_B_SSH_USER:-root}"
  NODE_C_SSH_USER="${NODE_C_SSH_USER:-root}"
}

is_missing_or_placeholder_ip() {
  local ip="${1:-}"
  [[ -z "$ip" || "$ip" == *"192.168.1.X"* || "$ip" == *"192.168.1.Y"* || "$ip" == *"192.168.1.Z"* ]]
}
