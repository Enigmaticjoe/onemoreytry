#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

PORTAINER_HOST_IP="${PORTAINER_HOST_IP:-192.168.1.222}"
NODE_A_IP="${NODE_A_IP:-192.168.1.9}"
NODE_B_IP="${NODE_B_IP:-192.168.1.222}"
NODE_C_IP="${NODE_C_IP:-192.168.1.6}"
SSH_USER="${SSH_USER:-root}"

check_http() {
  local name="$1" url="$2"
  if curl -kfsS --max-time 5 "$url" >/dev/null; then
    echo "[OK] ${name}: ${url}"
  else
    echo "[WARN] ${name}: ${url} unreachable"
  fi
}

check_remote_container() {
  local name="$1" host="$2" container="$3"
  if ssh -o StrictHostKeyChecking=accept-new "${SSH_USER}@${host}" "docker ps --format '{{.Names}}' | grep -Fxq '${container}'"; then
    echo "[OK] ${name}: container '${container}' running"
  else
    echo "[WARN] ${name}: container '${container}' not running"
  fi
}

check_http "Portainer UI" "https://${PORTAINER_HOST_IP}:9443"
check_remote_container "Node A" "${NODE_A_IP}" "portainer-edge-agent"
check_remote_container "Node B" "${NODE_B_IP}" "portainer-edge-agent"
check_remote_container "Node C" "${NODE_C_IP}" "portainer-edge-agent"
