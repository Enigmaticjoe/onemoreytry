# Deploy Node A — Brain Node (AMD RX 7900 XT)

Node A is the **heavy-reasoning brain** of the AI home lab.

| Item | Value |
|------|-------|
| Role | Brain / Deep Thought — heavy logic & reasoning |
| IP | `192.168.1.9` |
| CPU | Intel Core Ultra 7 265KF |
| RAM | 128 GB DDR5 |
| GPU | **AMD Radeon RX 7900 XT (20 GB VRAM)** |
| GPU arch | RDNA 3 / gfx1100 |
| Primary service | vLLM OpenAI-compatible API — **port 8000** |
| Alternative service | Ollama + ROCm — **port 11435** (see §3) |
| Dashboard | Node A Command Center — **port 3099** |
| KVM Operator | FastAPI — **port 5000** |

---

## 1 — Host Prerequisites

### 1.1 Operating System

Fedora 40 / 41 / 42 / 43 or Ubuntu 22.04 / 24.04 are the tested platforms.
The RX 7900 XT requires **ROCm 6.x** for GPU-accelerated inference.

### 1.2 ROCm (AMD GPU driver stack)

**Fedora:**
```bash
# Add the AMD ROCm dnf repo
sudo tee /etc/yum.repos.d/rocm.repo > /dev/null <<'REPO'
[ROCm]
name=ROCm
baseurl=https://repo.radeon.com/rocm/rhel9/latest/main
enabled=1
gpgcheck=1
gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key
REPO

sudo dnf install -y rocm-hip-sdk rocm-opencl-sdk rocminfo rocm-smi-lib
```

**Ubuntu 22.04 / 24.04:**
```bash
# Check the latest installer at https://repo.radeon.com/amdgpu-install/
# Replace 6.1.3 / 6.1.60103-1 with the current version shown on that page.
wget -q -O /tmp/amdgpu-install.deb \
  "https://repo.radeon.com/amdgpu-install/6.1.3/ubuntu/jammy/amdgpu-install_6.1.60103-1_all.deb"
sudo apt-get install -y /tmp/amdgpu-install.deb
sudo amdgpu-install --usecase=rocm --no-dkms -y
```

### 1.3 Add user to GPU groups

```bash
# Required so your user and Docker can reach /dev/kfd and /dev/dri
sudo usermod -aG render,video "$USER"
# Log out and back in (or: newgrp render)
```

### 1.4 Verify ROCm sees the GPU

```bash
/opt/rocm/bin/rocminfo | grep -A5 "Marketing Name"
# Expected: "Radeon RX 7900 XT"

ls -la /dev/kfd /dev/dri/render*
# /dev/kfd must exist; /dev/dri/renderD128 (or similar) must exist

rocm-smi
# Should list the GPU with VRAM and utilisation
```

### 1.5 Docker

```bash
# Install Docker CE (NOT the Fedora/Ubuntu package manager version)
# Fedora:
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo \
  https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
newgrp docker
```

---

## 2 — vLLM Deployment (Primary)

vLLM provides the highest-throughput OpenAI-compatible API on the RX 7900 XT.

### 2.1 Configure environment

```bash
cd ~/homelab/node-a-vllm
cp .env.example .env
nano .env      # set HUGGINGFACE_TOKEN and optionally VLLM_MODEL
```

`.env` options:
```bash
# HuggingFace token — required for gated models (e.g. Llama-3)
HUGGINGFACE_TOKEN=hf_your_token_here

# Model to serve.  Validated choices for 20 GB VRAM:
#   meta-llama/Llama-3.1-8B-Instruct   ~18 GB fp16  ← recommended start
#   mistralai/Mistral-7B-Instruct-v0.3 ~15 GB fp16
#   meta-llama/Llama-3.2-11B-Vision-Instruct ~22 GB  (requires --quantization awq)
VLLM_MODEL=meta-llama/Llama-3.1-8B-Instruct
```

### 2.2 Deploy

```bash
docker compose -f node-a-vllm/docker-compose.yml up -d
```

### 2.3 Verify

```bash
# Health check (returns 200 when model is loaded — may take 2-5 min on first start)
curl http://localhost:8000/health

# List served models
curl http://localhost:8000/v1/models | jq '.data[].id'
# → "brain-heavy"

# Quick chat test
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"brain-heavy","messages":[{"role":"user","content":"ping"}]}'
```

### 2.4 Key environment variables explained

| Variable | Purpose |
|----------|---------|
| `HSA_OVERRIDE_GFX_VERSION=11.0.0` | Tells ROCm the exact gfx ISA for RDNA 3 — **required** |
| `HIP_VISIBLE_DEVICES=0` | Use only the first (primary) GPU |
| `VLLM_MODEL` | HuggingFace model repo to download and serve |

### 2.5 Container logs

```bash
docker logs vllm_brain --tail 50 -f
```

Look for `Uvicorn running on http://0.0.0.0:8000` to confirm the model is loaded.

---

## 3 — Ollama Alternative (Simpler Setup)

If you prefer Ollama over vLLM (no HuggingFace token required, one-command model pull):

### 3.1 Deploy Ollama with ROCm

```bash
docker compose -f node-a-vllm/docker-compose.ollama.yml up -d
```

### 3.2 Pull a model

```bash
# Pull the recommended 8B reasoning model
docker exec ollama_brain ollama pull llama3.1:8b

# Optional — larger reasoning models (check VRAM budget first)
docker exec ollama_brain ollama pull mistral:7b
docker exec ollama_brain ollama pull qwen2.5:14b   # requires quantization flag
```

### 3.3 Verify

```bash
curl http://localhost:11435/api/version
# → {"version":"..."}

curl http://localhost:11435/api/tags | jq '.models[].name'
```

### 3.4 LiteLLM integration for Ollama on Node A

Add the following model entry to `node-b-litellm/config.yaml`:

```yaml
  - model_name: brain-ollama
    litellm_params:
      model: ollama/llama3.1:8b
      api_base: http://192.168.1.9:11435
      timeout: 180
```

---

## 4 — Port Reference (Node A)

| Port | Protocol | Service | Notes |
|------|----------|---------|-------|
| **8000** | TCP | vLLM OpenAI API | `brain-heavy` model; used by LiteLLM gateway |
| **11435** | TCP | Ollama API (ROCm) | Alternative to vLLM; *not* running by default |
| **3099** | TCP | Command Center Dashboard | Node.js status/chat proxy |
| **5000** | TCP | KVM Operator (FastAPI) | Human-in-the-loop AI KVM control |

> Note: Port 11435 is used instead of the default 11434 to avoid conflicts if Ollama
> is also running on this machine for other purposes.

---

## 5 — Integrating Node A with LiteLLM Gateway (Node B)

The LiteLLM config at `node-b-litellm/config.yaml` already routes `brain-heavy` to
`http://192.168.1.9:8000/v1`.  Verify from Node B:

```bash
# From Node B (192.168.1.222) or any machine on the LAN
# Replace sk-master-key with your actual LITELLM_MASTER_KEY if you changed it
curl -X POST http://192.168.1.222:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-master-key" \
  -H "Content-Type: application/json" \
  -d '{"model":"brain-heavy","messages":[{"role":"user","content":"Explain RDNA 3"}]}'
```

---

## 6 — Using the Automated Setup Script

The `scripts/setup-node-a.sh` script installs ROCm, prepares the `.env`, pulls the
Docker image, and deploys vLLM in one command:

```bash
# Full install + deploy
./scripts/setup-node-a.sh

# Install ROCm only — skip compose up
./scripts/setup-node-a.sh --no-deploy

# Check GPU + container health without making changes
./scripts/setup-node-a.sh --status
```

---

## 7 — Troubleshooting

### GPU not detected by ROCm

```bash
# Check kernel module is loaded
lsmod | grep amdgpu

# Check device nodes
ls -la /dev/kfd /dev/dri/render*

# Check group membership
groups   # should include 'render' and 'video'

# If /dev/kfd is missing, load the module manually
sudo modprobe amdgpu
```

### vLLM container exits immediately

```bash
docker logs vllm_brain --tail 30

# Common causes:
# 1. /dev/kfd not found — ROCm not installed or kernel module not loaded
# 2. HSA_OVERRIDE_GFX_VERSION not set — add to docker-compose.yml environment
# 3. Out of VRAM — choose a smaller model or enable quantization
```

### vLLM health endpoint returns 503

The model may still be loading (can take 2–5 min on first start).

```bash
docker logs vllm_brain -f | grep -E "loading|loaded|error|Uvicorn"
```

### VRAM out-of-memory

The RX 7900 XT has **20 GB VRAM** (fp16).  Practical limits:

| Model | VRAM (fp16) | Fits? |
|-------|-------------|-------|
| 7B / 8B | ~15-18 GB | ✓ Comfortable |
| 13B / 14B | ~28 GB | ✗ Requires Q4 quantization |
| 70B | >40 GB | ✗ Multi-GPU or CPU offload only |

To enable quantization in vLLM, add to the `command:` block in
`node-a-vllm/docker-compose.yml`:
```yaml
      --quantization awq
      --max-model-len 4096
```

### Checking GPU utilisation

```bash
rocm-smi
# Shows GPU utilisation %, VRAM used/total, temperature

# Continuous watch
watch -n 2 rocm-smi
```

---

## 8 — Quick-Reference Commands

```bash
# Start vLLM
docker compose -f node-a-vllm/docker-compose.yml up -d

# Stop vLLM
docker compose -f node-a-vllm/docker-compose.yml down

# Restart vLLM (e.g. after model change)
docker compose -f node-a-vllm/docker-compose.yml restart

# Follow logs
docker logs vllm_brain -f

# Status check
./scripts/setup-node-a.sh --status

# GPU utilisation
rocm-smi

# Test API directly
curl http://192.168.1.9:8000/health

# Test via gateway  (replace sk-master-key with your LITELLM_MASTER_KEY if changed)
curl -X POST http://192.168.1.222:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-master-key" \
  -H "Content-Type: application/json" \
  -d '{"model":"brain-heavy","messages":[{"role":"user","content":"Hello"}]}'
```
