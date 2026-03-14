/**
 * Shared HTTP utility functions used across homelab Node.js services.
 *
 * Consumed by:
 *   - deploy-gui/deploy-gui.js
 *   - node-a-command-center/node-a-command-center.js
 *   - node-e-sentinel/node-e-sentinel.js
 */

'use strict';

/**
 * Escape special HTML characters to prevent XSS.
 *
 * @param {*} value  Any value; coerced to string before escaping.
 * @returns {string} HTML-safe string.
 */
function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

/**
 * Write a JSON response to an HTTP response object.
 *
 * @param {import('http').ServerResponse} res      Response object.
 * @param {number}                        status   HTTP status code.
 * @param {*}                             payload  Value to serialise as JSON.
 * @param {boolean}                       [addCors=false]  Add CORS header when true.
 */
function sendJson(res, status, payload, addCors = false) {
  const body = JSON.stringify(payload);
  const headers = {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  };
  if (addCors) headers['Access-Control-Allow-Origin'] = '*';
  res.writeHead(status, headers);
  res.end(body);
}

/**
 * Buffer the request body and resolve with its UTF-8 string.
 *
 * @param {import('http').IncomingMessage} req           Incoming request.
 * @param {number}                         maxBodyBytes  Maximum allowed body size in bytes.
 * @returns {Promise<string>}
 */
function readBody(req, maxBodyBytes) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    req.on('data', (chunk) => {
      total += chunk.length;
      if (total > maxBodyBytes) {
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

/**
 * Fetch a URL using the global `fetch` API with an abort-controller timeout.
 *
 * Note: requires Node.js 18+ (built-in fetch).  For environments that use
 * the legacy http/https modules see fetchUrl() in deploy-gui.js.
 *
 * @param {string} url                  Target URL.
 * @param {RequestInit} [options={}]    Fetch options.
 * @param {number}      timeoutMs       Abort timeout in milliseconds.
 * @returns {Promise<Response>}
 */
async function fetchWithTimeout(url, options = {}, timeoutMs) {
  const controller = new AbortController();
  const tid = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(tid);
  }
}

/**
 * Check whether a service URL is reachable and return a status object.
 *
 * Uses the global `fetch` API (Node.js 18+).
 *
 * @param {{ key: string, label: string, url: string }} service   Service descriptor.
 * @param {number} timeoutMs  Per-request timeout in milliseconds.
 * @returns {Promise<{key: string, label: string, url: string, ok: boolean, status: number, latencyMs: number, error?: string}>}
 */
async function checkService(service, timeoutMs) {
  const start = Date.now();
  try {
    const response = await fetchWithTimeout(service.url, {}, timeoutMs);
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

module.exports = { escapeHtml, sendJson, readBody, fetchWithTimeout, checkService };
