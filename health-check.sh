#!/usr/bin/env bash
# Cron-able health monitor for NanoClaw stack.
# Intended for Unraid User Scripts plugin (every 5 minutes).

set -Eeuo pipefail

ENV_FILE="/mnt/user/appdata/nanoclaw/.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
NANOCLAW_HEALTH_PORT="${NANOCLAW_HEALTH_PORT:-3000}"
OLLAMA_HEALTH_URL="${OLLAMA_HEALTH_URL:-http://192.168.1.222:11434/api/tags}"
UNRAIDCLAW_HEALTH_URL="${UNRAIDCLAW_HEALTH_URL:-https://192.168.1.222:9876/health}"

failures=()

check_http() {
  local name="$1" url="$2" insecure="${3:-false}"
  local curl_flags=(-fsS --max-time 8)
  if [[ "$insecure" == "true" ]]; then curl_flags+=(-k); fi
  if ! curl "${curl_flags[@]}" "$url" >/dev/null; then
    failures+=("${name} failed: ${url}")
  fi
}

check_command() {
  local name="$1" cmd="$2"
  if ! eval "$cmd" >/dev/null 2>&1; then
    failures+=("${name} failed")
  fi
}

check_http "NanoClaw" "http://127.0.0.1:${NANOCLAW_HEALTH_PORT}/health"
check_http "Ollama" "$OLLAMA_HEALTH_URL"
check_http "UnraidClaw" "$UNRAIDCLAW_HEALTH_URL" true
check_command "Docker daemon" "docker info"

agent_count="0"
if docker ps --format '{{.Names}}' >/tmp/nanoclaw-containers.$$ 2>/dev/null; then
  agent_count="$(grep -ci 'nanoclaw\|agent' /tmp/nanoclaw-containers.$$ || true)"
  rm -f /tmp/nanoclaw-containers.$$
fi

if ((${#failures[@]} > 0)); then
  msg="🚨 NanoClaw Health Check FAILED on $(hostname)\n- ${failures[*]}\nAgent-like containers: ${agent_count}"
  echo "$msg"
  if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
    esc_msg=${msg//\"/\\\"}
    curl -fsS -H 'Content-Type: application/json' \
      -d "{\"content\":\"${esc_msg}\"}" \
      "$DISCORD_WEBHOOK_URL" >/dev/null || true
  fi
  exit 1
fi

echo "OK: NanoClaw stack healthy. Agent-like containers=${agent_count}"
