#!/usr/bin/env bash
# lib-colors.sh — Shared ANSI colour variables for homelab shell scripts.
#
# Source this file instead of re-declaring the variables in each script:
#
#   REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
#   source "${REPO_ROOT}/scripts/lib-colors.sh"
#
# The variables are intentionally unset when the terminal does not support
# colours (TERM=dumb or stdout is not a TTY) so that piped/logged output
# remains clean.
#
# Scripts that have a JSON/machine-readable output mode should call
# disable_colors() after parsing their flags to suppress colours entirely:
#
#   $JSON_OUTPUT && disable_colors

if [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  BLUE='\033[0;34m'
  MAGENTA='\033[0;35m'
  BOLD='\033[1m'
  DIM='\033[2m'
  NC='\033[0m'
else
  GREEN=''
  RED=''
  YELLOW=''
  CYAN=''
  BLUE=''
  MAGENTA=''
  BOLD=''
  DIM=''
  NC=''
fi

# disable_colors — zero all colour variables for machine-readable output modes.
disable_colors() {
  GREEN=''; RED=''; YELLOW=''; CYAN=''; BLUE=''; MAGENTA=''; BOLD=''; DIM=''; NC=''
}
