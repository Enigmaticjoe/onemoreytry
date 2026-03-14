#!/usr/bin/env node
/**
 * Homelab Deploy GUI — Node.js web application
 * Visual GUI to deploy and administer all AI home-lab nodes from Fedora 44 (cosmic nightly).
 *
 * Access: http://localhost:9999
 * Endpoints:
 *   GET  /              → Dashboard HTML
 *   GET  /api/status    → Live status of all nodes/services
 *   POST /api/deploy    → Trigger a node deployment via SSH
 *   POST /api/portainer → Portainer stack operations
 *   POST /api/openclaw  → Trigger OpenClaw task
 *   POST /api/ssh       → Execute a command on a remote node
 *   GET  /api/settings  → Retrieve current settings
 *   POST /api/settings  → Save settings
 *   GET  /api/logs/:node → Stream container logs (Server-Sent Events)
 *   POST /api/audit     → SSH + connectivity audit for a single node (wizard)
 *   POST /api/portainer-install → Install Portainer CE on a remote node
 */

'use strict';

const http = require('http');
const https = require('https');
const { URL } = require('url');
const fs = require('fs');
const path = require('path');
const { execFile, spawn } = require('child_process');
const { escapeHtml, sendJson: _sendJson, readBody: _readBody } = require('../lib/http-utils');

const PORT = Number(process.env.DEPLOY_GUI_PORT || 9999);
const DATA_DIR = process.env.DATA_DIR || '/data';
const SETTINGS_FILE = path.join(DATA_DIR, 'settings.json');
const REQUEST_TIMEOUT_MS = 8000;
const MAX_BODY_BYTES = 64 * 1024;

// ── Default settings (overridden by SETTINGS_FILE) ──────────────────────────
const DEFAULT_SETTINGS = {
  nodes: {
    nodeA: { label: 'Node A (Brain)', ip: '192.168.1.9', sshUser: 'root', enabled: true },
    nodeB: { label: 'Node B (Unraid/LiteLLM)', ip: '192.168.1.222', sshUser: 'root', enabled: true },
    nodeC: { label: 'Node C (Intel Arc)', ip: '192.168.1.6', sshUser: 'root', enabled: true },
    nodeD: { label: 'Node D (Home Assistant)', ip: '192.168.1.149', sshUser: 'root', enabled: false },
    nodeE: { label: 'Node E (Blue Iris/Sentinel)', ip: '192.168.1.116', sshUser: 'root', enabled: false },
  },
  services: {
    litellm: { label: 'LiteLLM Gateway', url: 'http://192.168.1.222:4000/health/readiness' },
    ollama: { label: 'Ollama (Node C)', url: 'http://192.168.1.6:11434/api/version' },
    openwebui: { label: 'Chimera Face UI', url: 'http://192.168.1.6:3000' },
    nodeaDash: { label: 'Node A Dashboard', url: 'http://192.168.1.9:3099/api/status' },
    kvmOperator: { label: 'KVM Operator', url: 'http://192.168.1.9:5000/health' },
    openclaw: { label: 'OpenClaw Gateway', url: 'http://192.168.1.222:18789/' },
    portainer: { label: 'Portainer', url: 'http://192.168.1.222:9000/api/status' },
    deployGui: { label: 'Deploy GUI', url: 'http://localhost:9999/api/status' },
  },
  tokens: {
    litellmKey: 'sk-master-key',
    kvmOperatorToken: '',
    openclawToken: '',
    portainerToken: '',
  },
  portainerUrl: 'http://192.168.1.222:9000',
  openclawUrl: 'http://192.168.1.222:18789',
  kvmOperatorUrl: 'http://192.168.1.9:5000',
  cloudflare: {
    dashboardUrl: '',
    litellmUrl: '',
    openclawUrl: '',
    openwebuiUrl: '',
    portainerUrl: '',
    homeAssistantUrl: '',
  },
};

// Minimal safe environment for child processes — never pass full process.env
// to avoid leaking tokens, API keys, and other secrets from the parent process.
const SAFE_CHILD_ENV = {
  HOME: process.env.HOME || '/root',
  PATH: process.env.PATH || '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
  TERM: 'xterm',
};

// ── Settings persistence ─────────────────────────────────────────────────────
function ensureDataDir() {
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  } catch (_) {}
}

function loadSettings() {
  try {
    const raw = fs.readFileSync(SETTINGS_FILE, 'utf8');
    const parsed = JSON.parse(raw);
    return {
      ...DEFAULT_SETTINGS,
      ...parsed,
      nodes: { ...DEFAULT_SETTINGS.nodes, ...(parsed.nodes || {}) },
      services: { ...DEFAULT_SETTINGS.services, ...(parsed.services || {}) },
      tokens: { ...DEFAULT_SETTINGS.tokens, ...(parsed.tokens || {}) },
      cloudflare: { ...DEFAULT_SETTINGS.cloudflare, ...(parsed.cloudflare || {}) },
    };
  } catch (_) {
    return { ...DEFAULT_SETTINGS };
  }
}

function saveSettings(settings) {
  ensureDataDir();
  fs.writeFileSync(SETTINGS_FILE, JSON.stringify(settings, null, 2), 'utf8');
}

let settings = loadSettings();

// ── HTTP helpers ─────────────────────────────────────────────────────────────
// escapeHtml, sendJson, and readBody are provided by ../lib/http-utils.js.
// sendJson is wrapped here to always include the CORS header required by this service.
function sendJson(res, status, payload) { return _sendJson(res, status, payload, true); }
function readBody(req) { return _readBody(req, MAX_BODY_BYTES); }

async function fetchUrl(url, opts = {}) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const lib = parsed.protocol === 'https:' ? https : http;
    const options = {
      hostname: parsed.hostname,
      port: parsed.port || (parsed.protocol === 'https:' ? 443 : 80),
      path: parsed.pathname + parsed.search,
      method: opts.method || 'GET',
      headers: opts.headers || {},
      timeout: REQUEST_TIMEOUT_MS,
    };
    const req = lib.request(options, res => {
      let data = '';
      res.on('data', c => (data += c));
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
    req.on('error', reject);
    if (opts.body) req.write(opts.body);
    req.end();
  });
}

// ── Service status checker ───────────────────────────────────────────────────
async function checkService(key, svc) {
  const start = Date.now();
  try {
    const result = await fetchUrl(svc.url);
    return {
      key, label: svc.label, url: svc.url,
      ok: result.status >= 200 && result.status < 400,
      status: result.status,
      latencyMs: Date.now() - start,
    };
  } catch (err) {
    return {
      key, label: svc.label, url: svc.url,
      ok: false, status: 0,
      latencyMs: Date.now() - start,
      error: err.message === 'timeout' ? 'timeout' : 'unreachable',
    };
  }
}

// ── Deploy commands (per-node) ───────────────────────────────────────────────
const DEPLOY_SCRIPTS = {
  nodeC: {
    label: 'Node C (Intel Arc + Ollama)',
    local: true,
    commands: [
      'cd /homelab/node-c-arc && docker compose pull',
      'cd /homelab/node-c-arc && docker compose up -d',
      'sleep 15',
      "docker exec ollama_intel_arc ollama pull llava || true",
    ],
  },
  nodeB: {
    label: 'Node B LiteLLM Gateway',
    local: false,
    nodeKey: 'nodeB',
    commands: [
      'cd /mnt/user/appdata/homelab/node-b-litellm && docker compose -f litellm-stack.yml pull',
      'cd /mnt/user/appdata/homelab/node-b-litellm && docker compose -f litellm-stack.yml up -d',
    ],
  },
  openclaw: {
    label: 'OpenClaw (Node B)',
    local: false,
    nodeKey: 'nodeB',
    commands: [
      'cd /mnt/user/appdata/homelab/openclaw && docker compose pull',
      'cd /mnt/user/appdata/homelab/openclaw && docker compose up -d',
    ],
  },
  kvmOperator: {
    label: 'KVM Operator (Node A)',
    local: true,
    commands: [
      'cd /homelab/kvm-operator && python3 -m venv .venv',
      'cd /homelab/kvm-operator && source .venv/bin/activate && pip install -q -r requirements.txt',
      'systemctl restart ai-kvm-operator || echo "systemd unit not found — run ./run_dev.sh manually"',
    ],
  },
  nodeADash: {
    label: 'Node A Dashboard',
    local: true,
    commands: [
      'pkill -f node-a-command-center.js || true',
      'sleep 1',
      'cd /homelab/node-a-command-center && nohup node node-a-command-center.js > /tmp/node-a-dashboard.log 2>&1 &',
      'echo "Node A dashboard restarted, log: /tmp/node-a-dashboard.log"',
    ],
  },
};

// ── SSH exec helper ──────────────────────────────────────────────────────────
function sshExec(host, user, command) {
  return new Promise((resolve) => {
    const sshArgs = [
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'ConnectTimeout=10',
      '-o', 'BatchMode=yes',
      `${user}@${host}`,
      command,
    ];
    const proc = execFile('ssh', sshArgs, { timeout: 60000 }, (err, stdout, stderr) => {
      resolve({
        ok: !err,
        stdout: stdout || '',
        stderr: stderr || '',
        error: err ? err.message : null,
      });
    });
    return proc;
  });
}

// ── SSH exec with stdin piping (for multi-line scripts) ───────────────────────
function sshExecStdin(host, user, stdinScript, timeoutMs) {
  return new Promise((resolve) => {
    const proc = spawn('ssh', [
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'ConnectTimeout=10',
      '-o', 'BatchMode=yes',
      `${user}@${host}`,
      'bash -s',
    ], { env: SAFE_CHILD_ENV, timeout: timeoutMs || 60000 });

    let stdout = ''; let stderr = '';
    proc.stdout.on('data', d => { stdout += d; });
    proc.stderr.on('data', d => { stderr += d; });
    proc.on('close', code => resolve({ ok: code === 0, stdout, stderr, error: code !== 0 ? `exit code ${code}` : null }));
    proc.on('error', err => resolve({ ok: false, stdout, stderr, error: err.message }));

    const timer = setTimeout(() => {
      try { proc.kill(); } catch (_) {}
      resolve({ ok: false, stdout, stderr, error: `SSH command timed out after ${timeoutMs || 60000}ms` });
    }, (timeoutMs || 60000) + 2000);
    proc.on('close', () => clearTimeout(timer));

    proc.stdin.write(stdinScript);
    proc.stdin.end();
  });
}

// ── Portainer API helper ─────────────────────────────────────────────────────
async function portainerRequest(endpoint, method = 'GET', body = null) {
  const url = `${settings.portainerUrl}/api${endpoint}`;
  const headers = { 'Content-Type': 'application/json' };
  if (settings.tokens.portainerToken) {
    headers['X-API-Key'] = settings.tokens.portainerToken;
  }
  try {
    const result = await fetchUrl(url, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });
    return { ok: result.status < 400, status: result.status, body: result.body };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

// ── OpenClaw API helper ──────────────────────────────────────────────────────
async function openclawTask(message) {
  const url = `${settings.openclawUrl}/hooks/agent`;
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${settings.tokens.openclawToken}`,
  };
  try {
    const result = await fetchUrl(url, {
      method: 'POST',
      headers,
      body: JSON.stringify({ message }),
    });
    return { ok: result.status < 400, status: result.status, body: result.body };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

// ── HTML Dashboard ────────────────────────────────────────────────────────────
function renderDashboard() {
  const s = settings;
  const nodesJson = JSON.stringify(s.nodes);
  const servicesJson = JSON.stringify(s.services);
  const tokensJson = JSON.stringify({ ...s.tokens, portainerToken: '***', openclawToken: '***', kvmOperatorToken: '***' });
  const deployTargetsJson = JSON.stringify(Object.entries(DEPLOY_SCRIPTS).map(([k, v]) => ({ key: k, label: v.label })));

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>🚀 Homelab Deploy GUI</title>
<style>
  :root {
    --bg: #050811; --surface: rgba(255,255,255,0.04); --surface2: rgba(255,255,255,0.07);
    --border: rgba(255,255,255,0.08); --accent: #7c6af7; --accent2: #5ce65c;
    --warn: #f0a500; --danger: #e74c3c; --text: #e8eaf6;
    --text2: #9197b3; --green: #27ae60; --red: #e74c3c;
    --glass-shadow: 0 8px 32px rgba(0,0,0,0.5), 0 1px 0 rgba(255,255,255,0.05) inset;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    background: var(--bg);
    background-image:
      radial-gradient(ellipse 80% 50% at 15% 5%, rgba(124,106,247,0.2) 0%, transparent 60%),
      radial-gradient(ellipse 60% 40% at 85% 85%, rgba(92,230,92,0.09) 0%, transparent 60%);
    color: var(--text); font-family: 'Segoe UI', system-ui, sans-serif; font-size: 14px; min-height: 100vh;
  }
  header {
    background: rgba(255,255,255,0.03);
    backdrop-filter: blur(16px); -webkit-backdrop-filter: blur(16px);
    border-bottom: 1px solid var(--border);
    padding: 12px 24px; display: flex; align-items: center; gap: 12px;
    position: sticky; top: 0; z-index: 100;
  }
  header h1 { font-size: 20px; font-weight: 700; }
  header span { font-size: 13px; color: var(--text2); }
  .tabs {
    display: flex;
    background: rgba(255,255,255,0.02);
    backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px);
    border-bottom: 1px solid var(--border); padding: 0 24px;
    position: sticky; top: 49px; z-index: 99;
  }
  .tab { padding: 10px 18px; cursor: pointer; border-bottom: 3px solid transparent; color: var(--text2); font-size: 13px; transition: all 0.15s; user-select: none; }
  .tab:hover { color: var(--text); }
  .tab.active { color: var(--accent); border-color: var(--accent); }
  .panel { display: none; padding: 24px; max-width: 1200px; }
  .panel.active { display: block; }
  .grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
  .grid3 { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; }
  .card {
    background: var(--surface);
    backdrop-filter: blur(16px); -webkit-backdrop-filter: blur(16px);
    border: 1px solid var(--border); border-radius: 14px; padding: 16px;
    box-shadow: var(--glass-shadow);
    transition: border-color 0.2s;
  }
  .card:hover { border-color: rgba(124,106,247,0.25); }
  .card h3 { font-size: 13px; color: var(--text2); margin-bottom: 12px; text-transform: uppercase; letter-spacing: 0.05em; }
  .status-row { display: flex; align-items: center; gap: 8px; padding: 6px 0; border-bottom: 1px solid rgba(255,255,255,0.05); }
  .status-row:last-child { border-bottom: none; }
  .dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
  .dot.green { background: var(--green); box-shadow: 0 0 8px var(--green); }
  .dot.red { background: var(--red); box-shadow: 0 0 8px var(--red); }
  .dot.gray { background: #555; }
  .dot.checking { background: var(--warn); animation: pulse 1s infinite; }
  @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.4} }
  .svc-label { flex: 1; }
  .svc-url { font-size: 11px; color: var(--text2); }
  .svc-latency { font-size: 11px; color: var(--text2); margin-left: auto; }
  button {
    background: linear-gradient(135deg, var(--accent), #5b50c8);
    color: #fff; border: none; border-radius: 8px; padding: 8px 16px;
    cursor: pointer; font-size: 13px; font-weight: 500; transition: opacity 0.15s, transform 0.1s;
  }
  button:hover { opacity: 0.88; transform: translateY(-1px); }
  button:active { transform: translateY(0); }
  button.secondary { background: var(--surface2); border: 1px solid var(--border); color: var(--text); }
  button.secondary:hover { transform: none; opacity: 0.9; }
  button.danger { background: linear-gradient(135deg, var(--danger), #b73128); }
  button.success { background: linear-gradient(135deg, var(--green), #1e8449); }
  button:disabled { opacity: 0.4; cursor: not-allowed; transform: none; }
  .deploy-item {
    background: var(--surface2); border: 1px solid var(--border); border-radius: 10px;
    padding: 14px 16px; margin-bottom: 10px; display: flex; align-items: center; gap: 12px;
    transition: border-color 0.2s;
  }
  .deploy-item:hover { border-color: rgba(124,106,247,0.3); }
  .deploy-label { flex: 1; font-weight: 500; }
  .deploy-sub { font-size: 12px; color: var(--text2); }
  .terminal {
    background: rgba(0,0,0,0.5); border: 1px solid var(--border); border-radius: 10px;
    padding: 12px; font-family: 'Courier New', monospace; font-size: 12px; line-height: 1.6;
    min-height: 200px; max-height: 420px; overflow-y: auto; color: #a8ff78; white-space: pre-wrap; word-break: break-all;
  }
  .terminal .err { color: var(--danger); }
  .terminal .info { color: var(--accent); }
  .terminal .ok { color: var(--green); }
  input, select, textarea {
    background: rgba(0,0,0,0.3); border: 1px solid var(--border);
    border-radius: 8px; padding: 8px 12px; color: var(--text); font-size: 13px; width: 100%;
  }
  input:focus, textarea:focus { outline: none; border-color: rgba(124,106,247,0.5); box-shadow: 0 0 0 3px rgba(124,106,247,0.15); }
  label { display: block; font-size: 12px; color: var(--text2); margin-bottom: 4px; margin-top: 10px; }
  .field-row { display: flex; gap: 10px; align-items: flex-end; }
  .field-row > * { flex: 1; }
  .badge { display: inline-block; font-size: 11px; padding: 2px 8px; border-radius: 99px; }
  .badge.ok { background: rgba(39,174,96,0.2); color: var(--green); border: 1px solid rgba(39,174,96,0.3); }
  .badge.fail { background: rgba(231,76,60,0.2); color: var(--red); border: 1px solid rgba(231,76,60,0.3); }
  .badge.warn { background: rgba(240,165,0,0.2); color: var(--warn); border: 1px solid rgba(240,165,0,0.3); }
  .stack-item { background: var(--surface2); border: 1px solid var(--border); border-radius: 10px; padding: 12px 14px; margin-bottom: 8px; }
  .stack-header { display: flex; align-items: center; gap: 10px; }
  .stack-name { flex: 1; font-weight: 500; }
  .stack-actions { display: flex; gap: 6px; }
  .hint { font-size: 11px; color: var(--text2); margin-top: 4px; }
  #settingsSaveStatus { font-size: 13px; color: var(--green); margin-left: 12px; display: none; }
  .section-title { font-size: 16px; font-weight: 600; margin-bottom: 14px; }
  .refresh-btn { background: var(--surface2); border: 1px solid var(--border); color: var(--text2); padding: 4px 10px; font-size: 12px; border-radius: 6px; cursor: pointer; transition: color 0.15s; }
  .refresh-btn:hover { color: var(--text); transform: none; opacity: 1; }
  .openclaw-response { background: rgba(0,0,0,0.4); border: 1px solid var(--border); border-radius: 10px; padding: 12px; font-size: 13px; min-height: 80px; max-height: 300px; overflow-y: auto; white-space: pre-wrap; color: #e8eaf6; display: none; }
  .links-grid { display:grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap:10px; }
  .link-item {
    display:block; padding:12px; border:1px solid var(--border); border-radius:10px;
    text-decoration:none; color:var(--text); background:var(--surface2);
    transition: border-color 0.2s, background 0.2s;
  }
  .link-item:hover { border-color: var(--accent); background: rgba(124,106,247,0.08); }
  .link-title { font-weight:600; font-size:13px; }
  .link-sub { color:var(--text2); font-size:11px; margin-top:4px; word-break: break-all; }
  .chat-shell { display:flex; flex-direction:column; gap:10px; }
  .chat-response { background: rgba(0,0,0,0.4); border:1px solid var(--border); border-radius:10px; padding:12px; min-height:140px; white-space:pre-wrap; color:#e8eaf6; }
  /* ── Installation Wizard ── */
  .wizard-steps { display:flex; gap:0; margin-bottom:24px; overflow-x:auto; padding-bottom:4px; }
  .wstep { display:flex; align-items:center; gap:0; flex-shrink:0; }
  .wstep-node { display:flex; flex-direction:column; align-items:center; cursor:pointer; padding:6px 12px; border-radius:10px; transition:background 0.15s; min-width:80px; }
  .wstep-node:hover { background:var(--surface2); }
  .wstep-num { width:28px; height:28px; border-radius:50%; display:flex; align-items:center; justify-content:center; font-size:13px; font-weight:700; background:var(--surface2); border:2px solid var(--border); color:var(--text2); transition:all 0.2s; }
  .wstep-num.active { background:var(--accent); border-color:var(--accent); color:#fff; box-shadow:0 0 12px rgba(124,106,247,0.5); }
  .wstep-num.done { background:var(--green); border-color:var(--green); color:#fff; }
  .wstep-label { font-size:10px; color:var(--text2); margin-top:4px; text-align:center; white-space:nowrap; }
  .wstep-label.active { color:var(--accent); font-weight:600; }
  .wstep-label.done { color:var(--green); }
  .wstep-arrow { color:var(--border); font-size:18px; padding:0 2px; margin-top:-4px; }
  .wizard-body { min-height:320px; }
  .audit-node-card { background:var(--surface2); border:1px solid var(--border); border-radius:12px; padding:16px; margin-bottom:12px; }
  .audit-node-header { display:flex; align-items:center; gap:10px; margin-bottom:8px; }
  .audit-node-label { flex:1; font-weight:600; }
  .audit-checks { display:flex; flex-direction:column; gap:4px; margin-top:6px; }
  .audit-check { display:flex; align-items:center; gap:8px; font-size:12px; }
  .audit-fixes { margin-top:8px; padding:8px; background:rgba(240,165,0,0.08); border:1px solid rgba(240,165,0,0.2); border-radius:8px; font-size:12px; }
  .audit-fix-item { padding:2px 0; color:var(--warn); }
  .inv-table { width:100%; border-collapse:collapse; font-size:12px; }
  .inv-table th { text-align:left; padding:6px 8px; color:var(--text2); border-bottom:1px solid var(--border); }
  .inv-table td { padding:6px 8px; border-bottom:1px solid rgba(255,255,255,0.04); }
  .wz-nav { display:flex; gap:10px; margin-top:20px; }
  .wz-node-row { display:grid; grid-template-columns:1fr 1fr 100px; gap:10px; margin-bottom:8px; align-items:end; }
  .portainer-install-card { background:var(--surface2); border:1px solid var(--border); border-radius:12px; padding:16px; margin-bottom:12px; }
  .portainer-install-header { display:flex; align-items:center; gap:10px; margin-bottom:8px; }
</style>
</head>
<body>
<header>
  <span style="font-size:24px">🚀</span>
  <h1>Homelab Deploy GUI</h1>
  <span>Grand Unified AI Home Lab — Command Center + Cloudflare Access</span>
  <span style="margin-left:auto;font-size:12px;color:var(--text2)" id="clock"></span>
</header>
<div class="tabs">
  <div class="tab active" onclick="showTab('overview')">📊 Overview</div>
  <div class="tab" onclick="showTab('deploy')">🚀 Deploy</div>
  <div class="tab" onclick="showTab('portainer')">📦 Portainer</div>
  <div class="tab" onclick="showTab('ssh')">💻 Terminal</div>
  <div class="tab" onclick="showTab('openclaw')">🤖 OpenClaw</div>
  <div class="tab" onclick="showTab('settings')">⚙️ Settings</div>
  <div class="tab" onclick="showTab('wizard')">🧙 Setup Wizard</div>
</div>

<!-- OVERVIEW TAB -->
<div class="panel active" id="tab-overview">
  <div style="display:flex;align-items:center;gap:10px;margin-bottom:18px">
    <span class="section-title">Service Status</span>
    <button class="refresh-btn" onclick="refreshStatus()">↺ Refresh</button>
    <span id="lastChecked" style="font-size:11px;color:var(--text2)"></span>
  </div>
  <div class="grid2">
    <div class="card">
      <h3>🖥️ AI Services</h3>
      <div id="statusList">
        <div class="status-row"><div class="dot checking"></div><span>Checking services…</span></div>
      </div>
    </div>
    <div class="card">
      <h3>⚡ Quick Actions</h3>
      <div style="display:flex;flex-direction:column;gap:8px">
        <button onclick="quickDeploy('nodeC')">▶ Start Node C (Ollama)</button>
        <button onclick="quickDeploy('nodeB')">▶ Start Node B (LiteLLM)</button>
        <button onclick="quickDeploy('nodeADash')">▶ Restart Node A Dashboard</button>
        <button onclick="quickDeploy('kvmOperator')">▶ Restart KVM Operator</button>
        <button class="secondary" onclick="runValidate()">✓ Run validate.sh</button>
        <button class="secondary" onclick="runPreflight()">🔍 Run Preflight Check</button>
      </div>
    </div>
  </div>
  <div style="margin-top:16px" class="card">
    <h3>📟 Quick Log</h3>
    <div class="terminal" id="quickLog">Ready. Use Quick Actions above or Deploy tab to run commands.</div>
  </div>
  <div style="margin-top:16px" class="grid2">
    <div class="card">
      <h3>🌐 Ecosystem Links (Local + Cloudflare)</h3>
      <div id="ecosystemLinks" class="links-grid"></div>
    </div>
    <div class="card">
      <h3>🧭 Ecosystem Assistant</h3>
      <div class="chat-shell">
        <textarea id="ecosystemChatInput" rows="3" placeholder="Ask: where is Home Assistant, how do I deploy Node B, show Cloudflare links, suggest next checks"></textarea>
        <div style="display:flex;gap:8px">
          <button onclick="askEcosystemAssistant()">Ask Assistant</button>
          <button class="secondary" onclick="fillOpenclawMsg(document.getElementById('ecosystemChatInput').value);showTab('openclaw')">Send to OpenClaw</button>
        </div>
        <div id="ecosystemChatResponse" class="chat-response">Assistant ready. I can index local services, Cloudflare URLs, and suggest next actions.</div>
      </div>
    </div>
  </div>

</div>

<!-- DEPLOY TAB -->
<div class="panel" id="tab-deploy">
  <div class="section-title">Deploy Nodes</div>
  <div id="deployList"></div>
  <div style="margin-top:16px" class="card">
    <h3>🗂️ Custom Command</h3>
    <label>Node / Target</label>
    <select id="customTarget">
      <option value="local">Local (this machine)</option>
      <option value="nodeB">Node B (Unraid)</option>
      <option value="nodeC">Node C (Intel Arc)</option>
      <option value="nodeD">Node D (Home Assistant)</option>
      <option value="nodeE">Node E (Sentinel)</option>
    </select>
    <label>Command</label>
    <input type="text" id="customCmd" placeholder="docker ps -a" style="font-family:monospace">
    <div style="margin-top:8px">
      <button onclick="runCustomCommand()">▶ Execute</button>
    </div>
    <div class="terminal" id="deployLog" style="margin-top:12px;display:none"></div>
  </div>
</div>

<!-- PORTAINER TAB -->
<div class="panel" id="tab-portainer">
  <div style="display:flex;align-items:center;gap:10px;margin-bottom:18px">
    <span class="section-title">Portainer Stacks</span>
    <button class="refresh-btn" onclick="loadPortainerStacks()">↺ Refresh</button>
  </div>
  <div id="portainerStatus" style="margin-bottom:12px"></div>
  <div id="stackList">
    <div style="color:var(--text2)">Click Refresh to load stacks from Portainer…</div>
  </div>
  <div style="margin-top:16px" class="card">
    <h3>📋 Portainer API — Stack Operations</h3>
    <p class="hint">Enter your Portainer URL and API token in ⚙️ Settings, then use the buttons above to manage stacks.</p>
    <div style="margin-top:10px">
      <a href="${settings.portainerUrl}" target="_blank" style="color:var(--accent)">
        Open Portainer → ${escapeHtml(settings.portainerUrl)}
      </a>
    </div>
  </div>
</div>

<!-- SSH TERMINAL TAB -->
<div class="panel" id="tab-ssh">
  <div class="section-title">Remote Terminal</div>
  <div class="card">
    <div class="field-row">
      <div>
        <label>Target Node</label>
        <select id="sshTarget">
          <option value="local">Local (this machine)</option>
          <option value="nodeB">Node B (${escapeHtml(settings.nodes.nodeB.ip)})</option>
          <option value="nodeC">Node C (${escapeHtml(settings.nodes.nodeC.ip)})</option>
          <option value="nodeD">Node D (${escapeHtml(settings.nodes.nodeD.ip)})</option>
          <option value="nodeE">Node E (${escapeHtml(settings.nodes.nodeE.ip)})</option>
        </select>
      </div>
      <div>
        <label>Command</label>
        <input type="text" id="sshCmd" placeholder="docker ps -a" style="font-family:monospace"
               onkeydown="if(event.key==='Enter')runSshCmd()">
      </div>
      <div style="flex:0;padding-bottom:2px">
        <button onclick="runSshCmd()">▶ Run</button>
      </div>
    </div>
    <div class="hint" style="margin-top:6px">SSH must be configured with key-based auth. See GUIDEBOOK.md §0.4.</div>
  </div>
  <div class="terminal" id="sshLog" style="margin-top:14px;min-height:300px">SSH output will appear here…</div>
</div>

<!-- OPENCLAW TAB -->
<div class="panel" id="tab-openclaw">
  <div class="section-title">🤖 OpenClaw AI Agent</div>
  <div class="grid2">
    <div class="card">
      <h3>Send Task</h3>
      <label>Message / Task Description</label>
      <textarea id="openclawMsg" rows="4"
        placeholder="E.g.: Check if all Docker stacks are healthy on Node B and summarize any issues."></textarea>
      <div style="margin-top:8px;display:flex;gap:8px">
        <button onclick="sendOpenclawTask()">🤖 Send to OpenClaw</button>
        <button class="secondary" onclick="openOpenclawUI()">🔗 Open UI</button>
      </div>
    </div>
    <div class="card">
      <h3>Quick Prompts</h3>
      <div style="display:flex;flex-direction:column;gap:6px">
        ${[
          'Give me a status report of all my AI nodes',
          'List all running Docker containers on Node B',
          'Restart the litellm_gateway container',
          'Take a screenshot of node-c via KVM',
          'Check LiteLLM gateway health and list available models',
          'Deploy the full AI lab stack in the correct order',
        ].map(p => `<button class="secondary" onclick="fillOpenclawMsg(${JSON.stringify(p)})">${escapeHtml(p)}</button>`).join('')}
      </div>
    </div>
  </div>
  <div class="card" style="margin-top:14px">
    <h3>Response</h3>
    <div class="openclaw-response" id="openclawResponse"></div>
    <div style="color:var(--text2);font-size:12px;margin-top:6px" id="openclawStatus"></div>
  </div>
</div>

<!-- SETTINGS TAB -->
<div class="panel" id="tab-settings">
  <div class="section-title">Settings</div>
  <div class="grid2">
    <div class="card">
      <h3>Node IP Addresses</h3>
      <label>Node A IP (Brain)</label>
      <input type="text" id="nodeAIp" value="${escapeHtml(settings.nodes.nodeA.ip)}">
      <label>Node B IP (Unraid/LiteLLM)</label>
      <input type="text" id="nodeBIp" value="${escapeHtml(settings.nodes.nodeB.ip)}">
      <label>Node C IP (Intel Arc)</label>
      <input type="text" id="nodeCIp" value="${escapeHtml(settings.nodes.nodeC.ip)}">
      <label>Node D IP (Home Assistant)</label>
      <input type="text" id="nodeDIp" value="${escapeHtml(settings.nodes.nodeD.ip)}">
      <label>Node E IP (Sentinel)</label>
      <input type="text" id="nodeEIp" value="${escapeHtml(settings.nodes.nodeE.ip)}">
    </div>

    <div class="card">
      <h3>Cloudflare Public URLs</h3>
      <label>Dashboard URL</label>
      <input type="text" id="cfDashboardUrl" value="${escapeHtml(settings.cloudflare.dashboardUrl || '')}" placeholder="https://dashboard.example.com">
      <label>LiteLLM URL</label>
      <input type="text" id="cfLitellmUrl" value="${escapeHtml(settings.cloudflare.litellmUrl || '')}" placeholder="https://litellm.example.com">
      <label>OpenClaw URL</label>
      <input type="text" id="cfOpenclawUrl" value="${escapeHtml(settings.cloudflare.openclawUrl || '')}" placeholder="https://openclaw.example.com">
      <label>OpenWebUI URL</label>
      <input type="text" id="cfOpenwebuiUrl" value="${escapeHtml(settings.cloudflare.openwebuiUrl || '')}" placeholder="https://chat.example.com">
      <label>Portainer URL</label>
      <input type="text" id="cfPortainerUrl" value="${escapeHtml(settings.cloudflare.portainerUrl || '')}" placeholder="https://portainer.example.com">
      <label>Home Assistant URL</label>
      <input type="text" id="cfHomeAssistantUrl" value="${escapeHtml(settings.cloudflare.homeAssistantUrl || '')}" placeholder="https://ha.example.com">
    </div>
    <div class="card">
      <h3>Tokens & Keys</h3>
      <label>LiteLLM API Key</label>
      <input type="password" id="litellmKey" value="${escapeHtml(settings.tokens.litellmKey)}">
      <label>KVM Operator Token</label>
      <input type="password" id="kvmToken" value="${escapeHtml(settings.tokens.kvmOperatorToken)}">
      <label>OpenClaw Gateway Token</label>
      <input type="password" id="openclawToken" value="${escapeHtml(settings.tokens.openclawToken)}">
      <label>Portainer API Token</label>
      <input type="password" id="portainerToken" value="${escapeHtml(settings.tokens.portainerToken)}">
    </div>
  </div>
  <div style="margin-top:14px;display:flex;align-items:center;gap:10px">
    <button onclick="saveSettings()">💾 Save Settings</button>
    <span id="settingsSaveStatus">✓ Saved!</span>
  </div>
</div>

<!-- SETUP WIZARD TAB -->
<div class="panel" id="tab-wizard">
  <!-- Populated by renderWizard() on tab activation -->
  <div style="color:var(--text2);padding:40px;text-align:center">
    Loading wizard… <span style="animation:pulse 1s infinite">⚡</span>
  </div>
</div>

<script>
// ── State ─────────────────────────────────────────────────────────────────
const DEPLOY_TARGETS = ${deployTargetsJson};
const nodes = ${nodesJson};
const settings = { nodes, services: ${servicesJson}, portainerUrl: ${JSON.stringify(s.portainerUrl)}, openclawUrl: ${JSON.stringify(s.openclawUrl)} };
let statusData = [];

// ── Clock ─────────────────────────────────────────────────────────────────
function updateClock() {
  document.getElementById('clock').textContent = new Date().toLocaleTimeString();
}
setInterval(updateClock, 1000);
updateClock();

// ── Tabs ──────────────────────────────────────────────────────────────────
function showTab(name) {
  document.querySelectorAll('.tab').forEach((t, i) => t.classList.toggle('active', t.textContent.toLowerCase().includes(name) || (name === 'overview' && i === 0)));
  document.querySelectorAll('.panel').forEach(p => p.classList.toggle('active', p.id === 'tab-' + name));
  if (name === 'overview') refreshStatus();
  if (name === 'deploy') renderDeployList();
  if (name === 'portainer') loadPortainerStacks();
  if (name === 'wizard') renderWizard();
}

// ── Status ────────────────────────────────────────────────────────────────
async function refreshStatus() {
  document.getElementById('statusList').innerHTML =
    '<div class="status-row"><div class="dot checking"></div><span>Checking services…</span></div>';
  try {
    const r = await fetch('/api/status');
    const data = await r.json();
    statusData = data.services || [];
    renderStatusList(statusData);
    document.getElementById('lastChecked').textContent = 'Last checked: ' + new Date().toLocaleTimeString();
  } catch(e) {
    document.getElementById('statusList').innerHTML =
      '<div class="status-row"><div class="dot red"></div><span>Failed to fetch status</span></div>';
  }
}


function buildEcosystemIndex() {
  const links = [
    { name: 'Node A Dashboard (local)', url: 'http://' + settings.nodes.nodeA.ip + ':3099', group: 'local' },
    { name: 'LiteLLM Gateway (local)', url: 'http://' + settings.nodes.nodeB.ip + ':4000', group: 'local' },
    { name: 'OpenClaw Gateway (local)', url: 'http://' + settings.nodes.nodeB.ip + ':18789', group: 'local' },
    { name: 'Portainer (local)', url: settings.portainerUrl, group: 'local' },
    { name: 'Ollama API (local)', url: 'http://' + settings.nodes.nodeC.ip + ':11434', group: 'local' },
    { name: 'Chimera Face UI (local)', url: 'http://' + settings.nodes.nodeC.ip + ':3000', group: 'local' },
    { name: 'KVM Operator (local)', url: settings.kvmOperatorUrl, group: 'local' },
    { name: 'Home Assistant (local)', url: 'http://' + settings.nodes.nodeD.ip + ':8123', group: 'local' },
    { name: 'Blue Iris / Sentinel (local)', url: 'http://' + settings.nodes.nodeE.ip + ':81', group: 'local' },
    { name: 'Deploy GUI (local)', url: 'http://localhost:9999', group: 'local' },
    { name: 'Dashboard (Cloudflare)', url: settings.cloudflare.dashboardUrl, group: 'cloudflare' },
    { name: 'LiteLLM (Cloudflare)', url: settings.cloudflare.litellmUrl, group: 'cloudflare' },
    { name: 'OpenClaw (Cloudflare)', url: settings.cloudflare.openclawUrl, group: 'cloudflare' },
    { name: 'OpenWebUI (Cloudflare)', url: settings.cloudflare.openwebuiUrl, group: 'cloudflare' },
    { name: 'Portainer (Cloudflare)', url: settings.cloudflare.portainerUrl, group: 'cloudflare' },
    { name: 'Home Assistant (Cloudflare)', url: settings.cloudflare.homeAssistantUrl, group: 'cloudflare' },
  ];
  return links.filter(l => l.url);
}

function renderEcosystemLinks() {
  const links = buildEcosystemIndex();
  const el = document.getElementById('ecosystemLinks');
  if (!el) return;
  if (!links.length) {
    el.innerHTML = '<div style="color:var(--text2)">No links configured yet. Add Cloudflare URLs in Settings.</div>';
    return;
  }
  el.innerHTML = links.map(link => {
    return '<a class="link-item" href="' + link.url + '" target="_blank" rel="noreferrer noopener">' +
      '<div class="link-title">' + link.name + '</div>' +
      '<div class="link-sub">' + link.url + '</div>' +
      '</a>';
  }).join('');
}

function askEcosystemAssistant() {
  const input = (document.getElementById('ecosystemChatInput').value || '').trim();
  const out = document.getElementById('ecosystemChatResponse');
  if (!input) {
    out.textContent = 'Ask a question first. Example: show me Cloudflare links for OpenClaw and Home Assistant.';
    return;
  }

  const query = input.toLowerCase();
  const links = buildEcosystemIndex();
  const words = query.split(/\s+/).filter(Boolean);
  const matches = links.filter(link => words.some(w => link.name.toLowerCase().includes(w) || link.url.toLowerCase().includes(w)));

  const suggestions = [];
  if (query.includes('deploy') || query.includes('restart')) suggestions.push('Use the Deploy tab to run Node deploy targets, then review logs in Quick Log.');
  if (query.includes('health') || query.includes('status') || query.includes('down')) suggestions.push('Run Refresh in Overview, then run ./scripts/preflight-check.sh from Quick Actions for a full health report.');
  if (query.includes('cloudflare') || query.includes('public')) suggestions.push('Validate Cloudflare tunnel DNS + ingress, then save/update the Cloudflare URLs in Settings for one-click access.');
  if (query.includes('find') || query.includes('where') || query.includes('link')) suggestions.push('Use the Ecosystem Links card to open local and Cloudflare endpoints directly.');

  let text = 'Query: ' + input + '\n\nIndexed endpoints: ' + links.length;
  if (matches.length) {
    text += '\n\nBest matches (' + matches.length + '):\n' + matches.slice(0, 8).map((m, i) => (i + 1) + '. ' + m.name + ' -> ' + m.url).join('\n');
  } else {
    text += '\n\nNo direct endpoint match. Try keywords like: litellm, openclaw, dashboard, home assistant, portainer, cloudflare.';
  }
  if (suggestions.length) {
    text += '\n\nSuggested next actions:\n' + suggestions.map((v, i) => (i + 1) + '. ' + v).join('\n');
  }
  out.textContent = text;
}

function renderStatusList(services) {
  const el = document.getElementById('statusList');
  el.innerHTML = services.map(s => {
    const cls = s.ok ? 'green' : 'red';
    const lat = s.latencyMs ? s.latencyMs + 'ms' : '';
    return \`<div class="status-row">
      <div class="dot \${cls}"></div>
      <div class="svc-label">\${s.label}</div>
      <div class="svc-url">\${s.url || ''}</div>
      <div class="svc-latency">\${lat}</div>
      <span class="badge \${s.ok ? 'ok' : 'fail'}">\${s.ok ? 'UP' : (s.error || 'DOWN')}</span>
    </div>\`;
  }).join('');
}

// ── Deploy list ───────────────────────────────────────────────────────────
function renderDeployList() {
  const el = document.getElementById('deployList');
  el.innerHTML = DEPLOY_TARGETS.map(t => \`
    <div class="deploy-item">
      <div>
        <div class="deploy-label">\${t.label}</div>
      </div>
      <button onclick="quickDeploy('\${t.key}')">🚀 Deploy</button>
    </div>
  \`).join('');
}

function quickDeploy(key) {
  appendLog('quickLog', 'info', '→ Deploying ' + key + '…');
  fetch('/api/deploy', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ target: key }),
  }).then(r => r.json()).then(data => {
    if (data.output) appendLog('quickLog', data.ok ? 'ok' : 'err', data.output);
    else appendLog('quickLog', data.ok ? 'ok' : 'err', data.ok ? '✓ Done' : ('✗ Error: ' + (data.error || 'unknown')));
  }).catch(e => appendLog('quickLog', 'err', '✗ ' + e.message));
}

function runValidate() {
  appendLog('quickLog', 'info', '→ Running validate.sh…');
  fetch('/api/ssh', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ target: 'local', command: 'cd /homelab && ./validate.sh 2>&1' }),
  }).then(r => r.json()).then(d => {
    appendLog('quickLog', d.ok ? 'ok' : 'err', d.stdout + (d.stderr ? '\\nSTDERR: ' + d.stderr : ''));
  }).catch(e => appendLog('quickLog', 'err', '✗ ' + e.message));
}

function runPreflight() {
  appendLog('quickLog', 'info', '→ Running preflight-check.sh…');
  fetch('/api/ssh', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ target: 'local', command: 'cd /homelab && ./scripts/preflight-check.sh 2>&1' }),
  }).then(r => r.json()).then(d => {
    appendLog('quickLog', d.ok ? 'ok' : 'err', d.stdout + (d.stderr ? '\\nSTDERR: ' + d.stderr : ''));
  }).catch(e => appendLog('quickLog', 'err', '✗ ' + e.message));
}

// ── Custom command ─────────────────────────────────────────────────────────
function runCustomCommand() {
  const target = document.getElementById('customTarget').value;
  const cmd = document.getElementById('customCmd').value.trim();
  if (!cmd) return;
  const log = document.getElementById('deployLog');
  log.style.display = 'block';
  appendLog('deployLog', 'info', '→ [' + target + '] ' + cmd);
  fetch('/api/ssh', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ target, command: cmd }),
  }).then(r => r.json()).then(d => {
    appendLog('deployLog', d.ok ? 'ok' : 'err',
      d.stdout + (d.stderr ? '\\nSTDERR: ' + d.stderr : '') + (d.error ? '\\nERROR: ' + d.error : ''));
  }).catch(e => appendLog('deployLog', 'err', '✗ ' + e.message));
}

// ── SSH tab ────────────────────────────────────────────────────────────────
function runSshCmd() {
  const target = document.getElementById('sshTarget').value;
  const cmd = document.getElementById('sshCmd').value.trim();
  if (!cmd) return;
  appendLog('sshLog', 'info', '$ [' + target + '] ' + cmd);
  fetch('/api/ssh', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ target, command: cmd }),
  }).then(r => r.json()).then(d => {
    if (d.stdout) appendLog('sshLog', '', d.stdout);
    if (d.stderr) appendLog('sshLog', 'err', d.stderr);
    if (d.error) appendLog('sshLog', 'err', 'ERROR: ' + d.error);
    if (!d.stdout && !d.stderr && !d.error) appendLog('sshLog', 'ok', '(no output)');
  }).catch(e => appendLog('sshLog', 'err', '✗ ' + e.message));
}

// ── Portainer ─────────────────────────────────────────────────────────────
async function loadPortainerStacks() {
  document.getElementById('stackList').innerHTML = '<div style="color:var(--text2)">Loading stacks…</div>';
  try {
    const r = await fetch('/api/portainer?action=list_stacks');
    const data = await r.json();
    if (!data.ok) {
      document.getElementById('portainerStatus').innerHTML =
        '<span class="badge fail">Cannot reach Portainer — check URL and token in Settings</span>';
      document.getElementById('stackList').innerHTML = '';
      return;
    }
    document.getElementById('portainerStatus').innerHTML =
      '<span class="badge ok">Portainer connected</span>';
    const stacks = Array.isArray(data.stacks) ? data.stacks : [];
    if (stacks.length === 0) {
      document.getElementById('stackList').innerHTML = '<div style="color:var(--text2)">No stacks found.</div>';
      return;
    }
    document.getElementById('stackList').innerHTML = stacks.map(st => {
      const running = st.Status === 1;
      return \`<div class="stack-item">
        <div class="stack-header">
          <span class="dot \${running ? 'green' : 'red'}"></span>
          <span class="stack-name">\${st.Name || st.name || 'unknown'}</span>
          <span class="badge \${running ? 'ok' : 'warn'}">\${running ? 'Active' : 'Stopped'}</span>
          <div class="stack-actions">
            <button class="secondary" onclick="portainerAction('start',\${st.Id || 0})">▶</button>
            <button class="secondary" onclick="portainerAction('stop',\${st.Id || 0})">⏹</button>
            <button class="secondary" onclick="portainerAction('update',\${st.Id || 0})">↺</button>
          </div>
        </div>
      </div>\`;
    }).join('');
  } catch(e) {
    document.getElementById('stackList').innerHTML = '<div style="color:var(--danger)">Error: ' + e.message + '</div>';
  }
}

function portainerAction(action, stackId) {
  fetch('/api/portainer', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, stackId }),
  }).then(r => r.json()).then(d => {
    alert(d.ok ? 'Done!' : ('Error: ' + (d.error || JSON.stringify(d))));
    loadPortainerStacks();
  }).catch(e => alert('Error: ' + e.message));
}

// ── OpenClaw ──────────────────────────────────────────────────────────────
function fillOpenclawMsg(msg) { document.getElementById('openclawMsg').value = msg; }
function openOpenclawUI() { window.open('${escapeHtml(settings.openclawUrl)}/?token=${escapeHtml(settings.tokens.openclawToken)}', '_blank'); }

async function sendOpenclawTask() {
  const msg = document.getElementById('openclawMsg').value.trim();
  if (!msg) return;
  document.getElementById('openclawStatus').textContent = '⏳ Sending to OpenClaw…';
  document.getElementById('openclawResponse').style.display = 'block';
  document.getElementById('openclawResponse').textContent = '';
  try {
    const r = await fetch('/api/openclaw', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: msg }),
    });
    const data = await r.json();
    document.getElementById('openclawStatus').textContent = data.ok ? '✓ Sent' : '✗ Failed — check token in Settings';
    document.getElementById('openclawResponse').textContent = data.body || data.error || JSON.stringify(data);
  } catch(e) {
    document.getElementById('openclawStatus').textContent = '✗ ' + e.message;
  }
}

// ── Settings ──────────────────────────────────────────────────────────────
async function saveSettings() {
  const settings = {
    nodes: {
      nodeA: { label: 'Node A (Brain)', ip: document.getElementById('nodeAIp').value, sshUser: 'root', enabled: true },
      nodeB: { label: 'Node B (Unraid/LiteLLM)', ip: document.getElementById('nodeBIp').value, sshUser: 'root', enabled: true },
      nodeC: { label: 'Node C (Intel Arc)', ip: document.getElementById('nodeCIp').value, sshUser: 'root', enabled: true },
      nodeD: { label: 'Node D (Home Assistant)', ip: document.getElementById('nodeDIp').value, sshUser: 'root', enabled: true },
      nodeE: { label: 'Node E (Sentinel)', ip: document.getElementById('nodeEIp').value, sshUser: 'root', enabled: true },
    },
    tokens: {
      litellmKey: document.getElementById('litellmKey').value,
      kvmOperatorToken: document.getElementById('kvmToken').value,
      openclawToken: document.getElementById('openclawToken').value,
      portainerToken: document.getElementById('portainerToken').value,
    },
    cloudflare: {
      dashboardUrl: document.getElementById('cfDashboardUrl').value.trim(),
      litellmUrl: document.getElementById('cfLitellmUrl').value.trim(),
      openclawUrl: document.getElementById('cfOpenclawUrl').value.trim(),
      openwebuiUrl: document.getElementById('cfOpenwebuiUrl').value.trim(),
      portainerUrl: document.getElementById('cfPortainerUrl').value.trim(),
      homeAssistantUrl: document.getElementById('cfHomeAssistantUrl').value.trim(),
    },
  };
  try {
    const r = await fetch('/api/settings', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(settings),
    });
    const data = await r.json();
    if (data.ok) {
      const st = document.getElementById('settingsSaveStatus');
      st.style.display = 'inline';
      setTimeout(() => { st.style.display = 'none'; }, 3000);
    }
  } catch(e) { alert('Save failed: ' + e.message); }
}

// ── Log helper ────────────────────────────────────────────────────────────
function appendLog(elId, cls, text) {
  const el = document.getElementById(elId);
  if (!el) return;
  const span = document.createElement('span');
  if (cls) span.className = cls;
  span.textContent = text + '\\n';
  el.appendChild(span);
  el.scrollTop = el.scrollHeight;
}

// Init
refreshStatus();
renderDeployList();
renderEcosystemLinks();

// ── Setup Wizard ───────────────────────────────────────────────────────────
const WZ_STEPS = ['Configure','SSH Audit','Inventory','Portainer','Deploy','Verify'];
let wzStep = 0;
let wzAuditResults = [];
let wzPortainerResults = {};
let wzNodes = [
  { label: 'Node A (Brain)',          ip: nodes.nodeA.ip, user: nodes.nodeA.sshUser || 'root', enabled: true  },
  { label: 'Node B (Unraid/LiteLLM)', ip: nodes.nodeB.ip, user: nodes.nodeB.sshUser || 'root', enabled: true  },
  { label: 'Node C (Intel Arc)',       ip: nodes.nodeC.ip, user: nodes.nodeC.sshUser || 'root', enabled: true  },
  { label: 'Node D (Home Assistant)',  ip: nodes.nodeD.ip, user: 'root',                        enabled: false },
  { label: 'Node E (Sentinel)',        ip: nodes.nodeE.ip, user: 'root',                        enabled: false },
];

function renderWizardSteps() {
  return WZ_STEPS.map((name, i) => {
    const isDone   = i < wzStep;
    const isActive = i === wzStep;
    return \`<div class="wstep">
      <div class="wstep-node" onclick="wzGoTo(\${i})">
        <div class="wstep-num \${isDone ? 'done' : isActive ? 'active' : ''}">\${isDone ? '✓' : i + 1}</div>
        <div class="wstep-label \${isDone ? 'done' : isActive ? 'active' : ''}">\${name}</div>
      </div>
      \${i < WZ_STEPS.length - 1 ? '<div class="wstep-arrow">›</div>' : ''}
    </div>\`;
  }).join('');
}

function wzGoTo(step) {
  if (step > wzStep) return; // can't skip forward
  wzStep = step;
  renderWizard();
}

function renderWizard() {
  const el = document.getElementById('tab-wizard');
  if (!el) return;
  el.innerHTML = \`
    <div class="section-title">🧙 Installation Wizard</div>
    <div class="card" style="margin-bottom:18px">
      <div class="wizard-steps">\${renderWizardSteps()}</div>
      <div class="wizard-body" id="wz-body"></div>
      <div class="wz-nav" id="wz-nav"></div>
    </div>
  \`;
  const body = document.getElementById('wz-body');
  const nav  = document.getElementById('wz-nav');
  switch (wzStep) {
    case 0: wzRenderConfigure(body, nav); break;
    case 1: wzRenderAudit(body, nav);     break;
    case 2: wzRenderInventory(body, nav); break;
    case 3: wzRenderPortainer(body, nav); break;
    case 4: wzRenderDeploy(body, nav);    break;
    case 5: wzRenderVerify(body, nav);    break;
  }
}

// Step 0 — Configure Nodes
function wzRenderConfigure(body, nav) {
  body.innerHTML = \`
    <div style="color:var(--text2);margin-bottom:14px;font-size:13px">
      Enter the IP addresses of your nodes. Uncheck nodes you don't have.
    </div>
    \${wzNodes.map((n, i) => \`
    <div class="wz-node-row">
      <div>
        <label style="display:flex;align-items:center;gap:6px">
          <input type="checkbox" id="wz-en-\${i}" \${n.enabled ? 'checked' : ''}
            onchange="wzNodes[\${i}].enabled=this.checked" style="width:auto">
          \${n.label}
        </label>
        <input type="text" id="wz-ip-\${i}" value="\${n.ip}" placeholder="192.168.1.X"
          onblur="wzNodes[\${i}].ip=this.value" style="margin-top:4px">
      </div>
      <div>
        <label>SSH User</label>
        <input type="text" id="wz-user-\${i}" value="\${n.user}" placeholder="root"
          onblur="wzNodes[\${i}].user=this.value">
      </div>
      <div>
        <label>&nbsp;</label>
        <button class="secondary" onclick="wzTestSingle(\${i})" id="wz-test-\${i}"
          \${n.enabled ? '' : 'disabled'}>Test SSH</button>
      </div>
    </div>
    <div id="wz-test-result-\${i}" style="font-size:12px;color:var(--text2);margin-bottom:6px"></div>
    \`).join('')}
  \`;
  nav.innerHTML = \`
    <button onclick="wzSaveConfigAndNext()">Next: Audit Connections →</button>
  \`;
}

async function wzTestSingle(idx) {
  const btn = document.getElementById('wz-test-' + idx);
  const res = document.getElementById('wz-test-result-' + idx);
  wzNodes[idx].ip   = document.getElementById('wz-ip-'   + idx).value;
  wzNodes[idx].user = document.getElementById('wz-user-' + idx).value;
  btn.disabled = true; btn.textContent = 'Testing…';
  try {
    const r = await fetch('/api/audit', { method:'POST',
      headers:{'Content-Type':'application/json'},
      body: JSON.stringify({ ip: wzNodes[idx].ip, user: wzNodes[idx].user, quick: true }) });
    const d = await r.json();
    res.innerHTML = d.ping
      ? (d.ssh ? \`<span style="color:var(--green)">✓ Reachable & SSH OK</span>\`
               : \`<span style="color:var(--warn)">⚠ Ping OK — SSH auth failed (run ssh-copy-id \${wzNodes[idx].user}@\${wzNodes[idx].ip})</span>\`)
      : \`<span style="color:var(--red)">✗ Not reachable (check IP / network)</span>\`;
  } catch(e) { res.textContent = 'Error: ' + e.message; }
  btn.disabled = false; btn.textContent = 'Test SSH';
}

function wzSaveConfigAndNext() {
  // Sync input values (user may not have blurred)
  wzNodes.forEach((n, i) => {
    const ipEl   = document.getElementById('wz-ip-'   + i);
    const userEl = document.getElementById('wz-user-' + i);
    const enEl   = document.getElementById('wz-en-'   + i);
    if (ipEl)   n.ip      = ipEl.value;
    if (userEl) n.user    = userEl.value;
    if (enEl)   n.enabled = enEl.checked;
  });
  wzStep = 1; renderWizard();
}

// Step 1 — SSH Audit
async function wzRenderAudit(body, nav) {
  const enabled = wzNodes.filter(n => n.enabled && n.ip && !n.ip.includes('X'));
  body.innerHTML = \`<div style="color:var(--text2);font-size:13px;margin-bottom:14px">
    Auditing SSH connectivity, firewall status, and available tools on each node…
  </div>\` + enabled.map(n => \`
    <div class="audit-node-card" id="wz-audit-\${n.ip.replace(/\\./g,'-')}">
      <div class="audit-node-header">
        <div class="dot checking"></div>
        <div class="audit-node-label">\${n.label} — \${n.ip}</div>
        <span style="font-size:12px;color:var(--text2)">Checking…</span>
      </div>
    </div>
  \`).join('');
  nav.innerHTML = '<button class="secondary" onclick="wzStep=0;renderWizard()">← Back</button>';

  wzAuditResults = [];
  const promises = enabled.map(n => wzAuditOne(n));
  await Promise.all(promises);

  nav.innerHTML = \`
    <button class="secondary" onclick="wzStep=0;renderWizard()">← Back</button>
    <button onclick="wzStep=2;renderWizard()">Next: Inventory →</button>
  \`;
}

async function wzAuditOne(node) {
  const cardId = 'wz-audit-' + node.ip.replace(/\\./g, '-');
  try {
    const r = await fetch('/api/audit', { method:'POST',
      headers:{'Content-Type':'application/json'},
      body: JSON.stringify({ ip: node.ip, user: node.user }) });
    const d = await r.json();
    wzAuditResults.push({ ...d, label: node.label });
    const card = document.getElementById(cardId);
    if (!card) return;
    const overall = d.ssh ? 'green' : d.ping ? 'warn' : 'red';
    const dotClass = d.ssh ? 'green' : d.ping ? 'checking' : 'red';
    const status   = d.ssh ? '✓ Connected' : d.ping ? '⚠ Ping OK / SSH failed' : '✗ Unreachable';
    card.innerHTML = \`
      <div class="audit-node-header">
        <div class="dot \${dotClass}"></div>
        <div class="audit-node-label">\${node.label} — \${node.ip}</div>
        <span style="font-size:12px;color:var(--\${overall === 'green' ? 'accent2' : overall === 'warn' ? 'warn' : 'danger'})">\${status}</span>
      </div>
      <div class="audit-checks">
        <div class="audit-check"><span>\${d.ping ? '✓' : '✗'}</span> Ping</div>
        <div class="audit-check"><span>\${d.port22 ? '✓' : '✗'}</span> Port 22 open</div>
        <div class="audit-check"><span>\${d.ssh ? '✓' : '✗'}</span> SSH key auth</div>
        \${d.tailscale_ip ? \`<div class="audit-check"><span>✓</span> Tailscale: \${d.tailscale_ip}</div>\` : ''}
      </div>
      \${(d.fixes && d.fixes.length) ? \`
      <div class="audit-fixes">
        <div style="font-weight:600;margin-bottom:4px;color:var(--warn)">⚠ Suggested Fixes:</div>
        \${d.fixes.map(f => \`<div class="audit-fix-item">→ \${f}</div>\`).join('')}
      </div>\` : ''}
    \`;
  } catch(e) {
    const card = document.getElementById(cardId);
    if (card) card.innerHTML += \`<div style="color:var(--danger);font-size:12px">Error: \${e.message}</div>\`;
  }
}

// Step 2 — Pre-Install Inventory
function wzRenderInventory(body, nav) {
  const results = wzAuditResults.filter(r => r.ssh);
  if (!results.length) {
    body.innerHTML = '<div style="color:var(--warn);padding:20px">No nodes were reachable via SSH — go back and fix connections first.</div>';
  } else {
    body.innerHTML = \`<div style="color:var(--text2);font-size:13px;margin-bottom:14px">
      Software inventory collected from each reachable node:
    </div>\` + results.map(r => {
      const inv = r.inventory || {};
      const rows = Object.entries(inv).map(([k,v]) => \`<tr><td>\${k}</td><td>\${v || '—'}</td></tr>\`).join('');
      return \`<div class="audit-node-card">
        <div class="audit-node-header">
          <div class="dot green"></div>
          <div class="audit-node-label">\${r.label} — \${r.ip}</div>
        </div>
        <table class="inv-table"><thead><tr><th>Package / Service</th><th>Version / Status</th></tr></thead>
        <tbody>\${rows || '<tr><td colspan=2 style="color:var(--text2)">No inventory data</td></tr>'}</tbody>
        </table>
      </div>\`;
    }).join('');
  }
  nav.innerHTML = \`
    <button class="secondary" onclick="wzStep=1;renderWizard()">← Back</button>
    <button onclick="wzStep=3;renderWizard()">Next: Install Portainer →</button>
  \`;
}

// Step 3 — Install Portainer
function wzRenderPortainer(body, nav) {
  const targets = wzAuditResults.filter(r => r.ssh);
  body.innerHTML = \`<div style="color:var(--text2);font-size:13px;margin-bottom:14px">
    Install Portainer CE on each node. Portainer manages all Docker containers and stacks via a web UI.
    Already-running instances will be skipped.
  </div>\` + (targets.length ? targets.map(r => \`
    <div class="portainer-install-card" id="wz-port-\${r.ip.replace(/\\./g,'-')}">
      <div class="portainer-install-header">
        <div class="dot \${wzPortainerResults[r.ip] === 'ok' ? 'green' : wzPortainerResults[r.ip] === 'running' ? 'green' : wzPortainerResults[r.ip] === 'error' ? 'red' : 'gray'}"></div>
        <div style="flex:1;font-weight:600">\${r.label} — \${r.ip}</div>
        \${wzPortainerResults[r.ip]
          ? \`<span style="font-size:12px;color:var(--\${wzPortainerResults[r.ip] === 'ok' || wzPortainerResults[r.ip] === 'running' ? 'accent2' : 'danger'})">\${wzPortainerResults[r.ip] === 'ok' ? '✓ Installed' : wzPortainerResults[r.ip] === 'running' ? '✓ Already running' : '✗ Failed'}</span>\`
          : \`<button onclick="wzInstallPortainer('\${r.ip}', '\${r.user}')">▶ Install Portainer</button>\`}
      </div>
      <div id="wz-port-log-\${r.ip.replace(/\\./g,'-')}" style="font-size:12px;color:var(--text2);margin-top:6px"></div>
      \${wzPortainerResults[r.ip] && (wzPortainerResults[r.ip] === 'ok' || wzPortainerResults[r.ip] === 'running') ? \`
        <div style="margin-top:8px">
          <a href="http://\${r.ip}:9000" target="_blank" style="color:var(--accent)">
            Open Portainer → http://\${r.ip}:9000
          </a>
        </div>\` : ''}
    </div>
  \`).join('') : '<div style="color:var(--warn);padding:20px">No reachable nodes — go back to Step 1 and fix SSH connections.</div>');

  const allDone = targets.length > 0 && targets.every(r => ['ok','running'].includes(wzPortainerResults[r.ip]));
  nav.innerHTML = \`
    <button class="secondary" onclick="wzStep=2;renderWizard()">← Back</button>
    <button onclick="wzStep=4;renderWizard()">Next: Deploy Stacks →</button>
    \${allDone ? '<span style="color:var(--green);font-size:13px;margin-left:8px">✓ All nodes have Portainer</span>' : ''}
  \`;
}

async function wzInstallPortainer(ip, user) {
  const safeId = ip.replace(/\\./g, '-');
  const log = document.getElementById('wz-port-log-' + safeId);
  if (log) log.textContent = 'Installing Portainer CE… (this may take 60-90 seconds)';
  try {
    const r = await fetch('/api/portainer-install', { method:'POST',
      headers:{'Content-Type':'application/json'},
      body: JSON.stringify({ ip, user }) });
    const d = await r.json();
    if (d.ok) {
      wzPortainerResults[ip] = 'ok';
    } else if (d.already_running) {
      wzPortainerResults[ip] = 'running';
    } else {
      wzPortainerResults[ip] = 'error';
      if (log) log.textContent = 'Error: ' + (d.error || 'unknown');
    }
  } catch(e) {
    wzPortainerResults[ip] = 'error';
    if (log) log.textContent = 'Error: ' + e.message;
  }
  renderWizard(); wzStep = 3;
}

// Step 4 — Deploy Stacks
function wzRenderDeploy(body, nav) {
  body.innerHTML = \`
    <div style="color:var(--text2);font-size:13px;margin-bottom:14px">
      Deploy all AI home-lab services.  Use the Quick Deploy buttons to start each stack,
      or run the full deployment script.
    </div>
    <div class="card" style="margin-bottom:14px">
      <h3>🚀 Full Automated Deploy</h3>
      <p class="hint" style="margin-bottom:10px">Runs <code>scripts/deploy-all.sh</code> — deploys all nodes in sequence with health checks.</p>
      <button onclick="wzRunFullDeploy()">▶ Run Full Deploy</button>
      <div class="terminal" id="wz-deploy-log" style="margin-top:12px;min-height:140px;display:none"></div>
    </div>
    <div class="card">
      <h3>📦 Individual Stack Deploys</h3>
      <div style="display:flex;flex-direction:column;gap:8px;margin-top:8px">
        <button onclick="quickDeploy('nodeC')">▶ Node C — Ollama (Intel Arc)</button>
        <button onclick="quickDeploy('nodeB')">▶ Node B — LiteLLM Gateway</button>
        <button onclick="quickDeploy('nodeADash')">▶ Node A — Command Center Dashboard</button>
        <button onclick="quickDeploy('kvmOperator')">▶ KVM Operator</button>
      </div>
      <div class="terminal" id="wz-stack-log" style="margin-top:12px;min-height:100px;display:none"></div>
    </div>
  \`;
  nav.innerHTML = \`
    <button class="secondary" onclick="wzStep=3;renderWizard()">← Back</button>
    <button onclick="wzStep=5;renderWizard()">Next: Verify →</button>
  \`;
}

async function wzRunFullDeploy() {
  const log = document.getElementById('wz-deploy-log');
  if (log) { log.style.display = 'block'; log.textContent = 'Starting full deployment…\\n'; }
  try {
    const r = await fetch('/api/deploy', { method:'POST',
      headers:{'Content-Type':'application/json'},
      body: JSON.stringify({ target: 'all' }) });
    const d = await r.json();
    if (log) log.textContent += (d.output || 'Done') + '\\n';
  } catch(e) {
    if (log) log.textContent += 'Error: ' + e.message + '\\n';
  }
}

// Step 5 — Verify
async function wzRenderVerify(body, nav) {
  body.innerHTML = \`<div style="color:var(--text2);font-size:13px;margin-bottom:14px">
    Running final health checks on all services…
  </div><div id="wz-verify-list">
    <div class="status-row"><div class="dot checking"></div><span>Checking…</span></div>
  </div>\`;
  nav.innerHTML = '<button class="secondary" onclick="wzStep=4;renderWizard()">← Back</button>';

  try {
    const r = await fetch('/api/status');
    const data = await r.json();
    const services = data.services || [];
    const listEl = document.getElementById('wz-verify-list');
    if (!listEl) return;
    if (!services.length) {
      listEl.innerHTML = '<div style="color:var(--text2)">No services configured yet.</div>';
    } else {
      listEl.innerHTML = services.map(s => \`
        <div class="status-row">
          <div class="dot \${s.status === 'ok' ? 'green' : s.status === 'unknown' ? 'gray' : 'red'}"></div>
          <span class="svc-label">\${s.label}</span>
          <span class="svc-latency">\${s.status === 'ok' ? s.latency + 'ms' : s.status}</span>
        </div>
      \`).join('');
    }
    const allOk = services.every(s => s.status === 'ok' || s.status === 'unknown');
    nav.innerHTML = \`
      <button class="secondary" onclick="wzStep=4;renderWizard()">← Back</button>
      <button class="success" onclick="showTab('overview')">✓ Done — Go to Dashboard</button>
      \${allOk ? '<span style="color:var(--green);font-size:13px;margin-left:8px">🎉 All services healthy!</span>' : ''}
    \`;
  } catch(e) {
    const listEl = document.getElementById('wz-verify-list');
    if (listEl) listEl.innerHTML = \`<div style="color:var(--danger)">Status check failed: \${e.message}</div>\`;
  }
}
</script>
</body>
</html>`;
}

// ── API handlers ─────────────────────────────────────────────────────────────
async function handleStatus(res) {
  const checks = Object.entries(settings.services).map(([k, v]) => checkService(k, v));
  const services = await Promise.all(checks);
  sendJson(res, 200, { timestamp: new Date().toISOString(), services });
}

function handleHealth(res) {
  sendJson(res, 200, { ok: true, service: 'deploy-gui' });
}

async function handleDeploy(req, res) {
  let body;
  try { body = JSON.parse(await readBody(req)); } catch { return sendJson(res, 400, { error: 'Invalid JSON' }); }
  const target = typeof body.target === 'string' ? body.target : '';
  const script = DEPLOY_SCRIPTS[target];
  if (!script) return sendJson(res, 400, { error: `Unknown deploy target: ${target}` });

  const output = [];
  let ok = true;

  for (const cmd of script.commands) {
    if (script.local) {
      const result = await new Promise(resolve => {
        execFile('sh', ['-c', cmd], { timeout: 120000, env: SAFE_CHILD_ENV }, (err, stdout, stderr) => {
          resolve({ ok: !err, stdout: stdout || '', stderr: stderr || '', error: err ? err.message : null });
        });
      });
      output.push(`$ ${cmd}`);
      if (result.stdout) output.push(result.stdout.trim());
      if (result.stderr) output.push('STDERR: ' + result.stderr.trim());
      if (result.error) { output.push('ERROR: ' + result.error); ok = false; }
    } else {
      const node = settings.nodes[script.nodeKey];
      if (!node) { output.push(`ERROR: Node ${script.nodeKey} not configured`); ok = false; break; }
      const result = await sshExec(node.ip, node.sshUser, cmd);
      output.push(`$ [${node.ip}] ${cmd}`);
      if (result.stdout) output.push(result.stdout.trim());
      if (result.stderr) output.push('STDERR: ' + result.stderr.trim());
      if (result.error) { output.push('ERROR: ' + result.error); ok = false; }
    }
  }

  sendJson(res, 200, { ok, output: output.join('\n') });
}

async function handleSsh(req, res) {
  let body;
  try { body = JSON.parse(await readBody(req)); } catch { return sendJson(res, 400, { error: 'Invalid JSON' }); }
  const { target, command } = body;
  if (!command || typeof command !== 'string') return sendJson(res, 400, { error: 'command required' });
  // Basic length guard — prevents very long payloads that might indicate injection attempts
  if (command.length > 2048) return sendJson(res, 400, { error: 'command too long (max 2048 chars)' });

  if (!target || target === 'local') {
    const result = await new Promise(resolve => {
      execFile('sh', ['-c', command], { timeout: 60000, env: SAFE_CHILD_ENV }, (err, stdout, stderr) => {
        resolve({ ok: !err, stdout: stdout || '', stderr: stderr || '', error: err ? err.message : null });
      });
    });
    return sendJson(res, 200, result);
  }

  const node = settings.nodes[target];
  if (!node) return sendJson(res, 400, { error: `Unknown node: ${target}` });
  const result = await sshExec(node.ip, node.sshUser, command);
  sendJson(res, 200, result);
}

async function handlePortainer(req, res, parsedUrl) {
  if (req.method === 'GET') {
    const action = parsedUrl.searchParams.get('action');
    if (action === 'list_stacks') {
      const result = await portainerRequest('/stacks');
      if (!result.ok) return sendJson(res, 200, { ok: false, error: result.error || 'Portainer unreachable' });
      try {
        const stacks = JSON.parse(result.body);
        return sendJson(res, 200, { ok: true, stacks: Array.isArray(stacks) ? stacks : [] });
      } catch {
        return sendJson(res, 200, { ok: false, error: 'Invalid response from Portainer' });
      }
    }
    return sendJson(res, 400, { error: 'Unknown action' });
  }

  let body;
  try { body = JSON.parse(await readBody(req)); } catch { return sendJson(res, 400, { error: 'Invalid JSON' }); }
  const { action, stackId } = body;

  if (action === 'start') {
    const r = await portainerRequest(`/stacks/${stackId}/start`, 'POST');
    return sendJson(res, 200, { ok: r.ok });
  }
  if (action === 'stop') {
    const r = await portainerRequest(`/stacks/${stackId}/stop`, 'POST');
    return sendJson(res, 200, { ok: r.ok });
  }
  if (action === 'update') {
    const r = await portainerRequest(`/stacks/${stackId}/git/redeploy`, 'PUT', { prune: false });
    return sendJson(res, 200, { ok: r.ok });
  }

  sendJson(res, 400, { error: 'Unknown action' });
}

async function handleOpenclaw(req, res) {
  let body;
  try { body = JSON.parse(await readBody(req)); } catch { return sendJson(res, 400, { error: 'Invalid JSON' }); }
  const { message } = body;
  if (!message) return sendJson(res, 400, { error: 'message required' });
  const result = await openclawTask(message);
  sendJson(res, 200, result);
}

// ── Audit handler — SSH/ping/inventory check for a single node ────────────────
async function handleAudit(req, res) {
  let body;
  try { body = JSON.parse(await readBody(req)); } catch { return sendJson(res, 400, { error: 'Invalid JSON' }); }
  const ip   = typeof body.ip   === 'string' ? body.ip.trim()   : '';
  const user = typeof body.user === 'string' ? body.user.trim() : 'root';
  const quick = Boolean(body.quick);

  if (!ip) return sendJson(res, 400, { error: 'ip required' });

  const result = {
    ip, user,
    ping: false, port22: false, ssh: false,
    tailscale_ip: '',
    inventory: {},
    errors: [],
    fixes: [],
    recommend: 'unreachable',
  };

  // 1. Ping
  const pingOk = await new Promise(resolve => {
    execFile('ping', ['-c', '1', '-W', '2', ip], { timeout: 5000, env: SAFE_CHILD_ENV },
      (err) => resolve(!err));
  });
  result.ping = pingOk;
  if (!pingOk) result.errors.push('Host not reachable via ping');

  // 2. Port 22 check using bash /dev/tcp via sh
  const port22Ok = await new Promise(resolve => {
    execFile('sh', ['-c', `(echo >/dev/tcp/${ip}/22) 2>/dev/null && echo ok || echo fail`],
      { timeout: 6000, env: SAFE_CHILD_ENV },
      (err, stdout) => resolve(!err && stdout.trim() === 'ok'));
  });
  result.port22 = port22Ok;
  if (!port22Ok) {
    result.errors.push('Port 22 is not reachable');
    if (pingOk) {
      result.fixes.push(`Ensure sshd is installed and running: systemctl enable --now sshd`);
      result.fixes.push(`Allow SSH through firewall: sudo ufw allow ssh  OR  sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload`);
    }
  }

  // 3. SSH key auth test
  const sshOk = await new Promise(resolve => {
    execFile('ssh', [
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'ConnectTimeout=8',
      '-o', 'BatchMode=yes',
      `${user}@${ip}`, 'true',
    ], { timeout: 12000, env: SAFE_CHILD_ENV }, (err) => resolve(!err));
  });
  result.ssh = sshOk;
  if (!sshOk) {
    result.errors.push('SSH key authentication failed');
    if (port22Ok) result.fixes.push(`Set up key-based auth: ssh-copy-id ${user}@${ip}`);
    result.recommend = pingOk ? 'tailscale' : 'unreachable';
  } else {
    result.recommend = 'direct';
  }

  // 4. Full inventory (skip if quick=true or no SSH)
  if (sshOk && !quick) {
    const invScript = [
      'OUT=""',
      'command -v docker &>/dev/null && { DVER=$(docker --version 2>/dev/null | grep -oP "\\d+\\.\\d+\\.\\d+" | head -1); OUT="${OUT}docker=${DVER}|"; }',
      'docker compose version &>/dev/null 2>&1 && { DCV=$(docker compose version 2>/dev/null | grep -oP "\\d+\\.\\d+\\.\\d+" | head -1 || echo plugin); OUT="${OUT}docker_compose=${DCV}|"; }',
      'command -v docker &>/dev/null && { for c in portainer portainer-ce; do ST=$(docker inspect --format "{{.State.Status}}" "$c" 2>/dev/null||true); [ -n "$ST" ] && OUT="${OUT}portainer=${ST}|" && break; done; }',
      'command -v docker &>/dev/null && { for c in litellm_gateway ollama_intel_arc chimera_face openclaw-gateway; do ST=$(docker inspect --format "{{.State.Status}}" "$c" 2>/dev/null||true); [ -n "$ST" ] && OUT="${OUT}${c}=${ST}|"; done; }',
      'OS=$(grep -oP \'(?<=^PRETTY_NAME=").*(?=")\' /etc/os-release 2>/dev/null || echo unknown); OUT="${OUT}os=${OS}|"',
      'command -v tailscale &>/dev/null && { TSIP=$(tailscale ip -4 2>/dev/null | head -1 || true); [ -n "$TSIP" ] && OUT="${OUT}tailscale_ip=${TSIP}|"; }',
      'FW=none; command -v ufw &>/dev/null && ufw status 2>/dev/null|grep -q active && FW=ufw; command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null|grep -q running && FW=firewalld; OUT="${OUT}firewall=${FW}|"',
      'command -v node &>/dev/null && OUT="${OUT}nodejs=$(node --version|tr -d v)|"',
      'command -v python3 &>/dev/null && OUT="${OUT}python3=$(python3 --version 2>/dev/null|awk "{print $2}")|"',
      'echo "$OUT"',
    ].join('\n');

    const invResult = await sshExecStdin(ip, user, invScript, 30000);
    const invRaw = invResult.stdout || '';

    // Parse key=value|… pairs
    invRaw.split('|').forEach(pair => {
      const eq = pair.indexOf('=');
      if (eq > 0) {
        const k = pair.slice(0, eq).trim();
        const v = pair.slice(eq + 1).trim();
        if (k && v) result.inventory[k] = v;
      }
    });

    if (result.inventory.tailscale_ip) result.tailscale_ip = result.inventory.tailscale_ip;
  }

  sendJson(res, 200, result);
}

// ── Portainer-install handler ─────────────────────────────────────────────────
async function handlePortainerInstall(req, res) {
  let body;
  try { body = JSON.parse(await readBody(req)); } catch { return sendJson(res, 400, { error: 'Invalid JSON' }); }
  const ip   = typeof body.ip   === 'string' ? body.ip.trim()   : '';
  const user = typeof body.user === 'string' ? body.user.trim() : 'root';
  const port = Number(body.port) || 9000;

  if (!ip) return sendJson(res, 400, { error: 'ip required' });

  // Verify SSH connectivity
  const sshOk = await new Promise(resolve => {
    execFile('ssh', ['-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=8', '-o', 'BatchMode=yes',
      `${user}@${ip}`, 'true'], { timeout: 12000, env: SAFE_CHILD_ENV }, err => resolve(!err));
  });
  if (!sshOk) return sendJson(res, 200, { ok: false, error: `SSH connection to ${user}@${ip} failed. Run the SSH audit first.` });

  // Check if Portainer is already running
  const alreadyRunning = await new Promise(resolve => {
    execFile('ssh', ['-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=8', '-o', 'BatchMode=yes',
      `${user}@${ip}`,
      `docker inspect --format '{{.State.Status}}' portainer 2>/dev/null || docker inspect --format '{{.State.Status}}' portainer-ce 2>/dev/null || echo ''`],
      { timeout: 15000, env: SAFE_CHILD_ENV }, (err, stdout) => resolve(!err && stdout.trim() === 'running'));
  });
  if (alreadyRunning) return sendJson(res, 200, { ok: true, already_running: true, url: `http://${ip}:${port}` });

  // Run install script on the remote
  const installScript = `
set -euo pipefail
PORT=${port}
command -v docker &>/dev/null || { echo "Docker not installed — please install Docker first"; exit 1; }
docker info &>/dev/null 2>&1 || { systemctl start docker 2>/dev/null || true; sleep 3; }
docker rm -f portainer 2>/dev/null || true
docker volume create portainer_data 2>/dev/null || true
docker run -d --name portainer --restart always \\
  -p $PORT:9000 -p 8000:8000 \\
  -v /var/run/docker.sock:/var/run/docker.sock \\
  -v portainer_data:/data \\
  portainer/portainer-ce:latest
for i in $(seq 1 20); do
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://localhost:$PORT/api/status 2>/dev/null || echo 000)
  [[ "$HTTP" =~ ^2 ]] && echo "READY" && break
  sleep 3
done
`;

  const installOut = await sshExecStdin(ip, user, installScript, 180000);

  const ok = installOut.ok || installOut.stdout.includes('READY');
  sendJson(res, 200, {
    ok,
    url: ok ? `http://${ip}:${port}` : '',
    output: installOut.stdout,
    error: ok ? null : (installOut.error || installOut.stderr),
  });
}

async function handleSettingsGet(res) {
  // Return settings without sensitive tokens
  const safe = { ...settings, tokens: { ...settings.tokens, portainerToken: '***', openclawToken: '***', kvmOperatorToken: '***' } };
  sendJson(res, 200, safe);
}

async function handleSettingsSave(req, res) {
  let body;
  try { body = JSON.parse(await readBody(req)); } catch { return sendJson(res, 400, { error: 'Invalid JSON' }); }

  // Merge carefully — only update known top-level keys
  if (body.nodes && typeof body.nodes === 'object') {
    for (const [k, v] of Object.entries(body.nodes)) {
      if (settings.nodes[k] && typeof v === 'object') {
        settings.nodes[k] = { ...settings.nodes[k], ...v };
      }
    }
  }
  if (body.tokens && typeof body.tokens === 'object') {
    for (const [k, v] of Object.entries(body.tokens)) {
      if (k in settings.tokens && typeof v === 'string' && v !== '***') {
        settings.tokens[k] = v;
      }
    }
  }
  ['portainerUrl', 'openclawUrl', 'kvmOperatorUrl'].forEach(key => {
    if (typeof body[key] === 'string') settings[key] = body[key];
  });
  if (body.cloudflare && typeof body.cloudflare === 'object') {
    settings.cloudflare = { ...settings.cloudflare, ...body.cloudflare };
  }

  // Regenerate service URLs from updated node IPs
  settings.services.litellm.url = `http://${settings.nodes.nodeB.ip}:4000/health/readiness`;
  settings.services.ollama.url = `http://${settings.nodes.nodeC.ip}:11434/api/version`;
  settings.services.openwebui.url = `http://${settings.nodes.nodeC.ip}:3000`;
  settings.services.nodeaDash.url = `http://${settings.nodes.nodeA.ip}:3099/api/status`;
  settings.services.kvmOperator.url = `http://${settings.nodes.nodeA.ip}:5000/health`;
  settings.services.openclaw.url = `http://${settings.nodes.nodeB.ip}:18789/`;
  settings.services.portainer.url = `http://${settings.nodes.nodeB.ip}:9000/api/status`;

  saveSettings(settings);
  sendJson(res, 200, { ok: true });
}

// ── HTTP server ───────────────────────────────────────────────────────────────
const server = http.createServer(async (req, res) => {
  const parsedUrl = new URL(req.url, `http://localhost:${PORT}`);
  const { pathname } = parsedUrl;

  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }

  // Routes
  if (req.method === 'GET' && pathname === '/') {
    const html = renderDashboard();
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Content-Length': Buffer.byteLength(html), 'Cache-Control': 'no-store' });
    return res.end(html);
  }

  if (req.method === 'GET' && pathname === '/api/health') return handleHealth(res);
  if (req.method === 'GET' && pathname === '/api/status') return handleStatus(res);
  if (req.method === 'GET' && pathname === '/api/settings') return handleSettingsGet(res);
  if (req.method === 'POST' && pathname === '/api/settings') return handleSettingsSave(req, res);
  if (req.method === 'POST' && pathname === '/api/deploy') return handleDeploy(req, res);
  if (req.method === 'POST' && pathname === '/api/ssh') return handleSsh(req, res);
  if (pathname === '/api/portainer') return handlePortainer(req, res, parsedUrl);
  if (req.method === 'POST' && pathname === '/api/openclaw') return handleOpenclaw(req, res);
  if (req.method === 'POST' && pathname === '/api/audit') return handleAudit(req, res);
  if (req.method === 'POST' && pathname === '/api/portainer-install') return handlePortainerInstall(req, res);

  sendJson(res, 404, { error: 'Not found' });
});

ensureDataDir();
server.listen(PORT, () => {
  process.stdout.write(`Homelab Deploy GUI running at http://localhost:${PORT}\n`);
  process.stdout.write(`Data directory: ${DATA_DIR}\n`);
});
