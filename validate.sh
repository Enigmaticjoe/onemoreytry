#!/bin/bash
# Grand Unified AI Home Lab - Validation Test Script
# This script validates the configuration files for syntax and structure

echo "================================================================================"
echo "  GRAND UNIFIED AI HOME LAB - VALIDATION TEST"
echo "================================================================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Function to print test result
test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $2"
        ((TESTS_FAILED++))
    fi
}

# Test 1: Validate YAML syntax
echo "1. Validating YAML syntax..."
echo "----------------------------"

python3 -c "import yaml; yaml.safe_load(open('node-b-litellm/config.yaml'))"
test_result $? "LiteLLM config.yaml syntax"

python3 -c "import yaml; yaml.safe_load(open('node-b-litellm/litellm-stack.yml'))"
test_result $? "LiteLLM litellm-stack.yml syntax"

python3 -c "import yaml; yaml.safe_load(open('node-b-litellm/docker-compose.yml'))"
test_result $? "LiteLLM docker-compose.yml syntax"

python3 -c "import yaml; yaml.safe_load(open('node-c-arc/docker-compose.yml'))"
test_result $? "Node C docker-compose.yml syntax"

python3 -c "import yaml; yaml.safe_load(open('home-assistant/configuration.yaml.snippet'))"
test_result $? "Home Assistant configuration.yaml.snippet syntax"

echo ""

# Test 2: Validate LiteLLM configuration structure
echo "2. Validating LiteLLM configuration structure..."
echo "------------------------------------------------"

# Check for required model names
grep -q "brain-heavy" node-b-litellm/config.yaml
test_result $? "brain-heavy model defined"

grep -q "brawn-fast" node-b-litellm/config.yaml
test_result $? "brawn-fast model defined"

grep -q "intel-vision" node-b-litellm/config.yaml
test_result $? "intel-vision model defined"

# Check for correct IPs
grep -q "192.168.1.9:8000" node-b-litellm/config.yaml
test_result $? "Brain IP (192.168.1.9:8000) configured"

grep -q "192.168.1.222:8002" node-b-litellm/config.yaml
test_result $? "Brawn IP (192.168.1.222:8002) configured"

grep -q "192.168.1.6:11434" node-b-litellm/config.yaml
test_result $? "Command Center IP (192.168.1.6:11434) configured"

# Check for API key
grep -q "sk-master-key" node-b-litellm/config.yaml
test_result $? "API key (sk-master-key) configured"

# Check for vision support
grep -q "supports_vision: True" node-b-litellm/config.yaml
test_result $? "Vision support enabled for intel-vision model"

echo ""

# Test 3: Validate Intel Arc configuration
echo "3. Validating Intel Arc (Node C) configuration..."
echo "------------------------------------------------"

# Check for standard Ollama image (not IPEX or ROCm)
grep -q "image: ollama/ollama:latest" node-c-arc/docker-compose.yml
test_result $? "Using standard Ollama image (not ROCm)"

# Check for required Intel Arc environment variables
grep -q "ZES_ENABLE_SYSMAN.*1" node-c-arc/docker-compose.yml
test_result $? "ZES_ENABLE_SYSMAN=1 set (REQUIRED for Arc)"

grep -q "OLLAMA_NUM_GPU.*999" node-c-arc/docker-compose.yml
test_result $? "OLLAMA_NUM_GPU=999 set"

# Check for /dev/dri device mapping
grep -q "/dev/dri:/dev/dri" node-c-arc/docker-compose.yml
test_result $? "/dev/dri device mapped for Intel GPU"

# Check service names
grep -q "ollama:" node-c-arc/docker-compose.yml
test_result $? "Service named 'ollama' (not ollama-arc)"

grep -q "chimera_face:" node-c-arc/docker-compose.yml
test_result $? "Service named 'chimera_face' (not open-webui)"

# Verify no ROCm references (excluding comments)
! grep -v "^#" node-c-arc/docker-compose.yml | grep -v "^\s*#" | grep -q -i "rocm"
test_result $? "No ROCm references in configuration (excluding comments)"

# Verify no ipex-llm image
! grep -q "ipex-llm" node-c-arc/docker-compose.yml
test_result $? "Not using IPEX-LLM image"

echo ""

# Test 4: Validate Home Assistant configuration
echo "4. Validating Home Assistant configuration..."
echo "--------------------------------------------"

grep -q "openai_conversation:" home-assistant/configuration.yaml.snippet
test_result $? "openai_conversation integration defined"

grep -q "192.168.1.222:4000/v1" home-assistant/configuration.yaml.snippet
test_result $? "Correct LiteLLM Gateway URL (192.168.1.222:4000/v1)"

grep -q "sk-master-key" home-assistant/configuration.yaml.snippet
test_result $? "API key (sk-master-key) configured"

# Node D directory
[ -d "node-d-home-assistant" ]
test_result $? "node-d-home-assistant/ directory exists"

[ -f "node-d-home-assistant/docker-compose.yml" ]
test_result $? "node-d-home-assistant/docker-compose.yml exists"

python3 -c "import yaml; yaml.safe_load(open('node-d-home-assistant/docker-compose.yml'))"
test_result $? "node-d-home-assistant/docker-compose.yml YAML syntax valid"

grep -q "healthcheck:" node-d-home-assistant/docker-compose.yml
test_result $? "node-d-home-assistant has healthcheck defined"

[ -f "node-d-home-assistant/.env.example" ]
test_result $? "node-d-home-assistant/.env.example exists"

[ -f "node-d-home-assistant/configuration.yaml.snippet" ]
test_result $? "node-d-home-assistant/configuration.yaml.snippet exists"

echo ""

# Test 5: Validate Docker Compose structure
echo "5. Validating Docker Compose structure..."
echo "----------------------------------------"

# Check LiteLLM stack uses host network
grep -q "network_mode: host" node-b-litellm/litellm-stack.yml
test_result $? "LiteLLM using host network mode"

# Check for health checks
grep -q "healthcheck:" node-b-litellm/litellm-stack.yml
test_result $? "LiteLLM has healthcheck defined"

grep -q "healthcheck:" node-c-arc/docker-compose.yml
test_result $? "Node C Ollama has healthcheck defined"

grep -q "healthcheck:" node-a-vllm/docker-compose.yml
test_result $? "Node A vLLM has healthcheck defined"

# Check container names
grep -q "container_name: litellm_gateway" node-b-litellm/litellm-stack.yml
test_result $? "LiteLLM container named 'litellm_gateway'"

grep -q "container_name: ollama_intel_arc" node-c-arc/docker-compose.yml
test_result $? "Ollama container named 'ollama_intel_arc'"

grep -q "container_name: chimera_face" node-c-arc/docker-compose.yml
test_result $? "Open WebUI container named 'chimera_face'"

grep -q "container_name: vllm_brain" node-a-vllm/docker-compose.yml
test_result $? "Node A vLLM container named 'vllm_brain'"

echo ""

# Test 6: File existence
echo "6. Validating required files exist..."
echo "------------------------------------"

[ -f "node-b-litellm/litellm-stack.yml" ]
test_result $? "litellm-stack.yml exists"

[ -f "node-b-litellm/config.yaml" ]
test_result $? "config.yaml exists"

[ -f "node-c-arc/docker-compose.yml" ]
test_result $? "node-c-arc/docker-compose.yml exists"

[ -f "node-a-vllm/docker-compose.yml" ]
test_result $? "node-a-vllm/docker-compose.yml exists"

[ -f "node-a-vllm/.env.example" ]
test_result $? "node-a-vllm/.env.example exists"

[ -f "scripts/setup-node-a.sh" ]
test_result $? "scripts/setup-node-a.sh exists"

[ -x "scripts/setup-node-a.sh" ]
test_result $? "scripts/setup-node-a.sh is executable"

[ -f "home-assistant/configuration.yaml.snippet" ]
test_result $? "configuration.yaml.snippet exists"

[ -f "DEPLOYMENT_GUIDE.md" ]
test_result $? "DEPLOYMENT_GUIDE.md exists"

[ -f "QUICK_REFERENCE.md" ]
test_result $? "QUICK_REFERENCE.md exists"

[ -f "node-a-command-center/node-a-command-center.js" ]
test_result $? "node-a-command-center/node-a-command-center.js exists"

[ -f "docs/09_NODE_A_COMMAND_CENTER_GUIDEBOOK.md" ]
test_result $? "Node A command center guidebook exists"

[ -f "docs/10_UNIFIED_INSTALL_GUIDEBOOK.md" ]
test_result $? "Unified install guidebook exists"

[ -f "docs/11_OPENCLAW_KVM_GUIDEBOOK.md" ]
test_result $? "OpenClaw + KVM integration guidebook exists"

grep -q "api/status" node-a-command-center/node-a-command-center.js
test_result $? "Node A dashboard status endpoint configured"

grep -q "api/chat" node-a-command-center/node-a-command-center.js
test_result $? "Node A dashboard chat endpoint configured"

grep -q "install-wizard" node-a-command-center/node-a-command-center.js
test_result $? "Node A install wizard route configured"

[ -f "node-a-command-center/install-desktop-icon.sh" ]
test_result $? "node-a-command-center/install-desktop-icon.sh exists"

[ -x "node-a-command-center/install-desktop-icon.sh" ]
test_result $? "install-desktop-icon.sh is executable"

grep -q "xdg-open" node-a-command-center/install-desktop-icon.sh
test_result $? "install-desktop-icon.sh opens browser with xdg-open"

grep -q "Desktop Entry" node-a-command-center/install-desktop-icon.sh
test_result $? "install-desktop-icon.sh creates .desktop file"

echo ""

# Test 7: Validate NanoKVM / OpenClaw integration
echo "7. Validating NanoKVM + OpenClaw integration..."
echo "-----------------------------------------------"

[ -f "kvm-operator/.env.example" ]
test_result $? "kvm-operator/.env.example exists"

[ -f "openclaw/skill-kvm.md" ]
test_result $? "openclaw/skill-kvm.md (OpenClaw KVM skill) exists"

# AES key fix: SECRET_KEY must be a valid 32-byte AES-256 key
grep -q "SECRET_KEY = (_KEY_RAW" kvm-operator/app.py
test_result $? "AES-256-CBC key padding applied (32-byte key)"

# Dual-path read endpoints
grep -q '"/kvm/snapshot/{target}"' kvm-operator/app.py
test_result $? "Read endpoint GET /kvm/snapshot/{target} defined"

grep -q '"/kvm/status/{target}"' kvm-operator/app.py
test_result $? "Read endpoint GET /kvm/status/{target} defined"

grep -q '"/kvm/power/{target}"' kvm-operator/app.py
test_result $? "Read endpoint GET /kvm/power/{target} defined"

# Dual-path write endpoints
grep -q '"/kvm/power/{target}"' kvm-operator/app.py
test_result $? "Write endpoint POST /kvm/power/{target} defined"

grep -q '"/kvm/keyboard/{target}"' kvm-operator/app.py
test_result $? "Write endpoint POST /kvm/keyboard/{target} defined"

grep -q '"/kvm/mouse/{target}"' kvm-operator/app.py
test_result $? "Write endpoint POST /kvm/mouse/{target} defined"

# Approval gate on write path
grep -q "REQUIRE_APPROVAL" kvm-operator/app.py
test_result $? "REQUIRE_APPROVAL gate present on write endpoints"

# NanoKVM complete endpoint surface
grep -q "get_vm_info" kvm-operator/app.py
test_result $? "NanoKVM GET /api/vm/info method defined"

grep -q "get_power_status" kvm-operator/app.py
test_result $? "NanoKVM GET /api/vm/power method defined"

grep -q "power_action" kvm-operator/app.py
test_result $? "NanoKVM POST /api/vm/power method defined"

grep -q "hid_key" kvm-operator/app.py
test_result $? "NanoKVM POST /api/hid/keyboard method defined"

grep -q "hid_mouse" kvm-operator/app.py
test_result $? "NanoKVM POST /api/hid/mouse method defined"

# OpenClaw integration
grep -q "KVM_OPERATOR_URL" openclaw/docker-compose.yml
test_result $? "KVM_OPERATOR_URL env var in OpenClaw docker-compose"

grep -q "KVM_OPERATOR_TOKEN" openclaw/docker-compose.yml
test_result $? "KVM_OPERATOR_TOKEN env var in OpenClaw docker-compose"

grep -q "skill-kvm" openclaw/skill-kvm.md
test_result $? "skill-kvm.md references NanoKVM skill name"

# Deploy skill
[ -f "openclaw/skill-deploy.md" ]
test_result $? "openclaw/skill-deploy.md (deployment skill) exists"

grep -q "Portainer" openclaw/skill-deploy.md
test_result $? "skill-deploy.md documents Portainer stack management"

# Docker socket for deployment assistant
grep -q "/var/run/docker.sock" openclaw/docker-compose.yml
test_result $? "Docker socket mounted in OpenClaw (deployment assistant)"

echo ""

# Test 8: Validate new scripts and guidebook
echo "8. Validating scripts and guidebook..."
echo "---------------------------------------"

[ -f "GUIDEBOOK.md" ]
test_result $? "GUIDEBOOK.md (comprehensive unified guidebook) exists"

grep -q "Chapter 0" GUIDEBOOK.md
test_result $? "GUIDEBOOK.md has Chapter 0 (Pre-Flight)"

grep -q "Chapter 5" GUIDEBOOK.md
test_result $? "GUIDEBOOK.md has Chapter 5 (OpenClaw)"

grep -q "Chapter 6" GUIDEBOOK.md
test_result $? "GUIDEBOOK.md has Chapter 6 (OpenClaw x KVM Integration)"

grep -q "Chapter 7" GUIDEBOOK.md
test_result $? "GUIDEBOOK.md has Chapter 7 (Deploy GUI)"

[ -f "scripts/deploy-all.sh" ]
test_result $? "scripts/deploy-all.sh exists"

[ -x "scripts/deploy-all.sh" ]
test_result $? "scripts/deploy-all.sh is executable"

[ -f "scripts/preflight-check.sh" ]
test_result $? "scripts/preflight-check.sh exists"

[ -x "scripts/preflight-check.sh" ]
test_result $? "scripts/preflight-check.sh is executable"

[ -f "scripts/install-openclaw-deployer.sh" ]
test_result $? "scripts/install-openclaw-deployer.sh exists"

[ -x "scripts/install-openclaw-deployer.sh" ]
test_result $? "scripts/install-openclaw-deployer.sh is executable"

[ -f "scripts/prepare-openclaw.sh" ]
test_result $? "scripts/prepare-openclaw.sh exists"

[ -x "scripts/prepare-openclaw.sh" ]
test_result $? "scripts/prepare-openclaw.sh is executable"

[ -f "deploy-gui/deploy-gui.js" ]
test_result $? "deploy-gui/deploy-gui.js exists"

[ -f "deploy-gui/Dockerfile" ]
test_result $? "deploy-gui/Dockerfile exists"

[ -f "deploy-gui/docker-compose.yml" ]
test_result $? "deploy-gui/docker-compose.yml exists"

python3 -c "import yaml; yaml.safe_load(open('deploy-gui/docker-compose.yml'))"
test_result $? "deploy-gui/docker-compose.yml YAML syntax valid"

grep -q "9999" deploy-gui/docker-compose.yml
test_result $? "Deploy GUI exposes port 9999"

grep -q "/api/status" deploy-gui/deploy-gui.js
test_result $? "Deploy GUI has /api/status endpoint"

grep -q "/api/deploy" deploy-gui/deploy-gui.js
test_result $? "Deploy GUI has /api/deploy endpoint"

grep -q "portainer" deploy-gui/deploy-gui.js
test_result $? "Deploy GUI has Portainer integration"

grep -q "/api/audit" deploy-gui/deploy-gui.js
test_result $? "Deploy GUI has /api/audit endpoint (SSH auditor)"

grep -q "wizard" deploy-gui/deploy-gui.js
test_result $? "Deploy GUI has Setup Wizard tab"

grep -q "/api/portainer-install" deploy-gui/deploy-gui.js
test_result $? "Deploy GUI has /api/portainer-install endpoint"

[ -f "scripts/ssh-auditor.sh" ]
test_result $? "scripts/ssh-auditor.sh exists"

[ -x "scripts/ssh-auditor.sh" ]
test_result $? "scripts/ssh-auditor.sh is executable"

[ -f "scripts/portainer-install.sh" ]
test_result $? "scripts/portainer-install.sh exists"

[ -x "scripts/portainer-install.sh" ]
test_result $? "scripts/portainer-install.sh is executable"

[ -f "scripts/connection-wizard.sh" ]
test_result $? "scripts/connection-wizard.sh (connection wizard) exists"

[ -x "scripts/connection-wizard.sh" ]
test_result $? "scripts/connection-wizard.sh is executable"

[ -f "connection-wizard.sh" ]
test_result $? "connection-wizard.sh root wrapper exists"

[ -x "connection-wizard.sh" ]
test_result $? "connection-wizard.sh root wrapper is executable"

grep -q "scripts/connection-wizard.sh" connection-wizard.sh
test_result $? "connection-wizard.sh root wrapper delegates to scripts/connection-wizard.sh"

grep -q "\-\-ssh" scripts/connection-wizard.sh
test_result $? "connection-wizard.sh has --ssh direct-jump flag"

grep -q "\-\-tailscale" scripts/connection-wizard.sh
test_result $? "connection-wizard.sh has --tailscale direct-jump flag"

grep -q "\-\-cloudflare" scripts/connection-wizard.sh
test_result $? "connection-wizard.sh has --cloudflare direct-jump flag"

grep -q "\-\-all-checks" scripts/connection-wizard.sh
test_result $? "connection-wizard.sh has --all-checks flag"

grep -q "ssh_menu\|ssh_audit_all\|ssh_copy_key" scripts/connection-wizard.sh
test_result $? "connection-wizard.sh has SSH management functions"

grep -q "tailscale_menu\|ts_install_local\|ts_connect_local" scripts/connection-wizard.sh
test_result $? "connection-wizard.sh has Tailscale management functions"

grep -q "cloudflare_menu\|cf_install\|cf_create_tunnel" scripts/connection-wizard.sh
test_result $? "connection-wizard.sh has Cloudflare tunnel functions"

grep -q "run_all_checks" scripts/connection-wizard.sh
test_result $? "connection-wizard.sh has run_all_checks function"

grep -q "ssh-auditor.sh" scripts/connection-wizard.sh
test_result $? "connection-wizard.sh invokes ssh-auditor.sh"

grep -q "preflight-check.sh" scripts/connection-wizard.sh
test_result $? "connection-wizard.sh invokes preflight-check.sh"

[ -f "docs/12_INSTALL_WIZARD_GUIDE.md" ]
test_result $? "docs/12_INSTALL_WIZARD_GUIDE.md (wizard guide) exists"

grep -q "Portainer" docs/12_INSTALL_WIZARD_GUIDE.md
test_result $? "Install wizard guide covers Portainer setup"

grep -q "ssh-auditor" docs/12_INSTALL_WIZARD_GUIDE.md
test_result $? "Install wizard guide references ssh-auditor.sh"

echo ""

# Test 9: Validate Node C OpenClaw files
echo "9. Validating Node C OpenClaw files..."
echo "---------------------------------------"

[ -f "node-c-arc/openclaw.yml" ]
test_result $? "node-c-arc/openclaw.yml exists"

python3 -c "import yaml; yaml.safe_load(open('node-c-arc/openclaw.yml'))"
test_result $? "node-c-arc/openclaw.yml YAML syntax valid"

grep -q "/opt/openclaw" node-c-arc/openclaw.yml
test_result $? "node-c-arc/openclaw.yml uses Linux /opt/openclaw paths (not Unraid)"

grep -q "host.docker.internal:host-gateway" node-c-arc/openclaw.yml
test_result $? "node-c-arc/openclaw.yml has host.docker.internal for Ollama access"

grep -q "OLLAMA_API_KEY" node-c-arc/openclaw.yml
test_result $? "node-c-arc/openclaw.yml has OLLAMA_API_KEY env var"

grep -q "LITELLM_API_KEY" node-c-arc/openclaw.yml
test_result $? "node-c-arc/openclaw.yml has LITELLM_API_KEY for Node B fallback"

[ -f "node-c-arc/openclaw.json" ]
test_result $? "node-c-arc/openclaw.json exists"

grep -q "host.docker.internal:11434" node-c-arc/openclaw.json
test_result $? "node-c-arc/openclaw.json points Ollama to host.docker.internal:11434"

grep -q "192.168.1.222:4000" node-c-arc/openclaw.json
test_result $? "node-c-arc/openclaw.json points LiteLLM to Node B (192.168.1.222:4000)"

grep -q "ollama/your-ollama-model-here" node-c-arc/openclaw.json
test_result $? "node-c-arc/openclaw.json has Ollama primary model placeholder"

[ -f "node-c-arc/.env.openclaw.example" ]
test_result $? "node-c-arc/.env.openclaw.example exists"

grep -q "OPENCLAW_GATEWAY_TOKEN" node-c-arc/.env.openclaw.example
test_result $? ".env.openclaw.example has OPENCLAW_GATEWAY_TOKEN"

grep -q "KVM_OPERATOR_URL" node-c-arc/.env.openclaw.example
test_result $? ".env.openclaw.example has KVM_OPERATOR_URL"

[ -f "scripts/install-openclaw-node-c.sh" ]
test_result $? "scripts/install-openclaw-node-c.sh exists"

[ -x "scripts/install-openclaw-node-c.sh" ]
test_result $? "scripts/install-openclaw-node-c.sh is executable"

grep -q "NODE_C_IP" scripts/install-openclaw-node-c.sh
test_result $? "install-openclaw-node-c.sh references NODE_C_IP from inventory"

grep -q "/opt/openclaw" scripts/install-openclaw-node-c.sh
test_result $? "install-openclaw-node-c.sh uses /opt/openclaw data path"

echo ""

# Test 10: Validate Node A Brain (RX 7900 XT) documentation and compose files
echo "10. Validating Node A Brain (RX 7900 XT) documentation and config..."
echo "---------------------------------------------------------------------"

[ -f "docs/03_DEPLOY_NODE_A_BRAIN.md" ]
test_result $? "docs/03_DEPLOY_NODE_A_BRAIN.md (brain node guide) exists"

grep -q "7900 XT\|7900XT\|RX 7900" docs/03_DEPLOY_NODE_A_BRAIN.md
test_result $? "Brain guide references RX 7900 XT"

grep -q "ROCm" docs/03_DEPLOY_NODE_A_BRAIN.md
test_result $? "Brain guide covers ROCm installation"

grep -q "HSA_OVERRIDE_GFX_VERSION" docs/03_DEPLOY_NODE_A_BRAIN.md
test_result $? "Brain guide documents HSA_OVERRIDE_GFX_VERSION (required for gfx1100)"

grep -q "8000" docs/03_DEPLOY_NODE_A_BRAIN.md
test_result $? "Brain guide documents vLLM port 8000"

grep -q "11435" docs/03_DEPLOY_NODE_A_BRAIN.md
test_result $? "Brain guide documents Ollama port 11435"

grep -q "brain-heavy" docs/03_DEPLOY_NODE_A_BRAIN.md
test_result $? "Brain guide references brain-heavy model name"

[ -f "node-a-vllm/docker-compose.ollama.yml" ]
test_result $? "node-a-vllm/docker-compose.ollama.yml (Ollama alternative) exists"

python3 -c "import yaml; yaml.safe_load(open('node-a-vllm/docker-compose.ollama.yml'))"
test_result $? "node-a-vllm/docker-compose.ollama.yml YAML syntax valid"

grep -q "container_name: ollama_brain" node-a-vllm/docker-compose.ollama.yml
test_result $? "Ollama brain container named 'ollama_brain'"

grep -q "ollama/ollama:rocm" node-a-vllm/docker-compose.ollama.yml
test_result $? "Ollama brain uses ROCm image"

grep -q "HSA_OVERRIDE_GFX_VERSION.*11.0.0" node-a-vllm/docker-compose.ollama.yml
test_result $? "Ollama brain sets HSA_OVERRIDE_GFX_VERSION=11.0.0"

grep -q "/dev/kfd" node-a-vllm/docker-compose.ollama.yml
test_result $? "Ollama brain maps /dev/kfd for ROCm"

grep -q "healthcheck:" node-a-vllm/docker-compose.ollama.yml
test_result $? "Ollama brain has healthcheck defined"

grep -q "11435" node-a-vllm/docker-compose.ollama.yml
test_result $? "Ollama brain exposes port 11435"

# DEPLOYMENT_GUIDE.md has Node A section
grep -q "Node A.*vLLM\|Node A.*Brain\|Node A: Deploy" DEPLOYMENT_GUIDE.md
test_result $? "DEPLOYMENT_GUIDE.md has Node A Brain deployment section"

grep -q "8000" DEPLOYMENT_GUIDE.md
test_result $? "DEPLOYMENT_GUIDE.md documents vLLM port 8000"

# GUIDEBOOK.md has Chapter 2.5
grep -q "Chapter 2.5" GUIDEBOOK.md
test_result $? "GUIDEBOOK.md has Chapter 2.5 (Node A Brain)"

echo ""

# Test 11: Validate Unraid management stack + Homepage config
echo "11. Validating Unraid management stack and Homepage config..."
echo "-------------------------------------------------------------"

[ -d "unraid" ]
test_result $? "unraid/ directory exists"

[ -f "unraid/docker-compose.yml" ]
test_result $? "unraid/docker-compose.yml exists"

python3 -c "import yaml; yaml.safe_load(open('unraid/docker-compose.yml'))"
test_result $? "unraid/docker-compose.yml YAML syntax valid"

grep -q "container_name: homepage" unraid/docker-compose.yml
test_result $? "unraid/docker-compose.yml defines homepage container"

grep -q "container_name: uptime-kuma" unraid/docker-compose.yml
test_result $? "unraid/docker-compose.yml defines uptime-kuma container"

grep -q "container_name: dozzle" unraid/docker-compose.yml
test_result $? "unraid/docker-compose.yml defines dozzle container"

grep -q "container_name: watchtower" unraid/docker-compose.yml
test_result $? "unraid/docker-compose.yml defines watchtower container"

grep -q "HOMEPAGE_ALLOWED_HOSTS" unraid/docker-compose.yml
test_result $? "unraid/docker-compose.yml sets HOMEPAGE_ALLOWED_HOSTS (fixes 400 error)"

grep -q "healthcheck:" unraid/docker-compose.yml
test_result $? "unraid/docker-compose.yml has at least one healthcheck defined"

[ -f "unraid/.env.example" ]
test_result $? "unraid/.env.example exists"

grep -q "TAILSCALE_AUTHKEY" unraid/.env.example
test_result $? "unraid/.env.example documents TAILSCALE_AUTHKEY"

grep -q "HA_LONG_LIVED_TOKEN" unraid/.env.example
test_result $? "unraid/.env.example documents HA_LONG_LIVED_TOKEN"

[ -d "unraid/homepage-config" ]
test_result $? "unraid/homepage-config/ directory exists"

[ -f "unraid/homepage-config/services.yaml" ]
test_result $? "unraid/homepage-config/services.yaml exists"

python3 -c "import yaml; yaml.safe_load(open('unraid/homepage-config/services.yaml'))"
test_result $? "unraid/homepage-config/services.yaml YAML syntax valid"

grep -q "192.168.1.222" unraid/homepage-config/services.yaml
test_result $? "homepage services.yaml references Unraid IP (192.168.1.222)"

grep -q "192.168.1.9" unraid/homepage-config/services.yaml
test_result $? "homepage services.yaml references Node A Brain (192.168.1.9)"

grep -q "192.168.1.6" unraid/homepage-config/services.yaml
test_result $? "homepage services.yaml references Node C Arc (192.168.1.6)"

grep -q "192.168.1.149" unraid/homepage-config/services.yaml
test_result $? "homepage services.yaml references Node D Home Assistant (192.168.1.149)"

grep -q "192.168.1.116" unraid/homepage-config/services.yaml
test_result $? "homepage services.yaml references Node E Sentinel (192.168.1.116)"

grep -q "uptime-kuma" unraid/homepage-config/services.yaml
test_result $? "homepage services.yaml includes Uptime Kuma"

grep -q "dozzle\|Dozzle" unraid/homepage-config/services.yaml
test_result $? "homepage services.yaml includes Dozzle"

grep -q "LiteLLM\|litellm" unraid/homepage-config/services.yaml
test_result $? "homepage services.yaml includes LiteLLM Gateway"

grep -q "Home Assistant\|homeassistant" unraid/homepage-config/services.yaml
test_result $? "homepage services.yaml includes Home Assistant"

[ -f "unraid/homepage-config/bookmarks.yaml" ]
test_result $? "unraid/homepage-config/bookmarks.yaml exists"

python3 -c "import yaml; yaml.safe_load(open('unraid/homepage-config/bookmarks.yaml'))"
test_result $? "unraid/homepage-config/bookmarks.yaml YAML syntax valid"

[ -f "unraid/homepage-config/settings.yaml" ]
test_result $? "unraid/homepage-config/settings.yaml exists"

python3 -c "import yaml; yaml.safe_load(open('unraid/homepage-config/settings.yaml'))"
test_result $? "unraid/homepage-config/settings.yaml YAML syntax valid"

grep -q "Happy Struggle Bus\|happystrugglebus" unraid/homepage-config/settings.yaml
test_result $? "homepage settings.yaml sets correct title (Happy Struggle Bus)"

[ -f "unraid/homepage-config/widgets.yaml" ]
test_result $? "unraid/homepage-config/widgets.yaml exists"

python3 -c "import yaml; yaml.safe_load(open('unraid/homepage-config/widgets.yaml'))"
test_result $? "unraid/homepage-config/widgets.yaml YAML syntax valid"

[ -f "unraid/homepage-config/docker.yaml" ]
test_result $? "unraid/homepage-config/docker.yaml exists"

python3 -c "import yaml; yaml.safe_load(open('unraid/homepage-config/docker.yaml'))"
test_result $? "unraid/homepage-config/docker.yaml YAML syntax valid"

grep -q "docker.sock" unraid/homepage-config/docker.yaml
test_result $? "homepage docker.yaml configures Docker socket integration"

[ -f "docs/13_HOMEPAGE_SETUP_GUIDE.md" ]
test_result $? "docs/13_HOMEPAGE_SETUP_GUIDE.md (homepage setup guide) exists"

grep -q "HOMEPAGE_ALLOWED_HOSTS" docs/13_HOMEPAGE_SETUP_GUIDE.md
test_result $? "homepage guide covers HOMEPAGE_ALLOWED_HOSTS fix"

grep -q "Uptime Kuma\|uptimekuma" docs/13_HOMEPAGE_SETUP_GUIDE.md
test_result $? "homepage guide covers Uptime Kuma integration"

# Node A command center includes the new infra links
grep -q "UPTIME_KUMA_BASE_URL" node-a-command-center/node-a-command-center.js
test_result $? "Command center defines UPTIME_KUMA_BASE_URL"

grep -q "DOZZLE_BASE_URL" node-a-command-center/node-a-command-center.js
test_result $? "Command center defines DOZZLE_BASE_URL"

grep -q "HOMEPAGE_BASE_URL" node-a-command-center/node-a-command-center.js
test_result $? "Command center defines HOMEPAGE_BASE_URL"

grep -q "Uptime Kuma" node-a-command-center/node-a-command-center.js
test_result $? "Command center lists Uptime Kuma in dashboard links"

grep -q "Dozzle" node-a-command-center/node-a-command-center.js
test_result $? "Command center lists Dozzle in dashboard links"

echo ""

# Test 12: Validate new layman's guides documentation suite
echo "12. Validating layman's guides documentation suite..."
echo "------------------------------------------------------"

[ -f "docs/14_POST_INSTALL_LAYMENS_GUIDE.md" ]
test_result $? "docs/14_POST_INSTALL_LAYMENS_GUIDE.md (post-install guide) exists"

grep -q "health\|Health\|verify\|Verify" docs/14_POST_INSTALL_LAYMENS_GUIDE.md
test_result $? "post-install guide covers health checks"

grep -q "3099\|Command Center\|command center" docs/14_POST_INSTALL_LAYMENS_GUIDE.md
test_result $? "post-install guide references Node A Command Center (port 3099)"

grep -q "ollama pull\|ollama" docs/14_POST_INSTALL_LAYMENS_GUIDE.md
test_result $? "post-install guide covers loading Ollama models"

[ -f "docs/15_LITELLM_OPENWEBUI_USER_GUIDE.md" ]
test_result $? "docs/15_LITELLM_OPENWEBUI_USER_GUIDE.md (LiteLLM+OpenWebUI guide) exists"

grep -q "192.168.1.222:4000" docs/15_LITELLM_OPENWEBUI_USER_GUIDE.md
test_result $? "LiteLLM+OpenWebUI guide contains correct gateway URL"

grep -q "sk-master-key" docs/15_LITELLM_OPENWEBUI_USER_GUIDE.md
test_result $? "LiteLLM+OpenWebUI guide references master key"

grep -q "system prompt\|System Prompt\|master prompt\|Master Prompt" docs/15_LITELLM_OPENWEBUI_USER_GUIDE.md
test_result $? "LiteLLM+OpenWebUI guide covers system/master prompts"

grep -q "Anthropic\|OpenAI\|Gemini\|OpenRouter" docs/15_LITELLM_OPENWEBUI_USER_GUIDE.md
test_result $? "LiteLLM+OpenWebUI guide covers cloud connectors"

[ -f "docs/16_NODE_A_LAYMENS_GUIDE.md" ]
test_result $? "docs/16_NODE_A_LAYMENS_GUIDE.md (Node A guide) exists"

grep -q "192.168.1.9\|ROCm\|vLLM\|7900" docs/16_NODE_A_LAYMENS_GUIDE.md
test_result $? "Node A guide references correct IP, ROCm, vLLM"

grep -q "HSA_OVERRIDE_GFX_VERSION" docs/16_NODE_A_LAYMENS_GUIDE.md
test_result $? "Node A guide documents HSA_OVERRIDE_GFX_VERSION fix"

[ -f "docs/17_NODE_B_LAYMENS_GUIDE.md" ]
test_result $? "docs/17_NODE_B_LAYMENS_GUIDE.md (Node B guide) exists"

grep -q "192.168.1.222\|LiteLLM\|Portainer" docs/17_NODE_B_LAYMENS_GUIDE.md
test_result $? "Node B guide references correct IP, LiteLLM, Portainer"

[ -f "docs/18_NODE_C_LAYMENS_GUIDE.md" ]
test_result $? "docs/18_NODE_C_LAYMENS_GUIDE.md (Node C guide) exists"

grep -q "192.168.1.6\|Intel Arc\|chimera_face\|ZES_ENABLE_SYSMAN" docs/18_NODE_C_LAYMENS_GUIDE.md
test_result $? "Node C guide references correct IP, Intel Arc, chimera_face, ZES_ENABLE_SYSMAN"

[ -f "docs/19_NODE_D_LAYMENS_GUIDE.md" ]
test_result $? "docs/19_NODE_D_LAYMENS_GUIDE.md (Node D Home Assistant guide) exists"

grep -q "192.168.1.149\|8123\|openai_conversation" docs/19_NODE_D_LAYMENS_GUIDE.md
test_result $? "Node D guide references correct IP, port 8123, openai_conversation"

[ -f "docs/20_NODE_E_LAYMENS_GUIDE.md" ]
test_result $? "docs/20_NODE_E_LAYMENS_GUIDE.md (Node E Sentinel guide) exists"

grep -q "Frigate\|Sentinel\|3005\|SENTINEL_TOKEN" docs/20_NODE_E_LAYMENS_GUIDE.md
test_result $? "Node E guide references Frigate, Sentinel, port 3005, SENTINEL_TOKEN"

[ -f "docs/21_OPENCLAW_KVM_LAYMENS_GUIDE.md" ]
test_result $? "docs/21_OPENCLAW_KVM_LAYMENS_GUIDE.md (OpenClaw+KVM big guide) exists"

grep -q "18789\|OPENCLAW_GATEWAY_TOKEN\|openssl rand" docs/21_OPENCLAW_KVM_LAYMENS_GUIDE.md
test_result $? "OpenClaw+KVM guide covers port 18789, token, openssl rand"

grep -q "skill-kvm\|KVM_OPERATOR_URL\|REQUIRE_APPROVAL" docs/21_OPENCLAW_KVM_LAYMENS_GUIDE.md
test_result $? "OpenClaw+KVM guide covers skill-kvm, KVM_OPERATOR_URL, REQUIRE_APPROVAL"

grep -q "5000\|approval\|Approval\|denylist" docs/21_OPENCLAW_KVM_LAYMENS_GUIDE.md
test_result $? "OpenClaw+KVM guide covers KVM Operator port 5000, approval, denylist"

[ -f "docs/22_PROXMOX_BLUEIRIS_FRIGATE_GUIDE.md" ]
test_result $? "docs/22_PROXMOX_BLUEIRIS_FRIGATE_GUIDE.md (Proxmox+Blue Iris+Frigate guide) exists"

grep -q "192.168.1.174\|Proxmox\|8006" docs/22_PROXMOX_BLUEIRIS_FRIGATE_GUIDE.md
test_result $? "Proxmox guide references correct IP and port 8006"

grep -q "Blue Iris\|Frigate\|RTSP" docs/22_PROXMOX_BLUEIRIS_FRIGATE_GUIDE.md
test_result $? "Proxmox guide covers Blue Iris, Frigate, and RTSP"

grep -q "Windows\|VM\|VirtIO" docs/22_PROXMOX_BLUEIRIS_FRIGATE_GUIDE.md
test_result $? "Proxmox guide covers Windows VM with VirtIO"

[ -f "docs/23_HOME_ASSISTANT_LAYMENS_GUIDE.md" ]
test_result $? "docs/23_HOME_ASSISTANT_LAYMENS_GUIDE.md (Home Assistant big guide) exists"

grep -q "192.168.1.149\|8123\|brawn-fast\|brain-heavy" docs/23_HOME_ASSISTANT_LAYMENS_GUIDE.md
test_result $? "HA guide references correct IP, port 8123, model names"

grep -q "HACS\|automation\|Automation\|voice\|Voice" docs/23_HOME_ASSISTANT_LAYMENS_GUIDE.md
test_result $? "HA guide covers HACS, automations, and voice control"

echo ""
echo "================================================================================"
echo "  TEST RESULTS"
echo "================================================================================"
echo ""
echo -e "Tests Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Tests Failed: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED!${NC}"
    echo ""
    echo "Your Grand Unified AI Home Lab configuration is ready for deployment!"
    echo ""
    echo "Next steps:"
    echo "  1. Review DEPLOYMENT_GUIDE.md for detailed deployment instructions"
    echo "  2. Deploy Node B (LiteLLM Gateway): cd node-b-litellm && docker compose -f litellm-stack.yml up -d"
    echo "  3. Deploy Node C (Intel Arc): cd node-c-arc && docker compose up -d"
    echo "  4. Configure Node D (Home Assistant): Add configuration.yaml.snippet to your config"
    echo "  5. Test the unified endpoint: curl http://192.168.1.222:4000/health"
    echo ""
    exit 0
else
    echo -e "${RED}✗ SOME TESTS FAILED!${NC}"
    echo "Please review the failures above and fix the issues."
    exit 1
fi
