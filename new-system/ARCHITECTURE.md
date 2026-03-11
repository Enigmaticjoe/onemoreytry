# Project Chimera — New System Architecture
> Node B · Unraid · 192.168.1.222 · RTX 4070 · 96 GB DDR5

## System Overview

```mermaid
graph TB
    subgraph VOICE["Voice & Chat Inputs"]
        AX[Alexa Smart Speaker]
        CHAT[Open WebUI Chat]
        BOT[Discord / Telegram Bot]
    end

    subgraph HA["Node D — Home Assistant 192.168.1.149"]
        HA_CORE[HA Core]
        EXTENDED[Extended OpenAI Conversation]
        WYOMING_IN[Wyoming STT Pipeline]
        WYOMING_OUT[Wyoming TTS Response]
        HA_AUTO[Automations & Scenes]
    end

    subgraph NODE_B["Node B — Unraid 192.168.1.222"]
        subgraph AI_STACK["Stack 02 — AI Core"]
            OLLAMA[Ollama\nRTX 4070 CUDA\n:11434]
            N8N[n8n Dispatcher\n:5678]
            WHISPER[Faster-Whisper\nGPU STT :9191]
            WYW[Wyoming-Whisper\n:10300]
            WYP[Wyoming-Piper\n:10200]
            SEARX[SearXNG\n:8082]
            OWU[Open WebUI\n:3002]
        end

        subgraph DUMB["Stack 03 — DUMB Core (Real-Debrid)"]
            ZURG[Zurg WebDAV\n:9999]
            RCLONE[rclone FUSE\n/mnt/debrid]
            RIVEN[Riven Engine\n:8080]
            RIVFE[Riven Frontend\n:3001]
            ZILEAN[Zilean Cache\n:8181]
        end

        subgraph ARR["Stack 04 — Media *arr"]
            PROWLARR[Prowlarr\n:9696]
            SONARR[Sonarr :8989]
            RADARR[Radarr :7878]
            LIDARR[Lidarr :8686]
            READARR[Readarr :8787]
            BAZARR[Bazarr :6767]
            DECYPHARR[Decypharr\nVirtual RD Client :8282]
            DECLUTTARR[Decluttarr]
        end

        subgraph SERVERS["Stack 05 — Media Servers"]
            PLEX[Plex :32400\nNVIDIA NVENC]
            JF[Jellyfin :8096\nNVIDIA NVENC]
            NAVI[Navidrome :4533]
            ABS[Audiobookshelf\n:13378]
            STREMIO[Stremio :11470]
        end

        subgraph BOOKS["Stack 06 — Books & Games"]
            CALIBRE[Calibre-Web :8083]
            KAVITA[Kavita :5000]
            GAMEVAULT[GameVault :8998]
            ROMM[Romm :9083]
        end

        subgraph MGMT["Stack 07 — Media Management"]
            OVERSEERR[Overseerr :5055]
            TAUTULLI[Tautulli :8181]
            MAINTAINERR[Maintainerr :6246]
            RECYCLARR[Recyclarr]
            HUNTARR[Huntarr :9705]
            NOTIFIARR[Notifiarr :5454]
            KOMETA[Kometa daily 04:00]
        end

        subgraph INFRA["Stack 01 — Infrastructure"]
            PORTAINER[Portainer :9000]
            HOMEPAGE[Homepage :8010]
            KUMA[Uptime Kuma :3010]
            DOZZLE[Dozzle :8888]
            TS[Tailscale VPN]
            CF[Cloudflared Tunnel]
            WIZARR[Wizarr :5690]
        end
    end

    subgraph STORAGE["DUMB Storage Layer"]
        RD[Real-Debrid Cloud\nInstant Cache]
        SYMLINKS[/mnt/debrid/riven_symlinks\nPlex + Jellyfin Library]
        LOCALMEDIA[/mnt/user/DUMB\nMusic · Books · Games]
    end

    subgraph OTHER["Other Nodes"]
        NODE_A[Node A Brain\n192.168.1.9\nROCm vLLM]
        NODE_C[Node C Chimera Face\n192.168.1.6\nOpen WebUI + Arc GPU]
        NODE_E[Node E Sentinel\n192.168.1.116\nFrigate NVR]
    end

    %% Voice pipeline
    AX -->|Alexa Skill / Nabu Casa| HA_CORE
    CHAT -->|webhook| N8N
    HA_CORE --> EXTENDED
    EXTENDED -->|OpenAI API| OLLAMA
    AX -->|Alexa Routine| WYOMING_IN
    WYOMING_IN -->|Wyoming Protocol| WYW
    WYW -->|transcribed text| N8N
    N8N -->|classify intent| OLLAMA
    OLLAMA -->|structured JSON| N8N

    %% Media dispatch
    N8N -->|POST /api/v1/request| OVERSEERR
    N8N -->|direct API| RADARR
    N8N -->|direct API| SONARR
    N8N -->|direct API| READARR
    N8N -->|POST /riven/request| RIVEN
    N8N -->|HA webhook| HA_AUTO
    HA_AUTO -->|notify| WYOMING_OUT
    WYOMING_OUT --> WYP

    %% DUMB acquisition chain
    OVERSEERR --> RIVEN
    RIVEN -->|scrape| ZILEAN
    RIVEN -->|resolve via RD API| RD
    RD -->|WebDAV| ZURG
    ZURG -->|FUSE mount| RCLONE
    RCLONE --> SYMLINKS
    RIVEN -->|symlink create| SYMLINKS
    RIVEN -->|library scan trigger| PLEX
    RIVEN -->|library scan trigger| JF

    %% *arr path (for music/books, or non-cached content)
    PROWLARR --> SONARR & RADARR & LIDARR & READARR
    SONARR & RADARR -->|"download client (magnet → RD)"| DECYPHARR
    DECYPHARR -->|RD API| RD
    LIDARR -->|download| LOCALMEDIA
    READARR -->|download| LOCALMEDIA
    DECLUTTARR -.->|clean stalled| SONARR & RADARR

    %% Serving
    PLEX & JF -->|read symlinks| SYMLINKS
    NAVI -->|read| LOCALMEDIA
    ABS -->|read| LOCALMEDIA
    CALIBRE & KAVITA -->|read books| LOCALMEDIA
    GAMEVAULT & ROMM -->|read games/ROMs| LOCALMEDIA

    %% Analytics → AI → automations
    TAUTULLI -->|webhook on play| HA_AUTO
    TAUTULLI -->|watch data| N8N

    %% Management
    KOMETA -.->|overlay collections| PLEX
    MAINTAINERR -.->|delete watched| PLEX & RADARR & SONARR
    RECYCLARR -.->|sync quality profiles| SONARR & RADARR
    HUNTARR -.->|trigger missing searches| SONARR & RADARR
    NOTIFIARR -.->|Discord notifications| PLEX

    %% Infrastructure
    PORTAINER -->|manage| ARR & SERVERS & DUMB
    TS -->|remote access| NODE_B
    CF -->|public tunnel| OVERSEERR & OWU

    %% Other nodes
    NODE_A -->|heavy inference| N8N
    NODE_C -->|shared chat UI| CHAT
    NODE_E -->|motion events| HA_CORE
```

---

## Port Map — Node B (192.168.1.222)

| Port | Service | Stack |
|------|---------|-------|
| 8010 | Homepage dashboard | 01-infra |
| 3010 | Uptime Kuma | 01-infra |
| 8888 | Dozzle logs | 01-infra |
| 9000/9443 | Portainer | 01-infra |
| 5690 | Wizarr | 01-infra |
| 11434 | Ollama CUDA | 02-ai |
| 5678 | n8n | 02-ai |
| 9191 | Whisper API | 02-ai |
| 10300 | Wyoming Whisper STT | 02-ai |
| 10200 | Wyoming Piper TTS | 02-ai |
| 8082 | SearXNG | 02-ai |
| 3002 | Open WebUI | 02-ai |
| 9999 | Zurg WebDAV | 03-dumb-core |
| 8080 | Riven backend | 03-dumb-core |
| 3001 | Riven frontend | 03-dumb-core |
| 8181 | Zilean | 03-dumb-core |
| 8090 | Gluetun proxy | 04-media-arr |
| 8191 | FlareSolverr | 04-media-arr |
| 9696 | Prowlarr | 04-media-arr |
| 8989 | Sonarr | 04-media-arr |
| 7878 | Radarr | 04-media-arr |
| 8686 | Lidarr | 04-media-arr |
| 8787 | Readarr | 04-media-arr |
| 6767 | Bazarr | 04-media-arr |
| 8282 | Decypharr | 04-media-arr |
| 32400 | Plex (host network) | 05-media-servers |
| 8096/8920 | Jellyfin | 05-media-servers |
| 4533 | Navidrome | 05-media-servers |
| 13378 | Audiobookshelf | 05-media-servers |
| 11470 | Stremio | 05-media-servers |
| 8083 | Calibre-Web | 06-media-books-games |
| 5000 | Kavita | 06-media-books-games |
| 25600 | Komga | 06-media-books-games |
| 8998 | GameVault | 06-media-books-games |
| 9083 | Romm | 06-media-books-games |
| 5055 | Overseerr | 07-media-mgmt |
| 8181 | Tautulli | 07-media-mgmt |
| 6246 | Maintainerr | 07-media-mgmt |
| 9705 | Huntarr | 07-media-mgmt |
| 5454 | Notifiarr | 07-media-mgmt |

---

## Storage Layout

```
/mnt/user/appdata/DUMB/     ← All container config (PUID=99 PGID=100)
  ├── zurg/
  │   └── config.yaml       ← EDIT: add Real-Debrid API token
  ├── rclone/
  │   └── rclone.conf       ← Auto-generated by setup-mounts.sh
  ├── riven/
  ├── ollama/               ← Model weights (~5-15 GB per model)
  ├── plex/
  ├── jellyfin/
  └── ...

/mnt/user/DUMB/             ← Local media files
  ├── music/                ← Lidarr → Navidrome
  ├── audiobooks/           ← Manual → Audiobookshelf
  ├── books/                ← Readarr → Calibre-Web, Kavita
  ├── comics/               ← Manual → Kavita, Komga
  ├── games/                ← Manual → GameVault
  ├── roms/                 ← Manual → Romm
  └── downloads/            ← Gluetun/qBittorrent fallback

/mnt/debrid/                ← rclone FUSE mount (Real-Debrid via Zurg)
  ├── shows/                ← Zurg-organized TV content
  ├── movies/               ← Zurg-organized movies
  └── riven_symlinks/       ← Riven-created symlinks ← Plex + Jellyfin read HERE
      ├── movies/
      │   └── Dune Part Two (2024)/
      │       └── Dune.Part.Two.2024.2160p.mkv → /mnt/debrid/movies/...
      └── shows/
          └── Severance (2022)/
              └── Season 01/
                  └── S01E01.mkv → /mnt/debrid/shows/...
```

---

## Request Lifecycle — "Alexa, add Dune 3"

```
1. User: "Alexa, add Dune 3 to my movies"
   └─► Alexa Routine → HA Script: chimera_media_request
                                 command="add Dune 3 to my movies"

2. HA rest_command → POST http://192.168.1.222:5678/webhook/media-request
   body: { "command": "add Dune 3 to my movies", "source": "alexa" }

3. n8n Webhook trigger → Ollama node (llama3.1:8b)
   Prompt: "classify this media request as JSON"
   Response: { "action": "add", "media_type": "movie", "title": "Dune 3", "confidence": 0.95 }

4. n8n Switch → Route: action=add, type=movie
   → POST http://overseerr:5055/api/v1/request
     body: { "mediaType": "movie", "mediaId": <tmdb_id> }

5. Overseerr → notifies Riven (via webhook or Riven polls Overseerr)

6. Riven → Torrentio scraper finds best 2160p cached result
   → Real-Debrid API: check cache → ✓ cached → resolve
   → Creates symlink: /mnt/debrid/riven_symlinks/movies/Dune 3 (2026)/...

7. Riven → POST http://plex:32400/library/sections/1/refresh
   → Plex picks up the new symlink within seconds

8. n8n → POST http://HA:8123/api/webhook/chimera_media_ready
   body: { "message": "Dune 3 has been added to your library in 4K." }

9. HA automation → service: tts.speak (Piper TTS)
   "Dune 3 has been added to your library in 4K."
   └─► Speaker plays the response

Total time from voice command to available in Plex: ~30-60 seconds
```
