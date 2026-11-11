// Revit Hub - Central registry and router for Revit MCP connections
// Deployed to Cloud Run, receives connections from Cowork and routes to Windows machines

'use strict';

const http = require('http');
const crypto = require('crypto');

const PORT = Number(process.env.PORT || 8080);
const HUB_SECRET = process.env.HUB_SECRET || '';  // For admin operations

// In-memory registry (production would use Firestore/Redis)
// device_id -> { tunnelUrl, apiKey, lastSeen, metadata, ownerEmail }
const devices = new Map();

// Email -> device_id mapping for auto-discovery
const emailToDevice = new Map();

// Generate secure tokens
function generateToken(length = 32) {
  return crypto.randomBytes(length).toString('base64url');
}

function timingSafeCompare(a, b) {
  const bufA = Buffer.from(a || '', 'utf8');
  const bufB = Buffer.from(b || '', 'utf8');
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

// Parse JSON body
function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', c => {
      body += c;
      if (body.length > 1024 * 1024) {
        req.destroy();
        reject(new Error('body too large'));
      }
    });
    req.on('end', () => {
      try { resolve(JSON.parse(body)); }
      catch (e) { reject(e); }
    });
  });
}

// Proxy request to device
async function proxyToDevice(device, req, res, body) {
  const url = new URL(device.tunnelUrl);

  const options = {
    hostname: url.hostname,
    port: url.port || 443,
    path: url.pathname,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Accept': req.headers['accept'] || 'application/json',
    },
    timeout: 120000,
  };

  const protocol = url.protocol === 'https:' ? require('https') : require('http');

  const proxyReq = protocol.request(options, (proxyRes) => {
    res.writeHead(proxyRes.statusCode, proxyRes.headers);
    proxyRes.pipe(res);
  });

  proxyReq.on('error', (err) => {
    console.error(`[hub] proxy error to ${device.tunnelUrl}: ${err.message}`);
    res.writeHead(502, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      jsonrpc: '2.0',
      error: { code: -32000, message: 'Device unreachable: ' + err.message }
    }));
  });

  proxyReq.write(JSON.stringify(body));
  proxyReq.end();
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const parts = url.pathname.split('/').filter(Boolean);

  // CORS for Cowork
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    return res.end();
  }

  try {
    // Health check
    if (parts[0] === 'health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ status: 'ok', devices: devices.size }));
    }

    // Register device: POST /register
    // Body: { tunnelUrl, email, metadata? }
    // Returns: { deviceId, apiKey }
    if (parts[0] === 'register' && req.method === 'POST') {
      const body = await parseBody(req);

      if (!body.tunnelUrl) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'tunnelUrl required' }));
      }

      if (!body.email) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'email required' }));
      }

      const email = body.email.toLowerCase().trim();

      // Check if this email already has a device - update it
      let deviceId = emailToDevice.get(email);
      let apiKey;

      if (deviceId && devices.has(deviceId)) {
        const existing = devices.get(deviceId);
        apiKey = existing.apiKey;
        existing.tunnelUrl = body.tunnelUrl;
        existing.lastSeen = Date.now();
        existing.metadata = { ...existing.metadata, ...body.metadata };
        console.log(`[hub] updated device ${deviceId} for ${email}`);
      } else {
        deviceId = generateToken(8);
        apiKey = generateToken(32);

        devices.set(deviceId, {
          tunnelUrl: body.tunnelUrl,
          apiKey,
          lastSeen: Date.now(),
          metadata: body.metadata || {},
          ownerEmail: email,
        });

        emailToDevice.set(email, deviceId);
        console.log(`[hub] registered device ${deviceId} for ${email}`);
      }

      res.writeHead(201, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ deviceId, apiKey, email }));
    }

    // Auto-connect by email: POST /connect
    // Body: JSON-RPC + email field
    // Routes automatically to the user's device
    if (parts[0] === 'connect' && req.method === 'POST') {
      const body = await parseBody(req);
      const email = body._email?.toLowerCase().trim();

      if (!email) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({
          jsonrpc: '2.0',
          id: body.id,
          error: { code: -32602, message: '_email field required' }
        }));
      }

      const deviceId = emailToDevice.get(email);
      if (!deviceId) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({
          jsonrpc: '2.0',
          id: body.id,
          error: {
            code: -32000,
            message: 'No Revit device registered for ' + email + '. Run the installer on your Windows PC first.'
          }
        }));
      }

      const device = devices.get(deviceId);
      if (!device) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({
          jsonrpc: '2.0',
          id: body.id,
          error: { code: -32000, message: 'Device configuration error' }
        }));
      }

      device.lastSeen = Date.now();

      // Forward without the _email field
      const { _email, ...rpcPayload } = body;
      await proxyToDevice(device, req, res, rpcPayload);
      return;
    }

    // Update device: POST /devices/:id/heartbeat
    // Header: Authorization: Bearer <apiKey>
    if (parts[0] === 'devices' && parts[2] === 'heartbeat' && req.method === 'POST') {
      const deviceId = parts[1];
      const device = devices.get(deviceId);

      if (!device) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'device not found' }));
      }

      const auth = (req.headers['authorization'] || '').replace(/^Bearer\s+/i, '');
      if (!timingSafeCompare(auth, device.apiKey)) {
        res.writeHead(401, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'unauthorized' }));
      }

      const body = await parseBody(req).catch(() => ({}));
      device.lastSeen = Date.now();
      if (body.tunnelUrl) device.tunnelUrl = body.tunnelUrl;
      if (body.metadata) Object.assign(device.metadata, body.metadata);

      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ status: 'ok' }));
    }

    // List devices (admin): GET /admin/devices
    // Header: Authorization: Bearer <HUB_SECRET>
    if (parts[0] === 'admin' && parts[1] === 'devices' && req.method === 'GET') {
      const auth = (req.headers['authorization'] || '').replace(/^Bearer\s+/i, '');
      if (!HUB_SECRET || !timingSafeCompare(auth, HUB_SECRET)) {
        res.writeHead(401, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'unauthorized' }));
      }

      const list = [];
      for (const [id, d] of devices) {
        list.push({
          deviceId: id,
          tunnelUrl: d.tunnelUrl,
          lastSeen: d.lastSeen,
          metadata: d.metadata,
        });
      }

      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ devices: list }));
    }

    // MCP proxy: POST /mcp/:deviceId/:apiKey
    // This is what Cowork connects to
    if (parts[0] === 'mcp' && req.method === 'POST') {
      const deviceId = parts[1];
      const providedKey = parts[2];

      if (!deviceId || !providedKey) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'deviceId and apiKey required in path' }));
      }

      const device = devices.get(deviceId);
      if (!device) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'device not found' }));
      }

      if (!timingSafeCompare(providedKey, device.apiKey)) {
        // Return 401 WITHOUT WWW-Authenticate to avoid OAuth flow (gotcha #12)
        res.writeHead(401, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'unauthorized' }));
      }

      // Update last seen
      device.lastSeen = Date.now();

      // Parse and proxy
      const body = await parseBody(req);
      await proxyToDevice(device, req, res, body);
      return;
    }

    // Not found
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'not found' }));

  } catch (err) {
    console.error('[hub] error:', err);
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: err.message }));
  }
});

server.listen(PORT, () => {
  console.log(`[hub] Revit Hub listening on port ${PORT}`);
});
