# Node B Final — Optimized Unraid Stack

**Node B** (Unraid at `192.168.1.222`) running **23–26 containers** with full AI integration.  
Reduced from 37 containers (including 3 dead, ~15 redundant) to a lean, AI-powered ecosystem.

---

## What Changed

| Category | Before | After | Savings |
|----------|--------|-------|---------|
| AI Stack | 8 containers, ~12 GB RAM | 2 containers, ~4 GB RAM | −6 containers, −8 GB |
| Media Stack | Unchanged | Unchanged | — |
| Infrastructure | Unchanged | Unchanged | — |
| New AI additions | 0 | 4 containers, ~2 GB RAM | +4 containers |
| **Total** | **~37, ~22 GB** | **~23–26, ~16 GB** | **~−6 GB RAM** |

**Containers dropped:** `hf-vllm`, `hf-openwebui`, `hf-qdrant`, `hf-redis`, `hf-searxng`,
`hf-tei-embed`, `hf-browserless` (duplicate), `qBittorrent` (dead), `Stremio Server`,
`binhex-krusader`, `github-desktop` (dead), `13Feet-Ladder` (dead), `Nextcloud + DB`

---

## Directory Structure

```
nodebfinal/
├── .env.example                    ← copy to .env and fill in values
├── .gitignore
├── README.md
├── stacks/
│   ├── 01-infra-stack.yml          ← Homepage, Uptime Kuma, Dozzle, Watchtower, Tailscale, Portainer BE, Cloudflared
│   ├── 02-ai-stack.yml             ← Ollama (CUDA), Browserless
│   ├── 03-media-stack.yml          ← Gluetun, Zurg, rclone-zurg, rdt-client, Prowlarr, Sonarr, Radarr, Bazarr, Overseerr, Tautulli, Plex, Jellyfin, FlareSolverr
│   ├── 04-automation-stack.yml     ← n8n, Recommendarr
│   ├── 05-voice-stack.yml          ← Wyoming Whisper, Wyoming Piper
│   └── 06-conditional-stack.yml   ← Lidarr, Audiobookshelf (only if you use them)
├── homepage-config/
│   ├── services.yaml
│   ├── settings.yaml
│   └── widgets.yaml
└── n8n-workflows/
    ├── morning-briefing.json
    ├── container-health-monitor.json
    ├── weekly-media-digest.json
    └── smart-content-approval.json
```

---

## Quick Start

### 1. Copy and configure environment

```bash
cd /mnt/user/appdata/nodebfinal
cp .env.example .env
nano .env   # fill in your values
```

**Required values to fill in immediately:**
- `TAILSCALE_AUTHKEY` — from https://login.tailscale.com/admin/settings/authkeys
- `CLOUDFLARE_TUNNEL_TOKEN` — from Cloudflare Zero Trust dashboard
- `VPN_USER` / `VPN_PASSWORD` — your VPN credentials
- `N8N_PASSWORD` — choose a strong password

### 2. Deploy in order

```bash
# Step 1: Infrastructure (dashboard, monitoring, VPN mesh)
docker compose -f stacks/01-infra-stack.yml up -d

# Step 2: AI stack (Ollama GPU inference + Browserless)
docker compose -f stacks/02-ai-stack.yml up -d

# Step 3: Pull AI models (first time only, takes a few minutes)
docker exec ollama ollama pull qwen3:8b
docker exec ollama ollama pull phi4-mini
docker exec ollama ollama pull nomic-embed-text

# Step 4: Media stack
docker compose -f stacks/03-media-stack.yml up -d

# Step 5: Automation (n8n + Recommendarr)
docker compose -f stacks/04-automation-stack.yml up -d

# Step 6: Voice pipeline (Wyoming Whisper + Piper)
docker compose -f stacks/05-voice-stack.yml up -d

# Step 7: Optional — deploy only what you use
docker compose -f stacks/06-conditional-stack.yml up -d lidarr
docker compose -f stacks/06-conditional-stack.yml up -d audiobookshelf
```

---

## Container Inventory

### Stack 1 — Infrastructure (7 containers)

| Container | Port | Purpose |
|-----------|------|---------|
| Tailscale | — | Zero-config VPN mesh for secure remote access |
| Portainer BE | 9000/9443 | Docker management UI (central pane of glass) |
| Homepage | 8010 | Central dashboard with service widgets |
| Uptime Kuma | 3010 | Service monitoring + webhook alerts to n8n |
| Dozzle | 8888 | Live Docker log viewer |
| Watchtower | — | Weekly auto-updates (Sunday 3am, prevents mid-shift surprises) |
| Cloudflared | — | Zero-Trust tunnel — exposes Overseerr + Homepage externally without open ports |

### Stack 2 — AI (2 containers)

| Container | Port | Purpose |
|-----------|------|---------|
| Ollama | 11434 | NVIDIA CUDA inference. Pull any model with `ollama pull <name>` |
| Browserless | 3005 | Headless Chrome for n8n web-scraping workflows |

> **Why Ollama instead of vLLM?**  
> vLLM's PagedAttention and continuous batching optimize for multi-user, high-concurrency
> scenarios. For a single user on consumer NVIDIA, Ollama gives 90% of the performance
> with ~10% of the configuration overhead. One command to pull models, built-in
> OpenAI-compatible API, and native embedding support (`nomic-embed-text`).

### Stack 3 — Media (13 containers)

| Container | Port | Purpose |
|-----------|------|---------|
| Gluetun | 8090 | VPN tunnel for all download traffic |
| Zurg | 9999 | Real-Debrid filesystem daemon |
| rclone-zurg | — | Mounts Real-Debrid content as local filesystem |
| rdt-client | 6500 | Real-Debrid torrent manager (replaces dead qBittorrent) |
| Prowlarr | 9696 | Unified indexer management for all \*arr apps |
| FlareSolverr | 8191 | Cloudflare bypass for Prowlarr indexers |
| Sonarr | 8989 | TV show automation |
| Radarr | 7878 | Movie automation |
| Bazarr | 6767 | Subtitle automation with AI Whisper support |
| Overseerr | 5055 | Media request portal |
| Tautulli | 8181 | Watch analytics (feeds weekly AI digest) |
| Plex | 32400 | Media server (keep if sharing with family) |
| Jellyfin | 8096 | Free media server (better if solo viewer) |

> **Plex vs. Jellyfin:** The stack runs both so you can evaluate. After 2 weeks,
> pick one and comment out the other. Plex if you share with non-technical family.
> Jellyfin if it's just you (free hardware transcoding, no cloud dependency).

### Stack 4 — Automation (2 containers)

| Container | Port | Purpose |
|-----------|------|---------|
| n8n | 5678 | Visual workflow automation — the AI integration brain |
| Recommendarr | 3006 | AI movie/TV recommendations from your library via Ollama |

### Stack 5 — Voice (2 containers)

| Container | Port | Purpose |
|-----------|------|---------|
| Wyoming Whisper | 10300 | Local speech-to-text (Home Assistant voice pipeline) |
| Wyoming Piper | 10200 | Local text-to-speech (natural voices, zero cloud) |

### Stack 6 — Conditional (deploy only if you use them)

| Container | Port | Condition |
|-----------|------|-----------|
| Lidarr | 8686 | Only if you automate music downloads |
| Audiobookshelf | 13378 | Only if you listen to audiobooks/podcasts |

---

## AI Integration

### Homepage AI Briefing Widget

Edit `homepage-config/widgets.yaml` and uncomment the `customapi` block at the bottom.
This adds a live "AI Briefing" card to the top of your dashboard that calls Ollama.

### n8n Workflows

Import the JSON files from `n8n-workflows/` into n8n at
`http://192.168.1.222:5678` → Workflows → Import from File.

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `morning-briefing.json` | Cron 7:30am weekdays | Weather + HA sensors → Ollama → spoken via Piper TTS + Discord |
| `container-health-monitor.json` | Uptime Kuma webhook | Service down → Ollama analyzes error → Discord fix suggestion |
| `weekly-media-digest.json` | Cron Sunday 8am | Tautulli stats → Ollama summary → Discord weekly digest |
| `smart-content-approval.json` | Overseerr webhook | New request → check watch history → Ollama decides → auto-approve or hold |

**Workflow setup checklist:**
1. In n8n: set environment variables `DISCORD_WEBHOOK`, `TAUTULLI_API_KEY`,
   `HA_TOKEN`, `OVERSEERR_API_KEY`
2. In Uptime Kuma: add webhook notification → `http://192.168.1.222:5678/webhook/uptime-kuma-alert`
3. In Overseerr: Settings → Notifications → Webhook → `http://192.168.1.222:5678/webhook/overseerr-request`

### Recommendarr

After deploying, fill in your API keys in `.env`:
- `SONARR_API_KEY` — Sonarr → Settings → General → API Key
- `RADARR_API_KEY` — Radarr → Settings → General → API Key
- `JELLYFIN_API_KEY` — Jellyfin → Dashboard → API Keys → Create
- `PLEX_TOKEN` — from Plex account settings

Access at `http://192.168.1.222:3006`

### Wyoming Voice Pipeline

After deploying the voice stack, add to Home Assistant:

1. Settings → Devices & Services → Add Integration → **Wyoming Protocol**
2. Add **Whisper** (STT): host `192.168.1.222`, port `10300`
3. Add **Piper** (TTS): host `192.168.1.222`, port `10200`
4. Settings → Voice Assistants → Create assistant → select Whisper + Piper

### Bazarr AI Subtitles

In Bazarr → Settings → Providers → Add Provider → **Whisper**:
- API URL: `http://192.168.1.222:10300`

This uses your local Wyoming Whisper to generate subtitles from audio when no
pre-made subtitle file is found.

---

## Homepage Setup

Copy the homepage config to your Portainer appdata:

```bash
cp -r homepage-config/* /mnt/user/appdata/homepage/config/
```

Then restart Homepage:
```bash
docker restart homepage
```

---

## Watchtower Schedule

Watchtower is configured to update containers once per week (Sunday at 3:00am).
This avoids auto-updates during your third shift. Change the schedule by editing
`WATCHTOWER_SCHEDULE` in `01-infra-stack.yml`.

Cron format: `sec min hour day month weekday`  
`0 0 3 * * 0` = Sunday, 3:00am

---

## Migration Checklist

- [ ] Stop old containers: `hf-vllm`, `hf-openwebui`, `hf-qdrant`, `hf-redis`, `hf-searxng`, `hf-tei-embed`, `hf-browserless`, `Stremio Server`, `binhex-krusader`
- [ ] Remove dead containers: `qbittorrent` (exit 128), `github-desktop` (exited), `13Feet-Ladder` (OOM)
- [ ] Copy `.env.example` to `.env` and fill in values
- [ ] Deploy Stack 1 (infra) → verify Homepage loads at :8010
- [ ] Deploy Stack 2 (AI) → pull `qwen3:8b` and `phi4-mini`
- [ ] Test Ollama: `curl http://192.168.1.222:11434/api/version`
- [ ] Deploy Stack 3 (media) → configure Prowlarr first
- [ ] Deploy Stack 4 (automation) → import n8n workflows
- [ ] Deploy Stack 5 (voice) → add Wyoming to Home Assistant
- [ ] Evaluate Stack 6 (conditional) — deploy only what you use
- [ ] Copy homepage-config to appdata
- [ ] Configure Uptime Kuma to monitor all new services
- [ ] After 2 weeks: decide Plex vs. Jellyfin, comment out the other

---

## Port Reference

| Port | Service | Stack |
|------|---------|-------|
| 3005 | Browserless | AI |
| 3006 | Recommendarr | Automation |
| 5055 | Overseerr | Media |
| 5678 | n8n | Automation |
| 6500 | rdt-client | Media |
| 6767 | Bazarr | Media |
| 7878 | Radarr | Media |
| 8010 | Homepage | Infra |
| 8090 | Gluetun control | Media |
| 8096 | Jellyfin | Media |
| 8181 | Tautulli | Media |
| 8191 | FlareSolverr | Media |
| 8686 | Lidarr (conditional) | Conditional |
| 8888 | Dozzle | Infra |
| 8989 | Sonarr | Media |
| 9000 | Portainer BE (HTTP) | Infra |
| 9443 | Portainer BE (HTTPS) | Infra |
| 9696 | Prowlarr | Media |
| 9999 | Zurg | Media |
| 10200 | Wyoming Piper | Voice |
| 10300 | Wyoming Whisper | Voice |
| 11434 | Ollama | AI |
| 13378 | Audiobookshelf (cond.) | Conditional |
| 32400 | Plex | Media |
