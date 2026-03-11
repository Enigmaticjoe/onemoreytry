# Project Chimera — Voice & AI Control Guide
> "Say it. Chimera handles the rest."

This guide shows you exactly how to connect Alexa, Home Assistant, and your AI ecosystem so that voice commands, chat messages, and smart home triggers all flow through to your media server — and responses come back spoken aloud.

---

## How It All Connects

```
YOU SAY:                    "Alexa, add Inception to my movies"
          │
          ▼
ALEXA:    Alexa Routine triggers HA Script "chimera_media_request"
          │
          ▼
HOME      rest_command.chimera_media_request
ASSISTANT:  → POST http://192.168.1.222:5678/webhook/media-request
          │   { "command": "add Inception to my movies", "source": "alexa" }
          │
          ▼
N8N:      Webhook trigger → Ollama (llama3.1:8b) classifies intent
          → { action: "add", media_type: "movie", title: "Inception" }
          → Routes to Overseerr API → Riven → Real-Debrid → Plex
          → Posts result back to HA webhook
          │
          ▼
HA TTS:   "Inception has been added to your library in 4K."
          └─► Piper TTS speaks through your speaker
```

---

## Step-by-Step Setup

### Step 1 — Deploy Stack 02 (AI Core)

```bash
cd new-system
docker compose -f stacks/02-ai.yml up -d

# Pull the AI model (takes 5-10 min first time)
docker exec ollama ollama pull llama3.1:8b
docker exec ollama ollama pull nomic-embed-text
```

**Verify:**
```bash
curl http://192.168.1.222:11434/api/version
# Expected: {"version":"0.x.x"}

curl http://192.168.1.222:5678/healthz
# Expected: {"status":"ok"}
```

---

### Step 2 — Configure n8n

1. Open `http://192.168.1.222:5678` → create your admin account
2. **Add Ollama credential:**
   - Credentials → New → Ollama
   - Base URL: `http://ollama:11434`
3. **Add Overseerr credential:**
   - Credentials → New → Header Auth
   - Name: `Overseerr API`
   - Header Name: `X-Api-Key`
   - Header Value: your `OVERSEERR_API_KEY`
4. **Import the workflow:**
   - Workflows → Import from file
   - Select `n8n-workflows/media-voice-request.json`
5. **Activate the workflow** (toggle in top-right corner)

**Test it from terminal:**
```bash
curl -X POST http://192.168.1.222:5678/webhook/media-request \
  -H 'Content-Type: application/json' \
  -d '{"command": "add the movie Dune", "source": "test"}'

# Expected response:
# {"status":"ok","message":"Got it! I've sent a request for Dune to the movie library..."}
```

---

### Step 3 — Configure Home Assistant

Add to your HA `configuration.yaml` (or use packages):

```yaml
# Copy contents of new-system/home-assistant/configuration-snippet.yaml
# into /config/configuration.yaml on Node D (192.168.1.149)
```

Add to `/config/secrets.yaml`:
```yaml
ollama_api_key: sk-none
ha_self_token: your-ha-long-lived-access-token
```

Restart HA:
```bash
# HA UI → Settings → System → Restart
# or via CLI on Node D:
ha core restart
```

---

### Step 4 — Configure Voice Pipeline (Wyoming)

In Home Assistant:

1. **Settings → Integrations → Add Integration → Wyoming Protocol**
   - Add twice: once for Whisper (STT), once for Piper (TTS)

2. **Wyoming Whisper (Speech-to-Text):**
   - Host: `192.168.1.222`
   - Port: `10300`

3. **Wyoming Piper (Text-to-Speech):**
   - Host: `192.168.1.222`
   - Port: `10200`

4. **Settings → Voice Assistants → Add Assistant:**
   - Name: `Chimera`
   - Conversation agent: `Extended OpenAI Conversation` (after HACS install)
   - Speech-to-text: `Wyoming (faster-whisper)`
   - Text-to-speech: `Wyoming (piper)`
   - Wake word: your choice (Alexa, Hey Jarvis, etc.)

---

### Step 5 — Extended OpenAI Conversation (HACS)

This is what makes HA "smart" — it can control lights AND add media.

1. **Install HACS** if not already done: `hacs.xyz`
2. **HACS → Integrations → Search: "Extended OpenAI Conversation"**
3. **Install → Restart HA**
4. **Settings → Integrations → Add: Extended OpenAI Conversation**
   - API Key: `sk-none`
   - Base URL: `http://192.168.1.222:11434/v1`
   - Model: `llama3.1:8b`
5. **Set as Conversation Agent** in your Voice Assistant settings

The system prompt in `configuration-snippet.yaml` instructs the model to:
- Control HA devices naturally
- Route media requests to n8n automatically
- Speak back confirmed actions

---

### Step 6 — Alexa Integration

**Option A: Nabu Casa (Recommended — easiest)**
- Subscribe at `nabucasa.com` (~$6.50/month)
- In HA: Settings → Home Assistant Cloud → Enable Alexa
- In Alexa app: discover devices
- Alexa can now control HA + trigger your voice assistant

**Option B: Custom Alexa Skill**
- Use the `Alexa Smart Home` HA integration (free, requires public HA URL)
- Configure via Cloudflared tunnel as your public URL

**Creating Alexa Routines for Media:**

In the Alexa app:
1. More → Routines → Create Routine
2. When: "Alexa, add [movie name]" (custom phrase)
3. Action: Smart Home → `chimera_media_request` script
   - Or: Send HA notification with the phrase as payload

The cleanest approach: **Alexa Routine → HA Webhook → n8n**
```
Alexa routine:
  Trigger: "Alexa, add [title]"  (use a variable-phrase routine)
  Action: Call HA service
    Service: rest_command.chimera_media_request
    Data: { "command": "add [title]", "source": "alexa" }
```

---

## Voice Commands Reference

| What You Say | What Happens |
|---|---|
| "Alexa, add Dune 3 to my movies" | n8n → Overseerr → Riven → Plex (30-60s) |
| "Alexa, add Severance season 2" | n8n → Sonarr → RD → Plex |
| "Alexa, add the book Dune by Frank Herbert" | n8n → Readarr → Calibre-Web |
| "Alexa, what's in the download queue?" | n8n → Riven status → spoken response |
| "Alexa, search for Christopher Nolan movies" | n8n → Overseerr search → spoken results |
| "Hey Chimera, movie night" | HA scene: dim lights, turn on TV, open Plex |
| "Hey Chimera, what's playing?" | HA → Tautulli → spoken Now Playing info |

---

## Chat Interface (Open WebUI)

For text-based requests without voice:

1. Open `http://192.168.1.222:3002`
2. Create your account
3. Type naturally: `"Add the movie Arrival to my library"`
4. The AI responds and dispatches to the appropriate service

**Enable the media request function call:**

In Open WebUI: Settings → Workspace → Functions → Create Function

```python
"""
name: chimera_media_request
description: Add movies, TV shows, books, or music to the Chimera media library
parameters:
  command: string (the media request in natural language)
"""
import requests
def chimera_media_request(command: str) -> str:
    r = requests.post(
        "http://192.168.1.222:5678/webhook/media-request",
        json={"command": command, "source": "open_webui"},
        timeout=30
    )
    return r.json().get("message", "Request sent.")
```

---

## Troubleshooting

### "Alexa doesn't understand my custom routine"
Alexa Routines with free-text phrases can be finicky. Use **exact trigger phrases** like "add a movie" and pair with HA input_text helpers that users fill in separately, OR use Nabu Casa + HA Voice pipeline directly.

### "n8n says 'unauthorized' when calling Overseerr"
Your `OVERSEERR_API_KEY` in `.env` is wrong or empty. Get the correct key from: `Overseerr → Settings → General → API Key`.

### "Ollama classifies wrong media type"
Try a different model: `docker exec ollama ollama pull qwen2.5:7b` and update the workflow's Ollama node to use `qwen2.5:7b`. It has stronger instruction following.

### "HA doesn't speak the response"
Check that:
1. `wyoming-piper` container is running: `docker ps | grep piper`
2. Wyoming TTS is configured in HA Voice Assistants
3. Your speaker entity is correct in the `chimera_speak` script

### "Riven doesn't find the movie on Real-Debrid"
The content may not be cached on RD. Riven only uses cached results by default. Workaround: add it manually via Radarr + Decypharr, which will wait for a torrent to be cached.
