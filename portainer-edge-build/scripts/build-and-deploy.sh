#!/usr/bin/env bash
set -euo pipefail

# Deploys Portainer BE centrally and Edge Agents to nodes A/B/C.
# Usage:
#   ./scripts/build-and-deploy.sh
# Requirements:
#   - .env populated from .env.example
#   - docker + docker compose on each target node
#   - passwordless SSH from runner to each node

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: ${ENV_FILE} not found. Copy .env.example to .env and fill values." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

: "${PORTAINER_HOST_IP:?Missing PORTAINER_HOST_IP in .env}"

NODE_A_IP="${NODE_A_IP:-192.168.1.9}"
NODE_B_IP="${NODE_B_IP:-192.168.1.222}"
NODE_C_IP="${NODE_C_IP:-192.168.1.6}"
SSH_USER="${SSH_USER:-root}"

scp_safe() {
  local src="$1" host="$2" dest="$3"
  scp -o StrictHostKeyChecking=accept-new "${src}" "${SSH_USER}@${host}:${dest}"
}

ssh_safe() {
  local host="$1"; shift
  ssh -o StrictHostKeyChecking=accept-new "${SSH_USER}@${host}" "$@"
}

deploy_central() {
  local host="$1"
  echo "[INFO] Deploying central Portainer BE on ${host}"
  scp_safe "${ROOT_DIR}/central/docker-compose.portainer-be.yml" "${host}" "/tmp/docker-compose.portainer-be.yml"
  scp_safe "${ENV_FILE}" "${host}" "/tmp/portainer-edge.env"
  ssh_safe "${host}" "docker compose --env-file /tmp/portainer-edge.env -f /tmp/docker-compose.portainer-be.yml up -d"
}

deploy_edge() {
  local host="$1" compose_file="$2"
  echo "[INFO] Deploying edge agent on ${host}"
  scp_safe "${compose_file}" "${host}" "/tmp/docker-compose.edge-agent.yml"
  scp_safe "${ENV_FILE}" "${host}" "/tmp/portainer-edge.env"
  ssh_safe "${host}" "docker compose --env-file /tmp/portainer-edge.env -f /tmp/docker-compose.edge-agent.yml up -d"
}

deploy_central "${NODE_B_IP}"
deploy_edge "${NODE_A_IP}" "${ROOT_DIR}/node-a/docker-compose.edge-agent.yml"
deploy_edge "${NODE_B_IP}" "${ROOT_DIR}/node-b/docker-compose.edge-agent.yml"
deploy_edge "${NODE_C_IP}" "${ROOT_DIR}/node-c/docker-compose.edge-agent.yml"

echo "[DONE] Deployed. Open https://${PORTAINER_HOST_IP}:9443 to finish first-time setup."
