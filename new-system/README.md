# Project Chimera — New System
> Node B · Unraid · 192.168.1.222 · RTX 4070 · 96 GB DDR5
> Fully AI-integrated media server with voice control via Alexa + Home Assistant

## What This Is

A complete, multinode AI home lab media stack. Tell Alexa to add a movie. It appears in Plex in 30 seconds — no manual downloads, no queues. Browse books, audiobooks, music, games, and ROMs from dedicated servers. Have a conversation with your AI about what to watch tonight.

```
You: "Alexa, add Dune 3 to my movies"
     ↓ 30 seconds later ↓
Plex: "Dune Part Three (2026)" appears in 4K, ready to play
Alexa: "Dune 3 has been added to your library in 4K."
```

---

## Quickstart

### Prerequisites

- Unraid 6.12+ at 192.168.1.222 with Docker enabled
- Real-Debrid subscription (realD-ebrid.com — ~€4/month)
- NVIDIA GPU with CUDA drivers (RTX 4070 recommended)
- Home Assistant on Node D (192.168.1.149)
- `.env` file filled with your secrets

### 1. Mount setup (run once as root)

```bash
sudo bash scripts/setup-mounts.sh
```

This creates `/mnt/debrid`, sets up the rshared bind mount, generates Zurg and rclone config stubs, and creates all appdata directories.

### 2. Fill in secrets

```bash
cp .env.example .env
nano .env   # Fill in all required values
```

**Required minimum:**
- `REAL_DEBRID_API_KEY` — from real-debrid.com/apitoken
- `N8N_PASSWORD` — openssl rand -base64 24
- `RIVEN_DB_PASSWORD` — openssl rand -base64 24
- `RIVEN_AUTH_SECRET` — openssl rand -base64 32
- `PLEX_CLAIM_TOKEN` — from plex.tv/claim (first run only)

Then edit the generated Zurg config:
```bash
nano /mnt/user/appdata/DUMB/zurg/config.yaml
# Replace: YOUR_REAL_DEBRID_API_KEY
```

### 3. Deploy all stacks

```bash
bash scripts/deploy-all.sh
```

Or deploy individually:
```bash
docker compose -f stacks/01-infra.yml up -d        # Infrastructure
docker compose -f stacks/02-ai.yml up -d            # AI + voice pipeline
docker compose -f stacks/03-dumb-core.yml up -d     # DUMB AIO (Real-Debrid)
docker compose -f stacks/04-media-arr.yml up -d     # *arr suite
docker compose -f stacks/05-media-servers.yml up -d # Plex + Jellyfin
docker compose -f stacks/06-media-books-games.yml up -d # Books + games
docker compose -f stacks/07-media-mgmt.yml up -d    # Management + intelligence
```

### 4. Pull AI models

```bash
docker exec ollama ollama pull llama3.1:8b
docker exec ollama ollama pull nomic-embed-text
```

### 5. Verify

```bash
bash scripts/verify-all.sh
```

### 6. Configure voice control

See **VOICE_AI_GUIDE.md** — full walkthrough for n8n, Home Assistant, and Alexa setup.

---

## Stack Map

| Stack | Services | Purpose |
|-------|---------|---------|
| `01-infra.yml` | Portainer · Homepage · Uptime Kuma · Dozzle · Watchtower · Tailscale · Cloudflared · Wizarr | Infrastructure backbone |
| `02-ai.yml` | Ollama · n8n · Whisper · Wyoming STT/TTS · SearXNG · Open WebUI | AI inference + voice pipeline |
| `03-dumb-core.yml` | Zurg · rclone · Riven · Riven-frontend · Zilean | Real-Debrid acquisition engine |
| `04-media-arr.yml` | Gluetun · Prowlarr · Sonarr · Radarr · Lidarr · Readarr · Bazarr · Decypharr · Decluttarr | Media automation (*arr) |
| `05-media-servers.yml` | Plex · Jellyfin · Navidrome · Audiobookshelf · Stremio | Media serving |
| `06-media-books-games.yml` | Calibre-Web · Kavita · Komga · GameVault · Romm | Books + games |
| `07-media-mgmt.yml` | Overseerr · Tautulli · Maintainerr · Recyclarr · Huntarr · Notifiarr · Kometa | Library intelligence |

---

## Key URLs (Node B — 192.168.1.222)

| Service | URL |
|---------|-----|
| Homepage Dashboard | http://192.168.1.222:8010 |
| Portainer | https://192.168.1.222:9443 |
| Open WebUI (AI Chat) | http://192.168.1.222:3002 |
| n8n Workflows | http://192.168.1.222:5678 |
| Overseerr (Requests) | http://192.168.1.222:5055 |
| Plex | http://192.168.1.222:32400/web |
| Jellyfin | http://192.168.1.222:8096 |
| Riven Dashboard | http://192.168.1.222:3001 |
| Sonarr | http://192.168.1.222:8989 |
| Radarr | http://192.168.1.222:7878 |
| Navidrome (Music) | http://192.168.1.222:4533 |
| Audiobookshelf | http://192.168.1.222:13378 |
| Kavita (Books) | http://192.168.1.222:5000 |
| GameVault | http://192.168.1.222:8998 |
| Tautulli | http://192.168.1.222:8181 |
| Maintainerr | http://192.168.1.222:6246 |
| Uptime Kuma | http://192.168.1.222:3010 |
| Dozzle (Logs) | http://192.168.1.222:8888 |

---

## Docs

- **ARCHITECTURE.md** — Full system architecture with Mermaid diagrams
- **VOICE_AI_GUIDE.md** — Step-by-step voice + AI integration guide
- **SETUP_GUIDE.md** — Detailed first-time setup for each service
- **home-assistant/configuration-snippet.yaml** — Paste into HA config
- **n8n-workflows/media-voice-request.json** — Import into n8n

---

## Multinode Context

This repo manages all nodes. Node B (this stack) integrates with:

| Node | IP | Role |
|------|----|------|
| A | 192.168.1.9 | Heavy inference (RX 7900 XT ROCm) |
| B | 192.168.1.222 | **This node** — media + AI (RTX 4070) |
| C | 192.168.1.6 | Shared Open WebUI (Intel Arc) |
| D | 192.168.1.149 | Home Assistant + voice pipeline |
| E | 192.168.1.116 | Frigate NVR (motion → HA events) |
