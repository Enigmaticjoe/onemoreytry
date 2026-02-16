# Security guidance (must-read)

Your blueprint warns that AI console control is high risk and recommends human-in-the-loop safeguards and low temperature sampling.

This bundle adds:
- Bearer token auth for the operator API
- denylist for destructive commands
- REQUIRE_APPROVAL=true by default

Recommended:
- isolate NanoKVM traffic on a restricted VLAN
- rotate ALL secrets (LiteLLM master key, operator token, NanoKVM admin password)
