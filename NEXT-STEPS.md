# NEXT STEPS (Manual Checklist)

1. Copy project files to Unraid paths:
   - `/mnt/user/appdata/nanoclaw/` for NanoClaw assets.
   - `/mnt/user/appdata/unraidclaw/` for Option B UnraidClaw data.

2. Run bootstrap:
   - `bash deploy.sh`

3. Fill secrets in `/mnt/user/appdata/nanoclaw/.env`:
   - `DISCORD_BOT_TOKEN`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`
   - `HOME_ASSISTANT_TOKEN`
   - `GITHUB_TOKEN`
   - `BRAVE_API_KEY` or `TAVILY_API_KEY`
   - `QDRANT_API_KEY` (if enabled)

4. Choose UnraidClaw mode:
   - **Option A (recommended):** install UnraidClaw plugin from Community Applications and create API key in WebGUI.
   - **Option B:** set `COMPOSE_PROFILES=unraidclaw-container` in Portainer stack env, then deploy containerized UnraidClaw.

5. Generate/rotate UnraidClaw API key (do NOT hardcode in git):
   - `openssl rand -hex 32`
   - Update `UNRAIDCLAW_API_KEY` in `.env`.

6. Confirm TLS behavior:
   - Plugin mode uses self-signed cert by default.
   - Keep `tlsSkipVerify: true` in `.mcp.json` until you trust/install your local CA.

7. Deploy stack in Portainer:
   - Use `docker-compose.yml` from `/mnt/user/appdata/nanoclaw/`.
   - Verify `nanoclaw` container is healthy.

8. Pull fallback and task-specific Ollama models on Node B:
   - `ollama pull huihui_ai/qwen3-abliterated:14b`
   - `ollama pull dolphin3:70b`
   - `ollama pull glm4-9b-abliterated`
   - `ollama pull josiefied/qwen3:8b`
   - `ollama pull dolphin-mixtral:8x7b`

9. Validate MCP connectivity from NanoClaw runtime:
   - UnraidClaw endpoint reachable at `https://192.168.1.222:9876`
   - Filesystem tool can read/write `/opt/nanoclaw/workspace`
   - Docker MCP can list containers
   - Qdrant reachable on Node A Tailscale URL

10. Schedule health checks (Unraid User Scripts plugin):
    - Add `health-check.sh` every 5 minutes.
    - Configure `DISCORD_WEBHOOK_URL` to receive failure alerts.

11. Configure Open WebUI integration:
    - Point Open WebUI to NanoClaw API endpoint (or model-router endpoint if using proxy strategy).
    - If NanoClaw has no built-in web UI in your deployed commit, use Telegram/Discord/Open WebUI as user-facing channels.

12. Seed personas and verify behavior:
    - Confirm all four memory files under `/mnt/user/appdata/nanoclaw/agents/*/CLAUDE.md`.
    - Test CHIMERA morning report task, FORGE compose generation, SENTINEL read-only security checks, ORACLE Qdrant-first retrieval.

13. Lock down permissions after shakeout period:
    - Move UnraidClaw from full-admin preset to least privilege per agent.
    - Restrict Docker socket exposure scope wherever practical.
