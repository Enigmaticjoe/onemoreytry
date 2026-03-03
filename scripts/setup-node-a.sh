#!/usr/bin/env bash
# Grand Unified AI Home Lab — Node A Setup Script
# Configures ROCm for the AMD RX 7900 XT and deploys the Brain Project stack.
#
# Hardware: Intel i9-265F, 128 GB RAM, AMD RX 7900 XT (20 GB)
# IP:       192.168.1.9
#
# Brain Project services (all started by this script):
#   vLLM (8000), OpenWebUI (3000), Qdrant (6333), Embeddings (8001),
#   SearXNG (8888), Coding Agent (8899), Hardware Agent (8090), Dashboard (8080)
#
# Usage:
#   ./scripts/setup-node-a.sh              # full ROCm install + Brain Project deploy
#   ./scripts/setup-node-a.sh --no-deploy  # install ROCm only, skip compose up
#   ./scripts/setup-node-a.sh --status     # check GPU and service health

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
source "${REPO_ROOT}/scripts/lib-inventory.sh"
load_inventory "$REPO_ROOT"

NO_DEPLOY=false
STATUS_ONLY=false
for arg in "$@"; do
  [[ "$arg" == "--no-deploy" ]] && NO_DEPLOY=true
  [[ "$arg" == "--status" ]]    && STATUS_ONLY=true
done

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }
step() { echo ""; echo -e "${BOLD}$1${NC}"; echo ""; }

# ── Status check ──────────────────────────────────────────────────────────────
if [ "$STATUS_ONLY" = true ]; then
  echo ""
  echo "Brain Project status (${NODE_A_IP:-192.168.1.9})"
  echo ""

  # GPU visibility
  if command -v rocminfo &>/dev/null; then
    GPU_NAME=$(rocminfo 2>/dev/null | grep -i "Marketing Name" | head -1 | awk -F': ' '{print $2}' || true)
    if [ -n "$GPU_NAME" ]; then
      ok "ROCm GPU: ${GPU_NAME}"
    else
      warn "rocminfo found no GPU — check /dev/kfd permissions"
    fi
  else
    warn "rocminfo not found — ROCm may not be installed"
  fi

  if [ -e /dev/kfd ]; then
    ok "/dev/kfd present"
  else
    err "/dev/kfd missing — ROCm kernel module not loaded"
  fi

  # Docker container status
  if command -v docker &>/dev/null; then
    for svc in brain-vllm brain-qdrant brain-embeddings brain-searxng brain-openwebui brain-coding-agent brain-hardware-agent brain-dashboard; do
      if docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null | grep -q "^${svc} "; then
        STATUS=$(docker ps --format '{{.Status}}' --filter "name=^${svc}$" 2>/dev/null || echo "unknown")
        ok "Container ${svc}: ${STATUS}"
      else
        warn "Container ${svc} is not running"
      fi
    done
  fi

  # HTTP health checks
  NODE_A="${NODE_A_IP:-192.168.1.9}"
  for label_url in \
    "vLLM API|http://${NODE_A}:8000/health" \
    "OpenWebUI|http://${NODE_A}:3000/health" \
    "Qdrant|http://${NODE_A}:6333/healthz" \
    "Embeddings|http://${NODE_A}:8001/health" \
    "SearXNG|http://${NODE_A}:8888/healthz" \
    "Coding Agent|http://${NODE_A}:8899/api" \
    "Hardware Agent|http://${NODE_A}:8090/health" \
    "Dashboard|http://${NODE_A}:8080/api/healthcheck"; do
    label="${label_url%%|*}"
    url="${label_url##*|}"
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    if [[ "$code" =~ ^2 ]]; then
      ok "${label} healthy (HTTP ${code})"
    elif [ "$code" = "000" ]; then
      warn "${label} not reachable at ${url}"
    else
      warn "${label} returned HTTP ${code}"
    fi
  done

  exit 0
fi

# ── Main flow ─────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Node A — Brain Project Setup (AMD RX 7900 XT)         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Node A IP  : ${NODE_A_IP:-192.168.1.9}"
echo "  GPU        : AMD RX 7900 XT (gfx1100 / RDNA 3, 20 GB)"
echo "  Model      : dolphin-2.9.3-llama-3.1-8b (AWQ)"
echo "  Stack dir  : node-a-vllm/"
echo ""

ERRORS=0

# ── Step 1: Prerequisites ─────────────────────────────────────────────────────
step "Step 1 — Verify prerequisites"

if [ "$(id -u)" -ne 0 ]; then
  warn "Not running as root — will use sudo for system-level steps"
  SUDO="sudo"
else
  SUDO=""
fi

# OS detection
if [ -f /etc/os-release ]; then
  # shellcheck source=/dev/null
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_VER="${VERSION_ID:-}"
  ok "OS: ${PRETTY_NAME:-${OS_ID} ${OS_VER}}"
else
  warn "Could not detect OS — /etc/os-release not found"
  OS_ID="unknown"
fi

# Docker
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  ok "Docker is running ($(docker --version | cut -d' ' -f3 | tr -d ','))"
elif command -v docker &>/dev/null && sudo docker info &>/dev/null 2>&1; then
  warn "Docker requires sudo — consider: sudo usermod -aG docker \$USER && newgrp docker"
  SUDO="sudo"
  ok "Docker is running via sudo"
else
  err "Docker is not running — install it first:"
  info "  Fedora:  sudo dnf install docker -y && sudo systemctl enable --now docker"
  info "  Ubuntu:  https://docs.docker.com/engine/install/ubuntu/"
  exit 1
fi

# Docker Compose
if docker compose version &>/dev/null 2>&1 || $SUDO docker compose version &>/dev/null 2>&1; then
  ok "Docker Compose plugin available"
else
  err "Docker Compose not found — install the compose plugin"
  exit 1
fi

# curl
if command -v curl &>/dev/null; then
  ok "curl available"
else
  err "curl not found"
  info "  Fedora: sudo dnf install curl -y"
  exit 1
fi

# ── Step 2: ROCm installation ─────────────────────────────────────────────────
step "Step 2 — ROCm installation for RX 7900 XT"

ROCM_ALREADY=false
if command -v rocminfo &>/dev/null; then
  ROCM_VER=$(rocminfo 2>/dev/null | grep -i "ROCm" | head -1 || true)
  ok "ROCm is already installed${ROCM_VER:+: ${ROCM_VER}}"
  ROCM_ALREADY=true
fi

if [ -e /dev/kfd ]; then
  ok "/dev/kfd exists (ROCm KFD driver loaded)"
else
  warn "/dev/kfd missing — ROCm kernel module may not be loaded"
  if [ "$ROCM_ALREADY" = false ]; then
    info "Installing ROCm..."
    case "$OS_ID" in
      fedora)
        info "Fedora: installing ROCm via AMDGPU installer"
        $SUDO dnf install -y 'dnf-command(config-manager)' 2>/dev/null || true
        # Add the AMD ROCm repo
        $SUDO tee /etc/yum.repos.d/rocm.repo > /dev/null <<'REPO'
[ROCm]
name=ROCm
baseurl=https://repo.radeon.com/rocm/rhel9/latest/main
enabled=1
gpgcheck=1
gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key
REPO
        $SUDO dnf install -y rocm-hip-sdk rocm-opencl-sdk rocminfo 2>&1 | tail -5
        ;;
      ubuntu|debian)
        info "Ubuntu/Debian: installing ROCm via apt"
        $SUDO apt-get update -qq
        $SUDO apt-get install -y wget gnupg
        wget -q -O /tmp/amdgpu-install.deb \
          "https://repo.radeon.com/amdgpu-install/6.1.3/ubuntu/jammy/amdgpu-install_6.1.60103-1_all.deb"
        $SUDO apt-get install -y /tmp/amdgpu-install.deb
        $SUDO amdgpu-install --usecase=rocm --no-dkms -y 2>&1 | tail -5
        ;;
      *)
        warn "Unsupported OS '${OS_ID}' — skipping automated ROCm install"
        info "Manual ROCm install: https://rocm.docs.amd.com/projects/install-on-linux/en/latest/"
        ;;
    esac
  fi
fi

# Ensure current user is in the render/video groups (needed for /dev/kfd + /dev/dri)
CURRENT_USER="${SUDO_USER:-$(whoami)}"
for grp in render video; do
  if getent group "$grp" &>/dev/null; then
    if id -nG "$CURRENT_USER" 2>/dev/null | grep -qw "$grp"; then
      ok "User '${CURRENT_USER}' is in group '${grp}'"
    else
      $SUDO usermod -aG "$grp" "$CURRENT_USER" 2>/dev/null && \
        warn "Added '${CURRENT_USER}' to group '${grp}' — log out and back in (or run: newgrp ${grp})" || \
        warn "Could not add '${CURRENT_USER}' to group '${grp}' — run: sudo usermod -aG ${grp} ${CURRENT_USER}"
    fi
  fi
done

# Verify GPU is visible to ROCm
if command -v rocminfo &>/dev/null; then
  GPU_LINE=$(rocminfo 2>/dev/null | grep -i "Marketing Name" | head -1 || true)
  if [ -n "$GPU_LINE" ]; then
    GPU_NAME=$(echo "$GPU_LINE" | awk -F': ' '{print $2}')
    ok "ROCm sees GPU: ${GPU_NAME}"
  else
    warn "ROCm installed but no GPU detected — check /dev/kfd permissions and driver load"
    info "  Try: sudo modprobe amdgpu && ls -la /dev/kfd /dev/dri/render*"
  fi
fi

# ── Step 3: Prepare .env file ─────────────────────────────────────────────────
step "Step 3 — Prepare node-a-vllm/.env"

if [ -f "node-a-vllm/.env" ]; then
  ok "node-a-vllm/.env already exists — using existing file"
elif [ -f "node-a-vllm/.env.example" ]; then
  cp node-a-vllm/.env.example node-a-vllm/.env
  ok "Created node-a-vllm/.env from .env.example"

  # Auto-generate secrets
  if command -v openssl &>/dev/null; then
    WEBUI_SECRET=$(openssl rand -hex 32)
    SEARXNG_SECRET=$(openssl rand -hex 32)
    JUPYTER_TOKEN=$(openssl rand -hex 16)
    sed -i "s|^WEBUI_SECRET_KEY=.*|WEBUI_SECRET_KEY=${WEBUI_SECRET}|" node-a-vllm/.env
    sed -i "s|^SEARXNG_SECRET=.*|SEARXNG_SECRET=${SEARXNG_SECRET}|" node-a-vllm/.env
    sed -i "s|^JUPYTER_TOKEN=.*|JUPYTER_TOKEN=${JUPYTER_TOKEN}|" node-a-vllm/.env
    ok "Auto-generated WEBUI_SECRET_KEY, SEARXNG_SECRET, JUPYTER_TOKEN"
  fi

  warn "Set HUGGING_FACE_HUB_TOKEN in node-a-vllm/.env before deploying"
  info "  Get a token: https://huggingface.co/settings/tokens"
  info "  Edit: \$EDITOR node-a-vllm/.env"
else
  err "node-a-vllm/.env.example not found"
  exit 1
fi

# Source the .env so the compose command inherits the values
set -o allexport
# shellcheck source=/dev/null
source node-a-vllm/.env 2>/dev/null || true
set +o allexport

info "Model: cognitivecomputations/dolphin-2.9.3-llama-3.1-8b-AWQ"

# Rough VRAM check
VRAM_MB=0
if command -v rocm-smi &>/dev/null; then
  VRAM_MB=$(rocm-smi --showmeminfo vram 2>/dev/null | grep "VRAM Total" | awk '{print $NF}' | head -1 || echo "0")
fi
if [ "$VRAM_MB" -gt 0 ] 2>/dev/null; then
  VRAM_GB=$(( VRAM_MB / 1024 ))
  ok "GPU VRAM: ${VRAM_GB} GB (${VRAM_MB} MB)"
  if [ "$VRAM_GB" -lt 10 ]; then
    warn "Less than 10 GB VRAM detected — the selected model may not fit"
  fi
fi

# ── Step 4: Pull Brain Project images ─────────────────────────────────────────
step "Step 4 — Pull Brain Project Docker images"

info "Pulling all Brain Project images (this may take several minutes on first run)..."
$SUDO docker compose -f node-a-vllm/docker-compose.yml pull 2>&1 | tail -10
ok "Images ready"

# ── Step 5: Deploy ────────────────────────────────────────────────────────────
step "Step 5 — Deploy Brain Project"

if [ "$NO_DEPLOY" = true ]; then
  echo ""
  echo "  --no-deploy flag set. To deploy manually:"
  echo ""
  echo "    cd ${REPO_ROOT}/node-a-vllm"
  echo "    docker compose up -d"
  echo ""
else
  info "Starting Brain Project containers..."
  $SUDO docker compose -f node-a-vllm/docker-compose.yml up -d
  ok "Brain Project containers started"

  info "Waiting for vLLM to load the model (can take 3-5 min on first run)..."
  MAX_RETRIES=20
  RETRY=0
  DELAY=15
  while [ $RETRY -lt $MAX_RETRIES ]; do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
           "http://localhost:8000/health" 2>/dev/null || echo "000")
    if [[ "$code" =~ ^2 ]]; then
      ok "vLLM is healthy (HTTP ${code})"
      break
    fi
    RETRY=$((RETRY + 1))
    info "  Attempt ${RETRY}/${MAX_RETRIES} — HTTP ${code}, waiting ${DELAY}s..."
    sleep "$DELAY"
  done

  if [ $RETRY -ge $MAX_RETRIES ]; then
    warn "vLLM did not respond in time — it may still be downloading the model"
    info "  Check logs: docker logs brain-vllm --tail 30 -f"
    info "  Health:     curl http://localhost:8000/health"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "  ${GREEN}Node A — Brain Project setup complete!${NC}"
echo "═══════════════════════════════════════════════════════════════"
echo ""
NODE_A="${NODE_A_IP:-192.168.1.9}"
echo "  Service        URL"
echo "  ─────────────────────────────────────────────────────────"
echo "  vLLM API       http://${NODE_A}:8000/v1"
echo "  OpenWebUI      http://${NODE_A}:3000"
echo "  Qdrant         http://${NODE_A}:6333/dashboard"
echo "  Embeddings     http://${NODE_A}:8001/health"
echo "  SearXNG        http://${NODE_A}:8888"
echo "  Coding Agent   http://${NODE_A}:8899"
echo "  Hardware Agent http://${NODE_A}:8090/status"
echo "  Dashboard      http://${NODE_A}:8080"
echo ""
echo "  Model alias:  brain-heavy → dolphin-2.9.3-llama-3.1-8b"
echo ""
echo "  Quick test:"
echo "    curl http://\${NODE_A}:8000/health"
echo ""
echo "  Container logs:"
echo "    docker logs brain-vllm --tail 30 -f"
echo ""
echo "  Re-check status at any time:"
echo "    ./scripts/setup-node-a.sh --status"
echo ""
echo "  Full docs: docs/03_DEPLOY_NODE_A_BRAIN.md"
echo ""
