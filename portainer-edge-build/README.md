# Portainer Edge Build (Nodes A/B/C)

Use this folder to deploy Portainer BE as the central control plane and attach nodes A, B, C through Edge Agents.

## Fast path

```bash
cd portainer-edge-build
cp .env.example .env
# fill .env
./scripts/build-and-deploy.sh
./scripts/check-health.sh
```

For plain-English instructions, read:

- `LAYMENS_PORTAINER_EDGE_GUIDE.md`
