# Node C — The Command Center / Eyes: Layman's Guide

> Canonical architecture authority: [`docs/ARCHITECTURE_CANONICAL_2026.md`](ARCHITECTURE_CANONICAL_2026.md).


> **Who this guide is for:** Anyone who wants to chat with the AI, analyze images, or manage deployments from Node C. This is the most user-facing node — the one you'll interact with the most day-to-day.

---

## What Is Node C?

Node C is the **face of the system** — the node you interact with most directly. It's where:

- You open a chat window and talk to the AI
- The system analyzes images (security cameras, uploaded photos, anything visual)
- OpenClaw helps you manage and deploy services across the lab

- IP address: **192.168.1.6**
- Nickname: **The Command Center / Eyes**
- OS: **Fedora 44** (cosmic nightly)

Think of Node A as the brain working in the back room, and Node C as the friendly face at the front desk that takes your request, handles the quick stuff itself, and calls the back room only when needed.

---

## The Hardware — Plain English

| Part | What You've Got | Why It Matters |
|---|---|---|
| **GPU** | Intel Arc A770 (16 GB VRAM) | Great for vision AI and running mid-size models; surprisingly capable for its price |
| **CPU** | AMD Ryzen 7 7700X | Fast, efficient — keeps chat and vision responses snappy |
| **RAM** | 32 GB DDR5 | Enough for running multiple services simultaneously |

### What Makes the Intel Arc A770 Special?

The Arc A770 has **16 GB of VRAM** — more than NVIDIA's RTX 4070 Ti, at a fraction of the cost. This means it can fit larger models in memory than you'd expect from a mid-range card. It's especially well-suited for:

- **Vision models** (llava and similar) — they need lots of VRAM to process images
- Running Ollama efficiently with Intel's oneAPI acceleration
- Being the "always-on" card since it runs cool and efficient at idle

---

## What Software Runs on Node C?

| Software | Port | What It Does |
|---|---|---|
| **Ollama** | 11434 | Runs and serves AI models, including vision models |
| **Open WebUI ("chimera_face")** | 3000 | Your chat interface — the window you type into |
| **OpenClaw** | 18789 | Deployment and management assistant with a control UI |

---

## Setting Up Node C — Step by Step

### Step 1: Install Intel GPU Drivers on Fedora 44 (cosmic nightly)

Fedora 44 (cosmic nightly) includes decent Intel GPU support out of the box, but for AI workloads you want the full Intel oneAPI stack.

```bash
# Update system first
sudo dnf update -y

# Add Intel's repository
sudo dnf install -y intel-one-api-mkl intel-opencl

# Install level-zero (needed for GPU compute)
sudo dnf install -y level-zero level-zero-devel
```

Verify the GPU is recognized:

```bash
clinfo | grep "Device Name"
```

You should see `Intel(R) Arc(TM) A770 Graphics` or similar.

### Step 2: Set the Required Environment Variable

Intel Arc GPUs need one special setting to expose hardware management info. Add this to your shell profile:

```bash
echo 'export ZES_ENABLE_SYSMAN=1' >> ~/.bashrc
source ~/.bashrc
```

This tells the Intel driver to enable system management features — without it, Ollama and other tools can't properly read GPU temperature and memory usage.

### Step 3: Start Node C Services

```bash
cd /path/to/node-c-arc
docker compose up -d
```

This starts Ollama, Open WebUI (chimera_face), and OpenClaw together.

### Step 4: Pull Vision and Chat Models

```bash
# The vision model — can analyze images
ollama pull llava

# A good all-around chat model
ollama pull llama3.1:8b

# A faster, smaller model for quick responses
ollama pull phi3:mini
```

---

## Accessing Open WebUI (Your Chat Interface)

Open your browser and go to:

```
http://192.168.1.6:3000
```

This is `chimera_face` — your main AI chat window. From here you can:
- Type messages and get responses from any model in the lab
- Upload images and ask the AI to describe or analyze them
- Switch between different AI models using the dropdown at the top
- See your conversation history

> **First time?** You'll be asked to create a local account. This is just for keeping your chat history organized — it stays on your home network.

---

## Accessing the OpenClaw Control UI

OpenClaw has its own web interface for managing deployments:

```
http://192.168.1.6:18789
```

From here you can:
- See what services are deployed across the lab
- Trigger deployments and updates
- Chat with the AI specifically about your infrastructure
- Connect to LiteLLM as a fallback for harder questions

---

## How to Analyze an Image in Open WebUI

1. Open `http://192.168.1.6:3000` in your browser
2. Make sure the **llava** model is selected in the dropdown (top of chat)
3. Click the **paperclip or image icon** in the chat input area
4. Select a photo from your computer
5. Type your question, for example: `"What do you see in this image?"`
6. Press Enter — the AI will describe what it sees

This works for any image: security camera screenshots, photos you've taken, diagrams, documents, anything visual.

---

## How to Connect OpenClaw to LiteLLM for Fallback

If OpenClaw's local model isn't good enough for a task, it can fall back to LiteLLM on Node B (which can route to Node A's powerful models).

In OpenClaw's settings or its config file, set:

```yaml
litellm_base_url: http://192.168.1.222:4000
litellm_api_key: sk-master-key
fallback_model: brain-heavy
```

Now when OpenClaw hits a complex task, it automatically upgrades to Node A's models.

---

## ZES_ENABLE_SYSMAN — Why It's Needed

`ZES_ENABLE_SYSMAN=1` is a flag that tells Intel's GPU driver to turn on its hardware monitoring features. Without it:

- Ollama can't report GPU temperature or memory usage
- Some models may fail to load properly
- Performance monitoring tools show incomplete data

Think of it like turning on the "check engine" light system in a car — the car works without it, but you lose visibility into what's happening under the hood.

Always make sure this is set before starting Ollama:

```bash
# Check if it's set
echo $ZES_ENABLE_SYSMAN
# Should print: 1

# Set it for current session if missing
export ZES_ENABLE_SYSMAN=1
```

If running via Docker, add it to the Compose environment:

```yaml
environment:
  - ZES_ENABLE_SYSMAN=1
```

---

## Common Problems and Fixes

### Arc GPU Not Recognized

```bash
# Check if the GPU shows up
lspci | grep -i "arc\|intel.*graphics"

# Check OpenCL devices
clinfo | grep -i "device name"
```

If nothing shows, make sure the Intel compute runtime is installed:

```bash
sudo dnf install -y intel-opencl
```

Then reboot and try again.

### Models Running Slowly

A few things to check:

1. **Is ZES_ENABLE_SYSMAN set?** (see above)
2. **Is Ollama using the GPU?** Run `ollama ps` — it should show GPU usage
3. **Is another model already loaded?** Run `ollama ps` and stop unused models

```bash
# See what's loaded
ollama ps

# Stop a specific model
ollama stop llama3.1:8b
```

### Open WebUI Can't Reach Ollama

If you see an error like "Cannot connect to Ollama" in Open WebUI:

```bash
# Check if Ollama is running
docker ps | grep ollama

# Test Ollama directly
curl http://192.168.1.6:11434/api/tags
```

If Ollama isn't running, restart it:

```bash
docker compose up -d ollama
```

If it's running but WebUI still can't connect, check the `OLLAMA_BASE_URL` setting in your Open WebUI container — it should be set to `http://ollama:11434` (using the Docker service name) or `http://192.168.1.6:11434`.

### OpenClaw Shows No Services

Make sure OpenClaw has the correct lab configuration. Check its config file for the correct IP addresses of other nodes and restart:

```bash
docker compose restart openclaw
```

---

## When to Use Node C

| Task | Node C? |
|---|---|
| Quick chat / questions | ✅ Yes — fast, responsive |
| Analyzing a photo or screenshot | ✅ Yes — has llava vision model |
| Deploying or managing services | ✅ Yes — OpenClaw is here |
| Writing a long complex document | ❌ Consider Node A (`brain-heavy`) |
| Smart home control | ❌ Use Node D (Home Assistant) |
| Security camera AI analysis | ✅ Yes — Node E uses Node C for vision |

---

## Quick Reference

| Thing | Value |
|---|---|
| IP Address | 192.168.1.6 |
| Open WebUI | http://192.168.1.6:3000 |
| Ollama API | http://192.168.1.6:11434 |
| OpenClaw UI | http://192.168.1.6:18789 |
| Model alias | `intel-vision` (llava) |
| GPU | Intel Arc A770 (16 GB) |
| OS | Fedora 44 (cosmic nightly) |
| Key env var | `ZES_ENABLE_SYSMAN=1` |

---

## Maintenance

### Updating Models

```bash
# Re-pull a model to get the latest version
ollama pull llava
ollama pull llama3.1:8b

# List all downloaded models and their sizes
ollama list
```

### Freeing Up Space

Models take up significant disk space. Remove ones you don't use:

```bash
ollama rm model-name-here
```

### Checking GPU Health

```bash
# Intel GPU status (requires ZES_ENABLE_SYSMAN=1)
intel_gpu_top

# Or use this simpler check
cat /sys/class/drm/card*/gt/gt0/freq_cur_mhz
```
