# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Validation (Run After Every Change)

```bash
bash validate.sh
```

411 tests must pass. This is the single source of truth — if it fails, the change is wrong. Run after modifying any YAML, compose file, or config. The script validates YAML syntax, LiteLLM model routing, Intel Arc GPU config, Home Assistant integration, nodebfinal stacks, and n8n workflow structure.

## Deployment Scripts

```bash
# Deploy all stacks (Node B context)
bash scripts/deploy-all.sh

# Deploy new-system stacks only
bash new-system/scripts/deploy-all.sh [--dry-run] [--stack N]

# Verify service health
bash new-system/scripts/verify-all.sh [--media] [--ai]

# SSH audit / connectivity check
bash scripts/ssh-auditor.sh

# Preflight checks before deployment
bash scripts/preflight-check.sh

# Reconcile nodebfinal (cleanup + optional redeploy)
bash nodebfinal/scripts/reconcile-nodeb.sh [--apply]

# Mount setup (run once on Unraid before DUMB stack)
bash new-system/scripts/setup-mounts.sh
```

## Interactive Installer

```bash
python3 bos.py
```

Menu-driven TUI (Python 3.8+, no extra deps). Options: system health, prereqs, venv, env config, service ops, AI setup, help chat, logs, full guided install.

## Architecture

### Node Roles

| Node | IP | Role |
|------|-----|------|
| A | 192.168.1.9 | Inference — ROCm/vLLM, Ollama :11434 |
| B | 192.168.1.222 | Operations — Portainer :9443, n8n :5678, Ollama :11434 |
| C | 192.168.1.6 | UI — Open WebUI :3000, Ollama :11434, Intel Arc |
| D | 192.168.1.149 | Home automation — Home Assistant :8123 |
| E | — | Surveillance / extras |

### Two Active Deployment Systems

**`nodebfinal/`** — Mature, optimized Node B stack (8 Docker Compose files, ~24 containers, LiteLLM gateway). Deploy in order 01→08. The `validate.sh` suite is written against this directory.

**`new-system/`** — Project Chimera full rewrite (7 stacks, ~30 containers). Adds DUMB/Real-Debrid core, Alexa voice pipeline, Riven symlink engine. Supersedes nodebfinal for new deployments.

### nodebfinal Stack Order

```
01-infra-stack.yml       → Portainer, Homepage, Uptime Kuma, Tailscale, Cloudflared
02-ai-stack.yml          → Ollama (CUDA), LiteLLM gateway (:4000), Browserless
03-media-stack.yml       → *arr suite, Plex, Jellyfin, Overseerr, Tautulli
04-automation-stack.yml  → n8n (:5678), Recommendarr
05-voice-stack.yml       → Wyoming Whisper (:10300 STT), Piper (:10200 TTS)
06-conditional-stack.yml → Lidarr, Audiobookshelf (optional)
07-ai-orchestration-stack.yml → Open WebUI, Qdrant, Redis, SearXNG, TEI embed
08-cloud-apps-stack.yml  → Nextcloud, Stremio (optional)
```

LiteLLM at `nodebfinal/litellm-config.yaml` routes 5 model aliases across Nodes A/B/C. All AI clients (HA, Open WebUI, n8n) use `http://192.168.1.222:4000/v1`.

### new-system Stack Order

```
01-infra.yml       → Portainer, Homepage (:8010), Uptime Kuma, Dozzle, Watchtower, Tailscale, Cloudflared, Wizarr
02-ai.yml          → Ollama (CUDA), n8n, Faster-Whisper-GPU (:9191), Wyoming Whisper/Piper, SearXNG, Open WebUI
03-dumb-core.yml   → Zurg (WebDAV :9999), rclone FUSE mount, Riven (:3001/:8080), Zilean (:8181)
04-media-arr.yml   → Gluetun VPN, Decypharr (:8282), Prowlarr, Sonarr, Radarr, Lidarr, Readarr, Bazarr, Decluttarr
05-media-servers.yml → Plex (host network), Jellyfin, Navidrome, Audiobookshelf, Stremio
06-media-books-games.yml → Calibre-Web, Kavita, Komga, GameVault+PostgreSQL, Romm+MariaDB
07-media-mgmt.yml  → Overseerr, Tautulli, Maintainerr, Recyclarr, Huntarr, Notifiarr, Kometa
```

### DUMB AIO (Real-Debrid) Data Flow

```
Real-Debrid API → Zurg (WebDAV) → rclone FUSE mount (/mnt/debrid)
  → Riven (scrape + symlinks at /mnt/debrid/riven_symlinks)
  → Plex/Jellyfin read symlinks only (no local video downloads)
```

Critical requirements:
- `rclone --vfs-cache-mode full --vfs-cache-max-size 20G` — mandatory for Plex 4K direct play
- `/mnt/debrid` must be `rshared` bind-mounted before containers start (`setup-mounts.sh`)
- Riven image: `ghcr.io/rivenmedia/riven:latest` (not the old `spoked/riven`)

### Voice Request Pipeline

```
Alexa Routine → HA script → rest_command POST → n8n webhook (:5678/webhook/media-request)
  → Ollama llama3.1:8b (classify intent to JSON) → Switch on action/media_type
  → Overseerr/Sonarr/Radarr/Riven API → HA webhook (chimera_media_ready) → Piper TTS speaks
```

n8n workflows live in `*/n8n-workflows/*.json`. Import via n8n UI or mount the directory.

## Technical Standards (from copilot-instructions.md)

- **PUID=99, PGID=100** on all Unraid containers (nobody:users)
- **Appdata:** `/mnt/user/appdata/DUMB/<service>` (new-system) or `/mnt/user/appdata/<service>` (nodebfinal)
- **Media root:** `/mnt/user/DUMB`
- **DUMB mounts:** `DEBRID_MOUNT=/mnt/debrid`, `RIVEN_SYMLINKS=/mnt/debrid/riven_symlinks`
- **No hardcoded secrets** — always `.env` files; use `${VAR:-}` for optional vars
- **Atomic env writes:** `mktemp → write → mv` pattern in scripts
- **Kometa image:** `kometateam/kometa:latest` (never the deprecated `meisnate12/plexmetamanager`)
- **Readarr tag:** `lscr.io/linuxserver/readarr:develop` (no stable release)
- **Plex:** must be `network_mode: host` for multicast discovery; Jellyfin uses bridge
- **n8n AI nodes** in nodebfinal use `OLLAMA_BASE_URL=http://ollama:11434` (direct Ollama, not LiteLLM)

## Key Config Files

| File | Purpose |
|------|---------|
| `nodebfinal/litellm-config.yaml` | Model routing (5 aliases → 3 nodes) |
| `nodebfinal/.env.example` | All secrets template for nodebfinal |
| `new-system/.env.example` | All secrets template for new-system |
| `new-system/docs/zurg-config-template.yaml` | Zurg WebDAV daemon config |
| `new-system/docs/recyclarr-template.yml` | TRaSH Guides quality profile sync |
| `new-system/docs/kometa-config.yml` | Plex overlays + collections config |
| `new-system/docs/homepage-config/` | Homepage dashboard YAML (services/settings/widgets) |
| `new-system/home-assistant/` | HA config snippets for voice + Alexa |

## Docker Networks

| Network | Used By |
|---------|---------|
| `infra` | Infrastructure services |
| `ai` | Ollama, n8n, Open WebUI, voice containers |
| `media` | All *arr, media servers, Overseerr |
| `automation` | n8n, Recommendarr (nodebfinal) |

n8n must join both `ai` and `media` (and `automation` in nodebfinal) to bridge all services.

## Homepage Dashboard Env Vars

Homepage reads `{{HOMEPAGE_VAR_*}}` templates from the container environment. All vars are documented in `new-system/docs/homepage-config/homepage-env-additions.env`. Append to `.env` with:

```bash
cat new-system/docs/homepage-config/homepage-env-additions.env >> .env
```
