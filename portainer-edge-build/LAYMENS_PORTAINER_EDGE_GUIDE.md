# Layman’s Guide: Portainer as Your Main Deployment Center (Nodes A, B, C)

This folder gives you a ready build so **Portainer Business Edition (BE)** is your single control center, and each node (A/B/C) connects using **Edge Agent**.

## What this means (plain English)

- **Node B** runs the Portainer website (your control tower).
- **Nodes A, B, and C** run lightweight Edge Agents.
- The agents call home to Portainer, so you manage all nodes from one UI.
- You deploy/update stacks from one place instead of SSHing into each box.

---

## Folder map

- `central/docker-compose.portainer-be.yml` → runs Portainer BE (main center)
- `node-a/docker-compose.edge-agent.yml` → edge agent for Node A
- `node-b/docker-compose.edge-agent.yml` → edge agent for Node B
- `node-c/docker-compose.edge-agent.yml` → edge agent for Node C
- `.env.example` → all variables you fill in
- `scripts/build-and-deploy.sh` → one-command deployment
- `scripts/check-health.sh` → health checks after install

---

## Before you start (required)

1. Docker Engine + Docker Compose plugin installed on A/B/C.
2. SSH access from your runner machine to A/B/C.
3. Portainer BE license key.
4. Open ports:
   - `9443/tcp` on Node B (Portainer HTTPS UI)
   - `8000/tcp` on Node B (Edge tunnel)
   - `9001/tcp` on each node (agent port)

---

## Step-by-step install

### 1) Go into this folder

```bash
cd portainer-edge-build
```

### 2) Create your env file

```bash
cp .env.example .env
nano .env
```

Fill these values:

- `PORTAINER_LICENSE_KEY`
- `PORTAINER_HOST_IP` (usually Node B)
- `NODE_A_EDGE_ID`, `NODE_A_EDGE_KEY`
- `NODE_B_EDGE_ID`, `NODE_B_EDGE_KEY`
- `NODE_C_EDGE_ID`, `NODE_C_EDGE_KEY`
- (optional) `NODE_A_IP`, `NODE_B_IP`, `NODE_C_IP`, `SSH_USER`

### 3) Get Edge ID/Key values from Portainer

You do this in Portainer UI:

1. Open `https://<NODE_B_IP>:9443`
2. Go to **Environments → Add environment → Docker Standalone → Edge Agent**
3. Create one endpoint each for `node-a`, `node-b`, `node-c`
4. Copy each generated **Edge ID** and **Edge Key** into `.env`

> If this is your first pass, deploy Portainer first, then come back and add IDs/keys.

### 4) Deploy everything

```bash
./scripts/build-and-deploy.sh
```

This will:
- Deploy Portainer BE to Node B
- Deploy Edge Agent to Node A
- Deploy Edge Agent to Node B
- Deploy Edge Agent to Node C

### 5) Validate health

```bash
./scripts/check-health.sh
```

You should see `[OK]` lines for UI and all three edge agents.

---

## Daily use (simple workflow)

1. Open Portainer UI: `https://<NODE_B_IP>:9443`
2. Confirm all endpoints are **up**.
3. Use **Stacks** to deploy/update apps.
4. Use **Containers** tab per node for logs and restarts.

---

## Troubleshooting quick hits

- **Agent shows down:**
  - Verify `EDGE_ID` and `EDGE_KEY` in `.env`
  - Verify Node B port `8000` reachable from that node
  - Restart agent: `docker restart portainer-edge-agent`

- **Cannot open Portainer UI:**
  - Check Node B firewall allows `9443`
  - Check container running: `docker ps | grep portainer-be`

- **Compose command missing:**
  - Install Docker Compose plugin (`docker compose version` should work)

---

## Safety notes

- Keep `.env` private; it contains secrets.
- Prefer HTTPS (`9443`) over HTTP (`9000`).
- Rotate Edge keys if shared accidentally.
