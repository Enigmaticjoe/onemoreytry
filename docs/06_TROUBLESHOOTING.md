# Troubleshooting

> Canonical architecture authority: [`docs/ARCHITECTURE_CANONICAL_2026.md`](ARCHITECTURE_CANONICAL_2026.md).


Open WebUI cannot connect to Ollama:
- If Ollama runs on host network, localhost inside container is wrong.
- Use OLLAMA_BASE_URL=http://host.docker.internal:11434 + extra_hosts host-gateway
Open WebUI reference:
  https://docs.openwebui.com/getting-started/quick-start/

LiteLLM vision calls fail:
- Ensure kvm-vision has model_info.supports_vision: True
LiteLLM reference:
  https://docs.litellm.ai/docs/vision

Operator aborts with REQUIRE_APPROVAL=true:
- Expected default. Set REQUIRE_APPROVAL=false only after you trust prompts + denylist.
