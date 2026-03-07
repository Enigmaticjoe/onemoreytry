# Project Chimera — Model Selection Guide

> Canonical architecture authority: [`docs/ARCHITECTURE_CANONICAL_2026.md`](ARCHITECTURE_CANONICAL_2026.md).

This guide explains the recommended Ollama model assignment for each node in your Project Chimera home lab, how to pull them, and how to verify everything is working end-to-end.

---

## The Short Version

Run the installer script on each node (or all at once from a machine with SSH access):

```bash
# Pull models on a specific node (run locally on that machine)
./scripts/pull-models.sh --node a     # Node A — Brain
./scripts/pull-models.sh --node b     # Node B — Brawn
./scripts/pull-models.sh --node c     # Node C — Arc

# Pull models on all three nodes via SSH (from any machine in the lab)
./scripts/pull-models.sh --all

# Preview what would run without executing
./scripts/pull-models.sh --node a --dry-run

# Interactive menu (no flags needed)
./scripts/pull-models.sh
```

Then restart LiteLLM on Node B to pick up the updated config:

```bash
docker restart litellm
curl http://192.168.1.222:4000/v1/models | jq '[.data[].id]'
```

---

## Node Assignments

### Node A — Brain (AMD RX 7900 XT, 20 GB VRAM)

| Model | Size | Role |
|-------|------|------|
| `qwen2.5:32b` | ~19.4 GB | Primary reasoning thinker — complex analysis, multi-step logic |
| `llava:13b` | ~8.0 GB | Vision-language model — image captioning, multimodal prompts |

**Why `qwen2.5:32b`?**  
With 20 GB VRAM you can comfortably run a 32-billion-parameter model at 4-bit quantisation. `qwen2.5:32b` delivers GPT-4-class reasoning for tasks that need deep thinking: document analysis, complex code review, multi-hop QA. The model is uncensored by default and responds in 100+ languages.

**Why `llava:13b`?**  
The 13B LLaVA variant gives a strong vision encoder without exceeding the 20 GB budget (even when the 32B text model is not loaded simultaneously). It handles document images, screenshots, and photos for Home Assistant automations and n8n workflows.

**VRAM budget:**

| Loaded model | VRAM used |
|---|---|
| `qwen2.5:32b` (q4_K_M) | ~19.4 GB |
| `llava:13b` (q4_K_M) | ~8.0 GB |
| ROCm runtime overhead | ~1–2 GB |

> **Note:** Only one large model loads at a time. Ollama evicts the previous model when a new one is requested, so both can be configured even though they don't fit simultaneously.

---

### Node B — Brawn (NVIDIA RTX 4070, 12 GB VRAM)

| Model | Size | Role | LiteLLM alias |
|-------|------|------|---------------|
| `dolphin-mistral:7b` | ~4.1 GB | Uncensored all-rounder — chat, summarisation, light code | `brawn-fast` |
| `qwen2.5-coder:14b` | ~8.4 GB | Specialised code generation, debugging, review | `brawn-code` |
| `phi4-mini` | ~2.5 GB | Ultra-fast for simple classifications / cheap calls | `brawn-mini` |
| `nomic-embed-text` | ~0.3 GB | Embeddings — used by n8n AI nodes and OpenWebUI RAG | `brawn-embed` |

**Why `dolphin-mistral:7b`?**  
Based on Mistral 7B with Dolphin fine-tuning to remove refusals and safety filters. At ~4 GB it leaves room for `qwen2.5-coder` in the same VRAM pool. Ideal for general chat, tool-calling, and summarisation tasks in n8n workflows.

**Why `qwen2.5-coder:14b`?**  
Qwen 2.5 Coder is purpose-built for code. At 8.4 GB it fits within the RTX 4070's 12 GB budget and outperforms GPT-3.5 on HumanEval. Use it for the Coding Agent workflows and Jupyter notebook generation.

---

### Node C — Arc (Intel Arc A770, 16 GB VRAM)

| Model | Size | Role | LiteLLM alias |
|-------|------|------|---------------|
| `phi4:latest` | ~9.1 GB | Fast, efficient conversation on Intel GPU | `intel-fast` |
| `dolphin3:8b` | ~4.9 GB | Uncensored, low-latency responses | `intel-uncensored` |

**Why `phi4:latest`?**  
Microsoft's Phi-4 punches well above its weight — it outperforms many 70B models on reasoning benchmarks while fitting in 9 GB. On Intel Arc its INT4 execution via the OneAPI Level Zero driver is highly optimised. It's the go-to model for Home Assistant intents and real-time chat in OpenWebUI.

**Why `dolphin3:8b`?**  
The third generation of Eric Hartford's Dolphin series, based on Llama 3.1 8B with zero system-prompt censorship. At ~4.9 GB it runs alongside `phi4` in the 16 GB Arc VRAM pool. Use it when you need raw, unfiltered output for automation scripts, creative tasks, or research.

---

## Step-by-Step Deployment

### Prerequisites

Make sure the Ollama container is running on each node before pulling models:

```bash
# Node A — start the Ollama ROCm container
cd ~/homelab/node-a-vllm
docker compose -f docker-compose.ollama.yml up -d

# Node B — Ollama is part of the nodebfinal stack
cd ~/homelab/nodebfinal
docker compose up -d

# Node C — Ollama is part of the node-c-arc stack
cd ~/homelab/node-c-arc
docker compose up -d
```

### Pull models (recommended: use the script)

```bash
# From the repo root on Node A:
./scripts/pull-models.sh --node a

# From the repo root on Node B:
./scripts/pull-models.sh --node b

# From the repo root on Node C:
./scripts/pull-models.sh --node c
```

### Pull models manually

If you prefer to pull manually:

```bash
# Node A (container: ollama_brain, port 11435)
docker exec ollama_brain ollama pull qwen2.5:32b
docker exec ollama_brain ollama pull llava:13b

# Node B (container: ollama, port 11434)
docker exec ollama ollama pull dolphin-mistral:7b
docker exec ollama ollama pull qwen2.5-coder:14b
docker exec ollama ollama pull phi4-mini
docker exec ollama ollama pull nomic-embed-text

# Node C (container: ollama_intel_arc, port 11434)
docker exec ollama_intel_arc ollama pull phi4:latest
docker exec ollama_intel_arc ollama pull dolphin3:8b
```

### Verify models are loaded

```bash
# Check what's on Node A
curl -s http://192.168.1.9:11435/api/tags | jq '[.models[].name]'

# Check what's on Node B
curl -s http://192.168.1.222:11434/api/tags | jq '[.models[].name]'

# Check what's on Node C
curl -s http://192.168.1.6:11434/api/tags | jq '[.models[].name]'
```

### Update LiteLLM and verify routing

After pulling all models, restart LiteLLM on Node B:

```bash
docker restart litellm
sleep 5

# List all routable model aliases
curl -s http://192.168.1.222:4000/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" | jq '[.data[].id]'
```

Expected output (order may vary):
```json
[
  "brain-heavy",
  "brain-vision",
  "brawn-fast",
  "brawn-code",
  "brawn-mini",
  "brawn-embed",
  "intel-fast",
  "intel-uncensored",
  "intel-vision"
]
```

---

## Quick Test Prompts

### Test Node A reasoning

```bash
curl -s -X POST http://192.168.1.222:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "brain-heavy",
    "messages": [{"role": "user", "content": "Explain the difference between vLLM and Ollama in three sentences."}]
  }' | jq -r '.choices[0].message.content'
```

### Test Node B uncensored chat

```bash
curl -s -X POST http://192.168.1.222:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "brawn-fast",
    "messages": [{"role": "user", "content": "Write a Python function to reverse a linked list."}]
  }' | jq -r '.choices[0].message.content'
```

### Test Node B coding model

```bash
curl -s -X POST http://192.168.1.222:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "brawn-code",
    "messages": [{"role": "user", "content": "Refactor this Python snippet to use a dataclass: class Foo:\n  def __init__(self, x, y):\n    self.x = x\n    self.y = y"}]
  }' | jq -r '.choices[0].message.content'
```

### Test Node C fast conversation

```bash
curl -s -X POST http://192.168.1.222:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "intel-fast",
    "messages": [{"role": "user", "content": "What is today weather like?"}]
  }' | jq -r '.choices[0].message.content'
```

### Test Node A vision (image input)

```bash
# Encode an image to base64 and ask llava:13b to describe it
IMG_B64=$(base64 -w 0 /path/to/image.jpg)

curl -s -X POST http://192.168.1.222:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"brain-vision\",
    \"messages\": [{
      \"role\": \"user\",
      \"content\": [
        {\"type\": \"text\", \"text\": \"Describe this image in detail.\"},
        {\"type\": \"image_url\", \"image_url\": {\"url\": \"data:image/jpeg;base64,${IMG_B64}\"}}
      ]
    }]
  }" | jq -r '.choices[0].message.content'
```

---

## VRAM Budget Reference

### Node A — AMD RX 7900 XT (20 GB)

| Scenario | VRAM |
|---|---|
| `qwen2.5:32b` only | ~19.4 GB |
| `llava:13b` only | ~8.0 GB |
| Both (Ollama hot-swaps) | 19.4 GB max (one at a time) |

### Node B — NVIDIA RTX 4070 (12 GB)

| Model(s) loaded | VRAM |
|---|---|
| `dolphin-mistral:7b` | ~4.1 GB |
| `qwen2.5-coder:14b` | ~8.4 GB |
| `phi4-mini` | ~2.5 GB |
| `nomic-embed-text` | ~0.3 GB |
| All four simultaneously | ~15.3 GB — exceeds budget; Ollama evicts LRU |
| Best active pair: `dolphin-mistral` + `qwen2.5-coder` | ~12.5 GB — fits in 12 GB with tight margin |

> **Tip:** Set `OLLAMA_MAX_LOADED_MODELS=2` in the Node B Ollama environment to cap concurrent model memory.

### Node C — Intel Arc A770 (16 GB)

| Model(s) loaded | VRAM |
|---|---|
| `phi4:latest` | ~9.1 GB |
| `dolphin3:8b` | ~4.9 GB |
| Both simultaneously | ~14.0 GB — fits in 16 GB |

Both Node C models can be resident in VRAM at the same time, giving zero cold-start latency when switching between them.

---

## Troubleshooting

### Model download is slow / stalled

Ollama pulls from the Ollama registry (https://registry.ollama.ai) by default. Large models (32B) can take 20–40 minutes on a 100 Mbps connection.

```bash
# Monitor pull progress inside the container
docker exec ollama_brain ollama pull qwen2.5:32b
# Press Ctrl-C to pause; re-run to resume (pulls are resumable)
```

### Model not found after pull

```bash
# List installed models
docker exec ollama_brain ollama list

# Verify the API sees them
curl http://localhost:11435/api/tags | jq '.models[].name'
```

### LiteLLM returns "model not found"

1. Confirm the model is pulled: `docker exec ollama ollama list`
2. Check the model name matches exactly (including tag) in the LiteLLM config
3. Restart LiteLLM: `docker restart litellm`
4. Check LiteLLM logs: `docker logs litellm --tail 50`

### Intel Arc model loads but is slow

Ensure these environment variables are set in `node-c-arc/docker-compose.yml`:

```yaml
environment:
  ZES_ENABLE_SYSMAN: "1"
  ONEAPI_DEVICE_SELECTOR: "level_zero:0"
  SYCL_CACHE_PERSISTENT: "1"
```

### Node A ROCm model not using GPU

Check that the ROCm container has access to `/dev/kfd` and `/dev/dri`, and that `HSA_OVERRIDE_GFX_VERSION=11.0.0` is set:

```bash
docker exec ollama_brain env | grep HSA
# Should print: HSA_OVERRIDE_GFX_VERSION=11.0.0

docker exec ollama_brain ls /dev/kfd
# Should succeed without errors
```

---

## Model Aliases Cheat Sheet

| Alias | Backend | Model | Best for |
|---|---|---|---|
| `brain-heavy` | Node A | `qwen2.5:32b` | Deep reasoning, long documents |
| `brain-vision` | Node A | `llava:13b` | Image understanding, screenshots |
| `brawn-fast` | Node B | `dolphin-mistral:7b` | Fast uncensored chat |
| `brawn-code` | Node B | `qwen2.5-coder:14b` | Code generation and review |
| `brawn-mini` | Node B | `phi4-mini` | Quick, cheap inference |
| `brawn-embed` | Node B | `nomic-embed-text` | RAG embeddings |
| `intel-fast` | Node C | `phi4:latest` | Real-time conversation |
| `intel-uncensored` | Node C | `dolphin3:8b` | Unfiltered automation |
| `intel-vision` | Node C | `llava:13b` | Vision (Node C path) |

All aliases are available through the single LiteLLM gateway at `http://192.168.1.222:4000/v1`.
