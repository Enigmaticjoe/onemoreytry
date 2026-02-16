# Grand Unified AI Home Lab - Quick Reference

## Three Core Deliverables

### 1. Node B: LiteLLM Gateway Stack (Unraid)

**File:** `node-b-litellm/litellm-stack.yml`

```yaml
version: "3.9"

services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm_gateway
    restart: unless-stopped
    network_mode: host
    environment:
      LITELLM_LOG: INFO
      JSON_LOGS: "true"
      WORKERS: "4"
    volumes:
      - ./config.yaml:/app/config.yaml:ro
    command: ["--config", "/app/config.yaml", "--port", "4000"]
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:4000/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
```

**Config:** `node-b-litellm/config.yaml`

Key routing rules:
- `brain-heavy` → `http://192.168.1.9:8000/v1` (RX 7900 XT)
- `brawn-fast` → `http://192.168.1.222:8002/v1` (RTX 4070)
- `intel-vision` → `http://192.168.1.X:11434` (Intel Arc A770)
- API Key: `sk-master-key`

**Deploy:**
```bash
cd node-b-litellm
docker compose -f litellm-stack.yml up -d
```

---

### 2. Node C: Intel Arc Ollama (Fedora 43)

**File:** `node-c-arc/docker-compose.yml`

**Key Changes from Original:**
- ✅ Uses standard `ollama/ollama:latest` (NOT ROCm image)
- ✅ Intel Arc support via `/dev/dri` devices
- ✅ Required environment: `ZES_ENABLE_SYSMAN=1`
- ✅ Renamed services: `ollama` and `chimera_face`

**Critical Intel Arc Environment Variables:**
```yaml
ZES_ENABLE_SYSMAN: "1"          # REQUIRED for Arc support
OLLAMA_NUM_GPU: "999"            # Use all GPUs
ONEAPI_DEVICE_SELECTOR: "level_zero:0"
SYCL_CACHE_PERSISTENT: "1"
```

**Deploy:**
```bash
# Ensure Intel drivers are installed first
sudo dnf install intel-level-zero-gpu intel-opencl

cd node-c-arc
docker compose up -d

# Pull Llava model
docker exec ollama_intel_arc ollama pull llava
```

---

### 3. Node D: Home Assistant Configuration

**File:** `home-assistant/configuration.yaml.snippet`

**Add to your Home Assistant `configuration.yaml`:**

```yaml
# HTTP configuration for proxy support
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 192.168.1.0/24

# OpenAI Conversation integration (connects to LiteLLM)
openai_conversation:
  - api_key: sk-master-key
    base_url: http://192.168.1.222:4000/v1
    model: brawn-fast
    max_tokens: 2000
    temperature: 0.7
```

**After adding:**
1. Restart Home Assistant
2. Go to Settings → Devices & Services → Add Integration → OpenAI Conversation
3. Select the configured provider
4. Test with a voice command

---

## Quick Test Commands

### Test LiteLLM Gateway
```bash
# Health check
curl http://192.168.1.222:4000/health

# Test brain-heavy model
curl -X POST http://192.168.1.222:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-master-key" \
  -H "Content-Type: application/json" \
  -d '{"model": "brain-heavy", "messages": [{"role": "user", "content": "Hello"}]}'
```

### Test Intel Arc Ollama
```bash
# Check Ollama is running
docker logs ollama_intel_arc

# List available models
docker exec ollama_intel_arc ollama list

# Test generation
docker exec ollama_intel_arc ollama run llava "Describe this image"
```

### Test Home Assistant
```bash
# From HA host
curl http://192.168.1.222:4000/v1/models \
  -H "Authorization: Bearer sk-master-key"
```

---

## Port Reference

| Node | Service | Port | Protocol |
|------|---------|------|----------|
| Node A (Brain) | vLLM | 8000 | HTTP |
| Node B (Brawn) | LiteLLM Gateway | 4000 | HTTP |
| Node B (Brawn) | vLLM | 8002 | HTTP |
| Node C (Command) | Ollama | 11434 | HTTP |
| Node C (Command) | Chimera Face | 3000 | HTTP |

---

## Hardware-to-Node Mapping (Corrected)

**IMPORTANT:** The problem statement corrects naming confusion in original repo files.

| Node | Name | GPU | IP | Correct Assignment |
|------|------|-----|----|--------------------|
| A | Brain (Deep Thought) | **RX 7900 XT (20GB)** | 192.168.1.9 | Heavy reasoning |
| B | Brawn (Gateway) | **RTX 4070 (12GB)** | 192.168.1.222 | Fast chat + Gateway |
| C | Command Center (Eyes) | **Intel Arc A770 (16GB)** | 192.168.1.X | Vision AI |

**Trust the hardware in the problem statement, not old repo file names!**

---

## Common Issues & Fixes

### Issue: "GPU not found" on Intel Arc
**Fix:** Ensure `ZES_ENABLE_SYSMAN=1` is set and `/dev/dri` is accessible
```bash
docker exec ollama_intel_arc env | grep ZES_ENABLE_SYSMAN
docker exec ollama_intel_arc ls -la /dev/dri
```

### Issue: LiteLLM can't reach backend models
**Fix:** Check network connectivity and port mapping
```bash
# From Node B, test Node A
curl http://192.168.1.9:8000/health

# From Node B, test local vLLM
curl http://localhost:8002/health

# From Node B, test Node C
curl http://192.168.1.X:11434/api/tags
```

### Issue: Home Assistant can't connect
**Fix:** Verify base URL and API key
```yaml
# Must use Node B's IP, not hostname
base_url: http://192.168.1.222:4000/v1  # ✅ Correct
base_url: http://node-b:4000/v1         # ❌ Wrong (unless DNS configured)
```

---

## File Locations Summary

```
/home/runner/work/onemoreytry/onemoreytry/
├── node-b-litellm/
│   ├── litellm-stack.yml        # ✅ Deploy this on Node B
│   ├── config.yaml              # ✅ LiteLLM routing config
│   └── docker-compose.yml       # Same as litellm-stack.yml
├── node-c-arc/
│   └── docker-compose.yml       # ✅ Deploy this on Node C (Intel Arc fixed)
├── home-assistant/
│   └── configuration.yaml.snippet # ✅ Add to Node D config
└── DEPLOYMENT_GUIDE.md          # Full deployment documentation
```

---

## Deployment Checklist

- [ ] **Node A (Brain)**: Ensure vLLM is running on port 8000
- [ ] **Node B (Brawn)**: Deploy `litellm-stack.yml` with `config.yaml`
- [ ] **Node C (Command)**: Install Intel drivers, deploy `docker-compose.yml`
- [ ] **Node C (Command)**: Pull Llava model: `ollama pull llava`
- [ ] **Node D (Home Assistant)**: Add `configuration.yaml.snippet` content
- [ ] **Test**: Run all test commands above
- [ ] **Verify**: Check logs on all nodes
- [ ] **Update**: Replace IP placeholders (192.168.1.X/Y/Z) with actual IPs
