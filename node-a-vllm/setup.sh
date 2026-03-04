#!/usr/bin/env bash
# Brain Project — Node A Setup Script
# Bootstraps the Brain Project AI stack on an AMD RX 7900 XT system.
#
# Hardware: AMD Radeon RX 7900 XT (20GB) | Intel i9-265F | 128GB RAM
# IP:       192.168.1.9
#
# Usage:
#   ./setup.sh              # full setup + deploy
#   ./setup.sh --no-deploy  # prepare environment only, skip compose up
#   ./setup.sh --status     # check GPU and service health without changes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NO_DEPLOY=false
STATUS_ONLY=false
for arg in "$@"; do
  [[ "$arg" == "--no-deploy" ]] && NO_DEPLOY=true
  [[ "$arg" == "--status" ]]    && STATUS_ONLY=true
done

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1" >&2; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }
step() { echo ""; echo -e "${BOLD}$1${NC}"; echo ""; }

# ── Status check ──────────────────────────────────────────────────────────────
if [ "$STATUS_ONLY" = true ]; then
  echo ""
  echo "Brain Project status (192.168.1.9)"
  echo ""

  if command -v rocminfo &>/dev/null; then
    GPU_NAME=$(rocminfo 2>/dev/null | grep -i "Marketing Name" | head -1 | awk -F': ' '{print $2}' || true)
    [ -n "$GPU_NAME" ] && ok "ROCm GPU: ${GPU_NAME}" || warn "rocminfo found no GPU — check /dev/kfd permissions"
  else
    warn "rocminfo not found — ROCm may not be installed"
  fi

  [ -e /dev/kfd ] && ok "/dev/kfd present" || err "/dev/kfd missing — ROCm kernel module not loaded"

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

  for label_url in \
    "vLLM API|http://localhost:8000/health" \
    "OpenWebUI|http://localhost:3000/health" \
    "Qdrant|http://localhost:6333/healthz" \
    "Embeddings|http://localhost:8001/health" \
    "SearXNG|http://localhost:8888/healthz" \
    "Coding Agent|http://localhost:8899/api" \
    "Hardware Agent|http://localhost:8090/health" \
    "Dashboard|http://localhost:8080/api/healthcheck"; do
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

# ── Main setup ────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Brain Project — Node A Setup (AMD RX 7900 XT)             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
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

if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  ok "OS: ${PRETTY_NAME:-${OS_ID}}"
else
  warn "Could not detect OS"
  OS_ID="unknown"
fi

check_docker() {
  if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    return 0
  elif command -v docker &>/dev/null && sudo docker info &>/dev/null 2>&1; then
    SUDO="sudo"
    return 0
  fi
  return 1
}

if check_docker; then
  if [ "$SUDO" = "sudo" ]; then
    warn "Docker requires sudo — consider: sudo usermod -aG docker \$USER && newgrp docker"
    ok "Docker is running via sudo"
  else
    ok "Docker is running"
  fi
else
  warn "Docker not found or not running — attempting automatic install"
  case "${OS_ID:-unknown}" in
    fedora)
      info "Installing Docker CE on Fedora..."
      $SUDO dnf -y install dnf-plugins-core
      $SUDO dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
      $SUDO dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      $SUDO systemctl enable --now docker
      ;;
    ubuntu|debian)
      info "Installing Docker CE on ${OS_ID}..."
      $SUDO apt-get update -qq
      $SUDO apt-get install -y ca-certificates curl gnupg
      $SUDO install -m 0755 -d /etc/apt/keyrings
      curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" \
        | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${OS_ID} $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
      $SUDO apt-get update -qq
      $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      $SUDO systemctl enable --now docker
      ;;
    *)
      err "Docker is not running — install it first (see https://docs.docker.com/engine/install/)"
      exit 1
      ;;
  esac
  if check_docker; then
    ok "Docker installed and running${SUDO:+ (via sudo)}"
  else
    err "Docker installation failed — see https://docs.docker.com/engine/install/"
    exit 1
  fi
fi

if docker compose version &>/dev/null 2>&1 || $SUDO docker compose version &>/dev/null 2>&1; then
  ok "Docker Compose plugin available"
else
  err "Docker Compose not found"
  exit 1
fi

command -v curl &>/dev/null && ok "curl available" || { err "curl not found"; exit 1; }

# ── Step 2: ROCm check ────────────────────────────────────────────────────────
step "Step 2 — Check ROCm for RX 7900 XT"

if command -v rocminfo &>/dev/null; then
  GPU_LINE=$(rocminfo 2>/dev/null | grep -i "Marketing Name" | head -1 || true)
  [ -n "$GPU_LINE" ] && ok "ROCm sees GPU: $(echo "$GPU_LINE" | awk -F': ' '{print $2}')" || \
    warn "ROCm installed but no GPU detected — check /dev/kfd permissions"
else
  warn "ROCm tools not found on host — GPU will still be accessed by vLLM container via /dev/kfd"
fi

[ -e /dev/kfd ] && ok "/dev/kfd present" || warn "/dev/kfd missing — ROCm kernel module may not be loaded; see docs/03_DEPLOY_NODE_A_BRAIN.md §1"

CURRENT_USER="${SUDO_USER:-$(whoami)}"
for grp in render video; do
  if getent group "$grp" &>/dev/null; then
    if id -nG "$CURRENT_USER" 2>/dev/null | grep -qw "$grp"; then
      ok "User '${CURRENT_USER}' is in group '${grp}'"
    else
      $SUDO usermod -aG "$grp" "$CURRENT_USER" 2>/dev/null && \
        warn "Added '${CURRENT_USER}' to group '${grp}' — log out and back in (or: newgrp ${grp})" || \
        warn "Could not add to group '${grp}' — run: sudo usermod -aG ${grp} ${CURRENT_USER}"
    fi
  fi
done

# ── Step 3: Prepare .env file ─────────────────────────────────────────────────
step "Step 3 — Prepare .env"

if [ -f ".env" ]; then
  ok ".env already exists — using existing file"
else
  cp .env.example .env
  ok "Created .env from .env.example"

  # Auto-generate secrets if they're still placeholder values
  if command -v openssl &>/dev/null; then
    WEBUI_SECRET=$(openssl rand -hex 32)
    SEARXNG_SECRET=$(openssl rand -hex 32)
    JUPYTER_TOKEN=$(openssl rand -hex 16)
    sed -i "s|^WEBUI_SECRET_KEY=.*|WEBUI_SECRET_KEY=${WEBUI_SECRET}|" .env
    sed -i "s|^SEARXNG_SECRET=.*|SEARXNG_SECRET=${SEARXNG_SECRET}|" .env
    sed -i "s|^JUPYTER_TOKEN=.*|JUPYTER_TOKEN=${JUPYTER_TOKEN}|" .env
    ok "Auto-generated WEBUI_SECRET_KEY, SEARXNG_SECRET, JUPYTER_TOKEN"
  fi

  warn "Set HUGGING_FACE_HUB_TOKEN in .env before deploying (required to download the model)"
  info "  Edit: \$EDITOR .env"
fi

# Validate HuggingFace token is set
if grep -q "^HUGGING_FACE_HUB_TOKEN=hf_your_token_here" .env 2>/dev/null; then
  warn "HUGGING_FACE_HUB_TOKEN is still set to placeholder — vLLM will fail to download the model"
  warn "  Get a token at https://huggingface.co/settings/tokens and update .env"
fi

# ── Step 4: Pull Docker images ────────────────────────────────────────────────
step "Step 4 — Pull Docker images"

info "Pulling all Brain Project images (this may take several minutes on first run)..."
$SUDO docker compose pull 2>&1 | tail -10
ok "Images ready"

# ── Step 5: Deploy ────────────────────────────────────────────────────────────
step "Step 5 — Deploy Brain Project"

if [ "$NO_DEPLOY" = true ]; then
  echo ""
  echo "  --no-deploy flag set. To deploy manually:"
  echo ""
  echo "    cd ${SCRIPT_DIR}"
  echo "    docker compose up -d"
  echo ""
else
  info "Starting Brain Project containers..."
  $SUDO docker compose up -d
  ok "Containers started"

  echo ""
  info "Waiting for vLLM to load the model (can take 3–5 min on first run)..."
  MAX_RETRIES=20
  RETRY=0
  DELAY=15
  while [ $RETRY -lt $MAX_RETRIES ]; do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://localhost:8000/health" 2>/dev/null || echo "000")
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
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "  ${GREEN}Brain Project — Node A setup complete!${NC}"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Service        URL"
echo "  ─────────────────────────────────────────────────────────"
echo "  vLLM API       http://192.168.1.9:8000/v1"
echo "  OpenWebUI      http://192.168.1.9:3000"
echo "  Qdrant         http://192.168.1.9:6333/dashboard"
echo "  Embeddings     http://192.168.1.9:8001/health"
echo "  SearXNG        http://192.168.1.9:8888"
echo "  Coding Agent   http://192.168.1.9:8899  (token in .env: JUPYTER_TOKEN)"
echo "  Hardware Agent http://192.168.1.9:8090/status"
echo "  Dashboard      http://192.168.1.9:8080"
echo "  Command Center http://192.168.1.9:3099"
echo ""
echo "  Quick test:"
echo "    curl http://192.168.1.9:8000/health"
echo ""
echo "  LiteLLM model alias: brain-heavy → dolphin-2.9.3-llama-3.1-8b"
echo ""
