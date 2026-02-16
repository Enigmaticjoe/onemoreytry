# Deploy Node C (Intel Arc A770 on Fedora 43) — Ollama via IPEX-LLM

## Host prerequisites (Fedora)
Install Intel userspace runtime packages (per your blueprint):
  sudo dnf install intel-compute-runtime intel-level-zero intel-gpu-tools

Verify GPU driver:
  sudo dmesg | grep -E "i915|xe" || true
  intel_gpu_top

## Bring up stack
  cd node-c-arc
  cp .env.example .env
  docker compose up -d

Verify:
  curl -fsS http://127.0.0.1:11434/api/version

Open WebUI note:
- If Ollama is host-networked, localhost inside the WebUI container won’t work.
- This bundle uses host.docker.internal:host-gateway + OLLAMA_BASE_URL=http://host.docker.internal:11434
Open WebUI reference:
  https://docs.openwebui.com/getting-started/quick-start/
