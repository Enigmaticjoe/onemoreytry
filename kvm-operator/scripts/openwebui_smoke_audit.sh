#!/usr/bin/env bash
set -euo pipefail

WEBUI_CONTAINER="${WEBUI_CONTAINER:-open-webui}"
WEBUI_PORT="${WEBUI_PORT:-3000}"

echo "[1/4] Checking container: $WEBUI_CONTAINER"
docker ps --format '{{.Names}}' | grep -qx "$WEBUI_CONTAINER" || { echo "ERROR: container not running"; exit 1; }

echo "[2/4] Checking HTTP reachability: http://localhost:${WEBUI_PORT}"
curl -fsS "http://localhost:${WEBUI_PORT}/" >/dev/null || { echo "ERROR: WebUI not reachable"; exit 1; }

echo "[3/4] Checking persistence (volume or bind)"
# If you used a named volume "open-webui", this prints the mountpoint
if docker volume inspect open-webui >/dev/null 2>&1; then
  MP="$(docker volume inspect open-webui -f '{{.Mountpoint}}')"
  echo "Open WebUI volume mountpoint: $MP"
  # Open WebUI docs show these expected items in the data store:
  # audit.log, uploads/, vector_db/, webui.db
  for item in audit.log uploads vector_db webui.db; do
    if [[ ! -e "$MP/$item" ]]; then
      echo "WARN: missing $item under $MP (may be new install or different layout)"
    else
      echo "OK: found $item"
    fi
  done
else
  echo "INFO: docker volume 'open-webui' not found. If you bind-mounted data, set OPEN_WEBUI_DATA_DIR and check manually."
fi

echo "[4/4] Checking Ollama connectivity from WebUI network namespace"
OLLAMA_BASE_URL="$(docker inspect "$WEBUI_CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' | awk -F= '/^OLLAMA_BASE_URL=/{print $2}' | tail -n1 || true)"
if [[ -z "${OLLAMA_BASE_URL}" ]]; then
  echo "WARN: OLLAMA_BASE_URL not set in container env."
  exit 0
fi
echo "OLLAMA_BASE_URL=$OLLAMA_BASE_URL"
docker run --rm --network "container:${WEBUI_CONTAINER}" curlimages/curl:8.5.0 -fsS "${OLLAMA_BASE_URL}/api/version" >/dev/null \
  && echo "OK: WebUI namespace can reach Ollama" \
  || echo "WARN: WebUI namespace cannot reach Ollama (check host.docker.internal mapping / firewall / Ollama bind)"
