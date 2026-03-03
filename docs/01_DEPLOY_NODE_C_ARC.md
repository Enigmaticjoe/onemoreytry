# Deploy Node C — Intel Arc A770 on Fedora 44

Node C is the **vision and fast-chat** node of the home lab — an Intel Arc A770 GPU running
Ollama with the chimera_face (Open WebUI) chat interface.

| Item | Value |
|------|-------|
| Role | Vision AI, fast local chat, OpenClaw agent gateway |
| IP | `192.168.1.6` |
| GPU | **Intel Arc A770 (16 GB VRAM)** |
| GPU driver | Intel Compute Runtime / Level Zero |
| OS | **Fedora 44** |

> ⚠️ **OOM / offload warning:** The Arc A770 has 16 GB of VRAM. Models larger than ~13 B parameters (fp16) or ~26 B (4-bit) will exceed available VRAM and either OOM-crash or fall back to slow CPU offload. Use `:8b`-`:13b` quantised models for reliable GPU-only inference.

---

## 1 — Host Prerequisites (Fedora 44)

### 1.1 Update system

```bash
sudo dnf update -y
```

### 1.2 Install Intel Compute Runtime and GPU tools

```bash
sudo dnf install -y intel-compute-runtime intel-level-zero intel-gpu-tools
```

### 1.3 Verify GPU is visible

```bash
# Check kernel driver loaded (should show i915 or xe)
sudo dmesg | grep -E "i915|xe" | tail -5

# Verify OpenCL sees the GPU
clinfo | grep "Device Name"
# Expected: Intel(R) Arc(TM) A770 Graphics

# Interactive GPU monitor (press Ctrl+C to exit)
intel_gpu_top
```

### 1.4 Docker

```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo \
  https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
newgrp docker
```

### 1.5 Set required environment variable

```bash
echo 'export ZES_ENABLE_SYSMAN=1' >> ~/.bashrc
source ~/.bashrc
```

`ZES_ENABLE_SYSMAN=1` enables Intel's hardware monitoring interface. Without it, Ollama cannot
read GPU temperature and memory usage. It is also passed into the container via
`docker-compose.yml`.

---

## 2 — Deploy the Node C Stack

### 2.1 Start the stack

```bash
cd ~/homelab/node-c-arc
docker compose up -d
```

This starts:
- **`ollama_intel_arc`** (port 11434) — Ollama model server using the Arc A770 GPU
- **`chimera_face`** (port 3000) — Open WebUI chat interface

### 2.2 Verify

```bash
# Ollama API should return version info
curl -fsS http://127.0.0.1:11434/api/version

# Pull a vision model (required for image analysis)
docker exec ollama_intel_arc ollama pull llava

# Pull a general chat model
docker exec ollama_intel_arc ollama pull llama3.1:8b
```

### 2.3 Open the chat interface

Open `http://192.168.1.6:3000` in your browser. On first visit, create a local account
(stays on your home network).

---

## 3 — Deploy OpenClaw (optional)

OpenClaw is the AI agent gateway on Node C. Deploy it with:

```bash
./scripts/install-openclaw-node-c.sh
```

Or manually — see `node-c-arc/openclaw.yml` and `node-c-arc/.env.openclaw.example`.

OpenClaw will be reachable at `http://192.168.1.6:18789`.

---

## 4 — Port Reference (Node C)

| Port | Service | Notes |
|------|---------|-------|
| **11434** | Ollama API | Models endpoint: `GET /api/tags`, `POST /api/generate` |
| **3000** | Open WebUI (chimera_face) | Chat interface, model selection, image upload |
| **18789** | OpenClaw Gateway | AI agent control UI + OpenAI-compat API |

---

## 5 — Troubleshooting

### GPU not detected by Ollama

```bash
# Check container logs
docker logs ollama_intel_arc --tail 30

# Verify /dev/dri is mapped
ls -la /dev/dri/

# Check ZES_ENABLE_SYSMAN in container
docker exec ollama_intel_arc env | grep ZES
```

### chimera_face shows "Cannot connect to Ollama"

The WebUI connects to Ollama using the Docker service name `ollama` on port 11434 (bridge
network). Verify both containers are on the same network:

```bash
docker network inspect arc-node-c | grep -A3 "ollama\|chimera"
```

If either container is missing from the network, restart the stack:

```bash
docker compose down && docker compose up -d
```

### Model runs slowly / CPU fallback

Run `ollama ps` and check the **Processor** column. If it shows CPU instead of GPU:

1. Check `ZES_ENABLE_SYSMAN=1` is set in the container environment
2. Verify `/dev/dri` is mapped correctly in `docker-compose.yml`
3. Check available VRAM -- models too large for 16 GB will offload to CPU

---

## Before Submitting PRs

Always run the repository validation suite from the repo root before opening a pull request:

```bash
./validate.sh
```

---

## Migration Notes

> **What changed and why** -- for operators upgrading from an earlier version.

| Area | Old behaviour | New behaviour | Action needed |
|---|---|---|---|
| Ollama networking | `network_mode: host` | **Bridge network** (`arc-node-c`) with `ports: 11434:11434` | `docker compose down && docker compose up -d` |
| WebUI to Ollama URL | `http://host.docker.internal:11434` | `http://ollama:11434` (service name, cleaner) | Automatic on redeploy |
| Intel packages | `intel-one-api-mkl`, `intel-opencl` | `intel-compute-runtime intel-level-zero intel-gpu-tools` | `sudo dnf install -y intel-compute-runtime intel-level-zero intel-gpu-tools` |
| IPEX-LLM reference | Mentioned in title | **Removed** -- standard Ollama image is used | None |
