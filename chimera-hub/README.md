# Chimera Hub

Unified interactive dashboard and control plane for Project Chimera.

## Deploy (Phase 5 target)

Portainer repository stack deploy uses:

- **Repository:** `https://github.com/Enigmaticjoe/onemoreytry`
- **Reference:** branch containing `chimera-hub/` (for production, `main`)
- **Compose path:** `chimera-hub/docker-compose.yml`
- **Endpoint:** Node B local endpoint (`endpointId=3`)

The compose is configured to build from repo root (`context: ..`) so the image includes:

- `chimera-hub/server.js`
- `config/node-inventory.env.example` (seeded to `/app/data/node-inventory.env`)
- `kvm-operator/policy_denylist.txt` (seeded to `/app/data/policy_denylist.txt`)

## Runtime environment

Copy `chimera-hub/.env.example` and set real values for:

- `PORTAINER_TOKEN`
- `LITELLM_API_KEY`
- `HOME_ASSISTANT_TOKEN`
- `KVM_OPERATOR_TOKEN`
- `JWT_SECRET`
- `CHIMERA_HUB_ADMIN_PASSWORD`

Health probe:

```bash
curl -s http://127.0.0.1:3099/api/health
```

## Unraid appdata target

Container data path:

`/mnt/user/appdata/chimera-hub`
