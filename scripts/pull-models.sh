#!/usr/bin/env bash
# Project Chimera — Ollama Model Installer
# Downloads and installs the recommended AI models for each node.
#
# Usage:
#   ./scripts/pull-models.sh --node a        # Pull models for Node A (Brain)
#   ./scripts/pull-models.sh --node b        # Pull models for Node B (Brawn)
#   ./scripts/pull-models.sh --node c        # Pull models for Node C (Arc)
#   ./scripts/pull-models.sh --all           # Pull models for all three nodes via SSH
#   ./scripts/pull-models.sh                 # Interactive menu
#
# Remote flags (used with --all or --node X):
#   --ssh-user USER   SSH user for remote nodes (default: from node-inventory.env)
#   --dry-run         Print the pull commands without executing them
#
# Model assignments:
#   Node A  AMD RX 7900 XT  20 GB  qwen2.5:32b  +  llava:13b
#   Node B  RTX 4070        12 GB  dolphin-mistral:7b  +  qwen2.5-coder:14b
#   Node C  Intel Arc A770  16 GB  phi4:latest  +  dolphin3:8b

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/lib-inventory.sh"
load_inventory "$REPO_ROOT"

# ── Colour helpers ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1" >&2; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }
step() { echo ""; echo -e "${BOLD}$1${NC}"; echo ""; }
dim()  { echo -e "  ${DIM}$1${NC}"; }

# ── Model table ───────────────────────────────────────────────────────────────
#
# Node A — Brain (AMD RX 7900 XT, 20 GB VRAM, ROCm, port 11435)
#   qwen2.5:32b          — 19.4 GB — best quality thinker; fits comfortably in 20 GB
#   llava:13b            —  8.0 GB — vision-language model for multimodal tasks
#
# Node B — Brawn (NVIDIA RTX 4070, 12 GB VRAM, CUDA, port 11434)
#   dolphin-mistral:7b   —  4.1 GB — uncensored versatile all-rounder
#   qwen2.5-coder:14b    —  8.4 GB — specialised code generation and review
#
# Node C — Arc (Intel Arc A770, 16 GB VRAM, OneAPI/Level Zero, port 11434)
#   phi4:latest          —  9.1 GB — fast, efficient conversational model
#   dolphin3:8b          —  4.9 GB — uncensored, low-latency responses
#
# Embedding model (Node B, shared across the lab via LiteLLM gateway):
#   nomic-embed-text     —  0.3 GB — embeddings for RAG in n8n and OpenWebUI
#

NODE_A_MODELS=("qwen2.5:32b" "llava:13b")
NODE_B_MODELS=("dolphin-mistral:7b" "qwen2.5-coder:14b" "nomic-embed-text")
NODE_C_MODELS=("phi4:latest" "dolphin3:8b")

# Ollama container names per node
CONTAINER_A="ollama_brain"   # node-a-vllm/docker-compose.ollama.yml
CONTAINER_B="ollama"         # nodebfinal stacks / node-b-litellm
CONTAINER_C="ollama_intel_arc" # node-c-arc/docker-compose.yml

# ── Argument parsing ──────────────────────────────────────────────────────────
TARGET_NODE=""
RUN_ALL=false
DRY_RUN=false
SSH_USER_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --node) TARGET_NODE="${2:-}"; shift 2 ;;
    --all)  RUN_ALL=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --ssh-user) SSH_USER_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'HELP'
Usage:
  ./scripts/pull-models.sh --node a        # Pull models for Node A (Brain)
  ./scripts/pull-models.sh --node b        # Pull models for Node B (Brawn)
  ./scripts/pull-models.sh --node c        # Pull models for Node C (Arc)
  ./scripts/pull-models.sh --all           # Pull models for all nodes via SSH
  ./scripts/pull-models.sh                 # Interactive menu

Optional flags:
  --ssh-user USER   SSH user for remote nodes (default: from node-inventory.env)
  --dry-run         Print commands without executing them
HELP
      exit 0
      ;;
    *) warn "Unknown argument: $1"; shift ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
pull_model_local() {
  local container="$1" model="$2"
  if $DRY_RUN; then
    info "[dry-run] docker exec ${container} ollama pull ${model}"
    return
  fi

  # Check Docker daemon is accessible before inspecting containers
  if ! docker info >/dev/null 2>&1; then
    err "Docker daemon is not accessible — is Docker running and do you have permission?"
    return 1
  fi

  if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$container"; then
    warn "Container '${container}' is not running — skipping ${model}"
    warn "  Start it first, then re-run this script."
    return 1
  fi

  info "Pulling ${model} …"
  if docker exec "$container" ollama pull "$model"; then
    ok "${model} ready"
  else
    err "Failed to pull ${model}"
    return 1
  fi
}

pull_models_remote() {
  local node_label="$1" ip="$2" ssh_user="$3" container="$4" port="$5"
  shift 5
  local models=("$@")

  echo ""
  echo -e "${BOLD}  ── ${node_label} (${ip}) ──────────────────────────────────────${NC}"
  echo ""

  for model in "${models[@]}"; do
    local pull_cmd="docker exec ${container} ollama pull ${model}"
    if $DRY_RUN; then
      info "[dry-run] ssh ${ssh_user}@${ip} '${pull_cmd}'"
      continue
    fi
    info "Pulling ${model} on ${node_label} …"
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
         "${ssh_user}@${ip}" "$pull_cmd"; then
      ok "${model} ready on ${node_label}"
    else
      err "Failed to pull ${model} on ${node_label}"
    fi
  done

  # Verify the Ollama API responds
  if ! $DRY_RUN; then
    local api_url="http://${ip}:${port}/api/tags"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$api_url" 2>/dev/null || echo "000")
    if [[ "$code" =~ ^2 ]]; then
      ok "Ollama API healthy on ${node_label} (HTTP ${code})"
    else
      warn "Ollama API not responding on ${node_label} at ${api_url} (HTTP ${code})"
    fi
  fi
}

# ── Node-specific pull functions ──────────────────────────────────────────────
pull_node_a() {
  step "Node A — Brain (AMD RX 7900 XT, 20 GB VRAM)"
  echo "  Models to pull:"
  echo "    qwen2.5:32b       ~19.4 GB  — primary reasoning model"
  echo "    llava:13b         ~ 8.0 GB  — vision-language model"
  echo ""
  echo "  ⚠  First-time pull may take 10–30 minutes depending on bandwidth."
  echo ""

  for model in "${NODE_A_MODELS[@]}"; do
    pull_model_local "$CONTAINER_A" "$model"
  done

  if ! $DRY_RUN; then
    echo ""
    ok "Node A models installed.  Test with:"
    dim "  curl -X POST http://localhost:11435/api/generate \\"
    dim "    -d '{\"model\":\"qwen2.5:32b\",\"prompt\":\"Hello\",\"stream\":false}' | jq .response"
    echo ""
    ok "LiteLLM model aliases:  brain-heavy → qwen2.5:32b  |  brain-vision → llava:13b"
  fi
}

pull_node_b() {
  step "Node B — Brawn (NVIDIA RTX 4070, 12 GB VRAM)"
  echo "  Models to pull:"
  echo "    dolphin-mistral:7b   ~4.1 GB  — uncensored all-rounder (chat + light code)"
  echo "    qwen2.5-coder:14b    ~8.4 GB  — specialised code generation"
  echo "    nomic-embed-text     ~0.3 GB  — embeddings for RAG"
  echo ""

  for model in "${NODE_B_MODELS[@]}"; do
    pull_model_local "$CONTAINER_B" "$model"
  done

  if ! $DRY_RUN; then
    echo ""
    ok "Node B models installed.  LiteLLM model aliases:"
    dim "  brawn-fast    → dolphin-mistral:7b"
    dim "  brawn-code    → qwen2.5-coder:14b"
    dim "  brawn-embed   → nomic-embed-text"
    echo ""
    ok "Test via LiteLLM gateway:"
    dim "  curl -X POST http://localhost:4000/v1/chat/completions \\"
    dim "    -H 'Authorization: Bearer \$LITELLM_MASTER_KEY' \\"
    dim "    -d '{\"model\":\"brawn-fast\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'"
  fi
}

pull_node_c() {
  step "Node C — Arc (Intel Arc A770, 16 GB VRAM)"
  echo "  Models to pull:"
  echo "    phi4:latest    ~9.1 GB  — fast, efficient conversational model"
  echo "    dolphin3:8b    ~4.9 GB  — uncensored, low-latency responses"
  echo ""
  echo "  Note: Intel Arc uses the OneAPI/Level Zero driver stack (not ROCm or CUDA)."
  echo "        Ensure ZES_ENABLE_SYSMAN=1 is set in your docker-compose environment."
  echo ""

  for model in "${NODE_C_MODELS[@]}"; do
    pull_model_local "$CONTAINER_C" "$model"
  done

  if ! $DRY_RUN; then
    echo ""
    ok "Node C models installed.  LiteLLM model aliases:"
    dim "  intel-fast    → phi4:latest"
    dim "  intel-vision  → llava (existing)"
    dim "  intel-uncensored → dolphin3:8b"
    echo ""
    ok "Test directly:"
    dim "  curl http://localhost:11434/api/tags | jq '[.models[].name]'"
  fi
}

# ── Interactive menu ───────────────────────────────────────────────────────────
show_menu() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║   Project Chimera — Ollama Model Installer                  ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Which node are you deploying on?"
  echo ""
  echo "  [a]  Node A — Brain  (AMD RX 7900 XT, 20 GB)"
  echo "         • qwen2.5:32b   (reasoning)"
  echo "         • llava:13b     (vision)"
  echo ""
  echo "  [b]  Node B — Brawn  (NVIDIA RTX 4070, 12 GB)"
  echo "         • dolphin-mistral:7b   (uncensored chat)"
  echo "         • qwen2.5-coder:14b    (code)"
  echo "         • nomic-embed-text     (embeddings)"
  echo ""
  echo "  [c]  Node C — Arc    (Intel Arc A770, 16 GB)"
  echo "         • phi4:latest   (fast conversation)"
  echo "         • dolphin3:8b   (uncensored)"
  echo ""
  echo "  [q]  Quit"
  echo ""
  printf "  Choice: "
  local choice
  IFS= read -r choice 2>/dev/null || choice="q"
  echo "$choice"
}

# ── Main ──────────────────────────────────────────────────────────────────────

print_banner() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║   Project Chimera — Ollama Model Installer                  ║"
  echo "║                                                              ║"
  echo "║   Pulls the best optimised uncensored models for each       ║"
  echo "║   node based on GPU type and VRAM capacity.                 ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
}

if $RUN_ALL; then
  print_banner
  echo ""
  info "Running in --all mode: pulling models on all three nodes via SSH"
  echo ""

  SSH_A="${SSH_USER_OVERRIDE:-${NODE_A_SSH_USER:-root}}"
  SSH_B="${SSH_USER_OVERRIDE:-${NODE_B_SSH_USER:-root}}"
  SSH_C="${SSH_USER_OVERRIDE:-${NODE_C_SSH_USER:-root}}"

  pull_models_remote "Node A (Brain)" "$NODE_A_IP" "$SSH_A" "$CONTAINER_A" "11435" "${NODE_A_MODELS[@]}"
  pull_models_remote "Node B (Brawn)" "$NODE_B_IP" "$SSH_B" "$CONTAINER_B" "11434" "${NODE_B_MODELS[@]}"
  pull_models_remote "Node C (Arc)"   "$NODE_C_IP" "$SSH_C" "$CONTAINER_C" "11434" "${NODE_C_MODELS[@]}"

  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo -e "  ${GREEN}All models pulled across the cluster!${NC}"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo "  Next steps:"
  echo "  1. Update nodebfinal/litellm-config.yaml (see docs/25_MODEL_SELECTION_GUIDE.md)"
  echo "  2. Restart the LiteLLM container:  docker restart litellm"
  echo "  3. Verify routing:  curl http://192.168.1.222:4000/v1/models"
  echo ""
  exit 0
fi

if [ -n "$TARGET_NODE" ]; then
  print_banner
  case "${TARGET_NODE,,}" in
    a|brain)   pull_node_a ;;
    b|brawn)   pull_node_b ;;
    c|arc)     pull_node_c ;;
    *)
      err "Unknown node '${TARGET_NODE}'. Use --node a, --node b, or --node c."
      exit 1
      ;;
  esac
  exit 0
fi

# Interactive fallback
print_banner
while true; do
  choice=$(show_menu)
  case "${choice,,}" in
    a) pull_node_a; break ;;
    b) pull_node_b; break ;;
    c) pull_node_c; break ;;
    q|"") echo ""; info "Exiting."; exit 0 ;;
    *) warn "Invalid choice '${choice}' — enter a, b, c, or q." ;;
  esac
done

echo ""
echo "  ─────────────────────────────────────────────────────────────"
echo "  See docs/25_MODEL_SELECTION_GUIDE.md for:"
echo "    • LiteLLM gateway config updates"
echo "    • VRAM budgets and model size reference"
echo "    • Troubleshooting Intel Arc / ROCm / CUDA model loading"
echo "  ─────────────────────────────────────────────────────────────"
echo ""
