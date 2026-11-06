'use strict';
// CI only (tests/ci-boot-smoke.sh, third start): a Supervisor that answers.
// Runs as `supervisor` in the boot test's Docker network, from the app image
// itself (node). It serves the app options (FAKE_OPTIONS, deliberately
// without remote_control_session_name and the package lists, so the real
// bashio 0.19.0 in the image meets missing options - n21), Home Assistant
// states for the status line (p18) and the Supervisor parts it reads. Every
// request is logged with whether it carried the token (FAKE_LOG); a request
// without the token gets 401.
const fs = require('node:fs');
const http = require('node:http');

const TOKEN = process.env.FAKE_TOKEN || 'ci-token';
const LOG = process.env.FAKE_LOG || '/tmp/requests.log';
const options = JSON.parse(process.env.FAKE_OPTIONS || '{}');

const ok = (data) => JSON.stringify({ result: 'ok', data });
// The takeover check (cli.js detect) sees only this app: it decides "nothing
// to offer" and removes /data/migration/undecided, so the status line and the
// plugin get set up (n33).
const SELF = 'local_claude_workbench';
const routes = {
  '/addons/self/options/config': () => ok(options),
  '/addons/self/info': () => ok({ slug: SELF, options }),
  '/addons': () => ok({ addons: [{ slug: SELF, name: 'Claude Workbench', state: 'started' }] }),
  // Home Assistant's own API answers with the bare list.
  '/core/api/states': () => JSON.stringify([
    { entity_id: 'binary_sensor.kitchen_smoke', state: 'on',
      attributes: { device_class: 'smoke', friendly_name: 'Kitchen smoke' } },
    { entity_id: 'sensor.door_battery', state: '80',
      attributes: { device_class: 'battery', friendly_name: 'Door' } },
  ]),
  '/core/info': () => ok({ version: '2026.11.0', version_latest: '2026.11.0', update_available: false }),
  '/host/info': () => ok({ disk_total: 100, disk_used: 40 }),
  '/backups': () => ok({ backups: [{ date: new Date().toISOString() }] }),
  '/resolution/info': () => ok({ unhealthy: [], issues: [] }),
};

http.createServer((req, res) => {
  const path = req.url.split('?')[0];
  const bearer = req.headers.authorization === `Bearer ${TOKEN}`;
  const header = req.headers['x-supervisor-token'] === TOKEN;
  const authorized = bearer || header;
  fs.appendFileSync(LOG, `${req.method} ${path} ${authorized ? 'token' : 'no-token'}\n`);
  res.setHeader('content-type', 'application/json');
  if (!authorized) {
    res.writeHead(401);
    res.end(JSON.stringify({ result: 'error', message: 'unauthorized' }));
    return;
  }
  const route = routes[path];
  if (!route) {
    res.writeHead(404);
    res.end(JSON.stringify({ result: 'error', message: `no route for ${path}` }));
    return;
  }
  res.writeHead(200);
  res.end(route());
}).listen(80);
