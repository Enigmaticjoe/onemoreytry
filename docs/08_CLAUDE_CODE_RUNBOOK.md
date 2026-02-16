# Claude 4.6 Code — Review & Deployment Runbook

## What to give Claude
- This whole bundle folder (or the zip produced by this script)
- Your node OS/IP notes + VLAN policy
- Whether you actually use OpenAI upstream (brain-heavy) or only local routes

## Single prompt (repo review + hardening + deploy runbook)
You are Claude 4.6 Code acting as a senior SRE + security engineer.
You have a repo containing:
- docker compose stacks for Node C (Arc/Ollama + optional Open WebUI) and Node B (LiteLLM + Postgres)
- a FastAPI “AI KVM Operator” that logs into NanoKVM and uses LiteLLM vision to decide what to type

Tasks:
1) Validate YAML correctness: run `docker compose config` for each stack, fix any issues.
2) Review networking assumptions (host network vs bridge) and ensure Open WebUI can reach host Ollama.
3) Review LiteLLM config: confirm vision route includes model capability metadata; ensure env vars are correct.
4) Security hardening:
   - remove `privileged: true` if possible and suggest least-privilege alternatives
   - ensure no secrets are hardcoded; use .env/.env.example patterns
   - review FastAPI auth implementation
   - improve denylist/policy controls
5) Reliability:
   - add timeouts/retries where appropriate
   - ensure MJPEG snapshot extraction closes streams
   - improve error messages and logging
6) Output:
   - a unified diff patch
   - an updated README with end-to-end deployment checklist
   - a test plan with exact commands

Constraints:
- Keep changes minimal and production-practical.
- Don’t invent NanoKVM endpoints beyond login/stream/hid paste unless you can justify with evidence.
