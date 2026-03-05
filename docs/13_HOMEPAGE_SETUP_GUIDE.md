# Homepage Dashboard Setup Guide

> Canonical architecture authority: [`docs/ARCHITECTURE_CANONICAL_2026.md`](ARCHITECTURE_CANONICAL_2026.md).


This guide covers deploying and configuring the [gethomepage/homepage](https://gethomepage.dev/) dashboard on your Unraid server so that it reflects the full AI home-lab ecosystem.

The finished dashboard is publicly accessible at: **https://homepage.happystrugglebus.us/**

---

## Overview

The `unraid/` directory in this repository contains two things:

| Path | Purpose |
|---|---|
| `unraid/docker-compose.yml` | Deploys Homepage, Uptime Kuma, Dozzle, Watchtower, and Tailscale |
| `unraid/homepage-config/` | Config files that Homepage reads from `/app/config` |

---

## 1. Deploy the Unraid stack

```bash
cd unraid
cp .env.example .env
# Edit .env — fill in TAILSCALE_AUTHKEY, HA_LONG_LIVED_TOKEN, TZ, etc.
docker compose up -d
```

The following services will start:

| Service | Port | URL |
|---|---|---|
| Homepage | 8010 | http://192.168.1.222:8010 |
| Uptime Kuma | 3010 | http://192.168.1.222:3010 |
| Dozzle | 8888 | http://192.168.1.222:8888 |
| Watchtower | — | background only |
| Tailscale | — | background VPN |

---

## 2. Copy homepage config to Unraid

Homepage reads its config from `/mnt/user/appdata/homepage/config` (mapped to `/app/config` inside the container).

Copy the config files from this repository:

```bash
cp -r unraid/homepage-config/* /mnt/user/appdata/homepage/config/
```

Or on a remote Unraid machine:

```bash
scp -r unraid/homepage-config/* root@192.168.1.222:/mnt/user/appdata/homepage/config/
```

Homepage hot-reloads — no container restart needed after copying.

---

## 3. Set the Home Assistant token

The `services.yaml` uses `{{HOMEPAGE_VAR_HA_TOKEN}}` to inject your HA long-lived access token without hardcoding it in the YAML.

Set the variable in `unraid/.env` (which is passed to the homepage container):

```env
HA_LONG_LIVED_TOKEN=your-token-here
```

Generate the token in Home Assistant at **Settings → Security → Long-lived access tokens**.

---

## 4. Ecosystem services shown on the dashboard

| Group | Service | IP:Port |
|---|---|---|
| Management | Homepage | 192.168.1.222:8010 |
| Management | Uptime Kuma | 192.168.1.222:3010 |
| Management | Dozzle | 192.168.1.222:8888 |
| Management | Command Center | 192.168.1.222:3099 |
| AI Gateway | LiteLLM Gateway | 192.168.1.222:4000 |
| AI Gateway | Node A Brain (vLLM) | 192.168.1.9:8000 |
| AI Gateway | Node A Brain (Ollama) | 192.168.1.9:11435 |
| Node C | Chimera Face (Open WebUI) | 192.168.1.6:3000 |
| Node C | Ollama Intel Arc | 192.168.1.6:11434 |
| Smart Home | Home Assistant | 192.168.1.149:8123 |
| Security | Sentinel (Node E) | 192.168.1.116:3005 |
| Security | KVM Operator | 192.168.1.222:5000 |

---

## 5. Troubleshooting

**400 Bad Request on the homepage**

The `docker-compose.yml` includes `HOMEPAGE_ALLOWED_HOSTS=*` which suppresses this error when accessing via a custom domain.

**Status dots show red for offline services**

This is expected if a service is not yet deployed. Deploy the relevant node and the status dot will turn green automatically.

**Uptime Kuma widget shows no data**

Create a status page named `default` in Uptime Kuma, then add your monitors to it. The widget slug must match (`slug: default`).

**Home Assistant widget shows no data**

Ensure `HA_LONG_LIVED_TOKEN` in `unraid/.env` is a valid long-lived token and that the container was restarted after setting it.
