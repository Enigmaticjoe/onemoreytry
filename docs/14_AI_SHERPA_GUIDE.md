# AI Sherpa — Installation Guide & Mobile Monitor

## Overview

The **AI Sherpa** is your digital IT guide for the Grand Unified AI Home Lab.  
It combines an interactive installation wizard with a live AI chatbot, so you always have expert help exactly when and where you need it.

Additionally, a **Mobile Monitor PWA** lets you check the status of every node and chat with the Sherpa from any Android or iOS device — no app store required.

---

## Features

### 🏔️ AI Sherpa (`/sherpa`)

| Feature | Description |
|---------|-------------|
| Step-by-step wizard | Sidebar with every installation step (Node A → E, KVM Operator, OpenClaw) |
| Contextual AI chat | Clicking a step primes the Sherpa with that node's context |
| System prompt | The Sherpa knows your exact node IPs, model names, and architecture |
| LiteLLM backend | Calls `/api/sherpa-chat` which uses the `brain-heavy` model via LiteLLM |
| Keyboard shortcut | Press **Enter** to send (Shift+Enter for newline) |

The Sherpa system prompt gives the AI expert knowledge of:
- Docker Compose commands for every node
- Intel Arc GPU environment variables
- LiteLLM config structure
- KVM Operator denylist and approval flow
- Home Assistant `extended_openai_conversation` setup

### 📱 Mobile Monitor (`/mobile`)

| Feature | Description |
|---------|-------------|
| PWA-ready | Add to Android/iOS home screen via browser "Add to Home Screen" |
| Auto-refresh | Service status tiles refresh automatically every 30 seconds |
| Touch-optimized | Large tiles, big tap targets, and dark theme |
| Sherpa chat | Inline chatbot for quick questions while monitoring |
| All services | Shows status and latency for every service check |

### 📋 PWA Manifest (`/manifest.json`)

The manifest enables Android and iOS "Add to Home Screen" support with:
- App name: **Grand Unified AI Home Lab**
- Short name: **Home Lab**
- Start URL: `/mobile`
- Display: `standalone` (full-screen app experience)
- Theme: dark (`#050811`)

---

## Accessing the Features

| URL | Description |
|-----|-------------|
| `http://<node-a-ip>:3099/sherpa` | AI Sherpa installation guide |
| `http://<node-a-ip>:3099/mobile` | Mobile monitor (PWA) |
| `http://<node-a-ip>:3099/manifest.json` | PWA manifest |
| `POST /api/sherpa-chat` | Sherpa API (JSON: `{"message": "..."}`) |

---

## Installing the Mobile App on Android

1. Open **Chrome** on your Android device.
2. Navigate to `http://<node-a-ip>:3099/mobile`
3. Tap the **⋮ menu** (top-right) → **Add to Home screen**
4. Name it **Home Lab** and tap **Add**
5. The app will appear on your home screen with a house icon 🏠

> **Tip**: Connect to the same Wi-Fi network as your home lab, or use Tailscale for remote access.

---

## How the Sherpa API Works

The `/api/sherpa-chat` endpoint calls LiteLLM with a specialized system prompt:

```
POST /api/sherpa-chat
Content-Type: application/json

{ "message": "How do I install Node C?" }
```

Response:
```json
{ "reply": "To install Node C (Intel Arc)…" }
```

Unlike the general `/api/chat` endpoint, the Sherpa endpoint always prepends a detailed system prompt that gives the AI full context about your home lab topology, node IPs, and best practices.

---

## Configuration

The Sherpa uses the same environment variables as the command center:

| Variable | Default | Purpose |
|----------|---------|---------|
| `LITELLM_BASE_URL` | `http://192.168.1.222:4000` | LiteLLM gateway for Sherpa chat |
| `LITELLM_API_KEY` | `sk-master-key` | API key for LiteLLM |
| `DEFAULT_MODEL` | `brain-heavy` | AI model used by the Sherpa |

---

## Troubleshooting

**Sherpa responds with "Unable to reach LiteLLM gateway"**  
→ Ensure Node B (LiteLLM) is running: `curl http://192.168.1.222:4000/health`

**Mobile page shows "Failed to load status"**  
→ Check that Node A command center is reachable on port 3099.

**Android "Add to Home Screen" not appearing**  
→ The manifest is served at `/manifest.json`. Ensure you are accessing the page over HTTP (not just a file).

---

*Related guides: [docs/10_UNIFIED_INSTALL_GUIDEBOOK.md](10_UNIFIED_INSTALL_GUIDEBOOK.md) · [docs/12_INSTALL_WIZARD_GUIDE.md](12_INSTALL_WIZARD_GUIDE.md)*
