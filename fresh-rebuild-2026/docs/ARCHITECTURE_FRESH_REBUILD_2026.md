# Fresh Rebuild 2026 — Architecture

> **Phase 1 baseline** · March 2026 · Minimal working multi-node homelab

## Goals

Tear down the accumulated complexity of previous iterations and start clean.
Phase 1 delivers exactly what is needed: local LLM inference on every capable
node and a single, unified chat interface — nothing more.

**Hard exclusions (Phase 1):** LiteLLM · OpenClaw · vLLM · KVM Operator ·
multiple Open WebUI instances · media stack changes.

---

## Node Map

| Node | Hardware | IP (LAN) | Role |
|------|----------|----------|------|
| **A** | Fedora 44 · RX 7900 XT (20 GB) | 192.168.1.9 | Ollama ROCm + Portainer Agent |
| **B** | Unraid · RTX 4070 (12 GB) | 192.168.1.222 | Ollama CUDA · n8n · infra dashboard |
| **C** | Fedora 44 · Arc A770 (16 GB) | 192.168.1.6 | **Single** Open WebUI (multi-backend) |
| **D** | Home Assistant OS | 192.168.1.149 | Direct Ollama API (no LiteLLM) |
| **E** | Proxmox / Blue Iris | 192.168.1.116 | Webhooks → HA (docs only, Phase 1) |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         HOME LAN  192.168.1.0/24                       │
│                                                                         │
│  ┌──────────────────┐       ┌──────────────────┐                       │
│  │   NODE A (Brain) │       │   NODE B (Brawn) │                       │
│  │  192.168.1.9     │       │  192.168.1.222    │                       │
│  │                  │       │                  │                       │
│  │  Ollama ROCm     │       │  Ollama CUDA     │                       │
│  │  :11435          │       │  :11434          │                       │
│  │                  │       │                  │                       │
│  │  Portainer Agent │       │  Portainer CE    │                       │
│  │  :9001           │       │  :9000 / :9443   │                       │
│  └────────┬─────────┘       │                  │                       │
│           │                 │  n8n   :5678     │                       │
│           │ Ollama API      │  Homepage :8010  │                       │
│           │                 │  Uptime K :3010  │                       │
│           │                 │  Dozzle  :8888   │                       │
│           │                 │  Watchtower      │                       │
│           │                 └────────┬─────────┘                       │
│           │                          │ Ollama API                      │
│           │                          │                                 │
│           └──────────┬───────────────┘                                 │
│                      │ OLLAMA_BASE_URLS                                 │
│                      ▼                                                  │
│           ┌──────────────────┐                                          │
│           │   NODE C (UI)    │                                          │
│           │  192.168.1.6     │                                          │
│           │                  │                                          │
│           │  Open WebUI      │◄──── Browser (LAN / Tailscale)          │
│           │  :3000           │                                          │
│           └──────────────────┘                                          │
│                                                                         │
│  ┌──────────────────┐       ┌──────────────────┐                       │
│  │   NODE D (HA)    │       │   NODE E (NVR)   │                       │
│  │  192.168.1.149   │       │  192.168.1.116    │                       │
│  │                  │       │                  │                       │
│  │  HA → Ollama     │       │  Webhooks → HA   │                       │
│  │  http://NodeB    │       │  (Phase 1: docs) │                       │
│  │  :11434 direct   │       │                  │                       │
│  └──────────────────┘       └──────────────────┘                       │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Port Map

### Node A — 192.168.1.9

| Port | Service | Protocol |
|------|---------|----------|
| 11435 | Ollama ROCm API | HTTP |
| 9001 | Portainer Agent | HTTP |

### Node B — 192.168.1.222

| Port | Service | Protocol |
|------|---------|----------|
| 11434 | Ollama CUDA API | HTTP |
| 9000 | Portainer CE (HTTP) | HTTP |
| 9443 | Portainer CE (HTTPS) | HTTPS |
| 8000 | Portainer Edge tunnel | TCP |
| 8010 | Homepage dashboard | HTTP |
| 3010 | Uptime Kuma | HTTP |
| 8888 | Dozzle log viewer | HTTP |
| 5678 | n8n workflow automation | HTTP |

### Node C — 192.168.1.6

| Port | Service | Protocol |
|------|---------|----------|
| 3000 | Open WebUI (single instance) | HTTP |

### Node D — 192.168.1.149

| Endpoint | Description |
|----------|-------------|
| http://192.168.1.222:11434 | Ollama API consumed by Home Assistant AI integrations |

---

## Deploy Order

```
Phase 1:
  1. Node A  — docker compose up -d          (Ollama ROCm + Portainer Agent)
  2. Node B  — docker compose -f stacks/01-infra.yml up -d
              docker compose -f stacks/02-ai.yml   up -d
  3. Node C  — docker compose up -d          (Open WebUI, after B is healthy)
  4. Node D  — manual HA configuration       (see node-d/README.md)
```

---

## Security Notes

- Ollama APIs are LAN-only by default (no public exposure).
- Portainer is LAN-only; use Tailscale for remote access.
- No secrets are committed; all sensitive values live in `.env` files.
- Generate tokens with `openssl rand -hex 32` or `openssl rand -base64 32`.
