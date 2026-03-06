# 🏠 Home Lab Setup Guide — From Zero to AI in Four Nodes

> **You've got this.** This guide walks you through building a real AI home lab — step by step, one machine at a time. You don't need to be a tech expert. You just need to follow instructions carefully, and this guide will explain every single step along the way.

---

## Table of Contents

- [Chapter 0: Before You Begin](#chapter-0-before-you-begin)
- [Chapter 1: Node A — The Heavy Thinker (AMD RX 7900 XT)](#chapter-1-node-a--the-heavy-thinker-amd-rx-7900-xt)
- [Chapter 2: Node B — The Command Centre (Unraid + RTX 4070)](#chapter-2-node-b--the-command-centre-unraid--rtx-4070)
- [Chapter 3: Node C — The Chat Interface (Intel Arc A770)](#chapter-3-node-c--the-chat-interface-intel-arc-a770)
- [Chapter 4: Node D — Home Assistant Talks to AI](#chapter-4-node-d--home-assistant-talks-to-ai)
- [Chapter 5: The Final Check — Is Everything Working Together?](#chapter-5-the-final-check--is-everything-working-together)

---

# Chapter 0: Before You Begin

## What This Guide Covers

Welcome! By the end of this guide, you'll have a working **four-node AI home lab** running in your house. In plain English: you'll have four computers talking to each other, with one of them running artificial intelligence that you can chat with — privately, on your own hardware, no subscription, no cloud, no monthly fee.

Here's the big picture of what each computer (we call them **nodes**) will do:

| Node | Computer | Role |
|------|----------|------|
| **Node A** | Fedora Linux + AMD GPU | Runs AI models — the "brain" |
| **Node B** | Unraid Server + NVIDIA GPU | The hub — runs the dashboard, automation, fast AI |
| **Node C** | Fedora Linux + Intel GPU | Runs the chat website you'll open in your browser |
| **Node D** | Home Assistant | Your smart home controller — now with AI! |

This is **Phase 1** — a solid, working foundation. Think of it as getting all the furniture into the house before you start decorating.

---

## The Recipe Analogy — Understanding Docker, Containers, and Nodes

Before we touch a single command, let's make sure you understand the building blocks. Don't skip this section — it'll make everything else click.

**A Node** is just a computer. You might call it a "server" or a "machine." In this guide, we have four of them sitting in your house, connected to your home network (your Wi-Fi router). When we say "Node A," we just mean "that computer with the AMD graphics card."

**Docker** is a program that lets you run software in a controlled box. Imagine Docker as a kitchen: it lets you cook many different recipes (programs) without them interfering with each other. Each recipe gets its own pot, its own ingredients, its own space.

**A Container** is one running recipe in that kitchen. Each container is its own little isolated world — it has its own software, its own settings, and it doesn't care what's happening in the next container. You can start it, stop it, throw it away and rebuild it without affecting anything else.

**An Image** is the recipe card itself — the instructions Docker uses to create a container. You "pull" (download) an image, and Docker can run it as a container.

**A Volume** is where a container saves its data. When you stop a container, its data would normally disappear — like clearing a whiteboard. A volume is a folder on your actual hard drive that the container writes to, so the data survives even if you restart or rebuild the container.

**A Compose File** (also called `docker-compose.yml` or `compose.yml`) is a text file that lists multiple containers and their settings in one place. Instead of running 10 containers one by one, you point Docker at this file and it sets everything up at once.

---

## Glossary

Here are the terms you'll see throughout this guide. Keep this table handy — it's your cheat sheet.

| Term | Plain English Meaning |
|------|-----------------------|
| **Node** | A computer in your home lab network |
| **Container** | A small, isolated box that runs one piece of software |
| **Docker** | The program that creates and manages containers |
| **Image** | The downloaded recipe that Docker uses to build a container |
| **Volume** | A real folder on your hard drive where container data is saved |
| **Compose File** | A text file listing multiple containers and their settings |
| **.env File** | A text file containing settings/passwords your containers read at startup |
| **Port** | A numbered "door" on a computer. Programs listen on specific ports (e.g., port 80 is the normal web door) |
| **SSH** | A way to securely connect to another computer's terminal from your laptop |
| **Terminal** | The black (or white) box where you type commands. Also called "command line," "shell," or "console" |
| **IP Address** | A number like `192.168.1.9` — the address of a specific computer on your network |
| **Service** | A program running inside a container, doing a specific job (e.g., serving a website) |

---

## Your Hardware

Here's what you're working with:

| Node | OS | GPU | IP Address | Role |
|------|----|-----|------------|------|
| **Node A** | Fedora 44 Linux | AMD RX 7900 XT | `192.168.1.9` | AI model inference (ROCm) |
| **Node B** | Unraid OS | NVIDIA RTX 4070 | `192.168.1.222` | Hub — dashboards, automation, fast AI |
| **Node C** | Fedora 44 Linux | Intel Arc A770 | `192.168.1.6` | Chat interface (Open WebUI) |
| **Node D** | Home Assistant OS | — | `192.168.1.149` | Smart home + AI integration |

**Your laptop or desktop** is your **control machine** — you'll run almost every command *from* your laptop, connecting remotely to each node. You won't need to physically sit at each server with a keyboard. That's the beauty of SSH.

---

## What You'll Need Before Starting

- ✅ A laptop or desktop computer with internet access
- ✅ All four nodes powered on and connected to your home network (same router)
- ✅ The username and password for each node
- ✅ The `fresh-rebuild-2026/` project folder on your laptop (downloaded from the repo)
- ✅ About 3–4 hours of uninterrupted time

---

## Opening a Terminal on Your Control Machine

A **terminal** is the window where you type commands. Here's how to open one:

**On Windows:**
Press `Windows + X`, then click **Windows Terminal** or **PowerShell**. If you don't have Windows Terminal, search for "PowerShell" in the Start Menu.

**On Mac:**
Press `Cmd + Space`, type `Terminal`, press Enter.

**On Linux:**
Press `Ctrl + Alt + T`. A terminal window will open.

Once you see a blinking cursor waiting for you to type, you're ready.

---

## How to SSH Into a Remote Machine

**SSH** (Secure Shell) is how you control a remote computer from your laptop. Think of it as a secure telephone call where instead of talking, you type commands.

The format is always:
```bash
ssh your_username@ip_address_of_the_node
```

For example, to connect to Node A (replace `youruser` with your actual username on that machine):
```bash
ssh youruser@192.168.1.9
```

The first time you connect to a new machine, it will ask: *"Are you sure you want to connect?"* — type `yes` and press Enter.

Then type your password when prompted (the cursor won't move as you type — that's normal, it's just hidden for security).

**To disconnect** from an SSH session (return to your own laptop's terminal), type:
```bash
exit
```

---

## Setting Up SSH Keys — Skip Typing Your Password Every Time

Right now, every time you SSH in, you type a password. SSH keys let you log in automatically — much faster and more secure. Here's how to set them up:

**Step 1: Generate a key pair on your laptop** (only do this once):
```bash
ssh-keygen -t ed25519 -C "homelab"
```
This creates two files: a **private key** (stays on your laptop, never share it) and a **public key** (gets copied to each server). When it asks for a passphrase, you can press Enter to leave it blank (simpler) or set one (more secure).

**Step 2: Copy your public key to Node A:**
```bash
ssh-copy-id youruser@192.168.1.9
```
It asks for your password one last time, then copies the key. After this, `ssh youruser@192.168.1.9` will log you in without a password.

**Repeat Step 2 for each node** (replacing the IP and username):
```bash
ssh-copy-id youruser@192.168.1.6
ssh-copy-id root@192.168.1.222
```

💡 **Tip:** Node B (Unraid) uses `root` as the username by default.

---

## Verifying Docker Is Installed

Once you've SSH'd into a node, you can check if Docker is already installed by running:
```bash
docker --version
```

Expected output (the exact version number might differ, that's fine):
```
Docker version 27.3.1, build ce12230
```

Also check that Docker Compose is installed:
```bash
docker compose version
```

Expected output:
```
Docker Compose version v2.29.7
```

⚠️ **If you see "command not found"**, Docker isn't installed yet. The chapters below cover installation for each node.

---

## Getting the Project Files Onto Your Laptop

If you don't already have the project files, clone the repository:
```bash
git clone https://github.com/yourrepo/onemoreytry.git
cd onemoreytry
```

`git clone` downloads the entire project from GitHub onto your laptop. `cd` means "change directory" — it moves you into that folder.

Once you have the files locally, each chapter will show you how to copy the right folder to the right node.

---

# Chapter 1: Node A — The Heavy Thinker (AMD RX 7900 XT)

**What Node A does:** Node A is the workhorse. It uses the AMD RX 7900 XT graphics card to run AI models — programs that understand and generate text. When you ask an AI a question on your home lab, there's a good chance Node A is doing the heavy lifting.

💡 **Before starting:** Make sure Node A is powered on, connected to your network, and you know its username and password.

---

## Part 1: Install ROCm — AMD's GPU Language for AI

Your AMD graphics card (GPU) is incredibly powerful, but it speaks its own language. **ROCm** (pronounced "rock-em") is the software that translates between the AI programs and your AMD hardware. Without ROCm, your GPU would just sit there doing nothing — all the AI work would fall back to the slower CPU.

SSH into Node A from your laptop:
```bash
ssh youruser@192.168.1.9
```

**Step 1: Add the AMD software repository**

A **repository** (or "repo") is like an app store — a list of software packages your system can download and install.
```bash
sudo dnf install -y https://repo.radeon.com/amdgpu-install/6.3/rhel/9.4/amdgpu-install-6.3.60300-1.el9.noarch.rpm
```
This downloads and registers the AMD software store so your system knows where to find the GPU tools. The `sudo` at the front means "run this as administrator."

**Step 2: Install the ROCm stack**
```bash
sudo amdgpu-install --usecase=rocm --no-dkms
```
This tells the installer: "Set up ROCm for AI work, but skip the display driver parts." `--no-dkms` avoids touching your display setup — we just want the compute side.

This step takes a few minutes. You'll see a lot of text scrolling by — that's normal.

**Step 3: Add yourself to the GPU user groups**

Linux controls who can access hardware through **groups** (think of them as VIP lists). You need to be on the list to use the GPU.
```bash
sudo usermod -aG render,video $USER
```
`$USER` automatically fills in your own username — you don't need to replace it.

**Step 4: Reboot**

⚠️ **This reboot is mandatory.** The group changes don't take effect until you log out and back in. Rebooting is the cleanest way to ensure everything takes effect.
```bash
sudo reboot
```
Your SSH connection will drop. Wait about 60 seconds, then reconnect:
```bash
ssh youruser@192.168.1.9
```

**Step 5: Verify ROCm sees your GPU**
```bash
rocm-smi
```

Expected output (something like this):
```
======================= ROCm System Management Interface =======================
================================= Concise Info =================================
GPU  Temp (DieEdge)  AvgPwr  SCLK    MCLK     Fan    Perf    PwrCap  VRAM%  GPU%
  0         38.0°C   32.0W  800Mhz  96Mhz   0.0%   auto   287.0W    1%   0%
================================================================================
```

You should see at least one row (your RX 7900 XT). If you see a table like that, ROCm is working. 🎉

✅ Verify: `rocm-smi` shows your GPU listed with a temperature reading.

---

## Part 2: Install Docker on Fedora 44

Now let's install Docker so we can run containers on Node A.

**Step 1: Install a helper tool first**
```bash
sudo dnf -y install dnf-plugins-core
```
This installs a plugin that lets `dnf` (Fedora's package manager — think of it as Fedora's app store) manage software repositories.

**Step 2: Add Docker's official software repository**
```bash
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
```
Tells your system: "Docker's software is available here — trust this source."

**Step 3: Install Docker and its components**
```bash
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```
This installs the full Docker package. `docker-ce` is the main engine, `docker-ce-cli` is the command-line tool you type into, and `docker-compose-plugin` adds the `docker compose` command.

**Step 4: Start Docker and set it to auto-start on reboot**
```bash
sudo systemctl enable --now docker
```
`enable` means "start automatically when the computer boots." `--now` means "also start it right now, don't wait for a reboot."

**Step 5: Add yourself to the Docker group**
```bash
sudo usermod -aG docker $USER
```
Without this, you'd have to type `sudo` before every Docker command. This is the same VIP-list trick as with ROCm.

**Step 6: Apply the group change immediately**
```bash
newgrp docker
```
This refreshes your group membership without a full logout. You might need to do this again after re-connecting via SSH.

**Verify Docker is working:**
```bash
docker --version
docker compose version
```

Expected output:
```
Docker version 27.3.1, build ce12230
Docker Compose version v2.29.7
```

✅ Verify: Both commands return a version number.

---

## Part 3: Copy the Node A Project Files

From **your laptop** (not from Node A — open a new terminal on your laptop or type `exit` first), copy the Node A project folder over:
```bash
scp -r fresh-rebuild-2026/node-a/ youruser@192.168.1.9:~/homelab-node-a/
```

`scp` stands for "Secure Copy" — it copies files over SSH. The `-r` flag means "copy the folder and everything inside it." After the `:`, you specify where on Node A to put it — `~/` means "your home folder."

This creates a `homelab-node-a` folder in your home directory on Node A.

---

## Part 4: Create Your .env File

An **.env file** is a simple text file full of settings — like a preferences menu for your containers. Each line is a `NAME=value` pair. The containers read these values when they start up.

SSH back into Node A:
```bash
ssh youruser@192.168.1.9
cd ~/homelab-node-a
```

`cd` means "change directory." Now you're inside the project folder.

Copy the example file to create your real settings file:
```bash
cp .env.example .env
```

Open it to edit:
```bash
nano .env
```

`nano` is a simple text editor that runs in your terminal. Use arrow keys to move around. Here's what each line means:

| Setting | Example | What It Means |
|---------|---------|---------------|
| `TZ=America/New_York` | `America/Chicago`, `Europe/London` | Your timezone. Logs will show correct local times. |
| `APPDATA_PATH=/opt/ollama` | Any folder path | Where model files and container data are stored on this machine. |

Set your timezone and save the file:
- Press `Ctrl + O` to save ("Write Out")
- Press `Enter` to confirm the filename
- Press `Ctrl + X` to exit nano

---

## Part 5: Start Node A Services

You're ready to launch. This single command reads your compose file and starts all the containers defined in it:
```bash
docker compose -f compose.yml up -d
```

`-f compose.yml` tells Docker which compose file to use. `-d` means **detached** — the containers run in the background so you can close your terminal without stopping them. Think of it like starting a movie and walking out of the room — it keeps playing.

You'll see Docker downloading images and creating containers. The first time takes a few minutes because it has to download everything.

**What just happened?** Docker read your `compose.yml` file, downloaded the container images from the internet, created the containers with your settings from `.env`, and started them all in the background. They'll restart automatically if the machine reboots.

✅ Verify all containers are running:
```bash
docker ps
```

You should see a table with each container showing **"Up X minutes"** in the Status column.

---

## Part 6: Pull Your First AI Model

An **AI model** is like a brain you download. It's the actual trained intelligence that understands your questions and writes responses. Models come in different sizes — larger models are smarter but take more memory and time.

We'll start with `llama3.1:8b` — a capable, reasonably sized model (8 billion parameters — think of "parameters" as the number of connections in the AI's brain).
```bash
docker exec ollama-rocm ollama pull llama3.1:8b
```

`docker exec` means "run a command inside an already-running container." `ollama-rocm` is the container name. `ollama pull llama3.1:8b` is the command we're running inside it — it downloads the model.

This downloads about 4–5 GB of data. It will take **5–15 minutes** depending on your internet speed. You'll see a progress bar. Be patient — this is normal.

Expected output while downloading:
```
pulling manifest
pulling 8eeb52dfb3bb... 45% ████████░░░░░░  2.1 GB/4.7 GB
```

When it's done:
```
success
```

💡 **Tip:** Want to check progress if you've been away? Run: `docker logs ollama-rocm -f` (the `-f` means "follow" — it streams live logs. Press `Ctrl + C` to stop watching).

---

## Part 7: Verify Node A Is Working

Let's confirm the AI service is responding. We'll use `curl` — a command that fetches a URL, just like a browser visiting a webpage, but in text form.
```bash
curl http://192.168.1.9:11435/api/version
```

Expected output:
```json
{"version":"0.5.1"}
```

If you see a version number like that, Node A's Ollama service is running and reachable. 🎉

✅ Verify: `curl` returns a JSON response with a version number.

---

## Troubleshooting Chapter 1

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| `rocm-smi shows nothing` | Forgot to reboot after adding groups | Run `sudo reboot`, reconnect, try again |
| `rocm-smi: command not found` | ROCm didn't install correctly | Re-run the `amdgpu-install` command |
| `docker: command not found` | Docker install step was skipped or failed | Re-run Part 2 from the beginning |
| `curl: Connection refused` | Container isn't running | Run `docker ps` to check; if missing run `docker compose -f compose.yml up -d` |
| `curl: Connection refused` (still) | Container crashed | Run `docker logs ollama-rocm` to see the error message |
| `model pull is stuck for 20+ minutes` | Download stalled | Press `Ctrl + C`, run the pull command again — it resumes where it left off |
| `Permission denied` running docker | Not in docker group | Run `newgrp docker` and try again |

---

# Chapter 2: Node B — The Command Centre (Unraid + RTX 4070)

**What Node B does:** Node B is the hub of your home lab. It runs:
- **Portainer** — a web interface to manage all your containers visually
- **Homepage** — a clean dashboard showing all your services
- **Uptime Kuma** — monitors whether all your services are online
- **Dozzle** — lets you read container logs from a web browser
- **Watchtower** — automatically updates your containers when new versions are released
- **Ollama CUDA** — fast AI inference using the NVIDIA RTX 4070
- **n8n** — a visual automation tool (like IFTTT, but running on your hardware)

💡 **Note:** Complete Chapter 1 fully before starting Chapter 2.

---

## Part 1: Understanding Unraid

**Unraid** is a special operating system designed for home servers. Unlike regular Linux (like Node A), Unraid has a friendly web interface for managing everything. You can control it from your browser without SSH.

**To open the Unraid web interface:**
1. On any computer on your home network, open a web browser
2. Type `http://192.168.1.222` in the address bar
3. Enter your Unraid password

You'll see the Unraid dashboard — your server's control panel.

**The Unraid terminal:** You can also type commands directly in Unraid's browser interface. Look for the **>_ Terminal** button in the top-right of the Unraid header bar. Click it, and a terminal window opens right in your browser.

**Where data lives on Unraid:** Unraid stores container configuration files and data at `/mnt/user/appdata/`. Think of this as the "Documents" folder for all your containers. When you set up a container on Unraid, its settings live in a subfolder here.

---

## Part 2: Verify Docker Is Running on Unraid

Unraid has Docker built in — you don't install it separately. Let's make sure it's enabled.

1. In the Unraid web interface, click **Settings** in the top menu
2. Find and click **Docker** in the settings list
3. Look for **"Docker service"** — it should say **Enabled**

If it says Disabled, toggle it to Enabled and click Apply.

✅ Verify: Settings → Docker → Docker service shows **Enabled**

You can also check via SSH:
```bash
ssh root@192.168.1.222
docker --version
```

Expected output:
```
Docker version 27.3.1, build ce12230
```

---

## Part 3: Install the NVIDIA Driver Plugin (for RTX 4070)

On Unraid, the recommended way to enable NVIDIA GPU support for containers is through the **Community Applications** plugin — Unraid's own app store.

**Step 1: Install Community Applications** (if not already installed)
1. In Unraid, go to the **Apps** tab
2. If you don't see it, go to **Plugins** → search for "Community Applications" → install it

**Step 2: Install the NVIDIA Driver Plugin**
1. Click the **Apps** tab
2. In the search box, type `Nvidia Driver`
3. Find **"Nvidia-Driver"** by ich777
4. Click **Install**
5. Accept the default settings and click **Install** again
6. Wait for it to finish — it will download and install the driver

**Step 3: Verify the NVIDIA driver works**

After installation, open the Unraid terminal (or SSH in) and run:
```bash
nvidia-smi
```

Expected output (your exact numbers will differ):
```
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 550.90.07    Driver Version: 550.90.07    CUDA Version: 12.4               |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
|   0  NVIDIA GeForce RTX 4070        Off |   00000000:01:00.0 Off |                  N/A |
+-----------------------------------------------------------------------------------------+
```

You should see your RTX 4070 listed.

✅ Verify: `nvidia-smi` shows your GPU with a driver version.

⚠️ **If nvidia-smi hangs or fails:** Try rebooting Unraid (`Main` → Scroll down → `Reboot`) and try again.

---

## Part 4: Copy the Node B Project Files

From your laptop:
```bash
scp -r fresh-rebuild-2026/node-b/ root@192.168.1.222:/mnt/user/appdata/fresh-rebuild/
```

This copies your Node B project files into Unraid's appdata folder — right where they belong.

---

## Part 5: Create Your .env File

SSH into Node B:
```bash
ssh root@192.168.1.222
cd /mnt/user/appdata/fresh-rebuild/
cp .env.example .env
nano .env
```

Here's what each setting in Node B's `.env` means:

| Setting | Example Value | What It Means |
|---------|---------------|---------------|
| `TZ` | `America/New_York` | Your local timezone |
| `PUID` | `99` | User ID for Unraid — **always 99 on Unraid, do not change** |
| `PGID` | `100` | Group ID for Unraid — **always 100 on Unraid, do not change** |
| `NODE_B_IP` | `192.168.1.222` | Node B's own IP address |
| `APPDATA_PATH` | `/mnt/user/appdata` | Where container data is stored |
| `HA_TOKEN` | `eyJ0eX...` | Your Home Assistant API key (see below) |
| `WATCHTOWER_DISCORD_URL` | `https://discord.com/api/webhooks/...` | Optional — Discord notification webhook |
| `N8N_USER` | `admin` | The username for the n8n automation web interface |
| `N8N_PASSWORD` | `YourStrongPassword123!` | The password for n8n — **choose a real password!** |

**Getting your Home Assistant token (`HA_TOKEN`):**
1. Open Home Assistant at `http://192.168.1.149:8123`
2. Click your username/profile picture in the bottom-left
3. Scroll down to **Long-Lived Access Tokens**
4. Click **Create Token**
5. Give it a name like "Node B Integration"
6. Copy the long string of characters it shows you — paste it as your `HA_TOKEN` value

⚠️ **The token is only shown once.** Copy it immediately and paste it into your `.env` file before clicking OK.

Save and exit nano: `Ctrl + O`, `Enter`, `Ctrl + X`.

---

## Part 6: Deploy the Infrastructure Stack (Stack 1)

Time to launch. This command starts all the core infrastructure services:
```bash
cd /mnt/user/appdata/fresh-rebuild/
docker compose -f stacks/01-infra.yml --env-file .env up -d
```

`--env-file .env` explicitly tells Docker which settings file to use. This starts:

| Container | What It Does | Web Address |
|-----------|-------------|-------------|
| **Portainer CE** | Visual manager for all containers | `http://192.168.1.222:9000` |
| **Homepage** | Your home lab dashboard | `http://192.168.1.222:8010` |
| **Uptime Kuma** | Service uptime monitor | `http://192.168.1.222:3010` |
| **Dozzle** | Container log viewer | `http://192.168.1.222:8888` |
| **Watchtower** | Auto-updater (runs silently) | — |

**What just happened?** Docker read `stacks/01-infra.yml`, pulled any missing images from the internet, created containers with your `.env` settings, and started them in the background. Each container has a name, a set of ports it listens on, and a folder mapped to `/mnt/user/appdata` so its data persists.

---

## Part 7: Deploy the AI Stack (Stack 2)
```bash
docker compose -f stacks/02-ai.yml --env-file .env up -d
```

This starts:

| Container | What It Does | Web Address |
|-----------|-------------|-------------|
| **Ollama (CUDA)** | Fast AI using your NVIDIA GPU | `http://192.168.1.222:11434` |
| **n8n** | Visual workflow automation | `http://192.168.1.222:5678` |

---

## Part 8: Pull AI Models on Node B
```bash
docker exec ollama ollama pull llama3.1:8b
docker exec ollama ollama pull qwen2.5:7b
```

The first command downloads the same llama3.1:8b model as Node A (~4.7 GB). The second downloads qwen2.5:7b — a strong multilingual model (~4.4 GB). Both will take several minutes.

💡 **Tip:** You can run the second pull while the first is still running — open a second terminal, SSH in, and run the second command. Both will download in parallel.

---

## Part 9: Verify Node B Services Are Running

Check that all containers are up:
```bash
docker ps
```

Expected output (abbreviated):
```
CONTAINER ID   IMAGE             COMMAND        STATUS          PORTS                     NAMES
a1b2c3d4e5f6   portainer/ce      ...            Up 3 minutes    0.0.0.0:9000->9000/tcp    portainer
b2c3d4e5f6a7   ollama/ollama     ...            Up 3 minutes    0.0.0.0:11434->11434/tcp  ollama
c3d4e5f6a7b8   louislam/uptime   ...            Up 3 minutes    0.0.0.0:3010->3001/tcp    uptime-kuma
...
```

Every container should show **"Up X minutes"** — not "Restarting" or "Exited."

Test Ollama is responding:
```bash
curl http://192.168.1.222:11434/api/version
```

Expected output:
```json
{"version":"0.5.1"}
```

**Open these in your browser to verify each service:**

| URL | What You Should See |
|-----|---------------------|
| `http://192.168.1.222:9000` | Portainer — create admin account (first visit only) |
| `http://192.168.1.222:8010` | Homepage dashboard |
| `http://192.168.1.222:3010` | Uptime Kuma — set up monitors |
| `http://192.168.1.222:8888` | Dozzle — list of running containers |
| `http://192.168.1.222:5678` | n8n — automation canvas |

💡 **Portainer first login:** The very first time you visit Portainer, it asks you to create an administrator account. Choose a username and a strong password — you'll use this to log in every time.

✅ Verify: All five URLs load a working web page.

---

## Troubleshooting Chapter 2

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| `nvidia-smi: command not found` | NVIDIA plugin not installed | Go to Apps → search "Nvidia Driver" → install |
| Ollama container keeps restarting | GPU not accessible to Docker | Check `docker logs ollama` — look for "no NVIDIA GPU detected" |
| n8n won't start | `N8N_PASSWORD` is empty or missing | Edit `.env`, set `N8N_PASSWORD`, re-run `docker compose up -d` |
| Homepage shows blank/broken | Config folder doesn't exist | Check Portainer started first; run `docker logs homepage` |
| `docker: command not found` | Docker service disabled | Settings → Docker → Enable |
| "Restarting" status on containers | Missing env variable | Run `docker logs <container_name>` — look for the error |

---

# Chapter 3: Node C — The Chat Interface (Intel Arc A770)

**What Node C does:** Node C runs **Open WebUI** — the beautiful web interface you'll open in your browser to chat with your AI. It acts as a friendly front door that connects to the AI brains on Node A and Node B. The Intel Arc A770 GPU on this machine is not used for AI inference in Phase 1 — that's planned for a future phase.

💡 **Before starting:** Make sure Chapters 1 and 2 are complete and verified. Node C needs to reach Node A and Node B over the network.

---

## Part 1: Install Docker on Node C (Fedora 44)

Node C runs the same operating system as Node A (Fedora 44), so the Docker installation steps are identical. SSH in and run these commands:
```bash
ssh youruser@192.168.1.6
```

```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

Verify:
```bash
docker --version
docker compose version
```

✅ Verify: Both commands return a version number.

---

## Part 2: Intel GPU Drivers — A Note for the Future

Node C has an Intel Arc A770 graphics card. In this Phase 1 setup, we're only running the chat interface on Node C — the GPU isn't doing any AI work yet.

When you're ready to use it for AI inference in a future phase, you'll need Intel's **oneAPI** stack and the `intel-gpu-tools` package. For now, no GPU setup is needed.

```bash
# Just confirming the GPU exists (optional curiosity check):
lspci | grep -i VGA
```

Expected output (something like):
```
01:00.0 VGA compatible controller: Intel Corporation Arc A770 Graphics
```

---

## Part 3: Copy the Node C Project Files

From your laptop:
```bash
scp -r fresh-rebuild-2026/node-c/ youruser@192.168.1.6:~/homelab-node-c/
```

---

## Part 4: Create Your .env File

```bash
ssh youruser@192.168.1.6
cd ~/homelab-node-c
cp .env.example .env
nano .env
```

Here's what each setting means:

| Setting | Example Value | What It Means |
|---------|---------------|---------------|
| `TZ` | `America/New_York` | Your timezone |
| `APPDATA_PATH` | `/opt/open-webui` | Where Open WebUI stores its database and settings |
| `WEBUI_NAME` | `Home Lab AI` | The name shown in your browser tab — put whatever you like! |
| `WEBUI_SECRET_KEY` | *(generate below)* | A random string that secures your login sessions |
| `OLLAMA_BASE_URLS` | *(see below)* | The addresses of both Ollama backends |

**Generating your WEBUI_SECRET_KEY:**

This is a random string of characters that keeps your login sessions secure — like a secret salt for your passwords. Generate one now:
```bash
openssl rand -hex 32
```

Expected output (yours will be different):
```
a3f8d2c19b4e7f6a2d5c8b1e4f7a0d3c6b9e2f5a8d1c4b7e0f3a6d9c2b5e8f1
```

Copy that entire string and paste it as the value of `WEBUI_SECRET_KEY` in your `.env` file.

⚠️ **Do not share this key.** It's like a master password for your session security.

**Setting OLLAMA_BASE_URLS:**

This is where you tell Open WebUI where to find the AI models. We're pointing it at **both** Node A and Node B — separated by a semicolon:
```
OLLAMA_BASE_URLS=http://192.168.1.9:11435;http://192.168.1.222:11434
```

The semicolon means "check both of these." Open WebUI will list models from both servers in the dropdown.

| Address | Which Node | Port |
|---------|------------|------|
| `http://192.168.1.9:11435` | Node A (AMD ROCm) | 11435 |
| `http://192.168.1.222:11434` | Node B (NVIDIA CUDA) | 11434 |

Save and exit: `Ctrl + O`, `Enter`, `Ctrl + X`.

---

## Part 5: Start Open WebUI
```bash
docker compose -f compose.yml --env-file .env up -d
```

Docker will pull the Open WebUI image (about 1–2 GB) and start the container. The first startup can take 2–3 minutes as it initializes its database.

**What just happened?** Open WebUI is now running on Node C, listening on port 3000. When you visit it in a browser, it will connect to both Ollama instances using the URLs you provided.

✅ Verify the container is running:
```bash
docker ps
```

Look for `open-webui` in the list with status **"Up X minutes"**.

---

## Part 6: First Login to Open WebUI

Open your browser and go to:
```
http://192.168.1.6:3000
```

**First-time setup:**
1. You'll see a "Get Started" or sign-up screen
2. Enter an email address (doesn't have to be real — it's just your username on this local system), a display name, and a password
3. Click **Create Account**

This first account is automatically made the **administrator**. Keep this password safe.

**Verify Ollama connections:**
1. Click your profile picture → **Settings**
2. Go to **Connections**
3. You should see two Ollama entries — both should show a **green dot** indicating they're connected
4. If one shows red, double-check that the IP address and port match what's in your `.env` file

✅ Verify: Both Ollama connections show as green/connected.

---

## Part 7: Test Your First AI Chat

1. Click the **pencil/new chat** button (usually top-left or top-center)
2. In the model dropdown (usually labeled "Select a model"), you'll see a list of all available models from Node A and Node B
3. Select `llama3.1:8b`
4. In the chat input box, type:
   ```
   Hello! Can you tell me a fun fact about space?
   ```
5. Press Enter and wait for the response

The response should appear within 5–30 seconds depending on how busy the GPU is. The first response after a model is loaded can be slower — subsequent ones are faster.

💡 **Tip:** Look at the bottom of the response — Open WebUI often shows which model and backend served the request.

✅ Verify: You get a coherent AI response to your message.

---

## Troubleshooting Chapter 3

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| "Cannot connect to Ollama" error | Wrong IP or port in `OLLAMA_BASE_URLS` | Edit `.env`, verify the IPs and ports, re-run `docker compose up -d` |
| No models appear in dropdown | Models not pulled on Node A/B yet | Complete Chapter 1 Part 6 and Chapter 2 Part 8 |
| Login page won't load | Container not running | Check `docker ps`; if missing run `docker compose -f compose.yml up -d` |
| "WEBUI_SECRET_KEY" errors in logs | Placeholder value left unchanged | Run `openssl rand -hex 32`, paste result in `.env`, restart: `docker compose restart` |
| Very slow responses | Normal on first request; model loading | Wait 30–60 seconds — subsequent responses are much faster |
| Green dot but no models | Ollama running but no models pulled | SSH into Node A/B and run `ollama pull llama3.1:8b` |

---

# Chapter 4: Node D — Home Assistant Talks to AI

**What Node D does:** Node D runs **Home Assistant** — your smart home controller. It can control lights, thermostats, door sensors, and hundreds of other devices. In this chapter, we connect Home Assistant directly to Ollama on Node B, so your smart home can use AI for voice assistants and intelligent automations.

💡 **Before starting:** Make sure Chapter 2 is complete — specifically that Ollama is running on Node B and models have been pulled.

---

## Part 1: No Docker Setup Needed — HA Config Only

Node D runs **Home Assistant OS (HAOS)** — a special, locked-down operating system designed specifically for Home Assistant. We don't deploy containers or run commands on this node. Everything is done through Home Assistant's own web interface.

Think of it like configuring a smart TV through its menu — you don't need to open a terminal.

---

## Part 2: Open Home Assistant

In your browser, navigate to:
```
http://192.168.1.149:8123
```

Log in with your Home Assistant username and password.

You should see the Home Assistant Overview page — your smart home dashboard.

✅ Verify: Home Assistant loads and you can see your dashboard.

---

## Part 3: Install the Ollama Integration

An **integration** in Home Assistant is an official add-on that connects HA to a specific service or device. We're going to install the Ollama integration so HA can send questions to your AI.

Follow these steps in your browser:

1. Click **Settings** (gear icon in the left sidebar)
2. Click **Devices & Services**
3. Click the blue **+ Add Integration** button (bottom-right corner)
4. In the search box, type `Ollama`
5. Click on **Ollama** when it appears in the list
6. You'll see a configuration screen — fill in the **URL** field with:
   ```
   http://192.168.1.222:11434
   ```
   This is the address of Ollama on Node B.
7. Click **Submit**
8. A dropdown will appear asking you to choose a model — select `llama3.1:8b` (it should be in the list because you pulled it in Chapter 2)
9. Click **Finish**

**What just happened?** Home Assistant now has a direct connection to the Ollama AI running on Node B. It can send questions and receive answers — this is the foundation for AI-powered automations and voice responses.

✅ Verify: You see "Ollama" listed under **Settings → Devices & Services** with no error icon.

---

## Part 4: Set Ollama as Your Voice Assistant Brain

Now let's make Ollama the conversation engine for your voice assistant:

1. Go to **Settings → Voice Assistants**
2. Click on your existing voice assistant to edit it (or click **+ Add Assistant** to create one)
3. Find the **Conversation agent** dropdown
4. Change it from the default to **"Ollama"** (or the specific Ollama model entry)
5. Click **Update**

Now when you use the voice assistant — whether through the HA app, a tablet, or a smart speaker — it uses your local AI instead of a cloud service.

---

## Part 5: Verify the Connection

Let's test it properly using Home Assistant's Developer Tools — a built-in toolkit for testing things without affecting your real home setup.

**Test 1: Check the integration is live**
1. Go to **Settings → Devices & Services → Ollama**
2. Look for the integration card — it should show **Connected** with no warnings

**Test 2: Send a test message via Developer Tools**
1. In the left sidebar, click **Developer Tools** (the `</>` icon — may be at the bottom)
2. Click the **Actions** tab (or "Services" in older HA versions)
3. In the "Action" dropdown, type and select: `conversation.process`
4. In the Service Data field, enter:
   ```yaml
   text: "What is the capital of France?"
   agent_id: conversation.ollama
   ```
5. Click **Perform Action** (or **Call Service**)
6. Scroll down to see the response — it should appear as an AI-generated reply

Expected response area shows something like:
```
The capital of France is Paris.
```

✅ Verify: The conversation.process action returns an AI-generated response.

---

## Part 6: (Optional) Create an AI Morning Briefing Automation

Want Home Assistant to give you an AI-generated good morning message? Here's how to create a simple test automation:

1. Go to **Settings → Automations & Scenes**
2. Click **+ Create Automation**
3. Click **Create new automation**
4. Give it a name like "Good Morning AI Briefing"

**Trigger:**
- Click **Add Trigger** → **Time**
- Set the time to something like `7:00 AM`

**Action:**
- Click **Add Action** → **Call Service**
- Service: `conversation.process`
- Data:
  ```yaml
  text: "Good morning! Give me a short, cheerful morning message and one interesting fact for today."
  agent_id: conversation.ollama
  ```
- Add another action: **Notifications: Send a notification**
- Connect the response from the previous step to the notification message

5. Click **Save**

💡 **Tip:** HA automations are very flexible. Once you're comfortable, you can trigger AI responses based on motion sensors, weather, or any home event.

---

## Troubleshooting Chapter 4

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| "Ollama" doesn't appear in integration search | HA version might be old | Update HA via **Settings → System → Updates** |
| "Connection failed" during integration setup | Node B's Ollama not running | Test from laptop: `curl http://192.168.1.222:11434/api/version` |
| No models appear in model dropdown | Models not pulled on Node B | SSH into Node B: `docker exec ollama ollama pull llama3.1:8b` |
| Response is very slow (>60 seconds) | Normal for first request after a long idle period | The model was unloaded from memory; wait — next request is much faster |
| `conversation.process` returns an error | Wrong `agent_id` | Check the exact integration ID in **Settings → Devices & Services → Ollama** |
| Voice assistant not using Ollama | Voice assistant still points to old agent | Re-check **Settings → Voice Assistants** and re-save |

---

# Chapter 5: The Final Check — Is Everything Working Together?

Congratulations on making it here! 🎉 You've set up four nodes, installed drivers, configured containers, and connected everything together. Now let's do one final verification pass to make sure the whole system works as a unit.

---

## The Master Checklist

Work through this list top to bottom. Every item should have a ✅ before you consider yourself done.

**Node A (192.168.1.9):**
- ✅ `ssh youruser@192.168.1.9` connects without errors
- ✅ `rocm-smi` shows the RX 7900 XT
- ✅ `docker ps` shows `ollama-rocm` container with status **Up**
- ✅ `curl http://192.168.1.9:11435/api/version` returns a version number
- ✅ At least one model is pulled (`docker exec ollama-rocm ollama list` shows `llama3.1:8b`)

**Node B (192.168.1.222):**
- ✅ `nvidia-smi` shows the RTX 4070
- ✅ `docker ps` shows **all** infrastructure and AI containers with status **Up**
- ✅ `curl http://192.168.1.222:11434/api/version` returns a version number
- ✅ `http://192.168.1.222:9000` loads Portainer
- ✅ `http://192.168.1.222:8010` loads the Homepage dashboard
- ✅ `http://192.168.1.222:3010` loads Uptime Kuma
- ✅ `http://192.168.1.222:5678` loads n8n

**Node C (192.168.1.6):**
- ✅ `docker ps` shows `open-webui` container with status **Up**
- ✅ `http://192.168.1.6:3000` loads the Open WebUI login page
- ✅ Logged into Open WebUI — both Ollama connections show green
- ✅ Models appear in the model dropdown

**Node D (192.168.1.149):**
- ✅ Home Assistant loads at `http://192.168.1.149:8123`
- ✅ Ollama integration shows **Connected** in Settings → Devices & Services
- ✅ `conversation.process` action returns an AI response in Developer Tools

---

## The End-to-End Test

This is the ultimate test: send a message through Open WebUI and confirm it actually reaches the AI GPU on one of your nodes.

1. Open `http://192.168.1.6:3000` in your browser
2. Log in to Open WebUI
3. Create a new chat
4. In the model dropdown, select a model from Node A (they're labeled with the source)
5. Type this message:
   ```
   Please tell me: what GPU are you running on, and what AI model are you?
   ```
6. Send it

A well-configured Ollama instance will respond with information about the model. Watch the bottom of the response for metadata showing which backend served the request.

💡 **How to tell which backend answered:** Open WebUI displays the model name and sometimes the source in the response footer. You can also check Node A's logs while chatting:
```bash
ssh youruser@192.168.1.9
docker logs ollama-rocm -f
```
You'll see incoming requests logged in real time as you chat.

---

## What "Healthy" Looks Like

When everything is working correctly, here's what you'll see across your services:

| Service | Healthy Sign |
|---------|-------------|
| **Portainer** | Shows all containers as green/running |
| **Uptime Kuma** | All monitored services show green "Up" badges |
| **Dozzle** | Lists all containers; clicking one shows live logs |
| **Open WebUI** | Models load, AI responds in under 30 seconds |
| **Home Assistant** | Ollama integration shows Connected |
| **n8n** | Canvas loads; can create and run workflows |

---

## Checking Logs When Something Seems Off

The most useful debugging command is:
```bash
docker logs <container-name>
```

For example:
```bash
docker logs ollama-rocm
docker logs open-webui
docker logs ollama
docker logs n8n
```

Add `-f` to follow logs in real time:
```bash
docker logs ollama-rocm -f
```

Press `Ctrl + C` to stop watching.

---

## Port Reference — All Services at a Glance

| Node | Service | URL | Port |
|------|---------|-----|------|
| Node A | Ollama (ROCm/AMD) | `http://192.168.1.9:11435` | 11435 |
| Node B | Ollama (CUDA/NVIDIA) | `http://192.168.1.222:11434` | 11434 |
| Node B | Portainer | `http://192.168.1.222:9000` | 9000 |
| Node B | Homepage | `http://192.168.1.222:8010` | 8010 |
| Node B | Uptime Kuma | `http://192.168.1.222:3010` | 3010 |
| Node B | Dozzle | `http://192.168.1.222:8888` | 8888 |
| Node B | n8n | `http://192.168.1.222:5678` | 5678 |
| Node C | Open WebUI | `http://192.168.1.6:3000` | 3000 |
| Node D | Home Assistant | `http://192.168.1.149:8123` | 8123 |

---

## Congratulations — You Built a Home AI Lab! 🏆

Take a moment to appreciate what you've just done. You have:

- 🤖 **A private AI that runs on your own hardware** — no cloud subscription, no data sent outside your house
- 🖥️ **Two GPUs doing AI inference** — Node A's AMD RX 7900 XT and Node B's NVIDIA RTX 4070 working in parallel
- 💬 **A beautiful chat interface** on Node C that connects to both AI backends automatically
- 🏠 **A smart home that can think** — Home Assistant on Node D now has an AI conversation engine
- 📊 **A full monitoring and management suite** — Portainer, Uptime Kuma, Dozzle, and Homepage so you always know what's happening
- 🔄 **Automatic updates** — Watchtower keeps your containers fresh without any manual work

This is a real, production-grade home lab setup. Most people never get this far.

---

## What's Next

Now that Phase 1 is solid, here are some things to explore:

- **Configure Homepage** — add widgets for each service, weather, and system stats
- **Set up Uptime Kuma monitors** — add URLs for each service so you get alerted if something goes down
- **Explore n8n automations** — connect your AI to RSS feeds, email, home sensors, and more
- **Try different AI models** — pull `mistral:7b`, `codellama:13b`, or `phi3:mini` and compare them
- **Enable the Intel Arc A770 on Node C** — Phase 2 will add inference capability here

For configuring each individual service beyond the basics, refer to the **Apps & Services Guide** in this docs folder.

---

> 💡 **Remember:** If something breaks, don't panic. Every problem has a fix, and the troubleshooting sections throughout this guide cover the most common ones. The home lab community is also incredibly helpful — forums like r/homelab and the Home Assistant community are full of people who've solved the same problems you'll encounter.

> You're no longer just a user of technology — you're running your own piece of the AI revolution, right in your home. That's genuinely impressive. 🚀
