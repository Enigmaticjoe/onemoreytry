#!/bin/sh
set -eu

curl -fsS "http://127.0.0.1:${PORT:-3099}/api/health" >/dev/null
