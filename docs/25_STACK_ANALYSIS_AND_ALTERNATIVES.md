# Stack Analysis & Alternatives Guide

> **Who this is for:** Anyone who feels overwhelmed by this homelab, is struggling to get things running, or just wants to understand what each piece does and whether a simpler option exists.  
> **Plain English. No assumed knowledge.**

---

## Table of Contents

1. [How To Read This Guide](#1-how-to-read-this-guide)
2. [Your Current Stack — Big Picture](#2-your-current-stack--big-picture)
3. [Difficulty Ratings Explained](#3-difficulty-ratings-explained)
4. [Component-by-Component Analysis](#4-component-by-component-analysis)
   - [AI Inference (LLM serving)](#41-ai-inference-llm-serving)
   - [AI Chat Interface](#42-ai-chat-interface)
   - [AI Gateway / Router](#43-ai-gateway--router)
   - [Vector Database (AI Memory / RAG)](#44-vector-database-ai-memory--rag)
   - [Private Web Search for AI](#45-private-web-search-for-ai)
   - [Text Embeddings](#46-text-embeddings)
   - [Home Automation](#47-home-automation)
   - [Security Cameras / NVR](#48-security-cameras--nvr)
   - [Media Server](#49-media-server)
   - [Media Automation Pipeline](#410-media-automation-pipeline)
   - [Container Management](#411-container-management)
   - [KVM / Remote Access](#412-kvm--remote-access)
   - [Network Tunneling](#413-network-tunneling)
   - [Service Monitoring & Dashboard](#414-service-monitoring--dashboard)
   - [AI Orchestration / Workflow Automation](#415-ai-orchestration--workflow-automation)
5. [Summary Comparison Tables](#5-summary-comparison-tables)
6. [Recommended Beginner Quick-Win Path](#6-recommended-beginner-quick-win-path)
7. [What To Keep, What To Simplify, What To Skip](#7-what-to-keep-what-to-simplify-what-to-skip)
8. [Frequently Asked Questions](#8-frequently-asked-questions)

---

## 1. How To Read This Guide

Each section covers one *category* of service. For each one you will find:

- **What it does** — plain English
- **What you currently use** — the service in this repo
- **Why it can be hard** — honest assessment of pain points
- **Alternatives** — simpler or better options, with pros and cons
- **Our pick for beginners** — single best recommendation

A 🟢 emoji = easy / beginner-friendly  
A 🟡 emoji = moderate / requires some Linux comfort  
A 🔴 emoji = hard / requires real experience to set up and maintain

---

## 2. Your Current Stack — Big Picture

You are running a **five-node homelab** aimed at building a self-contained AI ecosystem with local LLMs, home automation, media management, and physical hardware control. Here is the full picture in one place:

| Node | Role | Hardware | Key Services |
|------|------|----------|--------------|
| **Node A** | AI Brain | AMD RX 7900 XT 20 GB, Intel i9-265F, 128 GB RAM | vLLM (ROCm), OpenWebUI, Qdrant, SearXNG, Embeddings, JupyterLab, Command Center |
| **Node B / Unraid** | Gateway + Media Server | NVIDIA RTX 4070 12 GB, Intel i5-13600K, 96 GB RAM | LiteLLM, Portainer, OpenClaw, Plex, Riven, Decypharr, Zurg, rclone, Zilean, Ollama |
| **Node C** | Intel Arc Vision | Intel Arc A770 16 GB | Ollama (SYCL), OpenWebUI (Chimera Face) |
| **Node D** | Home Automation | — | Home Assistant |
| **Node E** | Surveillance | — | Frigate NVR, Blue Iris relay, Sentinel |

**Total active services across all nodes: 30+**

That is a lot. Before you chase alternatives, understand the core truth: **complexity is your biggest enemy right now.** Most newbie pain comes not from choosing the wrong software, but from trying to run too much at once before any single piece is stable.

---

## 3. Difficulty Ratings Explained

| Rating | Meaning |
|--------|---------|
| 🟢 Easy | Installs in minutes, web UI, minimal config, large community, great docs |
| 🟡 Moderate | Requires some terminal work, config files, occasional debugging |
| 🔴 Hard | Requires deep Linux knowledge, driver/kernel level work, poor error messages, small community |

---

## 4. Component-by-Component Analysis

### 4.1 AI Inference (LLM serving)

> **What it does:** This is the engine that actually *runs* the AI model. Every chat message, every AI response, flows through here.

#### What you currently use: **vLLM with AMD ROCm** (Node A) + **vLLM** (Node B)

- **Difficulty: 🔴 Hard (Node A ROCm) / 🟡 Moderate (Node B CUDA)**
- vLLM is a high-performance inference engine originally built for NVIDIA GPUs. AMD support via ROCm is significantly less stable, poorly documented, and has many hardware-specific flags you must tune manually (`HSA_OVERRIDE_GFX_VERSION`, `PYTORCH_ROCM_ARCH`, `HIP_FORCE_DEV_KERNARG`).
- On Node B (NVIDIA RTX 4070) vLLM is more reliable, but still requires Docker GPU passthrough and careful config.
- Common failure modes: container fails to start due to ROCm version mismatch, model fails to load due to VRAM miscalculation, quantization errors.

#### Alternatives

| Option | What it is | Difficulty | Pros | Cons |
|--------|-----------|------------|------|------|
| **Ollama** | All-in-one LLM server | 🟢 Easy | Single binary, auto-detects GPU, pulls models like Docker images, works on AMD/NVIDIA/Intel/CPU, huge community | Slightly lower raw throughput than vLLM at scale |
| **LM Studio** | Desktop app for running LLMs | 🟢 Easy | Zero config, GUI model browser, works on any hardware | Desktop app only, not server-oriented |
| **LocalAI** | Drop-in OpenAI API replacement | 🟡 Moderate | OpenAI-compatible API, supports many backends (llama.cpp, whisper, stable diffusion) | More complex config than Ollama |
| **llama.cpp** | Raw inference library | 🟡 Moderate | Runs on any hardware (CPU/GPU), very efficient | CLI only, no built-in API server without extra setup |
| **Jan.ai** | Desktop AI app | 🟢 Easy | Beautiful GUI, model hub, works offline | Desktop only, not suitable for headless servers |
| **vLLM** (current) | High-performance batch serving | 🔴 Hard (AMD) / 🟡 (NVIDIA) | Fastest for high-concurrency, OpenAI-compatible | AMD ROCm support is fragile, complex config |

#### ✅ Our pick for beginners: **Ollama**

Ollama is what all the other tools wish they were for beginners. Install it with one command, pull a model like `ollama pull llama3.2`, and it just works on your AMD RX 7900 XT, your RTX 4070, and your Intel Arc — without any ROCm flags or Docker GPU juggling. You can migrate to vLLM later once everything else is stable.

```bash
# Install Ollama (works on all three of your GPU nodes)
curl -fsSL https://ollama.ai/install.sh | sh

# Pull a model (adjust size to your VRAM)
ollama pull llama3.2          # 2 GB — safe for any GPU
ollama pull mistral           # 4 GB — fast and capable
ollama pull llama3.1:70b-q4  # 40 GB — for Node A's 20 GB + Node B's 12 GB combined via LiteLLM

# Test it
ollama run llama3.2
```

---

### 4.2 AI Chat Interface

> **What it does:** The web page where you actually chat with the AI, upload files, manage conversations, and configure settings.

#### What you currently use: **Open WebUI** (all nodes)

- **Difficulty: 🟢 Easy** — Open WebUI is genuinely one of the best choices available and is already what you have. It connects to Ollama or any OpenAI-compatible API, supports RAG, document upload, web search, voice, image generation, and more.
- **Keep this.** Open WebUI is the right choice. The pain you may have experienced is likely from connecting it to vLLM/LiteLLM, not from Open WebUI itself.

#### Alternatives (for comparison only)

| Option | Difficulty | Pros | Cons |
|--------|-----------|------|------|
| **Open WebUI** (current) | 🟢 Easy | Feature-rich, actively developed, great Ollama integration | Can be slow to load on first start |
| **AnythingLLM** | 🟢 Easy | All-in-one: chat + RAG + vector DB + web search built in | Heavier single container, less configurable |
| **LibreChat** | 🟡 Moderate | Multi-user, many API integrations, plugins | More complex setup, requires MongoDB |
| **Chatbot UI** | 🟢 Easy | Clean, simple, lightweight | Fewer features, less active development |
| **SillyTavern** | 🟡 Moderate | Advanced persona/roleplay features | Niche focus, harder to configure for general use |

#### ✅ Our pick for beginners: **Open WebUI** (keep what you have)

Just point it at Ollama directly for your first install. Skip LiteLLM as a middle layer until you need to route between multiple models.

---

### 4.3 AI Gateway / Router

> **What it does:** Sits between your chat interface and your AI models, routing requests to different models on different servers. Useful when you have multiple nodes running different models.

#### What you currently use: **LiteLLM** (Node B, port 4000)

- **Difficulty: 🟡 Moderate**
- LiteLLM is a solid choice for routing between OpenAI, Ollama, vLLM, and dozens of other providers. It requires a Postgres database, a config YAML file, and some networking understanding.
- Pain point: Until you have multiple working model endpoints to route between, LiteLLM adds complexity without benefit.

#### Alternatives

| Option | Difficulty | Pros | Cons |
|--------|-----------|------|------|
| **LiteLLM** (current) | 🟡 Moderate | Routes to 100+ providers, usage tracking, budgets, teams | Requires Postgres, YAML config |
| **No gateway (direct Ollama)** | 🟢 Easy | Zero extra services, lowest latency | Each client app must be configured to point to correct node |
| **OpenRouter** (cloud) | 🟢 Easy | Managed service, 100+ models, pay-per-use | Sends data to cloud, ongoing cost |
| **Portkey** | 🟢 Easy | SaaS gateway with fallbacks, logging | Managed/cloud service |
| **One-API** | 🟡 Moderate | Self-hosted, aggregates many providers | Less documentation than LiteLLM |

#### ✅ Our pick for beginners: **Skip LiteLLM initially; use it only after individual nodes are stable**

Connect Open WebUI directly to Ollama on the same node. Once you have three working nodes, then introduce LiteLLM to unify them. Trying to configure LiteLLM before the backends are stable means you are debugging two problems at once.

---

### 4.4 Vector Database (AI Memory / RAG)

> **What it does:** Stores pieces of text as mathematical vectors so the AI can quickly find relevant information from your documents. This is what enables "chat with your files" or "AI that remembers what you told it."

#### What you currently use: **Qdrant** (Node A + Node B)

- **Difficulty: 🟡 Moderate**
- Qdrant is a good vector database — fast, well-documented, has a nice UI. The complexity comes from wiring it to an embedding model and then to Open WebUI correctly.

#### Alternatives

| Option | Difficulty | Pros | Cons |
|--------|-----------|------|------|
| **Qdrant** (current) | 🟡 Moderate | Fast, production-grade, good docs, REST + gRPC | Requires separate embedding service |
| **ChromaDB** | 🟢 Easy | Python-first, simple setup, good for prototyping | Less production-ready, single-node |
| **Weaviate** | 🟡 Moderate | Built-in embedding modules, GraphQL API | Heavier resource usage |
| **Open WebUI built-in** | 🟢 Easy | Open WebUI has built-in RAG with local SQLite vector store | Less powerful than dedicated DB, but works for most use cases |
| **Milvus** | 🔴 Hard | Enterprise-grade, distributed | Overkill for homelab, complex ops |

#### ✅ Our pick for beginners: **Use Open WebUI's built-in RAG first, upgrade to Qdrant only when you need it**

Open WebUI includes its own built-in document storage and vector search. Enable it in settings, upload a PDF, and chat with it — no separate database required. Add Qdrant when you have hundreds of documents or need shared memory across multiple chat sessions.

---

### 4.5 Private Web Search for AI

> **What it does:** Lets the AI search the internet privately without using Google or Bing directly. The AI asks this service for search results, then uses them to answer your question.

#### What you currently use: **SearXNG** (Node A port 8888, Node B port 8082)

- **Difficulty: 🟢 Easy** — SearXNG is a great choice. It is open-source, privacy-respecting, and has a Docker image that works well.
- **Keep this.** SearXNG is the right tool for this job.

#### Alternatives

| Option | Difficulty | Pros | Cons |
|--------|-----------|------|------|
| **SearXNG** (current) | 🟢 Easy | Open-source, self-hosted, no API key needed, many search engines | Needs occasional settings tuning |
| **Brave Search API** | 🟢 Easy | Fast, high-quality results, free tier | Requires API key, cloud service |
| **Tavily** | 🟢 Easy | Purpose-built for AI agents, great quality | Paid, cloud service |
| **DuckDuckGo HTML scraping** | 🟡 Moderate | No API key needed | Fragile, against ToS |
| **Perplexica** | 🟡 Moderate | AI-powered search with source citations | Requires SearXNG as backend anyway |

#### ✅ Our pick for beginners: **SearXNG** (keep what you have)

Enable web search in Open WebUI settings, point it at your SearXNG instance, and it works out of the box.

---

### 4.6 Text Embeddings

> **What it does:** Converts text into numbers (vectors) that the AI uses for similarity search. Required for RAG and document search.

#### What you currently use: **HuggingFace Text Embeddings Inference (TEI)** (Node A + Node B)

- **Difficulty: 🟡 Moderate** — TEI requires a GPU passthrough Docker setup, choosing the right model, and correct wiring to Open WebUI.

#### Alternatives

| Option | Difficulty | Pros | Cons |
|--------|-----------|------|------|
| **HuggingFace TEI** (current) | 🟡 Moderate | Fast, GPU-accelerated, many models | Docker GPU config required |
| **Ollama embeddings** | 🟢 Easy | Same Ollama you already run, just pull an embedding model | Slightly slower than dedicated TEI |
| **Open WebUI default** | 🟢 Easy | Uses a small built-in model | CPU-only, slower for large datasets |

#### ✅ Our pick for beginners: **Ollama's built-in embedding support**

```bash
# Pull a lightweight embedding model into your existing Ollama
ollama pull nomic-embed-text

# Then in Open WebUI Settings → Documents → Embedding Model,
# select "nomic-embed-text" (served by Ollama)
```

No extra Docker container, no GPU passthrough config — Ollama handles it all.

---

### 4.7 Home Automation

> **What it does:** Controls smart home devices (lights, locks, thermostats, sensors), runs automations, and sends/receives notifications.

#### What you currently use: **Home Assistant** (Node D, port 8123)

- **Difficulty: 🟢 Easy** (after initial setup)
- Home Assistant is the undisputed best choice for self-hosted home automation. There is no meaningful alternative. Keep it.
- The AI integration via LiteLLM conversation agent is a nice feature — but wait until LiteLLM is stable before enabling it.

#### ✅ Keep Home Assistant. It is the correct and only serious choice.

---

### 4.8 Security Cameras / NVR

> **What it does:** Records video from IP cameras, detects motion/objects (people, cars, animals), sends alerts, and stores footage.

#### What you currently use: **Frigate NVR** (Docker) + **Blue Iris** (Windows VM on Proxmox)

- **Difficulty: 🟡 Moderate (Frigate) / 🔴 Hard (Blue Iris on Proxmox VM)**
- Running Blue Iris in a Windows VM on Proxmox, then relaying to Frigate, is a complex two-layer architecture. Unless you specifically need Blue Iris features (e.g., you already own a license), this adds unnecessary complexity.

#### Alternatives

| Option | Difficulty | Pros | Cons |
|--------|-----------|------|------|
| **Frigate** (current, Docker) | 🟡 Moderate | Open-source, Home Assistant integration, AI detection, actively developed | Requires hardware accelerator (Coral/GPU) for best performance |
| **Blue Iris** (current, Windows VM) | 🔴 Hard (in VM) | Feature-rich, very mature | Windows license required, VM overhead, complex integration |
| **Scrypted** | 🟡 Moderate | Excellent Home Assistant + HomeKit + Google integration, plugin ecosystem | Less AI detection than Frigate |
| **Shinobi** | 🟡 Moderate | Open-source, web UI, many camera types | Less active development than Frigate |
| **MotionEye** | 🟢 Easy | Simple, lightweight | Limited AI features |
| **Eufy/cloud NVR** | 🟢 Easy | Zero config | Cloud dependency, privacy concerns |

#### ✅ Our pick for beginners: **Frigate only, skip Blue Iris**

If you don't already depend on Blue Iris, retire it and use only Frigate. You get better Home Assistant integration, AI-powered detection via a Coral TPU or your GPU, and you eliminate a whole Windows VM from your Proxmox overhead.

---

### 4.9 Media Server

> **What it does:** Organizes and streams your movie/TV library to any device in your home or remotely.

#### What you currently use: **Plex** (Unraid)

- **Difficulty: 🟢 Easy** (Plex itself is easy to install)
- Plex is excellent. The pain you may have is not from Plex but from the complex pipeline feeding it (Riven + Decypharr + Zurg + rclone — see section 4.10).

#### Alternatives

| Option | Difficulty | Pros | Cons |
|--------|-----------|------|------|
| **Plex** (current) | 🟢 Easy | Polished UI, wide device support, good apps | Some features require Plex Pass subscription |
| **Jellyfin** | 🟢 Easy | 100% free and open-source, no subscription, Plex-compatible | Slightly less polished UI, fewer apps |
| **Emby** | 🟢 Easy | Similar to Plex, open-source core | Some features behind paywall |
| **Kodi** | 🟡 Moderate | Highly customizable, local playback focused | Complex for server/multi-user setup |

#### ✅ Our pick for beginners: **Either Plex or Jellyfin**

If you pay for Plex Pass and value the extra features, keep Plex. If you want zero cost and full ownership, Jellyfin is excellent and actually simpler for a homelab. Either way, the media server is not your pain point.

---

### 4.10 Media Automation Pipeline

> **What it does:** Automatically finds, downloads, organizes, and adds media to your media server. Your current setup uses Real-Debrid (cloud cached torrents) as the source.

#### What you currently use: **Zurg + rclone + Riven + Decypharr + Zilean** (5 services + Postgres)

- **Difficulty: 🔴 Hard** — This is the most complex part of your entire homelab. Five separate services all need to work in the correct order, each with its own config file, and each one can fail independently. Real-Debrid adds an external dependency and ongoing cost.
- Riven is a relatively new project. Decypharr and Zilean are niche tools with smaller communities.

#### Alternatives

| Option | Difficulty | Pros | Cons |
|--------|-----------|------|------|
| **Current DUMB AIO stack** | 🔴 Hard | Cached-only = instant playback, no seeding | 5+ services, RD subscription required, fragile chain |
| **Traditional arr stack** (Sonarr + Radarr + Prowlarr + qBittorrent) | 🟡 Moderate | Very well-documented, huge community, many guides | Uses BitTorrent (check local laws), slower acquisition |
| **Sonarr + Radarr + Prowlarr + RD** | 🟡 Moderate | arr stack simplicity + Real-Debrid speed | Fewer integration options than Riven for RD |
| **Stremio + Torrentio addon** | 🟢 Easy | Zero-config streaming from RD/Torrentio | No local library, streaming only, addon policy changes |
| **Manual download + Plex/Jellyfin** | 🟢 Easy | No automation complexity | Manual work |

#### ✅ Our pick for beginners: **Traditional arr stack if you want automation**

The Sonarr + Radarr + Prowlarr + qBittorrent stack has 10 years of guides, troubleshooting threads, and community support. It is the industry standard for homelab media automation. If you specifically need Real-Debrid cached streaming (zero seeding, instant availability), consider the Sonarr/Radarr + Debrid-link approach, which is simpler than the current Riven/Decypharr/Zilean setup.

The current DUMB AIO stack is excellent if you are an experienced user. For a beginner, the traditional arr stack is far less frustrating to set up and maintain.

---

### 4.11 Container Management

> **What it does:** Provides a web interface to see, start, stop, and manage all your Docker containers without needing the command line.

#### What you currently use: **Portainer CE** (all nodes)

- **Difficulty: 🟢 Easy**
- Portainer is the right choice. Keep it. The web UI is excellent and the community is large.
- Also included: Dozzle (log viewer), Uptime Kuma (status monitoring) — both are excellent and easy.

#### ✅ Keep Portainer, Dozzle, and Uptime Kuma. They are all correct choices.

---

### 4.12 KVM / Remote Access

> **What it does:** Lets you control a computer's keyboard, video, and mouse over the network — even if it has no OS or is locked up. Essential for headless server management.

#### What you currently use: **NanoKVM** + custom **KVM Operator** (Flask app)

- **Difficulty: 🔴 Hard** — The KVM Operator is a custom-built Flask application that wraps NanoKVM with an AI-driven interface, approval gates, and a denylist. While impressive, it is a lot of custom code to maintain.

#### Alternatives

| Option | Difficulty | Pros | Cons |
|--------|-----------|------|------|
| **NanoKVM + KVM Operator** (current) | 🔴 Hard | AI integration, approval workflow, denylist | Custom code to maintain, fragile |
| **NanoKVM + direct web UI** | 🟢 Easy | NanoKVM has its own built-in web interface | No AI integration, but much simpler |
| **PiKVM** | 🟡 Moderate | Very popular, excellent docs, Raspberry Pi based | Requires Raspberry Pi hardware |
| **JetKVM** | 🟢 Easy | Modern alternative to PiKVM, cloud-ready | Newer product, smaller community |
| **TinyPilot** | 🟢 Easy | Polished hardware/software combo | Higher cost |
| **Cloudflare Tunnel + SSH** | 🟢 Easy | Remote terminal access with zero open ports | No graphical KVM, terminal only |

#### ✅ Our pick for beginners: **Use NanoKVM's built-in web UI first**

The KVM Operator is a powerful future feature, but it is not required to manage your servers. NanoKVM has its own web interface. Use that directly until you specifically need the AI-driven approval workflow.

---

### 4.13 Network Tunneling

> **What it does:** Lets you securely reach your home network from anywhere in the world, and lets nodes on your network connect to each other as if they were on the same local network.

#### What you currently use: **Tailscale**

- **Difficulty: 🟢 Easy**
- Tailscale is the correct choice. It is the easiest VPN ever built. The agent model, ACL system, and MagicDNS are all excellent.
- **Keep it.** There is no compelling reason to switch.

#### ✅ Keep Tailscale. It is the best choice for homelabs.

---

### 4.14 Service Monitoring & Dashboard

> **What it does:** Shows you the status of all your services in one place, and alerts you if something goes down.

#### What you currently use: **Homepage** (Unraid) + **Uptime Kuma** (Unraid) + **Dozzle** (Unraid) + **Node A Command Center** (port 3099)

- **Difficulty: 🟢–🟡 Easy to Moderate**
- These are all good choices. Homepage is a popular self-hosted dashboard. Uptime Kuma is the best open-source uptime monitor. Dozzle is the best Docker log viewer.
- The Node A Command Center is a custom Node.js dashboard — impressive but adds a custom codebase to maintain.

#### ✅ Keep Homepage, Uptime Kuma, and Dozzle. They are all correct choices.

---

### 4.15 AI Orchestration / Workflow Automation

> **What it does:** Chains AI models together with tools (web search, code execution, file reading) to complete multi-step tasks automatically.

#### What you currently use: **OpenClaw** (custom) + **Brothers Keeper** (custom approval HMI)

- **Difficulty: 🔴 Hard** — These are custom-built applications specific to this repo. They are powerful when working but require deep familiarity with the codebase to maintain and debug.

#### Alternatives

| Option | Difficulty | Pros | Cons |
|--------|-----------|------|------|
| **OpenClaw + Brothers Keeper** (current) | 🔴 Hard | Tightly integrated, KVM-aware | Custom code, no community support |
| **n8n** | 🟡 Moderate | Visual workflow builder, 400+ integrations, self-hosted | Less AI-native than newer tools |
| **Flowise** | 🟢 Easy | Drag-and-drop LLM pipeline builder, Langchain-based | Less mature than n8n |
| **Dify** | 🟢 Easy | All-in-one AI app builder (workflows, RAG, API) | Opinionated, less flexible for custom hardware control |
| **Activepieces** | 🟢 Easy | Open-source n8n alternative, cleaner UI | Smaller community |
| **Open WebUI Pipelines** | 🟢 Easy | Built into Open WebUI, no extra service | Limited to Open WebUI context |
| **LangChain + Python** | 🔴 Hard | Maximum flexibility | Code-heavy, no visual interface |

#### ✅ Our pick for beginners: **Start with Open WebUI Pipelines or Flowise**

Before building custom AI orchestration, spend time with Open WebUI's built-in pipeline/agent features (tools, function calling). For visual workflow building, Flowise is the easiest self-hosted option and runs as a single Docker container.

---

## 5. Summary Comparison Tables

### AI Inference — Quick Reference

| Service | Your Hardware | Difficulty | Recommended? |
|---------|--------------|------------|--------------|
| **Ollama** | All nodes (AMD/NVIDIA/Intel/CPU) | 🟢 Easy | ✅ Start here |
| vLLM (NVIDIA) | Node B RTX 4070 | 🟡 Moderate | Later, after Ollama is stable |
| vLLM (AMD ROCm) | Node A RX 7900 XT | 🔴 Hard | Later, after Ollama is stable |
| LocalAI | Any | 🟡 Moderate | Good alternative to Ollama |
| LM Studio | Desktop only | 🟢 Easy | Good for model testing on a desktop |

### Chat Interface — Quick Reference

| Service | Difficulty | Recommended? |
|---------|-----------|--------------|
| **Open WebUI** (current) | 🟢 Easy | ✅ Keep — it is the best choice |
| AnythingLLM | 🟢 Easy | Good all-in-one alternative |
| LibreChat | 🟡 Moderate | Multi-user scenarios |

### Vector Database — Quick Reference

| Service | Difficulty | Recommended? |
|---------|-----------|--------------|
| Open WebUI built-in RAG | 🟢 Easy | ✅ Start here |
| **Qdrant** (current) | 🟡 Moderate | Upgrade when you need it |
| ChromaDB | 🟢 Easy | Good for Python-heavy development |

### Media Automation — Quick Reference

| Stack | Difficulty | Recommended for beginners? |
|-------|-----------|---------------------------|
| **Zurg+Riven+Decypharr+Zilean** (current) | 🔴 Hard | Only if you are committed to RD streaming |
| Sonarr+Radarr+Prowlarr+qBittorrent | 🟡 Moderate | ✅ Much better starting point |
| Stremio + Torrentio | 🟢 Easy | Good for streaming only, no local library |

---

## 6. Recommended Beginner Quick-Win Path

The single biggest cause of frustration for a new homelab builder is trying to get everything working at once. Here is a phased approach that gives you *working AI on Day 1* and builds from there.

---

### Phase 1 — One Node, Working AI (Day 1–3)

**Goal:** Have a working AI chat interface on your best GPU node (Node B, RTX 4070).

**Services to install:**
1. Portainer (you likely already have this)
2. Ollama
3. Open WebUI

**Steps:**
```bash
# On Node B (Unraid) — SSH or Unraid terminal

# 1. Install Ollama with NVIDIA GPU support
docker run -d --gpus=all \
  -v ollama:/root/.ollama \
  -p 11434:11434 \
  --name ollama \
  --restart unless-stopped \
  ollama/ollama

# 2. Pull a model
docker exec ollama ollama pull llama3.2

# 3. Open WebUI
docker run -d \
  -p 3000:8080 \
  -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
  -v open-webui:/app/backend/data \
  --name open-webui \
  --restart unless-stopped \
  ghcr.io/open-webui/open-webui:main
```

**Result:** Open `http://192.168.1.222:3000`, create an account, start chatting.

**Time to working AI: under 30 minutes.**

---

### Phase 2 — Add Search and Documents (Week 1)

Once Open WebUI + Ollama is stable:

1. Deploy SearXNG (already in your repo at `node-b-litellm/stacks/ai-orchestration-stack.yml`)
2. In Open WebUI → Settings → Web Search: enter your SearXNG URL
3. In Open WebUI → Settings → Documents: enable RAG, upload a PDF
4. Pull a lightweight embedding model: `docker exec ollama ollama pull nomic-embed-text`
5. In Open WebUI → Settings → Documents → Embedding Model: select `nomic-embed-text`

**Result:** AI that can search the web and answer questions about your documents. No extra services needed.

---

### Phase 3 — Add Node A Brain (Week 2)

Once Node B is stable and you are comfortable:

1. Install Ollama on Node A (AMD): `curl -fsSL https://ollama.ai/install.sh | sh`
2. Pull a larger model: `ollama pull llama3.1:8b`
3. Add Node A as a second Ollama connection in Open WebUI (Settings → Connections)
4. Now you can choose between "fast small model on Node B" and "powerful large model on Node A"

**Note on vLLM + ROCm on Node A:** AMD ROCm support in vLLM is improving but still fragile. Ollama also supports AMD GPUs natively (it uses ROCm under the hood, but handles all the configuration automatically). Start with Ollama, and only migrate to vLLM on Node A once you specifically need its batch-processing throughput features.

---

### Phase 4 — Add LiteLLM Gateway (Week 3)

Once you have Ollama running on at least two nodes:

1. Deploy LiteLLM using the existing `node-b-litellm/` config
2. Point it at Node A Ollama and Node B Ollama
3. Update Open WebUI to use LiteLLM as its gateway instead of direct Ollama URLs
4. Now you have a single endpoint that routes to the best available model

---

### Phase 5 — Home Assistant Integration (Week 3–4)

1. Node D Home Assistant is already separate — configure it first
2. Add the LiteLLM conversation agent integration to Home Assistant
3. Use it for natural language device control ("turn off all lights downstairs")

---

### Phase 6 — Add Remaining Nodes + Custom Services (Month 2+)

- Node C (Intel Arc): Ollama with Intel SYCL, add as a third model source in LiteLLM
- Node E (Surveillance): Frigate NVR, connect to Home Assistant
- Node A full stack: vLLM (if Ollama proves insufficient), Qdrant, Command Center
- Media stack: Use traditional arr stack or DUMB AIO once everything else is stable

---

## 7. What To Keep, What To Simplify, What To Skip

### ✅ Keep As-Is

| Service | Reason |
|---------|--------|
| Open WebUI | Best-in-class chat interface for self-hosted LLMs |
| SearXNG | Best self-hosted private search engine |
| Home Assistant | No alternative for self-hosted home automation |
| Tailscale | Easiest secure remote networking available |
| Portainer | Best Docker management UI for homelabs |
| Uptime Kuma | Best open-source uptime monitor |
| Dozzle | Best Docker log viewer |
| Frigate NVR | Best open-source AI camera NVR |
| Qdrant | Good vector DB — but defer it until Phase 3+ |

### 🔄 Simplify (Switch or Defer)

| Current Service | Recommendation | Why |
|----------------|---------------|-----|
| vLLM (ROCm, Node A) | **Start with Ollama** | Ollama supports AMD natively, far simpler setup |
| vLLM (NVIDIA, Node B) | **Start with Ollama** | Simpler, same quality for single-user homelab |
| HuggingFace TEI (embeddings) | **Use `ollama pull nomic-embed-text`** | Already have Ollama — use it for embeddings too |
| LiteLLM (first-pass) | **Defer until 2+ nodes are stable** | Adds complexity before it adds value |
| Zurg+Riven+Decypharr+Zilean | **Consider Sonarr+Radarr+Prowlarr stack** | Much better documentation and community support |

### 🗑️ Skip / Retire (for now)

| Service | Reason |
|---------|--------|
| Blue Iris (Windows VM on Proxmox) | Use Frigate only; avoid a whole Windows VM unless you specifically need Blue Iris features |
| KVM Operator custom app | Use NanoKVM's built-in web UI; add AI layer later once stable |
| JupyterLab / Coding Agent | Useful but not core to AI ecosystem; add in Phase 4+ |
| Hardware Agent (custom) | Glances or Netdata are simpler drop-ins for GPU/CPU monitoring |

---

## 8. Frequently Asked Questions

**Q: Do I need all five nodes to have a working AI home lab?**  
A: No. A single Node B (Unraid + RTX 4070) running Ollama + Open WebUI + SearXNG gives you a fully functional unified AI assistant. Add more nodes when you have specific needs that one node cannot satisfy.

**Q: Why is AMD ROCm so painful?**  
A: ROCm is AMD's CUDA equivalent, but it has historically received much less investment. Many ML frameworks (vLLM, PyTorch) officially support CUDA first and ROCm second. Version mismatches between the ROCm libraries, the kernel modules, and the Docker image are common. Ollama avoids most of these issues by bundling its own optimized ROCm build. Use Ollama on your AMD hardware.

**Q: Is Real-Debrid worth the complexity?**  
A: Real-Debrid gives you instant access to cached content with no seeding. If that matters to you, it is worth it. But the Riven/Decypharr/Zilean stack is genuinely complex — plan for a few days of setup even if you are experienced. The traditional arr stack (Sonarr + Radarr + Prowlarr + qBittorrent) is better documented and easier to troubleshoot for beginners.

**Q: Can I use cloud AI APIs (OpenAI, Anthropic) instead of local models?**  
A: Yes. Open WebUI and LiteLLM both support cloud APIs out of the box. Using OpenAI's API while you set up your local stack is a great way to have a working AI assistant while local hardware is being configured. Just add an OpenAI API connection in Open WebUI settings.

**Q: What model should I run on each node?**  

| Node | GPU VRAM | Recommended Model |
|------|----------|------------------|
| Node A | 20 GB | `llama3.1:8b` or `mistral:7b-instruct-q8_0` — or `llama3.1:70b-q4_0` if performance allows |
| Node B | 12 GB | `llama3.2:latest` or `mistral:7b-instruct` |
| Node C | 16 GB | `llava:13b` for vision tasks, `llama3.1:8b` for text |

**Q: The documentation is overwhelming. Where do I start?**  
A: Read this document first, then follow the [Phase 1 quick-win path](#phase-1--one-node-working-ai-day-13) in Section 6. Once Phase 1 is working, come back and read only the guide for the next phase you want to tackle. You do not need to read all 25 documents at once.

**Q: Something broke. What do I do?**  
A: Start with the simplest possible test. Can you `curl http://localhost:11434/api/version` and get a response? If no, Ollama is the problem. Can you open Open WebUI in a browser? If no, Open WebUI is the problem. Isolate which single service is broken before reading logs or changing config. See `docs/06_TROUBLESHOOTING.md` for the structured troubleshooting guide.

---

*Generated as part of the stack analysis and alternatives review. For the full architecture, see `docs/ARCHITECTURE.md`. For node-specific guides, see `docs/16_NODE_A_LAYMENS_GUIDE.md` through `docs/20_NODE_E_LAYMENS_GUIDE.md`.*
