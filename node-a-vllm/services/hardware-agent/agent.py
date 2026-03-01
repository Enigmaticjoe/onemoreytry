#!/usr/bin/env python3
"""
Brain Hardware Agent - GPU and system monitoring for AMD RX 7900 XT.

Exposes a lightweight HTTP API on port 8090:
  GET /health  - liveness check
  GET /gpu     - GPU stats via rocm-smi
  GET /system  - CPU, RAM, and disk usage
  GET /status  - combined health of all Brain Project services
"""

import json
import os
import subprocess
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("PORT", 8090))
VLLM_URL = os.environ.get("VLLM_URL", "http://172.30.0.10:8000")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://172.30.0.20:6333")


def _probe(url: str, timeout: int = 3) -> bool:
    try:
        urllib.request.urlopen(url, timeout=timeout)
        return True
    except Exception:
        return False


def get_gpu_stats() -> dict:
    try:
        result = subprocess.run(
            ["rocm-smi", "--showallinfo", "--json"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
        return {"error": result.stderr.strip()}
    except FileNotFoundError:
        return {"error": "rocm-smi not found - is ROCm installed on the host?"}
    except Exception as exc:
        return {"error": str(exc)}


def get_system_stats() -> dict:
    stats: dict = {}
    # CPU usage via /proc/stat
    try:
        with open("/proc/stat") as fh:
            line = fh.readline()
        fields = list(map(int, line.split()[1:]))
        idle = fields[3]
        total = sum(fields)
        stats["cpu_idle_pct"] = round(idle * 100 / total, 1) if total else 0
    except Exception as exc:
        stats["cpu_error"] = str(exc)

    # Memory via /proc/meminfo
    try:
        meminfo: dict = {}
        with open("/proc/meminfo") as fh:
            for raw in fh:
                key, val = raw.split(":", 1)
                meminfo[key.strip()] = int(val.split()[0])
        total_kb = meminfo.get("MemTotal", 0)
        avail_kb = meminfo.get("MemAvailable", 0)
        stats["ram_total_gb"] = round(total_kb / 1048576, 1)
        stats["ram_available_gb"] = round(avail_kb / 1048576, 1)
        stats["ram_used_pct"] = round((total_kb - avail_kb) * 100 / total_kb, 1) if total_kb else 0
    except Exception as exc:
        stats["mem_error"] = str(exc)

    return stats


def get_service_status() -> dict:
    return {
        "vllm": _probe(f"{VLLM_URL}/health"),
        "qdrant": _probe(f"{QDRANT_URL}/healthz"),
    }


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, code: int, body: dict) -> None:
        payload = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:
        if self.path == "/health":
            self._send_json(200, {"status": "ok"})
        elif self.path == "/gpu":
            self._send_json(200, get_gpu_stats())
        elif self.path == "/system":
            self._send_json(200, get_system_stats())
        elif self.path == "/status":
            self._send_json(200, {
                "gpu": get_gpu_stats(),
                "system": get_system_stats(),
                "services": get_service_status(),
            })
        else:
            self._send_json(404, {"error": "not found"})

    def log_message(self, msg_format, *args):  # noqa: A002
        pass  # suppress default access log noise


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Brain Hardware Agent listening on :{PORT}", flush=True)
    server.serve_forever()
