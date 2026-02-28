#!/usr/bin/env python3
"""
Brothers Keeper — API Server
==============================
FastAPI application exposing the install orchestrator over HTTP so the
kiosk HMI (templates/index.html) can drive installation from a browser.

Endpoints:
  GET  /           — serve kiosk HMI (index.html)
  GET  /health     — liveness check
  GET  /state      — return current RuntimeContext as JSON
  POST /action     — queue an install action (allowlist enforced)
  POST /confirm    — approve or reject a pending action

Security:
  - Action allowlist prevents arbitrary command execution.
  - Payloads over MAX_PAYLOAD_LENGTH are rejected.
  - CORS restricted to same-origin by default; set BK_CORS_ORIGINS env var for LAN access.
  - Optional Bearer token via BK_API_TOKEN env var.
"""

from __future__ import annotations

import logging
import os
import queue
import threading
import time
from dataclasses import asdict
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field

from core_orchestrator import (
    FULL_INSTALL_SEQUENCE,
    TASK_REGISTRY,
    DEFAULT_STATE_FILE,
    RuntimeContext,
    confirm_action,
    dispatch_action,
    load_state,
    save_state,
)

load_dotenv()

LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
logging.basicConfig(level=LOG_LEVEL, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("brothers-keeper-api")

BK_API_TOKEN: str = os.getenv("BK_API_TOKEN", "")
MAX_PAYLOAD_LENGTH: int = int(os.getenv("MAX_PAYLOAD_LENGTH", "4096"))
STATE_FILE = Path(os.getenv("BK_STATE_FILE", str(DEFAULT_STATE_FILE)))
TEMPLATES_DIR = Path(__file__).parent / "templates"

# Strictly allowed action names — prevents arbitrary dispatch
ACTION_ALLOWLIST = set(TASK_REGISTRY.keys()) | {"full_install"}

# CORS origins (comma-separated); allow everything on LAN by default for homelab use
_cors_env = os.getenv("BK_CORS_ORIGINS", "*")
CORS_ORIGINS = [o.strip() for o in _cors_env.split(",") if o.strip()]

# ---------------------------------------------------------------------------
# Background worker — processes queued actions serially
# ---------------------------------------------------------------------------

_action_queue: "queue.Queue[str]" = queue.Queue()
_ctx_lock = threading.Lock()


def _worker() -> None:
    """Drain the action queue, executing one task at a time."""
    while True:
        action = _action_queue.get()
        try:
            ctx = load_state(STATE_FILE)
            dispatch_action(action, ctx, STATE_FILE)
        except Exception as exc:
            logger.error("Worker error dispatching '%s': %s", action, exc)
        finally:
            _action_queue.task_done()


_worker_thread = threading.Thread(target=_worker, daemon=True)
_worker_thread.start()

# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Brothers Keeper API",
    description="Install orchestrator API for the homelab kiosk HMI",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
)


# ---------------------------------------------------------------------------
# Auth helper
# ---------------------------------------------------------------------------

def _check_token(authorization: Optional[str] = Header(default=None)) -> None:
    """Require Bearer token when BK_API_TOKEN is configured."""
    if not BK_API_TOKEN:
        return
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or malformed Authorization header")
    token = authorization.split(" ", 1)[1]
    if token != BK_API_TOKEN:
        raise HTTPException(status_code=403, detail="Invalid API token")


# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------

class ActionRequest(BaseModel):
    action: str = Field(..., max_length=64, description="Action name from the allowlist")


class ConfirmRequest(BaseModel):
    action: str = Field(..., max_length=64, description="Action to confirm or reject")
    approved: bool = Field(..., description="True to approve, False to reject")


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.get("/", include_in_schema=False)
async def serve_hmi() -> FileResponse:
    """Serve the kiosk HMI single-page app."""
    html_file = TEMPLATES_DIR / "index.html"
    if not html_file.exists():
        raise HTTPException(status_code=404, detail="HMI template not found")
    return FileResponse(str(html_file), media_type="text/html")


@app.get("/health")
async def health() -> JSONResponse:
    """Liveness probe."""
    return JSONResponse({"status": "ok", "ts": time.time()})


@app.get("/state", dependencies=[Depends(_check_token)])
async def get_state() -> JSONResponse:
    """Return the current RuntimeContext as JSON."""
    ctx = load_state(STATE_FILE)
    return JSONResponse(asdict(ctx))


@app.post("/action", dependencies=[Depends(_check_token)])
async def post_action(request: Request, body: ActionRequest) -> JSONResponse:
    """Queue an install action.  Rejects unknown or disallowed action names."""
    # Payload length guard
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > MAX_PAYLOAD_LENGTH:
        raise HTTPException(status_code=413, detail="Payload too large")

    action = body.action.strip()
    if action not in ACTION_ALLOWLIST:
        raise HTTPException(status_code=400, detail=f"Action '{action}' is not in the allowlist")

    if action == "full_install":
        for step in FULL_INSTALL_SEQUENCE:
            _action_queue.put(step)
        return JSONResponse({"queued": FULL_INSTALL_SEQUENCE})

    _action_queue.put(action)
    return JSONResponse({"queued": [action]})


@app.post("/confirm", dependencies=[Depends(_check_token)])
async def post_confirm(request: Request, body: ConfirmRequest) -> JSONResponse:
    """Approve or reject a pending action confirmation."""
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > MAX_PAYLOAD_LENGTH:
        raise HTTPException(status_code=413, detail="Payload too large")

    action = body.action.strip()
    if action not in ACTION_ALLOWLIST:
        raise HTTPException(status_code=400, detail=f"Action '{action}' is not in the allowlist")

    ctx = load_state(STATE_FILE)
    confirm_action(action, body.approved, ctx, STATE_FILE)
    return JSONResponse({
        "action": action,
        "approved": body.approved,
        "pending_confirm": ctx.pending_confirm,
    })


# ---------------------------------------------------------------------------
# Dev entrypoint
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("api_server:app", host="0.0.0.0", port=7070, reload=True)
