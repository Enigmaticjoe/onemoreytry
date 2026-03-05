# OpenClaw + KVM Operator: The Complete Layman's Guide

> Canonical architecture authority: [`docs/ARCHITECTURE_CANONICAL_2026.md`](ARCHITECTURE_CANONICAL_2026.md).


**Who this guide is for:** Anyone who wants to use OpenClaw — an AI command center you host yourself — to chat with AI, run automated tasks, and even control physical computers remotely. No programming background required.

---

## Table of Contents

1. [What Is OpenClaw?](#part-1--what-is-openclaw)
2. [Installing OpenClaw on Node C](#part-2--installing-openclaw-on-node-c)
3. [Connecting OpenClaw to Your AI Models](#part-3--connecting-openclaw-to-your-ai-models)
4. [Skills: Extending What OpenClaw Can Do](#part-4--skills-extending-what-openclaw-can-do)
5. [KVM Operator Setup](#part-5--kvm-operator-setup)
6. [Wiring OpenClaw to the KVM Operator](#part-6--wiring-openclaw-to-the-kvm-operator)
7. [Automating with Webhooks](#part-7--automating-with-webhooks)
8. [Troubleshooting OpenClaw + KVM](#part-8--troubleshooting-openclaw--kvm)

---

## Part 1 — What Is OpenClaw?

### The Short Version

OpenClaw is an AI command center that **you host on your own hardware**. Think of it like having a super-powered AI assistant that lives in your house — not in some company's cloud — and can actually *do things*, not just answer questions.

### The Longer Version

Most AI assistants (ChatGPT, Google Gemini, Amazon Alexa) live on someone else's servers. You send your questions up to the internet, they answer, and your data passes through systems you don't control.

OpenClaw is different. You install it on your own server (in this setup, **Node C at 192.168.1.6**), and it:

- Talks to AI models that also run on your own hardware (or connects to cloud APIs if you choose)
- Keeps your conversations private
- Can **take actions** — not just chat — through a system called "skills"
- Provides a web UI, an API endpoint, and a webhook listener so other systems can trigger it

### What Can OpenClaw Actually Do?

Here's a plain-English list of what you can do with OpenClaw once it's fully set up:

| Task | How OpenClaw Does It |
|------|---------------------|
| Chat with AI | Built-in chat interface, just like ChatGPT |
| Switch between AI models | Type `/model ollama/llama3` to switch on the fly |
| Control virtual machines | KVM skill + KVM Operator (reboot, snapshot, type keystrokes) |
| Deploy Docker stacks | Deploy skill + Portainer integration |
| Receive events from other systems | Webhook endpoint at `/hooks/agent` |
| Act as an OpenAI-compatible API | Any app that talks to OpenAI can talk to OpenClaw instead |
| Run scheduled tasks | Automation skills triggered on a schedule |
| Respond to Home Assistant | HA calls the webhook, OpenClaw acts |

### How Is OpenClaw Different from Open WebUI?

You may already have **Open WebUI** running on Node C at port 3000. Both provide a chat interface to AI models. Here's the difference:

**Open WebUI** is primarily a chat interface. It's great for:
- Browsing and chatting with models
- Image generation
- RAG (chatting with your documents)
- Casual conversation with AI

**OpenClaw** is an action-oriented platform. It's great for:
- Triggering real-world actions (reboot a server, run a script)
- Receiving webhooks from other systems (Home Assistant, Frigate)
- Exposing an API so *other apps* can use your AI
- Running "skills" that give the AI tools to work with
- Acting as the brain behind automation workflows

Think of it this way: **Open WebUI is for humans chatting with AI. OpenClaw is for making AI do things.**

### The Three Ways to Use OpenClaw

#### 1. The Control UI (Browser)

Open a browser and go to:

```
http://192.168.1.6:18789/?token=YOUR_TOKEN
```

Replace `YOUR_TOKEN` with the gateway token you set up during installation (more on that in Part 2). This opens a full chat interface where you can type commands, ask questions, and see OpenClaw's responses.

#### 2. The OpenAI-Compatible API (Port 18789/v1)

If you have an app that can talk to OpenAI's API — anything that accepts a custom API endpoint — you can point it at OpenClaw instead:

```
Base URL: http://192.168.1.6:18789/v1
API Key: YOUR_GATEWAY_TOKEN
```

This means apps like [TypingMind](https://typingmind.com/), [Obsidian](https://obsidian.md/) with AI plugins, or even custom scripts can route through OpenClaw and access all your local models.

#### 3. The Webhook Endpoint (Automation Trigger)

Other systems can send OpenClaw a task to perform:

```
POST http://192.168.1.6:18789/hooks/agent
```

For example, Home Assistant can send: *"Motion detected at front door, take a look"* — and OpenClaw will spring into action, potentially grabbing a screenshot from the KVM, analyzing it with AI, and sending you back a summary.

---

## Part 2 — Installing OpenClaw on Node C

### Before You Start: Prerequisites

Make sure these are already working before you install OpenClaw:

- [ ] **Node C** (192.168.1.6) is powered on and reachable on your network
- [ ] **Ollama** is running on Node C (check: `curl http://192.168.1.6:11434/api/tags`)
- [ ] **Docker** is installed on Node C (`docker --version` should show something)
- [ ] **Docker Compose** is available (`docker compose version`)
- [ ] You can SSH into Node C or access its terminal

### Step 1: Generate a Gateway Token

The gateway token is like a password for OpenClaw. Anyone who has it can use your OpenClaw instance, so keep it private.

Open a terminal on Node C and run:

```bash
openssl rand -hex 32
```

You'll get something like:

```
a3f8c2d1e9b4f6a2c8d3e1f9b2a4c6d8e1f3a5c7d9e2f4a6c8d1e3f5a7c9d2
```

**Copy this value.** You'll need it in a moment. This is your `OPENCLAW_GATEWAY_TOKEN`.

### Step 2: Create the Data Directories

OpenClaw needs a few folders to store its configuration, skills (more on those later), and logs.

```bash
sudo mkdir -p /opt/openclaw/config
sudo mkdir -p /opt/openclaw/workspace
sudo mkdir -p /opt/openclaw/logs

# Give your user ownership so you don't need sudo for everything
sudo chown -R $USER:$USER /opt/openclaw
```

What each folder does:
- `/opt/openclaw/config/` — stores `openclaw.json` (OpenClaw's main settings file)
- `/opt/openclaw/workspace/` — where you place skill files (Markdown files that teach OpenClaw new abilities)
- `/opt/openclaw/logs/` — log files for debugging

### Step 3: Create the OpenClaw Config File

Create the main config file at `/opt/openclaw/config/openclaw.json`:

```bash
nano /opt/openclaw/config/openclaw.json
```

Paste in this configuration:

```json
{
  "name": "OpenClaw",
  "version": "1.0",
  "gateway": {
    "port": 18789,
    "host": "0.0.0.0"
  },
  "defaultModel": "ollama/llama3",
  "models": [
    {
      "id": "ollama/llama3",
      "name": "Llama 3 (Local)",
      "provider": "ollama",
      "baseUrl": "http://host.docker.internal:11434"
    },
    {
      "id": "ollama/llava:latest",
      "name": "LLaVA Vision (Local)",
      "provider": "ollama",
      "baseUrl": "http://host.docker.internal:11434"
    },
    {
      "id": "litellm/brawn-fast",
      "name": "Brawn Fast (RTX 4070)",
      "provider": "litellm",
      "baseUrl": "http://192.168.1.222:4000/v1"
    },
    {
      "id": "litellm/brain-heavy",
      "name": "Brain Heavy (RX 7900 XT)",
      "provider": "litellm",
      "baseUrl": "http://192.168.1.222:4000/v1"
    }
  ],
  "workspace": "/workspace",
  "logging": {
    "level": "info",
    "file": "/logs/openclaw.log"
  }
}
```

Save and close (`Ctrl+X`, then `Y`, then `Enter` in nano).

### Step 4: Create the Environment File

The `.env` file holds secrets (API keys, tokens) that you don't want baked into config files. Create it in the same directory as your docker-compose file for OpenClaw:

```bash
nano /opt/openclaw/.env
```

Fill it in with your values:

```bash
# === OPENCLAW GATEWAY TOKEN ===
# This is your "password" for accessing OpenClaw
# Generate with: openssl rand -hex 32
OPENCLAW_GATEWAY_TOKEN=a3f8c2d1e9b4f6a2c8d3e1f9b2a4c6d8e1f3a5c7d9e2f4a6c8d1e3f5a7c9d2

# === LOCAL AI (OLLAMA) ===
# Ollama doesn't require a key by default, but set one if you've secured it
OLLAMA_API_KEY=

# === LITELLM ON NODE B ===
# The master key you set when installing LiteLLM
LITELLM_API_KEY=sk-master-key

# === KVM OPERATOR (on Node A) ===
# URL of the KVM Operator service
KVM_OPERATOR_URL=http://192.168.1.9:5000
# A shared secret between OpenClaw and KVM Operator
# Generate with: openssl rand -hex 32
KVM_OPERATOR_TOKEN=YOUR_KVM_OPERATOR_TOKEN_HERE

# === OPTIONAL: CLOUD AI KEYS ===
# Only needed if you want to use cloud AI providers
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
GOOGLE_GEMINI_API_KEY=
```

Save the file. **Keep this file private** — don't share it, don't commit it to Git.

### Step 5: The Docker Compose File

The OpenClaw Docker Compose file lives at `node-c-arc/openclaw.yml` in this repository. Here's what it looks like and what each part does:

```yaml
version: "3.8"

services:
  openclaw:
    image: openclaw/openclaw:latest
    container_name: openclaw
    restart: unless-stopped
    ports:
      - "18789:18789"          # The main OpenClaw port
    environment:
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
      - OLLAMA_API_KEY=${OLLAMA_API_KEY}
      - LITELLM_API_KEY=${LITELLM_API_KEY}
      - KVM_OPERATOR_URL=${KVM_OPERATOR_URL}
      - KVM_OPERATOR_TOKEN=${KVM_OPERATOR_TOKEN}
    volumes:
      - /opt/openclaw/config:/config       # Config files
      - /opt/openclaw/workspace:/workspace  # Skills go here
      - /opt/openclaw/logs:/logs           # Log output
      - /var/run/docker.sock:/var/run/docker.sock  # Allows Docker control
    extra_hosts:
      - "host.docker.internal:host-gateway" # Allows reaching Ollama on the host
```

> **Note on `/var/run/docker.sock`:** This mount gives OpenClaw the ability to control Docker containers on Node C. It's required for the Deploy skill. Only mount this if you trust OpenClaw and have your gateway token properly secured.

### Step 6: Start OpenClaw

Navigate to the directory containing `openclaw.yml` and start it:

```bash
cd /home/runner/work/onemoreytry/onemoreytry/node-c-arc
docker compose -f openclaw.yml --env-file /opt/openclaw/.env up -d
```

The `-d` flag means "detached" — it runs in the background.

### Step 7: Verify It's Running

Check that the container started:

```bash
docker ps | grep openclaw
```

You should see something like:

```
abc123def456   openclaw/openclaw:latest   "node dist/index.js"   Up 2 minutes   0.0.0.0:18789->18789/tcp   openclaw
```

Then open your browser and go to:

```
http://192.168.1.6:18789/?token=YOUR_TOKEN
```

Replace `YOUR_TOKEN` with the value of `OPENCLAW_GATEWAY_TOKEN` from your `.env` file.

You should see the OpenClaw chat interface. If you do — congratulations, OpenClaw is running!

### Checking the Logs

If something isn't right, check the logs:

```bash
docker logs openclaw --tail 50
```

Or view the log file directly:

```bash
tail -f /opt/openclaw/logs/openclaw.log
```

---

## Part 3 — Connecting OpenClaw to Your AI Models

### How Models Work in OpenClaw

OpenClaw doesn't run AI models itself — it connects to AI model servers and forwards your messages to them. Think of OpenClaw as a smart receptionist that knows how to talk to many different AI services.

You configure models in `/opt/openclaw/config/openclaw.json` (which you already did in Part 2). Here's a deeper look at each option.

### Option A: Local Ollama (Already Configured)

Ollama runs directly on Node C at port 11434. Since OpenClaw runs in Docker, it reaches Ollama via the special address `host.docker.internal` — this is Docker's way of saying "the computer I'm running on."

Your config already includes:

```json
{
  "id": "ollama/llama3",
  "provider": "ollama",
  "baseUrl": "http://host.docker.internal:11434"
}
```

**To list available Ollama models:**

```bash
curl http://192.168.1.6:11434/api/tags
```

You'll see a JSON list of all models you've pulled. Common ones in this setup:
- `llama3` — fast, general purpose
- `llava:latest` — can look at images (vision model)
- `codellama` — great for programming questions
- `mistral` — good balance of speed and quality

**To pull a new model (on Node C):**

```bash
docker exec -it ollama ollama pull llama3:8b
```

Once pulled, add it to `openclaw.json` if you want to be able to switch to it by name.

### Option B: LiteLLM on Node B (Brain-Heavy + Brawn-Fast)

Node B at 192.168.1.222 runs LiteLLM, which is a proxy that sits in front of multiple AI models. This is where the RTX 4070 lives.

LiteLLM gives you two named models in this setup:

- **brawn-fast** — runs on the RTX 4070, fast responses, good for most things
- **brain-heavy** — routes to Node A's RX 7900 XT, slower but more capable for complex reasoning

To use these, your `openclaw.json` already has:

```json
{
  "id": "litellm/brawn-fast",
  "provider": "litellm",
  "baseUrl": "http://192.168.1.222:4000/v1"
}
```

And the `LITELLM_API_KEY=sk-master-key` in your `.env` handles authentication.

**To test LiteLLM directly:**

```bash
curl http://192.168.1.222:4000/v1/models \
  -H "Authorization: Bearer sk-master-key"
```

This returns a list of all models LiteLLM knows about.

### Option C: Cloud AI Providers (Optional)

If you want to use Anthropic Claude, OpenAI GPT-4, or Google Gemini, add their API keys to your `.env` file:

```bash
ANTHROPIC_API_KEY=sk-ant-api03-YOUR-KEY-HERE
OPENAI_API_KEY=sk-YOUR-OPENAI-KEY
GOOGLE_GEMINI_API_KEY=YOUR-GEMINI-KEY
```

Then add them to `openclaw.json`:

```json
{
  "id": "anthropic/claude-3-5-sonnet-20241022",
  "name": "Claude 3.5 Sonnet",
  "provider": "anthropic"
},
{
  "id": "openai/gpt-4o",
  "name": "GPT-4o",
  "provider": "openai"
},
{
  "id": "google/gemini-1.5-pro",
  "name": "Gemini 1.5 Pro",
  "provider": "google"
}
```

After editing the config, restart OpenClaw:

```bash
docker compose -f node-c-arc/openclaw.yml restart
```

### Switching Models in Chat

In the OpenClaw chat UI, you can switch models mid-conversation with the `/model` command:

```
/model ollama/llama3
```

or

```
/model litellm/brawn-fast
```

### Testing the Vision Model

The `llava:latest` model can look at images. Here's a fun test:

1. In OpenClaw chat, type: `/model ollama/llava:latest`
2. You should see confirmation that the model switched
3. Upload an image (drag and drop, or click the attachment icon)
4. Type: `What do you see in this image? Describe it in detail.`

LLaVA will describe the contents of the image. This is the same capability that powers the AI camera analysis pipeline (more on that in the Frigate guide).

---

## Part 4 — Skills: Extending What OpenClaw Can Do

### What Are Skills?

Skills are **Markdown files** (`.md` files — plain text with simple formatting) that teach OpenClaw new abilities. When OpenClaw reads a skill file, it gains new context about what it can do and how to do it.

Think of it like giving a new employee a procedures manual. The manual tells them: "When someone asks you to restart a server, here's exactly how you do it and what you need to say."

Skills live in `/opt/openclaw/workspace/`. OpenClaw automatically scans this directory and loads any `.md` files it finds at the start of each conversation.

### The KVM Skill (skill-kvm.md)

The KVM skill teaches OpenClaw how to control virtual machines through the KVM Operator. Once loaded, you can literally say "Restart the Windows VM" and OpenClaw knows how to make it happen.

**Installing the KVM Skill:**

The skill file lives at `openclaw/skill-kvm.md` in this repository. Copy it to the workspace:

```bash
cp /home/runner/work/onemoreytry/onemoreytry/openclaw/skill-kvm.md \
   /opt/openclaw/workspace/skill-kvm.md
```

OpenClaw will load it automatically on the next conversation turn. No restart required.

**What the KVM Skill Enables:**

Once the KVM skill is loaded, you can ask OpenClaw things like:

- *"What VMs are running on Proxmox right now?"*
- *"Power on the Windows VM"*
- *"Restart the Blue Iris server"*
- *"Take a screenshot of the Windows VM desktop"*
- *"Type 'ipconfig' in the command prompt on Windows"*
- *"What is the power status of my NAS?"*

Each of these requests is routed through the KVM Operator (on Node A at port 5000) which handles the actual execution — with your approval, because `REQUIRE_APPROVAL=true` is on by default (more on that in Part 5).

**What the KVM Skill File Contains:**

The skill-kvm.md file tells OpenClaw:

1. The KVM Operator is available at the URL stored in `KVM_OPERATOR_URL`
2. It can make API calls to endpoints like `/vm/list`, `/vm/power`, `/vm/screenshot`, `/vm/keypress`
3. For destructive actions (like power off), it must always request approval first
4. How to format the API requests
5. How to interpret the responses and explain them to the user

### The Deploy Skill (skill-deploy.md)

The Deploy skill gives OpenClaw the ability to manage Docker stacks through Portainer.

```bash
cp /home/runner/work/onemoreytry/onemoreytry/openclaw/skill-deploy.md \
   /opt/openclaw/workspace/skill-deploy.md
```

With the Deploy skill loaded, you can say:

- *"Deploy the LiteLLM stack on Node B"*
- *"Restart the Open WebUI container"*
- *"Show me all running Docker stacks"*
- *"Update the Ollama container to the latest image"*

### Installing Skills from ClawhHub

ClawhHub is OpenClaw's skill marketplace (think of it like an app store for AI skills). To install a skill from ClawhHub:

```bash
# Get a shell in the OpenClaw container
docker exec -it openclaw sh

# Install a skill by name
node dist/index.js skills install weather-checker
node dist/index.js skills install home-assistant-controller
node dist/index.js skills install file-manager

# List installed skills
node dist/index.js skills list

# Exit the container
exit
```

Installed skills are automatically placed in the workspace directory.

### Writing Your Own Skill

You can write a custom skill — it's just a Markdown file! Here's the basic structure:

```markdown
# Skill: Your Skill Name

## Purpose
A plain English description of what this skill does.

## Capabilities
- List of things this skill allows you to do

## Instructions
When the user asks you to [do something], you should:
1. Step one
2. Step two
3. Respond with: [what to say back]

## API Endpoints (if applicable)
- GET /your-endpoint — description
- POST /your-endpoint — description, expected body

## Examples
User: "Do the thing"
Assistant: [calls endpoint, returns result]
```

Save it as `/opt/openclaw/workspace/skill-yourname.md` and it'll be loaded automatically.

### Three Example Skills You Could Build

#### Example Skill 1: Weather Checker

```markdown
# Skill: Weather Checker

## Purpose
Check current weather conditions using Open-Meteo (no API key required).

## Instructions
When the user asks about the weather:
1. Call GET https://api.open-meteo.com/v1/forecast?latitude=YOUR_LAT&longitude=YOUR_LON&current_weather=true
2. Parse the temperature_2m and weathercode fields
3. Respond: "It's currently X°F and [description]."

## Weather Codes
0 = Clear sky, 1-3 = Partly cloudy, 61-65 = Rain, 71-75 = Snow, 95 = Thunderstorm
```

#### Example Skill 2: Home Assistant Controller

```markdown
# Skill: Home Assistant Controller

## Purpose
Control smart home devices via Home Assistant REST API.

## Base URL
http://192.168.1.149:8123/api

## Auth Header
Authorization: Bearer YOUR_HA_LONG_LIVED_TOKEN

## Instructions
- To turn on a light: POST /services/light/turn_on {"entity_id": "light.ENTITY_NAME"}
- To turn off a light: POST /services/light/turn_off {"entity_id": "light.ENTITY_NAME"}
- To check a sensor: GET /states/sensor.ENTITY_NAME
- To list all entities: GET /states

When the user asks to control a device, find the matching entity and call the appropriate service.
```

#### Example Skill 3: File Manager

```markdown
# Skill: File Manager

## Purpose
Read, list, and summarize files in the workspace directory.

## Instructions
- To list files: call the filesystem tool with path="/workspace"
- To read a file: call the filesystem tool with path="/workspace/filename.txt"
- To summarize a document: read it first, then provide a 3-sentence summary
- Never delete files without explicit user confirmation

## Safety Rules
- Only operate within /workspace — never access /config or system directories
- Ask "Are you sure?" before any write or delete operation
```

---

## Part 5 — KVM Operator Setup

### What Is KVM? (Plain English)

KVM stands for "Kernel-based Virtual Machine." But you don't need to understand that to use it.

Here's the simple version: **KVM is remote control for your computers**, even if they have no monitor plugged in, no keyboard attached, and no operating system loaded yet.

Normally, to control a computer remotely you need:
- The computer to be powered on
- The operating system to be running
- A network connection and software like SSH or Remote Desktop

But what if the computer is frozen? Or won't boot? Or needs you to press F2 at startup to change BIOS settings? You'd normally have to physically walk to the machine.

**KVM solves this.** It lets you see the screen and send keyboard/mouse input to a computer at the hardware level — before the OS even loads.

### What Is NanoKVM?

NanoKVM is a small, inexpensive device (about the size of a USB dongle) that you physically connect to a computer. It provides:

- **Video capture** — it sees what's on the screen via HDMI
- **Virtual keyboard** — it can type keystrokes as if you were pressing keys
- **Virtual mouse** — it can move the cursor and click
- **Power control** — it can power on/off the machine (with the right wiring)

In this setup, NanoKVM is connected to your Proxmox server (or individual machines), and the **KVM Operator** software provides an API on top of it so that OpenClaw can send commands.

### Installing the KVM Operator on Node A

The KVM Operator is a Python service that runs on Node A (192.168.1.9).

#### Option A: Run Directly with Python

SSH into Node A first:

```bash
ssh user@192.168.1.9
```

Then:

```bash
# Navigate to the kvm-operator directory
cd /home/runner/work/onemoreytry/onemoreytry/kvm-operator

# Install Python dependencies
pip install -r requirements.txt

# Start the service
./run_dev.sh
```

The service will start on port 5000. You'll see:

```
INFO:     Started server process [12345]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:5000 (Press CTRL+C to quit)
```

#### Option B: Run with Docker

```bash
cd /home/runner/work/onemoreytry/onemoreytry/kvm-operator
docker compose up -d
```

#### Verifying It Works

Open your browser and go to:

```
http://192.168.1.9:5000/docs
```

This opens the **interactive API documentation** (Swagger UI). You can see all available endpoints and even test them directly from your browser. If this page loads, the KVM Operator is running correctly.

### The .env File for KVM Operator

The KVM Operator needs to know how to connect to your NanoKVM device and what security settings to use. Copy the example file and fill it in:

```bash
cd kvm-operator
cp .env.example .env
nano .env
```

Here's what each setting does:

```bash
# === SECURITY ===
# The secret key used to sign authentication tokens
# Generate with: openssl rand -hex 32
SECRET_KEY=your-very-long-random-secret-key

# Should humans approve actions before they execute?
# ALWAYS leave this as true unless you really know what you're doing
REQUIRE_APPROVAL=true

# === NANOKVM CONNECTION ===
# The IP address of your NanoKVM device
KVM_HOST=192.168.1.200

# The authentication token for your NanoKVM device
KVM_TOKEN=your-nanokvm-token

# === API SECURITY ===
# This token must be provided by clients (like OpenClaw) to use the API
# Generate with: openssl rand -hex 32
API_SECRET_KEY=your-kvm-operator-api-key
```

After editing, restart the service.

### REQUIRE_APPROVAL=true — The Safety Gate

This is the most important setting in the entire KVM Operator. **Always keep it set to `true`.**

Here's why: The KVM Operator can send keystrokes to any connected computer. Without approval, an AI hallucination or a crafty prompt could theoretically cause the AI to type `format c:` or `rm -rf /` on a real machine.

With `REQUIRE_APPROVAL=true`, the workflow is:

1. OpenClaw asks the KVM Operator to do something
2. The KVM Operator records the request as "pending"
3. **You** see the pending request at `http://192.168.1.9:5000/approve`
4. **You** click Approve or Deny
5. Only after your approval does the action execute

This keeps a human in the loop for anything that touches real hardware.

### The Policy Denylist (policy_denylist.txt)

The denylist is a list of commands that are **always blocked**, even if you approve them. It's a safety net to catch obviously dangerous commands.

The file lives at `kvm-operator/policy_denylist.txt`. Example contents:

```
format c:
rm -rf /
dd if=/dev/zero
mkfs
fdisk
shutdown -h now
del /f /s /q c:\
```

If OpenClaw tries to execute any command containing these strings, the KVM Operator will reject it immediately without even showing it to you for approval.

To add your own blocked commands:

```bash
nano kvm-operator/policy_denylist.txt
```

Add one command pattern per line. Patterns are checked as substrings (if any line in the denylist appears inside the requested command, it's blocked).

---

## Part 6 — Wiring OpenClaw to the KVM Operator

Now we connect everything together. OpenClaw (on Node C) will be able to send commands to the KVM Operator (on Node A), which will control your physical and virtual machines via NanoKVM.

### Step 1: Configure OpenClaw's .env

Make sure these lines are in `/opt/openclaw/.env`:

```bash
KVM_OPERATOR_URL=http://192.168.1.9:5000
KVM_OPERATOR_TOKEN=your-kvm-operator-api-key
```

The `KVM_OPERATOR_TOKEN` must match the `API_SECRET_KEY` in the KVM Operator's `.env` file.

### Step 2: Install the KVM Skill

```bash
cp /home/runner/work/onemoreytry/onemoreytry/openclaw/skill-kvm.md \
   /opt/openclaw/workspace/skill-kvm.md
```

Verify it's there:

```bash
ls /opt/openclaw/workspace/
```

### Step 3: Restart OpenClaw

```bash
cd /home/runner/work/onemoreytry/onemoreytry/node-c-arc
docker compose -f openclaw.yml restart
```

### Step 4: Test the Connection

Open the OpenClaw chat UI at `http://192.168.1.6:18789/?token=YOUR_TOKEN` and type:

```
What is the power status of my Windows VM?
```

What should happen:
1. OpenClaw reads the KVM skill
2. It sends a request to `http://192.168.1.9:5000/vm/status`
3. The KVM Operator returns the status of your VMs
4. OpenClaw presents this in plain English: "Your Windows VM is currently powered on and running."

If `REQUIRE_APPROVAL=true` is set for read operations (some setups require it for everything), you'll need to approve it first.

### Example: Restarting a VM Through OpenClaw

Here's a real example of the full workflow:

**You type in OpenClaw:**
```
Restart the Windows VM on Proxmox
```

**OpenClaw responds:**
```
I'll restart the Windows VM for you. Let me send that request to the KVM Operator.

⚠️ Action requested: Restart VM "windows-10" on Proxmox host 192.168.1.174
Status: Waiting for approval at http://192.168.1.9:5000/approve
```

**You go to the approval page:**

```
http://192.168.1.9:5000/approve
```

You'll see a card showing:
- **Action:** Restart VM
- **Target:** windows-10
- **Requested by:** OpenClaw
- **Time:** 2 minutes ago
- **[Approve]** **[Deny]** buttons

**You click Approve.**

**The KVM Operator executes the restart and reports back to OpenClaw.**

**OpenClaw reports to you:**
```
✅ The Windows VM has been restarted successfully. 
It took approximately 45 seconds to complete the restart cycle.
```

### The Approval Page in Detail

The approval page at `http://192.168.1.9:5000/approve` shows:

- All **pending** actions (awaiting your decision)
- All **completed** actions (with their outcomes)
- All **denied** actions (what you blocked)

You can also approve/deny via API, which is useful for Home Assistant automations:

```bash
# Approve action with ID 42
curl -X POST http://192.168.1.9:5000/approve/42 \
  -H "X-API-Key: your-kvm-operator-api-key"

# Deny action with ID 42
curl -X POST http://192.168.1.9:5000/deny/42 \
  -H "X-API-Key: your-kvm-operator-api-key"
```

---

## Part 7 — Automating with Webhooks

OpenClaw has a webhook endpoint at `POST /hooks/agent`. Any system that can make an HTTP POST request can trigger OpenClaw to take action.

### Triggering OpenClaw from Home Assistant

In Home Assistant, you can use `shell_command` or `rest_command` to POST to OpenClaw.

#### Using rest_command in configuration.yaml:

```yaml
rest_command:
  ask_openclaw:
    url: "http://192.168.1.6:18789/hooks/agent"
    method: POST
    headers:
      Authorization: "Bearer YOUR_GATEWAY_TOKEN"
      Content-Type: "application/json"
    payload: '{"prompt": "{{ message }}", "model": "ollama/llama3"}'
```

#### Using it in an automation:

```yaml
automation:
  - alias: "Motion Alert - AI Analysis"
    trigger:
      - platform: state
        entity_id: binary_sensor.front_door_motion
        to: "on"
    action:
      - service: rest_command.ask_openclaw
        data:
          message: >
            Motion was detected at the front door. 
            Check the KVM for any camera feeds if available and describe what you see.
            This triggered at {{ now().strftime('%I:%M %p') }}.
```

### Triggering from Frigate (Camera Events)

Frigate can send webhooks when it detects objects. Configure this in Frigate's `config.yml`:

```yaml
# In Frigate config.yml
notifications:
  webhook:
    enabled: true
    url: http://192.168.1.6:18789/hooks/agent
    headers:
      Authorization: "Bearer YOUR_GATEWAY_TOKEN"
    payload:
      prompt: "Frigate detected a {{ label }} at {{ camera }} with {{ score }}% confidence. Timestamp: {{ timestamp }}. Should I alert the homeowner?"
```

When Frigate spots a person, it sends that payload to OpenClaw, which can then decide to notify you through Home Assistant or take other action.

### Triggering from Unraid User Scripts

If you use Unraid on Node B, you can add User Scripts that call OpenClaw:

```bash
#!/bin/bash
# Daily backup completion notification via OpenClaw
curl -X POST http://192.168.1.6:18789/hooks/agent \
  -H "Authorization: Bearer YOUR_GATEWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "The nightly backup completed at '"$(date)"'. Disk usage is '"$(df -h /mnt/cache | tail -1 | awk '"'"'{print $5}'"'"')"'. Generate a one-sentence summary for the homeowner.",
    "model": "ollama/llama3"
  }'
```

### The "Good Morning" Automation

Here's a complete example of a Good Morning automation that uses OpenClaw to brief you on the day:

#### In Home Assistant (configuration.yaml):

```yaml
rest_command:
  good_morning_briefing:
    url: "http://192.168.1.6:18789/hooks/agent"
    method: POST
    headers:
      Authorization: "Bearer YOUR_GATEWAY_TOKEN"
      Content-Type: "application/json"
    payload: >
      {
        "prompt": "Give me a good morning briefing. Today is {{ now().strftime('%A, %B %d, %Y') }}. 
        It is {{ states('sensor.outdoor_temperature') }}°F outside. 
        I have {{ states('calendar.personal') | default('no events') }} today. 
        Keep it under 3 sentences and be cheerful.",
        "model": "litellm/brawn-fast",
        "webhook_response": true
      }
```

#### The automation trigger:

```yaml
automation:
  - alias: "Good Morning Briefing"
    trigger:
      - platform: time
        at: "07:30:00"
    condition:
      - condition: time
        weekday:
          - mon
          - tue
          - wed
          - thu
          - fri
    action:
      - service: rest_command.good_morning_briefing
      - delay: "00:00:03"
      - service: tts.speak
        data:
          entity_id: media_player.living_room_speaker
          message: "{{ states('input_text.openclaw_last_response') }}"
```

### Example Webhook Payload

Here's exactly what an OpenClaw webhook payload looks like:

**Request (what you send):**
```json
POST http://192.168.1.6:18789/hooks/agent
Authorization: Bearer YOUR_GATEWAY_TOKEN
Content-Type: application/json

{
  "prompt": "What is the current status of all VMs on Proxmox?",
  "model": "ollama/llama3",
  "context": {
    "source": "home_assistant",
    "triggered_by": "button.check_vm_status"
  }
}
```

**Response (what you get back):**
```json
{
  "id": "resp_abc123",
  "status": "completed",
  "response": "Here are the current VM statuses on your Proxmox server...",
  "model_used": "ollama/llama3",
  "duration_ms": 1842,
  "actions_taken": []
}
```

---

## Part 8 — Troubleshooting OpenClaw + KVM

### Problem: OpenClaw Won't Start

**Symptom:** `docker compose -f openclaw.yml up -d` shows an error, or the container exits immediately.

**Check 1: Config file error**

```bash
docker logs openclaw 2>&1 | head -30
```

Look for messages like `Error: config key 'models' is required` — this means your `openclaw.json` has a syntax error or missing field.

**Fix:** Validate your JSON:

```bash
python3 -c "import json; json.load(open('/opt/openclaw/config/openclaw.json')); print('JSON is valid')"
```

If it prints `JSON is valid`, the file is fine. If it shows an error, there's a typo (usually a missing comma or quote).

**Check 2: Token not set**

```bash
docker logs openclaw 2>&1 | grep -i "token"
```

If you see `OPENCLAW_GATEWAY_TOKEN is not set`, your `.env` file isn't being read.

**Fix:** Make sure you're using `--env-file`:

```bash
docker compose -f openclaw.yml --env-file /opt/openclaw/.env up -d
```

**Check 3: Port already in use**

```bash
sudo lsof -i :18789
```

If something else is on port 18789, either stop it or change OpenClaw's port in `openclaw.json`.

### Problem: Can't Connect to Ollama

**Symptom:** OpenClaw chat shows "Error connecting to Ollama" or model responses time out.

**Check:** Can OpenClaw reach Ollama from inside the container?

```bash
docker exec -it openclaw curl http://host.docker.internal:11434/api/tags
```

If this fails, `host.docker.internal` isn't resolving. This usually means the Docker network isn't configured correctly.

**Fix:** Make sure `extra_hosts` is in your docker-compose file:

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

If that's already there, try using the Node C IP directly:

```bash
docker exec -it openclaw curl http://192.168.1.6:11434/api/tags
```

If this works, change `host.docker.internal` to `192.168.1.6` in your `openclaw.json`.

### Problem: KVM Operator Unreachable

**Symptom:** OpenClaw says "Cannot connect to KVM Operator at http://192.168.1.9:5000"

**Check 1: Is the KVM Operator running on Node A?**

From any machine on your network:

```bash
curl http://192.168.1.9:5000/health
```

If this times out or gives a connection refused error, the KVM Operator isn't running.

**Fix:** SSH into Node A and start it:

```bash
ssh user@192.168.1.9
cd /home/runner/work/onemoreytry/onemoreytry/kvm-operator
./run_dev.sh
```

**Check 2: Firewall blocking the connection**

From Node C, test connectivity to Node A's port 5000:

```bash
nc -zv 192.168.1.9 5000
```

If it shows `Connection refused`, the firewall on Node A may be blocking port 5000.

**Fix on Node A (if using ufw):**

```bash
sudo ufw allow 5000/tcp
```

**Check 3: Token mismatch**

The `KVM_OPERATOR_TOKEN` in OpenClaw's `.env` must exactly match `API_SECRET_KEY` in the KVM Operator's `.env`.

Double-check both files and make sure they're identical (including capitalization).

### Problem: Approval Page Shows Nothing

**Symptom:** You go to `http://192.168.1.9:5000/approve` but there are no pending actions.

**Possible cause 1: No actions have been requested yet.** OpenClaw hasn't sent any KVM commands. Try asking OpenClaw to check VM status.

**Possible cause 2: `REQUIRE_APPROVAL=false`** — the KVM Operator is executing actions without showing them for approval. Check your `.env` file.

**Possible cause 3: Token mismatch** — OpenClaw's requests are being rejected by the KVM Operator before they even create pending actions. Check the KVM Operator logs:

```bash
docker logs kvm-operator --tail 20
# or
tail -f kvm-operator/logs/app.log
```

Look for `401 Unauthorized` or `403 Forbidden` errors.

### Problem: Skill Not Loading

**Symptom:** You ask OpenClaw to restart a VM but it says it doesn't know how to do that, even though you installed the KVM skill.

**Check 1: File is in the right place**

```bash
ls -la /opt/openclaw/workspace/
```

You should see `skill-kvm.md` listed. If it's not there, copy it again:

```bash
cp openclaw/skill-kvm.md /opt/openclaw/workspace/
```

**Check 2: File has the right extension**

Skills must end in `.md` (not `.txt`, not `.MD`). Check carefully.

**Check 3: Markdown syntax error**

If the skill file has a severe syntax issue, OpenClaw may skip it. Try a simpler skill first to verify the workspace is working:

```bash
cat > /opt/openclaw/workspace/test-skill.md << 'EOF'
# Skill: Test

## Purpose
This is a test skill to verify skill loading works.

## Instructions
When asked "skill test", respond with "Skills are working!"
EOF
```

Then ask OpenClaw: "skill test". If it responds correctly, the workspace is fine and the issue is in your skill file content.

**Check 4: Container restart may be needed**

While skills *should* load without restart, sometimes a restart forces a fresh scan:

```bash
docker restart openclaw
```

---

*End of OpenClaw + KVM Operator Guide. For questions about specific OpenClaw skill development, see the ClawhHub documentation. For KVM Operator API reference, visit `http://192.168.1.9:5000/docs` when the service is running.*
