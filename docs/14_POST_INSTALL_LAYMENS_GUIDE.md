# 14 — Post-Installation Layman's Guide: "Now What?"

**Who this guide is for:** You've followed the setup guides, your containers are (hopefully) running, and now you're staring at your screen wondering what to actually *do* next. This guide walks you through verifying everything works, sending your first AI message, and keeping things healthy — in plain English, no experience required.

---

## Table of Contents

1. [The Big Picture — What You Just Built](#1-the-big-picture)
2. [Step 1 — Check That Everything Is Running](#2-step-1--check-that-everything-is-running)
3. [Health-Check Checklist Table](#3-health-check-checklist-table)
4. [First-Time Tests](#4-first-time-tests)
5. [Loading Your First AI Model](#5-loading-your-first-ai-model)
6. [Choosing the Right Model: Brain-Heavy vs Brawn-Fast vs Intel-Vision](#6-choosing-the-right-model)
7. [Setting Up Your First System Prompt](#7-setting-up-your-first-system-prompt)
8. [Common First-Day Problems and Fixes](#8-common-first-day-problems-and-fixes)
9. [How to Know Everything Is Working Correctly](#9-how-to-know-everything-is-working-correctly)
10. [Maintenance Basics](#10-maintenance-basics)
11. [Quick-Reference: All Ports and URLs](#11-quick-reference-all-ports-and-urls)

---

## 1. The Big Picture

You built a private, home-hosted AI system. Here's a plain-English map of what's running:

| Nickname | Machine | IP Address | What It Does |
|---|---|---|---|
| **Node A — The Brain** | Desktop/Server | `192.168.1.9` | Runs heavy-duty AI models using an AMD RX 7900 XT GPU |
| **Node B — The Brawn** | Unraid Server | `192.168.1.222` | Routes all your AI requests and runs fast models on an RTX 4070 |
| **Node C — Command Center** | Intel Arc machine | `192.168.1.6` | Hosts the chat interface (Open WebUI), manages other services, handles images |
| **Node D — Home Assistant** | Dedicated machine | `192.168.1.149` | Your smart home brain; now powered by your local AI |
| **Node E — Sentinel** | Any machine | (your network) | Monitoring and alerting, available on port `3005` |

Think of **Node B** as the switchboard operator — every AI request goes through it first, and it decides where to send it. You talk to the system through **Node C's** chat interface.

---

## 2. Step 1 — Check That Everything Is Running

Before testing anything, let's make sure all the pieces are alive. Open a browser on any device on your home network and visit each URL below. You can also use the `curl` commands in a terminal if you prefer.

### Node A — The Brain (`192.168.1.9`)

**vLLM (heavy AI engine):**
- Browser: `http://192.168.1.9:8000/health`
- Expected: a page showing `{"status":"ok"}` or similar JSON
- Terminal test:
  ```bash
  curl http://192.168.1.9:8000/health
  ```

**Ollama (fast local models):**
- Browser: `http://192.168.1.9:11435`
- Expected: a plain page that says `Ollama is running`
- Terminal test:
  ```bash
  curl http://192.168.1.9:11435
  ```

---

### Node B — The Brawn / Unraid (`192.168.1.222`)

**LiteLLM Gateway (the AI switchboard):**
- Browser: `http://192.168.1.222:4000/health`
- Expected: JSON response with service status
- Terminal test:
  ```bash
  curl http://192.168.1.222:4000/health
  ```

**LiteLLM Dashboard (web interface):**
- Browser: `http://192.168.1.222:4000/ui`
- Expected: A login page or dashboard — this is where you manage models

**vLLM on Node B (fast GPU models):**
- Browser: `http://192.168.1.222:8002/health`
- Expected: `{"status":"ok"}`
- Terminal test:
  ```bash
  curl http://192.168.1.222:8002/health
  ```

---

### Node C — Command Center (`192.168.1.6`)

**Open WebUI (your chat interface):**
- Browser: `http://192.168.1.6:3000`
- Expected: A login/signup page that looks like ChatGPT

**Ollama on Node C:**
- Browser: `http://192.168.1.6:11434`
- Expected: `Ollama is running`
- Terminal test:
  ```bash
  curl http://192.168.1.6:11434
  ```

**OpenClaw Gateway:**
- Browser: `http://192.168.1.6:18789`
- Expected: A status or welcome page

**Node A Command Center Dashboard:**
- Browser: `http://192.168.1.6:3099`
- Expected: The command center dashboard with service status lights

---

### Node D — Home Assistant (`192.168.1.149`)

- Browser: `http://192.168.1.149:8123`
- Expected: The Home Assistant login page

---

### Node E — Sentinel Monitoring (`your-sentinel-machine:3005`)

- Browser: `http://<sentinel-ip>:3005`
- Expected: Monitoring dashboard

---

## 3. Health-Check Checklist Table

Use this as a checklist on first boot. Tick each one off before moving on.

| Service | URL to Visit | What You Should See | Status |
|---|---|---|---|
| Node A — vLLM | `http://192.168.1.9:8000/health` | `{"status":"ok"}` | ☐ |
| Node A — Ollama | `http://192.168.1.9:11435` | `Ollama is running` | ☐ |
| Node B — LiteLLM API | `http://192.168.1.222:4000/health` | JSON health response | ☐ |
| Node B — LiteLLM Dashboard | `http://192.168.1.222:4000/ui` | Dashboard or login page | ☐ |
| Node B — vLLM | `http://192.168.1.222:8002/health` | `{"status":"ok"}` | ☐ |
| Node C — Open WebUI | `http://192.168.1.6:3000` | Chat login/signup page | ☐ |
| Node C — Ollama | `http://192.168.1.6:11434` | `Ollama is running` | ☐ |
| Node C — OpenClaw | `http://192.168.1.6:18789` | Status/welcome page | ☐ |
| Node C — Command Center | `http://192.168.1.6:3099` | Dashboard with green lights | ☐ |
| Node D — Home Assistant | `http://192.168.1.149:8123` | HA login page | ☐ |

---

## 4. First-Time Tests

### Test 1 — Send Your First AI Chat Message (Open WebUI)

1. Open your browser and go to `http://192.168.1.6:3000`
2. If this is your first visit, click **Sign Up** and create an account (your first account automatically becomes the admin)
3. Once logged in, you'll see a chat window — just like ChatGPT
4. At the top of the chat, click the **model selector** (it may show a model name or a dropdown arrow)
5. Choose a model — start with `brawn-fast` if it's available, or any listed model
6. Type something simple in the chat box:
   ```
   Hello! Can you tell me what 2 + 2 is?
   ```
7. Press **Enter** or click the send button
8. If you get a response, **your AI is working!** 🎉

> **Didn't see any models in the dropdown?** You probably need to load a model first — see Section 5.

---

### Test 2 — Ask Home Assistant a Question Out Loud

> This assumes you've already set up the Home Assistant AI integration (see the Home Assistant guide).

1. Find a device with your Home Assistant voice assistant set up (phone, tablet, or smart speaker)
2. Say your wake word followed by a question, for example:
   - *"Hey Jarvis, what's the weather like today?"*
   - *"Hey Jarvis, turn on the living room lights."*
   - *"Hey Jarvis, write me a shopping list."*
3. If HA responds with an AI-generated answer (not just a pre-programmed response), the connection to your local AI is working
4. You can also test via the HA dashboard: go to `http://192.168.1.149:8123`, open the **Assist** panel (the chat icon in the top bar), and type a question

---

### Test 3 — Use the Node A Command Center Dashboard

1. Open your browser and go to `http://192.168.1.6:3099`
2. You should see a dashboard showing the status of all your nodes and services
3. Green indicators = services are healthy
4. Red or grey indicators = something needs attention
5. The dashboard also has a built-in chatbot — try typing a message to it directly from the dashboard

---

## 5. Loading Your First Ollama Model

Ollama models are like apps — you have to download ("pull") them before you can use them. Here's how to load the popular **Llama 3.2** model on Node C:

### Option A — Using the Terminal (SSH into Node C)

```bash
# SSH into Node C or open a terminal on that machine
ollama pull llama3.2
```

This downloads the model (it may be several gigabytes — be patient). You'll see a progress bar. When it finishes, the model is ready to use.

### Option B — Through Docker (if Ollama is running in a container)

```bash
# Run the pull command inside the Ollama container
docker exec -it ollama ollama pull llama3.2
```

### Option C — Through the Open WebUI Interface

1. Go to `http://192.168.1.6:3000`
2. Log in as admin
3. Go to **Settings** (gear icon) → **Admin Settings** → **Models**
4. Type `llama3.2` in the model download box and click **Pull**

### Other Useful Models to Pull

```bash
ollama pull llama3.2          # General purpose, great starter model
ollama pull llava             # Image analysis (use with intel-vision)
ollama pull mistral           # Fast and smart for most tasks
ollama pull codellama         # Specialized for writing code
ollama pull phi3              # Very small but surprisingly capable
```

---

## 6. Choosing the Right Model

You have three main "flavors" of AI available. Here's when to use each:

### 🧠 `brain-heavy` — Node A (192.168.1.9, RX 7900 XT)

**Best for:**
- Complex, multi-step reasoning
- Writing long documents or detailed analyses
- Tasks where accuracy matters more than speed
- Research questions, legal/medical explanations, technical deep-dives

**Trade-off:** Slower to respond (may take 30–60+ seconds for long outputs)

**Example use:** *"Explain the pros and cons of three different home network security setups in detail."*

---

### ⚡ `brawn-fast` — Node B (192.168.1.222, RTX 4070)

**Best for:**
- Quick questions and short answers
- Everyday chat, quick lookups
- Code snippets and simple explanations
- When you want a response in under 10 seconds

**Trade-off:** May not do as well on very long or very complex tasks

**Example use:** *"What's a quick Python command to list all files in a folder?"*

---

### 👁️ `intel-vision` — Node C (192.168.1.6, Intel Arc A770 + llava)

**Best for:**
- Looking at images and describing what's in them
- Reading text from a photo (receipts, signs, screenshots)
- Any task where you attach a picture

**Trade-off:** Text-only responses may not be as strong as brain-heavy or brawn-fast

**Example use:** Attach a photo of your fridge and ask *"What can I make for dinner with these ingredients?"*

---

### Quick Decision Chart

```
Is your task about an IMAGE?
  └─ Yes → intel-vision
  └─ No → Is the answer short (1-2 paragraphs or less)?
              └─ Yes → brawn-fast (fast and easy)
              └─ No → Is it complex, detailed, or accuracy-critical?
                          └─ Yes → brain-heavy
                          └─ No → brawn-fast (still fine)
```

---

## 7. Setting Up Your First System Prompt

A **system prompt** is a secret set of instructions you give to the AI *before* the conversation starts. It shapes how the AI behaves — its personality, what it focuses on, and what rules it follows. You set it once and it applies to every conversation.

### How to Set a Global System Prompt in Open WebUI

1. Go to `http://192.168.1.6:3000` and log in
2. Click your **profile icon** (bottom left) → **Settings**
3. Find **System Prompt** (in the General settings tab)
4. Paste in your prompt and click **Save**

### Example Starter System Prompts

**General Home Assistant:**
```
You are a helpful, friendly assistant running privately on my home network. 
You give clear, concise answers. When you're not sure about something, 
you say so rather than guessing. You keep responses brief unless I ask for detail.
```

**Home Lab Helper:**
```
You are an expert in self-hosted software, Docker, home networking, and Linux. 
You help me manage my home lab. Give practical, copy-paste-ready commands 
when relevant. Assume I'm comfortable with the basics but explain anything advanced.
```

**Code Helper:**
```
You are a coding assistant. When I ask for code, provide working examples 
with brief explanations. Prefer Python unless I specify otherwise. 
Point out potential bugs or improvements. Keep explanations short and practical.
```

> **Tip:** You can also set per-model system prompts in **Workspace → Models** — great if you want `brain-heavy` to behave differently from `brawn-fast`.

---

## 8. Common First-Day Problems and Fixes

### ❌ Problem: A container isn't starting

**Symptoms:** URL shows "Connection refused" or "This site can't be reached"

**Fixes:**
1. Open Portainer at `http://192.168.1.6:9000` (or whichever node runs it)
2. Go to **Containers** — look for containers with a red/stopped status
3. Click the container name → **Logs** — read the last few lines for error messages
4. Common causes:
   - **Port conflict:** Another app is already using that port → change the port in docker-compose.yml
   - **Missing environment variable:** The container needs an API key you didn't set → check `.env` file
   - **Not enough memory:** Especially for large models → check available RAM/VRAM
5. Click **Start** or **Restart** in Portainer to try again

---

### ❌ Problem: Model won't load / "Model not found" error

**Symptoms:** You select a model in Open WebUI but get an error, or the model list is empty

**Fixes:**
1. The model hasn't been pulled yet → run `ollama pull <model-name>` (see Section 5)
2. Ollama is running but on a different port than Open WebUI expects → check your Open WebUI connection settings
3. LiteLLM doesn't know about the model → check `config.yaml` on Node B and make sure the model alias is listed

---

### ❌ Problem: Home Assistant isn't responding to AI questions

**Symptoms:** HA gives generic or pre-programmed responses instead of AI-generated ones

**Fixes:**
1. Check that the `extended_openai_conversation` integration is installed and configured
2. Verify the LiteLLM URL in HA's integration settings: `http://192.168.1.222:4000/v1`
3. Verify the API key is `sk-master-key`
4. Test LiteLLM directly: `curl http://192.168.1.222:4000/health`
5. Check HA logs: **Settings → System → Logs**

---

### ❌ Problem: Open WebUI login page loads but chat doesn't work

**Symptoms:** You can log in, but sending a message produces an error or spins forever

**Fixes:**
1. Go to **Settings → Connections** in Open WebUI
2. Check that the LiteLLM URL is set to `http://192.168.1.222:4000/v1`
3. Check that the API key is `sk-master-key`
4. Click **Verify Connection** — it will tell you if there's a problem
5. If it says "No models found," your LiteLLM config may not have any models configured yet

---

### ❌ Problem: Responses are extremely slow

**Symptoms:** You send a message and wait minutes for a response

**Fixes:**
1. Check GPU utilization: if the GPU isn't being used, the model is running on CPU (much slower)
2. On Node A, run: `rocm-smi` (AMD) or check your system monitor
3. On Node B, run: `nvidia-smi`
4. If GPU isn't being used: the container may not have GPU passthrough configured — check `docker-compose.yml` for `deploy: resources: reservations: devices:`
5. Switch to a smaller model temporarily — `phi3` or `mistral` are much faster than large models

---

### ❌ Problem: Can't reach a URL from another device

**Symptoms:** Works on the host machine but not from your phone or another computer

**Fixes:**
1. Make sure both devices are on the **same home network** (same WiFi or LAN)
2. Check if a **firewall** is blocking the port — on Linux: `sudo ufw status`
3. Try using the IP address directly instead of a hostname
4. If using Unraid (Node B), check Unraid's network settings and firewall rules

---

## 9. How to Know Everything Is Working Correctly

You're in good shape when ALL of the following are true:

- ✅ Every URL in the health-check table (Section 3) loads without error
- ✅ Open WebUI shows at least one model in the dropdown
- ✅ Sending a test message in Open WebUI returns a real AI response
- ✅ The Node A Command Center dashboard (`http://192.168.1.6:3099`) shows green status lights
- ✅ LiteLLM dashboard (`http://192.168.1.222:4000/ui`) shows your models as active
- ✅ Home Assistant responds to voice or text questions with AI-generated answers
- ✅ `ollama list` (run on Node C) shows at least one downloaded model

---

## 10. Maintenance Basics

### Checking Logs with Portainer

Portainer is your visual window into all running containers.

1. Open Portainer (typically at `http://<your-node-ip>:9000`)
2. Click **Containers** in the left sidebar
3. Find the container you want to inspect
4. Click its name → click **Logs**
5. You'll see all the output from that container — errors will usually be in red or marked `ERROR`

**Useful tip:** Click **Auto-refresh** to watch logs in real time while you test.

---

### Updating Containers

When a new version of Open WebUI, LiteLLM, or Ollama is released, here's how to update:

**Using Portainer:**
1. Go to **Stacks** (if you deployed via docker-compose/stack) or **Containers**
2. Pull the latest image: click the container → **Recreate** → check "Re-pull image"
3. Click **Recreate** — the container restarts with the latest version

**Using the command line:**
```bash
# Pull the latest image
docker pull ghcr.io/open-webui/open-webui:main

# Restart the container (if using docker-compose)
cd /path/to/your/compose/folder
docker compose pull
docker compose up -d
```

> **Important:** Always check the release notes before updating Open WebUI or LiteLLM — occasionally a new version requires a config change.

---

### Regular Maintenance Tasks

| Task | How Often | How To Do It |
|---|---|---|
| Check container logs for errors | Weekly | Portainer → Containers → Logs |
| Update containers | Monthly | Portainer → Recreate with latest image |
| Check available disk space | Weekly | `df -h` in terminal |
| Back up Open WebUI data | Monthly | Copy the Docker volume or `/data` folder |
| Back up LiteLLM config | After any change | Copy `config.yaml` to a safe place |
| Check Home Assistant AI integration | Weekly | Test a voice command |

---

## 11. Quick-Reference: All Ports and URLs

Bookmark this section! Print it out if you want.

| Service | Node | URL | Notes |
|---|---|---|---|
| Open WebUI (chat interface) | C | `http://192.168.1.6:3000` | Your main AI chat window |
| Command Center Dashboard | C | `http://192.168.1.6:3099` | System status overview |
| OpenClaw Gateway | C | `http://192.168.1.6:18789` | Alternative AI gateway |
| Ollama (Node C) | C | `http://192.168.1.6:11434` | Local model server |
| LiteLLM API | B | `http://192.168.1.222:4000/v1` | AI request switchboard |
| LiteLLM Dashboard | B | `http://192.168.1.222:4000/ui` | Manage models & keys |
| vLLM (Node B) | B | `http://192.168.1.222:8002` | Fast GPU inference |
| vLLM (Node A) | A | `http://192.168.1.9:8000` | Heavy GPU inference |
| Ollama (Node A) | A | `http://192.168.1.9:11435` | Local model server |
| Home Assistant | D | `http://192.168.1.149:8123` | Smart home controller |
| Sentinel Monitoring | E | `http://<sentinel-ip>:3005` | System monitoring |
| Public domain | — | `https://happystrugglebus.us` | External access (if configured) |

### API Credentials Quick Reference

| Service | Key / Credential |
|---|---|
| LiteLLM Master Key | `sk-master-key` |
| Open WebUI → LiteLLM connection | URL: `http://192.168.1.222:4000/v1`, Key: `sk-master-key` |
| Open WebUI → OpenClaw connection | URL: `http://192.168.1.6:18789/v1`, Key: your `OPENCLAW_GATEWAY_TOKEN` |

---

*Last updated for the Grand Unified AI Home Lab stack. For setup instructions, see the earlier numbered guides. For LiteLLM and Open WebUI configuration detail, see `15_LITELLM_OPENWEBUI_USER_GUIDE.md`.*
