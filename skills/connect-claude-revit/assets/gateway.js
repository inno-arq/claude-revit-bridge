// gateway.js - puente HTTP stateless -> MCP stdio del plugin revit-mcp
//
// Disenado contra los gotchas #11, #12 y #13 del runbook connect-claude-revit:
//   #11 stateless de verdad: un solo proceso hijo, sin Mcp-Session-Id.
//   #12 el 401 va PELADO: sin WWW-Authenticate, o el conector se va a OAuth y falla.
//   #13 el token viaja en la RUTA (/mcp/<token>), porque los encabezados
//       personalizados requieren aprobacion de Anthropic.
//
// Env: MCP_TOKEN (obligatorio), PORT (8000), RPC_TIMEOUT_MS (120000),
//      MCP_COMMAND / MCP_ARGS (opcional; por defecto se leen del config de Claude Desktop).

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');

const TOKEN = process.env.MCP_TOKEN || '';
const PORT = Number(process.env.PORT || 8000);
const RPC_TIMEOUT_MS = Number(process.env.RPC_TIMEOUT_MS || 120000);

if (!TOKEN || TOKEN.length < 20) {
  console.error('[gateway] falta MCP_TOKEN (o es demasiado corto). Abortando.');
  process.exit(1);
}

// --- de donde sale el comando del server MCP ------------------------------

function claudeConfigPaths() {
  const out = [];
  const local = process.env.LOCALAPPDATA;
  if (local) {
    const pkgs = path.join(local, 'Packages');
    try {
      for (const d of fs.readdirSync(pkgs)) {
        if (d.startsWith('Claude_')) {
          out.push(path.join(pkgs, d, 'LocalCache', 'Roaming', 'Claude', 'claude_desktop_config.json'));
        }
      }
    } catch (_) { /* sin paquetes MSIX */ }
  }
  if (process.env.APPDATA) {
    out.push(path.join(process.env.APPDATA, 'Claude', 'claude_desktop_config.json'));
  }
  return out;
}

function resolveServerCmd() {
  if (process.env.MCP_COMMAND) {
    return { command: process.env.MCP_COMMAND, args: JSON.parse(process.env.MCP_ARGS || '[]') };
  }
  for (const p of claudeConfigPaths()) {
    try {
      const cfg = JSON.parse(fs.readFileSync(p, 'utf8'));
      const s = cfg && cfg.mcpServers && cfg.mcpServers['revit-mcp'];
      if (s && s.command) {
        console.error('[gateway] comando tomado de ' + p);
        return { command: s.command, args: s.args || [] };
      }
    } catch (_) { /* siguiente candidato */ }
  }
  throw new Error('no encontre el bloque mcpServers."revit-mcp" en ningun claude_desktop_config.json');
}

// --- proceso hijo y multiplexado JSON-RPC ---------------------------------

let child = null;
let nextId = 1;
const pending = new Map();   // id interno -> {resolve, timer}
let ready = null;            // promesa de initialize

function startChild() {
  const { command, args } = resolveServerCmd();
  console.error('[gateway] lanzando: ' + command + ' ' + args.join(' '));
  child = spawn(command, args, { stdio: ['pipe', 'pipe', 'inherit'] });

  let buf = '';
  child.stdout.on('data', (chunk) => {
    buf += chunk.toString('utf8');
    let nl;
    while ((nl = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, nl).trim();
      buf = buf.slice(nl + 1);
      if (!line) continue;
      let msg;
      try { msg = JSON.parse(line); } catch (_) { continue; }
      if (msg.id !== undefined && pending.has(msg.id)) {
        const { resolve, timer } = pending.get(msg.id);
        clearTimeout(timer);
        pending.delete(msg.id);
        resolve(msg);
      }
    }
  });

  child.on('exit', (code) => {
    console.error('[gateway] el server MCP salio con codigo ' + code + '; relanzando en 2s');
    for (const { resolve, timer } of pending.values()) {
      clearTimeout(timer);
      resolve({ jsonrpc: '2.0', error: { code: -32000, message: 'server MCP reiniciando' } });
    }
    pending.clear();
    child = null;
    setTimeout(() => { ready = boot(); }, 2000);
  });
}

function rpc(payload) {
  return new Promise((resolve) => {
    const internalId = nextId++;
    const timer = setTimeout(() => {
      pending.delete(internalId);
      resolve({ jsonrpc: '2.0', id: payload.id, error: { code: -32001, message: 'timeout esperando al server MCP' } });
    }, RPC_TIMEOUT_MS);
    pending.set(internalId, { resolve, timer });
    child.stdin.write(JSON.stringify(Object.assign({}, payload, { id: internalId })) + '\n');
  });
}

function notify(payload) {
  child.stdin.write(JSON.stringify(payload) + '\n');
}

async function boot() {
  startChild();
  const res = await rpc({
    jsonrpc: '2.0',
    method: 'initialize',
    params: {
      protocolVersion: '2025-06-18',
      capabilities: {},
      clientInfo: { name: 'revit-gateway', version: '1.0.0' }
    }
  });
  notify({ jsonrpc: '2.0', method: 'notifications/initialized' });
  console.error('[gateway] initialize ok: ' + JSON.stringify(res.result && res.result.serverInfo || {}));
}

// --- HTTP ------------------------------------------------------------------

function tokenOk(given) {
  const a = Buffer.from(given || '', 'utf8');
  const b = Buffer.from(TOKEN, 'utf8');
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

// 401 PELADO: ni WWW-Authenticate ni pistas de OAuth (gotcha #12).
function unauthorized(res) {
  res.writeHead(401, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'unauthorized' }));
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const parts = url.pathname.split('/').filter(Boolean);   // ['mcp', '<token>']

  if (parts[0] !== 'mcp') {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ error: 'not found' }));
  }
  if (!tokenOk(parts[1])) return unauthorized(res);
  if (req.method !== 'POST') {
    res.writeHead(405, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ error: 'method not allowed' }));
  }

  let body = '';
  req.on('data', (c) => {
    body += c;
    if (body.length > 8 * 1024 * 1024) req.destroy();
  });
  req.on('end', async () => {
    let payload;
    try { payload = JSON.parse(body); } catch (_) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'parse error' } }));
    }
    try {
      await ready;
      if (payload.id === undefined) {          // notificacion: no espera respuesta
        notify(payload);
        res.writeHead(202, { 'Content-Type': 'application/json' });
        return res.end('{}');
      }
      const out = await rpc(payload);
      out.id = payload.id;                     // devolver el id del cliente, no el interno
      const sse = /text\/event-stream/i.test(req.headers['accept'] || '');
      res.writeHead(200, sse
        ? { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', 'Connection': 'keep-alive' }
        : { 'Content-Type': 'application/json' });
      res.end(sse ? ('event: message\ndata: ' + JSON.stringify(out) + '\n\n') : JSON.stringify(out));
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ jsonrpc: '2.0', id: payload.id || null, error: { code: -32000, message: String(err && err.message || err) } }));
    }
  });
});

ready = boot();
server.listen(PORT, '127.0.0.1', () => {
  console.error('[gateway] escuchando en http://127.0.0.1:' + PORT + '/mcp/<token>');
});
