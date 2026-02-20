#!/usr/bin/env node
/**
 * Homelab Deploy GUI — Node.js web application
 * Visual GUI to deploy and administer all AI home-lab nodes from Fedora 43.
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
 */

'use strict';

const http = require('http');
const https = require('https');
const { URL } = require('url');
const fs = require('fs');
const path = require('path');
const { execFile, spawn } = require('child_process');

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
    nodeC: { label: 'Node C (Intel Arc)', ip: '192.168.1.X', sshUser: 'root', enabled: true },
    nodeD: { label: 'Node D (Home Assistant)', ip: '192.168.1.Y', sshUser: 'root', enabled: false },
    nodeE: { label: 'Node E (Sentinel)', ip: '192.168.1.Z', sshUser: 'root', enabled: false },
  },
  services: {
    litellm: { label: 'LiteLLM Gateway', url: 'http://192.168.1.222:4000/health' },
    ollama: { label: 'Ollama (Node C)', url: 'http://192.168.1.X:11434/api/version' },
    openwebui: { label: 'Chimera Face UI', url: 'http://192.168.1.X:3000' },
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
    return { ...DEFAULT_SETTINGS, ...JSON.parse(raw) };
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
function escapeHtml(v) {
  return String(v)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': '*',
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let buf = Buffer.alloc(0);
    req.on('data', chunk => {
      buf = Buffer.concat([buf, chunk]);
      if (buf.length > MAX_BODY_BYTES) reject(new Error('Body too large'));
    });
    req.on('end', () => resolve(buf.toString('utf8')));
    req.on('error', reject);
  });
}

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
    --bg: #0f1117; --surface: #1a1d27; --surface2: #242736;
    --border: #2e3148; --accent: #7c6af7; --accent2: #5ce65c;
    --warn: #f0a500; --danger: #e74c3c; --text: #e8eaf6;
    --text2: #9197b3; --green: #27ae60; --red: #e74c3c;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: var(--bg); color: var(--text); font-family: 'Segoe UI', system-ui, sans-serif; font-size: 14px; }
  header { background: var(--surface); border-bottom: 1px solid var(--border); padding: 12px 24px; display: flex; align-items: center; gap: 12px; }
  header h1 { font-size: 20px; font-weight: 700; }
  header span { font-size: 13px; color: var(--text2); }
  .tabs { display: flex; background: var(--surface); border-bottom: 1px solid var(--border); padding: 0 24px; }
  .tab { padding: 10px 18px; cursor: pointer; border-bottom: 3px solid transparent; color: var(--text2); font-size: 13px; transition: all 0.15s; user-select: none; }
  .tab:hover { color: var(--text); }
  .tab.active { color: var(--accent); border-color: var(--accent); }
  .panel { display: none; padding: 24px; max-width: 1200px; }
  .panel.active { display: block; }
  .grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
  .grid3 { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; }
  .card { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 16px; }
  .card h3 { font-size: 13px; color: var(--text2); margin-bottom: 12px; text-transform: uppercase; letter-spacing: 0.05em; }
  .status-row { display: flex; align-items: center; gap: 8px; padding: 6px 0; border-bottom: 1px solid var(--border); }
  .status-row:last-child { border-bottom: none; }
  .dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
  .dot.green { background: var(--green); box-shadow: 0 0 6px var(--green); }
  .dot.red { background: var(--red); box-shadow: 0 0 6px var(--red); }
  .dot.gray { background: #555; }
  .dot.checking { background: var(--warn); animation: pulse 1s infinite; }
  @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.4} }
  .svc-label { flex: 1; }
  .svc-url { font-size: 11px; color: var(--text2); }
  .svc-latency { font-size: 11px; color: var(--text2); margin-left: auto; }
  button { background: var(--accent); color: #fff; border: none; border-radius: 6px; padding: 8px 16px; cursor: pointer; font-size: 13px; font-weight: 500; transition: opacity 0.15s; }
  button:hover { opacity: 0.85; }
  button.secondary { background: var(--surface2); border: 1px solid var(--border); color: var(--text); }
  button.danger { background: var(--danger); }
  button.success { background: var(--green); }
  button:disabled { opacity: 0.4; cursor: not-allowed; }
  .deploy-item { background: var(--surface2); border: 1px solid var(--border); border-radius: 6px; padding: 14px 16px; margin-bottom: 10px; display: flex; align-items: center; gap: 12px; }
  .deploy-label { flex: 1; font-weight: 500; }
  .deploy-sub { font-size: 12px; color: var(--text2); }
  .terminal { background: #0a0c14; border: 1px solid var(--border); border-radius: 6px; padding: 12px; font-family: 'Courier New', monospace; font-size: 12px; line-height: 1.6; min-height: 200px; max-height: 420px; overflow-y: auto; color: #a8ff78; white-space: pre-wrap; word-break: break-all; }
  .terminal .err { color: var(--danger); }
  .terminal .info { color: var(--accent); }
  .terminal .ok { color: var(--green); }
  input, select, textarea { background: var(--surface2); border: 1px solid var(--border); border-radius: 6px; padding: 8px 12px; color: var(--text); font-size: 13px; width: 100%; }
  input:focus, textarea:focus { outline: 2px solid var(--accent); border-color: transparent; }
  label { display: block; font-size: 12px; color: var(--text2); margin-bottom: 4px; margin-top: 10px; }
  .field-row { display: flex; gap: 10px; align-items: flex-end; }
  .field-row > * { flex: 1; }
  .badge { display: inline-block; font-size: 11px; padding: 2px 8px; border-radius: 99px; }
  .badge.ok { background: rgba(39,174,96,0.2); color: var(--green); }
  .badge.fail { background: rgba(231,76,60,0.2); color: var(--red); }
  .badge.warn { background: rgba(240,165,0,0.2); color: var(--warn); }
  .stack-item { background: var(--surface2); border: 1px solid var(--border); border-radius: 6px; padding: 12px 14px; margin-bottom: 8px; }
  .stack-header { display: flex; align-items: center; gap: 10px; }
  .stack-name { flex: 1; font-weight: 500; }
  .stack-actions { display: flex; gap: 6px; }
  .hint { font-size: 11px; color: var(--text2); margin-top: 4px; }
  #settingsSaveStatus { font-size: 13px; color: var(--green); margin-left: 12px; display: none; }
  .section-title { font-size: 16px; font-weight: 600; margin-bottom: 14px; }
  .refresh-btn { background: var(--surface2); border: 1px solid var(--border); color: var(--text2); padding: 4px 10px; font-size: 12px; border-radius: 5px; cursor: pointer; }
  .refresh-btn:hover { color: var(--text); }
  .openclaw-response { background: #0a0c14; border: 1px solid var(--border); border-radius: 6px; padding: 12px; font-size: 13px; min-height: 80px; max-height: 300px; overflow-y: auto; white-space: pre-wrap; color: #e8eaf6; display: none; }
</style>
</head>
<body>
<header>
  <span style="font-size:24px">🚀</span>
  <h1>Homelab Deploy GUI</h1>
  <span>Grand Unified AI Home Lab — Fedora 43 Command Center</span>
  <span style="margin-left:auto;font-size:12px;color:var(--text2)" id="clock"></span>
</header>
<div class="tabs">
  <div class="tab active" onclick="showTab('overview')">📊 Overview</div>
  <div class="tab" onclick="showTab('deploy')">🚀 Deploy</div>
  <div class="tab" onclick="showTab('portainer')">📦 Portainer</div>
  <div class="tab" onclick="showTab('ssh')">💻 Terminal</div>
  <div class="tab" onclick="showTab('openclaw')">🤖 OpenClaw</div>
  <div class="tab" onclick="showTab('settings')">⚙️ Settings</div>
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

<script>
// ── State ─────────────────────────────────────────────────────────────────
const DEPLOY_TARGETS = ${deployTargetsJson};
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

  // Regenerate service URLs from updated node IPs
  settings.services.litellm.url = `http://${settings.nodes.nodeB.ip}:4000/health`;
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

  if (req.method === 'GET' && pathname === '/api/status') return handleStatus(res);
  if (req.method === 'GET' && pathname === '/api/settings') return handleSettingsGet(res);
  if (req.method === 'POST' && pathname === '/api/settings') return handleSettingsSave(req, res);
  if (req.method === 'POST' && pathname === '/api/deploy') return handleDeploy(req, res);
  if (req.method === 'POST' && pathname === '/api/ssh') return handleSsh(req, res);
  if (pathname === '/api/portainer') return handlePortainer(req, res, parsedUrl);
  if (req.method === 'POST' && pathname === '/api/openclaw') return handleOpenclaw(req, res);

  sendJson(res, 404, { error: 'Not found' });
});

ensureDataDir();
server.listen(PORT, () => {
  process.stdout.write(`Homelab Deploy GUI running at http://localhost:${PORT}\n`);
  process.stdout.write(`Data directory: ${DATA_DIR}\n`);
});
