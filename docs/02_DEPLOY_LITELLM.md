# Deploy Node B (LiteLLM Proxy)

> Canonical architecture authority: [`docs/ARCHITECTURE_CANONICAL_2026.md`](ARCHITECTURE_CANONICAL_2026.md).


Canonical reference:
  https://docs.litellm.ai/docs/proxy/docker_quick_start

Start:
  cd node-b-litellm
  cp .env.example .env
  # edit DB_PASSWORD + LITELLM_MASTER_KEY (+ OPENAI_API_KEY if you use upstream OpenAI)
  docker compose up -d

Verify:
  curl -fsS http://localhost:4000/v1/models -H "Authorization: Bearer $LITELLM_MASTER_KEY" | head
