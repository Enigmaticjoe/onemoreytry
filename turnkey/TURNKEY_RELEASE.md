# Turnkey release (Node A + Node C)

## 1) Node C local deployment (Fedora 44+)
1. Copy `turnkey/stacks/node-c-openclaw-compose.yml` to `/opt/openclaw/homelab/openclaw.yml`.
2. Copy `turnkey/node-c/.env.template` to `/opt/openclaw/.env`, then set real tokens/IPs.
3. Copy `node-c-arc/openclaw.json` to `/opt/openclaw/config/openclaw.json`.
4. Start:
   `docker compose -f /opt/openclaw/homelab/openclaw.yml --env-file /opt/openclaw/.env up -d`

## 2) Node A KVM operator container deployment
1. Copy `turnkey/node-a/kvm-operator.env.template` to `turnkey/stacks/kvm-operator.env`, update values.
2. Deploy:
   `cd turnkey/stacks && docker compose -f node-a-kvm-operator-compose.yml up -d`
3. Verify:
   `curl -fsS http://NODE_A_IP:5000/health`

## 3) Prompt bootstrap JSON
- Node C: `turnkey/node-c/agent-prompt.json`
- Node A: `turnkey/node-a/agent-prompt.json`

## 4) Automation best-practice defaults
- Keep `REQUIRE_APPROVAL=true` on KVM writes.
- Use non-root Docker where possible; only OpenClaw runtime requires root container user.
- Pin production images by digest after validating latest release checks.
- Schedule nightly health + weekly security audits from your orchestrator.
