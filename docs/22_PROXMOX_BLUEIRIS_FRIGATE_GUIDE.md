# Proxmox + Blue Iris + Frigate: The Complete Layman's Guide

**Who this guide is for:** Anyone who wants to record and analyze security camera footage using a mix of professional and open-source tools — and then connect it all to AI for smart alerts.

---

## Table of Contents

1. [Your Hardware Control Stack (Plain English)](#part-1--your-hardware-control-stack-plain-english)
2. [Setting Up Proxmox](#part-2--setting-up-proxmox)
3. [Setting Up Blue Iris on Your Windows VM](#part-3--setting-up-blue-iris-on-windows-vm)
4. [Setting Up Frigate](#part-4--setting-up-frigate)
5. [Connecting Cameras to Home Assistant](#part-5--connecting-cameras-to-home-assistant)
6. [AI-Powered Camera Analysis Pipeline](#part-6--ai-powered-camera-analysis-pipeline)
7. [Remote Access with KVM](#part-7--remote-access-with-kvm)
8. [Troubleshooting](#part-8--troubleshooting)

---

## Part 1 — Your Hardware Control Stack (Plain English)

### The Big Picture

This setup uses four software layers to watch, record, and intelligently analyze your cameras:

```
IP Cameras (on your network)
        ↓
Blue Iris (Windows VM) and/or Frigate (Docker)
   — record video, detect motion
        ↓
Node E Sentinel (192.168.1.x)
   — receives alerts, orchestrates AI analysis
        ↓
Node C Ollama — llava vision model
   — AI describes what it sees in snapshots
        ↓
Home Assistant (192.168.1.149)
   — sends notifications to your phone
```

Each layer does a specific job. You don't have to use all of them — start with what you need and add more as you go.

### What Is Proxmox?

**Proxmox** (at `https://192.168.1.174:8006`) is a free, open-source **hypervisor**. A hypervisor is software that lets one physical computer pretend to be many computers at the same time.

Think of it like an apartment building. Proxmox is the building. Each virtual machine (VM) is an apartment. The apartments share the same physical walls (hardware) but each one operates independently — different operating systems, different software, different purposes.

In this setup, Proxmox hosts:
- A **Windows VM** (for Blue Iris)
- Possibly other VMs for other services

### What Is Blue Iris?

**Blue Iris** is professional Windows software for recording security cameras. It:
- Records RTSP streams from IP cameras
- Detects motion (and can run local AI to classify it)
- Sends alerts via email, MQTT, webhook
- Has a full web interface for remote viewing
- Supports hundreds of simultaneous cameras
- Costs about $70 (one-time purchase)

It runs on Windows, which is why you need the Windows VM inside Proxmox.

### What Is Frigate?

**Frigate** is free, open-source software that does similar things to Blue Iris — but runs in **Docker**, not on Windows. It:
- Records RTSP camera streams
- Uses AI object detection (TensorFlow/OpenCV) to find people, cars, dogs, etc.
- Has a clean web UI
- Sends events via MQTT and webhooks
- Integrates natively with Home Assistant
- Works especially well with a **Coral TPU** for fast, energy-efficient AI detection

### Blue Iris vs. Frigate — Which Should You Use?

| Feature | Blue Iris | Frigate |
|---------|-----------|---------|
| Cost | ~$70 | Free |
| OS | Windows only | Docker (Linux/Mac/Windows) |
| AI Detection | Built-in + CodeProject.AI | TensorFlow / YOLO |
| HA Integration | Via MQTT | Native HACS integration |
| Recording Quality | Excellent | Very good |
| Ease of setup | Moderate | Moderate |
| Coral TPU support | No | Yes |
| Best for | Professional recording | AI-first detection |

**Our recommendation:** Use both. Blue Iris handles recording and reliability. Frigate handles smart detection and HA integration. They can watch the same cameras independently.

### How Everything Connects

Here's the complete data flow:

1. **Cameras** stream video via RTSP to Blue Iris and Frigate
2. **Motion is detected** — Blue Iris sends an MQTT alert, Frigate sends an MQTT event + webhook
3. **Node E Sentinel** receives the webhook, grabs a camera snapshot
4. **Sentinel** posts the snapshot to Node C's Ollama with the LLaVA vision model
5. **Ollama** describes what it sees in plain English
6. **Sentinel** forwards that description to **Home Assistant**
7. **Home Assistant** sends you a **push notification** on your phone with the AI description

---

## Part 2 — Setting Up Proxmox

### Accessing Proxmox

Open a browser and go to:

```
https://192.168.1.174:8006
```

You'll see a security warning because Proxmox uses a self-signed SSL certificate. Click **Advanced → Proceed** (or equivalent in your browser). Log in with your Proxmox root credentials.

### The Proxmox Interface At a Glance

- **Left sidebar:** Your datacenter, nodes, and VMs listed as a tree
- **Top right:** Create VM, Create CT (container) buttons
- **Center panel:** Summary of whatever you've clicked on
- **Console tab:** Live view of the VM's screen (like a remote monitor)

### Creating a Windows VM: Step by Step

#### Step 1: Download a Windows ISO

You need a Windows 10 or Windows 11 ISO file. Download it from Microsoft's official site and upload it to Proxmox:

In Proxmox:
1. Click on your node (e.g., `pve`) in the left sidebar
2. Click **local** (the storage) → **ISO Images**
3. Click **Upload** and upload your Windows ISO
4. Also upload the **VirtIO drivers ISO** from https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso — this improves performance significantly

#### Step 2: Create the VM

Click the **Create VM** button at the top right. Fill in each tab:

**General tab:**
- VM ID: `100` (or any unused number)
- Name: `windows-blueiris`

**OS tab:**
- ISO image: Select your Windows ISO
- Type: Microsoft Windows
- Version: 10/2016/2019 (or 11/2022)

**System tab:**
- Machine: `q35`
- BIOS: `OVMF (UEFI)` — modern, compatible with Windows 11
- Add TPM: Check this box if using Windows 11
- Add EFI Disk: Yes

**Disks tab:**
- Bus/Device: `VirtIO Block`
- Size: `60 GB` minimum (more if you want local recording storage — 200+ GB recommended for Blue Iris)
- Cache: `Write back`

**CPU tab:**
- Cores: `4`
- Type: `host` (gives Windows access to all CPU features)

**Memory tab:**
- RAM: `8192` MB (8 GB) — Blue Iris is memory-hungry, 16 GB is better

**Network tab:**
- Model: `VirtIO (paravirtualized)` — best performance

Click **Finish**.

#### Step 3: Install Windows

1. Select your new VM in the left sidebar
2. Click **Start** (top right)
3. Click the **Console** tab — you see the VM's screen
4. Windows setup will start from the ISO

During setup:
- When Windows asks for network drivers and doesn't find them: open the VirtIO ISO you uploaded (it will appear as a CD drive) and install the network drivers from `virtio-win/NetKVM/w10/amd64/`
- For storage drivers (if Windows can't see the disk): same VirtIO ISO, `virtio-win/viostor/w10/amd64/`

Complete the normal Windows installation process.

#### Step 4: Install QEMU Guest Agent

After Windows is installed and running:

1. In Proxmox, make sure the VirtIO ISO is still mounted (or mount it again)
2. Inside Windows, open the VirtIO ISO
3. Run `virtio-win-guest-tools.exe` — this installs all drivers AND the QEMU Guest Agent
4. Restart Windows when prompted

Once the Guest Agent is installed, Proxmox can:
- See the VM's IP address
- Gracefully shut down the VM via the Proxmox UI
- Take consistent snapshots (filesystem freeze)

#### Step 5: Take a Snapshot

**Before you install Blue Iris** (or any other software), take a snapshot. This gives you a restore point.

1. Click your VM in the left sidebar
2. Click the **Snapshots** tab
3. Click **Take Snapshot**
4. Name it: `clean-windows-install`
5. Check **Include RAM** if you want to snapshot while running
6. Click **Take Snapshot**

If anything goes wrong later, you can restore this snapshot and start over.

### How to Start and Stop VMs from the Proxmox UI

- **Start VM:** Click the VM → Click **Start** (▶) button
- **Shutdown VM:** Click the VM → Click **Shutdown** (graceful, tells Windows to close)
- **Stop VM:** Click **Stop** (force-off, like pulling the power cord — only do this if Shutdown hangs)
- **Reboot VM:** Click **Reboot**

You can also do these from the command line on Proxmox:

```bash
# Start VM 100
qm start 100

# Shutdown VM 100
qm shutdown 100

# Reboot VM 100
qm reboot 100

# Check status
qm status 100
```

### How NanoKVM Connects to Proxmox

NanoKVM is a small hardware device that connects to your **physical Proxmox server** via:
- **HDMI input** (captures what's on the server's screen)
- **USB** (acts as a keyboard and mouse)
- **Network** (connects to your LAN, gets an IP like 192.168.1.200)

This means even if Proxmox's network is misconfigured, or you need to press F2 to enter BIOS, NanoKVM lets you do it from your browser or through the KVM Operator API.

### Proxmox Backups

For long-term reliability, configure regular backups:

1. In Proxmox, go to **Datacenter → Backup**
2. Click **Add**
3. Set a schedule (e.g., every Sunday at 2:00 AM)
4. Select which VMs to back up
5. Choose storage location
6. Set retention (e.g., keep last 3 backups)

For professional backups, **Proxmox Backup Server (PBS)** is a free companion product that provides:
- Incremental backups (only backs up what changed)
- Deduplication (saves disk space)
- Encryption
- Fast restore

Install PBS on a separate machine (or VM) and add it as a storage target in Proxmox.

---

## Part 3 — Setting Up Blue Iris on Windows VM

### What Blue Iris Is

Blue Iris is Windows software that connects to your IP cameras and:
- Records video 24/7 or on motion
- Provides a web interface for live view and playback
- Sends alerts when motion or objects are detected
- Integrates with MQTT, webhooks, email, push notifications

It runs directly on Windows, which is why you installed a Windows VM in Proxmox.

### Installing Blue Iris

1. In your Windows VM, open a browser
2. Go to https://blueirissoftware.com
3. Download the installer
4. Run the installer — it's a standard Windows installer
5. Blue Iris starts automatically after installation
6. Enter your license key (or use the 15-day trial)

Blue Iris opens with a settings wizard. Follow it to set your recording paths (point it to a large drive if you have one).

### Adding Your IP Cameras

Each camera has an **RTSP URL** — a network address that streams video. Common formats:

```
# Hikvision cameras:
rtsp://admin:password@192.168.1.50:554/Streaming/Channels/101

# Dahua cameras:
rtsp://admin:password@192.168.1.51:554/cam/realmonitor?channel=1&subtype=0

# Reolink cameras:
rtsp://admin:password@192.168.1.52:554/h264Preview_01_main

# Generic / Onvif:
rtsp://admin:password@192.168.1.53:554/stream1
```

To add a camera in Blue Iris:

1. Click the **+** button (Add Camera) in the main window
2. Go to **Video** tab → **Network IP** → Paste your RTSP URL
3. Give it a short name (e.g., `frontdoor`, `backyard`)
4. Click **OK** — you should see the camera feed appear

Repeat for each camera.

### Setting Recording Schedules

In each camera's settings → **Record** tab:
- **Continuous:** Records 24/7 (uses a lot of storage)
- **Triggered:** Records only when motion/AI detects something
- **Schedule:** Records during certain hours only

For most home setups, **Triggered** is ideal. You get footage of events without filling your disk overnight.

### Blue Iris MQTT Integration

MQTT is a lightweight messaging protocol that Home Assistant uses extensively. Blue Iris can publish camera events to an MQTT broker.

In Blue Iris → **Settings → Digital IO and IoT → MQTT**:

```
Server: 192.168.1.149  (your MQTT broker — usually runs on the HA machine)
Port: 1883
Topic prefix: blueiris/
Client ID: blueiris
```

When motion is detected on your `frontdoor` camera, Blue Iris publishes:

```
Topic: blueiris/frontdoor/trigger
Payload: {"camera": "frontdoor", "trigger": "motion", "confidence": 85}
```

Home Assistant subscribes to these topics and can fire automations when they arrive.

### Accessing Blue Iris Remotely

Blue Iris has a built-in web server. Enable it in **Settings → Web Server**:
- Port: `81` (or any unused port)
- Enable authentication

To access it securely from outside your home:

**Option A: Tailscale** (recommended for beginners)
- Install Tailscale on the Windows VM
- Access Blue Iris via Tailscale IP from anywhere

**Option B: Your domain**
- Point `cameras.happystrugglebus.us` to your home IP
- Set up a reverse proxy (Nginx Proxy Manager) to forward to Blue Iris
- Enable HTTPS

### Connecting Blue Iris to Node E Sentinel

For AI analysis, Blue Iris can send a snapshot and webhook to Node E Sentinel when motion is detected.

In a camera's settings → **Alerts** tab → **On trigger** → **Post to a web server**:

```
URL: http://NODE_E_IP:PORT/webhook/camera-alert
Method: POST
Content-Type: application/json
Body:
{
  "camera": "&CAM",
  "trigger": "&TYPE",
  "time": "&TIME",
  "snapshot_url": "http://192.168.1.XXX:81/image/&CAM?q=50&s=&SIZE"
}
```

Replace `NODE_E_IP:PORT` with your Node E Sentinel address. Sentinel will receive this, fetch the snapshot, analyze it with LLaVA, and forward the results to Home Assistant.

---

## Part 4 — Setting Up Frigate

### What Frigate Is

Frigate is an open-source NVR (Network Video Recorder) that runs in Docker and has **AI object detection built in**. It can identify:
- People
- Cars
- Dogs, cats, birds
- Bicycles, motorcycles
- License plates (with additional plugins)

Unlike Blue Iris, Frigate was designed from the ground up to work with Home Assistant.

### Frigate Docker Compose on Node B (192.168.1.222)

Create a directory for Frigate on Node B:

```bash
mkdir -p /opt/frigate/config
mkdir -p /opt/frigate/storage
```

Create the Docker Compose file:

```bash
nano /opt/frigate/docker-compose.yml
```

```yaml
version: "3.9"

services:
  frigate:
    container_name: frigate
    privileged: true
    restart: unless-stopped
    image: ghcr.io/blakeblackshear/frigate:stable
    shm_size: "128mb"
    devices:
      # Uncomment if you have a Coral USB accelerator:
      # - /dev/bus/usb:/dev/bus/usb
      # Uncomment for Intel QuickSync hardware decoding:
      # - /dev/dri/renderD128:/dev/dri/renderD128
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /opt/frigate/config:/config
      - /opt/frigate/storage:/media/frigate
      - type: tmpfs
        target: /tmp/cache
        tmpfs:
          size: 1000000000
    ports:
      - "5000:5000"    # Frigate Web UI
      - "8554:8554"    # RTSP feeds (re-streamed from Frigate)
      - "8555:8555/tcp"  # WebRTC
      - "8555:8555/udp"
    environment:
      FRIGATE_RTSP_PASSWORD: "your_camera_password"
```

### Frigate Configuration (config.yml)

Create the Frigate config file:

```bash
nano /opt/frigate/config/config.yml
```

```yaml
# Frigate Configuration File
# Place at /opt/frigate/config/config.yml

mqtt:
  host: 192.168.1.149      # Your MQTT broker (usually same machine as Home Assistant)
  port: 1883
  user: mqtt_user
  password: mqtt_password

cameras:
  frontdoor:
    ffmpeg:
      inputs:
        - path: rtsp://admin:{FRIGATE_RTSP_PASSWORD}@192.168.1.50:554/Streaming/Channels/101
          roles:
            - detect    # Used for AI object detection (lower resolution)
            - record    # Full recording stream (higher resolution)
    detect:
      enabled: true
      width: 1280
      height: 720
      fps: 5              # 5 frames per second is enough for detection
    record:
      enabled: true
      retain:
        days: 7           # Keep recordings for 7 days
        mode: motion      # Only keep clips with motion
      events:
        retain:
          default: 14     # Keep event clips for 14 days
    motion:
      threshold: 25
      mask:
        - 0,0,1280,100    # Mask out the top 100px (e.g., sky/trees that always move)
    objects:
      track:
        - person
        - car
        - dog
        - cat
      filters:
        person:
          min_area: 5000   # Ignore tiny detections
          min_score: 0.5   # 50% minimum confidence

  backyard:
    ffmpeg:
      inputs:
        - path: rtsp://admin:{FRIGATE_RTSP_PASSWORD}@192.168.1.51:554/cam/realmonitor?channel=1&subtype=0
          roles:
            - detect
            - record
    detect:
      enabled: true
      width: 1280
      height: 720
      fps: 5
    record:
      enabled: true
      retain:
        days: 7
        mode: motion
    objects:
      track:
        - person
        - car

detectors:
  cpu1:
    type: cpu
    num_threads: 3
  # Uncomment if you have a Coral USB TPU:
  # coral:
  #   type: edgetpu
  #   device: usb

# Optional: use hardware decoding on Node B's RTX 4070
# ffmpeg:
#   hwaccel_args:
#     - -hwaccel
#     - cuda
#     - -hwaccel_output_format
#     - cuda
```

### Starting Frigate

```bash
cd /opt/frigate
docker compose up -d
```

Check logs:

```bash
docker logs frigate --tail 50 -f
```

You should see Frigate loading your config, connecting to cameras, and starting detection.

### Accessing Frigate UI

Open your browser:

```
http://192.168.1.222:5000
```

You'll see:
- **Live** tab: Real-time camera feeds with detected objects highlighted
- **Events** tab: All detected events with snapshots and short clips
- **Recordings** tab: Full recordings timeline

### Coral TPU (Optional — But Recommended)

A **Google Coral USB Accelerator** ($60-80) dramatically speeds up Frigate's AI detection and uses almost no CPU. Instead of using 100% of a CPU core for AI, the Coral processes detections in milliseconds.

If you have one:
1. Plug the Coral USB into Node B
2. Uncomment the `devices` section in docker-compose.yml
3. Uncomment the `coral` detector in config.yml
4. Remove or disable `cpu1` detector

### Frigate MQTT Events

When Frigate detects an object, it publishes to MQTT:

```
frigate/events — new/update/end events (JSON)
frigate/frontdoor/person — 1/0 for person presence
frigate/frontdoor/car — 1/0 for car presence
frigate/stats — system stats
```

An example event payload:

```json
{
  "before": {
    "id": "1699901234.abc123-frontdoor",
    "camera": "frontdoor",
    "label": "person",
    "score": 0.87,
    "top_score": 0.92,
    "has_snapshot": true,
    "has_clip": false
  },
  "after": {
    "id": "1699901234.abc123-frontdoor",
    "camera": "frontdoor",
    "label": "person",
    "score": 0.92,
    "top_score": 0.92,
    "has_snapshot": true,
    "has_clip": true,
    "start_time": 1699901234.5,
    "end_time": null
  },
  "type": "update"
}
```

### Frigate Webhook to Node E Sentinel

In Frigate's `config.yml`, you can configure notifications:

```yaml
notifications:
  webhook:
    enabled: true
    url: http://NODE_E_IP:PORT/webhook/frigate
    headers:
      Authorization: "Bearer YOUR_SENTINEL_TOKEN"
```

Or, use Home Assistant as the intermediary (described in Part 5).

### Frigate + Home Assistant Integration

Install the Frigate HACS integration in Home Assistant:

1. Install HACS (Home Assistant Community Store) — see Part 6 of the HA guide
2. In HACS → Integrations → Search for "Frigate"
3. Install it and restart Home Assistant
4. In HA → Settings → Devices & Services → Add Integration → Frigate
5. Enter Frigate URL: `http://192.168.1.222:5000`

You'll now have camera entities, binary sensors (person detected, car detected), and a Frigate card for your dashboard.

---

## Part 5 — Connecting Cameras to Home Assistant

### Adding Frigate Camera Entities

After installing the Frigate HACS integration, Home Assistant automatically creates:

- `camera.frontdoor` — live stream from Frigate
- `binary_sensor.frontdoor_person` — turns ON when a person is detected
- `binary_sensor.frontdoor_motion` — turns ON when any motion is detected
- `sensor.frontdoor_person_count` — how many people are currently visible

### Basic Motion Automation

The simplest automation: notify when someone is at the front door.

```yaml
automation:
  - alias: "Front Door Person Detected"
    trigger:
      - platform: state
        entity_id: binary_sensor.frontdoor_person
        to: "on"
    condition:
      - condition: time
        after: "07:00:00"
        before: "23:00:00"
    action:
      - service: notify.mobile_app_your_phone
        data:
          title: "👤 Person at Front Door"
          message: "Someone is at the front door."
          data:
            image: /api/frigate/notifications/{{ trigger.event.data.after.id }}/thumbnail.jpg
```

### The Full AI Pipeline Automation

This automation does everything: detects a person, grabs the snapshot, sends it to AI for analysis, then notifies you with the AI description.

```yaml
automation:
  - alias: "Front Door AI Analysis"
    trigger:
      - platform: mqtt
        topic: frigate/events
        payload: "new"
        value_template: "{{ value_json.type }}"
    condition:
      - condition: template
        value_template: "{{ trigger.payload_json.after.label == 'person' and trigger.payload_json.after.camera == 'frontdoor' }}"
    action:
      # Step 1: Get the snapshot URL
      - variables:
          event_id: "{{ trigger.payload_json.after.id }}"
          snapshot_url: "http://192.168.1.222:5000/api/events/{{ event_id }}/snapshot.jpg"

      # Step 2: Send to AI for analysis
      - service: rest_command.analyze_camera_snapshot
        data:
          snapshot_url: "{{ snapshot_url }}"
          camera: "frontdoor"
          label: "{{ trigger.payload_json.after.label }}"

      # Step 3: Wait briefly for the AI response
      - delay: "00:00:05"

      # Step 4: Notify with AI description
      - service: notify.mobile_app_your_phone
        data:
          title: "👤 Person at Front Door"
          message: "{{ states('input_text.ai_camera_description') }}"
          data:
            image: "{{ snapshot_url }}"
```

### Viewing Camera Streams in HA Dashboard

Add a camera card to your Lovelace dashboard:

**Simple Camera Card:**
```yaml
type: picture-entity
entity: camera.frontdoor
show_state: false
show_name: true
camera_view: live
```

**Frigate Event Card (shows recent detections):**
```yaml
type: custom:frigate-card
cameras:
  - camera_entity: camera.frontdoor
    frigate:
      url: http://192.168.1.222:5000
      camera_name: frontdoor
      labels:
        - person
        - car
```

### Blue Iris MQTT Events in HA

If you're using Blue Iris alongside Frigate, add an MQTT sensor in HA:

```yaml
# configuration.yaml
mqtt:
  sensor:
    - name: "Blue Iris Front Door"
      state_topic: "blueiris/frontdoor/trigger"
      value_template: "{{ value_json.trigger }}"
      expire_after: 10
```

And an automation to act on it:

```yaml
automation:
  - alias: "Blue Iris Motion Alert"
    trigger:
      - platform: mqtt
        topic: "blueiris/+/trigger"
    action:
      - service: notify.mobile_app_your_phone
        data:
          title: "Camera Alert"
          message: "Motion on {{ trigger.topic.split('/')[1] }}"
```

---

## Part 6 — AI-Powered Camera Analysis Pipeline

### The Full Pipeline, Step by Step

Here's exactly how a person walking past your front door becomes an AI notification on your phone:

```
1. Person walks past front door camera
        ↓
2. Frigate detects "person" with 89% confidence
        ↓
3. Frigate publishes MQTT event to 192.168.1.149:1883
        ↓
4. Home Assistant receives MQTT event
        ↓
5. HA automation fires: "Front Door AI Analysis"
        ↓
6. HA calls webhook to Node E Sentinel (or directly to OpenClaw)
   POST http://NODE_E_IP:PORT/webhook/camera
   Body: { snapshot_url: "http://...", camera: "frontdoor" }
        ↓
7. Sentinel/OpenClaw fetches the snapshot image
        ↓
8. Sends image + prompt to Ollama (LLaVA vision model) on Node C:
   POST http://192.168.1.6:11434/api/generate
   { model: "llava:latest", prompt: "Describe what you see...", images: [...] }
        ↓
9. LLaVA analyzes the image and returns a description
        ↓
10. Sentinel/OpenClaw sends description back to HA
        ↓
11. HA sends push notification to your phone:
    "Person detected at front door. Appears to be a delivery driver
     in a brown uniform carrying a large box."
```

### Setting Up the Sentinel Webhook

Node E Sentinel is your AI analysis router. Configure its webhook listener:

```yaml
# node-e-sentinel docker-compose snippet
services:
  sentinel:
    environment:
      - CAMERA_WEBHOOK_TOKEN=your-sentinel-token
      - OLLAMA_URL=http://192.168.1.6:11434
      - VISION_MODEL=llava:latest
      - HA_WEBHOOK_URL=http://192.168.1.149:8123/api/webhook/ai-camera-result
      - HA_TOKEN=your-ha-long-lived-token
```

### Customizing the AI Prompt

The AI prompt tells LLaVA what to focus on. Here are some prompt options:

**General description:**
```
Analyze this security camera image and describe what you see. 
Be specific about: who or what is in the frame, what they are doing, 
any identifying features like clothing or vehicle type.
Keep your response under 2 sentences.
```

**Package delivery focus:**
```
Is there a package or delivery person in this image? 
If yes, describe the delivery company (if visible), the size of any packages, 
and whether anyone is present. If no delivery, just say what you see instead.
```

**Security focus:**
```
This is a security camera image. Describe anyone present: 
their approximate age range, clothing, and what they appear to be doing. 
Note anything unusual or suspicious. Be factual and brief.
```

**Vehicle focus:**
```
Is there a vehicle in this image? If yes: describe the color, type (car/truck/SUV), 
and any visible license plate. If it's a person, describe their appearance briefly.
```

### Configuring HA rest_command for AI Analysis

Add to `configuration.yaml`:

```yaml
rest_command:
  analyze_camera_snapshot:
    url: "http://192.168.1.6:18789/hooks/agent"
    method: POST
    headers:
      Authorization: "Bearer YOUR_OPENCLAW_TOKEN"
      Content-Type: "application/json"
    payload: >
      {
        "prompt": "Analyze this security camera snapshot from the {{ camera }} camera. 
          A {{ label }} was detected. Describe what you see in 1-2 sentences. 
          Be specific and factual.",
        "image_url": "{{ snapshot_url }}",
        "model": "ollama/llava:latest",
        "response_entity": "input_text.ai_camera_description"
      }
```

### Example Notifications You'll Get

After setting this up, your phone notifications might look like:

> **👤 Front Door — 2:34 PM**
> *Person detected at front door. Appears to be a delivery driver in a blue Amazon uniform placing a brown cardboard box near the door.*

> **🚗 Driveway — 6:17 PM**
> *Car detected in driveway. A white Toyota Camry has pulled in; a person is exiting from the driver's side.*

> **🐕 Backyard — 11:02 AM**
> *Dog detected in backyard. A medium-sized brown dog is running near the fence line.*

---

## Part 7 — Remote Access with KVM

### Controlling Your Windows VM Remotely with OpenClaw

Sometimes Blue Iris crashes, or Windows needs a restart, or you need to check something on the Windows VM. Without KVM, you'd need to walk to your server room.

With OpenClaw + KVM Operator, you can:

1. Open the OpenClaw chat at `http://192.168.1.6:18789/?token=YOUR_TOKEN`
2. Type: *"Restart Blue Iris on the Windows VM"*
3. Approve the action at `http://192.168.1.9:5000/approve`
4. Done — Blue Iris restarts remotely

### How OpenClaw Controls the Windows VM

When you ask OpenClaw to restart Blue Iris:

1. OpenClaw's KVM skill interprets your request
2. It calls the KVM Operator API: `POST http://192.168.1.9:5000/vm/keypress`
3. KVM Operator passes the command to NanoKVM
4. NanoKVM (physically connected to your Proxmox server) simulates keystrokes:
   - `Win+R` (opens Run dialog)
   - Types `taskkill /f /im BlueIris.exe && start "" "C:\Program Files\Blue Iris 5\BlueIris.exe"`
   - Presses Enter
5. KVM Operator reports success back to OpenClaw
6. OpenClaw tells you: "Blue Iris has been restarted."

### Safety: The Approval Step

Because the KVM Operator has `REQUIRE_APPROVAL=true`, step 4 above doesn't happen automatically. After step 3:

- The action is queued as "pending"
- OpenClaw tells you: "Waiting for approval at http://192.168.1.9:5000/approve"
- You go to that URL, verify the action looks correct, and click Approve
- Then step 4 executes

This prevents accidents — if you accidentally ask OpenClaw to "restart everything," you'll catch it at the approval step.

---

## Part 8 — Troubleshooting

### Proxmox VM Won't Boot

**Symptom:** VM shows as "stopped" or stuck at BIOS/UEFI screen.

**Check 1: Disk issue**
In Proxmox, click your VM → **Hardware** tab. Verify a disk is listed and attached. If the disk shows as detached, reattach it.

**Check 2: Boot order**
VM settings → **Options → Boot Order**. Make sure the disk is listed first (before CD-ROM).

**Check 3: Snapshot rollback**
If a recent change broke the VM:
1. Click your VM → **Snapshots** tab
2. Select `clean-windows-install` (or your most recent good snapshot)
3. Click **Rollback**
4. Confirm — the VM reverts to that state

**Check 4: Console stuck at black screen**
Click the **Console** tab. If it's black, click inside the console window and press a key. Sometimes the VM is running but the console just needs focus.

### Blue Iris Not Receiving Camera Streams

**Symptom:** Camera feed shows "No Signal" or connection errors in Blue Iris.

**Check 1: RTSP URL format**
Test the RTSP URL from another machine:

```bash
# On any Linux machine, test if the stream works:
ffplay rtsp://admin:password@192.168.1.50:554/Streaming/Channels/101
```

If `ffplay` can't connect, the URL is wrong or the camera is offline.

**Check 2: Camera is on the same VLAN/subnet**
If your cameras are on a different network segment, they may not be reachable from the Windows VM. Check your network segmentation settings.

**Check 3: Windows Firewall**
In Windows VM, temporarily disable the firewall:
- Search "Windows Firewall" → Turn off for both Private and Public networks
- If Blue Iris works now, re-enable and add an exception for Blue Iris

**Check 4: Check Blue Iris logs**
In Blue Iris: **Help → About → Log** — look for camera connection error messages.

### Frigate Not Detecting Objects

**Symptom:** Cameras work (you see video) but no events appear in Frigate.

**Check 1: Config syntax**
Frigate won't start if config.yml has errors. Check logs:

```bash
docker logs frigate --tail 100 | grep -i error
```

Validate YAML syntax:

```bash
python3 -c "import yaml; yaml.safe_load(open('/opt/frigate/config/config.yml')); print('Valid')"
```

**Check 2: Camera resolution and FPS**
Make sure `detect.width` and `detect.height` in your config match or are lower than the camera's actual resolution. If you set 1920x1080 but the camera streams 1280x720, detection fails.

**Check 3: CPU load**
Frigate's CPU-based detection is demanding. Check CPU usage:

```bash
docker stats frigate
```

If CPU is constantly at 100%, either:
- Reduce `fps` in camera config to `2` or `3`
- Reduce resolution
- Add a Coral TPU accelerator
- Reduce the number of cameras being detected simultaneously

**Check 4: MQTT broker not running**
Frigate events won't reach HA if MQTT isn't working. Test:

```bash
# Install mosquitto-clients first if needed
mosquitto_sub -h 192.168.1.149 -p 1883 -t "frigate/#" -v
```

You should see events flowing. If nothing appears, Frigate can't reach the MQTT broker.

### Node E Sentinel Not Receiving Webhooks

**Symptom:** Frigate events happen, but Node E Sentinel never receives them.

**Check 1: Is Sentinel running?**

```bash
curl http://NODE_E_IP:PORT/health
```

If you get connection refused, Sentinel isn't running. Start it and check its logs.

**Check 2: Firewall/network**

```bash
# From Node B (Frigate host), test connectivity to Sentinel:
nc -zv NODE_E_IP PORT
```

If blocked, open the port on Node E's firewall.

**Check 3: Authentication token**
Make sure the webhook URL in Frigate's config uses the correct `Authorization` token that Sentinel expects. If the token doesn't match, Sentinel returns `401` and silently drops the request.

**Check 4: Check Sentinel logs for 401/403 errors**

```bash
docker logs sentinel --tail 50 | grep -E "(401|403|error|Error)"
```

### AI Analysis Timing Out

**Symptom:** Sentinel forwards snapshots to Ollama, but responses take too long or time out.

**Check 1: Is the LLaVA model loaded?**

```bash
curl http://192.168.1.6:11434/api/tags
```

Look for `llava:latest` in the list. If it's not there:

```bash
docker exec -it ollama ollama pull llava:latest
```

**Check 2: Node C is overloaded**

Check GPU/CPU usage on Node C. If Ollama is running another request, your camera analysis request has to wait in queue.

**Check 3: Image is too large**

LLaVA processes faster with smaller images. Make sure Frigate snapshots are JPEG at reasonable quality (Frigate defaults are fine). If you're sending full 4K frames, resize them first.

**Check 4: Increase timeout**

In your Sentinel or OpenClaw configuration, increase the AI request timeout:

```bash
VISION_MODEL_TIMEOUT=60  # 60 seconds instead of default 30
```

---

*End of Proxmox + Blue Iris + Frigate Guide. For camera-specific RTSP URL formats, check your camera manufacturer's documentation. For advanced Frigate configuration including zone-based detection and audio, see the official Frigate documentation at https://docs.frigate.video*
