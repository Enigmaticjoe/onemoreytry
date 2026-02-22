# Node A — The Brain: Layman's Guide

> **Who this guide is for:** Anyone who wants to understand, set up, or use Node A — no technical background required. If you can follow a recipe, you can follow this guide.

---

## What Is Node A?

Node A is the **heavy thinker** of your AI home lab. Think of it as the big, powerful library computer in the back room — it doesn't talk to you directly most of the time, but when you need serious brainpower (writing code, analyzing a long document, solving a hard problem), it's the one doing the work.

- IP address: **192.168.1.9**
- Nickname: **The Brain**
- Main job: Run large, powerful AI models that need lots of memory and computing power

---

## The Hardware — Plain English

| Part | What You've Got | Why It Matters |
|---|---|---|
| **GPU** | AMD RX 7900 XT (20 GB VRAM) | The AI's workspace — bigger = can run bigger, smarter models |
| **CPU** | Intel Core Ultra 7 265KF | Handles everything the GPU doesn't — preprocessing, routing, system tasks |
| **RAM** | 128 GB DDR5 | Lets the system juggle many things at once without slowing down |

**The GPU is the most important part.** AI models live in VRAM (GPU memory) while they're running. Node A's 20 GB VRAM means it can run models that smaller GPUs simply can't fit.

---

## What Software Runs on Node A?

| Software | Port | What It Does |
|---|---|---|
| **vLLM** | 8000 | Serves big AI models at high speed — this is your "smart brain" API |
| **Ollama (ROCm)** | 11435 | Another way to run models, especially useful for pulling and managing them |
| **Node A Command Center** | 3099 | A dashboard you can open in your browser to see the status of everything |

---

## Setting Up Node A — Step by Step

### Step 1: Install ROCm (AMD GPU Drivers for AI)

ROCm is AMD's software that lets the GPU run AI workloads. Without it, the GPU just sits there.

```bash
# Add AMD's software repository
sudo apt update
sudo apt install -y wget gnupg

wget https://repo.radeon.com/amdgpu-install/6.1.3/ubuntu/jammy/amdgpu-install_6.1.3.60103-1_all.deb
sudo dpkg -i amdgpu-install_6.1.3.60103-1_all.deb
sudo apt update

# Install ROCm
sudo amdgpu-install --usecase=rocm
```

After installing, add your user to the video and render groups so the GPU is accessible:

```bash
sudo usermod -aG video,render $USER
```

Then **reboot** the machine. This is required for ROCm to activate.

### Step 2: Verify ROCm Is Working

After rebooting, run this to confirm the GPU is detected:

```bash
rocm-smi
```

You should see your RX 7900 XT listed with temperature and memory usage. If you see it — you're good.

### Step 3: Start the Node A Services

Navigate to the Node A folder and start everything with Docker:

```bash
cd /path/to/node-a-vllm
docker compose up -d
```

The `-d` means "run in the background." You can close your terminal and it keeps running.

### Step 4: Pull AI Models into Ollama

Ollama makes downloading models easy — like downloading an app:

```bash
# A solid all-around model
ollama pull llama3.1:8b

# A bigger, more capable model (needs more VRAM)
ollama pull llama3.1:70b

# A fast coding model
ollama pull codestral:22b
```

> **Tip:** The number after the colon (like `:8b`) is the model size. Bigger numbers are smarter but slower and need more VRAM.

---

## Accessing the Command Center Dashboard

Open your browser and go to:

```
http://192.168.1.9:3099
```

This is your control panel. You can see:
- Which AI models are loaded and running
- How much GPU memory is being used
- Whether vLLM and Ollama are healthy
- Quick links to test endpoints

No login required on a home network — just open it and it works.

---

## Testing That vLLM Is Working

Open a terminal on any computer on your network and run:

```bash
curl http://192.168.1.9:8000/health
```

You should get back something like `{"status":"ok"}`. That means vLLM is alive and ready.

To actually ask the AI a question:

```bash
curl http://192.168.1.9:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "brain-heavy",
    "messages": [{"role": "user", "content": "What is 2 + 2?"}]
  }'
```

You should get a response with the answer. If you do — Node A is fully working.

---

## Why ROCm? (AMD vs NVIDIA for AI)

Most AI tutorials assume you have an NVIDIA GPU. AMD GPUs need **ROCm** instead of NVIDIA's CUDA. Think of it like this:

- NVIDIA GPU + CUDA = default track
- AMD GPU + ROCm = the AMD track — same destination, different road

ROCm has improved a lot and works great for running models, but occasionally needs a workaround.

### The Most Common ROCm Workaround

If models won't load or you see GPU errors, try setting this environment variable:

```bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
```

Add it to your Docker Compose environment section or your shell profile (`~/.bashrc`) so it's always set.

---

## Common Problems and Fixes

### "GPU not detected" or ROCm errors

```bash
# Check if ROCm sees the GPU
rocm-smi

# If nothing shows, check your group membership
groups $USER
# You should see "video" and "render" in the list
```

If the groups are missing, re-run the `usermod` command above and reboot again.

### "Model won't load" / Out of VRAM

The model is too big for available VRAM. Options:
1. Use a smaller model (e.g., `:8b` instead of `:70b`)
2. Stop other models that are loaded to free up memory
3. Check current VRAM usage with `rocm-smi`

### "Connection refused" on port 8000

vLLM probably isn't running yet. Check:

```bash
docker ps
```

Look for a container with "vllm" in the name. If it's not there:

```bash
cd /path/to/node-a-vllm
docker compose up -d
docker compose logs -f
```

The logs will tell you exactly what went wrong.

### HSA_OVERRIDE_GFX_VERSION

If you see an error mentioning `gfx` or unsupported GPU version, add this to your Docker Compose file under the vLLM service's `environment:` section:

```yaml
environment:
  - HSA_OVERRIDE_GFX_VERSION=11.0.0
```

Then restart: `docker compose down && docker compose up -d`

---

## When to Use Node A vs Other Nodes

| Task | Use Node A? |
|---|---|
| Writing or debugging long code | ✅ Yes — use `brain-heavy` model |
| Analyzing a 50-page document | ✅ Yes — needs big context window |
| Quick chat or simple question | ❌ No — use Node C (faster for quick tasks) |
| Image analysis / vision | ❌ No — use Node C (has vision models) |
| Smart home questions | ❌ No — use Node D (Home Assistant handles it) |

Node A is best for tasks that need **depth over speed**. If you're asking a hard question and willing to wait 10–30 seconds for a great answer, Node A is your go-to.

---

## Maintenance

### Updating Models

```bash
# Update a specific model
ollama pull llama3.1:8b

# See all downloaded models
ollama list
```

### Checking VRAM Usage

```bash
rocm-smi
```

Look at the "GPU Use%" and "VRAM Use" columns. If VRAM is near 100%, models may fail to load.

### Checking What's Running

```bash
docker ps
```

Lists all running containers. You should always see vLLM and Ollama running. If one is missing, restart it:

```bash
docker compose up -d
```

### Viewing Logs

```bash
# See recent logs from all containers
docker compose logs --tail=50

# Follow live logs (press Ctrl+C to stop)
docker compose logs -f
```

---

## Quick Reference

| Thing | Value |
|---|---|
| IP Address | 192.168.1.9 |
| Dashboard | http://192.168.1.9:3099 |
| vLLM API | http://192.168.1.9:8000 |
| Ollama API | http://192.168.1.9:11435 |
| Model alias | `brain-heavy` |
| GPU | AMD RX 7900 XT (20 GB) |
| GPU driver stack | ROCm |
