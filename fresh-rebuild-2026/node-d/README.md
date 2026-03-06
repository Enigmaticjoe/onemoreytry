# Fresh Rebuild 2026 — Node D (Home Assistant)
# Home Assistant OS · 192.168.1.149
#
# Phase 1: Documentation only — no Docker deployment required.
# HA connects directly to the Ollama API on Node B.

## What Node D Does in Phase 1

Home Assistant consumes the Ollama API on Node B for:

- **Conversation Agent** — talk to your home via voice or text using a local LLM
- **AI-powered automations** — summarise sensor data, generate TTS messages, etc.

No LiteLLM proxy is involved. HA talks directly to Ollama.

---

## Connecting Home Assistant to Node B Ollama

### Step 1 — Install the Ollama integration

1. Open HA → **Settings → Devices & Services → Add Integration**
2. Search for **"Ollama"** and install it
3. Set the **URL** to:
   ```
   http://192.168.1.222:11434
   ```
4. Choose a model that is already pulled on Node B (e.g. `llama3.1:8b`).

> **Tip:** Pull models on Node B first:
> ```bash
> docker exec ollama ollama pull llama3.1:8b
> ```

### Step 2 — Set as Conversation Agent (optional)

1. HA → **Settings → Voice Assistants → Edit your assistant**
2. Change **Conversation agent** to **Ollama (local)**

### Step 3 — Verify

From the HA Developer Tools → Template editor, test:

```yaml
{{ states('sensor.temperature') }}
```

Then trigger an Ollama service call in an automation to confirm the connection.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Connection refused` | Verify Node B Ollama is running: `curl http://192.168.1.222:11434/api/version` |
| `Model not found` | Pull the model: `docker exec ollama ollama pull <model>` |
| Slow responses | Use a smaller model (e.g. `phi4-mini`, `qwen2.5:3b`) for HA automations |
| HA on different VLAN | Add a firewall rule allowing HA → Node B TCP/11434 |

---

## Node E (Proxmox / Blue Iris) — Phase 1 Note

Node E sends webhooks to Home Assistant for camera motion events and VM alerts.
No Docker deployment is needed on Node E in Phase 1.

Configure HA automations to receive these webhooks:

```yaml
# configuration.yaml
automation:
  - alias: "Node E — Camera motion alert"
    trigger:
      platform: webhook
      webhook_id: node-e-camera-motion
    action:
      service: notify.persistent_notification
      data:
        message: "Camera motion detected: {{ trigger.json.camera }}"
```

Webhook URL for Blue Iris / Proxmox to call:
```
http://192.168.1.149:8123/api/webhook/node-e-camera-motion
```
