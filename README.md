# Grand Unified AI Homelab — Portainer-First Deployment

A multi-node homelab with unified LLM access, vision AI, KVM automation,
and a web-based control panel. Portainer is installed on every node first
to give you full visibility and control before deploying application stacks.

## Quick Start

```bash
# 1 — Set your node IPs and SSH users
cp config/node-inventory.env.example config/node-inventory.env
nano config/node-inventory.env

# 2 — Audit SSH connectivity and hardware on all nodes
./scripts/ssh-auditor.sh
#     ↳ fixes SSH issues, checks firewalls, inventories GPUs/RAM/containers
#     ↳ add --fix-firewall to auto-open ports
#     ↳ add --install-keys to push SSH keys (prompts passwords once)

# 3 — Install Portainer on every reachable node
./scripts/portainer-install.sh
#     ↳ installs Docker if missing, opens firewall ports, waits for healthy

# 4 — Deploy application stacks
./scripts/deploy-all.sh
```

Full guide: **[PORTAINER_GUIDE.md](PORTAINER_GUIDE.md)**

---

## Node Architecture

| Node | Role                  | Hardware          | Key Services           |
|------|-----------------------|-------------------|------------------------|
| A    | Brain — heavy LLM     | AMD RX 7900 XT    | vLLM :8000, Dashboard :3099 |
| B    | Gateway — Unraid      | RTX 4070 12GB     | LiteLLM :4000, Portainer :9000 |
| C    | Vision AI             | Intel Arc A770    | Ollama :11434, Open WebUI :3000 |
| D    | Home Automation       | —                 | Home Assistant :8123   |
| E    | Surveillance          | —                 | Blue Iris :81, Sentinel :3005 |

---

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `scripts/ssh-auditor.sh` | SSH pre-auditor: tests connectivity, audits hardware, maps firewall, discovers Tailscale |
| `scripts/portainer-install.sh` | Installs Portainer CE on all reachable nodes |
| `scripts/deploy-all.sh` | Deploys all application stacks (uses Portainer API when token set) |
| `scripts/preflight-check.sh` | Validates system requirements before deploy |
| `validate.sh` | 36-test configuration validation suite |

---

## Documentation

| File | Contents |
|------|----------|
| [PORTAINER_GUIDE.md](PORTAINER_GUIDE.md) | **Start here** — Portainer install, SSH troubleshooting, Tailscale, API |
| [GUIDEBOOK.md](GUIDEBOOK.md) | Full architecture and per-node deployment details |
| [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) | Step-by-step deployment reference |
| [QUICK_REFERENCE.md](QUICK_REFERENCE.md) | Copy-paste commands for common operations |

---

## Connectivity Options

The SSH auditor tries three methods to reach each node, in order:

1. **LAN SSH** — direct connection via local network (fastest)
2. **Tailscale** — encrypted mesh tunnel (fallback for remote nodes or firewall issues)
3. **Key push** — `ssh-copy-id` with `--install-keys` flag (one-time setup)

Set Tailscale IPs in `config/node-inventory.env` as `NODE_X_TS_IP=100.x.x.x`
if LAN SSH is unreliable.

---

## Inventory Template

```bash
# config/node-inventory.env
NODE_A_IP=192.168.1.9          # your actual IPs
NODE_B_IP=192.168.1.222
NODE_C_IP=192.168.1.6
NODE_A_SSH_USER=root
NODE_B_SSH_USER=root
NODE_A_TS_IP=                  # Tailscale 100.x.x.x (optional)
PORTAINER_TOKEN=               # ptr_... (from Portainer → My Account → Access Tokens)
```

---

## References

- Portainer CE docs: https://docs.portainer.io/
- Open WebUI: https://docs.openwebui.com/
- LiteLLM proxy: https://docs.litellm.ai/docs/proxy/docker_quick_start
- Tailscale: https://tailscale.com/kb/1017/install
