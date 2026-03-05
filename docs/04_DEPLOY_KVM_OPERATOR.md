# Deploy the AI KVM Operator service (FastAPI)

> Canonical architecture authority: [`docs/ARCHITECTURE_CANONICAL_2026.md`](ARCHITECTURE_CANONICAL_2026.md).


Install (recommended):
  sudo mkdir -p /opt/kvm-operator
  sudo cp -r kvm-operator/* /opt/kvm-operator/
  cd /opt/kvm-operator
  cp .env.example .env
  # edit .env: tokens + KVM IPs + LiteLLM URL/key

  python3 -m venv .venv
  source .venv/bin/activate
  pip install -r requirements.txt

Run:
  source .env
  uvicorn app:app --host 0.0.0.0 --port 5000

systemd:
  sudo cp systemd/ai-kvm-operator.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now ai-kvm-operator

Smoke test:
  curl -fsS http://localhost:5000/health
  curl -sS -X POST http://localhost:5000/kvm/task/node-c \
    -H "Authorization: Bearer $KVM_OPERATOR_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"instruction":"Describe the screen. If it is a login prompt, type username then password and press Enter. If logged in, respond success.","max_steps":3}'

Safety reality check:
  - denylist checks are helpful but incomplete against prompt-driven command generation
  - keep REQUIRE_APPROVAL=true for routine operation
  - only set ALLOW_DANGEROUS=true as a temporary break-glass action
