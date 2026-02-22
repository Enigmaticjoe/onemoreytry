#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  Node Labels — Apply or view Docker Swarm node labels
# ══════════════════════════════════════════════════════════════════════════════
#
#  Run on the Swarm MANAGER node to apply placement labels.
#  Labels control which services run on which nodes (GPU, role, etc.)
#
#  Usage (on manager):
#    ./swarm/node-labels.sh apply    # apply all labels
#    ./swarm/node-labels.sh view     # show all node labels
#    ./swarm/node-labels.sh remove   # remove homelab labels
#
#  Or from your workstation (via SSH):
#    ssh root@192.168.1.222 'bash -s' < swarm/node-labels.sh apply
#
# ══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

ACTION="${1:-apply}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}!${NC} $*"; }
info() { echo -e "  ${CYAN}→${NC} $*"; }

label() {
  local node_id="$1" key="$2" val="$3"
  docker node update --label-add "${key}=${val}" "$node_id" 2>/dev/null \
    && echo -n "." || echo -n "!"
}

unlabel() {
  local node_id="$1" key="$2"
  docker node update --label-rm "${key}" "$node_id" 2>/dev/null || true
}

if [[ "$ACTION" == "view" ]]; then
  echo ""
  echo "Docker Swarm Node Labels"
  echo "════════════════════════"
  docker node ls --format '{{.ID}} {{.Hostname}} {{.Status}}' | while read -r id hostname status; do
    echo ""
    echo -e "  ${CYAN}${hostname}${NC} (${id:0:12}) — ${status}"
    docker node inspect "$id" --format '{{range $k,$v := .Spec.Labels}}    • {{$k}}={{$v}}{{"\n"}}{{end}}' 2>/dev/null || true
  done
  echo ""
  exit 0
fi

if [[ "$ACTION" == "remove" ]]; then
  echo "Removing homelab labels from all nodes..."
  docker node ls -q | while read -r id; do
    for key in gpu gpu.vendor gpu.model vram role role.unraid role.vision node homelab.node; do
      unlabel "$id" "$key"
    done
    echo -n "."
  done
  echo " done"
  exit 0
fi

# ── APPLY labels ──────────────────────────────────────────────────────────────
echo ""
echo "Applying Swarm node labels..."
echo ""
echo "  You'll be prompted to identify each node by its hostname."
echo "  Run: docker node ls  — to see hostnames"
echo ""

docker node ls --format '{{.ID}} {{.Hostname}} ({{.Status}})' | while read -r id hostname status_raw; do
  status="${status_raw//(/}"
  status="${status//)/}"
  echo ""
  echo -e "  ${CYAN}Node:${NC} ${hostname} — ${status}"
  echo "  Which node is this? Options:"
  echo "    a) NODE_A — Brain/AMD RX 7900 XT (inference, heavy LLM)"
  echo "    b) NODE_B — Unraid/RTX 4070 (gateway, LiteLLM)"
  echo "    c) NODE_C — Intel Arc A770 (vision AI, Ollama)"
  echo "    d) NODE_D — Home Assistant (automation)"
  echo "    e) NODE_E — Sentinel/NVR"
  echo "    s) skip"
  echo -n "  Choice [a/b/c/d/e/s]: "
  read -r choice

  case "${choice,,}" in
    a)
      echo -n "  Applying NODE_A labels "
      label "$id" "gpu"          "amd"
      label "$id" "gpu.vendor"   "amd"
      label "$id" "gpu.model"    "rx7900xt"
      label "$id" "vram"         "20g"
      label "$id" "role"         "inference"
      label "$id" "node"         "node-a"
      label "$id" "homelab.node" "A"
      ok " done"
      ;;
    b)
      echo -n "  Applying NODE_B labels "
      label "$id" "gpu"          "nvidia"
      label "$id" "gpu.vendor"   "nvidia"
      label "$id" "gpu.model"    "rtx4070"
      label "$id" "vram"         "12g"
      label "$id" "role"         "gateway"
      label "$id" "role.unraid"  "true"
      label "$id" "node"         "node-b"
      label "$id" "homelab.node" "B"
      ok " done"
      ;;
    c)
      echo -n "  Applying NODE_C labels "
      label "$id" "gpu"          "intel"
      label "$id" "gpu.vendor"   "intel"
      label "$id" "gpu.model"    "arc-a770"
      label "$id" "vram"         "16g"
      label "$id" "role"         "inference"
      label "$id" "role.vision"  "true"
      label "$id" "node"         "node-c"
      label "$id" "homelab.node" "C"
      ok " done"
      ;;
    d)
      echo -n "  Applying NODE_D labels "
      label "$id" "role"         "automation"
      label "$id" "node"         "node-d"
      label "$id" "homelab.node" "D"
      ok " done"
      ;;
    e)
      echo -n "  Applying NODE_E labels "
      label "$id" "role"         "nvr"
      label "$id" "node"         "node-e"
      label "$id" "homelab.node" "E"
      ok " done"
      ;;
    s|*)
      info "Skipped ${hostname}"
      ;;
  esac
done

echo ""
echo "Final node labels:"
docker node ls --format '{{.ID}} {{.Hostname}}' | while read -r id hostname; do
  echo ""
  echo -e "  ${CYAN}${hostname}${NC}:"
  docker node inspect "$id" \
    --format '{{range $k,$v := .Spec.Labels}}    {{$k}}={{$v}}  {{end}}' 2>/dev/null \
    | tr '  ' '\n' | grep -v '^$' | sed 's/^/    /' || true
done
echo ""
