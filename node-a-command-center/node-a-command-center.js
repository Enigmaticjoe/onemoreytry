#!/usr/bin/env node

const http = require('http');
const { URL } = require('url');

const PORT = Number(process.env.COMMAND_CENTER_PORT || 3099);
const LITELLM_BASE_URL = process.env.LITELLM_BASE_URL || 'http://192.168.1.222:4000';
const BRAIN_BASE_URL = process.env.BRAIN_BASE_URL || 'http://192.168.1.9:8000';
const NODE_C_BASE_URL = process.env.NODE_C_BASE_URL || 'http://192.168.1.6';
const NODE_D_BASE_URL = process.env.NODE_D_BASE_URL || 'http://192.168.1.149:8123';
const NODE_E_BASE_URL = process.env.NODE_E_BASE_URL || 'http://192.168.1.116:3005';
const UPTIME_KUMA_BASE_URL = process.env.UPTIME_KUMA_BASE_URL || 'http://192.168.1.222:3010';
const DOZZLE_BASE_URL = process.env.DOZZLE_BASE_URL || 'http://192.168.1.222:8888';
const HOMEPAGE_BASE_URL = process.env.HOMEPAGE_BASE_URL || 'http://192.168.1.222:8010';
const LITELLM_API_KEY = process.env.LITELLM_API_KEY || 'sk-master-key';
const DEFAULT_MODEL = process.env.DEFAULT_MODEL || 'brain-heavy';
const REQUEST_TIMEOUT_MS = Number(process.env.REQUEST_TIMEOUT_MS || 7000);
const MAX_BODY_BYTES = 128 * 1024;
const MAX_CHAT_MESSAGE_CHARS = 5000;

const SHERPA_SYSTEM_PROMPT = `You are the AI Sherpa — a knowledgeable, encouraging IT guide and digital guru for the Grand Unified AI Home Lab. Your mission is to guide users step by step through the complete installation and configuration of their home lab nodes and services.

You have deep expertise in:
- Docker, Docker Compose, and container orchestration
- LiteLLM proxy and AI model management
- Intel Arc GPU setup and Ollama
- Home Assistant integration
- KVM/QEMU virtualization and NanoKVM
- Network configuration and SSH
- FastAPI and Node.js services

When helping with installation:
1. Always check prerequisites before each step
2. Give exact, copy-pasteable commands
3. Explain WHY each step is needed, not just how
4. Anticipate common pitfalls and warn proactively
5. Celebrate progress and be encouraging

Node layout for this lab:
- Node A (192.168.1.9): AMD RX 7900 XT Brain — vLLM or Ollama, runs this dashboard
- Node B (192.168.1.222): Unraid server — LiteLLM gateway, Portainer, Homepage, Uptime Kuma
- Node C (192.168.1.6): Intel Arc GPU — Ollama for vision tasks (llava model)
- Node D (192.168.1.149): Home Assistant — extended_openai_conversation integration
- Node E (192.168.1.116): Sentinel/NVR — Frigate webhook processor and vision relay

Answer questions clearly and concisely. Start by asking which node or step the user needs help with if it is not clear from their message.`;

const serviceChecks = [
  { key: 'gateway', label: 'Node B LiteLLM Gateway', url: `${LITELLM_BASE_URL}/health` },
  { key: 'brain', label: 'Node A Brain vLLM', url: `${BRAIN_BASE_URL}/health` },
  { key: 'vision', label: 'Node C Vision (Ollama)', url: `${NODE_C_BASE_URL}:11434/api/version` },
  { key: 'nodeCUi', label: 'Node C Chimera Face UI', url: `${NODE_C_BASE_URL}:3000` },
  { key: 'nodeD', label: 'Node D Home Assistant', url: `${NODE_D_BASE_URL}/api/` },
  { key: 'nodeE', label: 'Node E Sentinel (Vision)', url: `${NODE_E_BASE_URL}/health` },
  { key: 'uptimeKuma', label: 'Uptime Kuma (Monitoring)', url: `${UPTIME_KUMA_BASE_URL}` },
  { key: 'dozzle', label: 'Dozzle (Log Viewer)', url: `${DOZZLE_BASE_URL}/healthcheck` },
];

const dashboardLinks = [
  { name: 'LiteLLM Gateway Health', href: `${LITELLM_BASE_URL}/health` },
  { name: 'Node C Chimera Face UI', href: `${NODE_C_BASE_URL}:3000` },
  { name: 'Node D Home Assistant', href: `${NODE_D_BASE_URL}` },
  { name: 'Node E Sentinel Dashboard', href: `${NODE_E_BASE_URL}` },
  { name: 'Homepage Dashboard', href: `${HOMEPAGE_BASE_URL}` },
  { name: 'Uptime Kuma (Monitoring)', href: `${UPTIME_KUMA_BASE_URL}` },
  { name: 'Dozzle (Container Logs)', href: `${DOZZLE_BASE_URL}` },
  { name: 'Deployment Guide', href: '/docs/DEPLOYMENT_GUIDE' },
  { name: 'Quick Reference', href: '/docs/QUICK_REFERENCE' },
  { name: 'Node A Guidebook', href: '/docs/NODE_A_GUIDEBOOK' },
  { name: 'Unified Install Guidebook', href: '/docs/UNIFIED_INSTALL_GUIDEBOOK' },
  { name: 'Install Wizard', href: '/install-wizard' },
  { name: 'AI Sherpa Guide', href: '/sherpa' },
  { name: 'Mobile Monitor (PWA)', href: '/mobile' },
];

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

async function fetchWithTimeout(url, options = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    return response;
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchWithRetry(url, options = {}, maxRetries = 1, retryDelayMs = 500) {
  let lastError;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const response = await fetchWithTimeout(url, options);
      return response;
    } catch (error) {
      lastError = error;
      if (attempt < maxRetries) {
        await new Promise((resolve) => setTimeout(resolve, retryDelayMs));
      }
    }
  }
  throw lastError;
}

async function checkService(service) {
  const start = Date.now();
  try {
    const response = await fetchWithTimeout(service.url);
    return {
      ...service,
      ok: response.ok,
      status: response.status,
      latencyMs: Date.now() - start,
    };
  } catch (error) {
    return {
      ...service,
      ok: false,
      status: 0,
      latencyMs: Date.now() - start,
      error: error.name === 'AbortError' ? 'timeout' : 'unreachable',
    };
  }
}

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function getDocRedirectPath(pathname) {
  if (pathname === '/docs/DEPLOYMENT_GUIDE') return '/DEPLOYMENT_GUIDE.md';
  if (pathname === '/docs/QUICK_REFERENCE') return '/QUICK_REFERENCE.md';
  if (pathname === '/docs/NODE_A_GUIDEBOOK') return '/docs/09_NODE_A_COMMAND_CENTER_GUIDEBOOK.md';
  if (pathname === '/docs/UNIFIED_INSTALL_GUIDEBOOK') return '/docs/10_UNIFIED_INSTALL_GUIDEBOOK.md';
  return null;
}

function safeHref(href) {
  if (typeof href !== 'string') return '#';
  if (href.startsWith('/') && !href.startsWith('//')) return href;
  try {
    const parsed = new URL(href);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:' ? href : '#';
  } catch {
    return '#';
  }
}

function renderDashboard() {
  const linksHtml = dashboardLinks
    .map((item) => `<li><a href="${escapeHtml(safeHref(item.href))}" target="_blank" rel="noopener noreferrer">${escapeHtml(item.name)}</a></li>`)
    .join('');

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Node A Central Brain Command Center</title>
  <style>
    :root {
      color-scheme: dark;
      font-family: Inter, 'Segoe UI', Arial, sans-serif;
      --bg-base: #050811;
      --bg-mid: #0b0f1e;
      --glass-bg: rgba(255,255,255,0.04);
      --glass-bg-hover: rgba(255,255,255,0.07);
      --glass-border: rgba(255,255,255,0.08);
      --glass-shadow: 0 8px 32px rgba(0,0,0,0.5), 0 1px 0 rgba(255,255,255,0.05) inset;
      --accent: #7c6af7;
      --accent2: #5ce65c;
      --text: #e2e8f0;
      --text-muted: #94a3b8;
      --ok: #22c55e;
      --bad: #ef4444;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: var(--bg-base);
      background-image:
        radial-gradient(ellipse 80% 50% at 20% 10%, rgba(124,106,247,0.18) 0%, transparent 60%),
        radial-gradient(ellipse 60% 40% at 80% 80%, rgba(92,230,92,0.08) 0%, transparent 60%);
      color: var(--text);
      min-height: 100vh;
    }
    header {
      padding: 20px 24px;
      background: rgba(255,255,255,0.03);
      backdrop-filter: blur(12px);
      -webkit-backdrop-filter: blur(12px);
      border-bottom: 1px solid var(--glass-border);
      display: flex; flex-direction: column; gap: 4px;
    }
    h1 { font-size: 1.4rem; font-weight: 700; letter-spacing: -0.02em; }
    h2 { font-size: 1rem; font-weight: 600; margin-bottom: 12px; color: var(--text); }
    main { display: grid; gap: 18px; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); padding: 24px; }
    section {
      background: var(--glass-bg);
      backdrop-filter: blur(16px);
      -webkit-backdrop-filter: blur(16px);
      border: 1px solid var(--glass-border);
      border-radius: 16px;
      padding: 18px;
      box-shadow: var(--glass-shadow);
      transition: border-color 0.2s;
    }
    section:hover { border-color: rgba(124,106,247,0.25); }
    ul { margin: 8px 0 0; padding-left: 18px; }
    li { margin: 8px 0; }
    a { color: #93c5fd; text-decoration: none; }
    a:hover { text-decoration: underline; }
    button {
      background: linear-gradient(135deg, var(--accent), #5b50c8);
      color: white;
      border: none;
      padding: 8px 14px;
      border-radius: 8px;
      cursor: pointer;
      font-size: 0.875rem;
      font-weight: 500;
      transition: opacity 0.15s, transform 0.1s;
    }
    button:hover { opacity: 0.88; transform: translateY(-1px); }
    button:active { transform: translateY(0); }
    table { width: 100%; border-collapse: collapse; font-size: 0.9rem; margin-top: 12px; }
    th { font-size: 0.75rem; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.06em; padding: 6px 8px; border-bottom: 1px solid var(--glass-border); }
    td { padding: 8px; border-bottom: 1px solid rgba(255,255,255,0.04); }
    .ok { color: var(--ok); font-weight: 500; }
    .bad { color: var(--bad); font-weight: 500; }
    textarea {
      width: 100%;
      min-height: 90px;
      border-radius: 10px;
      background: rgba(0,0,0,0.3);
      color: var(--text);
      border: 1px solid var(--glass-border);
      padding: 10px;
      font-size: 0.9rem;
      resize: vertical;
    }
    textarea:focus { outline: none; border-color: rgba(124,106,247,0.5); box-shadow: 0 0 0 3px rgba(124,106,247,0.15); }
    pre {
      background: rgba(0,0,0,0.35);
      border-radius: 10px;
      border: 1px solid var(--glass-border);
      padding: 12px;
      min-height: 90px;
      overflow: auto;
      white-space: pre-wrap;
      font-size: 0.875rem;
      line-height: 1.5;
      margin-top: 10px;
    }
    .small { font-size: 0.82rem; color: var(--text-muted); margin-top: 8px; }
  </style>
</head>
<body>
  <header>
    <h1>Node A Central Brain — Command Center Dashboard</h1>
    <div class="small">Unified status, quick links, and chatbot for the Node A ecosystem.</div>
  </header>
  <main>
    <section>
      <h2>Ecosystem Links</h2>
      <ul>${linksHtml}</ul>
    </section>

    <section>
      <h2>Live Status</h2>
      <button id="refresh">Refresh</button>
      <table>
        <thead><tr><th>Service</th><th>Status</th><th>Code</th><th>Latency</th></tr></thead>
        <tbody id="statusRows"></tbody>
      </table>
      <div class="small">Status checks use fixed endpoints to avoid open-proxy behavior.</div>
    </section>

    <section>
      <h2>Chatbot (brain-heavy via LiteLLM)</h2>
      <textarea id="prompt" placeholder="Ask the central brain..."></textarea>
      <div style="margin-top: 8px;"><button id="send">Send</button></div>
      <pre id="reply"></pre>
    </section>
  </main>

  <script>
    const rows = document.getElementById('statusRows');
    const reply = document.getElementById('reply');
    const esc = (value) => String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');

    async function loadStatus() {
      rows.innerHTML = '<tr><td colspan="4">Loading...</td></tr>';
      try {
        const response = await fetch('/api/status');
        const data = await response.json();
        rows.innerHTML = data.services.map((item) => {
          const cls = item.ok ? 'ok' : 'bad';
          const statusText = item.ok ? 'online' : (item.error || 'offline');
          return '<tr>' +
            '<td>' + esc(item.label) + '</td>' +
            '<td class=\"' + esc(cls) + '\">' + esc(statusText) + '</td>' +
            '<td>' + esc(item.status) + '</td>' +
            '<td>' + esc(item.latencyMs) + ' ms</td>' +
          '</tr>';
        }).join('');
      } catch (error) {
        rows.innerHTML = '<tr><td colspan="4" class="bad">Failed to load status.</td></tr>';
      }
    }

    async function sendChat() {
      const prompt = document.getElementById('prompt').value.trim();
      if (!prompt) {
        reply.textContent = 'Please enter a message.';
        return;
      }
      reply.textContent = 'Thinking...';
      try {
        const response = await fetch('/api/chat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: prompt }),
        });
        const data = await response.json();
        reply.textContent = data.reply || data.error || 'No reply.';
      } catch (error) {
        reply.textContent = 'Chat request failed.';
      }
    }

    document.getElementById('refresh').addEventListener('click', loadStatus);
    document.getElementById('send').addEventListener('click', sendChat);
    loadStatus();
  </script>
</body>
</html>`;
}

function renderInstallWizard() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Install Wizard - Multi-Node Lab</title>
  <style>
    :root {
      color-scheme: dark;
      font-family: Inter, 'Segoe UI', Arial, sans-serif;
      --bg-base: #050811;
      --glass-bg: rgba(255,255,255,0.04);
      --glass-border: rgba(255,255,255,0.08);
      --glass-shadow: 0 8px 32px rgba(0,0,0,0.5), 0 1px 0 rgba(255,255,255,0.05) inset;
      --accent: #7c6af7;
      --text: #e2e8f0;
      --text-muted: #94a3b8;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: var(--bg-base);
      background-image:
        radial-gradient(ellipse 80% 50% at 20% 10%, rgba(124,106,247,0.18) 0%, transparent 60%),
        radial-gradient(ellipse 60% 40% at 80% 80%, rgba(92,230,92,0.08) 0%, transparent 60%);
      color: var(--text);
      min-height: 100vh;
    }
    header {
      padding: 20px 24px;
      background: rgba(255,255,255,0.03);
      backdrop-filter: blur(12px);
      -webkit-backdrop-filter: blur(12px);
      border-bottom: 1px solid var(--glass-border);
    }
    h1 { font-size: 1.4rem; font-weight: 700; letter-spacing: -0.02em; margin-bottom: 4px; }
    h2 { font-size: 1rem; font-weight: 600; margin-bottom: 10px; }
    main { max-width: 980px; margin: 0 auto; padding: 24px; }
    .small { font-size: 0.88rem; color: var(--text-muted); margin-bottom: 12px; }
    .tabs { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 16px; }
    button {
      background: linear-gradient(135deg, var(--accent), #5b50c8);
      color: #fff;
      border: none;
      padding: 8px 14px;
      border-radius: 8px;
      cursor: pointer;
      font-size: 0.875rem;
      font-weight: 500;
      transition: opacity 0.15s, transform 0.1s;
    }
    button:hover { opacity: 0.88; transform: translateY(-1px); }
    pre {
      background: rgba(0,0,0,0.35);
      border: 1px solid var(--glass-border);
      border-radius: 10px;
      padding: 12px;
      overflow: auto;
      white-space: pre-wrap;
      font-size: 0.875rem;
      line-height: 1.5;
      margin-top: 10px;
    }
    .card {
      background: var(--glass-bg);
      backdrop-filter: blur(16px);
      -webkit-backdrop-filter: blur(16px);
      border: 1px solid var(--glass-border);
      border-radius: 16px;
      padding: 20px;
      box-shadow: var(--glass-shadow);
    }
  </style>
</head>
<body>
  <header>
    <h1>Installation Wizard</h1>
    <div class="small">Per-node GUI runbook with copy/paste install commands. Use this with docs/10_UNIFIED_INSTALL_GUIDEBOOK.md.</div>
  </header>
  <main>
    <div class="tabs" id="tabs"></div>
    <section class="card">
      <h2 id="nodeTitle"></h2>
      <div class="small" id="nodeSummary"></div>
      <pre id="nodeCommands"></pre>
    </section>
  </main>
  <script>
    const brainBaseUrl = ${JSON.stringify(BRAIN_BASE_URL)};
    const lineBreak = '\\n';
    const steps = [
      {
        key: 'node-a',
        label: 'Node A (Brain)',
        summary: 'Run a feasible local model profile first (8B/14B). Promote to larger models only after measured VRAM/latency validation.',
        commands: ['cd node-a-command-center', 'node node-a-command-center.js', '# optional direct fallback test (bypass gateway)', 'curl ' + brainBaseUrl + '/health'].join(lineBreak)
      },
      {
        key: 'node-b',
        label: 'Node B (LiteLLM Gateway)',
        summary: 'Gateway is convenience, not a hard dependency. Keep direct endpoint fallbacks documented for Node A/C.',
        commands: ['cd node-b-litellm', 'cp .env.example .env', 'docker compose -f litellm-stack.yml up -d', 'curl http://localhost:4000/health'].join(lineBreak)
      },
      {
        key: 'node-c',
        label: 'Node C (Intel Arc Vision)',
        summary: 'Install Intel runtime, then deploy Ollama + Chimera Face and validate /dev/dri exposure.',
        commands: ['sudo dnf install intel-level-zero-gpu intel-opencl -y', 'cd node-c-arc', 'docker compose up -d', 'docker exec ollama_intel_arc ollama pull llava'].join(lineBreak)
      },
      {
        key: 'node-d',
        label: 'Node D (Home Assistant)',
        summary: 'Point HA to Node B first; keep emergency direct targets for Node A and Node C in secure notes.',
        commands: ['cp home-assistant/configuration.yaml.snippet /path/to/ha/configuration.yaml', '# restart Home Assistant and verify OpenAI Conversation provider'].join(lineBreak)
      },
      {
        key: 'node-e',
        label: 'Node E (Sentinel/NVR)',
        summary: 'Node E runs its own vision service that calls Node C Ollama directly — no Unraid/LiteLLM hop in the vision path.',
        commands: [
          'cd node-e-sentinel',
          '# Set required env vars before starting:',
          'export NODE_C_OLLAMA_URL=http://<node-c-ip>:11434',
          'export VISION_MODEL=llava',
          'export SENTINEL_TOKEN=<your-secret-token>',
          'export SENTINEL_PORT=3005',
          '# Start the service:',
          'node node-e-sentinel.js',
          '# Verify health (no auth):',
          'curl http://localhost:3005/health',
          '# Check upstream vision node reachability:',
          'curl http://localhost:3005/api/status',
          '# Point Frigate (or other NVR) webhooks to:',
          '#   POST http://<node-e-ip>:3005/api/webhook/frigate',
          '#   Authorization: Bearer <SENTINEL_TOKEN>',
        ].join(lineBreak)
      },
      {
        key: 'kvm',
        label: 'KVM Operator',
        summary: 'Denylist is guardrail-only. Keep REQUIRE_APPROVAL=true and treat ALLOW_DANGEROUS=true as break-glass.',
        commands: ['cd kvm-operator', 'cp .env.example .env', 'python3 -m venv .venv && source .venv/bin/activate', 'pip install -r requirements.txt', 'uvicorn app:app --host 0.0.0.0 --port 5000'].join(lineBreak)
      },
    ];

    const tabs = document.getElementById('tabs');
    const title = document.getElementById('nodeTitle');
    const summary = document.getElementById('nodeSummary');
    const commands = document.getElementById('nodeCommands');

    function selectStep(index) {
      const item = steps[index];
      title.textContent = item.label;
      summary.textContent = item.summary;
      commands.textContent = item.commands;
      tabs.querySelectorAll('button').forEach((btn, i) => {
        btn.style.background = i === index ? '#2563eb' : '#1e40af';
      });
    }

    steps.forEach((item, index) => {
      const btn = document.createElement('button');
      btn.textContent = item.label;
      btn.addEventListener('click', () => selectStep(index));
      tabs.appendChild(btn);
    });
    selectStep(0);
  </script>
</body>
</html>`;
}

function renderSherpaChatPage() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>AI Sherpa — Installation Guide</title>
  <style>
    :root {
      color-scheme: dark;
      font-family: Inter, 'Segoe UI', Arial, sans-serif;
      --bg-base: #050811;
      --glass-bg: rgba(255,255,255,0.04);
      --glass-bg-hover: rgba(255,255,255,0.07);
      --glass-border: rgba(255,255,255,0.08);
      --glass-shadow: 0 8px 32px rgba(0,0,0,0.5), 0 1px 0 rgba(255,255,255,0.05) inset;
      --accent: #7c6af7;
      --accent2: #5ce65c;
      --text: #e2e8f0;
      --text-muted: #94a3b8;
      --ok: #22c55e;
      --bad: #ef4444;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: var(--bg-base);
      background-image:
        radial-gradient(ellipse 80% 50% at 20% 10%, rgba(124,106,247,0.18) 0%, transparent 60%),
        radial-gradient(ellipse 60% 40% at 80% 80%, rgba(92,230,92,0.08) 0%, transparent 60%);
      color: var(--text);
      min-height: 100vh;
      display: flex; flex-direction: column;
    }
    header {
      padding: 16px 24px;
      background: rgba(255,255,255,0.03);
      backdrop-filter: blur(12px);
      -webkit-backdrop-filter: blur(12px);
      border-bottom: 1px solid var(--glass-border);
      display: flex; align-items: center; gap: 12px;
    }
    .sherpa-icon { font-size: 1.8rem; }
    h1 { font-size: 1.3rem; font-weight: 700; letter-spacing: -0.02em; }
    .subtitle { font-size: 0.85rem; color: var(--text-muted); margin-top: 2px; }
    .layout { display: grid; grid-template-columns: 320px 1fr; flex: 1; overflow: hidden; height: calc(100vh - 68px); }
    @media (max-width: 700px) { .layout { grid-template-columns: 1fr; height: auto; } }
    .steps-panel {
      background: var(--glass-bg);
      border-right: 1px solid var(--glass-border);
      overflow-y: auto;
      padding: 16px 12px;
    }
    .steps-title { font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.07em; color: var(--text-muted); margin-bottom: 10px; padding: 0 4px; }
    .step-btn {
      display: block; width: 100%; text-align: left;
      background: transparent; border: 1px solid transparent;
      border-radius: 10px; padding: 10px 12px; margin-bottom: 6px;
      color: var(--text); cursor: pointer; transition: background 0.15s, border-color 0.15s;
      font-size: 0.875rem;
    }
    .step-btn:hover { background: var(--glass-bg-hover); border-color: var(--glass-border); }
    .step-btn.active { background: rgba(124,106,247,0.15); border-color: rgba(124,106,247,0.4); color: #c4bbff; }
    .step-label { font-weight: 600; }
    .step-sub { font-size: 0.78rem; color: var(--text-muted); margin-top: 3px; }
    .chat-panel { display: flex; flex-direction: column; overflow: hidden; }
    .chat-messages {
      flex: 1; overflow-y: auto; padding: 16px 20px;
      display: flex; flex-direction: column; gap: 14px;
    }
    .msg { max-width: 82%; border-radius: 14px; padding: 10px 14px; font-size: 0.9rem; line-height: 1.55; word-break: break-word; }
    .msg-sherpa { align-self: flex-start; background: rgba(124,106,247,0.18); border: 1px solid rgba(124,106,247,0.25); }
    .msg-user { align-self: flex-end; background: rgba(255,255,255,0.07); border: 1px solid var(--glass-border); }
    .msg-label { font-size: 0.72rem; color: var(--text-muted); margin-bottom: 4px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; }
    .chat-input-row {
      padding: 14px 20px;
      border-top: 1px solid var(--glass-border);
      background: rgba(255,255,255,0.02);
      display: flex; gap: 10px; align-items: flex-end;
    }
    textarea {
      flex: 1; min-height: 60px; max-height: 160px;
      border-radius: 10px; background: rgba(0,0,0,0.3);
      color: var(--text); border: 1px solid var(--glass-border);
      padding: 10px; font-size: 0.9rem; resize: vertical; font-family: inherit;
    }
    textarea:focus { outline: none; border-color: rgba(124,106,247,0.5); box-shadow: 0 0 0 3px rgba(124,106,247,0.15); }
    button.send-btn {
      background: linear-gradient(135deg, var(--accent), #5b50c8);
      color: #fff; border: none; padding: 10px 18px;
      border-radius: 10px; cursor: pointer; font-size: 0.875rem;
      font-weight: 600; transition: opacity 0.15s, transform 0.1s; white-space: nowrap;
    }
    button.send-btn:hover { opacity: 0.88; transform: translateY(-1px); }
    button.send-btn:active { transform: translateY(0); }
    .context-hint {
      font-size: 0.78rem; color: rgba(124,106,247,0.8);
      padding: 6px 20px 0; font-style: italic;
    }
    .back-link { font-size: 0.82rem; color: #93c5fd; text-decoration: none; }
    .back-link:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <header>
    <span class="sherpa-icon">🏔️</span>
    <div>
      <h1>AI Sherpa — Your Installation Guide</h1>
      <div class="subtitle">Select a node on the left, then ask me anything about installing and configuring it.</div>
    </div>
    <div style="margin-left:auto"><a class="back-link" href="/">← Dashboard</a></div>
  </header>
  <div class="layout">
    <div class="steps-panel">
      <div class="steps-title">Installation Steps</div>
      <button class="step-btn" id="step-welcome" onclick="selectStep('welcome','Welcome','Start here — let me introduce your home lab and guide you through the overall plan.')">
        <div class="step-label">🗺️ Start Here</div>
        <div class="step-sub">Overview &amp; prerequisites</div>
      </button>
      <button class="step-btn" id="step-node-a" onclick="selectStep('node-a','Node A (Brain)','Node A runs the main AI brain (vLLM or Ollama) on an AMD RX 7900 XTX. It also hosts this dashboard on port 3099.')">
        <div class="step-label">🧠 Node A — Brain</div>
        <div class="step-sub">AMD GPU · vLLM · Dashboard</div>
      </button>
      <button class="step-btn" id="step-node-b" onclick="selectStep('node-b','Node B (Unraid/LiteLLM)','Node B is the Unraid server at 192.168.1.222. It runs LiteLLM gateway, Portainer, Homepage, Uptime Kuma, and Dozzle.')">
        <div class="step-label">🔀 Node B — Gateway</div>
        <div class="step-sub">Unraid · LiteLLM · Portainer</div>
      </button>
      <button class="step-btn" id="step-node-c" onclick="selectStep('node-c','Node C (Intel Arc Vision)','Node C runs Ollama with Intel Arc GPU support for vision tasks (llava model). It also hosts the Open WebUI (Chimera Face).')">
        <div class="step-label">👁️ Node C — Vision</div>
        <div class="step-sub">Intel Arc · Ollama · llava</div>
      </button>
      <button class="step-btn" id="step-node-d" onclick="selectStep('node-d','Node D (Home Assistant)','Node D runs Home Assistant at 192.168.1.149. Configure extended_openai_conversation to point at LiteLLM gateway.')">
        <div class="step-label">🏠 Node D — Home Assistant</div>
        <div class="step-sub">HA · AI conversation</div>
      </button>
      <button class="step-btn" id="step-node-e" onclick="selectStep('node-e','Node E (Sentinel/NVR)','Node E runs the Sentinel vision relay at 192.168.1.116. It accepts Frigate webhooks and routes them to Node C for AI analysis.')">
        <div class="step-label">📷 Node E — Sentinel</div>
        <div class="step-sub">NVR · Frigate · Vision relay</div>
      </button>
      <button class="step-btn" id="step-kvm" onclick="selectStep('kvm','KVM Operator','The KVM Operator is a FastAPI service for AI-controlled KVM/QEMU management with human-in-the-loop approval.')">
        <div class="step-label">🖥️ KVM Operator</div>
        <div class="step-sub">FastAPI · NanoKVM · Approval</div>
      </button>
      <button class="step-btn" id="step-openclaw" onclick="selectStep('openclaw','OpenClaw Integration','OpenClaw is the AI skill gateway. It enables workflow automation, deploy skills, and KVM skills from your AI models.')">
        <div class="step-label">🦾 OpenClaw</div>
        <div class="step-sub">AI skills · Automation</div>
      </button>
    </div>
    <div class="chat-panel">
      <div class="chat-messages" id="chatMessages">
        <div class="msg msg-sherpa">
          <div class="msg-label">🏔️ AI Sherpa</div>
          Welcome! I&apos;m your AI Sherpa — your digital guide through the Grand Unified AI Home Lab installation. 🎉<br><br>
          I know every node, every config file, and every command you need. Select a step on the left to get started, or just ask me anything about your setup!<br><br>
          <strong>Where would you like to start?</strong>
        </div>
      </div>
      <div class="context-hint" id="contextHint"></div>
      <div class="chat-input-row">
        <textarea id="sherpaPrompt" placeholder="Ask the Sherpa… e.g. &quot;How do I install Node B?&quot;" rows="2"></textarea>
        <button class="send-btn" id="sherpaSend">Ask Sherpa ↑</button>
      </div>
    </div>
  </div>
  <script>
    const esc = (v) => String(v)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#039;');
    let currentContext = '';
    const messages = document.getElementById('chatMessages');
    const hint = document.getElementById('contextHint');

    function appendMsg(role, text) {
      const div = document.createElement('div');
      div.className = 'msg ' + (role === 'sherpa' ? 'msg-sherpa' : 'msg-user');
      const label = document.createElement('div');
      label.className = 'msg-label';
      label.textContent = role === 'sherpa' ? '🏔️ AI Sherpa' : '👤 You';
      div.appendChild(label);
      const body = document.createElement('span');
      body.textContent = text;
      div.appendChild(body);
      messages.appendChild(div);
      messages.scrollTop = messages.scrollHeight;
    }

    function selectStep(key, label, description) {
      document.querySelectorAll('.step-btn').forEach(b => b.classList.remove('active'));
      const btn = document.getElementById('step-' + key);
      if (btn) btn.classList.add('active');
      currentContext = label + ': ' + description;
      hint.textContent = 'Context: ' + label + ' — type your question below';
      document.getElementById('sherpaPrompt').placeholder = 'Ask about ' + label + '…';
    }

    async function sendSherpa() {
      const prompt = document.getElementById('sherpaPrompt').value.trim();
      if (!prompt) return;
      document.getElementById('sherpaPrompt').value = '';
      const fullMsg = currentContext ? '[Context: ' + currentContext + '] ' + prompt : prompt;
      appendMsg('user', prompt);
      appendMsg('sherpa', '⏳ Thinking…');
      try {
        const resp = await fetch('/api/sherpa-chat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: fullMsg }),
        });
        const data = await resp.json();
        messages.lastChild.querySelector('span').textContent = data.reply || data.error || 'No reply.';
        messages.scrollTop = messages.scrollHeight;
      } catch {
        messages.lastChild.querySelector('span').textContent = 'Request failed — is the LiteLLM gateway reachable?';
      }
    }

    document.getElementById('sherpaSend').addEventListener('click', sendSherpa);
    document.getElementById('sherpaPrompt').addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendSherpa(); }
    });
    selectStep('welcome', 'Welcome', 'Start here — let me introduce your home lab and guide you through the overall plan.');
  </script>
</body>
</html>`;
}

function renderMobilePage() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
  <meta name="mobile-web-app-capable" content="yes" />
  <meta name="apple-mobile-web-app-capable" content="yes" />
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
  <meta name="apple-mobile-web-app-title" content="Home Lab" />
  <meta name="theme-color" content="#050811" />
  <link rel="manifest" href="/manifest.json" />
  <title>Home Lab Monitor</title>
  <style>
    :root {
      color-scheme: dark;
      font-family: Inter, 'Segoe UI', Arial, sans-serif;
      --bg-base: #050811;
      --glass-bg: rgba(255,255,255,0.05);
      --glass-border: rgba(255,255,255,0.09);
      --accent: #7c6af7;
      --text: #e2e8f0;
      --text-muted: #94a3b8;
      --ok: #22c55e;
      --bad: #ef4444;
      --warn: #f59e0b;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; -webkit-tap-highlight-color: transparent; }
    body {
      background: var(--bg-base);
      background-image:
        radial-gradient(ellipse 80% 50% at 20% 10%, rgba(124,106,247,0.15) 0%, transparent 60%);
      color: var(--text);
      min-height: 100vh; min-height: 100dvh;
    }
    header {
      padding: 14px 16px;
      background: rgba(255,255,255,0.03);
      backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px);
      border-bottom: 1px solid var(--glass-border);
      display: flex; align-items: center; justify-content: space-between;
      position: sticky; top: 0; z-index: 10;
    }
    .header-title { font-size: 1.1rem; font-weight: 700; }
    .header-sub { font-size: 0.75rem; color: var(--text-muted); margin-top: 2px; }
    .refresh-btn {
      background: rgba(124,106,247,0.2); color: var(--accent);
      border: 1px solid rgba(124,106,247,0.35);
      border-radius: 8px; padding: 7px 14px;
      font-size: 0.85rem; font-weight: 600; cursor: pointer;
      transition: background 0.15s;
    }
    .refresh-btn:active { background: rgba(124,106,247,0.35); }
    main { padding: 14px; display: flex; flex-direction: column; gap: 10px; }
    .section-title { font-size: 0.72rem; text-transform: uppercase; letter-spacing: 0.07em; color: var(--text-muted); margin-bottom: 6px; padding: 0 2px; }
    .tiles { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
    .tile {
      background: var(--glass-bg);
      border: 1px solid var(--glass-border);
      border-radius: 14px; padding: 14px 12px;
      display: flex; flex-direction: column; gap: 6px;
      transition: border-color 0.2s;
    }
    .tile.ok { border-color: rgba(34,197,94,0.25); }
    .tile.bad { border-color: rgba(239,68,68,0.25); }
    .tile-name { font-size: 0.82rem; font-weight: 600; color: var(--text-muted); }
    .tile-status { font-size: 1.05rem; font-weight: 700; }
    .tile-status.ok { color: var(--ok); }
    .tile-status.bad { color: var(--bad); }
    .tile-latency { font-size: 0.75rem; color: var(--text-muted); }
    .chat-section {
      background: var(--glass-bg);
      border: 1px solid var(--glass-border);
      border-radius: 16px; padding: 14px; margin-top: 4px;
    }
    .chat-log {
      min-height: 100px; max-height: 220px; overflow-y: auto;
      font-size: 0.875rem; line-height: 1.5; margin-bottom: 10px;
      display: flex; flex-direction: column; gap: 8px;
    }
    .chat-msg { padding: 8px 12px; border-radius: 10px; }
    .chat-msg.sherpa { background: rgba(124,106,247,0.15); border: 1px solid rgba(124,106,247,0.2); }
    .chat-msg.user { background: rgba(255,255,255,0.05); border: 1px solid var(--glass-border); align-self: flex-end; max-width: 85%; }
    .chat-input-row { display: flex; gap: 8px; align-items: flex-end; }
    .chat-input {
      flex: 1; padding: 10px 12px; border-radius: 10px;
      background: rgba(0,0,0,0.3); color: var(--text);
      border: 1px solid var(--glass-border); font-size: 0.9rem;
      font-family: inherit;
    }
    .chat-input:focus { outline: none; border-color: rgba(124,106,247,0.5); }
    .ask-btn {
      background: linear-gradient(135deg, var(--accent), #5b50c8);
      color: #fff; border: none; padding: 10px 14px;
      border-radius: 10px; font-size: 0.875rem; font-weight: 600;
      cursor: pointer; white-space: nowrap; min-width: 44px;
    }
    .ts { font-size: 0.72rem; color: var(--text-muted); text-align: center; padding: 6px 0; }
    a { color: #93c5fd; text-decoration: none; font-size: 0.85rem; }
  </style>
</head>
<body>
  <header>
    <div>
      <div class="header-title">🏠 Home Lab Monitor</div>
      <div class="header-sub" id="lastRefresh">Refreshing…</div>
    </div>
    <button class="refresh-btn" id="refreshBtn">↻ Refresh</button>
  </header>
  <main>
    <div class="section-title">Service Status</div>
    <div class="tiles" id="tiles"><div style="grid-column:1/-1;text-align:center;padding:20px;color:var(--text-muted)">Loading…</div></div>
    <div class="ts" id="ts"></div>

    <div class="chat-section">
      <div class="section-title" style="margin-bottom:8px">🏔️ Ask the Sherpa</div>
      <div class="chat-log" id="mobileChatLog">
        <div class="chat-msg sherpa">Hi! I&apos;m your AI Sherpa. Ask me anything about your home lab!</div>
      </div>
      <div class="chat-input-row">
        <input class="chat-input" id="mobileInput" type="text" placeholder="Ask a question…" />
        <button class="ask-btn" id="mobileAsk">↑</button>
      </div>
    </div>

    <div style="text-align:center;padding:10px 0">
      <a href="/">Full Dashboard</a> &nbsp;·&nbsp;
      <a href="/sherpa">AI Sherpa</a> &nbsp;·&nbsp;
      <a href="/install-wizard">Install Wizard</a>
    </div>
  </main>
  <script>
    const esc = (v) => String(v)
      .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    const tiles = document.getElementById('tiles');
    const tsEl = document.getElementById('ts');
    const lastRefresh = document.getElementById('lastRefresh');

    async function loadStatus() {
      lastRefresh.textContent = 'Refreshing…';
      try {
        const r = await fetch('/api/status');
        const d = await r.json();
        tiles.innerHTML = d.services.map(s => {
          const cls = s.ok ? 'ok' : 'bad';
          const icon = s.ok ? '✅' : '❌';
          return '<div class="tile ' + esc(cls) + '">' +
            '<div class="tile-name">' + esc(s.label) + '</div>' +
            '<div class="tile-status ' + esc(cls) + '">' + icon + ' ' + esc(s.ok ? 'Online' : (s.error || 'Offline')) + '</div>' +
            '<div class="tile-latency">' + (s.ok ? esc(s.latencyMs) + ' ms' : 'HTTP ' + esc(s.status)) + '</div>' +
            '</div>';
        }).join('');
        const t = new Date(d.timestamp);
        tsEl.textContent = 'Last check: ' + t.toLocaleTimeString();
        lastRefresh.textContent = 'Updated ' + t.toLocaleTimeString();
      } catch {
        tiles.innerHTML = '<div style="grid-column:1/-1;text-align:center;color:var(--bad)">Failed to load status</div>';
        lastRefresh.textContent = 'Error loading status';
      }
    }

    document.getElementById('refreshBtn').addEventListener('click', loadStatus);
    loadStatus();
    setInterval(loadStatus, 30000);

    // Mobile Sherpa chat
    const chatLog = document.getElementById('mobileChatLog');
    const mobileInput = document.getElementById('mobileInput');

    function appendMobileMsg(role, text) {
      const d = document.createElement('div');
      d.className = 'chat-msg ' + (role === 'sherpa' ? 'sherpa' : 'user');
      d.textContent = (role === 'sherpa' ? '🏔️ ' : '👤 ') + text;
      chatLog.appendChild(d);
      chatLog.scrollTop = chatLog.scrollHeight;
    }

    async function sendMobile() {
      const msg = mobileInput.value.trim();
      if (!msg) return;
      mobileInput.value = '';
      appendMobileMsg('user', msg);
      appendMobileMsg('sherpa', '⏳ Thinking…');
      try {
        const r = await fetch('/api/sherpa-chat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: msg }),
        });
        const d = await r.json();
        chatLog.lastChild.textContent = '🏔️ ' + (d.reply || d.error || 'No reply.');
        chatLog.scrollTop = chatLog.scrollHeight;
      } catch {
        chatLog.lastChild.textContent = '🏔️ Request failed.';
      }
    }

    document.getElementById('mobileAsk').addEventListener('click', sendMobile);
    mobileInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') sendMobile(); });
  </script>
</body>
</html>`;
}

function renderManifest() {
  return JSON.stringify({
    name: 'Grand Unified AI Home Lab',
    short_name: 'Home Lab',
    description: 'Monitor and manage your AI home lab nodes from any Android device.',
    start_url: '/mobile',
    display: 'standalone',
    background_color: '#050811',
    theme_color: '#050811',
    icons: [
      { src: 'data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>🏠</text></svg>', sizes: '192x192', type: 'image/svg+xml' },
    ],
  }, null, 2);
}

function readRequestBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let totalLength = 0;
    req.on('data', (chunk) => {
      totalLength += chunk.length;
      if (totalLength > MAX_BODY_BYTES) {
        reject(new Error('Payload too large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      resolve(Buffer.concat(chunks).toString('utf-8'));
    });
    req.on('error', reject);
  });
}

async function handleChat(req, res) {
  let parsed;
  try {
    const rawBody = await readRequestBody(req);
    parsed = JSON.parse(rawBody || '{}');
  } catch {
    sendJson(res, 400, { error: 'Invalid JSON body' });
    return;
  }

  const message = typeof parsed.message === 'string' ? parsed.message.trim() : '';
  const model = typeof parsed.model === 'string' && parsed.model.trim() ? parsed.model.trim() : DEFAULT_MODEL;

  if (!message) {
    sendJson(res, 400, { error: 'Field "message" is required' });
    return;
  }
  if (message.length > MAX_CHAT_MESSAGE_CHARS) {
    sendJson(res, 400, { error: `Message too long (max ${MAX_CHAT_MESSAGE_CHARS} chars)` });
    return;
  }

  try {
    const response = await fetchWithRetry(`${LITELLM_BASE_URL}/v1/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${LITELLM_API_KEY}`,
      },
      body: JSON.stringify({
        model,
        messages: [{ role: 'user', content: message }],
      }),
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      sendJson(res, response.status, { error: data.error?.message || 'Upstream chat request failed' });
      return;
    }

    const reply = data.choices?.[0]?.message?.content || '';
    sendJson(res, 200, { reply, model });
  } catch {
    sendJson(res, 502, { error: 'Unable to reach LiteLLM gateway' });
  }
}

async function handleSherpaChat(req, res) {
  let parsed;
  try {
    const rawBody = await readRequestBody(req);
    parsed = JSON.parse(rawBody || '{}');
  } catch {
    sendJson(res, 400, { error: 'Invalid JSON body' });
    return;
  }

  const message = typeof parsed.message === 'string' ? parsed.message.trim() : '';
  if (!message) {
    sendJson(res, 400, { error: 'Field "message" is required' });
    return;
  }
  if (message.length > MAX_CHAT_MESSAGE_CHARS) {
    sendJson(res, 400, { error: `Message too long (max ${MAX_CHAT_MESSAGE_CHARS} chars)` });
    return;
  }

  try {
    const response = await fetchWithRetry(`${LITELLM_BASE_URL}/v1/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${LITELLM_API_KEY}`,
      },
      body: JSON.stringify({
        model: DEFAULT_MODEL,
        messages: [
          { role: 'system', content: SHERPA_SYSTEM_PROMPT },
          { role: 'user', content: message },
        ],
      }),
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      sendJson(res, response.status, { error: data.error?.message || 'Upstream chat request failed' });
      return;
    }

    const reply = data.choices?.[0]?.message?.content || '';
    sendJson(res, 200, { reply });
  } catch {
    sendJson(res, 502, { error: 'Unable to reach LiteLLM gateway' });
  }
}

const server = http.createServer(async (req, res) => {
  const parsedUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'GET' && parsedUrl.pathname === '/') {
    const html = renderDashboard();
    res.writeHead(200, {
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Length': Buffer.byteLength(html),
      'Cache-Control': 'no-store',
    });
    res.end(html);
    return;
  }

  if (req.method === 'GET' && parsedUrl.pathname === '/install-wizard') {
    const html = renderInstallWizard();
    res.writeHead(200, {
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Length': Buffer.byteLength(html),
      'Cache-Control': 'no-store',
    });
    res.end(html);
    return;
  }

  if (req.method === 'GET' && parsedUrl.pathname === '/api/status') {
    const services = await Promise.all(serviceChecks.map(checkService));
    sendJson(res, 200, { timestamp: new Date().toISOString(), services });
    return;
  }

  if (req.method === 'POST' && parsedUrl.pathname === '/api/chat') {
    await handleChat(req, res);
    return;
  }

  if (req.method === 'GET' && parsedUrl.pathname === '/sherpa') {
    const html = renderSherpaChatPage();
    res.writeHead(200, {
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Length': Buffer.byteLength(html),
      'Cache-Control': 'no-store',
    });
    res.end(html);
    return;
  }

  if (req.method === 'POST' && parsedUrl.pathname === '/api/sherpa-chat') {
    await handleSherpaChat(req, res);
    return;
  }

  if (req.method === 'GET' && parsedUrl.pathname === '/mobile') {
    const html = renderMobilePage();
    res.writeHead(200, {
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Length': Buffer.byteLength(html),
      'Cache-Control': 'no-store',
    });
    res.end(html);
    return;
  }

  if (req.method === 'GET' && parsedUrl.pathname === '/manifest.json') {
    const body = renderManifest();
    res.writeHead(200, {
      'Content-Type': 'application/manifest+json; charset=utf-8',
      'Content-Length': Buffer.byteLength(body),
      'Cache-Control': 'no-store',
    });
    res.end(body);
    return;
  }

  const docPath = getDocRedirectPath(parsedUrl.pathname);
  if (req.method === 'GET' && docPath) {
    res.writeHead(302, { Location: docPath });
    res.end();
    return;
  }

  sendJson(res, 404, { error: 'Not found' });
});

server.listen(PORT, () => {
  if (NODE_C_BASE_URL.includes('192.168.1.X') || NODE_C_BASE_URL.includes('192.168.1.Y') || NODE_C_BASE_URL.includes('192.168.1.Z')) {
    process.stdout.write('Warning: NODE_C_BASE_URL still uses a placeholder IP. Update it before production.\n');
  }
  if (NODE_E_BASE_URL.includes('192.168.1.X') || NODE_E_BASE_URL.includes('192.168.1.Y') || NODE_E_BASE_URL.includes('192.168.1.Z')) {
    process.stdout.write('Warning: NODE_E_BASE_URL still uses a placeholder IP. Update it before production.\n');
  }
  process.stdout.write(`Node A command center is running at http://localhost:${PORT}\n`);
});
