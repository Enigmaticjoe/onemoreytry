# Changelog

All notable changes to **Project Chimera — Grand Unified AI Home Lab** are documented here.
Every entry below corresponds to a merged pull request and is considered **closed** (completed).

---

## [Unreleased]

> Current open work tracked in the active PR.

---

## 2026-03-06

### Added
- **#66** `copilot/revise-node-b-media-config` — Fresh Rebuild 2026 blueprint: phase-1 compose files, deploy/verify scripts, per-node `.env` examples, inventory template, Riven Node B stack, `APPS_AND_SERVICES_GUIDE.md`, `NODE_SETUP_GUIDE.md`, layman's guides, validation tests, and `README` link.
- **#65** `copilot/audit-and-ai-integration-node-b` — Node B audit and AI integration; complete optimised Node B package (`nodebfinal/`) per blueprint.
- **#64** `copilot/add-agent-instruction-framework` — Agent Instruction Framework: tooling, quality gates, and sovereign AI architecture documentation.

---

## 2026-03-05

### Security / Infrastructure
- **#63** `codex/inventory-docker-socket-mounts-and-access-types` — Hardened Docker socket exposure and network defaults across all stacks.

### Documentation
- **#62** `codex/define-canonical-architecture-document` — Established canonical 2026 architecture baseline (`docs/ARCHITECTURE_CANONICAL_2026.md`).

---

## 2026-03-04

### Fixed
- **#60** `copilot/fix-node-a-setup` — Used numeric GIDs in `group_add` to fix render group error in Node A containers.
- **#58** `copilot/fix-docker-not-running` — Auto-install Docker CE in `node-a-vllm/setup.sh` when not found or not running.

### Changed
- **#59** `copilot/switch-to-tailscale-installation` — Switched all remote connections from SSH/LAN IPs to Tailscale IPs via `resolve_node_ip()`.

---

## 2026-03-03

### Fixed
- **#57** `copilot/fix-openclaw-error` — Fixed OpenClaw "origin not allowed" error by adding `allowedOrigins` to `controlUi`.

### Infrastructure
- **#53** `codex/rewrite-install-script-for-local-fedora-install` — Rewrote Node C OpenClaw installer for Fedora local turnkey deployment.
- **#52** `copilot/remove-github-install-scripts` — Removed GitHub download/clone connections from scripts.

### Changed
- **#51** `copilot/review-bos-python-files` — `bos.py` Fedora 44 compatibility fixes, smarter interactive TUI, revised AI role from `crawk` to `integrator`.
- **#50** `revert-49-copilot/rewrite-node-a-c-docs-scripts` — Reverted Node A/C Fedora 44 hardening pass (PR #49) due to regressions.
- **#49** `copilot/rewrite-node-a-c-docs-scripts` — Node A/C Fedora 44 hardening pass: docs, compose networking, retry logic *(reverted by #50)*.

---

## 2026-03-02

### Changed
- **#48** `copilot/revise-files-for-fedora-44` — Updated Nodes A and C from Fedora 43 to Fedora 44 (cosmic nightly) across all repository files.

---

## 2026-03-01

### Infrastructure / CI
- **#47** `copilot/configure-actions-setup-steps` — Added harden-runner firewall after setup steps with PyPI allowlist.
- **#46** `copilot/revise-repo-files-and-scripts` — Added CI workflow, Python invariant tests, `ARCHITECTURE.md`, Unraid media+AI stacks, and updated agent instructions.

### Documentation
- **#45** `copilot/update-project-chimera-docs` — Updated Copilot instructions and revised agent role and operating principles.
- **#44** `copilot/move-directory-and-content` — Moved and reorganised directory content.

### Added
- **#43** `copilot/revise-node-a-installation-scripts` — Implemented Brain Project Node A stack: vLLM + OpenWebUI + RAG + SearXNG + hardware agents; addressed code review issues.

---

## 2026-02-28

### Added
- **#42** `copilot/upgrade-bos-installer-experience` — Upgraded `bos.py` to an OS-like menu-driven installer with local AI chatbot; removed caregiver PIN, added all-node Portainer install, expanded node deployments.
- **#41** `copilot/finalize-installer-hmi-implementation` — Implemented Brothers Keeper installer, API server, kiosk HMI, systemd services, and layman's guide.
- **#40** `copilot/finalize-brothers-keeper-installer` — Finalized Brothers Keeper installer (initial file uploads).

---

## 2026-02-26

### Added
- **#39** `codex/create-folder-with-portainer-build-and-guide` — Added Portainer BE edge-build package for Nodes A/B/C and a comprehensive `PORTAINER_GUIDE.md`.

---

## 2026-02-25

### Added / Fixed
- **#38** `claude/test-ai-installer-kvm-ozW5M` — AI installer and KVM integration test pass.
- **#37** `copilot/code-review-session` — Code-review session: tightened security, reduced duplication, improved error handling.

---

## 2026-02-22

### Added
- **#36** `copilot/create-env-file-script` — Added `scripts/setup-env.sh` for atomic env-file generation.
- **#35** `copilot/list-installed-containers` — Added container inventory helper script.
- **#34** `copilot/create-laymens-guides-again` — Recreated layman's guides (clean pass after revert).
- **#33** `copilot/create-ai-assistant-installer` — Created AI assistant installer (Python/Flask chat server).
- **#32** `copilot/create-laymens-guides` — Created initial set of layman's guides.
- **#31** `copilot/update-homepage-ecosystem` — Updated Homepage ecosystem configuration.
- **#30** `copilot/review-brain-node-setup` — Reviewed and corrected Brain Node A setup configuration.
- **#29** `claude/portainer-deploy-guide-OMpDK` — Added Portainer deployment guide.
- **#28** `copilot/fix-missing-node-d` — Fixed missing Node D configuration.
- **#27** `copilot/fix-permission-errors` — Fixed file permission errors across scripts.
- **#26** `copilot/fix-ssh-auth-issue` — Fixed SSH authentication issue in deployment scripts.
- **#25** `copilot/install-openclaw-node-c` — Added OpenClaw installation guide and scripts for Node C.
- **#24** `copilot/revise-portainer-install-scripts` — Revised Portainer install scripts.

---

## 2026-02-21

### Infrastructure
- **#23** `copilot/setup-copilot-instructions-again` — Re-established Copilot coding agent instructions.
- **#21** `copilot/refactor-deployment-framework-scripts` — Refactored deployment framework scripts for robustness and idempotency.
- **#20** `copilot/add-openclaw-installation-guide` — Added OpenClaw installation guide.
- **#19** `codex/fix-deploy-all.sh-and-other-scripts` — Fixed `deploy-all.sh` and related orchestration scripts.
- **#18** `claude/update-network-config-PfiCQ` — Updated network configuration (patch 2).
- **#17** `claude/update-network-config-PfiCQ` — Updated network configuration (patch 1).

---

## 2026-02-20

### Added / Documentation
- **#16** `codex/create-comprehensive-installation-guide` — Created comprehensive installation guide (`DEPLOYMENT_GUIDE.md`).
- **#15** `copilot/create-unified-guidebook` — Created unified guidebook (`GUIDEBOOK.md` / `UNIFIED_GUIDEBOOK.md`).
- **#14** `claude/rewrite-node-vision-system-cgTsN` — Rewrote Node C vision system configuration (Intel Arc / Llava).
- **#13** `copilot/add-desktop-icon-launcher` — Added Node A desktop icon launcher (`install-desktop-icon.sh`).
- **#12** `copilot/setup-copilot-instructions` — Set up Copilot coding agent instructions.
- **#10** `copilot/integrate-nanokvm-openclaw` — Integrated NanoKVM with OpenClaw on Node A.
- **#9** `copilot/review-docker-compose-and-config` — Reviewed and improved Docker Compose files and config.
- **#8** `claude/openclaw-unraid-stack-f7vrG` — Added OpenClaw Unraid stack configuration.

---

## 2026-02-17

### Added
- **#7** `copilot/create-node-a-folder` — Created Node A folder structure and initial configuration.

---

## 2026-02-16

### Added (Initial)
- **#6** `copilot/set-up-copilot-instructions` — Set up initial Copilot coding agent instructions.
- **#4** `copilot/optimize-node-a-setup` — Optimised Node A setup configuration.
- **#3** `copilot/create-docker-compose-lab` — Created Docker Compose lab configuration.
- **#1** `copilot/configure-docker-compose-lab` — Initial repository bootstrap: configured Docker Compose multi-node lab.

---

*All entries above represent merged pull requests and are **closed**.*
