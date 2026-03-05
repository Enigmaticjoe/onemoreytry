# Home Assistant: The Complete Layman's Guide

> Canonical architecture authority: [`docs/ARCHITECTURE_CANONICAL_2026.md`](ARCHITECTURE_CANONICAL_2026.md).


**Who this guide is for:** Anyone setting up Home Assistant for the first time, or anyone who wants to connect Home Assistant to their AI home-lab stack (LiteLLM, OpenClaw, Frigate, and more).

---

## Table of Contents

1. [What Is Home Assistant?](#part-1--what-is-home-assistant)
2. [First-Time Setup](#part-2--first-time-setup)
3. [Connecting Home Assistant to Your AI (LiteLLM)](#part-3--connecting-home-assistant-to-your-ai-litellm)
4. [Voice Control Setup](#part-4--voice-control-setup)
5. [Automations Made Easy](#part-5--automations-made-easy)
6. [Integrations Worth Adding](#part-6--integrations-worth-adding)
7. [The AI Assistant in Practice](#part-7--the-ai-assistant-in-practice)
8. [Connecting Everything Together](#part-8--connecting-everything-together)
9. [Troubleshooting](#part-9--troubleshooting)

---

## Part 1 — What Is Home Assistant?

### The Short Version

**Home Assistant (HA)** is your home's brain. It's free, open-source software that connects to — and controls — virtually every smart device in your home: lights, locks, thermostats, cameras, doorbells, TVs, speakers, energy monitors, and thousands more.

You install it yourself. You run it yourself. And because it runs **locally** on your own hardware (Node D at 192.168.1.149), your data never leaves your house.

### Why Home Assistant Is Better Than Alexa or Google Home

| Feature | Home Assistant | Alexa / Google |
|---------|---------------|----------------|
| Cost | Free | Free (but sells your data) |
| Privacy | Fully local, no cloud required | Cloud-dependent |
| Device support | 3,000+ integrations | Limited to certified products |
| Customization | Unlimited | Limited |
| Works when internet is down | Yes | Partially / No |
| Runs your own AI | Yes (in this setup) | No |
| Self-hosted | Yes | No |
| Open source | Yes | No |

### Where Home Assistant Lives in Your Setup

- **Node D:** 192.168.1.149 — the machine running Home Assistant
- **Port:** 8123 — the web interface
- **Access URL:** `http://192.168.1.149:8123`
- **Mobile:** Download the HA Companion App and it finds HA automatically

### HA Versions — Which One Are You Using?

Home Assistant comes in several flavors. It matters because features differ:

| Version | Description | Your Setup |
|---------|-------------|------------|
| **HA OS** | Installs directly on hardware, manages its own OS | ❌ |
| **HA Supervised** | Runs on your Linux, HA manages add-ons | ❌ |
| **HA Container** | Docker image, you manage everything | ✅ This one |
| **HA Core** | Bare Python install, no add-ons | ❌ |

You're running **Home Assistant Container** via Docker. This means:
- You manage Docker and the host OS yourself
- HA add-ons (like the Mosquitto MQTT broker add-on) are **not** available — you install those as separate Docker containers
- Everything else (automations, integrations, dashboards) works the same

---

## Part 2 — First-Time Setup

### Starting Home Assistant

From the `node-d-home-assistant/` directory:

```bash
cd /home/runner/work/onemoreytry/onemoreytry/node-d-home-assistant
docker compose up -d
```

Home Assistant takes **3-5 minutes** to start on first boot — it's building its database and loading integrations. Don't panic if the web page doesn't load immediately.

Check if it's running:

```bash
docker ps | grep homeassistant
docker logs homeassistant --tail 30
```

Wait for the log line that says `Home Assistant initialized in X.Xs` — then it's ready.

### Accessing the Web Interface

Open your browser and go to:

```
http://192.168.1.149:8123
```

On first launch, you'll see the HA onboarding wizard.

### Creating Your Admin Account

The wizard asks you to:

1. **Name** your home assistant (e.g., "My Home")
2. **Create an account** (username and strong password) — this is your admin account, keep it secure
3. **Set your location** — this is used for sunrise/sunset automations, weather, etc.
4. **Set your unit system** (Fahrenheit/Celsius, miles/km)

### Discovering Devices

After setup, HA immediately scans your network and finds devices it recognizes. This typically includes:
- Smart TVs (Roku, Apple TV, Chromecast, Samsung)
- Philips Hue bridges
- Sonos speakers
- Shelly smart switches
- Nest/Ecobee thermostats
- And hundreds more

A notification in HA will say *"We found these devices on your network — would you like to add them?"* Click through and add what you recognize.

### The Home Assistant Dashboard — Key Areas

Once you're in HA, here's what you're looking at:

**Left sidebar navigation:**
- **🏠 Overview** — your main dashboard (customizable with cards)
- **🗺️ Map** — shows locations of mobile devices
- **📋 Logbook** — history of what happened and when
- **📊 Energy** — energy monitoring (if you have compatible devices)
- **⚙️ Settings** — where all configuration lives

**Inside Settings:**
- **Devices & Services** — manage all your integrations
- **Automations & Scenes** — create and edit automations
- **Scripts** — reusable action sequences
- **Areas & Zones** — organize devices by room/area
- **Voice Assistants** — configure voice control
- **People** — track who's home

### The States: How HA Thinks About Your Home

Every device, sensor, and virtual item in HA has a **state**. A light has states `on` / `off`. A thermometer has a state like `72.4`. A motion sensor has states `detected` / `clear`.

You can view all states at:

```
http://192.168.1.149:8123/developer-tools/state
```

This is the raw list of everything HA knows. Very useful for troubleshooting.

---

## Part 3 — Connecting Home Assistant to Your AI (LiteLLM)

### What the OpenAI Conversation Integration Does

Home Assistant has a built-in integration called **OpenAI Conversation** (and an extended version available via HACS). This integration lets you:

- Chat with an AI directly in HA's Assist panel
- Use an AI model to understand voice commands and translate them into HA actions
- Let AI draft responses to questions about your home ("What's the temperature in every room?")

Instead of sending data to OpenAI's servers, you'll point it at your own **LiteLLM Gateway** on Node B — so your questions stay on your local network.

### Step-by-Step: Adding OpenAI Conversation

1. Open HA at `http://192.168.1.149:8123`
2. Go to **Settings → Devices & Services**
3. Click **Add Integration** (bottom right + button)
4. Search for **OpenAI Conversation**
5. Click it and fill in:

```
API Key:   sk-master-key
Base URL:  http://192.168.1.222:4000/v1
```

6. Click **Submit**
7. You'll see a model selection — choose your preferred default:
   - `brawn-fast` for fast everyday responses
   - `brain-heavy` for complex reasoning tasks

> **Why `sk-master-key`?** LiteLLM requires an API key for authentication, and `sk-master-key` is the master key configured when you set up LiteLLM on Node B. It grants access to all models on LiteLLM.

### Choosing Your Models

LiteLLM exposes models that you configured during Node B setup:

| Model Name | Description | Best For |
|-----------|-------------|----------|
| `brawn-fast` | RTX 4070 on Node B | Quick questions, voice commands |
| `brain-heavy` | RX 7900 XT on Node A | Complex reasoning, analysis |
| `ollama/llama3` | Direct Ollama on Node C | Fallback if Node B is down |

For Home Assistant conversations, **brawn-fast** is recommended — it responds in 1-3 seconds, which feels natural for voice interaction. Use **brain-heavy** for complex automations or deep analysis.

### Setting the System Prompt

The **system prompt** tells the AI who it is and how to behave inside Home Assistant. A good system prompt makes your AI assistant much more useful.

In the OpenAI Conversation settings, find the **System Prompt** field and enter:

```
You are the AI assistant for my smart home. 
The current time is {{ now().strftime('%I:%M %p on %A, %B %d, %Y') }}.

You have access to and can control all smart home devices in my home.
When asked to control a device, determine the correct entity and execute the action.

My home has:
- Living room: lights, TV, thermostat
- Kitchen: lights, smart plugs
- Front door: camera, doorbell, lock
- Backyard: cameras, motion sensors

Be concise. For simple control tasks, just confirm what you did.
For questions, answer briefly and accurately.
Never make up device states — if you don't know, say so.
```

The `{{ now() }}` part is a Jinja2 template — Home Assistant fills in the current time before sending the prompt to the AI.

### Testing the AI Connection

1. Go to **Settings → Voice Assistants**
2. Click on your voice assistant (or create one)
3. Click the **Try the pipeline** button (looks like a chat bubble)
4. Type: `What's the status of my living room lights?`

If the AI responds correctly (e.g., "Your living room lights are currently off"), the connection is working.

If you get an error, check:
- LiteLLM is running: `curl http://192.168.1.222:4000/v1/models -H "Authorization: Bearer sk-master-key"`
- The URL in the integration is exactly `http://192.168.1.222:4000/v1`
- The API key is exactly `sk-master-key`

---

## Part 4 — Voice Control Setup

### The Pieces You Need for Voice Control

Home Assistant's voice system (**Assist**) has three components:

1. **Speech-to-text (STT):** Converts your voice to text (what did you say?)
2. **Intent recognition:** Understands what you meant and matches it to a HA action
3. **Text-to-speech (TTS):** Speaks the response back to you

In this setup, the AI model handles intent recognition — you're essentially speaking to your LiteLLM-backed AI, which understands your commands and executes them.

### Connecting a Microphone

**Option A: Use your phone (easiest)**

The Home Assistant Companion App on your phone can use the phone's microphone to talk to Assist:
1. Install the HA app (iOS or Android)
2. Open the app and go to the Assist page (speech bubble icon)
3. Press the microphone button and speak

**Option B: USB Microphone plugged into Node D**

```yaml
# In your docker-compose.yml for Home Assistant, expose the audio device:
devices:
  - /dev/snd:/dev/snd
```

Then use the Wyoming protocol to stream audio.

**Option C: Wyoming Satellite (Raspberry Pi or spare computer)**

A Wyoming satellite is a small program you install on a Raspberry Pi or any spare computer. It listens for a wake word ("Hey Home Assistant" or custom), then streams your voice to HA for processing.

Install Wyoming satellite:

```bash
# On the Raspberry Pi / satellite device
pip install wyoming-satellite

# Start it
python -m wyoming_satellite \
  --name "Living Room Satellite" \
  --uri tcp://0.0.0.0:10700 \
  --mic-command "arecord -r 16000 -c 1 -f S16_LE -t raw" \
  --snd-command "aplay -r 22050 -c 1 -f S16_LE -t raw"
```

Then in HA → **Settings → Devices & Services → Add Integration → Wyoming Protocol**, enter the satellite's IP and port 10700.

### Creating a Voice Assistant Profile

1. Go to **Settings → Voice Assistants**
2. Click **Add Assistant**
3. Fill in:
   - **Name:** "Jarvis" (or whatever you prefer)
   - **Language:** English
   - **Conversation agent:** Your OpenAI Conversation integration
   - **Speech-to-text:** Home Assistant (built-in) or Whisper
   - **Text-to-speech:** Google TTS, Piper, or your preferred engine
4. Click **Create**

### Wake Word Detection (Optional)

Wake word detection means HA is always listening (on the satellite device) for a trigger phrase, so you don't have to open an app.

Built-in wake words include:
- "Hey Jarvis"
- "OK Nabu"
- "Hey Mycroft"

To enable:
1. Install the Wyoming openWakeWord add-on (or run it as a Docker container for Container installs)
2. In your Wyoming satellite config, add the wake word processor
3. Configure your Voice Assistant to use it

**For Container HA**, run openWakeWord as a separate container:

```yaml
# In a separate docker-compose.yml on Node D
services:
  openwakeword:
    image: rhasspy/wyoming-openwakeword
    ports:
      - "10400:10400"
    command: --preload-model 'hey_jarvis'
```

Then add it as a Wyoming integration in HA.

### Testing Voice

With a voice assistant profile set up:

1. Go to **Settings → Voice Assistants → [Your Assistant]**
2. Click **Try the pipeline**
3. Click the microphone icon
4. Say: *"What's the temperature in the living room?"*

You should hear (and see) a response. If you have a temperature sensor set up, you'll get the real value. If not, the AI will explain that there's no temperature sensor available.

---

## Part 5 — Automations Made Easy

### What Are Automations?

Automations are **"if this, then that"** rules. Three parts:
- **Trigger:** What starts the automation (a sensor changes, a time is reached, a button is pressed)
- **Condition:** Optional check before running (only run if it's daytime, only if someone is home)
- **Action:** What to do (turn on a light, send a notification, call a service)

### Creating an Automation via the UI

1. Go to **Settings → Automations & Scenes → Automations**
2. Click **Create Automation** → **Create new automation**
3. Fill in the three sections:

**Trigger section:**
- Click **Add Trigger**
- Choose the type: "State", "Time", "MQTT", "Device", etc.

**Condition section (optional):**
- Click **Add Condition**
- Add checks that must be true for the automation to run

**Action section:**
- Click **Add Action**
- Choose what to do: "Call service", "Wait", "Send notification", etc.

4. Give it a name and click **Save**

### Example 1: Motion Detected → AI Analysis → Notification

```yaml
alias: "Front Door Motion - AI Snapshot Analysis"
description: "When Frigate detects a person, analyze the snapshot with AI and notify."
trigger:
  - platform: state
    entity_id: binary_sensor.frontdoor_person
    to: "on"
condition:
  - condition: time
    after: "07:00:00"
    before: "23:00:00"
action:
  - service: rest_command.ask_openclaw
    data:
      message: >
        A person was detected at the front door at {{ now().strftime('%I:%M %p') }}.
        Fetch the latest Frigate snapshot for the frontdoor camera and describe 
        who or what you see. Keep it to 1-2 sentences.
  - wait_template: "{{ states('input_text.openclaw_last_response') != '' }}"
    timeout: "00:00:15"
  - service: notify.mobile_app_your_phone
    data:
      title: "👤 Front Door"
      message: "{{ states('input_text.openclaw_last_response') }}"
mode: single
```

### Example 2: Good Morning Routine

```yaml
alias: "Good Morning Routine"
description: "Weekday morning wake-up: lights, AI briefing, weather."
trigger:
  - platform: time
    at: "07:30:00"
condition:
  - condition: time
    weekday:
      - mon
      - tue
      - wed
      - thu
      - fri
  - condition: state
    entity_id: binary_sensor.someone_is_home
    state: "on"
action:
  # Gradually turn on lights
  - service: light.turn_on
    target:
      area_id: bedroom
    data:
      brightness_pct: 30
      transition: 60

  # Wait a minute while lights come up
  - delay: "00:01:00"

  # Ask OpenClaw for a morning briefing
  - service: rest_command.ask_openclaw
    data:
      message: >
        Good morning briefing. Today is {{ now().strftime('%A, %B %d') }}.
        It is {{ states('sensor.outdoor_temperature') | default('unknown') }}°F outside.
        Any scheduled events today from the calendar?
        Keep it under 3 sentences, be upbeat and cheerful.

  # Wait for response
  - delay: "00:00:05"

  # Speak the briefing on living room speaker
  - service: tts.speak
    target:
      entity_id: media_player.living_room_speaker
    data:
      message: "{{ states('input_text.openclaw_last_response') }}"
      language: en-US

  # Turn lights to full brightness
  - service: light.turn_on
    target:
      area_id: bedroom
    data:
      brightness_pct: 100
      transition: 30
mode: single
```

### Example 3: Doorbell Rings → AI Description → Notification

```yaml
alias: "Doorbell - Snapshot and Notify"
trigger:
  - platform: state
    entity_id: binary_sensor.front_doorbell
    to: "on"
action:
  - service: camera.snapshot
    target:
      entity_id: camera.frontdoor
    data:
      filename: /config/tmp/doorbell_snapshot.jpg

  - service: rest_command.analyze_camera_snapshot
    data:
      snapshot_url: "http://192.168.1.222:5000/api/latest/frontdoor/snapshot.jpg"
      camera: "frontdoor"
      label: "doorbell"

  - delay: "00:00:08"

  - service: notify.mobile_app_your_phone
    data:
      title: "🔔 Doorbell"
      message: "Someone rang the doorbell. {{ states('input_text.ai_camera_description') }}"
      data:
        image: /config/tmp/doorbell_snapshot.jpg
        actions:
          - action: "UNLOCK_DOOR"
            title: "Unlock Door"
          - action: "IGNORE"
            title: "Ignore"
mode: single
```

### Example 4: Lights Off at 10 PM

```yaml
alias: "Bedtime Lights Off"
trigger:
  - platform: time
    at: "22:00:00"
action:
  - service: light.turn_off
    target:
      area_id:
        - living_room
        - kitchen
        - hallway
  - service: notify.mobile_app_your_phone
    data:
      message: "Lights turned off. Good night! 🌙"
mode: single
```

### Using YAML for Advanced Automations

The UI is great for simple automations, but YAML gives you full control. To edit an automation's YAML:

1. Open the automation
2. Click the three-dot menu (⋮) at the top right
3. Click **Edit in YAML**

You'll see the raw YAML. You can paste any of the examples in this guide directly here.

### Automation Blueprints

Blueprints are pre-made automations you can import and configure without writing YAML. Find them at:

```
https://community.home-assistant.io/c/blueprints-exchange/53
```

Popular blueprints:
- **Motion-activated light** — turn on lights when motion detected, off after X minutes
- **Notify on low battery** — get notified when any device's battery drops below 20%
- **Away mode** — automatically adjust thermostat and lights when everyone leaves
- **Presence-based lighting** — different scenes depending on who's home

To import a blueprint:
1. Find a blueprint on the Community forum
2. Copy the URL
3. In HA: **Settings → Automations → Blueprints → Import Blueprint**
4. Paste the URL and click Preview Import

---

## Part 6 — Integrations Worth Adding

### HACS (Home Assistant Community Store)

HACS is an unofficial add-on store that adds thousands of community-built integrations, frontend cards, and themes. It's essential for a full-featured HA setup.

**Installing HACS (for Container HA):**

```bash
# SSH into Node D or run on the machine hosting HA
docker exec -it homeassistant bash

# Run the HACS installer
wget -O - https://get.hacs.xyz | bash -
```

Or manually:
```bash
cd /config  # Inside the HA container, /config is your HA config directory
mkdir -p custom_components
cd custom_components
wget https://github.com/hacs/integration/releases/latest/download/hacs.zip
unzip hacs.zip -d hacs
```

Restart HA, then go to **Settings → Devices & Services → Add Integration → HACS**.

### Frigate Integration (via HACS)

After installing HACS:
1. **HACS → Integrations → + Explore & Download**
2. Search "Frigate"
3. Install "Frigate (NVR Integration)"
4. Restart HA
5. **Settings → Devices & Services → Add Integration → Frigate**
6. Enter: `http://192.168.1.222:5000`

This adds all Frigate cameras and sensors to HA automatically.

### MQTT Broker: Mosquitto

MQTT is the messaging backbone for many HA integrations (Frigate events, Blue Iris alerts, Zigbee devices, custom sensors). Since you're running Container HA, install Mosquitto as a separate Docker container:

Create `/opt/mosquitto/docker-compose.yml`:

```yaml
version: "3.8"
services:
  mosquitto:
    image: eclipse-mosquitto:latest
    container_name: mosquitto
    restart: unless-stopped
    ports:
      - "1883:1883"    # MQTT
      - "9001:9001"    # WebSockets (optional, for web clients)
    volumes:
      - /opt/mosquitto/config:/mosquitto/config
      - /opt/mosquitto/data:/mosquitto/data
      - /opt/mosquitto/log:/mosquitto/log
```

Create `/opt/mosquitto/config/mosquitto.conf`:

```
listener 1883
allow_anonymous true

persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
```

Start it:

```bash
cd /opt/mosquitto
docker compose up -d
```

Then add the MQTT integration in HA:
**Settings → Devices & Services → Add Integration → MQTT**
- Broker: `192.168.1.149`
- Port: `1883`
- No username/password needed (unless you configured auth)

### Mobile App: HA Companion

The HA Companion App turns your phone into a smart home remote and sensor:

**iOS:** Search "Home Assistant" in the App Store
**Android:** Search "Home Assistant" in Google Play

Features:
- Full HA dashboard on your phone
- Push notifications from automations
- Send your phone's location to HA (know who's home)
- Expose phone sensors to HA: battery level, WiFi network, steps, charging state
- Speak to HA via the app's microphone
- View camera feeds

**First time setup:**
1. Open the app
2. Tap **Connect** — it auto-discovers HA on your local network
3. Enter your HA credentials
4. Grant all permissions (location, notifications, microphone) for full features

### Tailscale: Remote Access

Tailscale creates a secure private network between your devices, so you can reach HA from anywhere in the world without exposing ports to the internet.

Install Tailscale on Node D:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Follow the link it gives you to authenticate. Now you can access HA at your Tailscale IP from anywhere.

In the HA Companion App, add a second "External URL" using the Tailscale IP or hostname. The app automatically switches between local URL (when home) and Tailscale URL (when away).

### Alexa / Google Home Bridge

You can still use Alexa or Google Home voice assistants as just the voice input, while HA handles everything behind the scenes.

**Nabu Casa** ($6.50/month) is the easiest way — it's the official cloud service from HA that bridges Alexa/Google. Alternatively, you can self-host this bridge for free.

---

## Part 7 — The AI Assistant in Practice

### What the AI Can and Can't Do in HA

**What it CAN do:**
- Answer questions about your home's state ("Are the lights on?", "What's the temperature?")
- Control devices ("Turn off the kitchen lights", "Set the thermostat to 68 degrees")
- Create simple automations when you ask ("Create an automation to turn off lights at midnight")
- Tell you about recent events ("When did the front door sensor last trigger?")
- Understand natural language and map it to HA actions

**What it CAN'T do (by default):**
- See camera feeds (unless you route them through LLaVA separately)
- Remember things between conversations (each conversation starts fresh)
- Take actions that involve physical access (unlocking doors requires a separate lock integration)
- Predict the future or access the internet (unless you add tools for that)

### How Intent Recognition Works

When you say *"Turn on the living room lights"*:

1. HA sends your text to the AI with a system prompt that includes all your devices
2. The AI responds with a structured action: `{ "service": "light.turn_on", "entity_id": "light.living_room" }`
3. HA executes that service call
4. HA asks the AI to generate a spoken confirmation
5. You hear: "I've turned on the living room lights."

If the AI doesn't know which entity to use, it'll ask for clarification.

### Example Conversations

Here are real examples of what you can say and what happens:

---
**You:** "What's the status of my home?"

**AI:** "Here's a quick summary: The living room lights are off. The front door is locked. The thermostat is set to 70°F and currently reading 71.2°F. There are no active motion sensors."

---
**You:** "Turn off all the lights"

**AI:** "Turning off all lights now." *(HA turns off every light entity)*

---
**You:** "I'm cold"

**AI:** "I'll increase the thermostat by 2 degrees. Setting it to 72°F now." *(HA adjusts the thermostat)*

---
**You:** "Is anyone moving around the house?"

**AI:** "Your hallway motion sensor is currently active. All other motion sensors are clear."

---
**You:** "Set a bedtime scene"

**AI:** "Setting bedtime scene: turning off main lights, setting bedroom light to 20% warm white, locking the front door." *(HA runs multiple service calls)*

---

### Setting Up Assist Pipeline

The Assist pipeline is what connects voice input → AI processing → action → voice response. To create a pipeline:

1. **Settings → Voice Assistants → Add Assistant**
2. Configure:
   - **Conversation agent:** OpenAI Conversation (your LiteLLM connection)
   - **STT (Speech to Text):** Faster Whisper (local, best quality) or Cloud STT
   - **TTS (Text to Speech):** Piper (local, natural voices) or Google TTS

**For local Whisper STT** (no internet required):

Run Wyoming Whisper as a Docker container on Node D:

```yaml
services:
  whisper:
    image: rhasspy/wyoming-whisper
    ports:
      - "10300:10300"
    volumes:
      - /opt/whisper/data:/data
    command: --model small-int8 --language en
```

Then add it in HA as a Wyoming integration.

**For local Piper TTS** (natural-sounding voices, no internet):

```yaml
services:
  piper:
    image: rhasspy/wyoming-piper
    ports:
      - "10200:10200"
    volumes:
      - /opt/piper/data:/data
    command: --voice en_US-lessac-medium
```

### Customizing AI Responses with a Better System Prompt

The system prompt is the single biggest lever for improving your AI assistant's quality. Here's an advanced example:

```
You are ARIA, the AI assistant for my smart home at happystrugglebus.us.

Current context:
- Date and time: {{ now().strftime('%A, %B %d, %Y at %I:%M %p') }}
- People home: {% if states('group.family') == 'home' %}Yes{% else %}No{% endif %}
- Outdoor temperature: {{ states('sensor.outdoor_temperature') }}°F

Room inventory:
- Living Room: main lights, ceiling fan, TV, soundbar, air purifier
- Kitchen: counter lights, under-cabinet lights, coffee maker plug
- Master Bedroom: bedside lamps, ceiling fan, blackout blinds
- Front Door: Ring doorbell camera, August smart lock, motion sensor
- Backyard: flood lights, security camera, motion sensor

Your personality:
- Friendly but efficient — don't over-explain
- Use metric for measurements unless asked otherwise
- For safety devices (locks, alarms), always confirm before acting

Rules:
- Never lock/unlock doors without asking "Are you sure?"
- Never turn off security cameras
- If unsure which device the user means, ask for clarification
```

### Extended OpenAI Conversation (HACS)

The standard OpenAI Conversation integration is good but limited. **Extended OpenAI Conversation** (available via HACS) adds:

- Custom function definitions (give AI direct control over any HA service)
- More control over context and memory
- Better error handling
- Support for vision (if using LLaVA)

To install via HACS:
1. HACS → Integrations → Search "Extended OpenAI Conversation"
2. Install and restart
3. Set it up the same way as the regular integration
4. Configure functions in the integration settings

---

## Part 8 — Connecting Everything Together

### HA Automation That Triggers OpenClaw

OpenClaw's webhook endpoint lets HA hand off complex tasks to AI:

First, add to `configuration.yaml`:

```yaml
rest_command:
  ask_openclaw:
    url: "http://192.168.1.6:18789/hooks/agent"
    method: POST
    headers:
      Authorization: "Bearer YOUR_OPENCLAW_GATEWAY_TOKEN"
      Content-Type: "application/json"
    payload: '{"prompt": "{{ message }}", "model": "{{ model | default('"'"'litellm/brawn-fast'"'"') }}"}'
```

Use it in automations:

```yaml
action:
  - service: rest_command.ask_openclaw
    data:
      message: "The garage door has been open for 30 minutes. Should I close it?"
      model: "litellm/brawn-fast"
```

### HA Automation That Responds to Frigate Camera Events

```yaml
automation:
  - alias: "Frigate Person Alert with AI"
    trigger:
      - platform: mqtt
        topic: "frigate/events"
    condition:
      - condition: template
        value_template: >
          {{ trigger.payload_json.type == 'new' and 
             trigger.payload_json.after.label == 'person' }}
    action:
      - service: rest_command.ask_openclaw
        data:
          message: >
            Frigate detected a person at the {{ trigger.payload_json.after.camera }} camera 
            at {{ now().strftime('%I:%M %p') }}. 
            The snapshot is at: http://192.168.1.222:5000/api/events/{{ trigger.payload_json.after.id }}/snapshot.jpg
            Analyze the image and describe who you see in 1 sentence.
          model: "ollama/llava:latest"
```

### HA Script That Calls KVM Operator

For direct VM control from HA (without going through OpenClaw):

```yaml
script:
  restart_blueiris:
    alias: "Restart Blue Iris"
    description: "Asks KVM Operator to restart Blue Iris on Windows VM"
    sequence:
      - service: rest_command.kvm_restart_blueiris
    mode: single

rest_command:
  kvm_restart_blueiris:
    url: "http://192.168.1.9:5000/vm/action"
    method: POST
    headers:
      X-API-Key: "YOUR_KVM_OPERATOR_TOKEN"
      Content-Type: "application/json"
    payload: >
      {
        "vm_id": "windows-blueiris",
        "action": "run_command",
        "command": "taskkill /f /im BlueIris.exe && timeout 3 && start C:\\Program Files\\Blue Iris 5\\BlueIris.exe",
        "require_approval": true
      }
```

### HA Dashboard Cards for Everything

Here's a sample Lovelace dashboard YAML that ties the whole setup together:

```yaml
views:
  - title: "AI Home Lab"
    cards:
      # Camera feeds
      - type: horizontal-stack
        cards:
          - type: picture-entity
            entity: camera.frontdoor
            name: Front Door
            show_state: true
          - type: picture-entity
            entity: camera.backyard
            name: Backyard
            show_state: true

      # Node status
      - type: entities
        title: "Node Status"
        entities:
          - entity: binary_sensor.node_a_online
            name: "Node A (Brain) — 192.168.1.9"
          - entity: binary_sensor.node_b_online
            name: "Node B (Brawn) — 192.168.1.222"
          - entity: binary_sensor.node_c_online
            name: "Node C (Command) — 192.168.1.6"

      # AI quick actions
      - type: button
        name: "Morning Briefing"
        icon: mdi:coffee-to-go
        tap_action:
          action: call-service
          service: automation.trigger
          service_data:
            entity_id: automation.good_morning_routine

      - type: button
        name: "Goodnight"
        icon: mdi:moon-waning-crescent
        tap_action:
          action: call-service
          service: automation.trigger
          service_data:
            entity_id: automation.bedtime_lights_off

      # Frigate recent events
      - type: custom:frigate-card
        cameras:
          - camera_entity: camera.frontdoor
            frigate:
              url: http://192.168.1.222:5000
              camera_name: frontdoor
```

### The "Good Morning" Super-Automation

Here's the full good morning automation that ties weather, calendar, AI, lights, and music all together:

```yaml
automation:
  - alias: "Super Good Morning"
    trigger:
      - platform: time
        at: input_datetime.wake_up_time  # Set this in HA Helpers
    condition:
      - condition: state
        entity_id: input_boolean.weekend_mode
        state: "off"
    action:
      # 1. Gradually brighten bedroom lights
      - service: light.turn_on
        target:
          area_id: master_bedroom
        data:
          brightness_pct: 20
          color_temp_kelvin: 3000
          transition: 120  # 2-minute slow sunrise

      # 2. Start playing calm music
      - service: media_player.play_media
        target:
          entity_id: media_player.bedroom_speaker
        data:
          media_content_id: "spotify:playlist:morning_chill"
          media_content_type: music

      # 3. Get AI briefing from OpenClaw
      - service: rest_command.ask_openclaw
        data:
          message: >
            Good morning! Today is {{ now().strftime('%A, %B %d, %Y') }}.
            Please give me a friendly morning briefing that includes:
            1. The weather (it's {{ states('sensor.outdoor_temperature') }}°F outside)
            2. One positive thought for the day
            3. A reminder to check my calendar
            Keep it cheerful and under 4 sentences total.
          model: "litellm/brawn-fast"

      # 4. Wait for lights and briefing
      - delay: "00:02:30"

      # 5. Speak the briefing
      - service: tts.speak
        target:
          entity_id: media_player.bedroom_speaker
        data:
          message: "{{ states('input_text.openclaw_last_response') }}"

      # 6. Bring lights to full brightness
      - service: light.turn_on
        target:
          area_id: master_bedroom
        data:
          brightness_pct: 100
          color_temp_kelvin: 5000
          transition: 60

      # 7. Turn on kitchen lights too
      - service: light.turn_on
        target:
          area_id: kitchen
        data:
          brightness_pct: 80

mode: single
```

---

## Part 9 — Troubleshooting

### Problem: HA Won't Start

**Symptom:** `docker compose up -d` runs but HA is unreachable at port 8123.

**Check 1: Container running?**

```bash
docker ps -a | grep homeassistant
```

Look at the STATUS column. If it says `Exited (1)`, HA crashed on startup.

**Check 2: View the startup logs**

```bash
docker logs homeassistant --tail 100
```

Look for error messages near the bottom. Common ones:

- `ERROR (MainThread) [homeassistant.config] Error loading configuration.yaml` — your config file has a YAML syntax error
- `Address already in use` — something else is using port 8123
- `OperationalError: database is locked` — the HA database got corrupted

**Check 3: Port conflict**

```bash
sudo lsof -i :8123
```

If something else is on 8123, change the port mapping in your docker-compose.yml:

```yaml
ports:
  - "8124:8123"  # Use port 8124 on the host instead
```

**Check 4: Configuration.yaml syntax error**

Validate your HA configuration:

```bash
docker exec -it homeassistant python -m homeassistant --script check_config --config /config
```

**Check 5: Database corruption**

If HA crashes with `database is locked` or `disk I/O error`:

```bash
# Stop HA
docker stop homeassistant

# Rename the broken database
mv /opt/homeassistant/config/home-assistant_v2.db \
   /opt/homeassistant/config/home-assistant_v2.db.broken

# Start HA — it will create a fresh database
docker start homeassistant
```

You'll lose history data, but HA will work again. The database rebuilds itself over time.

### Problem: AI Integration Not Working

**Symptom:** You try to chat with the AI in HA Assist and get "Error communicating with LiteLLM" or similar.

**Check 1: Is LiteLLM running?**

```bash
curl http://192.168.1.222:4000/v1/models \
  -H "Authorization: Bearer sk-master-key"
```

If this fails, LiteLLM on Node B is down. SSH into Node B and restart it:

```bash
ssh user@192.168.1.222
cd /opt/litellm  # or wherever your litellm docker-compose.yml lives
docker compose up -d
```

**Check 2: Wrong URL or key in HA**

Go to **Settings → Devices & Services → OpenAI Conversation → Configure**

Verify:
- URL is exactly: `http://192.168.1.222:4000/v1` (no trailing slash, no missing `/v1`)
- API key is exactly: `sk-master-key`

**Check 3: Model doesn't exist**

The model name you selected in HA must match a model that LiteLLM knows about.

Check available models:

```bash
curl http://192.168.1.222:4000/v1/models \
  -H "Authorization: Bearer sk-master-key" | python3 -m json.tool | grep '"id"'
```

Use one of the IDs from this list in HA's model setting.

**Check 4: Firewall between Node D and Node B**

```bash
# From Node D
nc -zv 192.168.1.222 4000
```

If this fails, port 4000 on Node B is blocked.

### Problem: Voice Not Working

**Symptom:** You press the microphone button in HA Assist, speak, but nothing happens (or you see "Speech to text error").

**Check 1: Is the STT provider running?**

If you're using Wyoming Whisper:

```bash
curl http://192.168.1.149:10300/  # or whatever port your Whisper is on
```

If connection refused, your Whisper container isn't running:

```bash
docker ps | grep whisper
docker logs wyoming-whisper --tail 20
```

**Check 2: Microphone permissions**

In the HA Companion App, make sure microphone permissions are granted in your phone's Settings → Privacy → Microphone → Home Assistant.

**Check 3: Wrong STT in Voice Assistant profile**

**Settings → Voice Assistants → [Your Assistant]**

Make sure the Speech-to-text provider is correctly configured and points to your running Whisper instance.

**Check 4: Satellite not connecting**

If you're using a Wyoming satellite:

```bash
# On the satellite device
journalctl -u wyoming-satellite --tail 20
```

Look for connection errors to your HA IP.

### Problem: Automations Not Firing

**Symptom:** You set up an automation but it never runs, even when the trigger condition is met.

**Check 1: Is the automation enabled?**

**Settings → Automations** — make sure the toggle next to your automation is ON (blue/enabled).

**Check 2: Check the automation trace**

Click on your automation → Click **Traces** (top right) → Click the most recent trace

This shows you exactly what happened: did the trigger fire? Did the condition fail? Did the action error?

This is the most useful debugging tool in HA.

**Check 3: Entity unavailable**

If your trigger entity shows as `unavailable`, the trigger can't fire. Check that the device/integration providing that entity is working.

```bash
# In HA Developer Tools → States, search for your entity
# If it shows "unavailable", the integration feeding it has a problem
```

**Check 4: Condition failing silently**

Add a temporary notification to check if the trigger is firing but the condition is blocking:

```yaml
action:
  - service: notify.mobile_app_your_phone
    data:
      message: "Automation fired at {{ now() }}"
  # ... rest of your actions
```

If you get this notification, your trigger works. If not, the trigger never fires.

**Check 5: Trace the automation manually**

Click your automation → **Run** (▶) button — this manually triggers it ignoring all trigger conditions. If it works when manually triggered but not automatically, your trigger is the issue.

### Problem: Integration Disappeared

**Symptom:** An integration that was working yesterday is now gone from Settings → Devices & Services.

**Check 1: HA version update**

After a HA update, some integrations (especially HACS custom ones) may become incompatible. Check HA's change log:

```
http://192.168.1.149:8123/config/info
```

**Check 2: HACS integration needs update**

HACS → Updates — check if the missing integration has an available update. Update it and restart HA.

**Check 3: Config entry error**

The integration might still be there but in an error state. Check **Settings → System → Repairs** for any error entries.

**Check 4: Manual refresh**

Sometimes integrations just need a reload:

**Settings → Devices & Services → [Integration] → ⋮ menu → Reload**

If that doesn't work, try:
**Settings → Devices & Services → [Integration] → ⋮ menu → Delete** then re-add it.

---

## Quick Reference: Key URLs and Credentials

| Service | URL | Credentials |
|---------|-----|-------------|
| Home Assistant | http://192.168.1.149:8123 | Your admin account |
| LiteLLM (for AI) | http://192.168.1.222:4000 | API key: `sk-master-key` |
| OpenClaw | http://192.168.1.6:18789 | Bearer token from `.env` |
| Frigate | http://192.168.1.222:5000 | No auth by default |
| KVM Operator | http://192.168.1.9:5000 | Bearer token from `.env` |
| Proxmox | https://192.168.1.174:8006 | Proxmox root account |
| Ollama | http://192.168.1.6:11434 | No auth by default |
| Open WebUI | http://192.168.1.6:3000 | Your Open WebUI account |

---

*End of Home Assistant Layman's Guide. For advanced automations, HA scripting, and template tricks, visit the official Home Assistant documentation at https://www.home-assistant.io/docs/ and the community forums at https://community.home-assistant.io/*
