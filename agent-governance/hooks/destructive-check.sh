#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Agent Instruction Framework — Destructive Change Detection
# Grand Unified AI Home Lab / Project Chimera
#
# Scans staged changes for patterns that indicate potentially destructive
# operations.  Called by the pre-commit hook before any commit is accepted.
#
# Exit codes:
#   0 — no destructive patterns detected
#   1 — one or more destructive patterns detected; commit is blocked
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

VIOLATIONS=0

warn()  { echo -e "${YELLOW}[destructive-check] ⚠ $*${NC}"; }
block() { echo -e "${RED}[destructive-check] ✗ BLOCKED — $*${NC}"; ((VIOLATIONS++)) || true; }

# ─────────────────────────────────────────────────────────────────────────────
# Patterns that trigger a hard block (must match against the diff content)
# Uses ERE (-E) for portability across GNU and BSD grep.
# ─────────────────────────────────────────────────────────────────────────────
declare -A HARD_BLOCK_PATTERNS=(
    ["direct git push"]='^\+.*git[[:space:]]+push[[:space:]]'
    ["force push"]='^\+.*git[[:space:]]+push[[:space:]]+--(force|f)[[:space:]]'
    ["rm -rf system paths"]='^\+.*[[:space:]]rm[[:space:]]+-rf?[[:space:]]+/(bin|boot|dev|etc|lib|proc|run|sbin|sys|usr|var)'
    ["rm -rf home root"]='^\+.*[[:space:]]rm[[:space:]]+-rf?[[:space:]]+(~[[:space:]]*$|/home/[^/]+/[[:space:]]*$)'
    ["disk wipe (dd zero)"]='^\+.*[[:space:]]dd[[:space:]].*if=/dev/zero'
    ["mkfs (disk format)"]='^\+.*[[:space:]]mkfs\.[a-z]+'
    ["DROP TABLE/DATABASE"]='^\+.*DROP[[:space:]]+(TABLE|DATABASE)'
    ["TRUNCATE TABLE"]='^\+.*TRUNCATE[[:space:]]+TABLE'
    ["DELETE without WHERE"]='^\+.*DELETE[[:space:]]+FROM[[:space:]]+[a-zA-Z_]+[[:space:]]*;'
    ["curl pipe to shell"]='^\+.*curl[[:space:]].*\|[[:space:]]*(ba)?sh'
    ["wget pipe to shell"]='^\+.*wget[[:space:]].*-O[[:space:]]*-[[:space:]]*\|[[:space:]]*(ba)?sh'
    ["shred"]='^\+.*[[:space:]]shred[[:space:]]'
)

# ─────────────────────────────────────────────────────────────────────────────
# Patterns that trigger a warning (commit allowed, but operator is informed)
# ─────────────────────────────────────────────────────────────────────────────
declare -A WARN_PATTERNS=(
    ["docker socket mount"]='^\+.*/var/run/docker\.sock'
    ["privileged container"]='^\+.*privileged:[[:space:]]+true'
    ["network_mode host"]='^\+.*network_mode:[[:space:]]+host'
    ["rm -rf non-system"]='^\+.*[[:space:]]rm[[:space:]]+-rf?'
    ["chmod 777"]='^\+.*chmod[[:space:]]+777'
    ["nohup background"]='^\+.*nohup'
)

# ─────────────────────────────────────────────────────────────────────────────
# Get the staged diff (additions only, skip binary files)
# ─────────────────────────────────────────────────────────────────────────────
DIFF=$(git diff --cached --unified=0 -- . 2>/dev/null | grep -v '^Binary' || true)

if [ -z "$DIFF" ]; then
    echo "[destructive-check] No staged diff to scan."
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Run hard-block checks
# ─────────────────────────────────────────────────────────────────────────────
for label in "${!HARD_BLOCK_PATTERNS[@]}"; do
    pattern="${HARD_BLOCK_PATTERNS[$label]}"
    if echo "$DIFF" | grep -qE "$pattern" 2>/dev/null; then
        block "$label"
        echo "         Pattern matched: ${pattern}"
        echo "         Add AGENT_OVERRIDE=1 env var with human approval to bypass."
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# Allow bypass for explicitly approved operations
# ─────────────────────────────────────────────────────────────────────────────
if [ "${AGENT_OVERRIDE:-0}" = "1" ] && [ $VIOLATIONS -gt 0 ]; then
    warn "AGENT_OVERRIDE=1 is set — ${VIOLATIONS} destructive pattern(s) bypassed."
    warn "This override MUST be recorded in the audit log with human approval."
    VIOLATIONS=0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Run warning checks
# ─────────────────────────────────────────────────────────────────────────────
for label in "${!WARN_PATTERNS[@]}"; do
    pattern="${WARN_PATTERNS[$label]}"
    if echo "$DIFF" | grep -qE "$pattern" 2>/dev/null; then
        warn "${label} — review carefully before proceeding"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
if [ $VIOLATIONS -gt 0 ]; then
    echo ""
    echo -e "${RED}[destructive-check] ${VIOLATIONS} hard block(s) triggered. Commit aborted.${NC}"
    echo "  To review: git diff --cached"
    echo "  To bypass with human approval: AGENT_OVERRIDE=1 git commit"
    exit 1
fi

echo "[destructive-check] Clean — no destructive patterns detected."
exit 0
