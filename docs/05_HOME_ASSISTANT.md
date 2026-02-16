# Home Assistant wiring

1) Point extended_openai_conversation at LiteLLM:
- base_url: http://node-b-litellm:4000/v1
- api_key: your LITELLM_MASTER_KEY
- model: brawn-fast

2) Trigger KVM tasks via shell_command
See home-assistant/configuration.yaml.snippet

Security:
- Keep tokens in secrets.yaml
- Keep the operator API on a trusted VLAN
