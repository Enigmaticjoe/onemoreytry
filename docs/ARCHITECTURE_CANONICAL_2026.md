# Canonical Architecture 2026

This document is the **authoritative baseline** for default deployment and operations.

## Status taxonomy

Use these labels consistently across docs:

- **canonical**: Required default path for normal installs and operations.
- **optional**: Supported add-on that is not required for baseline functionality.
- **legacy**: Older supported path kept for compatibility/migration.
- **experimental**: Not production baseline; use only for testing.

## Canonical baseline (2026)

### Node roles

| Node | Canonical role | Canonical services |
|---|---|---|
| **Node A** | Inference node | Ollama (primary endpoint) |
| **Node B** | Operations / orchestration | Portainer, n8n |
| **Node C** | User interface node | Open WebUI (single shared instance) |
| **Node D** | Home automation | Home Assistant (direct to Ollama endpoint) |
| **Node E** | Surveillance/other workloads | Optional services only |

### Canonical service placement

- **Ollama runs on Nodes A, B, and C** (**canonical**).
- **Exactly one Open WebUI runs on Node C** (**canonical**).
- **Portainer runs on Node B** (**canonical**).
- **n8n runs on Node B** (**canonical**).
- **Home Assistant calls Ollama directly** (**canonical**), not through LiteLLM.

### Canonical routing

- User clients -> **Node C Open WebUI**.
- Open WebUI -> selected **Ollama endpoint** on Node A/B/C.
- Home Assistant -> direct **Ollama API endpoint** (`/api/generate` or configured Ollama-compatible integration).

## Non-canonical paths

- LiteLLM gateway patterns: **legacy** unless explicitly required.
- vLLM routes: **legacy** for this repo baseline.
- OpenClaw control paths: **legacy/optional** depending on operator needs.

## Authority and precedence

If any other document conflicts with this one, this file is the authority:

- `docs/ARCHITECTURE_CANONICAL_2026.md` (this file)

Related references:

- `docs/ARCHITECTURE.md` (high-level architecture view aligned to this baseline)
- `README.md` (default install flow)
