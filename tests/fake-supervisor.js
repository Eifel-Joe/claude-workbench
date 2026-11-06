'use strict';
// In-process stand-in for the Home Assistant Supervisor API, plus a builder
// for a partial-backup tarball in the format verified on HA-Test (Task 0).
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { spawnSync } = require('node:child_process');

// 0e003122 = first 8 hex of sha1("https://github.com/eifel-joe/claude-workbench"), as the Supervisor names apps.
const SELF_SLUG = '0e003122_claude_workbench';
const OLD_SLUG = 'a1b2c3d4_claude_terminal_pro';

function writeFile(file, content, mode) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
  if (mode) fs.chmodSync(file, mode);
}

function tar(args, cwd) {
  const r = spawnSync('tar', args, { cwd, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`tar ${args.join(' ')}: ${r.stderr}`);
}

// Builds <dir>/backup.tar containing <slug>.tar.gz whose data/ mirrors the old
// app's /data. Returns the path of backup.tar.
// opts.omit: paths relative to data/ deleted before archiving; opts.mtime: Date
// set on the memory file heating.md before archiving.
// opts.extra: { 'path/relative/to/data': content } written before archiving.
function buildBackupFixture(dir, slug = OLD_SLUG, { omit = [], mtime, extra = {} } = {}) {
  const app = path.join(dir, 'app');
  const data = path.join(app, 'data');
  writeFile(path.join(app, 'addon.json'), '{}');
  writeFile(path.join(data, 'home/.claude/projects/-config/memory/MEMORY.md'), '- [Heating](heating.md)\n');
  writeFile(path.join(data, 'home/.claude/projects/-config/memory/heating.md'), 'old memory\n');
  writeFile(path.join(data, 'home/.claude/CLAUDE.md'), 'old global instructions\n');
  writeFile(path.join(data, 'home/.claude/skills/shared/SKILL.md'), 'old skill\n');
  writeFile(path.join(data, 'home/.claude/.credentials.json'), '{"token":"old"}', 0o600);
  writeFile(path.join(data, 'home/.claude.json'), '{"oauthAccount":{"email":"x"}}');
  writeFile(path.join(data, '.config/gh/hosts.yml'), 'github.com:\n  user: old\n');
  writeFile(path.join(data, 'packages/python/venv/lib/python3.12/site-packages/requests-2.32.0.dist-info/METADATA'), '');
  // pip writes REQUESTED for packages installed by name; idna is only a dependency.
  writeFile(path.join(data, 'packages/python/venv/lib/python3.12/site-packages/requests-2.32.0.dist-info/REQUESTED'), '');
  writeFile(path.join(data, 'packages/python/venv/lib/python3.12/site-packages/idna-3.7.dist-info/METADATA'), '');
  writeFile(path.join(data, 'packages/python/venv/lib/python3.12/site-packages/pip-24.0.dist-info/METADATA'), '');
  for (const [rel, content] of Object.entries(extra)) writeFile(path.join(data, rel), content);
  for (const rel of omit) fs.rmSync(path.join(data, rel), { recursive: true, force: true });
  if (mtime) {
    fs.utimesSync(path.join(data, 'home/.claude/projects/-config/memory/heating.md'), mtime, mtime);
  }
  // Mirrors the real layout from Task 0, including the image the app was built
  // from, which the migration must not unpack.
  writeFile(path.join(app, 'image.tar'), 'not a real image');
  tar(['-czf', path.join(dir, `${slug}.tar.gz`), '-C', app, 'addon.json', 'image.tar', 'data'], dir);
  writeFile(path.join(dir, 'backup.json'), '{}');
  tar(['-cf', path.join(dir, 'backup.tar'), '-C', dir, 'backup.json', `${slug}.tar.gz`], dir);
  return path.join(dir, 'backup.tar');
}

// opts: { jobNoReference (done job without slug), apps, oldOptions, ownOptions, backupTar, failBackup (job 2nd poll reports an error), failStop,
//   failDownload, failDelete, failOldOptions, backupSizeMb (size in /backups/bk1/info, default 1),
//   hangOn (URL path that never gets an answer) }
// state: calls, ownOptions, stopped, backups (existing slugs), deletedBackups, jobPolls,
//   oldOptionsPosted (body of the last POST /addons/<old>/options)
function startFakeSupervisor(opts = {}) {
  const state = {
    calls: [],
    ownOptions: { ...(opts.ownOptions || {}) },
    stopped: [],
    backups: [],
    deletedBackups: [],
    oldOptionsPosted: null,
    jobPolls: 0,
  };
  const apps = opts.apps || [
    { slug: SELF_SLUG, name: 'Claude Workbench', version: '3.0.0', state: 'started' },
    { slug: OLD_SLUG, name: 'Claude Terminal Pro', version: '2.0.13', state: 'started' },
  ];
  const ok = (res, data = {}) => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ result: 'ok', data }));
  };
  const err = (res, code, message) => {
    res.writeHead(code, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ result: 'error', message }));
  };
  const server = http.createServer((req, res) => {
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      let json;
      try { json = body ? JSON.parse(body) : undefined; } catch { return err(res, 400, 'bad json'); }
      state.calls.push({ method: req.method, url: req.url, body: json });
      if (opts.hangOn === req.url) return undefined; // never answers
      if (req.headers.authorization !== 'Bearer test-token') return err(res, 401, 'unauthorized');
      const m = `${req.method} ${req.url}`;
      if (m === 'GET /addons') return ok(res, { addons: apps });
      if (m === 'GET /addons/self/info') return ok(res, { slug: SELF_SLUG, options: state.ownOptions });
      if (m === `GET /addons/${OLD_SLUG}/info`) {
        return ok(res, { slug: OLD_SLUG, name: 'Claude Terminal Pro', version: '2.0.13',
          repository: 'a1b2c3d4', url: 'https://github.com/ESJavadex/claude-code-ha',
          options: opts.oldOptions || {} });
      }
      if (m === 'POST /backups/new/partial') {
        if (!json || json.background !== true) return err(res, 400, 'expected background: true');
        state.jobPolls = 0;
        return ok(res, { job_id: 'job1' });
      }
      if (m === 'GET /jobs/job1') {
        state.jobPolls += 1;
        if (state.jobPolls === 1) return ok(res, { done: false, reference: null, errors: [] });
        if (opts.jobNoReference) return ok(res, { done: true, reference: null, errors: [] });
        if (opts.failBackup) return ok(res, { done: true, reference: null, errors: [{ message: 'backup failed' }] });
        if (!state.backups.includes('bk1')) state.backups.push('bk1');
        return ok(res, { done: true, reference: 'bk1', errors: [] });
      }
      if (m === 'GET /backups/bk1/info') {
        if (!state.backups.includes('bk1')) return err(res, 404, 'no such backup');
        return ok(res, { slug: 'bk1', size: opts.backupSizeMb ?? 1 });
      }
      if (m === 'GET /backups/bk1/download') {
        if (!state.backups.includes('bk1')) return err(res, 404, 'no such backup');
        if (opts.failDownload) return err(res, 500, 'download failed');
        if (!opts.backupTar) return err(res, 500, 'no backupTar configured');
        res.writeHead(200, { 'Content-Type': 'application/x-tar' });
        return fs.createReadStream(opts.backupTar).pipe(res);
      }
      if (m === 'DELETE /backups/bk1') {
        if (opts.failDelete) return err(res, 500, 'delete failed');
        state.backups = state.backups.filter((b) => b !== 'bk1');
        state.deletedBackups.push('bk1');
        return ok(res);
      }
      if (m === 'POST /addons/self/options') { state.ownOptions = json.options; return ok(res); }
      if (m === `POST /addons/${OLD_SLUG}/stop`) {
        if (opts.failStop) return err(res, 500, 'stop failed');
        state.stopped.push(OLD_SLUG); return ok(res);
      }
      if (m === `POST /addons/${OLD_SLUG}/options`) {
        if (opts.failOldOptions) return err(res, 400, 'options failed');
        state.oldOptionsPosted = json; return ok(res);
      }
      return err(res, 404, `unexpected ${m}`);
    });
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      resolve({
        url: `http://127.0.0.1:${server.address().port}`,
        state,
        close: () => new Promise((r) => { server.close(r); server.closeAllConnections(); }),
      });
    });
  });
}

module.exports = { buildBackupFixture, startFakeSupervisor, SELF_SLUG, OLD_SLUG };
