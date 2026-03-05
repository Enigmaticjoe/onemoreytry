# Node E — Sentinel / NVR Vision: Layman's Guide

> Canonical architecture authority: [`docs/ARCHITECTURE_CANONICAL_2026.md`](ARCHITECTURE_CANONICAL_2026.md).


> **Who this guide is for:** Anyone who wants to add AI-powered security camera analysis to their home lab. If you've ever wished your cameras could tell you *what* they see instead of just recording footage, this is for you.

---

## What Is Node E?

Node E runs **Sentinel** — the vision AI service that watches your cameras and describes what it sees in plain English.

Think of it like hiring a security guard who never sleeps, never blinks, and can tell you "a person is walking up your driveway" or "a delivery truck just parked out front" — automatically, the moment it happens.

- Port: **3005**
- Nickname: **Sentinel / The Eyes**
- Depends on: Node C (for AI vision analysis via Ollama + llava)

---

## How Sentinel Works — The Big Picture

```
Camera → Frigate (detects motion/objects)
           ↓
         Frigate sends a webhook to Sentinel
           ↓
         Sentinel grabs a snapshot of the event
           ↓
         Sentinel asks Node C's Ollama (llava model) "What do you see?"
           ↓
         Ollama responds with a plain English description
           ↓
         Sentinel forwards the description to Home Assistant
           ↓
         Home Assistant sends you a notification: "Person at front door"
```

Every step is automatic. You set it up once, and it runs on its own.

---

## What Is Frigate? (Plain English)

Frigate is a **free, open-source camera NVR** (Network Video Recorder). Think of it as the smart recorder that:

- Records your camera streams 24/7
- Uses AI to detect when specific objects appear (people, cars, animals, packages)
- Only saves video clips when something interesting happens
- Sends alerts to other services (like Sentinel) when it detects something

Frigate does the "is there something there?" detection. Sentinel then asks your AI lab "what exactly is happening?" — which gives you much richer descriptions.

---

## Deploying Node E Sentinel — Step by Step

### Step 1: Make Sure Node C Is Running

Sentinel relies entirely on Node C's Ollama for its AI analysis. Before setting up Sentinel, verify Node C is alive:

```bash
curl http://192.168.1.6:11434/api/tags
```

You should see a list of available models. Make sure `llava` is in the list. If it's not:

```bash
# Run this on Node C
ollama pull llava
```

### Step 2: Configure the Environment Variables

Create a `.env` file in the node-e-sentinel directory:

```bash
# Sentinel auth token (make this something hard to guess)
SENTINEL_TOKEN=your-secret-token-here

# Where to find Node C's Ollama
OLLAMA_BASE_URL=http://192.168.1.6:11434

# Which vision model to use
VISION_MODEL=llava

# Home Assistant connection (for sending alerts)
HA_URL=http://192.168.1.149:8123
HA_TOKEN=your-home-assistant-long-lived-token
```

### Step 3: Start Sentinel

```bash
node node-e-sentinel.js
```

Or if running as a service:

```bash
# Using PM2 (process manager) to keep it running
npm install -g pm2
pm2 start node-e-sentinel.js --name sentinel
pm2 save
pm2 startup
```

The last two commands make Sentinel start automatically when the machine reboots.

### Step 4: Verify It's Running

```bash
curl http://localhost:3005/health
```

You should get:

```json
{"status": "ok", "vision_backend": "http://192.168.1.6:11434"}
```

---

## Sentinel's Endpoints — Plain English

Sentinel has two main "doors" that other services knock on:

| Endpoint | URL | What It Does |
|---|---|---|
| **Health check** | `GET /health` | Confirms Sentinel is alive and connected to Node C |
| **Analyze image** | `POST /api/analyze` | Send it a photo URL or base64 image, get back a description |
| **Frigate webhook** | `POST /api/webhook/frigate` | Frigate sends events here automatically |

### Testing the Analyze Endpoint

```bash
curl -X POST http://192.168.1.x:3005/api/analyze \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-secret-token-here" \
  -d '{
    "image_url": "https://example.com/test-image.jpg",
    "prompt": "Describe what you see in this image."
  }'
```

Response will look like:

```json
{
  "description": "The image shows a person in a dark jacket standing near a door. They appear to be facing the camera."
}
```

---

## SENTINEL_TOKEN — What It Is and How to Set It

The `SENTINEL_TOKEN` is a password that protects Sentinel's API from unauthorized access. Without it, anyone on your network could send fake camera events to Sentinel.

Think of it as the lock on Sentinel's front door — only Frigate (and you) know the key.

### Setting the token

In your `.env` file:

```
SENTINEL_TOKEN=my-super-secret-camera-token-2024
```

Make it at least 20 characters. No spaces. Mix letters and numbers.

### Using the token in requests

Every request to Sentinel must include the token as a header:

```
Authorization: Bearer my-super-secret-camera-token-2024
```

If the token is wrong or missing, Sentinel responds with `401 Unauthorized`.

---

## Connecting Frigate Webhooks to Sentinel

### Step 1: Find Your Frigate Config

Frigate's config file is usually at `/config/config.yaml` inside the Frigate container.

### Step 2: Add a Webhook Notification

```yaml
# Inside Frigate's config.yaml
notifications:
  webhooks:
    - name: sentinel
      url: http://192.168.1.x:3005/api/webhook/frigate
      events:
        - new_snapshot
      headers:
        Authorization: "Bearer your-secret-token-here"
      body:
        camera: "{camera}"
        label: "{label}"
        score: "{score}"
        snapshot_url: "{snapshot_url}"
```

Replace `192.168.1.x` with Node E's actual IP address.

### Step 3: Restart Frigate

After saving the config, restart Frigate. It will now automatically notify Sentinel whenever it detects something.

---

## The Full Vision Pipeline — Step by Step

Here's exactly what happens when your doorbell camera detects motion:

1. **Your camera** sends a video stream to Frigate
2. **Frigate** analyzes the stream and detects a "person" with 94% confidence
3. **Frigate** takes a snapshot photo and sends it to Sentinel via webhook:
   ```
   POST /api/webhook/frigate
   { "camera": "front_door", "label": "person", "snapshot_url": "..." }
   ```
4. **Sentinel** receives the webhook, downloads the snapshot image
5. **Sentinel** sends the image to Node C's Ollama:
   ```
   "Here is a security camera snapshot. Describe what you see in detail."
   ```
6. **Node C's llava model** analyzes the image and responds:
   ```
   "A person wearing a brown uniform is standing at the front door holding a brown cardboard box."
   ```
7. **Sentinel** packages this description and sends it to Home Assistant
8. **Home Assistant** triggers a notification to your phone:
   ```
   📦 Front door: A delivery person is at the door with a package.
   ```

Total time from motion to notification: typically 5–15 seconds.

---

## Setting Up Alerts in Home Assistant

Once Sentinel is sending descriptions to Home Assistant, create an automation to notify you.

### Example Automation (via HA UI)

1. Go to **Settings → Automations → + Create Automation**
2. **Trigger:** Choose `Webhook` or the Sentinel-specific state trigger
3. **Condition:** (optional) Only notify between 8am–10pm
4. **Action:** `Notify → Your Phone`
   - Message: `{{ trigger.json.description }}`

### Example YAML Automation

Add this to your `automations.yaml`:

```yaml
- alias: "Sentinel AI Camera Alert"
  trigger:
    platform: webhook
    webhook_id: sentinel_alert
  action:
    service: notify.mobile_app_your_phone
    data:
      title: "{{ trigger.json.camera | title }} Camera"
      message: "{{ trigger.json.description }}"
```

---

## Use Cases — What Can Sentinel Identify?

| Scenario | What AI Reports |
|---|---|
| Person at front door | "A person in a blue jacket is standing at the door, facing the camera" |
| Package delivery | "A delivery person in a brown uniform left a box on the porch" |
| Vehicle in driveway | "A white sedan has pulled into the driveway — driver is exiting" |
| Animal in yard | "A medium-sized dog is running across the back yard" |
| Suspicious activity | "A person is looking at the car parked in the driveway, hands near the door handle" |
| Nighttime motion | "Motion detected but the image is dark — a person-shaped silhouette is visible" |

The AI describes what it actually sees, not just "motion detected." This dramatically reduces false alarm fatigue.

---

## Common Problems and Fixes

### Node C Ollama Is Unreachable

```bash
# Test the connection from Node E's machine
curl http://192.168.1.6:11434/api/tags
```

If this fails:
- Make sure Node C is powered on
- Make sure Ollama is running on Node C: `docker ps | grep ollama`
- Check that port 11434 isn't blocked by a firewall

### Vision Analysis Times Out

The llava model takes 5–20 seconds to analyze an image. If you're seeing timeouts:

1. Check if Node C is under heavy load: `docker stats`
2. Make sure no other large models are loaded in Ollama: `ollama ps`
3. Try reducing image resolution before sending to Sentinel
4. Increase the timeout setting in Sentinel's config

### Webhook Authentication Fails (401 Error)

The token in Frigate's webhook config doesn't match `SENTINEL_TOKEN` in Sentinel's `.env`.

```bash
# On Node E, check what token is set
cat .env | grep SENTINEL_TOKEN
```

Make sure the token in Frigate's `config.yaml` is exactly the same — no extra spaces, same capitalization.

### Frigate Webhooks Not Arriving

```bash
# Watch Sentinel's logs in real time
node node-e-sentinel.js  # (or check PM2 logs)
pm2 logs sentinel
```

Then trigger a motion event on your camera and watch if anything appears in the logs. If nothing shows, the issue is in Frigate's webhook config — double-check the URL and that Frigate is actually running.

### "llava not found" Error

The vision model isn't downloaded on Node C:

```bash
# Run this on Node C
ollama pull llava

# Verify it downloaded
ollama list | grep llava
```

---

## Security Notes

- Always set a strong `SENTINEL_TOKEN` — don't leave it as a placeholder
- Node E should only be accessible within your home network
- If you ever expose Sentinel to the internet (not recommended), use HTTPS and a reverse proxy like Nginx with SSL

---

## Quick Reference

| Thing | Value |
|---|---|
| Sentinel Port | 3005 |
| Health check | `GET http://[node-e-ip]:3005/health` |
| Analyze endpoint | `POST http://[node-e-ip]:3005/api/analyze` |
| Frigate webhook | `POST http://[node-e-ip]:3005/api/webhook/frigate` |
| Vision backend | Node C Ollama — http://192.168.1.6:11434 |
| Vision model | llava |
| Auth header | `Authorization: Bearer [SENTINEL_TOKEN]` |
| Start command | `node node-e-sentinel.js` |

---

## Maintenance

### Checking Sentinel Logs

```bash
# If running with PM2
pm2 logs sentinel --lines 50

# If running directly
# Redirect output when starting: node node-e-sentinel.js >> sentinel.log 2>&1
tail -f sentinel.log
```

### Updating the Vision Model

If llava releases a new version, update it on Node C:

```bash
# Run on Node C
ollama pull llava:latest
```

Sentinel will automatically use the updated model — no restart needed.

### Adjusting Analysis Sensitivity

If you're getting too many alerts (or too few), adjust the Frigate detection thresholds in Frigate's `config.yaml`:

```yaml
objects:
  track:
    - person
    - car
    - package
  filters:
    person:
      min_score: 0.7   # Only alert if 70%+ confident it's a person
```
