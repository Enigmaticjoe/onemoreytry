# Grand Unified AI Home Lab - Deployment Guide

This guide provides step-by-step instructions for deploying the unified AI home lab across five physical nodes.

## Network Topology

| Node | Role | IP | Hardware | GPU | Purpose |
|------|------|----|---------|----|---------|
| **Node A** | Brain (Deep Thought) | `192.168.1.9` | Core Ultra 7 265KF, 128GB DDR5 | **RX 7900 XT (20GB)** | Heavy Logic/Reasoning (start with feasible 8B/14B profile) |
| **Node B** | Brawn (The Gateway) | `192.168.1.222` | i5-13600K, 96GB DDR5 | **RTX 4070 (12GB)** | Fast Chat & **Central AI Gateway** |
| **Node C** | Command Center (The Eyes) | `192.168.1.6` | Ryzen 7 7700X, 32GB RAM | **Intel Arc A770 (16GB)** | Vision AI (Llava) & Whisper Audio |
| **Node D** | Home Assistant (The Voice) | `192.168.1.149` | Ryzen 7 7430U, 32GB DDR4 | N/A | Voice Client (connects to Gateway) |
| **Node E** | Sentinel (The Watcher) | `192.168.1.116` | Windows VM on Proxmox (192.168.1.174) | N/A | NVR (Blue Iris) |

## Unified API Endpoint

Primary AI access is through the **LiteLLM Gateway** on Node B at:
```
http://192.168.1.222:4000
```

API Key: `sk-master-key`

**Resiliency reality check:** if Node B is unavailable, clients needing continuity should use emergency direct endpoints (`Node A: :8000`, `Node C: :11434`) until gateway service is restored.

### Available Models

| Model Name | Routes to | Hardware | Use Case |
|-----------|-----------|----------|----------|
| `brain-heavy` | Node A vLLM (192.168.1.9:8000) | RX 7900 XT | Heavy reasoning, complex tasks (after model-size feasibility validation) |
| `brawn-fast` | Node B vLLM (192.168.1.222:8002) | RTX 4070 | Fast chat, quick responses |
| `intel-vision` | Node C Ollama (192.168.1.6:11434) | Intel Arc A770 | Vision AI, image analysis |

---

## Deployment Steps

### Node A: Deploy Brain Project (AMD RX 7900 XT)

**Location:** `node-a-vllm/`  
**Full guide:** [`docs/03_DEPLOY_NODE_A_BRAIN.md`](docs/03_DEPLOY_NODE_A_BRAIN.md)

1. Install ROCm on the host (Fedora example):
   ```bash
   sudo tee /etc/yum.repos.d/rocm.repo > /dev/null <<'REPO'
   [ROCm]
   name=ROCm
   baseurl=https://repo.radeon.com/rocm/rhel9/latest/main
   enabled=1
   gpgcheck=1
   gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key
   REPO
   sudo dnf install -y rocm-hip-sdk rocm-opencl-sdk rocminfo
   sudo usermod -aG render,video "$USER"
   ```

2. Verify the GPU is visible to ROCm:
   ```bash
   /opt/rocm/bin/rocminfo | grep "Marketing Name"
   # Expected: Radeon RX 7900 XT
   ```

3. Configure the environment:
   ```bash
   cd node-a-vllm
   cp .env.example .env
   # Edit .env: set HUGGING_FACE_HUB_TOKEN (secrets auto-generated)
   ```

4. Deploy the Brain Project stack:
   ```bash
   ./setup.sh         # or: docker compose up -d
   ```

5. Verify (vLLM may take 3–5 min on first start while the model downloads):
   ```bash
   docker logs brain-vllm --tail 20 -f
   curl http://localhost:8000/health
   curl http://localhost:8000/v1/models | jq '.data[].id'
   ```

6. One-command setup alternative:
   ```bash
   ./scripts/setup-node-a.sh        # full ROCm check + Brain Project deploy
   ./scripts/setup-node-a.sh --status   # check GPU + all service health
   ```

**Port summary for Node A:**
| Port | Service |
|------|---------|
| 8000 | vLLM OpenAI API (`dolphin-2.9.3-llama-3.1-8b` / `brain-heavy` alias) |
| 3000 | OpenWebUI chat interface |
| 6333 | Qdrant vector database |
| 8001 | Embeddings service |
| 8888 | SearXNG private search |
| 8899 | Coding Agent (JupyterLab) |
| 8090 | Hardware Agent (GPU monitoring) |
| 8080 | Dashboard (Homepage) |
| 11435 | Ollama + ROCm (alternative — see `node-a-vllm/docker-compose.ollama.yml`) |
| 3099 | Command Center Dashboard (Node.js) |
| 5000 | KVM Operator (FastAPI) |

---

### Node B: Deploy LiteLLM Gateway (Unraid)

**Location:** `/home/runner/work/onemoreytry/onemoreytry/node-b-litellm/`

1. Copy the files to your Unraid server:
   ```bash
   cd node-b-litellm
   ```

2. Deploy using the simplified stack:
   ```bash
   docker compose -f litellm-stack.yml up -d
   ```

3. Verify the gateway is running:
   ```bash
   docker logs litellm_gateway
   curl http://localhost:4000/health
   ```

4. Test the routing:
   ```bash
   curl -X POST http://localhost:4000/v1/chat/completions \
     -H "Authorization: Bearer sk-master-key" \
     -H "Content-Type: application/json" \
     -d '{
       "model": "brawn-fast",
       "messages": [{"role": "user", "content": "Hello"}]
     }'
   ```

**Notes:**
- Uses host networking for simple inter-node communication
- No database required for basic routing
- Config file: `config.yaml` with all routing rules

---

### Node C: Deploy Ollama with Intel Arc (Fedora 44 cosmic nightly)

**Location:** `/home/runner/work/onemoreytry/onemoreytry/node-c-arc/`

**⚠️ CRITICAL FIX:** This configuration now uses the **standard Ollama image** with Intel Arc support (no more ROCm!).

1. Ensure Intel Compute Runtime is installed on the host:
   ```bash
   # On Fedora 44 (cosmic nightly)
   sudo dnf install intel-level-zero-gpu intel-opencl
   ```

2. Verify GPU access:
   ```bash
   ls -la /dev/dri
   # Should show render and card devices
   ```

3. Deploy the stack:
   ```bash
   cd node-c-arc
   docker compose up -d
   ```

4. Verify Ollama is running with Intel Arc:
   ```bash
   docker logs ollama_intel_arc
   docker exec ollama_intel_arc ollama list
   ```

5. Pull the Llava model for vision tasks:
   ```bash
   docker exec ollama_intel_arc ollama pull llava
   ```

6. Test vision capability:
   ```bash
   curl http://localhost:11434/api/generate \
     -d '{"model": "llava", "prompt": "What is in this image?", "images": ["base64_encoded_image"]}'
   ```

7. Access Chimera Face (Open WebUI) at `http://192.168.1.6:3000`

**Environment Variables Explained:**
- `ZES_ENABLE_SYSMAN=1` - **REQUIRED** for Intel Arc GPU support
- `OLLAMA_NUM_GPU=999` - Enable all available GPUs
- `ONEAPI_DEVICE_SELECTOR=level_zero:0` - Use Level Zero API
- `SYCL_CACHE_PERSISTENT=1` - Cache optimization

---

### Node D: Configure Home Assistant

**Location:** `/home/runner/work/onemoreytry/onemoreytry/home-assistant/configuration.yaml.snippet`

1. Add the configuration to your `configuration.yaml`:
   ```yaml
   openai_conversation:
     - api_key: sk-master-key
       base_url: http://192.168.1.222:4000/v1
       model: brawn-fast
       max_tokens: 2000
       temperature: 0.7
   ```

2. Restart Home Assistant

3. Add a conversation integration and select the OpenAI Conversation provider

4. Test with a voice command or text input

**Available Models in Home Assistant:**
- `brawn-fast` - Quick responses from Node B
- `brain-heavy` - Complex reasoning from Node A
- `intel-vision` - Image analysis from Node C (requires image input)

---

## Troubleshooting

### LiteLLM Gateway (Node B)

**Issue:** Gateway not accessible from other nodes
```bash
# Check if listening on all interfaces
docker exec litellm_gateway netstat -tlnp | grep 4000

# Test locally first
curl http://localhost:4000/health

# Test from another node
curl http://192.168.1.222:4000/health
```

**Issue:** Model routing not working
```bash
# Check config is mounted
docker exec litellm_gateway cat /app/config.yaml

# Check logs for routing errors
docker logs litellm_gateway -f
```

### Intel Arc Ollama (Node C)

**Issue:** GPU not detected
```bash
# Verify /dev/dri exists in container
docker exec ollama_intel_arc ls -la /dev/dri

# Check environment variables
docker exec ollama_intel_arc env | grep -E "ZES|OLLAMA|ONEAPI"

# Look for GPU detection in logs
docker logs ollama_intel_arc 2>&1 | grep -i "gpu\|arc\|intel"
```

**Issue:** Ollama service won't start
```bash
# Check if ZES_ENABLE_SYSMAN is set
docker inspect ollama_intel_arc | grep ZES_ENABLE_SYSMAN

# Try running Ollama manually
docker exec -it ollama_intel_arc ollama serve
```

### Home Assistant Connection

**Issue:** Cannot connect to LiteLLM
```bash
# From Home Assistant host, test connectivity
ping 192.168.1.222
curl http://192.168.1.222:4000/health

# Check Home Assistant logs
docker logs homeassistant | grep -i openai
```

---

## Testing the Unified Ecosystem

### 1. Test Brain (Heavy Reasoning)
```bash
curl -X POST http://192.168.1.222:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-master-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "brain-heavy",
    "messages": [{"role": "user", "content": "Explain quantum entanglement"}]
  }'
```

### 2. Test Brawn (Fast Chat)
```bash
curl -X POST http://192.168.1.222:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-master-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "brawn-fast",
    "messages": [{"role": "user", "content": "What is 2+2?"}]
  }'
```

### 3. Test Vision (Intel Arc)
```bash
# Note: Requires base64-encoded image
curl -X POST http://192.168.1.222:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-master-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "intel-vision",
    "messages": [{
      "role": "user",
      "content": [
        {"type": "text", "text": "What is in this image?"},
        {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,..."}}
      ]
    }]
  }'
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Grand Unified AI Home Lab                 │
└─────────────────────────────────────────────────────────────┘

    ┌─────────────┐
    │  Node D     │
    │  Home Asst  │  Voice Client
    │  (Voice)    │  API: sk-master-key
    └──────┬──────┘
           │
           ▼
    ┌─────────────────────────────────────────┐
    │  Node B - LiteLLM Gateway (Port 4000)   │
    │  192.168.1.222 (RTX 4070)               │
    │  ┌───────────────────────────────────┐  │
    │  │  Model Router                     │  │
    │  │  • brain-heavy  → Node A         │  │
    │  │  • brawn-fast   → Local vLLM     │  │
    │  │  • intel-vision → Node C         │  │
    │  └───────────────────────────────────┘  │
    └────┬─────────────────────────┬──────────┘
         │                         │
    ┌────▼─────┐             ┌────▼─────┐
    │  Node A  │             │  Node C  │
    │  Brain   │             │ Cmd Ctr  │
    │  (Deep   │             │  (Eyes)  │
    │  Thought)│             │  Vision  │
    │          │             │  Arc A770│
    │ RX 7900  │             │  Llava   │
    │ XT 20GB  │             │  Ollama  │
    │ Llama-70B│             │  :11434  │
    │  :8000   │             └──────────┘
    └──────────┘
    
    Node E: Sentinel (NVR) - Future integration with Node C
```

---

## Security Considerations

1. **API Key Management**: The current setup uses a static API key (`sk-master-key`). For production:
   - Use environment variables
   - Rotate keys regularly
   - Consider per-client keys

2. **Network Security**: All traffic is currently unencrypted HTTP:
   - Add TLS/SSL for production
   - Use reverse proxy (nginx/traefik)
   - Consider VPN for external access

3. **Firewall Rules**: Limit access to required ports:
   - Node B: 4000 (LiteLLM), 8002 (vLLM)
   - Node A: 8000 (vLLM)
    - Node C: 11434 (Ollama), 3000 (WebUI)

4. **KVM Safety Controls**: denylist matching is useful but incomplete:
   - Keep `REQUIRE_APPROVAL=true`
   - Keep `ALLOW_DANGEROUS=false` outside break-glass maintenance
   - Continue network segmentation for KVM traffic

---

## Next Steps

1. **Network Addresses**: Node C=`192.168.1.6`, HA=`192.168.1.149`, Proxmox=`192.168.1.174`, Brawn=`192.168.1.222`, Blue Iris=`192.168.1.116`, KVM=`192.168.1.130` (kvm-d829.local)
2. **Deploy Node A**: Ensure vLLM is running on port 8000
3. **Test Full Pipeline**: Execute all test commands above
4. **Monitor Performance**: Add metrics/logging as needed
5. **Node E Integration**: Connect Blue Iris to Node C for object detection

---

## Support

For issues or questions:
- Check logs: `docker logs <container_name>`
- Verify networking: `docker network inspect bridge`
- Review LiteLLM docs: https://docs.litellm.ai/
- Ollama Intel GPU: https://ollama.com/blog/intel-arc
