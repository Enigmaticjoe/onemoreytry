# NanoKVM Operator Skill

> Skill ID: `skill-kvm` | File: `openclaw/skill-kvm.md`

Control NanoKVM Cube KVM-over-IP devices through the AI KVM Operator service.

## Overview

This skill lets agents observe and control remote computers over IP using NanoKVM Cube
hardware. It routes requests through the `kvm-operator` FastAPI service, which enforces
a **dual-path design**:

- **Read path** — snapshot, status, power state: executed immediately, no approval gate.
- **Write path** — power control, keyboard, mouse, vision tasks: gated by `REQUIRE_APPROVAL`.

## Prerequisites

1. Deploy the `kvm-operator` service (see `kvm-operator/run_dev.sh` or `systemd/ai-kvm-operator.service`).
2. Set `KVM_OPERATOR_URL` and `KVM_OPERATOR_TOKEN` in OpenClaw's environment.
3. The operator must be able to reach your NanoKVM device(s) at their LAN IPs.

## Environment Variables

| Variable | Example | Purpose |
|---|---|---|
| `KVM_OPERATOR_URL` | `http://192.168.1.222:5000` | Base URL of the kvm-operator service |
| `KVM_OPERATOR_TOKEN` | `abc123...` | Bearer token (matches `KVM_OPERATOR_TOKEN` on the operator) |

## API Reference

All requests use: `Authorization: Bearer $KVM_OPERATOR_TOKEN`

### Read Endpoints (No Approval Required)

#### Health check
```
GET $KVM_OPERATOR_URL/health
```
Returns service status and list of configured KVM targets.

#### Capture screenshot
```
GET $KVM_OPERATOR_URL/kvm/snapshot/{target}
```
Returns `{ "ok": true, "jpeg_b64": "<base64 JPEG>" }`.
Use this to see what is currently on the remote screen before deciding on an action.

#### VM info
```
GET $KVM_OPERATOR_URL/kvm/status/{target}
```
Returns NanoKVM device info from `GET /api/vm/info` (OS, version, uptime).

#### Power state
```
GET $KVM_OPERATOR_URL/kvm/power/{target}
```
Returns current ATX power state from `GET /api/vm/power`.

### Write Endpoints (Approval Gated)

> These return HTTP 202 when `REQUIRE_APPROVAL=true` on the operator service.
> Set `REQUIRE_APPROVAL=false` for headless/automated operation.

#### AI vision task (natural-language loop)
```
POST $KVM_OPERATOR_URL/kvm/task/{target}
Content-Type: application/json

{
  "instruction": "Open a terminal and run: docker ps",
  "max_steps": 5
}
```
Repeatedly captures a screenshot, asks the vision LLM what action to take, and
executes it (type/wait/abort/success). Useful for multi-step automation.

#### Power control
```
POST $KVM_OPERATOR_URL/kvm/power/{target}
Content-Type: application/json

{ "action": "reset" }
```
Valid actions: `on`, `off`, `reset`, `force-off`.

#### Raw keyboard input
```
POST $KVM_OPERATOR_URL/kvm/keyboard/{target}
Content-Type: application/json

{ "key": "ctrl+c", "modifiers": [] }
```
Sends a key event via `POST /api/hid/keyboard`. Destructive key sequences
(matching `policy_denylist.txt`) are blocked regardless of approval setting.

#### Mouse move / click / scroll
```
POST $KVM_OPERATOR_URL/kvm/mouse/{target}
Content-Type: application/json

{ "x": 640, "y": 400, "button": 1, "wheel": 0 }
```
`button` bitmask: 0=none, 1=left, 2=right, 4=middle.

#### Text paste (fastest way to type a string)
```
POST $KVM_OPERATOR_URL/kvm/task/{target}    ← vision loop
```
Or use HID paste directly via `POST /api/hid/paste` if the operator exposes it.

## Example Workflow

```
1. GET /kvm/power/node-c          → check if machine is on
2. GET /kvm/snapshot/node-c       → see current screen
3. POST /kvm/task/node-c          → ask vision AI to complete a task
4. GET /kvm/snapshot/node-c       → verify the result
```

## Security Notes

- Never expose the kvm-operator to the internet without authentication.
- The NanoKVM login password is AES-256-CBC encrypted before transmission
  (hardcoded key — see GitHub Issue #270 for security implications).
- Keep `REQUIRE_APPROVAL=true` unless running fully automated pipelines.
- The `policy_denylist.txt` blocks destructive commands even in headless mode.
