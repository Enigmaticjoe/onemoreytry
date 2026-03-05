# Unified Multi-Node Installation Guidebook

> Canonical architecture authority: [`docs/ARCHITECTURE_CANONICAL_2026.md`](ARCHITECTURE_CANONICAL_2026.md).


This is the single consolidated install document for Nodes A-E plus the KVM Operator.

## Reality checks first

1. **LiteLLM on Node B is a convenience gateway, not a hard dependency.**  
   Keep documented direct fallback paths to Node A (`:8000`) and Node C (`:11434`) for incident operations.
2. **Node A RX 7900 XT (20GB) is not a guaranteed fit for practical Llama-70B serving.**  
   Start with a feasible profile (8B/14B class or aggressive quantization) and only scale after measured VRAM + latency tests.
3. **KVM denylist is not a complete safety control.**  
   Keep `REQUIRE_APPROVAL=true`; treat `ALLOW_DANGEROUS=true` as break-glass only.

## Install order (recommended)

1. Node C (Intel Arc runtime + Ollama + Chimera Face)
2. Node B (LiteLLM gateway)
3. Node A (Command Center + status/chat)
4. Node D (Home Assistant integration)
5. Node E (NVR/Sentinel integration)
6. KVM Operator

## Node-by-node commands

### Node C
```bash
sudo dnf install intel-level-zero-gpu intel-opencl -y
cd node-c-arc
docker compose up -d
docker exec ollama_intel_arc ollama pull llava
```

### Node B
```bash
cd node-b-litellm
cp .env.example .env
docker compose -f litellm-stack.yml up -d
curl http://localhost:4000/health
```

### Node A
```bash
cd node-a-command-center
node node-a-command-center.js
curl http://127.0.0.1:3099/api/status
```

### Node D
```bash
# merge home-assistant/configuration.yaml.snippet into your HA configuration.yaml
```

### Node E
```bash
# configure Sentinel/NVR webhooks to approved AI endpoints only
```

### KVM Operator
```bash
cd kvm-operator
cp .env.example .env
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 5000
```

## GUI install wizard

Use the Node A command center GUI wizard:

- `http://<node-a-ip>:3099/install-wizard`

The wizard includes per-node install tabs and copy/paste command blocks.

## Validation

```bash
cd <repo-root>
./validate.sh
```
