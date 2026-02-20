#!/usr/bin/env python3
"""
AI KVM Operator (Revised) — NanoKVM + LiteLLM Vision (FastAPI)

NanoKVM expectations are based on your blueprint:
- MJPEG: GET /api/stream/mjpeg
- HID paste: POST /api/hid/paste
- Auth: POST /api/auth/login (some firmware uses AES-256-CBC encrypted password; plain fallback supported)

Safety:
- REQUIRE_APPROVAL=true by default (human-in-the-loop)
- denylist blocks destructive commands unless ALLOW_DANGEROUS=true
"""

from __future__ import annotations

import base64
import json
import logging
import os
import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional

import requests
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Header
from pydantic import BaseModel, Field

load_dotenv()

LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
logging.basicConfig(level=LOG_LEVEL, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("kvm-operator")

KVM_OPERATOR_TOKEN = os.getenv("KVM_OPERATOR_TOKEN", "")
LITELLM_URL = os.getenv("LITELLM_URL", "http://localhost:4000/v1/chat/completions")
LITELLM_KEY = os.getenv("LITELLM_KEY", "")
VISION_MODEL = os.getenv("VISION_MODEL", "kvm-vision")

NANOKVM_USERNAME = os.getenv("NANOKVM_USERNAME", "admin")
NANOKVM_PASSWORD = os.getenv("NANOKVM_PASSWORD", "admin")
NANOKVM_AUTH_MODE = os.getenv("NANOKVM_AUTH_MODE", "auto").lower()  # auto|encrypted|plain

REQUIRE_APPROVAL = os.getenv("REQUIRE_APPROVAL", "true").lower() in ("1", "true", "yes", "y")
ALLOW_DANGEROUS = os.getenv("ALLOW_DANGEROUS", "false").lower() in ("1", "true", "yes", "y")
MAX_STEPS_DEFAULT = int(os.getenv("MAX_STEPS_DEFAULT", "10"))

KVM_TARGETS_JSON = os.getenv("KVM_TARGETS_JSON", '{"node-c":"192.168.1.100"}')
try:
    KVM_TARGETS: Dict[str, str] = json.loads(KVM_TARGETS_JSON)
except Exception as e:
    raise RuntimeError(f"Invalid KVM_TARGETS_JSON: {e}")

# Blueprint auth constants (static in some firmware variants)
SECRET_KEY = b"nanokvm-sipeed-2024"
IV = b"0000000000000000"

DENYLIST_PATH = Path(__file__).with_name("policy_denylist.txt")


def load_denylist() -> list[str]:
    if not DENYLIST_PATH.exists():
        return []
    return [
        ln.strip().lower()
        for ln in DENYLIST_PATH.read_text(encoding="utf-8").splitlines()
        if ln.strip() and not ln.strip().startswith("#")
    ]


DENYLIST = load_denylist()


def extract_json_object(text: str) -> Optional[dict]:
    try:
        return json.loads(text)
    except Exception:
        pass
    m = re.search(r"\{.*\}", text, flags=re.DOTALL)
    if not m:
        return None
    try:
        return json.loads(m.group(0))
    except Exception:
        return None


def is_payload_allowed(payload: str) -> tuple[bool, str]:
    if ALLOW_DANGEROUS:
        return True, "ALLOW_DANGEROUS=true"
    low = payload.lower()
    low_compact = re.sub(r"\s+", " ", low)
    for bad in DENYLIST:
        if bad in low or bad in low_compact:
            return False, f"Denied by policy (matched: {bad})"
    return True, "OK"


def require_auth(authorization: Optional[str] = Header(default=None)) -> None:
    if not KVM_OPERATOR_TOKEN:
        raise HTTPException(status_code=500, detail="Server misconfigured (missing KVM_OPERATOR_TOKEN).")
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing Bearer token.")
    token = authorization.split(" ", 1)[1].strip()
    if token != KVM_OPERATOR_TOKEN:
        raise HTTPException(status_code=403, detail="Invalid token.")


@dataclass
class NanoKVMClient:
    ip: str
    username: str
    password: str
    auth_mode: str = "auto"

    def __post_init__(self):
        self.base_url = f"http://{self.ip}"
        self.session = requests.Session()
        self.token: Optional[str] = None

    def _encrypt_password(self) -> str:
        cipher = AES.new(SECRET_KEY, AES.MODE_CBC, IV)
        encrypted = cipher.encrypt(pad(self.password.encode("utf-8"), AES.block_size))
        return base64.b64encode(encrypted).decode("utf-8")

    def login(self) -> None:
        payload_plain = {"username": self.username, "password": self.password}
        payload_enc = {"username": self.username, "password": self._encrypt_password()}
        modes = [self.auth_mode] if self.auth_mode in ("plain", "encrypted") else ["encrypted", "plain"]

        last_err = None
        for mode in modes:
            payload = payload_enc if mode == "encrypted" else payload_plain
            try:
                res = self.session.post(f"{self.base_url}/api/auth/login", json=payload, timeout=10)
                if res.status_code != 200:
                    last_err = f"HTTP {res.status_code}: {res.text[:300]}"
                    continue
                data = res.json()
                if data.get("code") == 0 and "data" in data and "token" in data["data"]:
                    self.token = data["data"]["token"]
                    self.session.cookies.set("nano-kvm-token", self.token)
                    logger.info("NanoKVM login OK (%s)", mode)
                    return
                last_err = f"Bad response: {data}"
            except Exception as e:
                last_err = str(e)

        raise RuntimeError(f"NanoKVM login failed: {last_err}")

    def get_snapshot_jpeg(self) -> bytes:
        r = self.session.get(f"{self.base_url}/api/stream/mjpeg", stream=True, timeout=15)
        r.raise_for_status()
        buf = b""
        start = time.time()
        for chunk in r.iter_content(chunk_size=4096):
            if not chunk:
                continue
            buf += chunk
            a = buf.find(b"\xff\xd8")
            b = buf.find(b"\xff\xd9")
            if a != -1 and b != -1 and b > a:
                jpg = buf[a : b + 2]
                r.close()
                return jpg
            if time.time() - start > 10:
                r.close()
                break
        raise RuntimeError("Timed out extracting JPEG from MJPEG stream.")

    def hid_paste(self, content: str) -> Any:
        res = self.session.post(f"{self.base_url}/api/hid/paste", json={"content": content}, timeout=10)
        res.raise_for_status()
        return res.json()


class LiteLLMVision:
    def __init__(self, url: str, key: str, model: str):
        self.url = url
        self.key = key
        self.model = model
        self.session = requests.Session()

    def decide(self, instruction: str, jpeg: bytes) -> dict:
        b64 = base64.b64encode(jpeg).decode("utf-8")
        system_prompt = (
            "Return ONLY JSON with keys screen_state, action, payload. "
            'action ∈ ["type","wait","abort","success"]. '
            "If unsure, abort. Never suggest destructive commands."
        )

        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": instruction},
                        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}" }},
                    ],
                },
            ],
            "max_tokens": 250,
            "temperature": 0.1,
        }

        headers = {"Content-Type": "application/json"}
        if self.key:
            headers["Authorization"] = f"Bearer {self.key}"

        res = self.session.post(self.url, headers=headers, json=payload, timeout=60)
        res.raise_for_status()
        data = res.json()
        content = data["choices"][0]["message"]["content"]
        obj = extract_json_object(content)
        if not obj:
            raise RuntimeError(f"Model did not return valid JSON. Raw: {content[:400]}")
        return obj


class Operator:
    def __init__(self, kvm: NanoKVMClient, llm: LiteLLMVision):
        self.kvm = kvm
        self.llm = llm

    def run_task(self, instruction: str, max_steps: int) -> dict:
        self.kvm.login()
        history = []
        for step in range(1, max_steps + 1):
            jpeg = self.kvm.get_snapshot_jpeg()
            decision = self.llm.decide(instruction, jpeg)

            action = str(decision.get("action", "")).strip().lower()
            payload = str(decision.get("payload", "") if decision.get("payload") is not None else "")
            history.append({"step": step, "decision": decision})

            if action in ("success", "abort"):
                return {"status": action, "history": history}

            if action == "wait":
                time.sleep(2)
                continue

            if action == "type":
                ok, why = is_payload_allowed(payload)
                if not ok:
                    return {"status": "abort", "history": history, "error": why}
                if REQUIRE_APPROVAL:
                    raise RuntimeError("REQUIRE_APPROVAL=true (disable for headless automation).")
                self.kvm.hid_paste(payload)
                time.sleep(1.5)
                continue

            return {"status": "abort", "history": history, "error": f"Unknown action: {action}"}

        return {"status": "abort", "history": history, "error": "Max steps reached"}


app = FastAPI(title="AI KVM Operator", version="1.0.0")


class TaskRequest(BaseModel):
    instruction: str = Field(..., min_length=3)
    max_steps: int = Field(default=MAX_STEPS_DEFAULT, ge=1, le=50)


@app.get("/health")
def health():
    return {"ok": True, "targets": list(KVM_TARGETS.keys())}


@app.post("/kvm/task/{target}")
def kvm_task(target: str, req: TaskRequest, _auth: None = Depends(require_auth)):
    if target not in KVM_TARGETS:
        raise HTTPException(status_code=404, detail=f"Unknown target '{target}'. Known: {list(KVM_TARGETS)}")

    ip = KVM_TARGETS[target]
    kvm = NanoKVMClient(ip=ip, username=NANOKVM_USERNAME, password=NANOKVM_PASSWORD, auth_mode=NANOKVM_AUTH_MODE)
    llm = LiteLLMVision(url=LITELLM_URL, key=LITELLM_KEY, model=VISION_MODEL)
    op = Operator(kvm, llm)

    try:
        return op.run_task(req.instruction, req.max_steps)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
