#!/usr/bin/env node

const http = require('http');
const { URL } = require('url');

const PORT = Number(process.env.COMMAND_CENTER_PORT || 3099);
const LITELLM_BASE_URL = process.env.LITELLM_BASE_URL || 'http://192.168.1.222:4000';
const BRAIN_BASE_URL = process.env.BRAIN_BASE_URL || 'http://192.168.1.9:8000';
const NODE_C_BASE_URL = process.env.NODE_C_BASE_URL || 'http://192.168.1.6';
const NODE_E_BASE_URL = process.env.NODE_E_BASE_URL || 'http://192.168.1.116:3005';
const LITELLM_API_KEY = process.env.LITELLM_API_KEY || 'sk-master-key';
const DEFAULT_MODEL = process.env.DEFAULT_MODEL || 'brain-heavy';
const REQUEST_TIMEOUT_MS = Number(process.env.REQUEST_TIMEOUT_MS || 7000);
const MAX_BODY_BYTES = 128 * 1024;
const MAX_CHAT_MESSAGE_CHARS = 5000;

const serviceChecks = [
  { key: 'gateway', label: 'Node B LiteLLM Gateway', url: `${LITELLM_BASE_URL}/health` },
  { key: 'brain', label: 'Node A Brain vLLM', url: `${BRAIN_BASE_URL}/health` },
  { key: 'vision', label: 'Node C Vision (Ollama)', url: `${NODE_C_BASE_URL}:11434/api/version` },
  { key: 'nodeCUi', label: 'Node C Chimera Face UI', url: `${NODE_C_BASE_URL}:3000` },
  { key: 'nodeE', label: 'Node E Sentinel (Vision)', url: `${NODE_E_BASE_URL}/health` },
];

const dashboardLinks = [
  { name: 'LiteLLM Gateway Health', href: `${LITELLM_BASE_URL}/health` },
  { name: 'Node C Chimera Face UI', href: `${NODE_C_BASE_URL}:3000` },
  { name: 'Node E Sentinel Dashboard', href: `${NODE_E_BASE_URL}` },
  { name: 'Deployment Guide', href: '/docs/DEPLOYMENT_GUIDE' },
  { name: 'Quick Reference', href: '/docs/QUICK_REFERENCE' },
  { name: 'Node A Guidebook', href: '/docs/NODE_A_GUIDEBOOK' },
  { name: 'Unified Install Guidebook', href: '/docs/UNIFIED_INSTALL_GUIDEBOOK' },
  { name: 'Install Wizard', href: '/install-wizard' },
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
    :root { color-scheme: dark; font-family: Inter, Arial, sans-serif; }
    body { margin: 0; background: #0f172a; color: #e2e8f0; }
    header { padding: 18px 20px; border-bottom: 1px solid #1e293b; }
    h1 { margin: 0 0 6px; font-size: 1.35rem; }
    main { display: grid; gap: 16px; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); padding: 20px; }
    section { border: 1px solid #1e293b; border-radius: 10px; background: #111827; padding: 14px; }
    ul { margin: 8px 0 0; padding-left: 20px; }
    li { margin: 8px 0; }
    a { color: #93c5fd; }
    button { background: #2563eb; color: white; border: 0; padding: 8px 12px; border-radius: 8px; cursor: pointer; }
    button:hover { background: #1d4ed8; }
    table { width: 100%; border-collapse: collapse; font-size: 0.95rem; }
    th, td { border-bottom: 1px solid #1e293b; text-align: left; padding: 8px; }
    .ok { color: #22c55e; }
    .bad { color: #ef4444; }
    textarea { width: 100%; min-height: 90px; border-radius: 8px; background: #0b1220; color: #e2e8f0; border: 1px solid #334155; padding: 10px; box-sizing: border-box; }
    pre { background: #0b1220; border-radius: 8px; border: 1px solid #334155; padding: 10px; min-height: 90px; overflow: auto; white-space: pre-wrap; }
    .small { font-size: 0.85rem; color: #94a3b8; }
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
    :root { color-scheme: dark; font-family: Inter, Arial, sans-serif; }
    body { margin: 0; background: #0f172a; color: #e2e8f0; }
    header { padding: 16px 20px; border-bottom: 1px solid #1e293b; }
    main { max-width: 980px; margin: 0 auto; padding: 16px; }
    h1, h2 { margin: 0 0 8px; }
    .small { font-size: 0.9rem; color: #94a3b8; margin-bottom: 12px; }
    .tabs { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 12px; }
    button { background: #1e40af; color: #fff; border: 0; padding: 8px 12px; border-radius: 8px; cursor: pointer; }
    button:hover { background: #1d4ed8; }
    pre { background: #0b1220; border: 1px solid #334155; border-radius: 8px; padding: 10px; overflow: auto; white-space: pre-wrap; }
    .card { border: 1px solid #1e293b; border-radius: 10px; background: #111827; padding: 14px; }
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
    const response = await fetchWithTimeout(`${LITELLM_BASE_URL}/v1/chat/completions`, {
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
