#!/usr/bin/env bash
# Grand Unified AI Home Lab — Environment Setup Wizard
# Generates every .env file required by each node and service.
#
# Run this once before your first deployment:
#   ./scripts/setup-env.sh
#
# The script will:
#   1. Ask for values that are unique to your setup (IPs, tokens, passwords).
#   2. Pre-fill sensible defaults so you can just press Enter where possible.
#   3. Write all .env files in-place, skipping any that already exist
#      (unless you pass --force).
#   4. Print a short summary of where each file lives and, for remote nodes,
#      instructions on where to copy the file.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ── Flags ─────────────────────────────────────────────────────────────────────
FORCE=false
for arg in "$@"; do
  [[ "$arg" == "--force" ]] && FORCE=true
done

# ── Colours ───────────────────────────────────────────────────────────────────
source "${REPO_ROOT}/scripts/lib-colors.sh"

ok()     { echo -e "  ${GREEN}✓${NC} $1"; }
err()    { echo -e "  ${RED}✗${NC} $1"; }
warn()   { echo -e "  ${YELLOW}!${NC} $1"; }
info()   { echo -e "  ${CYAN}→${NC} $1"; }
header() { echo -e "${BOLD}$1${NC}"; }
dim()    { echo -e "${DIM}$1${NC}"; }
step()   { echo ""; echo -e "${CYAN}──────────────────────────────────────────${NC}"; echo -e "${BOLD}  $1${NC}"; echo -e "${CYAN}──────────────────────────────────────────${NC}"; }

# ── Prompt helper ─────────────────────────────────────────────────────────────
# ask VAR_NAME "Prompt text" "default value"
# Reads a value into a global variable named VAR_NAME.
ask() {
  local var_name="$1" prompt_text="$2" default_val="${3:-}"
  local display_default=""
  if [ -n "$default_val" ]; then
    display_default=" [${DIM}${default_val}${NC}]"
  fi
  printf "  %b%s%b%b: " "${CYAN}" "$prompt_text" "${NC}" "$display_default"
  local input
  IFS= read -r input 2>/dev/null || input=""
  if [ -z "$input" ] && [ -n "$default_val" ]; then
    input="$default_val"
  fi
  printf -v "$var_name" '%s' "$input"
}

# ask_secret VAR_NAME "Prompt text"
# Like ask() but hides input (for passwords/tokens).
ask_secret() {
  local var_name="$1" prompt_text="$2"
  printf "  %b%s%b (input hidden): " "${CYAN}" "$prompt_text" "${NC}"
  local input
  if read -rs input 2>/dev/null; then
    echo ""
  else
    IFS= read -r input 2>/dev/null || input=""
  fi
  printf -v "$var_name" '%s' "$input"
}

# gen_token — generate a random hex token using openssl
gen_token() {
  local len="${1:-24}"
  openssl rand -hex "$len" 2>/dev/null || \
    head -c "$((len * 2))" /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c "$((len * 2))"
}

# write_env_file DST_PATH CONTENT
# Writes CONTENT to DST_PATH unless the file already exists and --force was not set.
write_env_file() {
  local dst="$1" content="$2"
  if [ -f "$dst" ] && [ "$FORCE" = false ]; then
    warn "Skipping ${dst} — already exists (use --force to overwrite)"
    return 0
  fi
  # Atomic write: tmp → mv
  local tmp
  tmp="$(mktemp)"
  printf '%s\n' "$content" > "$tmp"
  mv "$tmp" "$dst"
  ok "Written: ${dst}"
}

# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   Grand Unified AI Home Lab — Env Setup Wizard         ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  This wizard will create the .env files for every node and service."
echo "  Press Enter to accept the default value shown in brackets."
echo "  Values shared across nodes (like IPs and API keys) are asked once."
echo ""
if [ "$FORCE" = true ]; then
  warn "--force mode: existing .env files WILL be overwritten."
else
  dim "  Tip: run with --force to regenerate files that already exist."
fi

# ─────────────────────────────────────────────────────────────────────────────
step "1 / 5 — Node IPs, Tailscale IPs & SSH users"
# ─────────────────────────────────────────────────────────────────────────────
echo ""
header "  LAN IPs (used for local service health checks and fallback)"
echo ""

ask NODE_A_IP      "Node A LAN IP (Brain / AMD RX 7900 XT)"  "192.168.1.9"
ask NODE_B_IP      "Node B LAN IP (Unraid / RTX 4070)"       "192.168.1.222"
ask NODE_C_IP      "Node C LAN IP (Intel Arc)"               "192.168.1.6"
ask NODE_D_IP      "Node D LAN IP (Home Assistant)"          "192.168.1.149"
ask NODE_E_IP      "Node E LAN IP (Sentinel / NVR)"          "192.168.1.116"
ask KVM_IP         "NanoKVM LAN IP"                          "192.168.1.130"
ask KVM_HOSTNAME   "NanoKVM mDNS hostname"                   "kvm-d829.local"

echo ""
header "  Tailscale IPs (used for all remote connections — preferred over LAN IPs)"
dim "  Run 'tailscale status' on each node to verify these addresses."
echo ""

ask NODE_A_TS_IP    "Node A Tailscale IP (node-a)"           "100.120.119.26"
ask NODE_B_TS_IP    "Node B Tailscale IP (node-b-unraid)"    "100.99.104.80"
ask NODE_C_TS_IP    "Node C Tailscale IP (node-c)"           "100.64.20.118"
ask NODE_D_TS_IP    "Node D Tailscale IP (optional)"         ""
ask NODE_E_TS_IP    "Node E Tailscale IP (optional)"         ""
ask KVM_TS_IP       "KVM Tailscale IP (node-a-kvm)"          "100.99.133.29"
ask NANOKVM_TS_IP   "NanoKVM Tailscale IP (node-c-nanokvm)"  "100.90.139.95"

echo ""
header "  SSH users"
echo ""
ask NODE_A_SSH_USER "SSH user for Node A"  "root"
ask NODE_B_SSH_USER "SSH user for Node B"  "root"
ask NODE_C_SSH_USER "SSH user for Node C"  "root"
ask NODE_D_SSH_USER "SSH user for Node D"  "root"
ask NODE_E_SSH_USER "SSH user for Node E"  "root"

# ─────────────────────────────────────────────────────────────────────────────
step "2 / 5 — Shared secrets (asked once, reused across files)"
# ─────────────────────────────────────────────────────────────────────────────
echo ""
header "  LiteLLM master key"
dim "  Bearer token used by every service that talks to the LiteLLM gateway."
ask LITELLM_API_KEY "LiteLLM master API key" "sk-master-key"

echo ""
header "  KVM Operator token"
dim "  Shared secret between OpenClaw and the KVM Operator FastAPI service."
GENERATED_KVM_TOKEN="$(gen_token 24)"
ask KVM_OPERATOR_TOKEN "KVM Operator token (or press Enter to auto-generate)" "$GENERATED_KVM_TOKEN"

echo ""
header "  OpenClaw Gateway token"
dim "  Access token for the OpenClaw UI: http://<NODE_C_IP>:18789/?token=<this>"
GENERATED_OC_TOKEN="$(gen_token 24)"
ask OPENCLAW_GATEWAY_TOKEN "OpenClaw gateway token (or press Enter to auto-generate)" "$GENERATED_OC_TOKEN"

echo ""
header "  HuggingFace token"
dim "  Required for gated models (Llama 3, Gemma, etc.)."
dim "  Get one at: https://huggingface.co/settings/tokens"
ask HUGGINGFACE_TOKEN "HuggingFace Hub token" "hf_your_token_here"

# ─────────────────────────────────────────────────────────────────────────────
step "3 / 5 — Optional cloud & service credentials"
# ─────────────────────────────────────────────────────────────────────────────
echo ""
header "  Tailscale auth key (used by the Unraid management stack)"
dim "  Generate at: https://login.tailscale.com/admin/authkeys"
ask TAILSCALE_AUTHKEY "Tailscale auth key" "tskey-auth-XXXXXXXXXXXXXXXX"

echo ""
header "  Home Assistant long-lived access token"
dim "  Settings → Security → Long-lived access tokens in the HA UI."
ask HA_LONG_LIVED_TOKEN "HA long-lived access token" "your-ha-long-lived-token-here"

echo ""
header "  VPN credentials (Gluetun, used in Node B stacks)"
ask VPN_SERVICE_PROVIDER "VPN provider (e.g. private internet access, mullvad)" "private internet access"
ask VPN_USER     "VPN username" "your-vpn-username"
ask_secret VPN_PASSWORD "VPN password"
if [ -z "$VPN_PASSWORD" ]; then VPN_PASSWORD="your-vpn-password"; fi

echo ""
header "  Cloudflare tunnel token (optional — leave default to skip)"
dim "  dash.cloudflare.com → Zero Trust → Access → Tunnels"
ask CLOUDFLARE_TUNNEL_TOKEN "Cloudflare tunnel token" "your-cloudflare-tunnel-token"

echo ""
header "  NanoKVM credentials"
ask NANOKVM_USERNAME "NanoKVM web UI username" "admin"
ask_secret NANOKVM_PASSWORD "NanoKVM web UI password"
if [ -z "$NANOKVM_PASSWORD" ]; then NANOKVM_PASSWORD="admin"; fi

# ─────────────────────────────────────────────────────────────────────────────
step "4 / 5 — Service-specific settings"
# ─────────────────────────────────────────────────────────────────────────────
echo ""
header "  Timezone"
ask TZ "Timezone (e.g. America/Chicago)" "America/Chicago"

echo ""
header "  Node A vLLM model"
dim "  Tested options for RX 7900 XT (20 GB VRAM):"
dim "    meta-llama/Llama-3.1-8B-Instruct   (~18 GB, fp16)"
dim "    mistralai/Mistral-7B-Instruct-v0.3 (~15 GB, fp16)"
ask VLLM_MODEL_A "vLLM model for Node A" "meta-llama/Llama-3.1-8B-Instruct"

echo ""
header "  Node B vLLM model (RTX 4070, 12 GB VRAM)"
dim "  Examples: mistralai/Mistral-7B-Instruct-v0.3"
dim "            microsoft/Phi-3-mini-128k-instruct"
ask VLLM_MODEL_B "vLLM model for Node B" "mistralai/Mistral-7B-Instruct-v0.3"

echo ""
header "  SearXNG secret key (Node B AI orchestration stack)"
GENERATED_SEARXNG="$(gen_token 32)"
ask SEARXNG_SECRET_KEY "SearXNG secret key (or press Enter to auto-generate)" "$GENERATED_SEARXNG"

echo ""
header "  Nextcloud database passwords"
ask NEXTCLOUD_DB_ROOT_PASSWORD "Nextcloud DB root password" "changeme-root"
ask NEXTCLOUD_DB_PASSWORD      "Nextcloud DB user password" "changeme-nc"

# ─────────────────────────────────────────────────────────────────────────────
step "5 / 5 — Writing .env files"
# ─────────────────────────────────────────────────────────────────────────────
echo ""

# ── config/node-inventory.env ─────────────────────────────────────────────────
write_env_file "${REPO_ROOT}/config/node-inventory.env" \
"# Grand Unified AI Homelab — Node Inventory
# Generated by scripts/setup-env.sh — edit to taste.

# ── Node IPs ──────────────────────────────────────────────────────────────────
NODE_A_IP=${NODE_A_IP}
NODE_B_IP=${NODE_B_IP}
NODE_C_IP=${NODE_C_IP}
NODE_D_IP=${NODE_D_IP}
NODE_E_IP=${NODE_E_IP}
KVM_IP=${KVM_IP}
KVM_HOSTNAME=${KVM_HOSTNAME}

# ── SSH Users ─────────────────────────────────────────────────────────────────
NODE_A_SSH_USER=${NODE_A_SSH_USER}
NODE_B_SSH_USER=${NODE_B_SSH_USER}
NODE_C_SSH_USER=${NODE_C_SSH_USER}
NODE_D_SSH_USER=${NODE_D_SSH_USER}
NODE_E_SSH_USER=${NODE_E_SSH_USER}

# ── Tailscale IPs — preferred for all remote connections ─────────────────────
NODE_A_TS_IP=${NODE_A_TS_IP}
NODE_B_TS_IP=${NODE_B_TS_IP}
NODE_C_TS_IP=${NODE_C_TS_IP}
NODE_D_TS_IP=${NODE_D_TS_IP}
NODE_E_TS_IP=${NODE_E_TS_IP}
KVM_TS_IP=${KVM_TS_IP}
NANOKVM_TS_IP=${NANOKVM_TS_IP}

# ── Service Ports ─────────────────────────────────────────────────────────────
PORTAINER_PORT=9000
PORTAINER_HTTPS_PORT=9443
PORTAINER_AGENT_PORT=8000
LITELLM_PORT=4000
OLLAMA_PORT=11434
OPENWEBUI_PORT=3000
NODE_A_DASHBOARD_PORT=3099
KVM_OPERATOR_PORT=5000
OPENCLAW_PORT=18789
DEPLOY_GUI_PORT=9999

# ── External Access ───────────────────────────────────────────────────────────
CLOUDFLARE_DOMAIN=happystrugglebus.us

# ── API Tokens ────────────────────────────────────────────────────────────────
LITELLM_API_KEY=${LITELLM_API_KEY}
KVM_OPERATOR_TOKEN=${KVM_OPERATOR_TOKEN}
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
PORTAINER_TOKEN=

# ── Portainer Edition ─────────────────────────────────────────────────────────
PORTAINER_EDITION=CE

# ── Docker Swarm ──────────────────────────────────────────────────────────────
SWARM_MANAGER_NODE=NODE_B
SWARM_WORKER_TOKEN=
SWARM_MANAGER_TOKEN="

# ── kvm-operator/.env ─────────────────────────────────────────────────────────
write_env_file "${REPO_ROOT}/kvm-operator/.env" \
"# KVM Operator — generated by scripts/setup-env.sh
# Runs on Node A (${NODE_A_IP}), port 5000.

KVM_OPERATOR_TOKEN=${KVM_OPERATOR_TOKEN}
REQUIRE_APPROVAL=true

# Node map (target name -> NanoKVM IP)
KVM_TARGETS_JSON={\"kvm-d829\":\"${KVM_IP}\"}
NANOKVM_USERNAME=${NANOKVM_USERNAME}
NANOKVM_PASSWORD=${NANOKVM_PASSWORD}

# Route model-assisted operations via LiteLLM
LITELLM_URL=http://${NODE_B_IP}:4000/v1/chat/completions
LITELLM_API_KEY=${LITELLM_API_KEY}"

# ── node-a-vllm/.env ──────────────────────────────────────────────────────────
write_env_file "${REPO_ROOT}/node-a-vllm/.env" \
"# Node A vLLM — generated by scripts/setup-env.sh

HUGGINGFACE_TOKEN=${HUGGINGFACE_TOKEN}
VLLM_MODEL=${VLLM_MODEL_A}"

# ── node-a-command-center/.env ────────────────────────────────────────────────
write_env_file "${REPO_ROOT}/node-a-command-center/.env" \
"# Node A Command Center — generated by scripts/setup-env.sh

COMMAND_CENTER_PORT=3099
LITELLM_BASE_URL=http://${NODE_B_IP}:4000
LITELLM_API_KEY=${LITELLM_API_KEY}
DEFAULT_MODEL=brain-heavy
BRAIN_BASE_URL=http://${NODE_A_IP}:8000
NODE_C_BASE_URL=http://${NODE_C_IP}
NODE_D_BASE_URL=http://${NODE_D_IP}:8123
NODE_E_BASE_URL=http://${NODE_E_IP}:3005
UPTIME_KUMA_BASE_URL=http://${NODE_B_IP}:3010
DOZZLE_BASE_URL=http://${NODE_B_IP}:8888
HOMEPAGE_BASE_URL=http://${NODE_B_IP}:8010"

# ── node-b-litellm/stacks/.env ────────────────────────────────────────────────
write_env_file "${REPO_ROOT}/node-b-litellm/stacks/.env" \
"# Node B LiteLLM stacks — generated by scripts/setup-env.sh
# Copy this file to Node B: scp node-b-litellm/stacks/.env ${NODE_B_SSH_USER}@${NODE_B_IP}:/mnt/user/appdata/homelab/node-b-litellm/stacks/.env

TZ=${TZ}
PUID=1000
PGID=1000
APPDATA_PATH=/mnt/user/appdata
MEDIA_PATH=/mnt/user/data

LITELLM_MASTER_KEY=${LITELLM_API_KEY}

VPN_SERVICE_PROVIDER=${VPN_SERVICE_PROVIDER}
VPN_USER=${VPN_USER}
VPN_PASSWORD=${VPN_PASSWORD}
VPN_REGIONS=US East

SEARXNG_SECRET_KEY=${SEARXNG_SECRET_KEY}
BROWSERLESS_TOKEN=your-secret-token

TEI_MODEL_ID=BAAI/bge-small-en-v1.5

VLLM_MODEL=${VLLM_MODEL_B}
VLLM_MAX_CTX=8192
VLLM_GPU_MEM=0.90
HUGGING_FACE_HUB_TOKEN=${HUGGINGFACE_TOKEN}

NEXTCLOUD_DB_ROOT_PASSWORD=${NEXTCLOUD_DB_ROOT_PASSWORD}
NEXTCLOUD_DB_PASSWORD=${NEXTCLOUD_DB_PASSWORD}

TAUTULLI_API_KEY=your-tautulli-api-key

OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}

CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}"

# ── node-c-arc/.env.openclaw ──────────────────────────────────────────────────
write_env_file "${REPO_ROOT}/node-c-arc/.env.openclaw" \
"# OpenClaw Node C — generated by scripts/setup-env.sh
# Usage: docker compose -f node-c-arc/openclaw.yml --env-file node-c-arc/.env.openclaw up -d

OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
OLLAMA_API_KEY=ollama
LITELLM_API_KEY=${LITELLM_API_KEY}
KVM_OPERATOR_URL=http://${NODE_A_IP}:5000
KVM_OPERATOR_TOKEN=${KVM_OPERATOR_TOKEN}"

# ── node-d-home-assistant/.env ────────────────────────────────────────────────
write_env_file "${REPO_ROOT}/node-d-home-assistant/.env" \
"# Node D Home Assistant — generated by scripts/setup-env.sh
# Copy this file to Node D: scp node-d-home-assistant/.env ${NODE_D_SSH_USER}@${NODE_D_IP}:~/homelab/node-d-home-assistant/.env

TZ=${TZ}
LITELLM_BASE_URL=http://${NODE_B_IP}:4000
LITELLM_API_KEY=${LITELLM_API_KEY}
NODE_A_BASE_URL=http://${NODE_A_IP}:8000"

# ── unraid/.env ───────────────────────────────────────────────────────────────
write_env_file "${REPO_ROOT}/unraid/.env" \
"# Unraid management stack — generated by scripts/setup-env.sh
# Copy this file to Node B: scp unraid/.env ${NODE_B_SSH_USER}@${NODE_B_IP}:/mnt/user/appdata/homelab/unraid/.env

TAILSCALE_AUTHKEY=${TAILSCALE_AUTHKEY}
LOCAL_SUBNET=192.168.1.0/24
APPDATA_PATH=/mnt/user/appdata
TZ=${TZ}
HA_LONG_LIVED_TOKEN=${HA_LONG_LIVED_TOKEN}"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   All done!  Summary of generated files                ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}LOCAL (Node A — stay here):${NC}"
echo -e "    config/node-inventory.env"
echo -e "    kvm-operator/.env"
echo -e "    node-a-vllm/.env"
echo -e "    node-a-command-center/.env"
echo ""
echo -e "  ${YELLOW}COPY TO Node B (Tailscale: ${NODE_B_TS_IP:-$NODE_B_IP}):${NC}"
echo -e "    scp node-b-litellm/stacks/.env ${NODE_B_SSH_USER}@${NODE_B_TS_IP:-$NODE_B_IP}:/mnt/user/appdata/homelab/node-b-litellm/stacks/.env"
echo -e "    scp unraid/.env                ${NODE_B_SSH_USER}@${NODE_B_TS_IP:-$NODE_B_IP}:/mnt/user/appdata/homelab/unraid/.env"
echo ""
echo -e "  ${YELLOW}COPY TO Node C (Tailscale: ${NODE_C_TS_IP:-$NODE_C_IP}):${NC}"
echo -e "    scp node-c-arc/.env.openclaw   ${NODE_C_SSH_USER}@${NODE_C_TS_IP:-$NODE_C_IP}:/opt/openclaw/.env"
echo ""
echo -e "  ${YELLOW}COPY TO Node D (Tailscale: ${NODE_D_TS_IP:-$NODE_D_IP}):${NC}"
echo -e "    scp node-d-home-assistant/.env ${NODE_D_SSH_USER}@${NODE_D_TS_IP:-$NODE_D_IP}:~/homelab/node-d-home-assistant/.env"
echo ""
echo -e "  ${CYAN}Next steps:${NC}"
echo -e "    1. Review each .env file and adjust any remaining placeholder values."
echo -e "    2. Ensure Tailscale is running on all nodes (run 'tailscale status' on each node to verify)."
echo -e "    3. Then deploy everything:"
echo -e "         ./scripts/deploy-all.sh"
echo ""
echo -e "  ${DIM}Tip: Never commit .env files — they are already in .gitignore.${NC}"
echo ""
