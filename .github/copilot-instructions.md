# Copilot Instructions — Grand Unified AI Home Lab

## Repository Overview

This repository is a deployable AI home-lab stack composed of multiple nodes and services:

- **node-a-command-center/** – Node.js dashboard, status checks, chatbot proxy, and GUI install wizard (port 3099).
- **node-b-litellm/** – LiteLLM proxy + Postgres. Config lives in `config.yaml`; stack file is `litellm-stack.yml`.
- **node-c-arc/** – Intel Arc GPU Ollama runtime + optional Open WebUI, managed via Docker Compose.
- **kvm-operator/** – FastAPI AI KVM Operator (Python) with NanoKVM integration, human-in-the-loop approval, and a command denylist.
- **home-assistant/** – Example `configuration.yaml.snippet` for `extended_openai_conversation`.
- **docs/** – Step-by-step deployment, troubleshooting, security, and Claude Code runbook guides.

## Validation

Run the validation script from the repository root to check YAML syntax and structural correctness of all config files:

```bash
./validate.sh
```

The script uses `python3 -c "import yaml; yaml.safe_load(...)"` for YAML files. There is no additional test framework; all checks are in `validate.sh`.

## Language & Tooling

- **Node.js** (`node-a-command-center/`) – plain JavaScript; run with `node node-a-command-center.js`.
- **Python** (`kvm-operator/`) – FastAPI + Uvicorn; dependencies in `requirements.txt`.
  - Install: `pip install -r kvm-operator/requirements.txt`
  - Dev server: `cd kvm-operator && ./run_dev.sh`
- **Docker Compose** – used throughout; each node has its own `docker-compose.yml` or `litellm-stack.yml`.
  - Start Node B: `cd node-b-litellm && docker compose -f litellm-stack.yml up -d`
  - Start Node C: `cd node-c-arc && docker compose up -d`
  - Start KVM Operator: `cd kvm-operator && ./run_dev.sh`

## Code Style Conventions

- Python: follow PEP 8; use `dataclass` and `pydantic.BaseModel` for data models (see `kvm-operator/app.py`).
- JavaScript: ES6+ vanilla JS; keep the single-file structure of `node-a-command-center.js`.
- YAML: 2-space indentation; validate with `python3 -c "import yaml; yaml.safe_load(open('<file>'))"`.
- Avoid hardcoding secrets; use environment variables loaded via `python-dotenv` (Python) or `process.env` (Node.js).

## Security Practices

- The KVM Operator defaults to `REQUIRE_APPROVAL=true` (human-in-the-loop). Do not disable this by default.
- The `policy_denylist.txt` blocks destructive commands. Do not weaken the denylist without explicit instruction.
- API tokens and keys must come from environment variables, never from source code.
- Docker Compose services should not use `privileged: true` unless strictly required for hardware access.

## Pull Request Guidelines

- Validate all YAML changes with `./validate.sh` before submitting.
- If any Docker Compose service definition changes, verify healthchecks are still present.
- Update the relevant `docs/` guide if deployment steps change.
- Do not alter IP addresses, model names, or container names without updating both the config files and the docs.
