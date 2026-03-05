# Security guidance (must-read)

## Hardened baseline profile (homelab)

This baseline reduces blast radius while preserving automation:

1. **No broad Docker socket exposure to AI-facing services.**
   - Route container lifecycle actions through **one control plane** (Portainer API).
   - Keep `/var/run/docker.sock` only where the platform itself requires it (Portainer/agent, Watchtower).
2. **Default to bridge networking.**
   - Use `network_mode: host` only for services that strictly require it (for example Tailscale).
3. **Scope published ports to required interfaces.**
   - Default bind is loopback (`127.0.0.1`) for local-only services.
   - Promote to LAN IP only when another node truly needs direct access.
4. **Human-in-the-loop for privileged actions.**
   - Keep operator approval gates enabled and destructive command denylist active.
5. **Segment management traffic.**
   - Put management APIs (Portainer, KVM operator, Unraid API) on trusted VLAN/Tailscale.

## Docker socket mount inventory and classification

Inventory method used: static repo scan for `/var/run/docker.sock` mounts in service definitions.

| Stack/file | Service | Mount mode | Classification | Notes |
|---|---|---:|---|---|
| `unraid/docker-compose.yml` | `homepage` | `:ro` | **Read-only needed** | Container discovery/widgets only. |
| `unraid/docker-compose.yml` | `dozzle` | `:ro` | **Read-only needed** | Docker log tailing. |
| `unraid/docker-compose.yml` | `watchtower` | `rw` | **Write-needed** | Pull/recreate containers. |
| `portainer-edge-build/central/docker-compose.portainer-be.yml` | `portainer` | `rw` | **Write-needed** | Portainer local Docker endpoint control plane. |
| `portainer-edge-build/node-a/docker-compose.edge-agent.yml` | `portainer_edge_agent` | `rw` | **Write-needed** | Remote node control for Portainer Edge. |
| `portainer-edge-build/node-b/docker-compose.edge-agent.yml` | `portainer_edge_agent` | `rw` | **Write-needed** | Remote node control for Portainer Edge. |
| `portainer-edge-build/node-c/docker-compose.edge-agent.yml` | `portainer_edge_agent` | `rw` | **Write-needed** | Remote node control for Portainer Edge. |
| `swarm/portainer-agent-stack.yml` | `agent` | `rw` | **Write-needed** | Swarm-wide Portainer agent control plane. |

### Removed from direct socket access in this hardening pass

These automation services are now expected to use **Portainer API credentials** (`PORTAINER_URL`, `PORTAINER_TOKEN`) instead of direct Docker socket mounts:

- `openclaw/docker-compose.yml` (`openclaw-gateway`)
- `node-c-arc/openclaw.yml` (`openclaw-gateway`)
- `node-b-litellm/stacks/openclaw-stack.yml` (`openclaw-gateway`)
- `turnkey/stacks/node-c-openclaw-compose.yml` (`openclaw-gateway`)
- `swarm/openclaw-swarm.yml` (`openclaw`)

## Network hardening defaults applied

- OLLAMA moved from host networking to bridge with explicit bind IP in:
  - `docker-compose.yml`
  - `node-c-arc/docker-compose.yml`
- UI/API ports now support interface scoping via bind-IP env vars (defaults to loopback):
  - `OPEN_WEBUI_BIND_IP`, `CHIMERA_FACE_BIND_IP`, `OPENCLAW_BIND_IP`
  - `HOMEPAGE_BIND_IP`, `UPTIME_KUMA_BIND_IP`, `DOZZLE_BIND_IP`

## Operational policy (recommended)

- Use a dedicated Portainer API token with minimal RBAC scope.
- Rotate: `OPENCLAW_GATEWAY_TOKEN`, Portainer API tokens, HA tokens, Unraid API keys.
- Keep `REQUIRE_APPROVAL=true` and `ALLOW_DANGEROUS=false` for automation services.
- Audit monthly:
  - socket mounts
  - host network usage
  - published ports bound to `0.0.0.0`

## Quick verification commands

```bash
# 1) Inventory docker.sock mounts
rg -n "/var/run/docker.sock" -S

# 2) Inventory host networking usage
rg -n "network_mode:\s*host" -S **/*.yml **/*.yaml docker-compose.yml

# 3) Inventory unscoped published ports (basic check)
rg -n "- \"[0-9]+:[0-9]+\"" -S **/*.yml **/*.yaml docker-compose.yml
```
