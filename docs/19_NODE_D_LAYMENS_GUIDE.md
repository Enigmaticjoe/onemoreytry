# Node D — Home Assistant: Layman's Guide

> Canonical architecture authority: [`docs/ARCHITECTURE_CANONICAL_2026.md`](ARCHITECTURE_CANONICAL_2026.md).


> **Who this guide is for:** Anyone who wants to automate their home, use voice control, or connect their smart home to the AI lab. You don't need any coding experience — Home Assistant is designed for regular people.

---

## What Is Node D?

Node D is the **smart home brain** of your setup. It runs Home Assistant — the software that connects all your smart devices (lights, thermostats, cameras, door locks) and lets you automate them, control them by voice, and now — ask AI questions about your home.

- IP address: **192.168.1.149**
- Nickname: **Home Assistant Node**
- Main job: Smart home hub + AI-powered voice control + automation engine

---

## What Is Home Assistant? (Plain English)

Imagine a control room for your entire house. Home Assistant:

- **Talks to your smart devices** — Philips Hue lights, Nest thermostat, Ring doorbell, smart plugs, anything
- **Runs automations** — "When I leave home, turn off all lights" or "When motion is detected at 2am, send me a notification"
- **Shows a dashboard** — one page where you can see and control everything in your home
- **Connects to AI** — with the integration we're setting up, you can ask it questions about your home and get intelligent answers

The best part: it runs **locally on your network**. Your smart home data never leaves your house.

---

## The Hardware — Plain English

| Part | What You've Got | Why It Matters |
|---|---|---|
| **CPU** | AMD Ryzen 7 7430U | Low-power mobile processor — runs Home Assistant 24/7 without burning much electricity |
| **RAM** | 32 GB DDR4 | Plenty for HA and all its integrations running simultaneously |

Node D doesn't need a GPU — Home Assistant doesn't do AI processing itself. It offloads AI requests to Node B (LiteLLM), which routes them to whichever AI is best suited.

---

## Setting Up Home Assistant — Step by Step

### Step 1: Start Home Assistant

```bash
cd /path/to/node-d-home-assistant
docker compose up -d
```

Home Assistant takes a minute or two to start for the first time — it's setting itself up. Be patient.

### Step 2: Access the Web Interface

Open your browser and go to:

```
http://192.168.1.149:8123
```

The first time you visit, Home Assistant will walk you through a setup wizard:
1. Create your admin account (username + password)
2. Set your home location (for sunrise/sunset automations)
3. Home Assistant will auto-detect many of your smart devices

### Step 3: Complete the Onboarding Wizard

Follow the on-screen prompts. You can always add more devices later — don't worry about getting everything perfect on the first run.

---

## Connecting Home Assistant to Your AI Lab

This is where it gets exciting — you can give Home Assistant the ability to answer questions using your AI models.

### Step 1: Install the OpenAI Conversation Integration

In Home Assistant:

1. Go to **Settings** (gear icon in the sidebar)
2. Click **Devices & Services**
3. Click the blue **+ Add Integration** button (bottom right)
4. Search for `OpenAI Conversation`
5. Click on it when it appears

### Step 2: Configure the Integration

When prompted, fill in:

| Field | Value |
|---|---|
| **API Key** | `sk-master-key` |
| **Base URL** | `http://192.168.1.222:4000/v1` |
| **Model** | `brawn-fast` (or `brain-heavy` for smarter responses) |

> **Why these values?** The "Base URL" points to LiteLLM on Node B, which routes your request to the right AI. The API key is your lab's master key. You're not using OpenAI's servers — everything stays local.

Click **Submit**.

### Step 3: Set the AI as Your Conversation Agent

1. Go to **Settings → Voice Assistants**
2. Click **Add Assistant** (or edit your existing one)
3. Under **Conversation agent**, select `OpenAI Conversation`
4. Save

Now when you use voice commands or the chat feature in HA, it uses your local AI.

---

## Writing Your Master Prompt (System Prompt)

The "master prompt" tells the AI how to behave inside Home Assistant. It's like giving the AI its job description.

To set it:

1. Go to **Settings → Devices & Services**
2. Click on the `OpenAI Conversation` integration
3. Click **Configure**
4. In the **Prompt** box, write something like:

```
You are Jarvis, an intelligent home assistant. You can control smart home devices,
answer questions about the home, and help with automations. The home is located in
[your city]. Always be concise and helpful. If you can control a device, do it
directly. If you're not sure about something, say so.
```

This prompt is sent with every conversation, giving the AI context about its role.

---

## Creating Voice Automations

Voice automations let you say something and have Home Assistant do it automatically.

### Example: "Hey Jarvis, turn off the lights"

1. Go to **Settings → Automations & Scenes**
2. Click **+ Create Automation**
3. Set the **Trigger** to: `Sentence` → type `turn off the lights`
4. Set the **Action** to: `Call Service → light.turn_off → All Lights`
5. Save the automation

Now saying "Hey Jarvis, turn off the lights" (via a voice assistant device or the HA app) will turn off your lights.

### More Automation Examples

| Voice Command | Action |
|---|---|
| "Good night" | Turn off all lights, lock front door, set thermostat to 68°F |
| "I'm leaving" | Turn off everything, arm security system |
| "Movie time" | Dim lights, turn on TV scene |
| "Wake up" | Gradually brighten lights, start coffee maker |

---

## Asking the AI About Your Home

With the OpenAI Conversation integration active, you can ask questions like:

- "What's the temperature in the living room?"
- "Is the front door locked?"
- "Which lights are on right now?"
- "What's my energy usage today?"
- "Set the thermostat to 72 degrees"

Home Assistant will check your actual device states and give the AI that context, so it can answer accurately.

---

## Shell Commands: Trigger KVM Actions from HA

Node D can send commands to other services in your lab using the `shell_command` integration. This lets Home Assistant trigger actions on other machines.

Add to your `configuration.yaml`:

```yaml
shell_command:
  restart_node_a: "curl -X POST http://192.168.1.9:3099/api/restart"
  check_cameras: "curl http://192.168.1.x:3005/api/status"
```

Then you can trigger these from an automation or the HA UI.

---

## Connecting HA to Frigate for Camera Alerts

Frigate is an AI NVR (camera recording software) that detects motion, people, vehicles, and more. Node E's Sentinel service bridges Frigate and your AI lab.

### To connect Frigate to Home Assistant:

1. Install the **Frigate** integration in HA (same way as OpenAI Conversation — search for "Frigate" in integrations)
2. Enter your Frigate server address when prompted
3. Home Assistant will now receive events from Frigate (person detected, car detected, etc.)

### Creating a Notification Automation

```yaml
automation:
  - alias: "Person at Front Door"
    trigger:
      platform: state
      entity_id: binary_sensor.frigate_front_door_person
      to: "on"
    action:
      service: notify.mobile_app_your_phone
      data:
        message: "Someone is at the front door!"
        data:
          image: /api/frigate/notifications/front_door/thumbnail.jpg
```

---

## Common Problems and Fixes

### HA Won't Start

```bash
# Check if the container is running
docker ps | grep homeassistant

# View startup logs
docker logs homeassistant --tail=50
```

Common causes:
- A bad `configuration.yaml` — HA will print exactly which line has an error
- Port 8123 already in use by another service
- Storage volume permission issues

### AI Integration Not Working

Check these in order:
1. Is LiteLLM on Node B running? → `curl http://192.168.1.222:4000/health`
2. Is the API key correct? → Must be exactly `sk-master-key` (or whatever you set)
3. Is the base URL correct? → Must be `http://192.168.1.222:4000/v1` (with `/v1` at the end)

### "API Key Rejected" or 401 Error

The key in HA doesn't match the key in LiteLLM's config. They must be identical — character for character, no extra spaces.

### HA Loads But Shows No Devices

Your smart devices need to be on the same network as HA, and some may need their apps/bridges set up first. Check:
1. **Settings → Devices & Services** — look for auto-discovered integrations
2. Make sure your smart home hub (Hue bridge, SmartThings, etc.) is powered on and connected

---

## Maintenance

### Updating Home Assistant

Home Assistant releases updates frequently. You'll see a notification in the HA UI when one is available.

To update via Docker:

```bash
docker compose pull
docker compose up -d
```

> **Always read the release notes before updating** — occasionally an update requires a configuration change. The HA community forums are very helpful.

### Adding New Integrations

1. Go to **Settings → Devices & Services → + Add Integration**
2. Search for your device brand or service
3. Follow the on-screen instructions

HA has 3,000+ integrations — if you have a smart home device, there's almost certainly an integration for it.

### Backing Up Your Configuration

Regular backups protect your automations and settings:

1. Go to **Settings → System → Backups**
2. Click **Create Backup**
3. Download it to your computer

Do this before any major update.

---

## Quick Reference

| Thing | Value |
|---|---|
| IP Address | 192.168.1.149 |
| Home Assistant UI | http://192.168.1.149:8123 |
| AI API Base URL | http://192.168.1.222:4000/v1 |
| AI API Key | sk-master-key |
| Recommended model | `brawn-fast` (fast) or `brain-heavy` (smart) |
| Integration name | OpenAI Conversation |
