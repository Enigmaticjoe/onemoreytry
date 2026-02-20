# Grand Unified AI Home Lab — Revised Deployment Bundle (2026-02-15)

This bundle is a revised, deployable set of files extracted from your uploaded blueprint and corrected for:
- Docker Compose syntax issues (broken volumes, missing healthchecks)
- Open WebUI ↔ Ollama connectivity when Ollama runs on the host network
- LiteLLM vision routing metadata (supports_vision)
- A deployable KVM Operator service (FastAPI + systemd) + safer defaults
- Practical smoke audits for Open WebUI + LiteLLM

## Canonical references (for your Claude review + deployment notes)
Open WebUI:
- https://docs.openwebui.com/getting-started/quick-start/
- https://docs.openwebui.com/troubleshooting/connection-error/

LiteLLM:
- https://docs.litellm.ai/docs/proxy/docker_quick_start
- https://docs.litellm.ai/docs/vision

> Note: NanoKVM API specifics are based on your uploaded blueprint + its cited vendor/GitHub sources.

## What’s inside
- node-c-arc/         Intel Arc (Fedora) Ollama via IPEX-LLM + optional Open WebUI
- node-b-litellm/     LiteLLM proxy + Postgres
- kvm-operator/       FastAPI “AI KVM Operator” + systemd unit + denylist policy
- node-a-command-center/  Node A dashboard + status checks + chatbot proxy
- home-assistant/     example snippet for extended_openai_conversation + webhook trigger
- docs/               step-by-step deploy, troubleshooting, security, Claude Code runbook

## Quick start
- Node C:  cd node-c-arc && cp .env.example .env && docker compose up -d
- Node B:  cd node-b-litellm && cp .env.example .env && docker compose up -d
- Operator: cd kvm-operator && cp .env.example .env && ./run_dev.sh
- Node A:  cd node-a-command-center && node node-a-command-center.js (opens dashboard on port 3099)
- Extended guidebook: docs/09_NODE_A_COMMAND_CENTER_GUIDEBOOK.md
- Unified install guidebook: docs/10_UNIFIED_INSTALL_GUIDEBOOK.md
- Root unified guidebook: UNIFIED_GUIDEBOOK.md
- Inventory template: config/node-inventory.env.example
- GUI install wizard (per-node): http://<node-a-ip>:3099/install-wizard
