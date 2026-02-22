# The Plain English Setup Guide
## Grand Unified AI Homelab — Anyone Can Do This

> **Who this guide is for:**
> Anyone. You do not need to be a computer expert.
> If you can follow a recipe, you can follow this guide.
> Every step is written out in full. Nothing is skipped.

---

## Before You Start — Read This First

### What Is This Thing?

Think of your homelab like a small private office building with several rooms.
Each room (called a **node**) has a computer in it doing a specific job.

- **Node A** — The brain room. Runs the heavy AI thinking work.
- **Node B** — The front desk. Routes traffic and runs your main server.
- **Node C** — The vision room. Handles image and camera AI.
- **Node D** — The home control room. Runs Home Assistant.
- **Node E** — The security room. Watches cameras.

**Portainer** is the building manager's office — one website where you
can see and control everything happening in every room, all at once.

**Docker** is the system that keeps programs neatly boxed up so they
don't mess with each other. Think of it like individual shipping
containers on a cargo ship — each program lives in its own container.

**Docker Swarm** is when all your computers agree to work together as
a team, sharing the workload.

---

### Words You Will See — What They Mean

| Word | What It Means In Plain English |
|------|-------------------------------|
| **Node** | One of your computers |
| **Node A, B, C...** | Just names to tell your computers apart |
| **IP Address** | Your computer's street address on your home network (looks like 192.168.1.222) |
| **SSH** | A secure way to type commands on a remote computer from across the room — or the world |
| **Terminal / Command Line** | A text box where you type instructions to your computer |
| **Docker** | Software that runs programs in tidy isolated boxes |
| **Container** | One program living in its tidy Docker box |
| **Portainer** | A website you open in your browser to manage all containers |
| **Stack** | A group of containers that work together as one service |
| **Firewall** | Your computer's bouncer — it decides what traffic gets in and out |
| **Port** | A numbered door on your computer that programs use to communicate |
| **Script** | A text file full of instructions your computer runs automatically |
| **CE** | Community Edition — the free version of Portainer |
| **BE** | Business Edition — the paid version of Portainer (you have this) |
| **Swarm** | Multiple computers working together as a team |

---

### What You Will Need

Before you start, make sure you have:

- [ ] All your computers (nodes) plugged in and turned on
- [ ] All computers connected to your home router with an Ethernet cable
  (Wi-Fi works too, but Ethernet is more reliable)
- [ ] A laptop or desktop computer to control everything from
  (this is the computer you will type commands on)
- [ ] Your Portainer Business Edition license key
  (it looks like a long string of letters and numbers)
- [ ] About 1-2 hours of uninterrupted time the first time through
- [ ] A piece of paper and pen to write down IP addresses

---

### Finding Your Computer's IP Address

An IP address is like a house number for your computer on your home network.
You need to know the IP address of each node before you start.

**On Linux (most of your nodes):**
1. Open a terminal on that computer
2. Type exactly: `hostname -I`
3. Press Enter
4. You will see something like: `192.168.1.9 172.17.0.1`
5. Write down the first number (ignore anything after the space)

**On Windows:**
1. Press the Windows key + R at the same time
2. Type `cmd` and press Enter
3. Type `ipconfig` and press Enter
4. Look for "IPv4 Address" — write that number down

**From your router (easiest method):**
1. Open a web browser
2. Go to `192.168.1.1` (or `192.168.0.1` — try both)
3. Log in to your router (password is usually on the router's label)
4. Look for "Connected Devices" or "DHCP Clients"
5. You will see a list of all computers and their IP addresses

---

## THE MASTER CHECKLIST

Work through this from top to bottom. Do not skip steps.

```
PHASE 1 — PREPARATION
  [ ] Step 1:  Find the IP address of every node
  [ ] Step 2:  Open a terminal on your control computer
  [ ] Step 3:  Navigate to the project folder
  [ ] Step 4:  Create your settings file

PHASE 2 — CONNECTION CHECK
  [ ] Step 5:  Run the Connection Checker (SSH Auditor)
  [ ] Step 6:  Fix any connection problems it found

PHASE 3 — INSTALL PORTAINER
  [ ] Step 7:  Install Portainer on all nodes
  [ ] Step 8:  Open Portainer in your browser
  [ ] Step 9:  Create your admin account
  [ ] Step 10: Enter your Business Edition license key

PHASE 4 — CONNECT ALL NODES TO ONE DASHBOARD
  [ ] Step 11: Set up Docker Swarm (team mode)
  [ ] Step 12: Add all nodes to your Portainer dashboard

PHASE 5 — LAUNCH YOUR SERVICES
  [ ] Step 13: Deploy LiteLLM (the AI gateway)
  [ ] Step 14: Deploy Ollama (the vision AI)
  [ ] Step 15: Deploy OpenClaw (the AI agent)
  [ ] Step 16: Verify everything is working
```

---

---

# PHASE 1 — PREPARATION

---

## Step 1: Find the IP Address of Every Node

Using the method above (or your router's device list), write down the
IP address for each computer. Fill this in with a pen:

```
Node A (Brain — AMD GPU)   IP: 192.168.1. _______
Node B (Unraid Server)     IP: 192.168.1. _______
Node C (Intel Arc)         IP: 192.168.1. _______
Node D (Home Assistant)    IP: 192.168.1. _______
Node E (Sentinel)          IP: 192.168.1. _______
```

**What if I don't have all of these computers?**
That is fine. Just leave any computers you don't have blank.
The setup will automatically skip them.

---

## Step 2: Open a Terminal on Your Control Computer

Your control computer is the laptop or desktop you are sitting at right now.

**On Linux:**
- Look for an application called "Terminal" or "Konsole"
- Or press Ctrl + Alt + T at the same time

**On Mac:**
- Press Command + Space
- Type "Terminal" and press Enter

**On Windows:**
- Press Windows key + X
- Click "Windows Terminal" or "PowerShell"

You will see a window with a blinking cursor. This is normal.
It is waiting for you to type something.

---

## Step 3: Navigate to the Project Folder

The project folder contains all the scripts we will use.

In your terminal, type this exactly and press Enter:

```
cd /home/user/onemoreytry
```

> **What does "cd" mean?** It means "change directory" — like walking
> into a different folder. You are telling the computer to go to the
> project folder.

After pressing Enter, your terminal should show the folder name.
If it shows an error saying the folder does not exist, ask for help
before continuing.

---

## Step 4: Create Your Settings File

Think of this like filling out a form before starting a job.
You will tell the setup what IP addresses your computers have.

**Part A — Make a copy of the blank form:**

Type this and press Enter:
```
cp config/node-inventory.env.example config/node-inventory.env
```

> You just made a copy of the blank settings form.
> The original stays untouched. You will fill in the copy.

**Part B — Open the form to fill it in:**

Type this and press Enter:
```
nano config/node-inventory.env
```

A simple text editor will open. It will look a bit like Notepad.

**Part C — Find the IP address lines:**

Use the arrow keys on your keyboard to scroll down.
Look for lines that say:

```
NODE_A_IP=192.168.1.9
NODE_B_IP=192.168.1.222
NODE_C_IP=192.168.1.6
```

Change each number after the `=` sign to match what you wrote down
in Step 1.

**Example:** If Node A's IP address is `192.168.1.50`, change the line to:
```
NODE_A_IP=192.168.1.50
```

**Part D — What about lines you can skip?**

Lines that have a `#` at the start are comments (notes). You do not need
to change them. They explain what the other lines mean.

Lines for computers you do not have: leave them as they are.
The scripts will skip any computer it cannot find.

**Part E — Save and close:**

1. Press **Ctrl + X** (hold Control, tap X)
2. It will ask "Save modified buffer?" — Press **Y**
3. It will ask for the filename — just press **Enter**

You have finished filling in the settings form.

---

---

# PHASE 2 — CONNECTION CHECK

---

## Step 5: Run the Connection Checker

The Connection Checker (called the SSH Auditor) will:
- Try to connect to each of your computers
- Check what hardware each one has
- Check what software is already installed
- Make a map of how to reach each computer
- Tell you what it found

**Run it by typing this and pressing Enter:**

```
./scripts/ssh-auditor.sh
```

> **What is "SSH"?** Think of it like a secure phone call between computers.
> SSH lets your control computer whisper instructions to each node privately.

**You will see the Connection Checker running.** It will print messages
on screen as it works. This is normal. Let it finish — it takes about
1-2 minutes.

**When it is done, you will see one of these:**

✅ **Good result:**
```
  Nodes reachable via SSH: 4
  Connection map written: /tmp/homelab-connmap.env
  Next step: ./scripts/portainer-install.sh
```

⚠️ **Partial result:**
```
  Nodes reachable via SSH: 2
  Nodes unreachable: 2 (NODE_A NODE_C)
```
This means it reached some computers but not all. Go to Step 6.

---

## Step 6: Fix Connection Problems

### "My computer shows as unreachable"

**The most common reason:** SSH is not enabled on that computer.

**How to fix it — go to that computer directly:**

On Ubuntu/Debian Linux:
```
sudo systemctl enable --now ssh
```

On Fedora/RHEL Linux:
```
sudo systemctl enable --now sshd
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --reload
```

On Unraid (Node B):
1. Open the Unraid web interface in a browser
2. Go to **Settings** → **Management Access**
3. Find **SSH** and turn it to **Enabled**
4. Click **Apply**

**After fixing SSH on the problem computer, run the Connection Checker again:**
```
./scripts/ssh-auditor.sh
```

---

### "It says my firewall is blocking things"

Run this to automatically open the right doors in the firewall:
```
./scripts/ssh-auditor.sh --fix-firewall
```

This will open port 22 (SSH), port 9000 (Portainer), and port 9443
(Portainer secure) on each computer's firewall.

---

### "It says 'Permission denied'"

This means the computers do not trust each other yet. We need to give
your control computer a key to unlock each node.

Run this and follow the instructions it gives you:
```
./scripts/ssh-auditor.sh --install-keys
```

**It will ask you for a password for each computer.** Type the password
for that computer and press Enter. You will need to do this once per
computer. After that, it will work automatically forever.

---

### "I still cannot connect to one computer"

**Last resort: use Tailscale**

Tailscale is a free program that creates a secure private tunnel between
your computers, even if they are on different networks or behind firewalls.

**Install Tailscale on every computer that is having trouble:**

1. Go to that problem computer (sit in front of it)
2. Open a terminal on it
3. Type this and press Enter:
   ```
   curl -fsSL https://tailscale.com/install.sh | sh
   ```
4. Then type:
   ```
   sudo tailscale up
   ```
5. It will print a web link. Open that link in a browser and sign in
   with a free Tailscale account. Do this on every computer.

**After all computers are on Tailscale:**
1. On any computer, type: `tailscale status`
2. You will see a list of all your computers with their Tailscale IP
   addresses. These start with `100.`
3. Write them down
4. Add them to your settings file:
   ```
   nano config/node-inventory.env
   ```
   Find the Tailscale IP lines and fill them in:
   ```
   NODE_A_TS_IP=100.x.x.x
   NODE_B_TS_IP=100.x.x.x
   ```
5. Run the Connection Checker again:
   ```
   ./scripts/ssh-auditor.sh
   ```

---

---

# PHASE 3 — INSTALL PORTAINER

---

## Step 7: Install Portainer on All Nodes

Portainer is the control panel you will use to manage everything.
Think of it as the cockpit of an airplane — once it is set up,
all the controls are in one place.

**Since you have the Business Edition license, run this:**

```
./scripts/portainer-install.sh --business
```

> The `--business` part tells the installer to use the paid version,
> which lets you control all your computers from one screen.

**The installer will:**
1. Go to each node one by one
2. Install Docker if it is not already there
3. Install Portainer
4. Open the firewall ports it needs
5. Wait until Portainer is ready
6. Print the web address for you to visit

**This takes about 5-10 minutes.** You will see it working as it goes.
Let it finish without interrupting it.

**When it finishes, you will see something like:**

```
╔══════════════════════════════════════════════════════════════╗
║  Portainer is READY on NODE_B
╚══════════════════════════════════════════════════════════════╝

  Admin URL (HTTP):  http://192.168.1.222:9000
  Admin URL (HTTPS): https://192.168.1.222:9443

  IMPORTANT — First Login:
    1. Open the URL above in your browser
    2. Create an admin account (username + password)
    3. Select 'Get Started' → choose 'local' environment
```

Write down the web address it gives you. You will need it next.

---

## Step 8: Open Portainer in Your Browser

1. Open Chrome, Firefox, or Edge on your control computer
2. In the address bar at the top, type the web address from Step 7
   Example: `http://192.168.1.222:9000`
3. Press Enter
4. You should see the Portainer setup screen

**What if it says "This site can't be reached"?**
- Wait 2 more minutes. Portainer sometimes takes a moment to fully start.
- Then try again. If it still does not work, check Step 12 (Troubleshooting).

**What if your browser shows a security warning?**
This is normal for a local home network. Click **"Advanced"** (or
**"More information"**), then click **"Proceed anyway"** or
**"Accept the risk and continue"**. This is safe — it is your own
computer on your own home network.

---

## Step 9: Create Your Admin Account

You will see a form asking you to create a username and password.

1. **Username:** Type `admin` (or whatever name you prefer)
2. **Password:** Choose a password that is at least 12 characters long.
   Write it down somewhere safe. You will need this to log in later.
3. **Confirm password:** Type your password again
4. Click the **Create user** button

> **IMPORTANT:** You have 5 minutes from when Portainer first starts
> to create this account. If the page shows "timeout" or "instance expired",
> go back to your terminal and type:
> ```
> ssh root@192.168.1.222 docker restart portainer
> ```
> (Replace 192.168.1.222 with your Node B IP address)
> Then go back to Step 8.

**After creating your account, Portainer will ask you to choose
an environment.** Click **"Get Started"**. Then click on the environment
that is already listed (it will say something like "local" or show
Docker containers). Click **"Connect"**.

You are now inside Portainer. It might look complicated — that is okay.
You just need a few specific things. Follow the steps below.

---

## Step 10: Enter Your Business Edition License Key

1. Look at the left side of the screen. You will see a menu with icons.
2. Click on **Settings** (it may look like a gear icon ⚙️)
3. In the Settings menu, look for **Licenses**
4. Click **Licenses**
5. Click **Add License** (or **Add a license key**)
6. Paste or type your Portainer Business Edition license key
7. Click **Submit** or **Add**

You will see a confirmation that your license is active.

> **"Portainer is now running in Business Edition mode."**
> That is the message you want to see.

---

---

# PHASE 4 — CONNECT ALL NODES TO ONE DASHBOARD

---

## Step 11: Set Up Team Mode (Docker Swarm)

Right now, each of your computers is running Portainer separately.
This next step makes them all work together and connects them to your
main Portainer control panel on Node B.

Go back to your terminal and type this, then press Enter:

```
./scripts/swarm-init.sh
```

**This script does several things automatically:**

1. **Makes Node B the team captain** (the Swarm manager)
2. **Invites all other nodes to join the team** (as Swarm workers)
3. **Gives each node a name tag** so the system knows which computer
   has which graphics card and job
4. **Installs a tiny helper program** on every computer that lets
   your main Portainer see what is happening there

**You will see it working through each step.** It will print messages
as it goes. Some of these messages look technical — do not worry about
them as long as the script keeps running and does not say "FAILED."

**When it finishes, you will see:**

```
╔══════════════════════════════════════════════════════════════╗
║   Swarm Setup Complete                                       ║
╚══════════════════════════════════════════════════════════════╝

  Swarm Manager:
    192.168.1.222  (NODE_B)

  Portainer BE Central Admin:
    http://192.168.1.222:9000
    https://192.168.1.222:9443

  NEXT STEPS in Portainer BE UI:
    1. Log in and set admin password (first time only)
    2. Apply your license key: Settings → Licenses
    3. Add the Swarm as an environment...
```

Read those "NEXT STEPS" — you will do them in Step 12.

---

## Step 12: Connect All Nodes in the Portainer Dashboard

Now you will tell Portainer about each of your computers so you can
see and control them all from one screen.

Go back to your browser with Portainer open.

---

### Part A — Add the Swarm (your whole team of computers at once)

1. Click **Home** in the left menu
2. Click the blue button **"Add environment"**
3. You see a list of options. Click **"Docker Swarm"**
4. Click **"Agent"**
5. Fill in the form:
   - **Name:** Type `Homelab Swarm` (or any name you like)
   - **Agent URL:** Type exactly: `tasks.agent:9001`
6. Click **"Connect"**

If it connects successfully, you will see "Homelab Swarm" appear on
your Home screen with a green indicator. This means Portainer can now
see ALL of your Swarm computers at once.

---

### Part B — Add Node D (Home Assistant) as a separate environment

Node D runs Home Assistant and may not be in the Swarm. Add it separately:

1. Click **Home** in the left menu
2. Click **"Add environment"**
3. Click **"Docker Standalone"**
4. Click **"Agent"**
5. Fill in the form:
   - **Name:** Type `Node D — Home Assistant`
   - **Agent URL:** Type your Node D's IP address followed by `:9001`
     Example: `192.168.1.149:9001`
6. Click **"Connect"**

---

### Part C — Add Node E (Sentinel/NVR) as a separate environment

Repeat the same process for Node E:

1. Click **Home** → **"Add environment"**
2. Click **"Docker Standalone"** → **"Agent"**
3. Fill in:
   - **Name:** `Node E — Sentinel`
   - **Agent URL:** Your Node E IP followed by `:9001`
     Example: `192.168.1.116:9001`
4. Click **"Connect"**

---

### What your Home screen should look like now

After adding everything, your Portainer Home screen should show:

```
┌─────────────────────────────────┐
│ ● Homelab Swarm          Swarm  │  ← Your whole team
│   Nodes: 3   Stacks: 0          │
├─────────────────────────────────┤
│ ● Node D — Home Assistant       │  ← Added separately
│   Containers: 0                 │
├─────────────────────────────────┤
│ ● Node E — Sentinel             │  ← Added separately
│   Containers: 0                 │
└─────────────────────────────────┘
```

All environments should show a green dot (●) meaning they are connected
and healthy. If any show red or orange, see Step 15 (Troubleshooting).

---

---

# PHASE 5 — LAUNCH YOUR SERVICES

---

## Step 13: Generate Your Portainer API Token

Before you launch everything, you need to give the deploy scripts
permission to talk to Portainer automatically.

Think of this like making a copy of your key to give to a trusted helper.

**In Portainer:**

1. Look at the top-right corner of the screen
2. You will see your username (probably "admin")
3. Click on it
4. Click **"My Account"**
5. Scroll down to **"Access tokens"**
6. Click **"Add access token"**
7. Give it a name (type anything like `deploy-script`)
8. Click **"Add access token"**
9. **A long key will appear.** It starts with `ptr_`.
   **Copy it immediately** — you will only see it once.

**Now add it to your settings file:**

Go to your terminal and type:
```
nano config/node-inventory.env
```

Find the line that says:
```
PORTAINER_TOKEN=
```

Add your token after the `=` sign:
```
PORTAINER_TOKEN=ptr_xxxxxxxxxxxxxxxxxx
```

Press Ctrl+X, then Y, then Enter to save.

---

## Step 14: Deploy Everything

Now the exciting part. This one command starts up all your AI services:

```
./scripts/deploy-all.sh
```

**What this does:**
- Starts the AI model server on Node C (the vision AI)
- Starts the LiteLLM gateway on Node B (the traffic director)
- Starts the control dashboard on Node A
- Starts the AI agent system on Node B
- Starts the web control panel

**This can take 10-30 minutes the very first time** because it is
downloading the AI models, which are large files (several gigabytes).
You will see download progress on screen. This is completely normal.

**The script will report on each service as it starts:**

```
  ✓ Node C (Intel Arc + Ollama) ready
  ✓ Node B LiteLLM Gateway ready
  ✓ Node A Dashboard ready at http://localhost:3099
  ✓ Deploy GUI ready at http://localhost:9999
```

If anything shows ✗ (a red X), do not panic. Continue reading to see
the full report at the end. Minor warnings are normal on a first install.

---

## Step 15: Verify Everything Is Working

### Quick check — type this in your terminal:

```
./scripts/deploy-all.sh status
```

You will see a health report for all your services:

```
✓ LiteLLM Gateway    — HTTP 200  (working)
✓ Ollama (Node C)    — HTTP 200  (working)
✓ Node A Dashboard   — HTTP 200  (working)
✓ Portainer          — HTTP 200  (working)
```

**Green checkmarks (✓)** = working correctly
**Yellow warnings (!)** = working but something to note
**Red X marks (✗)** = not running, needs attention

---

### What web addresses to visit when everything is working

Write these down. These are all the websites for your homelab
(replace the IP addresses with your actual ones from Step 1):

```
Main Control Panel (Portainer):
  http://192.168.1.222:9000       ← Control everything from here

AI Chat (Open WebUI):
  http://192.168.1.6:3000         ← Chat with your AI models

AI Gateway (LiteLLM):
  http://192.168.1.222:4000       ← API for connecting AI apps

Node A Dashboard:
  http://192.168.1.9:3099         ← System status overview

Deploy Control Panel:
  http://192.168.1.222:9999       ← Manage deployments visually

AI Agent (OpenClaw):
  http://192.168.1.222:18789      ← AI task automation

Home Assistant:
  http://192.168.1.149:8123       ← Smart home control
```

---

---

# WHAT TO DO IF SOMETHING GOES WRONG

---

## "A service shows red/not working in Portainer"

**Step 1:** Click on the service name in Portainer to open it.
**Step 2:** Click on **"Logs"** — this shows what the service is printing.
**Step 3:** Look for red error messages. Read the last few lines.
**Step 4:** Most common fixes:

- **"No space left on device"** — Your hard drive is full. Delete old unused Docker images:
  In your terminal: `docker system prune -f`

- **"Port already in use"** — Another program is using that network door.
  Restart that node and try again.

- **"Cannot connect to host"** — That node is turned off or disconnected.
  Turn it on and check the network cable.

---

## "Portainer shows a node as disconnected (red dot)"

1. Go to your terminal
2. Run the connection checker: `./scripts/ssh-auditor.sh --node NODE_B`
   (replace NODE_B with whichever node is disconnected)
3. It will tell you what the problem is and how to fix it

---

## "I forgot my Portainer password"

If you forgot the admin password, you can reset it:

1. In your terminal, type:
   ```
   ssh root@192.168.1.222 docker stop portainer
   ```
2. Then type:
   ```
   ssh root@192.168.1.222 docker run --rm -v portainer_data:/data portainer/helper-reset-password
   ```
3. It will print a temporary password. Write it down.
4. Then type:
   ```
   ssh root@192.168.1.222 docker start portainer
   ```
5. Log in with username `admin` and the temporary password
6. Go to **My Account** → change your password to something you will remember

---

## "A node shows 'timeout' when I first set up Portainer"

Portainer gives you only 5 minutes to create your admin account when
it first starts. If that time ran out:

1. Go to your terminal
2. Type: `ssh root@192.168.1.222 docker restart portainer`
   (Use your actual Node B IP address)
3. Wait 30 seconds
4. Go back to your browser and refresh the page
5. You now have another 5 minutes — create your account immediately

---

## "The deploy script failed halfway through"

1. Look at the error message it printed
2. Write down which step it failed on
3. Fix the problem it described
4. Run it again — it will skip things that are already working:
   ```
   ./scripts/deploy-all.sh
   ```

---

## "I don't know what step I'm on"

Run the status check — it tells you exactly what is and is not running:

```
./scripts/portainer-install.sh --status
```

And:

```
./scripts/swarm-init.sh --status
```

These will show you the current state of everything so you know
what still needs to be done.

---

---

# THE BIG PICTURE — HOW IT ALL FITS TOGETHER

Once everything is set up and working, here is what you have:

```
Your Browser
     │
     │  You type: http://192.168.1.222:9000
     │
     ▼
┌──────────────────────────────────────┐
│  PORTAINER (your control panel)      │
│  Running on: Node B                  │
│                                      │
│  ● Homelab Swarm ──────────────────┐ │
│  ● Node D (Home Assistant)         │ │
│  ● Node E (Sentinel)               │ │
└────────────────────────────────────│─┘
                                     │
              ┌──────────────────────┘
              │  (Portainer manages all of these)
              │
     ┌────────▼────────────────────────────────┐
     │              YOUR SWARM                 │
     │                                         │
     │  ┌──────────┐  ┌──────────┐  ┌────────┐│
     │  │  NODE A  │  │  NODE B  │  │ NODE C ││
     │  │          │  │          │  │        ││
     │  │ Heavy AI │  │ Gateway  │  │ Vision ││
     │  │ RX 7900  │  │ RTX 4070 │  │ Arc    ││
     │  │          │  │          │  │ A770   ││
     │  │ vLLM     │  │ LiteLLM  │  │ Ollama ││
     │  │ :8000    │  │ :4000    │  │ :11434 ││
     │  │          │  │          │  │        ││
     │  │          │  │ OpenClaw │  │ WebUI  ││
     │  │          │  │ :18789   │  │ :3000  ││
     │  └──────────┘  └──────────┘  └────────┘│
     └─────────────────────────────────────────┘
```

Every time you want to:
- **See what is running** → Open Portainer at `http://192.168.1.222:9000`
- **Chat with AI** → Open `http://192.168.1.6:3000`
- **Add a new service** → Portainer → your environment → Stacks → Add stack
- **Restart something** → Portainer → find the container → click Restart
- **Check logs** → Portainer → find the container → click Logs

---

---

# KEEPING THINGS RUNNING

## Daily — nothing to do!

Your services are set to restart automatically if they crash.
Portainer watches everything for you.

## Weekly — Optional health check

Open Portainer and glance at the Home screen.
Green dots = everything is fine.
Any red or orange = click on it to see what happened.

## Monthly — Update to latest versions

Go to your terminal and type:
```
./scripts/portainer-install.sh --update
./scripts/deploy-all.sh
```

This pulls the latest versions of everything.

---

## Getting Help

If something is broken and you cannot fix it:

1. Run the health check and save the output:
   ```
   ./scripts/preflight-check.sh > health-report.txt 2>&1
   ```

2. Run the SSH auditor and save its report:
   ```
   ./scripts/ssh-auditor.sh --report
   cat /tmp/homelab-audit.md
   ```

3. Share the contents of those files when asking for help.
   They contain all the information needed to diagnose the problem.

---

## Quick Reference Card

Cut out and keep near your computer:

```
┌──────────────────────────────────────────────────────────┐
│              HOMELAB QUICK REFERENCE                     │
├──────────────────────────────────────────────────────────┤
│ CONTROL PANEL:  http://192.168.1.222:9000                │
│ AI CHAT:        http://192.168.1.6:3000                  │
│ HOME ASSISTANT: http://192.168.1.149:8123                │
├──────────────────────────────────────────────────────────┤
│ LOGIN:  admin / [your password]                          │
├──────────────────────────────────────────────────────────┤
│ IF SOMETHING BREAKS — open terminal, type:               │
│   ./scripts/ssh-auditor.sh          (check connections)  │
│   ./scripts/portainer-install.sh --status  (check ports) │
│   ./scripts/swarm-init.sh --status   (check swarm)       │
│   ./scripts/deploy-all.sh status     (check services)    │
├──────────────────────────────────────────────────────────┤
│ TO RESTART EVERYTHING:                                   │
│   ./scripts/deploy-all.sh                               │
└──────────────────────────────────────────────────────────┘
```

---

*You did it. Your AI homelab is running.*
*Everything from here is just maintenance and exploration.*
