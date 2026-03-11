---
layout: default
title: Project Chimera — Home Lab Documentation
description: Grand Unified AI Home Lab — Node B Unraid · RTX 4070 · Multi-node AI cluster
---

# Project Chimera

**Multi-node AI-powered home lab** — Unraid, Real-Debrid, voice automation, and a three-GPU AI cluster.

---

## Quick Links

| Service | URL | Description |
|---------|-----|-------------|
| **Open WebUI (B)** | [192.168.1.222:3002](http://192.168.1.222:3002) | AI chat — RTX 4070 |
| **Open WebUI (C)** | [192.168.1.6:3000](http://192.168.1.6:3000) | AI chat — Intel Arc |
| **LiteLLM Gateway** | [192.168.1.222:4000](http://192.168.1.222:4000) | Unified AI API |
| **Overseerr** | [192.168.1.222:5055](http://192.168.1.222:5055) | Media requests |
| **Riven** | [192.168.1.222:3001](http://192.168.1.222:3001) | Real-Debrid engine |
| **Plex** | [192.168.1.222:32400](http://192.168.1.222:32400/web) | Media server |
| **Jellyfin** | [192.168.1.222:8096](http://192.168.1.222:8096) | Open media server |
| **n8n** | [192.168.1.222:5678](http://192.168.1.222:5678) | Workflow automation |
| **Portainer** | [192.168.1.222:9443](https://192.168.1.222:9443) | Docker management |
| **Homepage** | [192.168.1.222:8010](http://192.168.1.222:8010) | Dashboard |
| **Home Assistant** | [192.168.1.149:8123](http://192.168.1.149:8123) | Home automation |

---

## Node Architecture

| Node | IP | GPU | Role |
|------|-----|-----|------|
| **A — Brain** | 192.168.1.9 | RX 7900 XT 20GB | Heavy inference (32B models) |
| **B — Brawn** | 192.168.1.222 | RTX 4070 12GB | Operations hub, media, AI |
| **C — Face** | 192.168.1.6 | Intel Arc A770 16GB | UI, vision tasks |
| **D — Nerve** | 192.168.1.149 | — | Home Assistant automation |

---

## LiteLLM Model Aliases

All clients point to `http://192.168.1.222:4000/v1` with key `sk-chimera-master-2026`.

| Alias | Model | Node |
|-------|-------|------|
| `brawn-fast` | llama3.1:8b | Node B RTX 4070 |
| `brawn-mini` | phi4-mini | Node B |
| `brawn-code` | qwen2.5-coder:14b | Node B |
| `brawn-reason` | deepseek-r1:7b | Node B |
| `brawn-uncensored` | dolphin-mistral:7b | Node B |
| `brawn-vision` | llava:7b | Node B |
| `brawn-embed` | nomic-embed-text | Node B |
| `brain-heavy` | qwen2.5:32b | Node A RX 7900 XT |
| `brain-code` | qwen2.5-coder:32b | Node A |
| `brain-vision` | llava:13b | Node A |
| `intel-fast` | phi4 | Node C Arc A770 |
| `intel-uncensored` | dolphin3:8b | Node C |
| `intel-vision` | llava:13b | Node C |

---

## Stack Deploy Order (Node B)

```bash
cd /home/jb/dev/onemoreytry/new-system
docker compose --env-file .env -f stacks/01-infra.yml up -d
docker compose --env-file .env -f stacks/02-ai.yml up -d
docker compose --env-file .env -f stacks/03-dumb-core.yml up -d
docker compose --env-file .env -f stacks/04-media-arr.yml up -d
docker compose --env-file .env -f stacks/05-media-servers.yml up -d
docker compose --env-file .env -f stacks/06-media-books-games.yml up -d
docker compose --env-file .env -f stacks/07-media-mgmt.yml up -d
```

---

## Voice Pipeline

```
Alexa Routine → HA script → n8n webhook (:5678/webhook/media-request)
  → Ollama llama3.1:8b (classify intent) → Switch on action/media_type
  → Overseerr / Sonarr / Radarr / Riven API
  → HA webhook → Piper TTS speaks confirmation
```

---

## Documentation Index

- [README](https://github.com/Enigmaticjoe/onemoreytry/blob/main/README.md)
- [Deployment Guide](https://github.com/Enigmaticjoe/onemoreytry/blob/main/DEPLOYMENT_GUIDE.md)
- [Unified Guidebook](https://github.com/Enigmaticjoe/onemoreytry/blob/main/UNIFIED_GUIDEBOOK.md)
- [Quick Reference](https://github.com/Enigmaticjoe/onemoreytry/blob/main/QUICK_REFERENCE.md)
- [Layman's Guide](https://github.com/Enigmaticjoe/onemoreytry/blob/main/LAYMENS_GUIDE.md)
- [Portainer Guide](https://github.com/Enigmaticjoe/onemoreytry/blob/main/PORTAINER_GUIDE.md)
- [Swarm Guide](https://github.com/Enigmaticjoe/onemoreytry/blob/main/SWARM_GUIDE.md)

---

*Project Chimera · [GitHub](https://github.com/Enigmaticjoe/onemoreytry)*
