#!/usr/bin/env bash
# Brothers Keeper — dev server launcher
set -euo pipefail

cd "$(dirname "$0")"

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Load env if present
[ -f .env ] && { set -a; source .env; set +a; }

exec uvicorn api_server:app --host 0.0.0.0 --port 7070 --reload
