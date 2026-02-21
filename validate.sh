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

# Check container names
grep -q "container_name: litellm_gateway" node-b-litellm/litellm-stack.yml
test_result $? "LiteLLM container named 'litellm_gateway'"

grep -q "container_name: ollama_intel_arc" node-c-arc/docker-compose.yml
test_result $? "Ollama container named 'ollama_intel_arc'"

grep -q "container_name: chimera_face" node-c-arc/docker-compose.yml
test_result $? "Open WebUI container named 'chimera_face'"

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
