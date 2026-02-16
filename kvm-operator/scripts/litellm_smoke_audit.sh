#!/usr/bin/env bash
set -euo pipefail

LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-}"

echo "[1/2] Checking LiteLLM /v1/models"
if [[ -z "$LITELLM_MASTER_KEY" ]]; then
  echo "WARN: LITELLM_MASTER_KEY not set in env. Export it then re-run."
  exit 0
fi
curl -fsS "${LITELLM_URL}/v1/models" -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" | head -c 300 && echo

echo "[2/2] Done"
