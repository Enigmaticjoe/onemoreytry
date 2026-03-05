# Node B — Full Stack Layman's Guide

> Canonical architecture authority: [`docs/ARCHITECTURE_CANONICAL_2026.md`](ARCHITECTURE_CANONICAL_2026.md).

## AI-Integrated Media Server & AI Orchestration Hub

> **Who this guide is for:** Anyone who wants to understand, install, and manage every container running on Node B — the big Unraid server at **192.168.1.222**. No command-line experience required. We'll explain every step in plain English.

---

## Table of Contents

1. [What Is Node B?](#1-what-is-node-b)
2. [The Complete Container Inventory](#2-the-complete-container-inventory)
3. [How Stacks Work](#3-how-stacks-work)
4. [Stack 1 — Infrastructure (Homepage, Watchtower, Dozzle, Uptime Kuma, Tailscale)](#4-stack-1--infrastructure)
5. [Stack 2 — LiteLLM Gateway](#5-stack-2--litellm-gateway)
6. [Stack 3 — AI Orchestration (Open WebUI, Qdrant, SearXNG, Embeddings)](#6-stack-3--ai-orchestration)
7. [Stack 4 — vLLM (Local GPU Inference)](#7-stack-4--vllm)
8. [Stack 5 — Media (Jellyfin, *arr suite, VPN, Real-Debrid)](#8-stack-5--media)
9. [Stack 6 — Media Expansion (Audiobookshelf)](#9-stack-6--media-expansion)
10. [Stack 7 — Agentic (Browserless, Cloudflare Tunnel)](#10-stack-7--agentic)
11. [Stack 8 — Nextcloud](#11-stack-8--nextcloud)
12. [Stack 9 — Stremio](#12-stack-9--stremio)
13. [Stack 10 — OpenClaw Deployment Assistant](#13-stack-10--openclaw)
14. [Individual Containers (Portainer, Plex, Krusader, FlareSolverr, 13Feet-Ladder)](#14-individual-containers)
15. [How AI and Media Work Together](#15-how-ai-and-media-work-together)
16. [First-Time Setup — Full Walkthrough](#16-first-time-setup)
17. [Common Problems & Fixes](#17-common-problems--fixes)
18. [Quick Reference](#18-quick-reference)

---

## 1. What Is Node B?

Node B is the **powerhouse** of your home lab. It runs Unraid — a special server operating system — and hosts two completely different worlds at once:

**The AI World:** An entire AI stack including a local language model, a private AI chat interface, vector database memory, private web search, and text embeddings — all running locally on your own hardware, completely private.

**The Media World:** A fully automated media centre that can find, download, organise, and stream movies, TV shows, music, audiobooks and podcasts — all automatically. If a new episode airs, it gets downloaded, organised, and ready to watch without you doing anything.

**The glue:** Both worlds talk to each other. Your AI can recommend what to watch. Your watch history can feed AI-powered automations.

- **IP Address:** 192.168.1.222
- **OS:** Unraid
- **GPU:** NVIDIA RTX 4070 (12 GB VRAM) — used for AI inference AND media transcoding
- **CPU:** Intel i5-13600K
- **RAM:** 96 GB DDR5

---

## 2. The Complete Container Inventory

Here's every container on Node B, what it does, and which stack it belongs to:

| Container | Stack | Port(s) | What It Does |
|---|---|---|---|
| **homepage** | Infrastructure | 8010 | Dashboard — a single page showing all your services |
| **uptime-kuma** | Infrastructure | 3010 | Uptime monitor — tells you if any service is down |
| **dozzle** | Infrastructure | 8888 | Log viewer — see container logs from your browser |
| **watchtower** | Infrastructure | — | Auto-updates container images overnight |
| **tailscale** | Infrastructure | — | VPN — access your lab from anywhere securely |
| **litellm_gateway** | LiteLLM | 4000 | AI traffic controller — routes requests to the right AI model |
| **hf-openwebui** | AI Orchestration | 3002 | AI chat interface — like ChatGPT but private and local |
| **hf-qdrant** | AI Orchestration | 6333 | Vector database — AI's long-term memory store |
| **hf-redis** | AI Orchestration | — | Fast cache — speeds up AI sessions |
| **hf-searxng** | AI Orchestration | 8082 | Private search engine — AI can search the web privately |
| **hf-tei-embed** | AI Orchestration | 8881 | Text embeddings — turns text into math the AI understands |
| **hf-browserless** | AI Orchestration | 3000 | Headless browser — AI can visit web pages automatically |
| **hf-vllm** | vLLM | 8880 | Local AI model server — runs Mistral 7B on your RTX 4070 |
| **jellyfin** | Media | 8096 | Media server — stream movies/TV/music to any device |
| **sonarr** | Media | 8989 | TV show manager — finds and downloads new episodes |
| **radarr** | Media | 7878 | Movie manager — finds and downloads films |
| **lidarr** | Media | 8686 | Music manager — finds and downloads albums |
| **bazarr** | Media | 6767 | Subtitle manager — finds and downloads subtitles |
| **prowlarr** | Media | 9696 | Indexer manager — connects to torrent sites for the *arr suite |
| **overseerr** | Media | 5055 | Request portal — lets family/friends request content |
| **tautulli** | Media | 8181 | Watch analytics — stats for what's been watched |
| **gluetun** | Media | 8090 | VPN for downloads — hides torrent traffic |
| **qbittorrent** | Media | via gluetun | Torrent client — downloads via VPN |
| **zurg** | Media | 9999 | Real-Debrid daemon — manages cloud-cached downloads |
| **rclone-zurg** | Media | — | Mounts Real-Debrid content as a local folder |
| **rdt-client** | Media | 6500 | Real-Debrid client — sends magnets to Real-Debrid cloud |
| **plex** | Media | — | Alternative media server (runs alongside Jellyfin) |
| **audiobookshelf** | Media Expansion | 13378 | Audiobook + podcast server |
| **browserless** | Agentic | 3005 | Browser automation for AI agents |
| **cloudflared** | Agentic | — | Cloudflare tunnel — secure remote access, no port forwarding |
| **nextcloud** | Nextcloud | 9443 | Personal cloud storage — your own Google Drive |
| **nextcloud-db** | Nextcloud | — | Database for Nextcloud |
| **stremio-server** | Stremio | — | Stremio streaming server |
| **openclaw-gateway** | OpenClaw | 18789 | AI deployment assistant |
| **Portainer-BE** | Standalone | 9000/9443 | Docker management web UI |
| **binhex-krusader** | Standalone | 6080 | File manager — visual file browser for your server |
| **flaresolverr** | Standalone | 8191 | Solves Cloudflare captchas for torrent sites |
| **13Feet-Ladder** | Standalone | — | Bypasses paywalled articles |
| **github-desktop** | Standalone | — | Git GUI (currently stopped) |

---

## 3. How Stacks Work

### What Is a "Stack"?

A **stack** is a group of containers that belong together and are started as a unit. Instead of running 30+ `docker run` commands, you put them all in one YAML file and run one command.

Think of a stack like a recipe:
- The YAML file is the recipe card
- Running `docker compose up -d` is putting all ingredients together and starting cooking

### Where the Files Live

All Node B stack files are in:
```
node-b-litellm/
├── litellm-stack.yml          ← LiteLLM gateway
├── config.yaml                ← LiteLLM model configuration
└── stacks/
    ├── .env.example           ← Copy to .env and fill in your values
    ├── media-stack.yml        ← Full media suite
    ├── ai-orchestration-stack.yml  ← AI brain (Open WebUI, Qdrant, etc.)
    ├── vllm-stack.yml         ← Local GPU inference
    ├── agentic-stack.yml      ← Browser automation + Cloudflare
    ├── media-expansion-stack.yml   ← Audiobookshelf
    ├── nextcloud-stack.yml    ← Personal cloud
    ├── stremio-stack.yml      ← Stremio server
    └── openclaw-stack.yml     ← Deployment assistant
```

The infrastructure stack (Homepage, Watchtower, Dozzle, Uptime Kuma, Tailscale) lives in:
```
unraid/docker-compose.yml
```

---

## 4. Stack 1 — Infrastructure

**Contains:** Homepage · Uptime Kuma · Dozzle · Watchtower · Tailscale

### What Each Piece Does

**Homepage (port 8010):** A beautiful web page that shows all your services in one place. Links to every app, shows their health status, displays the current time and weather. Think of it as your server's home screen.

**Uptime Kuma (port 3010):** Constantly checks if every service is reachable. Sends you a notification (Telegram, Discord, email, etc.) if something goes down. Like a smoke detector for your containers.

**Dozzle (port 8888):** Shows you the logs (activity history) from any container in your browser. If something breaks, you open Dozzle and read what went wrong — no terminal needed.

**Watchtower:** Runs once a day, checks if any of your containers have a newer version available, and automatically updates them. Keeps everything current without you having to do it manually.

**Tailscale:** Creates a secure private network between all your devices. Once installed, you can access your home lab from your phone anywhere in the world as if you were sitting at home.

### How to Deploy

```bash
cd /mnt/user/appdata/unraid   # or wherever you placed the files
cp .env.example .env          # create your personal settings file
nano .env                     # fill in TAILSCALE_AUTHKEY and other values
docker compose up -d
```

### Accessing the Dashboard

Open your browser: **http://192.168.1.222:8010**

---

## 5. Stack 2 — LiteLLM Gateway

**Contains:** litellm_gateway

### What It Does

LiteLLM is the **AI traffic controller**. Every app in your lab that wants to talk to an AI model sends its request to LiteLLM on port 4000. LiteLLM then forwards the request to the right AI model — whether that's your local RTX 4070 (vLLM), Node A's 7900 XT, Node C's Intel Arc, or a cloud service like Claude or GPT-4.

**Why this matters:** You only need to configure one address (`http://192.168.1.222:4000`) in every app. If you want to swap which model they use, you change it in one place — the `config.yaml` file.

### How to Deploy

```bash
cd /mnt/user/appdata/litellm
docker compose -f litellm-stack.yml up -d
```

### Testing It Works

```bash
curl http://192.168.1.222:4000/health
```
Should return: `{"status": "healthy"}`

### Adding More Models

Edit `config.yaml` and add a new entry under `model_list:`:
```yaml
- model_name: my-model-name
  litellm_params:
    model: openai/mistral-7b
    api_base: http://192.168.1.222:8880/v1
    api_key: none
```
Then restart: `docker compose -f litellm-stack.yml restart`

---

## 6. Stack 3 — AI Orchestration

**Contains:** hf-openwebui · hf-qdrant · hf-redis · hf-searxng · hf-tei-embed · hf-browserless

### What This Stack Does

This is the **AI brain hub** on Node B. It's a complete, self-contained AI assistant stack that you can use for anything — writing, research, code, answering questions, summarising documents.

**The flow:**
1. You open **Open WebUI** in your browser at port 3002
2. You type a message
3. Open WebUI sends it to **LiteLLM** (which picks the right AI model)
4. If you ask about something current, Open WebUI queries **SearXNG** (private Google)
5. If you've uploaded documents, the text is indexed in **Qdrant** (vector database)
6. **Redis** keeps your conversation fast by caching session data
7. **TEI Embed** converts your documents to numbers so they can be searched semantically

The result: a private ChatGPT-style assistant that can browse the web, remember your documents, and never sends your data to a third party.

### First-Time Setup

**Step 1: Start the stack**
```bash
cd /mnt/user/appdata/node-b-stacks
cp stacks/.env.example stacks/.env
# Edit .env — set LITELLM_MASTER_KEY, SEARXNG_SECRET_KEY, BROWSERLESS_TOKEN
docker compose -f stacks/ai-orchestration-stack.yml up -d
```

**Step 2: Open the chat interface**

Go to: **http://192.168.1.222:3002**

On first visit, you'll be asked to create an admin account — use any email/password you like (this is local only).

**Step 3: Configure the AI connection**

Open WebUI should auto-connect to LiteLLM. If it doesn't:
1. Click your avatar (top right) → Settings → Connections
2. OpenAI API URL: `http://192.168.1.222:4000/v1`
3. API Key: `sk-master-key`
4. Click Save

**Step 4: Enable web search**

Settings → Documents → Web Search:
- Enable web search: ON
- Search engine: SearXNG
- SearXNG URL: `http://hf-searxng:8080/search?q=<query>&format=json`

### Tips for Daily Use

- **Upload a PDF** by clicking the paperclip icon in the chat — the AI will be able to answer questions about it
- **Use the @ mention** to pick a specific model (e.g. `@brawn-fast` for the local RTX 4070 model)
- **Create system prompts** in Settings → System Prompts to customise how the AI behaves for different tasks

---

## 7. Stack 4 — vLLM

**Contains:** hf-vllm

### What It Does

vLLM runs an AI language model **directly on your RTX 4070 GPU**. It exposes an OpenAI-compatible API on port 8880. LiteLLM uses this as the `brawn-fast` model.

**In plain English:** This is your private local AI. Prompts and responses never leave your house. It's fast (GPU-accelerated) and free to run indefinitely.

### Default Model

The stack is configured for **Mistral 7B Instruct** — a capable general-purpose model that fits comfortably in 12 GB of VRAM. It handles writing, coding, Q&A, and summarisation well.

### How to Deploy

```bash
docker compose -f stacks/vllm-stack.yml up -d
```

The first time, Docker downloads the model from HuggingFace (~14 GB). After that it's cached and starts in about 30 seconds.

### Switching to a Different Model

Edit `stacks/.env` and change `VLLM_MODEL`:

```bash
# Examples:
VLLM_MODEL=NousResearch/Hermes-2-Pro-Mistral-7B   # better for tool use
VLLM_MODEL=microsoft/Phi-3-mini-128k-instruct      # smallest, fastest
```

Then restart: `docker compose -f stacks/vllm-stack.yml up -d`

### Does It Need the Internet?

Only on first run to download the model weights. After that, it works fully offline.

### Testing It Works

```bash
curl http://192.168.1.222:8880/v1/models
```
Should return a JSON list containing your model name.

---

## 8. Stack 5 — Media

**Contains:** jellyfin · sonarr · radarr · lidarr · bazarr · prowlarr · overseerr · tautulli · gluetun · qbittorrent · zurg · rclone-zurg · rdt-client

### The Big Picture

This is your **fully automated media centre**. Here's how it all fits together:

```
You say "I want to watch Dune 2"
        ↓
  Overseerr (port 5055) — you click Request
        ↓
  Radarr (port 7878) — finds the best release
        ↓
  Prowlarr (port 9696) — searches your configured torrent indexers
        ↓
  ┌─ qBittorrent → Gluetun VPN → download (if using torrents)
  └─ RDT Client → Real-Debrid cloud → Zurg → RClone mount (if using Real-Debrid)
        ↓
  Movie lands in /data/movies (organised automatically)
        ↓
  Bazarr (port 6767) — downloads matching subtitles
        ↓
  Jellyfin (port 8096) — it appears in your library, ready to stream
```

### Real-Debrid vs Torrents

**Real-Debrid** is a paid service (~€4/month) that pre-downloads popular movies/shows to their servers. When you request something:
- It checks if it's already cached on Real-Debrid
- If yes, you get instant 10 Gbps streaming — no waiting for a torrent
- If no, it queues a normal torrent download

This is why you have **both** RDT Client (Real-Debrid) and qBittorrent. The setup tries Real-Debrid first, falls back to torrent.

### How to Deploy

**Step 1: Create your .env file**
```bash
cp stacks/.env.example stacks/.env
nano stacks/.env
# Fill in: VPN_USER, VPN_PASSWORD, VPN_SERVICE_PROVIDER
```

**Step 2: Start the stack**
```bash
docker compose -f stacks/media-stack.yml up -d
```

**Step 3: Configure Prowlarr first** (port 9696)

Prowlarr connects to torrent indexers. Without it, Sonarr/Radarr/Lidarr can't find anything.

1. Open: **http://192.168.1.222:9696**
2. Settings → Indexers → Add Indexer
3. Search for your favourite indexers and add them
4. Settings → Apps → Add Application → Add Sonarr, Radarr, and Lidarr

**Step 4: Configure Radarr** (port 7878)

1. Open: **http://192.168.1.222:7878**
2. Settings → Root Folders → Add `/data/movies`
3. Settings → Download Clients → Add qBittorrent (host: `gluetun`, port: `8080`)

**Step 5: Configure Sonarr** (port 8989) — same as Radarr but for TV shows, root folder `/data/tv`

**Step 6: Configure Overseerr** (port 5055)

1. Open: **http://192.168.1.222:5055**
2. Connect to Jellyfin for your library
3. Connect to Radarr and Sonarr for requests
4. Share the link with family — they can now request content!

### Bazarr AI Subtitles

Bazarr can use **OpenAI Whisper** to generate subtitles from audio when none are available. This is genuinely impressive — it transcribes speech directly from the video file.

To enable:
1. Open **http://192.168.1.222:6767**
2. Settings → Providers → Add "Whisper"
3. Point it to your local vLLM or a Whisper endpoint

### Tautulli — Watch Stats

Tautulli at **http://192.168.1.222:8181** shows you:
- What was watched, when, by whom
- How many hours of content you've consumed
- Graphs of your viewing habits

You can also set it up to send Home Assistant a notification when someone starts watching something — enabling automations like "dim the living room lights when a movie starts."

---

## 9. Stack 6 — Media Expansion

**Contains:** audiobookshelf

### What It Does

Audiobookshelf is a dedicated **audiobook and podcast server**. It tracks your listening progress (like Goodreads but for audiobooks), syncs between devices, and manages your podcast feeds.

### How to Deploy

```bash
docker compose -f stacks/media-expansion-stack.yml up -d
```

Open at: **http://192.168.1.222:13378**

Create your admin account on first visit.

### Adding Your Audiobooks

1. Go to Settings → Libraries → Add Library
2. Name it "Audiobooks"
3. Set the folder to where your `.mp3`/`.m4b` files are (e.g. `/audiobooks`)
4. Save and let it scan

### AI Integration Idea

In Open WebUI, upload the plain text version of a book you're currently listening to. Ask the AI for chapter summaries, character analyses, or discussion questions. You now have a reading companion powered by your own local AI.

---

## 10. Stack 7 — Agentic

**Contains:** browserless · cloudflared

### Browserless (port 3005)

Browserless runs **headless Chrome** — a web browser that has no visible screen. AI agents (like OpenClaw, n8n workflows, or custom scripts) can use it to:
- Visit web pages and read their content
- Fill in forms automatically
- Take screenshots
- Interact with JavaScript-heavy sites

This is how your AI can "browse the web" — it's using this real browser rather than just doing text searches.

### Cloudflared — No Port Forwarding Needed

Cloudflared creates a **secure tunnel** from the Cloudflare network directly to your home server. This means:

- You can access Overseerr, Open WebUI, Jellyfin, etc. from anywhere using a nice domain name
- You don't need to open any ports on your router
- Traffic is encrypted and protected by Cloudflare's security

**To set it up:**
1. Go to **dash.cloudflare.com** → Zero Trust → Access → Tunnels
2. Create a tunnel, copy the token
3. Add to your `.env`: `CLOUDFLARE_TUNNEL_TOKEN=your-token-here`
4. In the tunnel config, add a "Public Hostname" pointing to `http://192.168.1.222:3002` (or any other service)

### How to Deploy

```bash
docker compose -f stacks/agentic-stack.yml up -d
```

---

## 11. Stack 8 — Nextcloud

**Contains:** nextcloud · nextcloud-db

### What It Does

Nextcloud is your **personal Google Drive / iCloud** — except it runs on your own hardware and you control every byte. Store files, share them, sync them to your phone or PC, and access them from anywhere via the Cloudflare tunnel.

### How to Deploy

```bash
docker compose -f stacks/nextcloud-stack.yml up -d
```

Wait about 60 seconds for the database to initialise, then open:
**https://192.168.1.222:9443** (note HTTPS — your browser will warn about the certificate; click Advanced → Proceed)

### First-Time Setup

1. Create an admin username and password
2. In the database setup screen:
   - Database type: MySQL/MariaDB
   - Database user: `nextcloud`
   - Database password: whatever you set in `.env`
   - Database name: `nextcloud`
   - Database host: `nextcloud-db`

---

## 12. Stack 9 — Stremio

**Contains:** stremio-server

### What It Does

Stremio is a **streaming app** that works with Real-Debrid and Torrentio add-ons. It's an alternative or complement to Jellyfin — particularly good for quickly watching something without waiting for it to download and be catalogued by the *arr stack.

Your Stremio apps (phone, TV, browser) can connect to this server for local streaming.

### How to Deploy

```bash
docker compose -f stacks/stremio-stack.yml up -d
```

---

## 13. Stack 10 — OpenClaw

**Contains:** openclaw-gateway

### What It Does

OpenClaw is your **AI deployment assistant**. You can type natural language commands and it will manage your Docker containers:

- "Deploy the latest version of sonarr"
- "Show me what's using the most memory"
- "Restart jellyfin"
- "What containers are unhealthy?"

It routes these requests through LiteLLM (your AI gateway) and uses the AI to interpret them, then acts on your Docker environment.

### How to Deploy

```bash
docker compose -f stacks/openclaw-stack.yml up -d
```

---

## 14. Individual Containers

These containers are not in a stack — they're managed separately in Portainer or via individual `docker run` commands.

### Portainer Business Edition (ports 9000/9443)

Portainer is the **web-based Docker control panel**. It's how most people interact with containers on Unraid without using the terminal.

Access at: **https://192.168.1.222:9443** (or **http://192.168.1.222:9000**)

From Portainer you can:
- Start, stop, restart any container
- View live logs
- Edit environment variables
- Browse container filesystems

> Note: Portainer itself is installed as a standalone container, not inside a compose stack, because it needs to be running before anything else.

### binhex-krusader (port 6080)

Krusader is a **visual file manager** — like Windows Explorer but for your server. Access it in a browser at port 6080. Useful for moving, copying, renaming files without needing SSH or a terminal.

### FlareSolverr (port 8191)

FlareSolverr solves **Cloudflare "I'm not a robot" challenges** on torrent sites. Many torrent indexers use Cloudflare protection. FlareSolverr automatically bypasses it so Prowlarr can still read them.

Configure in Prowlarr: Settings → Indexers → add FlareSolverr as a proxy with URL `http://flaresolverr:8191`.

### 13Feet-Ladder

A proxy that bypasses **paywalled articles** by loading the cached Google version. Currently stopped (exited with code 137, meaning it ran out of memory or was manually stopped). Restart it from Portainer when needed.

### Plex

A **media server** alternative to Jellyfin. Both can run side by side — they share the same media files. Some users prefer Plex's interface; others prefer Jellyfin's local-first approach.

---

## 15. How AI and Media Work Together

This is what makes Node B truly special — the AI and media stacks are **deeply integrated**.

### Content Recommendations

Open WebUI has access to your watch history (via Tautulli's API) and can suggest what to watch next:

*"What should I watch tonight? I loved Severance and love psychological thrillers."*

The AI can:
1. Check your Tautulli history to see what you've already watched
2. Search SearXNG for current best-of lists
3. Return personalised recommendations
4. If connected to Overseerr's API, it can even submit the request automatically

### Automated Subtitle Generation

Bazarr + vLLM/Whisper = AI-generated subtitles for any content in any language. If a subtitle file doesn't exist, Bazarr can use the local AI to transcribe the audio and create one.

### Home Assistant Integrations

When combined with Node D (Home Assistant at 192.168.1.149:8123):

- **Lights dim** when Jellyfin starts playing (via Tautulli webhook → HA automation)
- **"What's playing?"** voice command shows the current Jellyfin stream
- **AI-powered routine planning:** "Set up movie night" dims lights, turns on TV, opens Jellyfin on the TV

### Personalised AI Content Context

Upload movie/show subtitles to Open WebUI's document store. Then ask:
- "Summarise everything that's happened in Breaking Bad so far"
- "What are the major themes in this season of The Bear?"

The AI reads the subtitles and gives you a genuine, spoiler-aware summary.

---

## 16. First-Time Setup

If you're setting up Node B from scratch, do it in this order:

### Phase 1: Foundation

1. **Install Unraid** — official guide at docs.unraid.net
2. **Enable Docker** — Unraid Settings → Docker → Enable
3. **Install Portainer** (one-time Docker command):
   ```bash
   docker run -d \
     --name Portainer-BE \
     --restart=always \
     -p 9000:9000 -p 9443:9443 \
     -v /var/run/docker.sock:/var/run/docker.sock \
     -v /mnt/user/appdata/portainer:/data \
     portainer/portainer-ee:latest
   ```
4. Open Portainer at **http://192.168.1.222:9000** and create your admin account

### Phase 2: Set Up Shared Folders

In Unraid Main → Shares, create:
- `appdata` — for container configuration files
- `data` — for all media (movies, TV, music, downloads)

### Phase 3: Copy Stack Files

Copy the files from this repository to your Unraid server:
```bash
# On your PC, or via Krusader, copy to:
/mnt/user/appdata/node-b-stacks/
```

### Phase 4: Configure Environment

```bash
cd /mnt/user/appdata/node-b-stacks
cp stacks/.env.example stacks/.env
```

Open `.env` in a text editor (or via Krusader) and fill in:
- `VPN_USER` and `VPN_PASSWORD` — your VPN login
- `LITELLM_MASTER_KEY` — the key for your AI gateway (from Node B's LiteLLM config)
- `SEARXNG_SECRET_KEY` — run `openssl rand -hex 32` to generate one

### Phase 5: Deploy Stacks (in order)

```bash
# 1. Infrastructure first
cd /mnt/user/appdata/unraid
docker compose up -d

# 2. LiteLLM gateway
cd /mnt/user/appdata/litellm
docker compose -f litellm-stack.yml up -d

# 3. AI stack
cd /mnt/user/appdata/node-b-stacks
docker compose -f stacks/ai-orchestration-stack.yml up -d

# 4. vLLM (takes 5-10 minutes to download model on first run)
docker compose -f stacks/vllm-stack.yml up -d

# 5. Media stack
docker compose -f stacks/media-stack.yml up -d

# 6. Everything else
docker compose -f stacks/media-expansion-stack.yml up -d
docker compose -f stacks/agentic-stack.yml up -d
docker compose -f stacks/nextcloud-stack.yml up -d
docker compose -f stacks/stremio-stack.yml up -d
docker compose -f stacks/openclaw-stack.yml up -d
```

### Phase 6: Configure Media Apps

Do this in order (each one depends on the previous):
1. **Prowlarr** (9696) — add indexers
2. **Radarr** (7878) — add download client + root folders + connect Prowlarr
3. **Sonarr** (8989) — same as Radarr
4. **Lidarr** (8686) — same as Radarr
5. **Bazarr** (6767) — connect to Sonarr and Radarr
6. **Overseerr** (5055) — connect to Jellyfin + Radarr + Sonarr
7. **Jellyfin** (8096) — add media libraries

### Phase 7: Test Everything

```bash
# AI gateway
curl http://192.168.1.222:4000/health

# vLLM model
curl http://192.168.1.222:8880/v1/models

# Open WebUI
curl http://192.168.1.222:3002/health

# Jellyfin
curl http://192.168.1.222:8096/health
```

---

## 17. Common Problems & Fixes

### Container Won't Start

1. Open **Dozzle** at http://192.168.1.222:8888
2. Find the container in the list
3. Read the error message — it will tell you exactly what's wrong

### VPN Not Connecting (Gluetun)

Check your VPN credentials in `.env`. Also check the Gluetun logs in Dozzle — it shows the exact error (wrong password, region unavailable, etc.).

### Sonarr/Radarr Says "No Root Folder"

The container can't see your media path. Check that `MEDIA_PATH` in `.env` points to an existing folder, and that the folder is mounted in the compose file.

### Jellyfin Can't Find Media

1. In Jellyfin → Dashboard → Libraries, make sure the paths match where your media actually is
2. Check that `rclone-zurg` is running if you use Real-Debrid (Jellyfin reads from its mount)

### vLLM Crashes on Start

Usually means the model is too large for 12 GB VRAM. Try:
1. Using a smaller model: `VLLM_MODEL=microsoft/Phi-3-mini-128k-instruct`
2. Reducing context: `VLLM_MAX_CTX=4096`

### Open WebUI Can't Connect to AI

1. Verify LiteLLM is running: `docker ps | grep litellm`
2. Test the gateway: `curl http://192.168.1.222:4000/health`
3. In Open WebUI settings, make sure the API URL is `http://192.168.1.222:4000/v1`

### Nextcloud Login Page Shows SSL Warning

This is normal for a home setup. Click **Advanced** → **Proceed to 192.168.1.222 (unsafe)** in your browser. It's only unsafe because the SSL certificate is self-signed (not from a trusted authority), not because the connection is insecure.

---

## 18. Quick Reference

| Service | URL | Default Credentials |
|---|---|---|
| Portainer | https://192.168.1.222:9443 | Set on first visit |
| Homepage | http://192.168.1.222:8010 | No login |
| Uptime Kuma | http://192.168.1.222:3010 | Set on first visit |
| Dozzle | http://192.168.1.222:8888 | No login |
| Open WebUI | http://192.168.1.222:3002 | Set on first visit |
| LiteLLM API | http://192.168.1.222:4000 | Key: sk-master-key |
| Jellyfin | http://192.168.1.222:8096 | Set on first visit |
| Sonarr | http://192.168.1.222:8989 | No login (home network) |
| Radarr | http://192.168.1.222:7878 | No login (home network) |
| Lidarr | http://192.168.1.222:8686 | No login (home network) |
| Bazarr | http://192.168.1.222:6767 | No login (home network) |
| Prowlarr | http://192.168.1.222:9696 | No login (home network) |
| Overseerr | http://192.168.1.222:5055 | Set on first visit |
| Tautulli | http://192.168.1.222:8181 | Set on first visit |
| RDT Client | http://192.168.1.222:6500 | Set on first visit |
| Zurg | http://192.168.1.222:9999 | Set in config |
| Audiobookshelf | http://192.168.1.222:13378 | Set on first visit |
| Nextcloud | https://192.168.1.222:9443 | Set on first visit |
| SearXNG | http://192.168.1.222:8082 | No login |
| Krusader (file mgr) | http://192.168.1.222:6080 | Set on first visit |
| Qdrant | http://192.168.1.222:6333 | No login |

### Model Aliases (LiteLLM)

| Alias | Points To | Best For |
|---|---|---|
| `brawn-fast` | Node B vLLM port 8880 | Fast local responses (RTX 4070) |
| `brain-heavy` | Node A vLLM port 8000 | Complex reasoning (7900 XT) |
| `intel-vision` | Node C Ollama port 11434 | Image analysis (Intel Arc) |

### Port Summary

| Port | Service |
|---|---|
| 3000 | hf-browserless |
| 3002 | Open WebUI |
| 3005 | browserless (agentic) |
| 3010 | Uptime Kuma |
| 4000 | LiteLLM gateway |
| 5055 | Overseerr |
| 6080 | Krusader |
| 6333 | Qdrant |
| 6500 | RDT Client |
| 6767 | Bazarr |
| 7878 | Radarr |
| 8082 | SearXNG |
| 8096 | Jellyfin |
| 8181 | Tautulli |
| 8686 | Lidarr |
| 8880 | vLLM |
| 8881 | TEI Embeddings |
| 8888 | Dozzle |
| 8010 | Homepage |
| 8989 | Sonarr |
| 9000 | Portainer HTTP |
| 9443 | Portainer HTTPS / Nextcloud |
| 9696 | Prowlarr |
| 9999 | Zurg |
| 13378 | Audiobookshelf |
| 18789 | OpenClaw |
