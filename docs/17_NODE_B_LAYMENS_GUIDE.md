# Node B — The Gateway: Layman's Guide

> Canonical architecture authority: [`docs/ARCHITECTURE_CANONICAL_2026.md`](ARCHITECTURE_CANONICAL_2026.md).


> **Who this guide is for:** Anyone setting up or managing Node B — the traffic director, storage hub, and deployment workhorse of the home lab. No technical background needed.

---

## What Is Node B?

Node B is the **gateway and brawn** of your AI home lab. If Node A is the deep thinker, Node B is the dispatcher and the muscle. It:

- Routes all AI requests across the lab through LiteLLM
- Hosts Postgres, the database that keeps everything organized
- Runs Portainer so you can manage Docker containers with a web interface
- Runs OpenClaw, the deployment assistant
- Handles its own fast AI inference with its own GPU

- IP address: **192.168.1.222**
- Nickname: **The Brawn / Gateway**
- OS: **Unraid**

---

## What Is Unraid?

Unraid is a special operating system designed for home servers and NAS (Network Attached Storage) machines. Think of it as the easy-mode operating system for people who want to:

- Store lots of data across many hard drives without worrying about formatting
- Run Docker containers without needing to be a Linux expert
- Manage everything from a web browser

You don't need to know Linux commands to use Unraid — most things have a point-and-click interface. But for this guide, we'll show you both the easy way and the terminal way.

---

## The Hardware — Plain English

| Part | What You've Got | Why It Matters |
|---|---|---|
| **GPU** | NVIDIA RTX 4070 (12 GB VRAM) | Runs fast AI models locally; NVIDIA = CUDA = very well supported |
| **CPU** | Intel i5-13600K | Strong performer, handles multiple services simultaneously |
| **RAM** | 96 GB DDR5 | Plenty for running LiteLLM, Postgres, and several containers at once |

---

## What Software Runs on Node B?

| Software | Port | What It Does |
|---|---|---|
| **LiteLLM** | 4000 | Routes AI requests — tells traffic which AI model to use |
| **vLLM** | 8002 | Local AI inference — runs fast GPU models directly |
| **Postgres** | 5432 | Database — stores LiteLLM usage logs and config |
| **OpenClaw** | varies | Deployment assistant — helps you deploy and manage services |
| **Portainer** | 9443 | Web UI for managing all Docker containers |

---

## Setting Up Node B — Step by Step

### Step 1: Make Sure Docker Is Running (Unraid)

In Unraid, Docker is built in. Go to **Settings → Docker** and make sure Docker is enabled.

### Step 2: Start the LiteLLM Stack

Connect to Node B via terminal (SSH) or Unraid's built-in terminal, then run:

```bash
cd /mnt/user/appdata/litellm   # or wherever you've placed the files
docker compose -f litellm-stack.yml up -d
```

This starts LiteLLM, its Postgres database, and the other services defined in the stack file.

### Step 3: Verify Everything Started

```bash
docker ps
```

You should see containers for `litellm`, `postgres`, and any others defined in the stack. If any are missing, check the logs (see below).

---

## Accessing Portainer

Portainer is a web-based Docker manager — like a control panel for all your containers.

Open your browser and go to:

```
https://192.168.1.222:9443
```

> **Note the `https`** — Portainer uses a secure connection. Your browser may warn you about the certificate — that's normal for a home network. Click "Advanced" and proceed.

From Portainer you can:
- Start / stop / restart any container with a click
- View live logs from any container
- See resource usage (CPU, memory) per container
- Pull new Docker images

---

## Testing LiteLLM Is Working

From any computer on your network, run:

```bash
curl http://192.168.1.222:4000/health
```

You should see something like:

```json
{"status": "healthy"}
```

To test that it can actually route an AI request:

```bash
curl http://192.168.1.222:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-master-key" \
  -d '{
    "model": "brawn-fast",
    "messages": [{"role": "user", "content": "Say hello"}]
  }'
```

If you get a response with text in it — LiteLLM is routing successfully.

---

## The Master Key — What It Is and How to Change It

The **master key** (`sk-master-key`) is the password that unlocks full access to LiteLLM. Any app sending requests to LiteLLM must include this key.

Think of it as the skeleton key for your AI gateway — it opens everything.

### How to change it

In your `config.yaml` (or `litellm-stack.yml` environment section), find:

```yaml
LITELLM_MASTER_KEY: sk-master-key
```

Change it to something harder to guess:

```yaml
LITELLM_MASTER_KEY: sk-your-new-secret-key-here
```

Then restart LiteLLM:

```bash
docker compose -f litellm-stack.yml down
docker compose -f litellm-stack.yml up -d
```

> **Important:** After changing the key, update it everywhere it's used — Home Assistant, Open WebUI, OpenClaw, etc.

---

## Adding New Models to config.yaml

LiteLLM uses a `config.yaml` file to know which AI models exist and where to find them. Adding a new model is like adding a new entry to a phonebook.

Open `config.yaml` and add under the `model_list:` section:

```yaml
model_list:
  - model_name: brawn-fast
    litellm_params:
      model: openai/mistral-7b
      api_base: http://192.168.1.222:8002/v1
      api_key: none

  - model_name: my-new-model
    litellm_params:
      model: openai/new-model-name
      api_base: http://192.168.1.222:8002/v1
      api_key: none
```

Save the file, then restart LiteLLM for the changes to take effect.

---

## Reading LiteLLM Logs

Logs are the record of everything LiteLLM has done — who asked what, which model was used, any errors.

```bash
# Show the last 100 lines of LiteLLM logs
docker logs litellm --tail=100

# Follow live logs (press Ctrl+C to stop)
docker logs litellm -f
```

Look for lines with `ERROR` or `FAILED` to spot problems. Successful requests show the model name and response time.

---

## OpenClaw on Node B — What It's For

OpenClaw is your **deployment assistant**. It helps you:
- Deploy and update services across the lab
- Automate Docker container management
- Get AI-assisted help with infrastructure tasks

Node B runs a dedicated deployer instance of OpenClaw, separate from the one on Node C. This instance is specifically designed for managing the Unraid/Docker environment on Node B.

---

## Managing Unraid Storage

Unraid is excellent at managing many drives in one pool. Here's when to pay attention:

### When to Add Drives

- When any existing drive is over 80% full
- When you want to add redundancy (a parity drive protects you from one drive failure)

### Checking Drive Health

In the Unraid web UI, go to **Main** — you'll see all drives, their sizes, and a health indicator. Green = good. Yellow/Red = attention needed.

---

## Common Problems and Fixes

### Postgres Won't Start

Postgres sometimes fails if its data directory has wrong permissions.

```bash
# Check logs
docker logs postgres --tail=50

# Common fix: check the volume permissions
ls -la /mnt/user/appdata/postgres
```

If the data folder is owned by root but Postgres expects another user, fix it:

```bash
sudo chown -R 999:999 /mnt/user/appdata/postgres
docker compose -f litellm-stack.yml restart postgres
```

### Model Not Routing / Wrong Model

Check that the model name in your request exactly matches the `model_name:` in `config.yaml`. It's case-sensitive.

```bash
# List all configured models
curl http://192.168.1.222:4000/models \
  -H "Authorization: Bearer sk-master-key"
```

### "Connection Refused" on Port 4000

LiteLLM isn't running. Check:

```bash
docker ps | grep litellm
```

If missing, start it:

```bash
cd /path/to/litellm
docker compose -f litellm-stack.yml up -d
```

### API Key Rejected (401 Unauthorized)

The key you're using doesn't match `LITELLM_MASTER_KEY`. Double-check the key in `config.yaml` and make sure the request uses the exact same value.

---

## Quick Reference

| Thing | Value |
|---|---|
| IP Address | 192.168.1.222 |
| LiteLLM API | http://192.168.1.222:4000 |
| vLLM API | http://192.168.1.222:8002 |
| Portainer | https://192.168.1.222:9443 |
| Master Key | sk-master-key |
| Model alias | `brawn-fast` |
| GPU | NVIDIA RTX 4070 (12 GB) |
| OS | Unraid |

---

## Model Aliases Cheat Sheet

| Alias | Points To | Best For |
|---|---|---|
| `brain-heavy` | Node A vLLM (port 8000) | Hard reasoning, long documents |
| `brawn-fast` | Node B vLLM (port 8002) | Fast responses, lighter tasks |
| `intel-vision` | Node C Ollama llava | Image analysis, vision tasks |
