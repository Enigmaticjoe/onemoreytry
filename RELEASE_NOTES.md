# Boss-Driven Homelab Install Assistant v2.0.0 — Release Notes

## Target Platform
- **Fedora 44** (cosmic nightly — GNOME 50 / Wayland / SELinux Enforcing)
- **DNF5 exclusively** (no dnf4/yum fallback)
- **Python 3.14** (PEP 668 compliant)

---

## Critical Bug Fixes

### 1. DNF5 Syntax Corrected
| Issue | Old (Broken) | New (Fixed) |
|-------|-------------|-------------|
| Repo add command | `dnf config-manager addrepo --from-repofile URL` (space) | `dnf5 config-manager addrepo --from-repofile=URL` (equals sign) |
| Plugins package | `dnf-plugins-core` (DNF4 legacy) | `dnf5-plugins` (ships by default on F44) |
| Fallback logic | Falls back to `dnf` if `dnf5` missing | Requires `dnf5` — fails fast with clear error |

### 2. PEP 668 — Externally Managed Environment
**Old:** `python3 -m pip install flask beautifulsoup4` → **crashes on Fedora 44** with `externally-managed-environment` error.

**New:** Creates a dedicated venv at `/opt/homelab/venv`, installs Flask + bs4 + gunicorn inside it. System Python untouched.

### 3. Type Annotation Fix
**Old:** `def run_command(...) -> (int, str):` — invalid syntax in Python 3.10+, rejected by type checkers.  
**New:** `def run_cmd(...) -> Tuple[int, str]:`

### 4. Argparse Crash
**Old:** `ArgumentParser(add_help=False)` then manually added `--help` action — causes a conflict crash.  
**New:** Uses standard `ArgumentParser()` with built-in help. Added `--version`, `--chat-only`, `--install-service` flags.

### 5. DuckDuckGo Scraping Brittleness
**Old:** Scraped `duckduckgo.com/html/` which frequently changes HTML structure.  
**New:** Uses DuckDuckGo **Lite** (`lite.duckduckgo.com/lite/`) which has a more stable DOM. Searches for both `result-link` and `result__a` CSS classes for resilience.

### 6. Dead Code Removed
- Python 2 `urllib2` / `urllib` fallback removed (F44 ships Python 3.14)
- Unreachable code paths cleaned up

---

## New Features

### One-Click Bootstrap (`install.sh`)
```bash
curl -fsSL https://raw.githubusercontent.com/Enigmaticjoe/onemoreytry/main/install.sh | sudo bash
```
- Validates Fedora 44 + dnf5 before doing anything
- Checks SELinux status (warns if not Enforcing)
- Installs only bootstrap deps, then hands off to Python installer
- Passes through all CLI arguments (`--non-interactive`, etc.)

### Systemd Service (`--install-service`)
```bash
sudo python3 boss_multi_agent_install.py --non-interactive --auto-start-chat --install-service
```
- Creates `/etc/systemd/system/homelab-assistant.service`
- Auto-starts on boot after Docker
- Restarts on failure (5s delay)
- Logs to journald: `journalctl -u homelab-assistant -f`

### Chat-Only Mode (`--chat-only`)
```bash
sudo python3 boss_multi_agent_install.py --chat-only
```
Skips all installation tasks, just launches the web chat server. Useful after initial setup.

### Firewall Integration
Automatically opens port 8008/tcp in firewalld when starting the chat server.

### Improved Security
- All `.env` files written with `0600` permissions (was world-readable)
- SELinux context restored via `restorecon` after every file write
- Secrets masked in interactive prompts via `getpass`

### Enhanced Chat UI
- WCAG-compliant ARIA roles and labels throughout
- Animated progress bar with `role="progressbar"`
- Keyboard focus management (Enter to send)
- Screen-reader-friendly `aria-live="polite"` message log
- `sr-only` class for accessible labels
- Fade-in animation on new messages
- Responsive layout with proper box-sizing

---

## Architecture Changes

| Aspect | v1 (Original) | v2 (This Release) |
|--------|--------------|-------------------|
| Package manager | dnf5 with dnf fallback | dnf5 only (F44 requirement) |
| Python deps | System pip (`pip install`) | Venv at `/opt/homelab/venv` |
| Logging | `print()` with manual timestamps | `logging` module with levels |
| File permissions | Default (world-readable) | `0600` for secrets, `0644` for config |
| SELinux | Ignored | `restorecon` after writes |
| Firewall | Manual | Auto `firewall-cmd` |
| Service | Manual process | Systemd unit file |
| CLI | Basic `--non-interactive` | Full argparse with `--version`, `--chat-only`, `--install-service` |
| Web search | DuckDuckGo HTML (brittle) | DuckDuckGo Lite (stable) |
| HTML | Inline string interpolation | `json.dumps()` for safe JS injection |
| Error handling | Silent catches | Structured logging + raise |

---

## File Structure
```
onemoreytry/
├── install.sh                      # One-click bootstrap (bash)
├── boss_multi_agent_install.py     # Main installer (python3)
├── chat/
│   └── index.html                  # Generated at runtime
└── config/
    ├── node-inventory.env          # Generated
    └── api.env                     # Generated (optional)
```

---

## CLI Reference

```
usage: boss_multi_agent_install.py [-h] [--non-interactive] [--config-file FILE]
                                    [--auto-start-chat] [--install-service]
                                    [--chat-only] [--repo-url URL]
                                    [--dest-dir DIR] [--version]

Options:
  --non-interactive    Run unattended (defaults + env vars + config file)
  --config-file FILE   JSON or .env file for non-interactive mode
  --auto-start-chat    Launch chat server after install completes
  --install-service    Create + enable systemd service
  --chat-only          Skip install, just run chat server
  --repo-url URL       Override git repo (default: onemoreytry)
  --dest-dir DIR       Override clone destination
  --version            Show version and exit
```

---

## Deployment Modes

### Interactive (guided)
```bash
sudo python3 boss_multi_agent_install.py
```

### Fully Automated
```bash
sudo python3 boss_multi_agent_install.py \
  --non-interactive \
  --config-file /path/to/homelab.env \
  --auto-start-chat \
  --install-service
```

### Container
```dockerfile
FROM fedora:44
RUN dnf5 install -y python3 python3-pip git curl && dnf5 clean all
COPY boss_multi_agent_install.py /opt/homelab/
EXPOSE 8008 8123
ENTRYPOINT ["python3", "/opt/homelab/boss_multi_agent_install.py", \
            "--non-interactive", "--auto-start-chat"]
```

### OVA/VM
Use `virt-builder` or Packer with the bootstrap script baked into cloud-init.
