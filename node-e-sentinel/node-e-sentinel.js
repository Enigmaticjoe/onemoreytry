#!/usr/bin/env node
/**
 * Node E Sentinel — Direct Vision Service
 *
 * Vision pipeline runs entirely on Node E, calling Node C Ollama directly.
 * No dependency on Unraid (Node B) or the LiteLLM gateway.
 *
 * Ollama vision API used: POST /api/generate  { model, prompt, images: [b64], stream: false }
 *
 * Endpoints:
 *   GET  /              Dashboard
 *   GET  /health        Simple health check (no auth)
 *   GET  /api/status    Live reachability of Node C / Node A (no auth)
 *   POST /api/analyze   Analyze a base64 image with a prompt (auth required)
 *   POST /api/webhook/frigate   Frigate NVR event webhook (auth required)
 *   POST /api/webhook/snapshot  Generic NVR snapshot webhook (auth required)
 *
 * Environment variables:
 *   SENTINEL_PORT         HTTP listen port              (default 3005)
 *   NODE_C_OLLAMA_URL     Ollama base URL on Node C     (default http://192.168.1.X:11434)
 *   NODE_A_BASE_URL       Node A vLLM fallback base URL (default http://192.168.1.9:8000)
 *   VISION_MODEL          Ollama model name             (default llava)
 *   SENTINEL_TOKEN        Bearer token for write routes (default — must be set in prod)
 *   REQUEST_TIMEOUT_MS    Vision inference timeout ms   (default 60000)
 */

'use strict';

const http = require('http');
const { URL } = require('url');

// ── Configuration ────────────────────────────────────────────────────────────

const PORT               = Number(process.env.SENTINEL_PORT       || 3005);
const NODE_C_OLLAMA_URL  = process.env.NODE_C_OLLAMA_URL          || 'http://192.168.1.X:11434';
const NODE_A_BASE_URL    = process.env.NODE_A_BASE_URL            || 'http://192.168.1.9:8000';
const VISION_MODEL       = process.env.VISION_MODEL               || 'llava';
const SENTINEL_TOKEN     = process.env.SENTINEL_TOKEN             || '';
const REQUEST_TIMEOUT_MS = Number(process.env.REQUEST_TIMEOUT_MS  || 60000);

const MAX_BODY_BYTES    = 20 * 1024 * 1024; // 20 MB — generous for raw base64 image payloads
const MAX_PROMPT_CHARS  = 2000;

// ── Service reachability checks (direct — no Unraid hop) ────────────────────

const serviceChecks = [
  { key: 'nodeC_ollama', label: 'Node C Ollama',       url: `${NODE_C_OLLAMA_URL}/api/version` },
  { key: 'nodeC_tags',   label: 'Node C model list',   url: `${NODE_C_OLLAMA_URL}/api/tags` },
  { key: 'nodeA_brain',  label: 'Node A Brain vLLM',   url: `${NODE_A_BASE_URL}/health` },
];

// ── Helpers ──────────────────────────────────────────────────────────────────

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
  const tid = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(tid);
  }
}

async function checkService(service) {
  const start = Date.now();
  try {
    const res = await fetchWithTimeout(service.url);
    return { ...service, ok: res.ok, status: res.status, latencyMs: Date.now() - start };
  } catch (err) {
    return {
      ...service,
      ok: false,
      status: 0,
      latencyMs: Date.now() - start,
      error: err.name === 'AbortError' ? 'timeout' : 'unreachable',
    };
  }
}

function sendJson(res, code, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    req.on('data', (chunk) => {
      total += chunk.length;
      if (total > MAX_BODY_BYTES) {
        reject(new Error('Payload too large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf-8')));
    req.on('error', reject);
  });
}

/** Validate Bearer token for write routes. Returns true if auth is satisfied. */
function checkAuth(req, res) {
  if (!SENTINEL_TOKEN) {
    sendJson(res, 500, { error: 'Server misconfigured: SENTINEL_TOKEN not set.' });
    return false;
  }
  const header = req.headers['authorization'] || '';
  if (!header.startsWith('Bearer ')) {
    sendJson(res, 401, { error: 'Missing Bearer token.' });
    return false;
  }
  const provided = header.slice(7).trim();
  if (provided !== SENTINEL_TOKEN) {
    sendJson(res, 403, { error: 'Invalid token.' });
    return false;
  }
  return true;
}

// ── Vision: direct Ollama call (Node C, no Unraid) ───────────────────────────

/**
 * Send an image to Node C Ollama for vision inference.
 *
 * Uses Ollama's native /api/generate with the `images` field — no proxy needed.
 *
 * @param {string} imageB64  Base64-encoded JPEG/PNG (no data-URI prefix)
 * @param {string} prompt    Text instruction for the vision model
 * @param {string} model     Ollama model name (default: VISION_MODEL)
 * @returns {Promise<string>} The model's response text
 */
async function analyzeImageDirect(imageB64, prompt, model = VISION_MODEL) {
  const body = JSON.stringify({
    model,
    prompt,
    images: [imageB64],
    stream: false,
  });

  const res = await fetchWithTimeout(`${NODE_C_OLLAMA_URL}/api/generate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
  });

  const data = await res.json().catch(() => ({}));

  if (!res.ok) {
    throw new Error(`Ollama error ${res.status}: ${data.error || JSON.stringify(data).slice(0, 200)}`);
  }

  const text = data.response;
  if (typeof text !== 'string') {
    throw new Error(`Unexpected Ollama response shape: ${JSON.stringify(data).slice(0, 200)}`);
  }
  return text;
}

/** Strip data-URI prefix if caller included it. */
function normalizeB64(raw) {
  if (typeof raw !== 'string') return '';
  const comma = raw.indexOf(',');
  return comma !== -1 ? raw.slice(comma + 1) : raw;
}

// ── Route handlers ───────────────────────────────────────────────────────────

async function handleAnalyze(req, res) {
  if (!checkAuth(req, res)) return;

  let parsed;
  try {
    const raw = await readBody(req);
    parsed = JSON.parse(raw || '{}');
  } catch {
    sendJson(res, 400, { error: 'Invalid JSON body' });
    return;
  }

  const imageB64 = normalizeB64(parsed.image_b64);
  const prompt   = typeof parsed.prompt === 'string' ? parsed.prompt.trim() : 'Describe what you see in this image.';
  const model    = typeof parsed.model  === 'string' && parsed.model.trim() ? parsed.model.trim() : VISION_MODEL;

  if (!imageB64) {
    sendJson(res, 400, { error: 'Field "image_b64" is required (base64-encoded image).' });
    return;
  }
  if (prompt.length > MAX_PROMPT_CHARS) {
    sendJson(res, 400, { error: `Prompt too long (max ${MAX_PROMPT_CHARS} chars).` });
    return;
  }

  try {
    const answer = await analyzeImageDirect(imageB64, prompt, model);
    sendJson(res, 200, { ok: true, model, prompt, answer });
  } catch (err) {
    sendJson(res, 502, { error: `Vision inference failed: ${err.message}` });
  }
}

/**
 * Frigate NVR webhook handler.
 *
 * Frigate POSTs a JSON event payload. If the event includes a snapshot
 * (base64 field "snapshot_b64") we forward it directly to Node C Ollama.
 * If no snapshot is embedded, we return guidance for calling /api/analyze
 * with a snapshot pulled from Frigate's own REST API.
 *
 * Frigate event shape (relevant fields):
 *   type        "new" | "update" | "end"
 *   after.id    event UUID
 *   after.label detected object class
 *   after.score confidence (0-1)
 *   after.camera camera name
 *   snapshot_b64  (optional) base64 JPEG snapshot from the event
 */
async function handleFrigateWebhook(req, res) {
  if (!checkAuth(req, res)) return;

  let parsed;
  try {
    const raw = await readBody(req);
    parsed = JSON.parse(raw || '{}');
  } catch {
    sendJson(res, 400, { error: 'Invalid JSON body' });
    return;
  }

  const eventType = parsed.type || 'unknown';
  const after     = parsed.after || {};
  const camera    = after.camera   || 'unknown';
  const label     = after.label    || 'unknown';
  const score     = after.score    ?? null;
  const eventId   = after.id       || 'unknown';

  // Only analyze "new" and "update" events that carry a snapshot
  if (!['new', 'update'].includes(eventType)) {
    sendJson(res, 200, { ok: true, skipped: true, reason: `Event type "${eventType}" not analyzed.` });
    return;
  }

  const rawSnap = parsed.snapshot_b64 || after.snapshot_b64 || '';
  const imageB64 = normalizeB64(rawSnap);

  if (!imageB64) {
    // No snapshot embedded — acknowledge and advise caller
    sendJson(res, 200, {
      ok: true,
      skipped: true,
      reason: 'No snapshot_b64 in payload. Pull the snapshot from Frigate REST API and POST to /api/analyze.',
      hint: `GET http://<frigate-host>/api/events/${eventId}/snapshot.jpg then base64-encode and POST to /api/analyze`,
    });
    return;
  }

  const prompt = `Frigate detected a "${label}" (confidence ${score !== null ? Math.round(score * 100) : '?'}%) on camera "${camera}". Describe what you see and whether this looks like a real ${label}.`;

  try {
    const answer = await analyzeImageDirect(imageB64, prompt, VISION_MODEL);
    sendJson(res, 200, {
      ok: true,
      event_id: eventId,
      camera,
      label,
      score,
      model: VISION_MODEL,
      answer,
    });
  } catch (err) {
    sendJson(res, 502, { error: `Vision inference failed: ${err.message}` });
  }
}

/**
 * Generic snapshot webhook.
 *
 * Accepts: { image_b64, prompt, camera, model }
 * Forwards image directly to Node C Ollama.
 */
async function handleSnapshotWebhook(req, res) {
  if (!checkAuth(req, res)) return;

  let parsed;
  try {
    const raw = await readBody(req);
    parsed = JSON.parse(raw || '{}');
  } catch {
    sendJson(res, 400, { error: 'Invalid JSON body' });
    return;
  }

  const imageB64 = normalizeB64(parsed.image_b64 || '');
  const camera   = typeof parsed.camera === 'string' ? parsed.camera.trim() : 'unknown';
  const prompt   = typeof parsed.prompt === 'string' && parsed.prompt.trim()
    ? parsed.prompt.trim()
    : `Camera "${camera}": describe what you see and flag any unusual activity.`;
  const model    = typeof parsed.model  === 'string' && parsed.model.trim() ? parsed.model.trim() : VISION_MODEL;

  if (!imageB64) {
    sendJson(res, 400, { error: 'Field "image_b64" is required.' });
    return;
  }
  if (prompt.length > MAX_PROMPT_CHARS) {
    sendJson(res, 400, { error: `Prompt too long (max ${MAX_PROMPT_CHARS} chars).` });
    return;
  }

  try {
    const answer = await analyzeImageDirect(imageB64, prompt, model);
    sendJson(res, 200, { ok: true, camera, model, prompt, answer });
  } catch (err) {
    sendJson(res, 502, { error: `Vision inference failed: ${err.message}` });
  }
}

// ── Dashboard HTML ───────────────────────────────────────────────────────────

function renderDashboard() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Node E Sentinel — Vision Service</title>
  <style>
    :root { color-scheme: dark; font-family: Inter, Arial, sans-serif; }
    body { margin: 0; background: #0f172a; color: #e2e8f0; }
    header { padding: 18px 20px; border-bottom: 1px solid #1e293b; }
    h1 { margin: 0 0 6px; font-size: 1.35rem; }
    main { display: grid; gap: 16px; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); padding: 20px; }
    section { border: 1px solid #1e293b; border-radius: 10px; background: #111827; padding: 14px; }
    h2 { margin: 0 0 10px; font-size: 1.05rem; }
    table { width: 100%; border-collapse: collapse; font-size: 0.95rem; }
    th, td { border-bottom: 1px solid #1e293b; text-align: left; padding: 8px; }
    .ok  { color: #22c55e; }
    .bad { color: #ef4444; }
    button { background: #2563eb; color: white; border: 0; padding: 8px 12px; border-radius: 8px; cursor: pointer; margin-bottom: 8px; }
    button:hover { background: #1d4ed8; }
    .small { font-size: 0.85rem; color: #94a3b8; margin-top: 6px; }
    code { background: #0b1220; border: 1px solid #334155; border-radius: 4px; padding: 2px 6px; font-size: 0.88rem; }
    pre { background: #0b1220; border: 1px solid #334155; border-radius: 8px; padding: 10px; overflow: auto; white-space: pre-wrap; font-size: 0.88rem; }
    ul { margin: 6px 0 0; padding-left: 20px; }
    li { margin: 6px 0; }
  </style>
</head>
<body>
  <header>
    <h1>Node E Sentinel — Direct Vision Service</h1>
    <div class="small">
      Vision inference via <strong>Node C Ollama</strong> directly.
      No Unraid / LiteLLM gateway in the path.
    </div>
  </header>
  <main>

    <section>
      <h2>Live Status</h2>
      <button id="refresh">Refresh</button>
      <table>
        <thead><tr><th>Service</th><th>Status</th><th>Code</th><th>Latency</th></tr></thead>
        <tbody id="statusRows"></tbody>
      </table>
      <div class="small">Checks go directly to Node C Ollama and Node A vLLM — no proxy hop.</div>
    </section>

    <section>
      <h2>API Reference</h2>
      <ul>
        <li><code>GET /health</code> — Simple health check (no auth)</li>
        <li><code>GET /api/status</code> — Upstream node reachability (no auth)</li>
        <li><code>POST /api/analyze</code> — Analyze base64 image <em>(auth)</em></li>
        <li><code>POST /api/webhook/frigate</code> — Frigate NVR event <em>(auth)</em></li>
        <li><code>POST /api/webhook/snapshot</code> — Generic NVR snapshot <em>(auth)</em></li>
      </ul>
      <div class="small">Auth: <code>Authorization: Bearer &lt;SENTINEL_TOKEN&gt;</code></div>
    </section>

    <section>
      <h2>Vision Model Info</h2>
      <table>
        <tbody id="modelRows"></tbody>
      </table>
      <div class="small">Model list fetched directly from Node C Ollama.</div>
    </section>

    <section>
      <h2>Quick Test</h2>
      <div class="small">Paste a base64 JPEG (no data-URI prefix) and a prompt, then click Analyze. Requires <code>SENTINEL_TOKEN</code> in the field below.</div>
      <div style="margin-bottom:8px;">
        <label>Token: <input id="token" type="password" style="background:#0b1220;color:#e2e8f0;border:1px solid #334155;border-radius:4px;padding:4px 8px;width:220px;" placeholder="SENTINEL_TOKEN value" /></label>
      </div>
      <textarea id="imgB64" style="width:100%;min-height:60px;background:#0b1220;color:#e2e8f0;border:1px solid #334155;border-radius:6px;padding:8px;box-sizing:border-box;font-size:0.8rem;" placeholder="Base64-encoded image (no data: prefix)"></textarea>
      <textarea id="prompt" style="width:100%;min-height:50px;margin-top:6px;background:#0b1220;color:#e2e8f0;border:1px solid #334155;border-radius:6px;padding:8px;box-sizing:border-box;" placeholder="Prompt (leave blank for default description)"></textarea>
      <button id="analyzeBtn" style="margin-top:8px;">Analyze</button>
      <pre id="analyzeResult">Result will appear here.</pre>
    </section>

  </main>

  <script>
    const esc = (v) => String(v)
      .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
      .replace(/"/g,'&quot;').replace(/'/g,'&#039;');

    async function loadStatus() {
      const tbody = document.getElementById('statusRows');
      tbody.innerHTML = '<tr><td colspan="4">Loading...</td></tr>';
      try {
        const r = await fetch('/api/status');
        const d = await r.json();
        tbody.innerHTML = d.services.map((s) => {
          const cls = s.ok ? 'ok' : 'bad';
          const txt = s.ok ? 'online' : (s.error || 'offline');
          return '<tr>' +
            '<td>' + esc(s.label) + '</td>' +
            '<td class="' + esc(cls) + '">' + esc(txt) + '</td>' +
            '<td>' + esc(s.status) + '</td>' +
            '<td>' + esc(s.latencyMs) + ' ms</td>' +
          '</tr>';
        }).join('');
      } catch {
        document.getElementById('statusRows').innerHTML = '<tr><td colspan="4" class="bad">Failed to load status.</td></tr>';
      }
    }

    async function loadModels() {
      const tbody = document.getElementById('modelRows');
      try {
        const r = await fetch('/api/status');
        const d = await r.json();
        const tags = d.tags || [];
        if (!tags.length) {
          tbody.innerHTML = '<tr><td>No models returned or Node C unreachable.</td></tr>';
          return;
        }
        tbody.innerHTML = '<tr><th>Model</th><th>Size</th></tr>' +
          tags.map((m) => '<tr><td>' + esc(m.name) + '</td><td>' + esc(m.size || '—') + '</td></tr>').join('');
      } catch {
        tbody.innerHTML = '<tr><td class="bad">Could not fetch model list.</td></tr>';
      }
    }

    document.getElementById('refresh').addEventListener('click', () => { loadStatus(); loadModels(); });

    document.getElementById('analyzeBtn').addEventListener('click', async () => {
      const token  = document.getElementById('token').value.trim();
      const imgB64 = document.getElementById('imgB64').value.trim();
      const prompt = document.getElementById('prompt').value.trim();
      const out    = document.getElementById('analyzeResult');

      if (!imgB64) { out.textContent = 'Paste a base64 image first.'; return; }
      out.textContent = 'Analyzing...';
      try {
        const r = await fetch('/api/analyze', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
          body: JSON.stringify({ image_b64: imgB64, prompt }),
        });
        const d = await r.json();
        out.textContent = d.answer || d.error || JSON.stringify(d, null, 2);
      } catch (e) {
        out.textContent = 'Request failed: ' + e.message;
      }
    });

    loadStatus();
    loadModels();
  </script>
</body>
</html>`;
}

// ── HTTP server ───────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const parsed = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const path   = parsed.pathname;
  const method = req.method;

  // Dashboard
  if (method === 'GET' && path === '/') {
    const html = renderDashboard();
    res.writeHead(200, {
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Length': Buffer.byteLength(html),
      'Cache-Control': 'no-store',
    });
    res.end(html);
    return;
  }

  // Simple health (no auth — safe for liveness probes)
  if (method === 'GET' && path === '/health') {
    sendJson(res, 200, { ok: true, service: 'node-e-sentinel', model: VISION_MODEL });
    return;
  }

  // Status: reachability of upstream vision nodes + model list
  if (method === 'GET' && path === '/api/status') {
    const [services, tagsRes] = await Promise.all([
      Promise.all(serviceChecks.map(checkService)),
      fetchWithTimeout(`${NODE_C_OLLAMA_URL}/api/tags`).catch(() => null),
    ]);

    let tags = [];
    if (tagsRes && tagsRes.ok) {
      const tagsData = await tagsRes.json().catch(() => ({}));
      tags = (tagsData.models || []).map((m) => ({ name: m.name, size: m.size }));
    }

    sendJson(res, 200, { timestamp: new Date().toISOString(), services, tags });
    return;
  }

  // Vision: analyze an arbitrary image
  if (method === 'POST' && path === '/api/analyze') {
    await handleAnalyze(req, res);
    return;
  }

  // Webhook: Frigate NVR
  if (method === 'POST' && path === '/api/webhook/frigate') {
    await handleFrigateWebhook(req, res);
    return;
  }

  // Webhook: generic NVR snapshot
  if (method === 'POST' && path === '/api/webhook/snapshot') {
    await handleSnapshotWebhook(req, res);
    return;
  }

  sendJson(res, 404, { error: 'Not found' });
});

server.listen(PORT, () => {
  const warnings = [];
  if (NODE_C_OLLAMA_URL.includes('192.168.1.X')) {
    warnings.push('NODE_C_OLLAMA_URL still uses placeholder IP (192.168.1.X). Set it before production.');
  }
  if (!SENTINEL_TOKEN) {
    warnings.push('SENTINEL_TOKEN is not set. Write endpoints (analyze, webhooks) will reject all requests.');
  }

  process.stdout.write(`Node E Sentinel vision service running at http://localhost:${PORT}\n`);
  process.stdout.write(`Vision model : ${VISION_MODEL}\n`);
  process.stdout.write(`Node C Ollama: ${NODE_C_OLLAMA_URL}  (direct — no Unraid hop)\n`);
  warnings.forEach((w) => process.stderr.write(`Warning: ${w}\n`));
});
