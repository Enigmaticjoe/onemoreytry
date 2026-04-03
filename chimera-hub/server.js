const fs = require("fs");
const path = require("path");
const os = require("os");
const dgram = require("dgram");
const express = require("express");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const WebSocket = require("ws");

const app = express();
app.use(express.json({ limit: "512kb" }));

const PORT = Number(process.env.PORT || 3099);
const REQUEST_TIMEOUT_MS = Number(process.env.REQUEST_TIMEOUT_MS || 5000);
const PORTAINER_ENDPOINT_ID = Number(process.env.PORTAINER_ENDPOINT_ID || 3);

const PORTAINER_URL = (process.env.PORTAINER_URL || "http://192.168.1.222:9000").replace(/\/$/, "");
const PORTAINER_TOKEN = process.env.PORTAINER_TOKEN || process.env.PORTAINER_API_KEY || "";
const LITELLM_BASE_URL = (process.env.LITELLM_BASE_URL || "http://192.168.1.222:4000").replace(/\/$/, "");
const LITELLM_API_KEY = process.env.LITELLM_API_KEY || "";
const HOME_ASSISTANT_URL = (process.env.HOME_ASSISTANT_URL || process.env.HOME_ASSISTANT_BASE_URL || "http://192.168.1.149:8123").replace(/\/$/, "");
const HOME_ASSISTANT_TOKEN = process.env.HOME_ASSISTANT_TOKEN || "";
const KVM_OPERATOR_URL = (process.env.KVM_OPERATOR_URL || "http://192.168.1.9:5000").replace(/\/$/, "");
const KVM_OPERATOR_TOKEN = process.env.KVM_OPERATOR_TOKEN || "";
const BROTHERS_KEEPER_URL = (process.env.BROTHERS_KEEPER_URL || "http://192.168.1.9:7070").replace(/\/$/, "");
const DOZZLE_URL = (process.env.DOZZLE_URL || "http://192.168.1.222:8888").replace(/\/$/, "");
const UPTIME_KUMA_URL = (process.env.UPTIME_KUMA_URL || "http://192.168.1.222:3010").replace(/\/$/, "");
const OPENCLAW_RELAY_URL = (process.env.OPENCLAW_RELAY_URL || "http://192.168.1.222:18790").replace(/\/$/, "");

const JWT_SECRET = process.env.JWT_SECRET || "replace-me-now";
const ADMIN_PASSWORD = process.env.CHIMERA_HUB_ADMIN_PASSWORD || "";
const AUTH_FILE = process.env.CHIMERA_HUB_AUTH_FILE || "/app/data/auth.json";

const NODE_INVENTORY_FILE = process.env.CHIMERA_NODE_INVENTORY || path.resolve(__dirname, "../config/node-inventory.env");
const DENYLIST_FILE = process.env.KVM_DENYLIST_PATH || path.resolve(__dirname, "../kvm-operator/policy_denylist.txt");

function resolveWritablePath(preferredPath, fallbackFileName) {
  const preferredDir = path.dirname(preferredPath);
  try {
    fs.mkdirSync(preferredDir, { recursive: true });
    fs.accessSync(preferredDir, fs.constants.W_OK);
    return preferredPath;
  } catch (_error) {
    const fallbackDir = path.join(os.tmpdir(), "chimera-hub");
    fs.mkdirSync(fallbackDir, { recursive: true });
    const fallbackPath = path.join(fallbackDir, fallbackFileName);
    console.warn(`[chimera-hub] ${preferredPath} is not writable; using ${fallbackPath}`);
    return fallbackPath;
  }
}

const AUTH_STORE_FILE = resolveWritablePath(AUTH_FILE, "auth.json");
const INVENTORY_STORE_FILE = resolveWritablePath(NODE_INVENTORY_FILE, "node-inventory.env");

const LITELLM_ALIASES = [
  "brain-heavy",
  "brain-vision",
  "brawn-fast",
  "brawn-code",
  "intel-fast",
  "intel-uncensored",
  "intel-vision",
];

const WOL_TARGETS = {
  a: process.env.NODE_A_WOL_MAC || process.env.NODE_A_MAC || "",
  b: process.env.NODE_B_WOL_MAC || process.env.NODE_B_MAC || "",
  c: process.env.NODE_C_WOL_MAC || process.env.NODE_C_MAC || "",
  d: process.env.NODE_D_WOL_MAC || process.env.NODE_D_MAC || "",
  e: process.env.NODE_E_WOL_MAC || process.env.NODE_E_MAC || "",
};

function parseEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return {};
  let lines = [];
  try {
    lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/);
  } catch (_error) {
    return {};
  }
  const result = {};
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const idx = trimmed.indexOf("=");
    if (idx === -1) continue;
    const key = trimmed.slice(0, idx).trim();
    const value = trimmed.slice(idx + 1).trim();
    result[key] = value;
  }
  return result;
}

function loadDenylist() {
  if (!fs.existsSync(DENYLIST_FILE)) return [];
  try {
    return fs
      .readFileSync(DENYLIST_FILE, "utf8")
      .split(/\r?\n/)
      .map((line) => line.trim().toLowerCase())
      .filter((line) => line && !line.startsWith("#"));
  } catch (_error) {
    return [];
  }
}

const denylist = loadDenylist();

function setAuthCookie(res, token) {
  res.cookie("chimera_hub_session", token, {
    httpOnly: true,
    sameSite: "lax",
    secure: false,
    maxAge: 8 * 60 * 60 * 1000,
  });
}

function clearAuthCookie(res) {
  res.clearCookie("chimera_hub_session", { httpOnly: true, sameSite: "lax", secure: false });
}

function getSessionToken(req) {
  const header = req.headers.authorization;
  if (header && header.startsWith("Bearer ")) {
    return header.slice("Bearer ".length).trim();
  }
  const cookie = req.headers.cookie || "";
  const match = cookie.match(/(?:^|;\s*)chimera_hub_session=([^;]+)/);
  if (match) return decodeURIComponent(match[1]);
  return "";
}

function issueSession(payload = {}) {
  return jwt.sign({ role: "admin", ...payload }, JWT_SECRET, { expiresIn: "8h" });
}

function requireAuth(req, res, next) {
  const token = getSessionToken(req);
  if (!token) {
    res.status(401).json({ error: "Authentication required", code: 401 });
    return;
  }
  try {
    req.user = jwt.verify(token, JWT_SECRET);
    next();
  } catch (_err) {
    res.status(401).json({ error: "Invalid session", code: 401 });
  }
}

async function withTimeout(url, options = {}, timeoutMs = REQUEST_TIMEOUT_MS) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    return response;
  } finally {
    clearTimeout(timeout);
  }
}

async function safeProbe(name, url, options = {}) {
  try {
    const start = Date.now();
    const response = await withTimeout(url, options);
    const latencyMs = Date.now() - start;
    return { name, status: response.ok ? "ok" : "degraded", statusCode: response.status, latencyMs };
  } catch (error) {
    return { name, status: "degraded", reason: "ECONNREFUSED", detail: error?.name || "error" };
  }
}

async function ensureAuthFile() {
  const dir = path.dirname(AUTH_STORE_FILE);
  fs.mkdirSync(dir, { recursive: true });
  if (fs.existsSync(AUTH_STORE_FILE)) return;
  const generated = ADMIN_PASSWORD || Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
  const passwordHash = await bcrypt.hash(generated, 12);
  fs.writeFileSync(AUTH_STORE_FILE, JSON.stringify({ passwordHash }, null, 2), "utf8");
  console.log(`[chimera-hub] Initial admin password generated: ${generated}`);
}

async function readAuthHash() {
  await ensureAuthFile();
  const data = JSON.parse(fs.readFileSync(AUTH_STORE_FILE, "utf8"));
  return data.passwordHash || "";
}

function errResponse(res, statusCode, message) {
  res.status(statusCode).json({ error: message, code: statusCode });
}

function upstreamErrorMessage(payload, fallback) {
  if (!payload || typeof payload !== "object") return fallback;
  if (typeof payload.error === "string") return payload.error;
  if (payload.error && typeof payload.error.message === "string") return payload.error.message;
  if (typeof payload.detail === "string") return payload.detail;
  if (typeof payload.message === "string") return payload.message;
  return fallback;
}

function sanitizeInventoryKey(key) {
  return typeof key === "string" && /^[A-Z][A-Z0-9_]*$/.test(key);
}

function atomicWriteFile(targetPath, content) {
  const dir = path.dirname(targetPath);
  fs.mkdirSync(dir, { recursive: true });
  const tempPath = path.join(
    dir,
    `.tmp-${path.basename(targetPath)}-${Date.now()}-${Math.random().toString(16).slice(2)}`
  );
  fs.writeFileSync(tempPath, content, "utf8");
  fs.renameSync(tempPath, targetPath);
}

function portainerHeaders() {
  if (!PORTAINER_TOKEN) return {};
  return { "X-API-Key": PORTAINER_TOKEN };
}

function extractQueueCount(payload) {
  if (Array.isArray(payload)) return payload.length;
  if (payload && Array.isArray(payload.records)) return payload.records.length;
  if (payload && typeof payload.totalRecords === "number") return payload.totalRecords;
  return null;
}

function parseMac(raw) {
  const compact = String(raw || "").toLowerCase().replace(/[^a-f0-9]/g, "");
  if (compact.length !== 12) return null;
  const bytes = [];
  for (let i = 0; i < compact.length; i += 2) {
    bytes.push(parseInt(compact.slice(i, i + 2), 16));
  }
  return Buffer.from(bytes);
}

function sendWol(mac) {
  return new Promise((resolve, reject) => {
    const macBytes = parseMac(mac);
    if (!macBytes) {
      reject(new Error("Invalid MAC address format"));
      return;
    }
    const packet = Buffer.concat([Buffer.alloc(6, 0xff), Buffer.concat(Array(16).fill(macBytes))]);
    const socket = dgram.createSocket("udp4");
    socket.on("error", (error) => {
      socket.close();
      reject(error);
    });
    socket.bind(() => {
      socket.setBroadcast(true);
      socket.send(packet, 0, packet.length, 9, "255.255.255.255", (error) => {
        socket.close();
        if (error) reject(error);
        else resolve();
      });
    });
  });
}

function cpuPercent(stats) {
  const cpuDelta =
    (stats?.cpu_stats?.cpu_usage?.total_usage || 0) - (stats?.precpu_stats?.cpu_usage?.total_usage || 0);
  const systemDelta = (stats?.cpu_stats?.system_cpu_usage || 0) - (stats?.precpu_stats?.system_cpu_usage || 0);
  const cpuCount = stats?.cpu_stats?.online_cpus || stats?.cpu_stats?.cpu_usage?.percpu_usage?.length || 1;
  if (cpuDelta <= 0 || systemDelta <= 0) return 0;
  return Number(((cpuDelta / systemDelta) * cpuCount * 100).toFixed(2));
}

app.post("/api/auth/login", async (req, res) => {
  try {
    const password = String(req.body?.password || "");
    if (!password) {
      errResponse(res, 400, "Password is required");
      return;
    }
    const hash = await readAuthHash();
    const ok = await bcrypt.compare(password, hash);
    if (!ok) {
      errResponse(res, 401, "Invalid credentials");
      return;
    }
    const token = issueSession();
    setAuthCookie(res, token);
    res.status(200).json({ ok: true, token });
  } catch (error) {
    errResponse(res, 500, `Login failed: ${error.message}`);
  }
});

app.post("/api/auth/logout", (_req, res) => {
  clearAuthCookie(res);
  res.status(200).json({ ok: true });
});

app.get("/api/health", async (_req, res) => {
  const inventory = parseEnvFile(INVENTORY_STORE_FILE);
  const checks = [
    safeProbe("node_a_kvm", `${KVM_OPERATOR_URL}/health`),
    safeProbe("node_a_brothers_keeper", `${BROTHERS_KEEPER_URL}/health`),
    safeProbe("node_b_litellm", `${LITELLM_BASE_URL}/health/liveliness`),
    safeProbe("node_b_portainer", `${PORTAINER_URL}/api/status`, { headers: portainerHeaders() }),
    safeProbe("node_b_openclaw", `${OPENCLAW_RELAY_URL}/health`),
    safeProbe("node_b_homepage", "http://192.168.1.222:8010"),
    safeProbe("node_d_home_assistant", `${HOME_ASSISTANT_URL}/api/`, {
      headers: HOME_ASSISTANT_TOKEN ? { Authorization: `Bearer ${HOME_ASSISTANT_TOKEN}` } : {},
    }),
    safeProbe("node_c_open_webui", "http://100.64.20.118:3000/health"),
  ];
  const settled = await Promise.allSettled(checks);
  const services = settled.map((entry) =>
    entry.status === "fulfilled" ? entry.value : { status: "degraded", reason: "ECONNREFUSED" }
  );
  const degraded = services.filter((service) => service.status !== "ok").length;
  res.status(200).json({
    status: degraded === 0 ? "ok" : "degraded",
    service: "chimera-hub",
    checks: services,
    inventorySummary: {
      nodeA: inventory.NODE_A_IP || null,
      nodeB: inventory.NODE_B_IP || null,
      nodeC: inventory.NODE_C_IP || null,
      nodeD: inventory.NODE_D_IP || null,
      nodeE: inventory.NODE_E_IP || null,
    },
  });
});

app.get("/api/status", requireAuth, async (_req, res) => {
  try {
    const [containersRes, endpointsRes] = await Promise.all([
      withTimeout(`${PORTAINER_URL}/api/endpoints/${PORTAINER_ENDPOINT_ID}/docker/containers/json?all=1`, {
        headers: portainerHeaders(),
      }),
      withTimeout(`${PORTAINER_URL}/api/endpoints`, { headers: portainerHeaders() }),
    ]);
    const containers = containersRes.ok ? await containersRes.json() : [];
    const endpoints = endpointsRes.ok ? await endpointsRes.json() : [];
    const reduced = containers.map((container) => ({
      id: container.Id,
      names: container.Names,
      image: container.Image,
      state: container.State,
      status: container.Status,
    }));
    const running = reduced.filter((container) => container.state === "running").slice(0, 12);
    const statsSettled = await Promise.allSettled(
      running.map(async (container) => {
        const response = await withTimeout(
          `${PORTAINER_URL}/api/endpoints/${PORTAINER_ENDPOINT_ID}/docker/containers/${container.id}/stats?stream=false`,
          { headers: portainerHeaders() },
          REQUEST_TIMEOUT_MS * 2
        );
        if (!response.ok) {
          return { id: container.id, name: container.names?.[0] || container.id, statusCode: response.status };
        }
        const stats = await response.json();
        const memoryUsage = Number(stats?.memory_stats?.usage || 0);
        const memoryLimit = Number(stats?.memory_stats?.limit || 0);
        const memoryPercent = memoryLimit > 0 ? Number(((memoryUsage / memoryLimit) * 100).toFixed(2)) : 0;
        return {
          id: container.id,
          name: container.names?.[0] || container.id,
          cpuPercent: cpuPercent(stats),
          memoryUsage,
          memoryLimit,
          memoryPercent,
        };
      })
    );
    const containerMetrics = statsSettled
      .filter((entry) => entry.status === "fulfilled")
      .map((entry) => entry.value);

    let gpu = { status: "unknown" };
    try {
      const kvmHealth = await withTimeout(`${KVM_OPERATOR_URL}/health`);
      if (kvmHealth.ok) {
        gpu = { status: "available-via-node-a" };
      }
    } catch (_error) {
      gpu = { status: "degraded", reason: "ECONNREFUSED" };
    }

    res.status(200).json({
      containerCount: reduced.length,
      containers: reduced,
      containerMetrics,
      gpu,
      endpoints: Array.isArray(endpoints)
        ? endpoints.map((endpoint) => ({ id: endpoint.Id, name: endpoint.Name, url: endpoint.URL }))
        : [],
      dozzle: DOZZLE_URL,
      uptimeKuma: UPTIME_KUMA_URL,
    });
  } catch (error) {
    errResponse(res, 500, `Status fetch failed: ${error.message}`);
  }
});

app.post("/api/chat", requireAuth, async (req, res) => {
  try {
    const messages = Array.isArray(req.body?.messages) ? req.body.messages : [];
    const model = String(req.body?.model || LITELLM_ALIASES[0]);
    const started = Date.now();
    const response = await withTimeout(`${LITELLM_BASE_URL}/v1/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(LITELLM_API_KEY ? { Authorization: `Bearer ${LITELLM_API_KEY}` } : {}),
      },
      body: JSON.stringify({ model, messages, stream: false }),
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      errResponse(res, 502, upstreamErrorMessage(payload, "Chat route failed"));
      return;
    }
    res.status(response.ok ? 200 : 502).json({
      route_used: model,
      fallback_used: false,
      latency_ms: Date.now() - started,
      raw: payload,
    });
  } catch (error) {
    errResponse(res, 502, `Chat route failed: ${error.message}`);
  }
});

app.post("/api/voice/transcribe", requireAuth, async (req, res) => {
  try {
    const response = await withTimeout("http://192.168.1.222:9191/v1/transcribe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(req.body || {}),
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      errResponse(res, 502, upstreamErrorMessage(payload, "Voice transcribe failed"));
      return;
    }
    res.status(200).json(payload);
  } catch (error) {
    errResponse(res, 502, `Voice transcribe failed: ${error.message}`);
  }
});

app.post("/api/vision/analyze", requireAuth, async (req, res) => {
  try {
    const prompt = String(req.body?.prompt || "Describe this image.");
    const images = Array.isArray(req.body?.images) ? req.body.images : [];
    const response = await withTimeout("http://100.64.20.118:11435/api/generate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: "llava",
        prompt,
        images,
        stream: false,
      }),
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      errResponse(res, 502, upstreamErrorMessage(payload, "Vision analysis failed"));
      return;
    }
    res.status(200).json(payload);
  } catch (error) {
    errResponse(res, 502, `Vision analysis failed: ${error.message}`);
  }
});

app.post("/api/wol/wake", requireAuth, (req, res) => {
  const node = String(req.body?.node || "").toLowerCase();
  if (!node) {
    errResponse(res, 400, "Node alias required");
    return;
  }
  const mac = WOL_TARGETS[node];
  if (!mac) {
    errResponse(res, 400, `No WOL MAC configured for node '${node}'`);
    return;
  }
  sendWol(mac)
    .then(() => {
      res.status(200).json({ ok: true, requested: node, mac });
    })
    .catch((error) => {
      errResponse(res, 502, `WOL failed: ${error.message}`);
    });
});

app.get("/api/portainer/stacks", requireAuth, async (_req, res) => {
  try {
    const response = await withTimeout(`${PORTAINER_URL}/api/stacks`, { headers: portainerHeaders() });
    const payload = await response.json().catch(() => []);
    if (!response.ok) {
      errResponse(res, 502, upstreamErrorMessage(payload, "Portainer stacks failed"));
      return;
    }
    res.status(200).json(payload);
  } catch (error) {
    errResponse(res, 502, `Portainer stacks failed: ${error.message}`);
  }
});

app.get("/api/portainer/containers", requireAuth, async (_req, res) => {
  try {
    const response = await withTimeout(`${PORTAINER_URL}/api/endpoints/${PORTAINER_ENDPOINT_ID}/docker/containers/json?all=1`, {
      headers: portainerHeaders(),
    });
    const payload = await response.json().catch(() => []);
    if (!response.ok) {
      errResponse(res, 502, upstreamErrorMessage(payload, "Portainer containers failed"));
      return;
    }
    res.status(200).json(payload);
  } catch (error) {
    errResponse(res, 502, `Portainer containers failed: ${error.message}`);
  }
});

app.post("/api/portainer/redeploy/:stackId", requireAuth, async (req, res) => {
  const stackId = Number(req.params.stackId);
  if (!Number.isFinite(stackId)) {
    errResponse(res, 400, "Invalid stack id");
    return;
  }
  const confirmation = String(req.body?.confirmation || "");
  if (confirmation !== "REDEPLOY") {
    errResponse(res, 400, "Missing confirmation token (expected 'REDEPLOY')");
    return;
  }
  const endpointId = Number(req.body?.endpointId || PORTAINER_ENDPOINT_ID);
  try {
    const response = await withTimeout(
      `${PORTAINER_URL}/api/stacks/${stackId}/git/redeploy?endpointId=${endpointId}`,
      {
        method: "PUT",
        headers: { ...portainerHeaders(), "Content-Type": "application/json" },
        body: JSON.stringify({ prune: false }),
      }
    );
    const text = await response.text();
    res.status(response.ok ? 200 : 502).json({
      ok: response.ok,
      stackId,
      endpointId,
      confirmation,
      response: text.slice(0, 500),
    });
  } catch (error) {
    errResponse(res, 502, `Portainer redeploy failed: ${error.message}`);
  }
});

app.get("/api/portainer/logs/:containerId", requireAuth, async (req, res) => {
  const containerId = encodeURIComponent(req.params.containerId);
  try {
    const response = await withTimeout(
      `${PORTAINER_URL}/api/endpoints/${PORTAINER_ENDPOINT_ID}/docker/containers/${containerId}/logs?stdout=1&stderr=1&tail=200`,
      { headers: portainerHeaders() },
      REQUEST_TIMEOUT_MS * 2
    );
    const text = await response.text();
    if (!response.ok) {
      errResponse(res, 502, `Portainer logs failed (status ${response.status})`);
      return;
    }
    res.status(200).json({ containerId: req.params.containerId, logs: text });
  } catch (error) {
    errResponse(res, 502, `Portainer logs failed: ${error.message}`);
  }
});

app.get("/api/litellm/routes", requireAuth, async (_req, res) => {
  const checks = LITELLM_ALIASES.map(async (alias) => {
    try {
      const response = await withTimeout(`${LITELLM_BASE_URL}/v1/chat/completions`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(LITELLM_API_KEY ? { Authorization: `Bearer ${LITELLM_API_KEY}` } : {}),
        },
        body: JSON.stringify({
          model: alias,
          messages: [{ role: "user", content: "ping" }],
          max_tokens: 8,
          stream: false,
        }),
      });
      return { alias, status: response.ok ? "ok" : "degraded", statusCode: response.status };
    } catch (error) {
      return { alias, status: "degraded", reason: error?.name || "error" };
    }
  });
  const results = await Promise.all(checks);
  res.status(200).json({ routes: results });
});

app.get("/api/media/status", requireAuth, async (_req, res) => {
  const sonarrKey = process.env.HOMEPAGE_VAR_SONARR_API_KEY || process.env.SONARR_API_KEY || "";
  const radarrKey = process.env.HOMEPAGE_VAR_RADARR_API_KEY || process.env.RADARR_API_KEY || "";
  const tautulliKey = process.env.HOMEPAGE_VAR_TAUTULLI_API_KEY || process.env.TAUTULLI_API_KEY || "";

  const sonarrUrl = process.env.SONARR_URL || "http://192.168.1.222:8989";
  const radarrUrl = process.env.RADARR_URL || "http://192.168.1.222:7878";
  const tautulliUrl = process.env.TAUTULLI_URL || "http://192.168.1.222:8181";

  const status = {
    sonarrQueue: null,
    radarrQueue: null,
    plexNowPlaying: null,
    notes: [],
  };

  try {
    if (!sonarrKey) {
      status.notes.push("SONARR_API_KEY missing");
    } else {
      const response = await withTimeout(`${sonarrUrl}/api/v3/queue?page=1&pageSize=50`, {
        headers: { "X-Api-Key": sonarrKey },
      });
      const payload = await response.json().catch(() => ({}));
      status.sonarrQueue = extractQueueCount(payload);
    }
  } catch (error) {
    status.notes.push(`sonarr error: ${error.name || "error"}`);
  }

  try {
    if (!radarrKey) {
      status.notes.push("RADARR_API_KEY missing");
    } else {
      const response = await withTimeout(`${radarrUrl}/api/v3/queue?page=1&pageSize=50`, {
        headers: { "X-Api-Key": radarrKey },
      });
      const payload = await response.json().catch(() => ({}));
      status.radarrQueue = extractQueueCount(payload);
    }
  } catch (error) {
    status.notes.push(`radarr error: ${error.name || "error"}`);
  }

  try {
    if (!tautulliKey) {
      status.notes.push("TAUTULLI_API_KEY missing");
    } else {
      const response = await withTimeout(
        `${tautulliUrl}/api/v2?apikey=${encodeURIComponent(tautulliKey)}&cmd=get_activity`
      );
      const payload = await response.json().catch(() => ({}));
      const sessions = payload?.response?.data?.sessions;
      status.plexNowPlaying = Array.isArray(sessions) ? sessions.length : 0;
    }
  } catch (error) {
    status.notes.push(`tautulli error: ${error.name || "error"}`);
  }

  res.status(200).json(status);
});

app.post("/api/kvm/execute", requireAuth, async (req, res) => {
  const target = String(req.body?.target || "kvm-d829");
  const content = String(req.body?.content || "");
  if (!content) {
    errResponse(res, 400, "content is required");
    return;
  }
  const lowered = content.toLowerCase();
  const matched = denylist.find((entry) => lowered.includes(entry));
  if (matched) {
    errResponse(res, 400, `Denied by policy (matched: ${matched})`);
    return;
  }

  try {
    const response = await withTimeout(`${KVM_OPERATOR_URL}/kvm/paste/${encodeURIComponent(target)}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(KVM_OPERATOR_TOKEN ? { Authorization: `Bearer ${KVM_OPERATOR_TOKEN}` } : {}),
      },
      body: JSON.stringify({ content }),
    });
    const payload = await response.json().catch(() => ({}));
    if (response.status === 202) {
      res.status(202).json({
        status: "blocked",
        reason: "approval-required",
        upstream: payload,
      });
      return;
    }
    if (!response.ok) {
      errResponse(res, 502, upstreamErrorMessage(payload, "KVM execution failed"));
      return;
    }
    res.status(200).json(payload);
  } catch (error) {
    errResponse(res, 502, `KVM execution failed: ${error.message}`);
  }
});

app.get("/api/logs/:container", requireAuth, async (req, res) => {
  const container = encodeURIComponent(req.params.container);
  try {
    const response = await withTimeout(
      `${PORTAINER_URL}/api/endpoints/${PORTAINER_ENDPOINT_ID}/docker/containers/${container}/logs?stdout=1&stderr=1&tail=200`,
      { headers: portainerHeaders() },
      REQUEST_TIMEOUT_MS * 2
    );
    const text = await response.text();
    if (!response.ok) {
      errResponse(res, 502, `Log fetch failed (status ${response.status})`);
      return;
    }
    res.status(200).json({ container: req.params.container, logs: text });
  } catch (error) {
    errResponse(res, 502, `Log fetch failed: ${error.message}`);
  }
});

app.get("/api/settings", requireAuth, (_req, res) => {
  const inventory = parseEnvFile(INVENTORY_STORE_FILE);
  const masked = {};
  for (const [key, value] of Object.entries(inventory)) {
    if (/token|key|secret|password/i.test(key)) {
      masked[key] = value ? "***" : "";
    } else {
      masked[key] = value;
    }
  }
  res.status(200).json(masked);
});

app.put("/api/settings", requireAuth, (req, res) => {
  const existing = parseEnvFile(INVENTORY_STORE_FILE);
  const incoming = req.body && typeof req.body === "object" ? req.body : {};
  const blocked = [];
  const normalized = {};
  for (const [key, value] of Object.entries(incoming)) {
    if (!sanitizeInventoryKey(key)) {
      blocked.push(key);
      continue;
    }
    if (/token|key|secret|password/i.test(key)) {
      blocked.push(key);
      continue;
    }
    normalized[key] = String(value);
  }
  const merged = { ...existing, ...normalized };
  const lines = Object.entries(merged).map(([key, value]) => `${key}=${value}`);
  atomicWriteFile(INVENTORY_STORE_FILE, `${lines.join("\n")}\n`);
  res.status(200).json({ ok: true, updated: Object.keys(normalized).length, blocked });
});

function renderSpaHtml() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Chimera Hub</title>
  <style>
    :root {
      --color-bg: #0d0f14;
      --color-surface: rgba(255,255,255,0.05);
      --color-surface-2: rgba(255,255,255,0.08);
      --color-border: rgba(255,255,255,0.12);
      --color-accent-green: #00ff88;
      --color-accent-blue: #00b4ff;
      --color-accent-amber: #ff6b35;
      --color-danger: #ff4d6d;
      --color-text: #e2e8f0;
      --color-muted: #94a3b8;
      --blur-glass: blur(16px);
      --glow-active: 0 0 16px rgba(0,255,136,0.28);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: Inter, Segoe UI, Roboto, Arial, sans-serif;
      color: var(--color-text);
      background:
        radial-gradient(circle at 10% 10%, rgba(0,180,255,0.12), transparent 30%),
        radial-gradient(circle at 90% 90%, rgba(0,255,136,0.09), transparent 35%),
        var(--color-bg);
      min-height: 100vh;
    }
    .shell {
      max-width: 1500px;
      margin: 0 auto;
      padding: 20px;
    }
    .hero {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 14px;
      margin-bottom: 14px;
      padding: 16px 18px;
      border: 1px solid var(--color-border);
      border-radius: 14px;
      background: var(--color-surface);
      backdrop-filter: var(--blur-glass);
    }
    .hero h1 { margin: 0; font-size: 1.2rem; letter-spacing: 0.3px; }
    .hero .meta { color: var(--color-muted); font-size: 0.9rem; }
    .btn {
      border: 1px solid var(--color-border);
      border-radius: 10px;
      background: var(--color-surface-2);
      color: var(--color-text);
      padding: 8px 12px;
      cursor: pointer;
      font-size: 0.9rem;
    }
    .btn:hover { border-color: var(--color-accent-blue); }
    .btn.primary { border-color: var(--color-accent-blue); box-shadow: 0 0 8px rgba(0,180,255,0.35); }
    .btn.danger { border-color: var(--color-danger); color: #ffd6de; }
    .toolbar { display: flex; gap: 8px; align-items: center; }
    .tablist {
      display: grid;
      grid-template-columns: repeat(9, minmax(0, 1fr));
      gap: 8px;
      margin-bottom: 14px;
    }
    .tab {
      border: 1px solid var(--color-border);
      border-radius: 10px;
      background: var(--color-surface);
      color: var(--color-text);
      padding: 10px 8px;
      text-align: center;
      cursor: pointer;
      font-size: 0.82rem;
      backdrop-filter: var(--blur-glass);
    }
    .tab.active {
      border-color: var(--color-accent-green);
      box-shadow: var(--glow-active);
      background: rgba(0,255,136,0.08);
    }
    .panel {
      display: none;
      border: 1px solid var(--color-border);
      border-radius: 14px;
      background: var(--color-surface);
      backdrop-filter: var(--blur-glass);
      padding: 16px;
      margin-bottom: 12px;
    }
    .panel.active { display: block; }
    .grid {
      display: grid;
      gap: 10px;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    }
    .card {
      border: 1px solid var(--color-border);
      border-radius: 12px;
      background: rgba(255,255,255,0.03);
      padding: 12px;
    }
    .muted { color: var(--color-muted); }
    .led {
      width: 10px;
      height: 10px;
      border-radius: 50%;
      display: inline-block;
      margin-right: 6px;
    }
    .led.ok { background: var(--color-accent-green); box-shadow: 0 0 10px rgba(0,255,136,0.4); }
    .led.degraded { background: var(--color-accent-amber); box-shadow: 0 0 10px rgba(255,107,53,0.4); }
    .led.error { background: var(--color-danger); box-shadow: 0 0 10px rgba(255,77,109,0.4); }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.88rem;
    }
    th, td {
      border-bottom: 1px solid var(--color-border);
      padding: 8px;
      vertical-align: top;
      text-align: left;
    }
    th { color: var(--color-muted); font-weight: 600; }
    pre {
      white-space: pre-wrap;
      border: 1px solid var(--color-border);
      border-radius: 10px;
      padding: 10px;
      background: rgba(0,0,0,0.28);
      overflow: auto;
      font-size: 0.82rem;
    }
    textarea, input, select {
      width: 100%;
      border: 1px solid var(--color-border);
      border-radius: 10px;
      background: rgba(0,0,0,0.28);
      color: var(--color-text);
      padding: 10px;
      font: inherit;
    }
    .row { display: grid; grid-template-columns: repeat(2, minmax(0,1fr)); gap: 10px; }
    .tiny { font-size: 0.8rem; }
    .chat-log { min-height: 170px; max-height: 340px; overflow: auto; }
    .bubble { padding: 8px 10px; border-radius: 10px; margin: 8px 0; }
    .bubble.user { background: rgba(0,180,255,0.14); border: 1px solid rgba(0,180,255,0.35); }
    .bubble.assistant { background: rgba(0,255,136,0.1); border: 1px solid rgba(0,255,136,0.3); }
    .route-badge {
      display: inline-block;
      border: 1px solid var(--color-accent-blue);
      border-radius: 100px;
      padding: 3px 8px;
      font-size: 0.76rem;
      color: #c7eeff;
    }
    .pulse {
      width: 11px;
      height: 11px;
      border-radius: 50%;
      background: var(--color-accent-green);
      display: inline-block;
      margin-left: 6px;
      opacity: 0.2;
    }
    .pulse.active { animation: pulse 1s infinite; opacity: 1; }
    @keyframes pulse {
      0% { transform: scale(0.8); opacity: 0.5; }
      50% { transform: scale(1.2); opacity: 1; }
      100% { transform: scale(0.8); opacity: 0.5; }
    }
    details {
      border: 1px solid var(--color-border);
      border-radius: 10px;
      margin-bottom: 8px;
      padding: 8px;
      background: rgba(255,255,255,0.02);
    }
    summary { cursor: pointer; }
    .modal {
      position: fixed;
      inset: 0;
      background: rgba(0,0,0,0.55);
      display: none;
      align-items: center;
      justify-content: center;
      z-index: 20;
    }
    .modal.active { display: flex; }
    .modal-box {
      width: min(560px, 96vw);
      border: 1px solid var(--color-border);
      border-radius: 14px;
      background: rgba(13,15,20,0.95);
      padding: 14px;
    }
    .auth-screen {
      position: fixed;
      inset: 0;
      display: none;
      align-items: center;
      justify-content: center;
      z-index: 30;
      background: rgba(0,0,0,0.68);
    }
    .auth-screen.active { display: flex; }
    .auth-card {
      width: min(420px, 94vw);
      border: 1px solid var(--color-border);
      border-radius: 14px;
      background: rgba(13,15,20,0.98);
      padding: 16px;
    }
    @media (max-width: 1200px) {
      .tablist { grid-template-columns: repeat(3, minmax(0, 1fr)); }
      .row { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <div id="authScreen" class="auth-screen active" aria-modal="true" role="dialog">
    <div class="auth-card">
      <h2>Chimera Hub Login</h2>
      <p class="muted tiny">Use the local admin password configured for chimera-hub.</p>
      <form id="loginForm">
        <input id="loginPassword" type="password" autocomplete="current-password" placeholder="Admin password" aria-label="Admin password" />
        <div style="margin-top:10px;" class="toolbar">
          <button class="btn primary" type="submit">Sign in</button>
          <span id="loginError" class="tiny" style="color:#ffb3c2;"></span>
        </div>
      </form>
    </div>
  </div>

  <div class="shell">
    <header class="hero">
      <div>
        <h1>Chimera Hub — Unified Control Plane</h1>
        <div class="meta">Node B target :3099 · live multi-node control surface</div>
      </div>
      <div class="toolbar">
        <button id="refreshAllBtn" class="btn">Refresh</button>
        <button id="logoutBtn" class="btn danger">Logout</button>
      </div>
    </header>

    <nav id="tablist" class="tablist" role="tablist" aria-label="Chimera Hub Tabs">
      <button class="tab active" role="tab" aria-selected="true" data-tab="dashboard">Dashboard</button>
      <button class="tab" role="tab" aria-selected="false" data-tab="status">Status</button>
      <button class="tab" role="tab" aria-selected="false" data-tab="chat">Chat / Voice</button>
      <button class="tab" role="tab" aria-selected="false" data-tab="install">Install Wizard</button>
      <button class="tab" role="tab" aria-selected="false" data-tab="sherpa">AI Sherpa</button>
      <button class="tab" role="tab" aria-selected="false" data-tab="notepad">Notepad / Planner</button>
      <button class="tab" role="tab" aria-selected="false" data-tab="settings">Settings</button>
      <button class="tab" role="tab" aria-selected="false" data-tab="portainer">Portainer Admin</button>
      <button class="tab" role="tab" aria-selected="false" data-tab="kvm">KVM Operator</button>
    </nav>

    <section id="panel-dashboard" class="panel active" role="tabpanel" aria-label="Dashboard">
      <div class="row">
        <div class="card">
          <h3>Node Health Grid</h3>
          <div id="nodeHealthGrid" class="grid"></div>
        </div>
        <div class="card">
          <h3>Service LEDs</h3>
          <div id="serviceLeds" class="grid"></div>
        </div>
      </div>
      <div class="card" style="margin-top:10px;">
        <h3>Media Widgets</h3>
        <div id="mediaWidgets" class="grid"></div>
      </div>
    </section>

    <section id="panel-status" class="panel" role="tabpanel" aria-label="Status">
      <div class="card">
        <h3>Service Table</h3>
        <table>
          <thead><tr><th>Service</th><th>Status</th><th>HTTP</th><th>Latency</th><th>Reason</th></tr></thead>
          <tbody id="serviceTableBody"></tbody>
        </table>
      </div>
      <div class="card" style="margin-top:10px;">
        <h3>Container Resource Table</h3>
        <table>
          <thead><tr><th>Name</th><th>CPU%</th><th>Mem%</th><th>Mem Usage</th><th>Log Link</th></tr></thead>
          <tbody id="containerMetricsBody"></tbody>
        </table>
      </div>
      <p class="tiny muted">Dozzle: <a href="#" id="dozzleLink" target="_blank" rel="noopener">open</a></p>
    </section>

    <section id="panel-chat" class="panel" role="tabpanel" aria-label="Chat and Voice">
      <div class="row">
        <div class="card">
          <h3>LiteLLM Chat <span id="routeBadge" class="route-badge">route: n/a</span><span id="ttsPulse" class="pulse"></span></h3>
          <div id="chatLog" class="chat-log"></div>
          <div class="row">
            <select id="chatModel" aria-label="Model selector">
              <option>brain-heavy</option>
              <option>brain-vision</option>
              <option>brawn-fast</option>
              <option>brawn-code</option>
              <option>intel-fast</option>
              <option>intel-uncensored</option>
              <option>intel-vision</option>
            </select>
            <button id="chatSendBtn" class="btn primary">Send</button>
          </div>
          <textarea id="chatInput" rows="4" placeholder="Ask Chimera..."></textarea>
        </div>
        <div class="card">
          <h3>Voice Transcribe</h3>
          <textarea id="voiceInput" rows="4" placeholder="Paste transcript payload text"></textarea>
          <div class="toolbar" style="margin-top:8px;">
            <button id="voiceSendBtn" class="btn">Transcribe</button>
          </div>
          <pre id="voiceOut"></pre>
        </div>
      </div>
    </section>

    <section id="panel-install" class="panel" role="tabpanel" aria-label="Install Wizard">
      <div class="card">
        <h3>Node-by-Node Commands</h3>
        <button id="installValidateBtn" class="btn">Run inline validation</button>
        <div id="installValidateOut" class="tiny muted" style="margin:8px 0;"></div>
        <details><summary>Node A (Brain)</summary><pre id="cmdNodeA">curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up</pre><button class="btn copy-btn" data-copy="cmdNodeA">Copy</button></details>
        <details><summary>Node B (Brawn/Unraid)</summary><pre id="cmdNodeB">curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up</pre><button class="btn copy-btn" data-copy="cmdNodeB">Copy</button></details>
        <details><summary>Node C (Intel Arc)</summary><pre id="cmdNodeC">curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up</pre><button class="btn copy-btn" data-copy="cmdNodeC">Copy</button></details>
        <details><summary>Node D (Home Assistant)</summary><pre id="cmdNodeD">sudo apt update && sudo apt install -y tailscale && sudo tailscale up</pre><button class="btn copy-btn" data-copy="cmdNodeD">Copy</button></details>
        <details><summary>Node E (Sentinel)</summary><pre id="cmdNodeE">sudo ufw allow ssh && curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up</pre><button class="btn copy-btn" data-copy="cmdNodeE">Copy</button></details>
      </div>
    </section>

    <section id="panel-sherpa" class="panel" role="tabpanel" aria-label="AI Sherpa">
      <div class="card">
        <h3>AI Sherpa (advisory mode)</h3>
        <p class="tiny muted">Uses the same chat route with an installation-focused prompt wrapper.</p>
        <textarea id="sherpaInput" rows="4" placeholder="Ask for deployment guidance..."></textarea>
        <div class="toolbar" style="margin-top:8px;">
          <button id="sherpaSendBtn" class="btn primary">Ask Sherpa</button>
        </div>
        <pre id="sherpaOut"></pre>
      </div>
    </section>

    <section id="panel-notepad" class="panel" role="tabpanel" aria-label="Notepad">
      <div class="card">
        <h3>Notepad / Planner</h3>
        <textarea id="notepad" rows="14" placeholder="Write planning notes in markdown..."></textarea>
        <div class="toolbar" style="margin-top:8px;">
          <button id="notepadSaveBtn" class="btn">Save locally</button>
          <span id="notepadStatus" class="tiny muted"></span>
        </div>
      </div>
    </section>

    <section id="panel-settings" class="panel" role="tabpanel" aria-label="Settings">
      <div class="card">
        <h3>Inventory Settings</h3>
        <p class="tiny muted">Sensitive keys are masked and blocked from updates.</p>
        <table>
          <thead><tr><th>Key</th><th>Value</th></tr></thead>
          <tbody id="settingsTableBody"></tbody>
        </table>
        <div class="toolbar" style="margin-top:8px;">
          <button id="settingsReloadBtn" class="btn">Reload</button>
          <button id="settingsSaveBtn" class="btn primary">Save updates</button>
          <span id="settingsStatus" class="tiny muted"></span>
        </div>
      </div>
    </section>

    <section id="panel-portainer" class="panel" role="tabpanel" aria-label="Portainer Admin">
      <div class="row">
        <div class="card">
          <h3>Stacks</h3>
          <button id="portainerRefreshBtn" class="btn">Refresh</button>
          <table>
            <thead><tr><th>ID</th><th>Name</th><th>Status</th><th>Action</th></tr></thead>
            <tbody id="stacksTableBody"></tbody>
          </table>
        </div>
        <div class="card">
          <h3>Containers</h3>
          <table>
            <thead><tr><th>Name</th><th>Image</th><th>State</th><th>Logs</th></tr></thead>
            <tbody id="containersTableBody"></tbody>
          </table>
        </div>
      </div>
      <div class="card" style="margin-top:10px;">
        <h3>Container Logs</h3>
        <pre id="portainerLogsOut"></pre>
      </div>
    </section>

    <section id="panel-kvm" class="panel" role="tabpanel" aria-label="KVM Operator">
      <div class="card">
        <h3>KVM Operator Controls</h3>
        <div class="row">
          <div>
            <label class="tiny muted">Target</label>
            <input id="kvmTarget" value="kvm-d829" />
          </div>
          <div>
            <label class="tiny muted">Quick actions</label>
            <div class="toolbar">
              <button class="btn kvm-quick" data-cmd="whoami">whoami</button>
              <button class="btn kvm-quick" data-cmd="uptime">uptime</button>
              <button class="btn kvm-quick" data-cmd="date">date</button>
            </div>
          </div>
        </div>
        <textarea id="kvmContent" rows="4" placeholder="Text to paste via KVM operator"></textarea>
        <div class="toolbar" style="margin-top:8px;">
          <button id="kvmExecuteBtn" class="btn danger">Execute (requires CONFIRM)</button>
        </div>
        <pre id="kvmOut"></pre>
      </div>
    </section>
  </div>

  <div id="redeployModal" class="modal" aria-modal="true" role="dialog">
    <div class="modal-box">
      <h3>Redeploy Stack</h3>
      <p class="tiny muted">Type <b>REDEPLOY</b> to confirm stack redeploy.</p>
      <input id="redeployConfirmInput" placeholder="REDEPLOY" />
      <div class="toolbar" style="margin-top:10px;">
        <button id="redeployConfirmBtn" class="btn danger">Confirm</button>
        <button id="redeployCancelBtn" class="btn">Cancel</button>
      </div>
    </div>
  </div>

  <div id="kvmModal" class="modal" aria-modal="true" role="dialog">
    <div class="modal-box">
      <h3>KVM Execution Confirmation</h3>
      <p class="tiny muted">Type <b>CONFIRM</b> to send command.</p>
      <input id="kvmConfirmInput" placeholder="CONFIRM" />
      <div class="toolbar" style="margin-top:10px;">
        <button id="kvmConfirmBtn" class="btn danger">Run</button>
        <button id="kvmCancelBtn" class="btn">Cancel</button>
      </div>
    </div>
  </div>

  <script>
    (function () {
      const state = {
        token: localStorage.getItem("chimeraHubToken") || "",
        activeTab: "dashboard",
        health: null,
        selectedStackId: null,
      };

      const tabs = ["dashboard","status","chat","install","sherpa","notepad","settings","portainer","kvm"];

      function byId(id) { return document.getElementById(id); }
      function esc(value) {
        return String(value || "")
          .replace(/&/g, "&amp;")
          .replace(/</g, "&lt;")
          .replace(/>/g, "&gt;")
          .replace(/"/g, "&quot;")
          .replace(/'/g, "&#039;");
      }
      function setPulse(active) {
        const pulse = byId("ttsPulse");
        if (!pulse) return;
        pulse.classList.toggle("active", !!active);
      }
      function setAuthUi(isAuthed) {
        byId("authScreen").classList.toggle("active", !isAuthed);
      }
      function activateTab(tab) {
        state.activeTab = tab;
        tabs.forEach(function (name) {
          const btn = document.querySelector('.tab[data-tab="' + name + '"]');
          const panel = byId("panel-" + name);
          if (btn) {
            const isActive = name === tab;
            btn.classList.toggle("active", isActive);
            btn.setAttribute("aria-selected", isActive ? "true" : "false");
          }
          if (panel) panel.classList.toggle("active", name === tab);
        });
      }
      async function api(path, options) {
        const opts = options || {};
        const headers = Object.assign({}, opts.headers || {});
        if (!headers["Content-Type"] && opts.body) headers["Content-Type"] = "application/json";
        if (state.token) headers["Authorization"] = "Bearer " + state.token;
        const res = await fetch(path, Object.assign({}, opts, { headers: headers }));
        let payload = {};
        try { payload = await res.json(); } catch (_e) {}
        if (!res.ok) {
          if (res.status === 401) {
            state.token = "";
            localStorage.removeItem("chimeraHubToken");
            setAuthUi(false);
          }
          const message = payload.error || payload.detail || payload.message || ("HTTP " + res.status);
          const err = new Error(message);
          err.status = res.status;
          err.payload = payload;
          throw err;
        }
        return payload;
      }

      function renderHealth() {
        const grid = byId("nodeHealthGrid");
        const leds = byId("serviceLeds");
        if (!state.health || !Array.isArray(state.health.checks)) {
          grid.innerHTML = '<div class="muted tiny">No health data yet.</div>';
          leds.innerHTML = "";
          return;
        }
        grid.innerHTML = state.health.checks.map(function (check) {
          const statusClass = check.status === "ok" ? "ok" : (check.status === "degraded" ? "degraded" : "error");
          return '<div class="card"><div><span class="led ' + statusClass + '"></span><b>' +
            esc(check.name) + '</b></div><div class="tiny muted">HTTP: ' + esc(check.statusCode || "-") +
            ' · ' + esc(check.latencyMs || "-") + 'ms</div><div class="tiny muted">' +
            esc(check.reason || "") + '</div></div>';
        }).join("");
        leds.innerHTML = state.health.checks.map(function (check) {
          const statusClass = check.status === "ok" ? "ok" : (check.status === "degraded" ? "degraded" : "error");
          return '<div><span class="led ' + statusClass + '"></span>' + esc(check.name) + '</div>';
        }).join("");
      }

      function renderServiceTable() {
        const tbody = byId("serviceTableBody");
        if (!state.health || !Array.isArray(state.health.checks)) {
          tbody.innerHTML = '<tr><td colspan="5" class="muted">No data</td></tr>';
          return;
        }
        tbody.innerHTML = state.health.checks.map(function (check) {
          return "<tr><td>" + esc(check.name) + "</td><td>" + esc(check.status) + "</td><td>" +
            esc(check.statusCode || "-") + "</td><td>" + esc(check.latencyMs || "-") + "</td><td>" +
            esc(check.reason || "") + "</td></tr>";
        }).join("");
      }

      async function loadDashboard() {
        try {
          state.health = await api("/api/health");
          renderHealth();
          renderServiceTable();
        } catch (error) {
          byId("nodeHealthGrid").innerHTML = '<div class="tiny" style="color:#ffb3c2;">' + esc(error.message) + "</div>";
        }
        try {
          const media = await api("/api/media/status");
          byId("mediaWidgets").innerHTML =
            '<div class="card"><b>Sonarr Queue</b><div class="tiny muted">' + esc(media.sonarrQueue) + "</div></div>" +
            '<div class="card"><b>Radarr Queue</b><div class="tiny muted">' + esc(media.radarrQueue) + "</div></div>" +
            '<div class="card"><b>Plex Now Playing</b><div class="tiny muted">' + esc(media.plexNowPlaying) + "</div></div>" +
            '<div class="card"><b>Notes</b><div class="tiny muted">' + esc((media.notes || []).join(", ")) + "</div></div>";
        } catch (error) {
          byId("mediaWidgets").innerHTML = '<div class="tiny" style="color:#ffb3c2;">' + esc(error.message) + "</div>";
        }
      }

      async function loadStatus() {
        const body = byId("containerMetricsBody");
        try {
          const status = await api("/api/status");
          byId("dozzleLink").href = status.dozzle || "#";
          const metrics = Array.isArray(status.containerMetrics) ? status.containerMetrics : [];
          if (!metrics.length) {
            body.innerHTML = '<tr><td colspan="5" class="muted">No metrics available</td></tr>';
            return;
          }
          body.innerHTML = metrics.map(function (row) {
            const logName = (row.name || "").replace(/^\\//, "");
            return "<tr><td>" + esc(row.name) + "</td><td>" + esc(row.cpuPercent) + "</td><td>" +
              esc(row.memoryPercent) + "</td><td>" + esc(row.memoryUsage) + "</td><td>" +
              '<button class="btn tiny log-btn" data-container="' + esc(logName) + '">Logs</button></td></tr>';
          }).join("");
          document.querySelectorAll(".log-btn").forEach(function (btn) {
            btn.addEventListener("click", async function () {
              const container = btn.getAttribute("data-container");
              try {
                const payload = await api("/api/logs/" + encodeURIComponent(container));
                byId("portainerLogsOut").textContent = payload.logs || "";
                activateTab("portainer");
              } catch (error) {
                byId("portainerLogsOut").textContent = error.message;
              }
            });
          });
        } catch (error) {
          body.innerHTML = '<tr><td colspan="5" style="color:#ffb3c2;">' + esc(error.message) + "</td></tr>";
        }
      }

      function appendBubble(logId, kind, text) {
        const log = byId(logId);
        const bubble = document.createElement("div");
        bubble.className = "bubble " + kind;
        bubble.textContent = text;
        log.appendChild(bubble);
        log.scrollTop = log.scrollHeight;
      }

      async function sendChatMessage(inputId, outLogId, modelId, routeBadgeId, promptPrefix) {
        const input = byId(inputId);
        const text = (input.value || "").trim();
        if (!text) return;
        input.value = "";
        appendBubble(outLogId, "user", text);
        setPulse(true);
        try {
          const model = byId(modelId).value;
          const messageText = promptPrefix ? (promptPrefix + "\\n\\n" + text) : text;
          const payload = await api("/api/chat", {
            method: "POST",
            body: JSON.stringify({
              model: model,
              messages: [{ role: "user", content: messageText }],
            }),
          });
          const content =
            payload &&
            payload.raw &&
            payload.raw.choices &&
            payload.raw.choices[0] &&
            payload.raw.choices[0].message &&
            payload.raw.choices[0].message.content
              ? payload.raw.choices[0].message.content
              : JSON.stringify(payload.raw || payload);
          appendBubble(outLogId, "assistant", content);
          if (routeBadgeId) byId(routeBadgeId).textContent = "route: " + (payload.route_used || "n/a");
        } catch (error) {
          appendBubble(outLogId, "assistant", "Error: " + error.message);
        } finally {
          setPulse(false);
        }
      }

      async function loadSettings() {
        const body = byId("settingsTableBody");
        try {
          const settings = await api("/api/settings");
          const keys = Object.keys(settings).sort();
          body.innerHTML = keys.map(function (key) {
            const value = settings[key];
            const isMasked = value === "***";
            return "<tr><td>" + esc(key) + "</td><td><input data-key='" + esc(key) + "' value='" + esc(value) + "'" +
              (isMasked ? " disabled" : "") + " /></td></tr>";
          }).join("");
        } catch (error) {
          body.innerHTML = '<tr><td colspan="2" style="color:#ffb3c2;">' + esc(error.message) + "</td></tr>";
        }
      }

      async function saveSettings() {
        const updates = {};
        document.querySelectorAll("#settingsTableBody input[data-key]").forEach(function (input) {
          if (input.disabled) return;
          updates[input.getAttribute("data-key")] = input.value;
        });
        try {
          const result = await api("/api/settings", {
            method: "PUT",
            body: JSON.stringify(updates),
          });
          byId("settingsStatus").textContent = "updated: " + result.updated + " blocked: " + (result.blocked || []).join(",");
        } catch (error) {
          byId("settingsStatus").textContent = "error: " + error.message;
        }
      }

      async function loadPortainer() {
        const stacksBody = byId("stacksTableBody");
        const containersBody = byId("containersTableBody");
        try {
          const stacks = await api("/api/portainer/stacks");
          stacksBody.innerHTML = (Array.isArray(stacks) ? stacks : []).map(function (stack) {
            return "<tr><td>" + esc(stack.Id) + "</td><td>" + esc(stack.Name) + "</td><td>" + esc(stack.Status) + "</td><td>" +
              '<button class="btn tiny redeploy-btn" data-stack="' + esc(stack.Id) + '">Redeploy</button></td></tr>';
          }).join("");
          document.querySelectorAll(".redeploy-btn").forEach(function (btn) {
            btn.addEventListener("click", function () {
              state.selectedStackId = btn.getAttribute("data-stack");
              byId("redeployConfirmInput").value = "";
              byId("redeployModal").classList.add("active");
            });
          });
        } catch (error) {
          stacksBody.innerHTML = '<tr><td colspan="4" style="color:#ffb3c2;">' + esc(error.message) + "</td></tr>";
        }
        try {
          const containers = await api("/api/portainer/containers");
          containersBody.innerHTML = (Array.isArray(containers) ? containers : []).slice(0, 60).map(function (container) {
            const name = (container.Names && container.Names[0] ? container.Names[0] : "").replace(/^\\//, "");
            return "<tr><td>" + esc(name) + "</td><td>" + esc(container.Image) + "</td><td>" + esc(container.State) + "</td><td>" +
              '<button class="btn tiny portainer-log-btn" data-id="' + esc(container.Id) + '">View</button></td></tr>';
          }).join("");
          document.querySelectorAll(".portainer-log-btn").forEach(function (btn) {
            btn.addEventListener("click", async function () {
              try {
                const payload = await api("/api/portainer/logs/" + encodeURIComponent(btn.getAttribute("data-id")));
                byId("portainerLogsOut").textContent = payload.logs || "";
              } catch (error) {
                byId("portainerLogsOut").textContent = error.message;
              }
            });
          });
        } catch (error) {
          containersBody.innerHTML = '<tr><td colspan="4" style="color:#ffb3c2;">' + esc(error.message) + "</td></tr>";
        }
      }

      async function executeKvm() {
        const target = byId("kvmTarget").value.trim() || "kvm-d829";
        const content = byId("kvmContent").value.trim();
        if (!content) {
          byId("kvmOut").textContent = "No command content provided.";
          return;
        }
        try {
          const payload = await api("/api/kvm/execute", {
            method: "POST",
            body: JSON.stringify({ target: target, content: content }),
          });
          byId("kvmOut").textContent = JSON.stringify(payload, null, 2);
        } catch (error) {
          const extra = error.payload ? "\\n" + JSON.stringify(error.payload, null, 2) : "";
          byId("kvmOut").textContent = error.message + extra;
        }
      }

      function setupWebSocket() {
        try {
          const protocol = location.protocol === "https:" ? "wss://" : "ws://";
          const ws = new WebSocket(protocol + location.host + "/ws/status");
          ws.onmessage = function (event) {
            try {
              const msg = JSON.parse(event.data);
              if (msg && msg.type === "status" && msg.payload) {
                state.health = msg.payload;
                renderHealth();
                renderServiceTable();
              }
            } catch (_err) {}
          };
        } catch (_err) {}
      }

      async function inlineInstallValidation() {
        try {
          const health = await api("/api/health");
          const ok = (health.checks || []).filter(function (check) { return check.status === "ok"; }).length;
          byId("installValidateOut").textContent = "Validation: " + ok + " services healthy out of " + ((health.checks || []).length);
        } catch (error) {
          byId("installValidateOut").textContent = "Validation failed: " + error.message;
        }
      }

      function bindUi() {
        document.querySelectorAll(".tab").forEach(function (tabBtn) {
          tabBtn.addEventListener("click", function () { activateTab(tabBtn.getAttribute("data-tab")); });
        });
        byId("refreshAllBtn").addEventListener("click", function () { refreshAll(); });
        byId("logoutBtn").addEventListener("click", async function () {
          try { await api("/api/auth/logout", { method: "POST" }); } catch (_e) {}
          state.token = "";
          localStorage.removeItem("chimeraHubToken");
          setAuthUi(false);
        });
        byId("chatSendBtn").addEventListener("click", function () { sendChatMessage("chatInput", "chatLog", "chatModel", "routeBadge", ""); });
        byId("voiceSendBtn").addEventListener("click", async function () {
          try {
            const payload = await api("/api/voice/transcribe", {
              method: "POST",
              body: JSON.stringify({ text: byId("voiceInput").value }),
            });
            byId("voiceOut").textContent = JSON.stringify(payload, null, 2);
          } catch (error) {
            byId("voiceOut").textContent = error.message;
          }
        });
        byId("sherpaSendBtn").addEventListener("click", async function () {
          const text = byId("sherpaInput").value.trim();
          if (!text) return;
          byId("sherpaOut").textContent = "Loading...";
          try {
            const payload = await api("/api/chat", {
              method: "POST",
              body: JSON.stringify({
                model: "brain-heavy",
                messages: [
                  {
                    role: "system",
                    content: "You are AI Sherpa. Give concise step-by-step homelab guidance with exact commands."
                  },
                  { role: "user", content: text }
                ]
              })
            });
            const content =
              payload &&
              payload.raw &&
              payload.raw.choices &&
              payload.raw.choices[0] &&
              payload.raw.choices[0].message &&
              payload.raw.choices[0].message.content
                ? payload.raw.choices[0].message.content
                : JSON.stringify(payload.raw || payload, null, 2);
            byId("sherpaOut").textContent = content;
          } catch (error) {
            byId("sherpaOut").textContent = error.message;
          }
        });
        byId("notepadSaveBtn").addEventListener("click", function () {
          localStorage.setItem("chimeraHubNotepad", byId("notepad").value);
          byId("notepadStatus").textContent = "Saved to browser storage.";
        });
        byId("settingsReloadBtn").addEventListener("click", loadSettings);
        byId("settingsSaveBtn").addEventListener("click", saveSettings);
        byId("portainerRefreshBtn").addEventListener("click", loadPortainer);
        byId("installValidateBtn").addEventListener("click", inlineInstallValidation);
        byId("redeployCancelBtn").addEventListener("click", function () { byId("redeployModal").classList.remove("active"); });
        byId("redeployConfirmBtn").addEventListener("click", async function () {
          if (byId("redeployConfirmInput").value.trim() !== "REDEPLOY") return;
          try {
            const payload = await api("/api/portainer/redeploy/" + encodeURIComponent(state.selectedStackId), {
              method: "POST",
              body: JSON.stringify({ endpointId: 3, confirmation: "REDEPLOY" }),
            });
            byId("portainerLogsOut").textContent = JSON.stringify(payload, null, 2);
            byId("redeployModal").classList.remove("active");
            loadPortainer();
          } catch (error) {
            byId("portainerLogsOut").textContent = error.message;
          }
        });
        byId("kvmCancelBtn").addEventListener("click", function () { byId("kvmModal").classList.remove("active"); });
        byId("kvmExecuteBtn").addEventListener("click", function () {
          byId("kvmConfirmInput").value = "";
          byId("kvmModal").classList.add("active");
        });
        byId("kvmConfirmBtn").addEventListener("click", async function () {
          if (byId("kvmConfirmInput").value.trim() !== "CONFIRM") return;
          byId("kvmModal").classList.remove("active");
          await executeKvm();
        });
        document.querySelectorAll(".kvm-quick").forEach(function (btn) {
          btn.addEventListener("click", function () { byId("kvmContent").value = btn.getAttribute("data-cmd"); });
        });
        document.querySelectorAll(".copy-btn").forEach(function (btn) {
          btn.addEventListener("click", async function () {
            const src = byId(btn.getAttribute("data-copy"));
            if (!src) return;
            try {
              await navigator.clipboard.writeText(src.textContent || "");
              btn.textContent = "Copied";
              setTimeout(function () { btn.textContent = "Copy"; }, 1000);
            } catch (_err) {}
          });
        });
        byId("loginForm").addEventListener("submit", async function (event) {
          event.preventDefault();
          byId("loginError").textContent = "";
          try {
            const payload = await fetch("/api/auth/login", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ password: byId("loginPassword").value }),
            }).then(async function (response) {
              const data = await response.json().catch(function () { return {}; });
              if (!response.ok) throw new Error(data.error || "Login failed");
              return data;
            });
            state.token = payload.token || "";
            localStorage.setItem("chimeraHubToken", state.token);
            byId("loginPassword").value = "";
            setAuthUi(true);
            refreshAll();
          } catch (error) {
            byId("loginError").textContent = error.message;
          }
        });
      }

      async function refreshAll() {
        if (!state.token) return;
        await loadDashboard();
        await loadStatus();
        await loadSettings();
        await loadPortainer();
      }

      function bootstrap() {
        bindUi();
        byId("notepad").value = localStorage.getItem("chimeraHubNotepad") || "";
        activateTab("dashboard");
        setAuthUi(!!state.token);
        setupWebSocket();
        if (state.token) {
          refreshAll();
          setInterval(function () {
            if (state.token && state.activeTab === "dashboard") loadDashboard();
          }, 15000);
        }
      }
      bootstrap();
    })();
  </script>
</body>
</html>`;
}

app.get("/", (_req, res) => {
  res.status(200).type("html").send(renderSpaHtml());
});

app.use((err, _req, res, _next) => {
  errResponse(res, 500, err?.message || "Unexpected server error");
});

const server = app.listen(PORT, "0.0.0.0", async () => {
  await ensureAuthFile();
  console.log(`chimera-hub listening on ${PORT} (${os.hostname()})`);
});

const wss = new WebSocket.Server({ server, path: "/ws/status" });

async function buildWsStatusPayload() {
  const healthResponse = await fetch(`http://127.0.0.1:${PORT}/api/health`).catch(() => null);
  if (!healthResponse) return { status: "degraded", reason: "ECONNREFUSED" };
  const payload = await healthResponse.json().catch(() => ({ status: "degraded", reason: "parse-error" }));
  return payload;
}

setInterval(async () => {
  if (wss.clients.size === 0) return;
  const payload = await buildWsStatusPayload();
  const body = JSON.stringify({ type: "status", ts: Date.now(), payload });
  for (const client of wss.clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(body);
    }
  }
}, 10000);
