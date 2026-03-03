# Repository reference audit (high-signal folders)

This audit is based on a direct repo scan and focuses on folders relevant to Node A, Node C, OpenClaw, and KVM automation.

## Core deployment folders
- `node-a-vllm/` — Node A inference stack and setup script.
- `node-c-arc/` — Node C Intel Arc + Ollama + OpenClaw config artifacts.
- `kvm-operator/` — FastAPI-based NanoKVM operator with denylist and token auth.
- `openclaw/` — generic OpenClaw compose + skills.
- `scripts/` — orchestration/install helpers.
- `docs/` — runbooks and node-specific guides.

## Automation-related folders
- `portainer-edge-build/` — edge-agent automation for multi-node container control.
- `swarm/` — Swarm stack templates.
- `brothers-keeper/` — API/orchestrator utilities and UI templates.

## Hardware-guidance docs reviewed for this release
- `docs/01_DEPLOY_NODE_C_ARC.md`
- `docs/03_DEPLOY_NODE_A_BRAIN.md`
- `docs/11_OPENCLAW_KVM_GUIDEBOOK.md`

## Included turnkey outputs
- `turnkey/stacks/node-c-openclaw-compose.yml`
- `turnkey/stacks/node-a-kvm-operator-compose.yml`
- `turnkey/node-a/agent-prompt.json`
- `turnkey/node-c/agent-prompt.json`
- `turnkey/TURNKEY_RELEASE.md`
