#!/usr/bin/env bash
# Root-level convenience wrapper for the Connection Wizard.
# Delegates to scripts/connection-wizard.sh so users can run it from the repo root:
#
#   ./connection-wizard.sh
#   ./connection-wizard.sh --ssh
#   ./connection-wizard.sh --all-checks
#
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${REPO_ROOT}/scripts/connection-wizard.sh"

if [ ! -f "$TARGET" ]; then
  echo "Error: cannot find scripts/connection-wizard.sh under ${REPO_ROOT}" >&2
  exit 1
fi

exec "$TARGET" "$@"
