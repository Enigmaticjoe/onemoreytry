# 🛠️ Apps & Services Configuration Guide
## Fresh Rebuild 2026 — Making Everything Actually *Work*

> **You made it!** Your containers are running. That was the hard part. Now it's time to sit down at your computer with a cup of tea and actually *configure* each service so it does something useful. This guide walks you through every app, one screen at a time.

---

## Table of Contents

- [Introduction: You're Already Running — Now Configure](#introduction-youre-already-running--now-configure)
- [Chapter 1: Portainer — Your Container Control Panel](#chapter-1-portainer--your-container-control-panel)
- [Chapter 2: Homepage — Your Unified Dashboard](#chapter-2-homepage--your-unified-dashboard)
- [Chapter 3: Ollama — Your AI Model Server](#chapter-3-ollama--your-ai-model-server)
- [Chapter 4: Open WebUI — Your AI Chat Interface](#chapter-4-open-webui--your-ai-chat-interface)
- [Chapter 5: n8n — Your Automation Hub](#chapter-5-n8n--your-automation-hub)
- [Chapter 6: Uptime Kuma — Service Monitoring](#chapter-6-uptime-kuma--service-monitoring)
- [Chapter 7: Dozzle — Reading Container Logs](#chapter-7-dozzle--reading-container-logs)
- [Chapter 8: Watchtower — Automatic Updates](#chapter-8-watchtower--automatic-updates)
- [Chapter 9: Home Assistant + Ollama — Your Smart Home Talks to AI](#chapter-9-home-assistant--ollama--your-smart-home-talks-to-ai)
- [Appendix: Quick Reference](#appendix-quick-reference)

---

# Introduction: You're Already Running — Now Configure

So the NODE_SETUP_GUIDE.md brought you here. You ran `docker compose up -d`, watched a wall of green text scroll past, and confirmed your containers are alive. That's genuinely impressive — well done!

But there's a difference between **deployed** and **configured**. Right now your containers are *deployed* — they're running, they're waiting, they're ready. But they don't know your preferences yet. They haven't been told which AI models to serve. Nobody has set up a login. Nothing is connected to anything else.

Think of it like this: your oven is on. The pilot light is lit, the power is flowing, the oven is definitely "running." But you haven't set the temperature for your recipe yet. You haven't preheated it. You haven't put the tray on the right rack. The oven being *on* and the oven being *ready to cook your specific dish* are two different things. This guide gets you from "oven is on" to "dinner is ready."

Work through each chapter in order — later chapters (like Open WebUI and n8n) depend on earlier ones (like Ollama being loaded with models). The whole journey takes about two hours on a relaxed afternoon.

---

# Chapter 1: Portainer — Your Container Control Panel

**🌐 URL: `http://192.168.1.222:9000`**

---

## What This Does for You

Portainer is a visual dashboard for managing your Docker containers. Without it, the only way to start, stop, or check on a container is to type commands into a terminal — which gets old fast. With Portainer, you can click a button to stop a container, read its logs, or see how much RAM it's using, all from a web page in your browser.

The best analogy: think of Docker as a TV with all the buttons hidden on the back. Portainer is the remote control. You don't need to reach around behind the TV anymore.

---

## First-Time Setup

1. Open your browser and go to **`http://192.168.1.222:9000`**.

2. You'll land on a setup screen with a form asking you to create the initial administrator account. This only appears once.

3. In the **Username** field, type:
   ```
   admin
   ```

4. In the **Password** field, choose something strong. At least 12 characters with a mix of uppercase, lowercase, numbers, and a symbol. A good trick is to use a phrase:
   ```
   MyLabIs$ecure2026!
   ```
   💡 **Tip:** Write this password down somewhere safe — a physical notebook, a password manager, or a sticky note on the back of your monitor. If you lose it, recovery is painful (see Troubleshooting below).

5. Type the same password in the **Confirm password** field.

6. Click the big blue **"Create user"** button.

7. ✅ You should land on the **Home** screen showing a card labelled **"local"** — this represents Node B's Docker environment. If you see this card, setup was successful.

---

## Understanding the Portainer Interface

When you click into the **local** environment, you'll see the main Portainer dashboard. Here's what each section in the left sidebar means:

| Sidebar Item | What It Is |
|---|---|
| **Dashboard** | Overview — how many containers, images, volumes exist |
| **Containers** | The list of all your running (and stopped) containers |
| **Images** | The downloaded Docker images on this machine |
| **Volumes** | The persistent data folders attached to containers |
| **Networks** | The virtual networks containers talk to each other through |
| **Stacks** | Entire compose files managed as one unit |

Most of your day-to-day use will be in **Containers** and **Stacks**.

💡 **What does "local" mean?** When Portainer says "local environment," it means it's managing the Docker engine running on Node B (192.168.1.222) — the same machine Portainer itself is running on. You can add remote nodes too, which we'll do next.

---

## Connecting Node A as a Remote Environment

Portainer can manage Node A's containers from this same dashboard — no need to SSH in separately.

1. In the left sidebar, click **Environments**.
2. Click the orange **"Add environment"** button in the top-right corner.
3. On the next screen, click the **"Agent"** option (it looks like a plug icon). The Portainer Agent is already running on Node A as part of your deployment.
4. Fill in the form:
   - **Name:** `Node A`
   - **Environment URL:** `192.168.1.9:9001`
5. Leave all other settings at their defaults.
6. Click **"Add environment"** at the bottom of the form.
7. ✅ You should now see a card for **Node A** alongside the **local** card on the Home screen. Click it and you'll see Node A's containers listed — just like you can for Node B.

---

## Connecting Node C as a Remote Environment

Node C (Open WebUI's host at 192.168.1.6) can also be connected the same way — *if* a Portainer Agent container is running there.

⚠️ **Note:** The Phase 1 setup for Node C focuses only on Open WebUI. A Portainer Agent is not deployed there by default. If you'd like to manage Node C from Portainer, SSH into Node C and run:
```bash
docker run -d \
  -p 9001:9001 \
  --name portainer-agent \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/lib/docker/volumes:/var/lib/docker/volumes \
  portainer/agent:latest
```
Then follow the same **Add environment** steps above using URL `192.168.1.6:9001`.

---

## Daily Use — What You'll Actually Do in Portainer

**View all running containers:**
1. Click **local** (or **Node A**) on the Home screen.
2. Click **Containers** in the left sidebar.
3. You'll see a table listing every container — name, status (green = running, grey = stopped), creation time, and ports.

**Start or stop a container with a click:**
1. In the Containers list, tick the checkbox next to the container name.
2. Use the **Start**, **Stop**, or **Restart** buttons that appear at the top of the table.

**View a container's logs:**
1. Click the container's name to open its detail page.
2. Click the **Logs** tab at the top.
3. Logs stream in real time. Use the search box to filter for specific text (e.g., "error").

**Restart a stuck container:**
1. Find it in the Containers list.
2. Tick its checkbox.
3. Click **Restart**. Portainer stops it and starts it again automatically.

**Check CPU and RAM usage:**
1. Click the container's name to open its detail page.
2. Click the **Stats** tab.
3. You'll see live graphs for CPU %, memory usage, and network I/O.

---

## Troubleshooting

**"Portainer won't load at all"**
SSH into Node B and check if the container is actually running:
```bash
ssh root@192.168.1.222
docker ps | grep portainer
```
Expected output — you should see a line with `portainer/portainer-ce` and the status `Up X hours`. If the line is missing, start it:
```bash
docker start portainer
```

**"I typed the wrong password and now I'm locked out"**
The only recovery is to delete Portainer's data volume and start fresh (you'll lose Portainer's settings, but your actual containers are unaffected):
```bash
docker stop portainer
docker rm portainer
docker volume rm portainer_data
```
Then re-run your infra compose stack to recreate Portainer fresh, and repeat the First-Time Setup above.

**"Node A shows as 'down' in Portainer"**
Check the Portainer Agent is running on Node A:
```bash
ssh your-username@192.168.1.9
docker ps | grep portainer-agent
```
If it's not listed, check that the Node A compose stack is running.

---

# Chapter 2: Homepage — Your Unified Dashboard

**🌐 URL: `http://192.168.1.222:8010`**

---

## What This Does for You

Homepage is your homelab's start page. Instead of keeping a list of bookmarks for nine different services, you have one beautiful page with a tile for each app. Each tile shows the service name, a description, an icon, and a link — click it to open the service. With a little extra configuration, tiles can also show live data like "Ollama is serving 2 models" or "Uptime Kuma: all systems green."

Think of it as the lobby of your homelab hotel — every room (service) is reachable from here.

---

## Understanding the Default Page

When you first visit `http://192.168.1.222:8010`, you'll see a mostly empty page — probably just a title or a generic placeholder. That's completely normal. Homepage reads its layout and service list from YAML configuration files stored at `/mnt/user/appdata/homepage/config/` on Node B. Right now those files are either missing or contain only the defaults.

⚠️ **YAML is indentation-sensitive.** This means spaces matter. Use exactly 4 spaces (not tabs) for each level of indentation. The examples below are correct — copy them carefully.

---

## Adding Your Services to the Dashboard

You'll create two files: `services.yaml` (your tiles) and `settings.yaml` (appearance). There are two ways to do this.

### Method 1: Via SSH (Recommended)

1. Open a terminal on your laptop and SSH into Node B:
   ```bash
   ssh root@192.168.1.222
   ```

2. Navigate to the Homepage config folder:
   ```bash
   cd /mnt/user/appdata/homepage/config
   ```

3. Create the services file. Copy and paste this entire block:
   ```bash
   cat > services.yaml << 'EOF'
   - AI Services:
       - Open WebUI:
           href: http://192.168.1.6:3000
           description: Private AI chat interface
           icon: openai.png
       - Ollama (Node B):
           href: http://192.168.1.222:11434
           description: CUDA AI inference engine
           icon: ollama.png
       - Ollama (Node A):
           href: http://192.168.1.9:11435
           description: ROCm AI inference engine
           icon: ollama.png

   - Management:
       - Portainer:
           href: http://192.168.1.222:9000
           description: Container manager
           icon: portainer.png
       - n8n:
           href: http://192.168.1.222:5678
           description: Workflow automation
           icon: n8n.png
       - Uptime Kuma:
           href: http://192.168.1.222:3010
           description: Service monitoring
           icon: uptime-kuma.png
       - Dozzle:
           href: http://192.168.1.222:8888
           description: Live container logs
           icon: dozzle.png

   - Smart Home:
       - Home Assistant:
           href: http://192.168.1.149:8123
           description: Smart home controller
           icon: home-assistant.png
   EOF
   ```

4. Create the settings file:
   ```bash
   cat > settings.yaml << 'EOF'
   title: Home Lab
   theme: dark
   color: slate
   headerStyle: boxed
   target: _blank
   EOF
   ```

5. Go back to your browser and refresh `http://192.168.1.222:8010`. The tiles should appear immediately — no restart needed.

✅ **Verify:** You should see two groups of tiles: "AI Services" and "Management," each with correctly named services. Clicking any tile should open that service in a new tab.

### Method 2: Via Portainer's File Editor

If you're not comfortable with SSH, you can use Portainer to edit the files:

1. In Portainer, click your local environment → **Volumes**.
2. Find the volume named `homepage_config` (or similar).
3. Click the **Browse** icon next to it.
4. You can create and edit files directly from the browser.

---

## Customization Tips

**Changing the theme:**
In `settings.yaml`, change `theme: dark` to `theme: light` for a light background. Options are `dark` and `light`.

**Adding a clock widget:**
Create or add to a file called `widgets.yaml`:
```yaml
- datetime:
    text_size: xl
    format:
      timeStyle: short
      dateStyle: short
      hourCycle: h23
```

**Adding a weather widget:**
```yaml
- openweathermap:
    label: My City
    latitude: 51.5074
    longitude: -0.1278
    units: metric
    apiKey: YOUR_OPENWEATHERMAP_API_KEY
    cache: 5
```
💡 Get a free API key at [openweathermap.org](https://openweathermap.org/api) — it takes about 2 minutes to sign up.

---

## Troubleshooting

**"The page shows a YAML parse error"**
YAML syntax is broken somewhere. The most common cause is using tabs instead of spaces, or wrong indentation. Each level of indentation must be exactly 4 spaces. Double-check by comparing your file to the examples above character by character.

**"Tiles are showing but icons are missing (broken image)"**
Icon names must exactly match the service name in the [Simple Icons library](https://simpleicons.org). Common ones: `portainer.png`, `ollama.png`, `home-assistant.png`, `n8n.png`. If an icon doesn't exist there, use `docker.png` as a fallback.

**"I changed the YAML but the page didn't update"**
Hard refresh the browser: press **Ctrl+Shift+R** (Windows/Linux) or **Cmd+Shift+R** (Mac). Homepage re-reads config files on every page load, but your browser might be showing a cached version.

---

# Chapter 3: Ollama — Your AI Model Server

**🌐 Node A: `http://192.168.1.9:11435`**
**🌐 Node B: `http://192.168.1.222:11434`**

---

## What This Does for You

Ollama is like Netflix for AI models. It handles downloading them, storing them, and serving them to other apps. When Open WebUI asks "hey, can you answer this question?", it's actually asking Ollama. When n8n wants to summarise something with AI, it calls Ollama. Ollama is the engine; Open WebUI and n8n are the steering wheels.

You have two Ollama instances:
- **Node B** (port 11434) — uses your NVIDIA RTX 4070 (CUDA). Fast, great for everyday models.
- **Node A** (port 11435) — uses your AMD RX 7900 XT (ROCm). More VRAM, handles bigger models.

---

## What Is a Model?

A model is an AI "brain" you download. Different models have different personalities and strengths:

| Model Name | Size | Personality / Best Use |
|---|---|---|
| `llama3.1:8b` | 4.7 GB | Well-rounded all-rounder. Good for chat, writing, questions. |
| `qwen2.5:7b` | 4.4 GB | Fast and efficient. Great for automations and quick answers. |
| `qwen2.5:32b` | 20 GB | High quality. Use on Node A for tasks needing more intelligence. |
| `llama3.1:70b` | 40 GB | Deep reasoner. Long documents, complex analysis. Node A only. |
| `nomic-embed-text` | 274 MB | Converts text to numbers (embeddings). Used by Open WebUI's document search feature. |
| `codestral:22b` | 13 GB | Specialises in writing and explaining code. |

The `:8b`, `:7b`, `:70b` suffixes mean "billion parameters" — a rough measure of model size and capability. Bigger generally = smarter but slower and needs more VRAM.

---

## Pulling (Downloading) Your First Models

SSH into Node B to load models onto the CUDA instance:

```bash
ssh root@192.168.1.222

# Pull the main chat model (4.7 GB — takes 2-5 minutes on good internet)
docker exec ollama ollama pull llama3.1:8b

# Pull a fast model for automations
docker exec ollama ollama pull qwen2.5:7b

# Pull the embedding model (needed for Open WebUI document search)
docker exec ollama ollama pull nomic-embed-text
```

While pulling, you'll see a progress bar like this:
```
pulling manifest
pulling 8934d96d3f08... 100% ▕████████████████████▏ 4.7 GB
pulling 8c17c2ebb0ea... 100% ▕████████████████████▏ 7.0 KB
verifying sha256 digest
writing manifest
success
```

Now SSH into Node A to load heavier models:

```bash
ssh your-username@192.168.1.9

# Pull a larger, higher-quality model for the bigger GPU
docker exec ollama-rocm ollama pull qwen2.5:32b
```

💡 **Tip:** Model downloads are large. Do these on a wired ethernet connection if possible, not Wi-Fi. A single model can be 5–40 GB.

---

## Listing Your Available Models

To see what's currently loaded on each node:

```bash
# On Node B
docker exec ollama ollama list

# On Node A
docker exec ollama-rocm ollama list
```

Expected output on Node B after pulling the three models above:
```
NAME                    ID              SIZE      MODIFIED
llama3.1:8b             42182419e950    4.7 GB    2 minutes ago
nomic-embed-text:latest 0a109f422b47    274 MB    1 minute ago
qwen2.5:7b              845dbda0ea48    4.4 GB    3 minutes ago
```

---

## Recommended Model Sets

| Node | Model | Size | Good For |
|---|---|---|---|
| Node B | `llama3.1:8b` | 4.7 GB | General chat, answering questions, writing |
| Node B | `qwen2.5:7b` | 4.4 GB | Fast responses, n8n automations |
| Node B | `nomic-embed-text` | 274 MB | Document search in Open WebUI |
| Node A | `qwen2.5:32b` | 20 GB | Best quality within 20 GB VRAM budget |
| Node A | `llama3.1:70b` | 40 GB | Deep reasoning, long documents (needs ~40 GB VRAM) |

---

## Removing Old Models to Free Up Space

AI models are large. When you're done experimenting with a model and want to reclaim disk space:

```bash
# Remove from Node B
docker exec ollama ollama rm model-name:tag

# Example
docker exec ollama ollama rm llama3.1:8b
```

---

## Troubleshooting

**"Model pull stuck at 0% or not progressing"**
This is almost always a network hiccup. Press Ctrl+C to cancel, wait 30 seconds, and run the pull command again. Ollama resumes from where it left off.

**"Error: model requires more system memory than is available"** or **"CUDA out of memory"**
The model is too large for the available VRAM. Try a smaller variant — if `llama3.1:70b` fails, try `llama3.1:8b` instead. If `qwen2.5:32b` fails, try `qwen2.5:7b`.

**"bash: ollama: command not found"**
You're trying to run `ollama` directly on the host. The ollama binary lives *inside* the container. Always use:
```bash
docker exec ollama ollama [command]
```

**"Connection refused" when testing from browser**
Ollama's web interface only returns useful data on specific endpoints. Try:
```
http://192.168.1.222:11434/api/version
```
You should see a JSON response like `{"version":"0.x.x"}`. If you get "connection refused," the container isn't running — check Portainer or `docker ps | grep ollama` on Node B.

---

# Chapter 4: Open WebUI — Your AI Chat Interface

**🌐 URL: `http://192.168.1.6:3000`**

---

## What This Does for You

Open WebUI is the website you open when you want to have a conversation with your AI. It looks and feels exactly like ChatGPT — there's a chat window, a history sidebar, and a model selector. The difference is everything happens on your hardware. Nothing leaves your house. No subscription. No data collected by anyone.

Open WebUI is smart enough to talk to *both* your Ollama instances (Node A and Node B), so all your models — from the quick everyday `qwen2.5:7b` to the heavyweight `qwen2.5:32b` — appear in one dropdown.

---

## First Login

1. Open **`http://192.168.1.6:3000`** in your browser.

2. You'll see the Open WebUI welcome screen with a **"Sign up"** button. Click it.

3. Fill in the form:
   - **Name:** Your name (e.g., `Alex`)
   - **Email:** Any email address — it doesn't need to be real and is never sent anywhere. Something like `alex@homelab.local` works fine.
   - **Password:** Choose something you'll remember. At least 8 characters.

4. Click **"Create Account"**.

⚠️ **Important:** The very first account created automatically becomes the **admin account**. Make this YOUR personal account. If anyone else in your house creates an account first, *they* become the admin. Do this step yourself before showing anyone else the URL.

---

## Understanding the Interface

When you log in, you'll see:

- **Left sidebar:** Your conversation history — every chat you've had, with the most recent at the top.
- **Model selector:** A dropdown at the top centre of the page. Click it to choose which AI you're talking to.
- **New Chat button:** The pencil icon in the top-left corner. Starts a fresh conversation.
- **Chat input box:** The text box at the bottom. Type here, press Enter or click the arrow to send.

---

## Configuring Connections (Verify Ollama Backends)

Open WebUI should already be connected to both Ollama instances from your compose file settings. Let's verify:

1. Click your **profile picture** or initials in the **top-right corner**.
2. Select **"Admin Panel"** from the dropdown menu.
3. In the Admin Panel, click **"Settings"** in the left sidebar.
4. Click **"Connections"** in the Settings menu.
5. You should see a list of Ollama API connections:
   - `http://192.168.1.9:11435` — should have a **green dot** ✅
   - `http://192.168.1.222:11434` — should have a **green dot** ✅

6. If either shows a **red dot**: click the circular **refresh arrow** button next to it. If it stays red, go back to Chapter 3 and verify that Ollama is running on that node.

---

## Having Your First Chat

Let's send your first message to your own private AI:

1. Click the **pencil icon** (top-left) to start a new chat.

2. Click the **model selector dropdown** at the top of the page. You'll see a list of all models pulled from both nodes — for example:
   - `llama3.1:8b` (from Node B)
   - `qwen2.5:7b` (from Node B)
   - `qwen2.5:32b` (from Node A)

3. Select **`llama3.1:8b`**.

4. Click in the chat box at the bottom and type:
   ```
   Hello! Can you tell me a fun fact about space?
   ```

5. Press **Enter** or click the **send arrow** (➤) button.

6. Wait 5–30 seconds. The AI will start typing its response word by word. The first response on a freshly started Ollama can take up to 60 seconds while the model loads into GPU memory — after that, responses are much faster.

✅ **Verify:** If you see words appearing in the chat window in response to your message, everything is working end-to-end. Congratulations — you're running your own private AI!

---

## Useful Features to Explore

**System Prompts:**
A system prompt is a hidden instruction you give the AI at the start of every conversation. It's like whispering to your assistant before a meeting: "Keep your answers brief and friendly."

To set a system prompt for all conversations:
1. Profile picture → Settings → General.
2. Find the **"System Prompt"** field.
3. Type your instructions, for example:
   ```
   You are a helpful home assistant. Keep your answers concise and practical. When you don't know something, say so clearly.
   ```

**Document Chat (RAG — Retrieval Augmented Generation):**
You can upload a PDF and ask questions about it. This is incredibly useful for things like manuals, recipes, or long articles.
1. In a chat, click the **paperclip icon** (📎) next to the chat input.
2. Upload a PDF file.
3. Ask questions about it: `"What does this document say about installation steps?"`

**Switching Models Mid-Conversation:**
You can change models without starting a new chat — just click the model selector dropdown at the top and choose a different model. The new model sees the entire conversation history.

---

## Managing Multiple Users

Want your partner or kids to have their own Open WebUI accounts?

1. Click your profile picture → **Admin Panel**.
2. In the left sidebar, click **Users**.
3. Click **"Add User"** (the plus button in the top-right).
4. Fill in their name, email, and a temporary password.
5. Click **Save**.
6. They visit `http://192.168.1.6:3000`, log in with the temporary password, and can change it in their profile settings.

Each user gets their own separate conversation history and settings.

---

## Troubleshooting

**"The model dropdown is empty / no models showing"**
Models haven't been pulled yet on Node A or Node B. Go to Chapter 3 and pull at least one model. Then come back and refresh the Open WebUI page.

**"Connection to Node A/B shows red"**
1. Check that the Ollama container is running: SSH to the relevant node and run `docker ps | grep ollama`.
2. Test the API directly from your laptop: open `http://192.168.1.9:11435/api/version` in your browser. You should see `{"version":"..."}`.

**"The AI is extremely slow (more than 2 minutes per response)"**
The model is either very large or the GPU isn't being used. Check Dozzle (Chapter 7) → click the `ollama` container → look for lines saying `loaded model` and check there are no VRAM error messages.

**"I forgot my Open WebUI password"**
If you're the admin, you can reset your own password: Admin Panel → Users → click your username → **Reset Password**. If you forgot the admin password, the only recovery is via database access (ask in the Open WebUI GitHub issues for the current reset procedure).

---

# Chapter 5: n8n — Your Automation Hub

**🌐 URL: `http://192.168.1.222:5678`**

---

## What This Does for You

n8n (pronounced "n-eight-n") is a visual automation tool that runs entirely on your own machine. It connects your services together — like digital plumbing. You draw a workflow on a canvas: "when *this* happens, do *that*, then send the result *there*."

Think of it as IFTTT or Zapier, except it runs in your house, your data never leaves, and it's completely free with no limits on the number of automations.

Example real-world uses:
- Every morning at 8am, ask Ollama for a motivational message and post it to your Discord.
- When Home Assistant detects motion, ask Ollama to write a summary alert and send a push notification.
- Every Sunday, compile your media watch history from Jellyfin and ask Ollama to write a digest.

---

## First Login

1. Open **`http://192.168.1.222:5678`** in your browser.

2. You'll see a login form. Use the credentials you set in your `.env` file — the values of `N8N_BASIC_AUTH_USER` and `N8N_BASIC_AUTH_PASSWORD`.

💡 **Can't remember?** SSH into Node B and check:
```bash
ssh root@192.168.1.222
grep N8N /mnt/user/appdata/n8n/.env
```

---

## Understanding the n8n Interface

When you log in, you'll see the **Workflows** page — a list of all your automations (empty for now).

Key concepts explained simply:

- **Workflow:** A single automation — a chain of steps that runs from start to finish.
- **Node** *(n8n's word for a step):* One block in a workflow. Each node does one thing: schedule a trigger, call an API, send a message, transform data.
  - ⚠️ **Naming collision alert:** n8n calls its workflow steps "nodes" — this has nothing to do with your Node A/B/C/D hardware! It's just unfortunate terminology.
- **Trigger node:** The first node in a workflow. It decides *when* the workflow runs (e.g., on a schedule, when a webhook is called, when a form is submitted).
- **Action node:** Any node after the trigger. It *does* something — calls an API, sends a Discord message, writes to a spreadsheet.
- **Canvas:** The grey grid where you drag and connect nodes.
- **Active toggle:** The switch in the top-right corner of a workflow. A workflow only runs when it's **Active** (blue/green toggle).

---

## Creating Your First Workflow — Daily AI Morning Briefing

Let's build a workflow that sends you a motivational AI-generated message on Discord every morning. Step by step:

1. On the Workflows page, click the orange **"New workflow"** button in the top-right corner.

2. You'll land on an empty canvas. Click the **"+"** button in the centre (or the big **"Add first step"** prompt).

3. In the search box that appears, type `Schedule` and select **"Schedule Trigger"** from the results.

4. A **Schedule Trigger** node appears on the canvas. Click it to configure:
   - **Trigger interval:** Select `Days`
   - **Days between triggers:** `1`
   - **Trigger at Hour:** `8`
   - **Trigger at Minute:** `0`
   This sets the workflow to run every day at 8:00 AM.

5. Click the **"+"** button on the right edge of the Schedule Trigger node to add the next step.

6. Search for `HTTP Request` and select it.

7. Configure the HTTP Request node:
   - **Method:** `POST`
   - **URL:**
     ```
     http://192.168.1.222:11434/api/generate
     ```
   - **Body Content Type:** `JSON`
   - **Body (JSON):**
     ```json
     {
       "model": "qwen2.5:7b",
       "prompt": "Give me a 3-sentence motivational morning message. Be warm and encouraging.",
       "stream": false
     }
     ```
   Click anywhere outside the node to save those settings.

8. Click the **"+"** on the right edge of the HTTP Request node to add the next step.

9. Search for `Discord` and select the **Discord** node.

10. Configure the Discord node:
    - **Webhook URL:** Paste your Discord server's webhook URL (see tip below).
    - **Content:** Click in the **Content** field, then click the **"Insert Expression"** button (the lightning bolt `⚡` icon) and type:
      ```
      {{ $json.response }}
      ```
      This inserts the AI's response as the Discord message.

11. Click **"Save"** in the top-right corner. Give the workflow a name like `Morning Briefing`.

12. Click the **"Activate"** toggle (top-right, next to Save). It should turn green/blue.

✅ The workflow will now run every morning at 8am. To test it immediately, click the **"Execute workflow"** button (the play triangle ▶ at the top).

💡 **How to get a Discord webhook URL:** In your Discord server → right-click a channel → Edit Channel → Integrations → Webhooks → New Webhook → Copy Webhook URL.

---

## Practical Workflow Ideas

Here are five real-world automations you can build once you're comfortable with the interface:

| # | Workflow Name | How It Works |
|---|---|---|
| 1 | **Morning Briefing** | Schedule → Ask Ollama for a motivational message → Post to Discord |
| 2 | **Motion Alert Summary** | Home Assistant webhook → Ask Ollama to summarise the alert → Push notification |
| 3 | **Weekly Media Digest** | Weekly schedule → Get Jellyfin/Tautulli stats → Ask Ollama to write a summary → Email |
| 4 | **Container Health Report** | Uptime Kuma webhook (on DOWN) → Ask Ollama what might be wrong → Discord alert |
| 5 | **Auto-Reply to Forms** | Form submission webhook → Ollama generates a personalised response → Send email reply |

---

## Importing a Workflow Someone Shared With You

n8n workflows can be shared as `.json` files. To import one:

1. On the Workflows page, click the **three-dot menu** (⋮) in the top-right corner.
2. Select **"Import from file"** or **"Import from URL"**.
3. Select the `.json` file from your computer.
4. The workflow appears on the canvas. Review every node carefully before activating — especially any nodes with API keys or webhook URLs, which you'll need to replace with your own.

---

## Troubleshooting

**"My workflow is set up but it's not running on schedule"**
Check the **Active** toggle in the top-right corner of the workflow editor. It must be toggled ON (green) for scheduled workflows to run. If you just created it and left the editor, it may have defaulted to off.

**"HTTP Request to Ollama returns a connection error"**
Inside Docker's network, containers can sometimes reach each other by container name instead of IP. Try:
```
http://ollama:11434/api/generate
```
If that doesn't work, use the full IP:
```
http://192.168.1.222:11434/api/generate
```

**"Discord message isn't sending"**
Discord webhook URLs expire if you regenerate or delete them. Go to your Discord server → channel settings → Integrations → Webhooks → verify the URL matches what's in n8n, or create a new webhook and update n8n.

**"n8n login page won't load / site unreachable"**
Check on Node B:
```bash
docker ps | grep n8n
docker logs n8n --tail 30
```
A common cause: `N8N_BASIC_AUTH_PASSWORD` is blank in your `.env` file. n8n requires a password to be set.

---

# Chapter 6: Uptime Kuma — Service Monitoring

**🌐 URL: `http://192.168.1.222:3010`**

---

## What This Does for You

Uptime Kuma watches all your services around the clock and alerts you the moment something goes down. It checks each service on a regular interval — like a night watchman walking the corridors every minute, trying every door. When a door doesn't open, it immediately sends you an alert.

Without Uptime Kuma, you'd only find out a service is down when you try to use it. With Uptime Kuma, you know within 60 seconds — often before you even notice yourself.

---

## First-Time Setup

1. Open **`http://192.168.1.222:3010`** in your browser.

2. You'll see a setup screen asking you to create an admin account. Fill in:
   - **Username:** `admin` (or your preference)
   - **Password:** Something strong

3. Click **"Create"**.

4. You'll land on the main dashboard — empty for now, just an encouraging "Add your first monitor" prompt.

---

## Adding Your First Monitor

1. Click the green **"+ Add New Monitor"** button (top-left area of the dashboard).

2. A panel slides in from the right. Fill in:
   - **Monitor Type:** `HTTP(s)` — this checks that a web URL responds correctly.
   - **Friendly Name:** `Ollama Node B`
   - **URL:** `http://192.168.1.222:11434/api/version`
   - **Heartbeat Interval:** `60` (checks every 60 seconds)
   - **Retries:** `3` (must fail 3 times in a row before declaring DOWN)

3. Click **"Save"** at the bottom of the panel.

4. ✅ You'll see a new card on the dashboard. Within 60 seconds it will turn green (UP) or red (DOWN). If it turns green, the monitor is working.

---

## Recommended Monitors — Set All of These Up

Repeat the "Add New Monitor" process for each of these:

| Friendly Name | Monitor Type | URL to Monitor | Heartbeat Interval |
|---|---|---|---|
| Ollama ROCm (Node A) | HTTP(s) | `http://192.168.1.9:11435/api/version` | 60s |
| Ollama CUDA (Node B) | HTTP(s) | `http://192.168.1.222:11434/api/version` | 60s |
| Open WebUI | HTTP(s) | `http://192.168.1.6:3000` | 60s |
| Portainer | HTTP(s) | `http://192.168.1.222:9000/api/status` | 60s |
| n8n | HTTP(s) | `http://192.168.1.222:5678/healthz` | 60s |
| Home Assistant | HTTP(s) | `http://192.168.1.149:8123` | 60s |
| Homepage | HTTP(s) | `http://192.168.1.222:8010` | 120s |
| Dozzle | HTTP(s) | `http://192.168.1.222:8888` | 120s |

💡 **Tip:** Set less critical monitors (Homepage, Dozzle) to 120 seconds to reduce noise in your logs.

---

## Setting Up Notifications

1. Click the **gear icon** (⚙️) in the top-right corner to open Settings.
2. Click **"Notifications"** in the left sidebar.
3. Click **"Setup Notification"**.
4. Choose your notification type from the list. The easiest options:

**Discord:**
- Type: `Discord`
- Webhook URL: Paste your Discord webhook URL
- Click **"Test"** — you should receive a test message in Discord
- Click **"Save"**

**Telegram:**
- Type: `Telegram`
- Bot Token: Create a bot via [@BotFather](https://t.me/botfather) on Telegram
- Chat ID: Your Telegram user ID (get it from [@userinfobot](https://t.me/userinfobot))

5. After saving, go back to the Settings and click **"Apply on all existing monitors"** so all your monitors use this notification.

---

## Reading the Status Page

Back on the main dashboard, each monitor card shows:

- **Green badge:** The service responded successfully in the last check.
- **Red badge:** The service is DOWN — you should investigate immediately.
- **Response time graph:** A small chart showing recent response times. If the bars are getting taller over time, a service is getting slow.
- **Uptime %:** The percentage of time the service has been UP over the last 24h / 7 days / 30 days.

---

## Creating a Public Status Page (Optional)

This is great for sharing with family members so they can check if the homelab is up without logging into Uptime Kuma.

1. In the left sidebar, click **"Status Pages"**.
2. Click **"New Status Page"**.
3. Give it a name: `Home Lab Status`
4. Set a slug (the URL path): `homelab`
5. Click **"Next"** and add your monitors to the page.
6. Click **"Save"**.
7. ✅ Your status page is now available at: `http://192.168.1.222:3010/status/homelab` — no login required. Share this URL with anyone you like.

---

## Troubleshooting

**"A monitor shows DOWN but I can open the service in my browser"**
The URL you entered might be slightly wrong. Copy the URL from the monitor settings, paste it into your browser, and check it returns a valid response. Some services need specific health check endpoints — use the ones in the table above, not just the service's home page.

**"I'm not getting Discord/Telegram notifications"**
Go to Settings → Notifications → click your notification → click **"Test"**. If the test fails, the webhook URL may have changed or expired. Regenerate it and update the notification in Uptime Kuma.

**"All my monitors suddenly went DOWN at the same time"**
This usually means Node B itself went down or restarted. Check if you can reach `http://192.168.1.222:9000` (Portainer). If everything came back up after a brief moment, Watchtower probably auto-updated and restarted containers (expected, happens Sunday at 3am per your config).

---

# Chapter 7: Dozzle — Reading Container Logs

**🌐 URL: `http://192.168.1.222:8888`**

---

## What This Does for You

Every container constantly writes messages to its log — things like "starting up", "received a request", "an error occurred on line 47." Normally these messages disappear into the void unless you specifically run a terminal command to see them. Dozzle gives you a live web-based window into every container's log stream.

When something goes wrong — and eventually something will — logs are how you figure out *why*. Dozzle makes reading them easy enough to actually be useful without feeling like an archaeologist.

---

## Opening Dozzle and Reading Logs

1. Open **`http://192.168.1.222:8888`** in your browser.

2. You'll see a list of all running containers down the left sidebar. Container names are usually descriptive: `ollama`, `n8n`, `open-webui`, `portainer`, etc.

3. Click any container name to open its live log stream on the right side of the screen.

4. Logs stream in real time — new lines appear at the bottom as the container generates them. If the container is idle, the log will be silent.

5. To search through the logs, click the **magnifying glass icon** (🔍) at the top of the log panel. Type a keyword — for example `error` or `failed` — and matching lines will be highlighted.

---

## Reading Logs — What to Look For

Most log lines look like noise, but these patterns are worth knowing:

| Log Pattern | What It Means |
|---|---|
| Timestamp + status words (starting, ready, listening) | Normal startup messages — everything is fine |
| `INFO` or `DEBUG` | Informational messages — nothing wrong |
| `WARN` or `WARNING` | Something slightly unexpected, but not necessarily broken |
| `ERROR` or `ERR` | Something went wrong. Read the line carefully. |
| `FATAL` or `PANIC` | Something went very wrong and the container may have crashed |
| `Connection refused` | This container is trying to reach another service and failing |
| `loaded model` (Ollama) | A model finished loading into GPU — now it's ready to respond |

💡 **Rule of thumb:** If the service is working, ignore the logs. If the service is broken, search for `ERROR` in Dozzle and read the surrounding lines for context.

---

## Filtering and Pinning Containers

Dozzle shows every container, which can get crowded. To keep things organised:

- **Pin a container:** Hover over a container name in the left sidebar and click the **pin icon** (📌) that appears. Pinned containers stay at the top of the list.
- **Suggested pins:** `ollama`, `n8n`, `open-webui` — these are the ones you'll check most often when troubleshooting.
- **Filter the sidebar:** There's a search box at the top of the container list. Type part of a container name to filter the list.

---

## Practical Troubleshooting with Dozzle

**Scenario 1: "Ollama is responding slowly"**
1. Open Dozzle → click `ollama` in the sidebar.
2. Look for recent lines containing `loaded model`. If you see `loading model into memory`, it's still warming up — wait 30–60 seconds.
3. If you see `VRAM OOM` or `out of memory`, the model is too large for the GPU. Switch to a smaller model in Open WebUI.

**Scenario 2: "An n8n workflow failed and I don't know why"**
1. Open Dozzle → click `n8n` in the sidebar.
2. Click the search icon and type `Error`.
3. Find the error line that occurred around the time the workflow failed. The message usually names the specific node and reason (e.g., `HTTP request failed: connection refused to 192.168.1.222:11434`).

**Scenario 3: "Open WebUI is showing a loading spinner and not connecting"**
1. Open Dozzle → click `open-webui` in the sidebar.
2. Look for lines containing `OLLAMA_BASE_URL` or `connection refused` or `could not connect`.
3. If you see connection errors to Ollama, verify Ollama is running (Chapter 3) and the URL in your Open WebUI compose configuration is correct.

---

## Troubleshooting

**"The container list on the left is empty"**
Dozzle needs access to the Docker socket to discover containers. Check it's running:
```bash
docker ps | grep dozzle
```
If it's running but shows no containers, the Docker socket might not be mounted correctly — review the Dozzle service definition in your compose file and ensure the volume `/var/run/docker.sock:/var/run/docker.sock` is present.

**"Logs are moving too fast to read"**
Click the **pause button** (⏸) at the top of the log panel to freeze the stream. When you're done reading, click the play button (▶) to resume.

---

# Chapter 8: Watchtower — Automatic Updates

**No browser UI — Watchtower runs silently in the background.**

---

## What This Does for You

Watchtower automatically checks if any of your Docker containers have newer images available, and if so, downloads the update and restarts the container with the new version. It's like Windows Update, but for your homelab containers — and it happens while you're asleep, so you never need to manually think about it.

Your Watchtower is configured to run once a week, on **Sunday mornings at 3:00 AM** — a time when you're almost certainly not using the lab and a brief restart won't bother anyone.

---

## How It Works (Plain English)

Every Sunday at 3:00 AM, Watchtower goes through this process:

1. Looks at every running container and notes which Docker image it was built from.
2. Checks Docker Hub (the public registry where most images are stored) to see if a newer version of each image exists.
3. For each container that has an update available:
   - Downloads the new image (in the background, while the old container keeps running).
   - Stops the old container.
   - Starts a new container using the new image and the exact same settings.
   - The downtime per container is typically 5–15 seconds.
4. Removes the old, now-unused image to free up disk space.
5. Sends you a Discord notification summarising what was updated (if configured).

---

## Checking That Watchtower Is Running

```bash
ssh root@192.168.1.222
docker ps | grep watchtower
```

Expected output:
```
a3f2b1c4d5e6   containrrr/watchtower:latest   "/watchtower"   2 hours ago   Up 2 hours   watchtower
```

To check what Watchtower has been doing recently:
```bash
docker logs watchtower --tail 30
```

Expected output on a quiet day (no updates):
```
time="2026-01-12T03:00:00Z" level=info msg="Checking all containers (except explicitly disabled)"
time="2026-01-12T03:00:05Z" level=info msg="Session done" Failed=0 Scanned=8 Updated=0 Skipped=0
```

Expected output on an update day:
```
time="2026-01-12T03:00:00Z" level=info msg="Checking all containers (except explicitly disabled)"
time="2026-01-12T03:00:12Z" level=info msg="Found new ghcr.io/open-webui/open-webui:main image (sha256:abc...)"
time="2026-01-12T03:00:45Z" level=info msg="Stopping /open-webui (open-webui) with SIGTERM"
time="2026-01-12T03:00:47Z" level=info msg="Creating /open-webui"
time="2026-01-12T03:00:47Z" level=info msg="Session done" Failed=0 Scanned=8 Updated=1 Skipped=0
```

---

## Receiving Update Notifications on Discord

If you set `WATCHTOWER_NOTIFICATION_URL` in your `.env` file to a Discord webhook URL, you'll get a Discord message every Sunday morning like:

> **Watchtower Update Report**
> ✅ Updated 2 containers on node-b:
> - `open-webui`: `sha256:abc123` → `sha256:def456`
> - `n8n`: `nightly-2026-01-10` → `nightly-2026-01-12`

If you haven't set this up yet:
1. Go to your Discord server → right-click a channel (e.g., `#homelab-alerts`) → Edit Channel → Integrations → Webhooks → New Webhook → Copy Webhook URL.
2. SSH into Node B:
   ```bash
   ssh root@192.168.1.222
   nano /mnt/user/appdata/watchtower/.env
   ```
3. Add or update the line:
   ```
   WATCHTOWER_NOTIFICATION_URL=discord://your-webhook-url-here
   ```
4. Restart Watchtower:
   ```bash
   docker restart watchtower
   ```

---

## Excluding a Container from Auto-Updates

Some containers you may want to pin at a specific version — for example, if you're testing a workflow that depends on a specific n8n feature that a newer version removed.

Add this label to the container's service definition in your compose file:
```yaml
services:
  n8n:
    image: n8nio/n8n:1.45.0   # pinned version
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
```

After editing the compose file, redeploy that container:
```bash
docker compose up -d n8n
```

Watchtower will now skip this container entirely during its weekly run.

---

## Troubleshooting

**"The watchtower container doesn't appear in `docker ps`"**
The infra stack probably didn't deploy it. Check:
```bash
cd /mnt/user/appdata/your-stack-folder
docker compose ps
```
If it's not there, check your compose file includes the watchtower service definition and run `docker compose up -d`.

**"Not getting Discord notifications"**
1. Check the env variable is set: `docker exec watchtower env | grep NOTIFICATION`
2. Verify the URL starts with `discord://` followed by the webhook path.
3. Force a manual run to test: `docker exec watchtower /watchtower --run-once` and watch the output.

---

# Chapter 9: Home Assistant + Ollama — Your Smart Home Talks to AI

**🌐 URL: `http://192.168.1.149:8123`**

---

## What This Does for You

Your Home Assistant can now use your local Ollama AI as a "conversation agent" — meaning you can talk to your smart home in plain English and it will give intelligent, contextual responses. More powerfully, you can build automations that use AI to *think* — not just "if door opens, turn on light," but "if this sensor reading is unusual for this time of day, generate an explanation and alert me."

Everything stays local: no Google, no Amazon, no cloud. The AI runs on your hardware down the hall.

---

## Verifying the Ollama Integration Is Active

The NODE_SETUP_GUIDE.md Chapter 4 should have walked you through installing the Ollama integration. Let's verify it's working:

1. Open **`http://192.168.1.149:8123`** and log in.

2. Click **Settings** (the gear icon ⚙️) in the left sidebar.

3. Click **"Devices & Services"**.

4. Look for a card labelled **"Ollama"**. It should show a green status indicator and list your Ollama instance at `http://192.168.1.222:11434`.

5. If you see the Ollama card: ✅ The integration is installed. Move on.

6. If you **don't** see the Ollama card:
   - Click **"+ Add Integration"** (bottom-right button)
   - Search for `Ollama`
   - Enter the URL: `http://192.168.1.222:11434`
   - Select the model you want to use (e.g., `qwen2.5:7b`)
   - Click Submit

---

## Setting Ollama as Your Conversation Agent

1. Go to **Settings → Voice Assistants** in Home Assistant.

2. Click on your existing voice assistant (usually named "Home Assistant" by default), or click **"Add Assistant"** to create a new one.

3. In the assistant settings, find the **"Conversation agent"** dropdown.

4. Change it from **"Home Assistant"** to **"Ollama Conversation"** (or the name Ollama registered under).

5. Click **"Save"**.

✅ Now when you talk to your Home Assistant — via the Assist microphone button, a voice satellite, or a dashboard chat widget — it uses your local Ollama AI to understand and respond.

---

## Creating Your First AI-Powered Automation

Let's build an automation that gives you a morning AI briefing — reading your actual sensor data aloud through a smart speaker.

1. Go to **Settings → Automations & Scenes**.

2. Click the **"+ Create Automation"** button (bottom-right corner).

3. Click **"Create new automation"** on the next screen.

4. **Set the trigger:**
   - Click **"Add Trigger"**
   - Choose **"Time"**
   - Set the time to `07:00:00`
   - This fires the automation every day at 7:00 AM.

5. **Add the AI action:**
   - Click **"Add Action"**
   - Search for and select **"Conversation: Process"**
   - In the **"Text"** field, paste:
     ```
     Good morning! Please give me a brief 2-sentence home summary. The living room is currently {{ states('sensor.living_room_temperature') }}°C and outside it is {{ states('sensor.outside_temperature') }}°C.
     ```
   - In the **"Agent"** dropdown, select **Ollama Conversation**.
   - In the **"Response variable"** field, type: `ai_response`

6. **Add the TTS (text-to-speech) action:**
   - Click **"Add Action"** again
   - Search for **"Text-to-Speech: Speak"**
   - **Media player entity:** Select your smart speaker (e.g., `media_player.living_room_speaker`)
   - **Message:** Click the template icon (the `{ }` button) and enter:
     ```
     {{ ai_response.response.speech.plain.speech }}
     ```

7. Click **"Save"** at the top-right. Give it a name: `Morning AI Briefing`.

8. Enable the automation with the toggle at the top of the automation.

💡 **Don't have smart speakers?** Skip step 6 and instead add a **Notify** action to send the AI's response to your phone via the Home Assistant companion app.

---

## Practical AI Automation Ideas

| Automation | Trigger | What the AI Does |
|---|---|---|
| **Morning Briefing** | 7:00 AM daily | Reads sensor data and gives a warm home summary |
| **Unusual Sensor Alert** | Sensor value deviates from history | Explains why the reading might be unusual and suggests action |
| **Weekly Energy Report** | Sunday 9:00 AM | Summarises the week's energy usage patterns from your power sensors |
| **Guest Mode Welcome** | Input boolean "guests" turned on | Suggests lighting and temperature scene adjustments for visitors |
| **Late Night Check** | Motion detected after midnight | AI evaluates whether it's expected (you're a night owl) or unexpected |

---

## Viewing AI Conversations in Home Assistant

Home Assistant logs every conversation with the AI:

1. Go to **Settings → Voice Assistants**.
2. Click on your assistant.
3. Click the **"Conversation History"** tab (or look for a history icon).
4. You'll see a chronological list of every message sent to the assistant and every AI response received. This is useful for debugging automations or just reviewing what your AI has been saying.

---

## Troubleshooting

**"The AI response is blank or I get an empty TTS message"**
The model on Node B might still be loading on the first call of the day. Wait 30 seconds and trigger the automation again manually (click the ▶ Run button on the automation page).

**"My automation runs but the TTS action fails"**
Double-check the media player entity name. In Home Assistant, go to **Developer Tools → States** and search for `media_player` to find the exact entity ID of your speaker. It might be something like `media_player.kitchen_display` rather than `media_player.living_room_speaker`.

**"Home Assistant can't reach Ollama"**
Home Assistant (Node D at 192.168.1.149) needs to reach Node B's Ollama at 192.168.1.222:11434 across your local network. Check:
1. Are Node B and Node D on the same network subnet?
2. Is there a firewall on Node B blocking the connection? On Unraid, check the network settings.
3. Test from Node D: `curl http://192.168.1.222:11434/api/version`

**"The AI response in automations is very slow"**
Automations benefit from fast models. In the Ollama integration settings, switch to `qwen2.5:3b` for automations — it's noticeably snappier. Save the larger, smarter models for your Open WebUI chat sessions.

---

# Appendix: Quick Reference

---

## All Service URLs

| Service | URL | Node | Default Username | Purpose |
|---|---|---|---|---|
| Portainer | `http://192.168.1.222:9000` | B | admin (you set it) | Manage all Docker containers |
| Homepage | `http://192.168.1.222:8010` | B | None (no login) | Homelab dashboard / start page |
| Uptime Kuma | `http://192.168.1.222:3010` | B | admin (you set it) | 24/7 service monitoring |
| Dozzle | `http://192.168.1.222:8888` | B | None (no login by default) | Live container log viewer |
| Ollama (Node B) | `http://192.168.1.222:11434` | B | None (API only) | CUDA AI model server |
| n8n | `http://192.168.1.222:5678` | B | From your .env file | Workflow automation |
| Ollama (Node A) | `http://192.168.1.9:11435` | A | None (API only) | ROCm AI model server |
| Open WebUI | `http://192.168.1.6:3000` | C | First account = admin | AI chat interface |
| Home Assistant | `http://192.168.1.149:8123` | D | From HA onboarding | Smart home + AI automations |

---

## Common Docker Commands Cheat Sheet

These are the 10 commands you'll use most often. Run all of these after SSHing into the relevant node.

| Command | What It Does |
|---|---|
| `docker ps` | List all running containers |
| `docker ps -a` | List all containers (including stopped ones) |
| `docker logs container-name --tail 50` | Show the last 50 log lines from a container |
| `docker logs container-name -f` | Follow live logs (Ctrl+C to stop) |
| `docker restart container-name` | Stop and start a container |
| `docker stop container-name` | Stop a container gracefully |
| `docker start container-name` | Start a stopped container |
| `docker exec container-name command` | Run a command inside a container |
| `docker exec -it container-name bash` | Open an interactive shell inside a container |
| `docker compose up -d` | Start all services in a compose file (run from the folder containing your compose.yml) |

💡 **Tip:** Replace `container-name` with the actual name from `docker ps`. Common names in your setup: `ollama`, `n8n`, `open-webui`, `portainer`, `homepage`, `uptime-kuma`, `dozzle`, `watchtower`.

---

## Where Everything Lives on Node B

All persistent data — the stuff that survives a container restart — lives here on Node B's hard drive:

| Path | What's Stored There |
|---|---|
| `/mnt/user/appdata/portainer` | Portainer database (users, environment settings, stack configs) |
| `/mnt/user/appdata/homepage/config` | Homepage YAML config files (`services.yaml`, `settings.yaml`, `widgets.yaml`) |
| `/mnt/user/appdata/uptime-kuma` | Uptime Kuma database (monitors, notification settings, history) |
| `/mnt/user/appdata/n8n` | n8n workflows, credentials, execution history |
| `/mnt/user/appdata/ollama` | AI model files — **can be 5–40 GB per model, grows fast** |
| `/mnt/user/appdata/dozzle` | Dozzle settings (minimal) |

⚠️ **Back up `/mnt/user/appdata/`** regularly. This folder contains everything that makes your homelab *yours* — your workflows, your monitoring rules, your settings. Unraid has built-in backup tools; use them.

---

## Healthcheck URLs at a Glance

Use these URLs to quickly test if a service is alive — paste them into your browser or use `curl`:

| Service | Healthcheck URL | Expected Response |
|---|---|---|
| Ollama Node B | `http://192.168.1.222:11434/api/version` | `{"version":"..."}` |
| Ollama Node A | `http://192.168.1.9:11435/api/version` | `{"version":"..."}` |
| n8n | `http://192.168.1.222:5678/healthz` | `{"status":"ok"}` |
| Portainer | `http://192.168.1.222:9000/api/status` | JSON with version info |
| Open WebUI | `http://192.168.1.6:3000` | The Open WebUI login page |
| Home Assistant | `http://192.168.1.149:8123` | The HA login page |

---

## Emoji Key Used in This Guide

| Emoji | Meaning |
|---|---|
| 💡 | Tip — a helpful shortcut or good-to-know fact |
| ⚠️ | Warning — pay attention, this step matters |
| ✅ | Verify — check that this worked before continuing |

---

*You made it through the whole guide. Your homelab is configured, your AI is talking, your automations are running, and your monitoring is watching everything while you sleep. That's genuinely impressive work.*

*Welcome to the club. 🏠🤖*
