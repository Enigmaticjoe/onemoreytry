#!/usr/bin/env bash
set -euo pipefail

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

set -a
source .env
set +a

exec uvicorn app:app --host 0.0.0.0 --port 5000
