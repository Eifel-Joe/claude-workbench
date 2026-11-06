'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync, execFile } = require('node:child_process');
const { buildBackupFixture, startFakeSupervisor, SELF_SLUG, OLD_SLUG } = require('./fake-supervisor');

const MOD = path.join(__dirname, '..', 'claude-workbench', 'scripts', 'app-migration');

// Every fixture directory is removed once the file's tests have run; they
// used to pile up in the system temp directory.
const tmpDirs = [];
function tmp() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mig-'));
  tmpDirs.push(dir);
  return dir;
}
test.after(() => {
  for (const dir of tmpDirs) fs.rmSync(dir, { recursive: true, force: true });
});

test('fixture: backup.tar holds the old app archive with data/', () => {
  const dir = tmp();
  const tarPath = buildBackupFixture(dir);
  const outer = spawnSync('tar', ['-tf', tarPath], { encoding: 'utf8' }).stdout;
  assert.match(outer, new RegExp(`${OLD_SLUG}\\.tar\\.gz`));
  const inner = spawnSync('tar', ['-tzf', path.join(dir, `${OLD_SLUG}.tar.gz`)], { encoding: 'utf8' }).stdout;
  assert.match(inner, /^data\/home\/\.claude\/CLAUDE\.md$/m);
  assert.match(inner, /^image\.tar$/m);
});

const { migrationPaths } = require(path.join(MOD, 'paths'));
const { createClient } = require(path.join(MOD, 'supervisor'));

test('paths: everything lives under MIGRATION_DATA_ROOT', () => {
  const p = migrationPaths({ MIGRATION_DATA_ROOT: '/x' });
  assert.equal(p.home, path.join('/x', 'home'));
  assert.equal(p.offer, path.join('/x', 'migration', 'offer.json'));
  assert.equal(p.state, path.join('/x', 'migration', 'state'));
  assert.equal(p.work, path.join('/x', 'migration', 'work'));
  assert.equal(p.replaced, path.join('/x', 'migration', 'replaced'));
});

test('client: get/post return data, backup job flow, download writes the file, errors throw', async () => {
  const dir = tmp();
  const sup = await startFakeSupervisor({ backupTar: buildBackupFixture(dir) });
  try {
    const client = createClient({ baseUrl: sup.url, token: 'test-token' });
    assert.equal((await client.get('/addons/self/info')).slug, SELF_SLUG);
    assert.deepEqual(await client.post('/backups/new/partial', { background: true }), { job_id: 'job1' });
    assert.deepEqual(sup.state.calls.at(-1).body, { background: true });
    assert.equal((await client.get('/jobs/job1')).done, false);
    const job = await client.get('/jobs/job1');
    assert.equal(job.done, true);
    assert.equal(job.reference, 'bk1');
    const out = path.join(dir, 'dl.tar');
    await client.download('/backups/bk1/download', out);
    assert.deepEqual(fs.readFileSync(out), fs.readFileSync(path.join(dir, 'backup.tar')));
    await assert.rejects(client.get('/nope'), /404/);
    await assert.rejects(createClient({ baseUrl: sup.url, token: 'bad' }).get('/addons'), /401/);
  } finally { await sup.close(); }
});

test("client: download before the backup exists fails with Supervisor's message", async () => {
  const dir = tmp();
  const sup = await startFakeSupervisor({ backupTar: buildBackupFixture(dir) });
  try {
    const client = createClient({ baseUrl: sup.url, token: 'test-token' });
    await assert.rejects(client.download('/backups/bk1/download', path.join(dir, 'x.tar')), /404 no such backup/);
  } finally { await sup.close(); }
});

test('client: network errors name the request', async () => {
  await assert.rejects(
    createClient({ baseUrl: 'http://127.0.0.1:9', token: 'x' }).get('/addons'),
    /GET \/addons -> /);
});

test('client: timeoutMs aborts a request that never gets an answer, naming it', async () => {
  const sup = await startFakeSupervisor({ hangOn: '/addons' });
  try {
    const started = Date.now();
    await assert.rejects(
      createClient({ baseUrl: sup.url, token: 'test-token', timeoutMs: 200 }).get('/addons'),
      /^Error: GET \/addons -> /);
    assert.ok(Date.now() - started < 3000, 'request was not aborted');
  } finally { await sup.close(); }
});

const { detect } = require(path.join(MOD, 'detect'));

async function withSupervisor(opts, fn) {
  const dir = tmp();
  const backupTar = buildBackupFixture(dir, OLD_SLUG, opts.fixture);
  const sup = await startFakeSupervisor({ backupTar, ...opts });
  const p = migrationPaths({ MIGRATION_DATA_ROOT: path.join(dir, 'data') });
  fs.mkdirSync(path.join(p.home, '.claude', 'skills'), { recursive: true }); // what init_environment creates
  try { return await fn(createClient({ baseUrl: sup.url, token: 'test-token' }), p, sup); }
  finally { await sup.close(); }
}

const OLD_OPTIONS = {
  auto_launch_claude: false, dangerously_skip_permissions: true, tmux_mouse: false,
  use_persistent_claude: false, auto_update_claude_on_start: false,
  persistent_apk_packages: ['htop', ' '], persistent_pip_packages: ['httpx'],
};

test('detect: offers the old app with its packages and settings', async () => {
  await withSupervisor({ oldOptions: OLD_OPTIONS }, async (client, p) => {
    const r = await detect(client, p);
    assert.equal(r.offered, true);
    const offer = JSON.parse(fs.readFileSync(p.offer, 'utf8'));
    assert.equal(offer.slug, OLD_SLUG);
    assert.equal(offer.version, '2.0.13');
    assert.equal(offer.repository, 'https://github.com/ESJavadex/claude-code-ha');
    assert.deepEqual(offer.apk, ['htop']);
    assert.deepEqual(offer.pip, ['httpx']);
    assert.deepEqual(offer.settings, { auto_launch_claude: false, dangerously_skip_permissions: true, tmux_mouse: false });
  });
});

// n31: ESJavadex's app has statusline and home_assistant_plugin under our
// names; its Remote Control switch is enable_remote_control, and it names the
// session "Home Assistant".
const ESJ_OPTIONS = {
  auto_launch_claude: true, tmux_mouse: false, dangerously_skip_permissions: false,
  enable_remote_control: true, statusline: ['alerts', '---', 'CO2=sensor.co2'], home_assistant_plugin: false,
  persistent_apk_packages: [], persistent_pip_packages: [],
};

test('detect: carries the status line, the plugin switch and Remote Control over from ESJavadex\'s app', async () => {
  await withSupervisor({ oldOptions: ESJ_OPTIONS }, async (client, p) => {
    const { offer } = await detect(client, p);
    assert.deepEqual(offer.settings, {
      auto_launch_claude: true, dangerously_skip_permissions: false, tmux_mouse: false,
      statusline: ['alerts', '---', 'CO2=sensor.co2'], home_assistant_plugin: false,
      remote_control: true, remote_control_session_name: 'Home Assistant',
    });
  });
});

test('detect: enable_remote_control off becomes remote_control off, without a name', async () => {
  await withSupervisor({ oldOptions: { ...ESJ_OPTIONS, enable_remote_control: false } }, async (client, p) => {
    const { offer } = await detect(client, p);
    assert.equal(offer.settings.remote_control, false);
    assert.equal('remote_control_session_name' in offer.settings, false);
    assert.equal('enable_remote_control' in offer.settings, false);
  });
});

test('detect: a null option of the old app is left out, not carried over', async () => {
  await withSupervisor({ oldOptions: { ...ESJ_OPTIONS, statusline: null } }, async (client, p) => {
    const { offer } = await detect(client, p);
    assert.equal('statusline' in offer.settings, false);
  });
});

test('detect: an old app with remote_control keeps it, enable_remote_control is ignored', async () => {
  const oldOptions = { ...ESJ_OPTIONS, remote_control: false, remote_control_session_name: 'Pi', enable_remote_control: true };
  await withSupervisor({ oldOptions }, async (client, p) => {
    const { offer } = await detect(client, p);
    assert.equal(offer.settings.remote_control, false);
    assert.equal(offer.settings.remote_control_session_name, 'Pi');
    assert.equal('enable_remote_control' in offer.settings, false);
  });
});

test('apply: the carried-over status line and plugin switch land in this app\'s options', async () => {
  const { result, sup } = await detectThenApply({ oldOptions: ESJ_OPTIONS, ownOptions: { statusline: [], home_assistant_plugin: true } }, ['settings']);
  assert.equal(result.results.settings, 'ok');
  assert.deepEqual(sup.state.ownOptions.statusline, ['alerts', '---', 'CO2=sensor.co2']);
  assert.equal(sup.state.ownOptions.home_assistant_plugin, false);
  assert.equal(sup.state.ownOptions.remote_control, true);
  assert.equal(sup.state.ownOptions.remote_control_session_name, 'Home Assistant');
  assert.equal('enable_remote_control' in sup.state.ownOptions, false);
});

test('detect: no offer without another Claude Terminal Pro app', async () => {
  const apps = [{ slug: SELF_SLUG, state: 'started' }, { slug: 'core_samba', state: 'started' }];
  await withSupervisor({ apps }, async (client, p) => {
    assert.deepEqual(await detect(client, p), { offered: false, reason: 'no-old-app' });
    assert.equal(fs.existsSync(p.offer), false);
  });
});

test('detect: no offer when this app already has Claude data', async () => {
  await withSupervisor({}, async (client, p) => {
    fs.mkdirSync(path.join(p.home, '.claude', 'projects', '-config'), { recursive: true });
    assert.equal((await detect(client, p)).reason, 'own-data');
  });
  await withSupervisor({}, async (client, p) => {
    fs.writeFileSync(path.join(p.home, '.claude', '.credentials.json'), '{}');
    assert.equal((await detect(client, p)).reason, 'own-data');
  });
});

test('detect: no offer once done or declined', async () => {
  for (const s of ['done', 'never']) {
    await withSupervisor({}, async (client, p) => {
      fs.mkdirSync(p.dir, { recursive: true });
      fs.writeFileSync(p.state, `${s}\n`);
      assert.equal((await detect(client, p)).reason, 'state');
    });
  }
});

test('detect: removes a stale offer when nothing is offered', async () => {
  const stale = (p) => { fs.mkdirSync(p.dir, { recursive: true }); fs.writeFileSync(p.offer, '{}'); };
  await withSupervisor({}, async (client, p) => {
    fs.mkdirSync(path.join(p.home, '.claude'), { recursive: true });
    fs.writeFileSync(path.join(p.home, '.claude', '.credentials.json'), '{}');
    stale(p);
    assert.equal((await detect(client, p)).reason, 'own-data');
    assert.equal(fs.existsSync(p.offer), false);
  });
  const apps = [{ slug: SELF_SLUG, state: 'started' }];
  await withSupervisor({ apps }, async (client, p) => {
    stale(p);
    assert.equal((await detect(client, p)).reason, 'no-old-app');
    assert.equal(fs.existsSync(p.offer), false);
  });
  await withSupervisor({}, async (client, p) => {
    stale(p);
    fs.writeFileSync(p.state, 'never\n');
    assert.equal((await detect(client, p)).reason, 'state');
    assert.equal(fs.existsSync(p.offer), false);
  });
});

test('detect: removes a work dir left behind by an interrupted apply', async () => {
  await withSupervisor({}, async (client, p) => {
    const leftover = path.join(p.work, 'app', 'data', 'home', '.claude', '.credentials.json');
    fs.mkdirSync(path.dirname(leftover), { recursive: true });
    fs.writeFileSync(leftover, '{"token":"old"}');
    fs.writeFileSync(path.join(p.home, '.claude', '.credentials.json'), '{}');
    assert.equal((await detect(client, p)).reason, 'own-data');
    assert.equal(fs.existsSync(p.work), false);
  });
});

test('detect: prefers a running old app over a stopped one', async () => {
  const apps = [
    { slug: SELF_SLUG, state: 'started' },
    { slug: 'ffff0000_claude_terminal_pro', state: 'stopped' },
    { slug: OLD_SLUG, state: 'started' },
  ];
  await withSupervisor({ apps }, async (client, p) => {
    assert.equal((await detect(client, p)).offer.slug, OLD_SLUG);
  });
});

// The renamed app (3.0.0) still takes over from *_claude_terminal_pro, but a
// second Claude Workbench is never a source, even while it runs.
test('detect: never offers another Claude Workbench as the source', async () => {
  const apps = [
    { slug: SELF_SLUG, state: 'started' },
    { slug: 'ffff0000_claude_workbench', state: 'started' },
    { slug: OLD_SLUG, state: 'stopped' },
  ];
  await withSupervisor({ apps }, async (client, p) => {
    assert.equal((await detect(client, p)).offer.slug, OLD_SLUG);
  });
});

// n33: run.sh creates <dir>/undecided before `cli.js detect`; detect removes it
// once it has decided (offer or nothing to offer). While it lies there, the
// status line and the plugin leave ~/.claude alone, so a takeover offer that
// only comes on a later start still finds the old files missing here.
// Async: the fake Supervisor runs in this process and must keep answering.
function runCliDetect(p, baseUrl) {
  return new Promise((resolve) => {
    execFile(process.execPath, [path.join(MOD, 'cli.js'), 'detect'], {
      env: { ...process.env, MIGRATION_DATA_ROOT: p.dataRoot, SUPERVISOR_API: baseUrl, SUPERVISOR_TOKEN: 'test-token' },
    }, (err, stdout) => resolve(stdout));
  });
}

test('paths: the undecided marker sits next to the offer', () => {
  const p = migrationPaths({ MIGRATION_DATA_ROOT: '/x' });
  assert.equal(p.undecided, path.join('/x', 'migration', 'undecided'));
});

test('cli detect: a decision removes the undecided marker, offer or not', async () => {
  for (const apps of [undefined, [{ slug: SELF_SLUG, state: 'started' }]]) {
    await withSupervisor({ apps, oldOptions: OLD_OPTIONS }, async (client, p, sup) => {
      fs.mkdirSync(p.dir, { recursive: true });
      fs.writeFileSync(p.undecided, '');
      const out = await runCliDetect(p, sup.url);
      assert.equal(fs.existsSync(p.undecided), false, out);
    });
  }
});

test('cli detect: a failed detection leaves the undecided marker', async () => {
  await withSupervisor({}, async (client, p) => {
    fs.mkdirSync(p.dir, { recursive: true });
    fs.writeFileSync(p.undecided, '');
    const out = await runCliDetect(p, 'http://127.0.0.1:1');
    assert.match(out, /WARNING: App migration: detection failed/);
    assert.match(out, /status line and Home Assistant plugin wait for the next start/);
    assert.equal(fs.existsSync(p.undecided), true);
  });
});

const { apply } = require(path.join(MOD, 'apply'));
const quiet = () => {}; // keeps apply's progress output out of the test report

async function detectThenApply(opts, selected, deps = {}) {
  return withSupervisor({ oldOptions: OLD_OPTIONS, ...opts }, async (client, p, sup) => {
    const { offer } = await detect(client, p);
    const result = await apply(client, p, offer, selected,
      { today: '2026-10-06', pollMs: 1, log: quiet, persistInstall: deps.persistInstall || 'false-bin', ...deps });
    return { result, p, sup };
  });
}

test('apply: creates a named partial backup of only the old app', async () => {
  const { sup } = await detectThenApply({}, []);
  const call = sup.state.calls.find((c) => c.url === '/backups/new/partial');
  assert.deepEqual(call.body, {
    name: 'Claude Workbench – Übernahme 2026-10-06', addons: [OLD_SLUG], homeassistant: false, background: true,
  });
});

test('apply: reports progress for backup, download, unpack and packages', async () => {
  const lines = [];
  const fake = fakePersistInstall(tmp());
  await detectThenApply({}, ['claude', 'packages'],
    { ...fake.deps, log: (l) => lines.push(l), progressEveryMs: 0 });
  const text = lines.join('\n');
  assert.match(text, /backup/i);
  assert.match(text, /Still creating the backup.* \d+ s/);
  assert.match(text, /download/i);
  assert.match(text, /unpack/i);
  assert.match(text, /install.*htop/i);
});

test('apply: Claude data without the login file', async () => {
  const { result, p } = await detectThenApply({}, ['claude']);
  assert.equal(result.results.claude, 'ok');
  assert.equal(fs.readFileSync(path.join(p.home, '.claude/projects/-config/memory/heating.md'), 'utf8'), 'old memory\n');
  assert.equal(fs.readFileSync(path.join(p.home, '.claude/CLAUDE.md'), 'utf8'), 'old global instructions\n');
  assert.ok(fs.existsSync(path.join(p.home, '.claude.json')));
  assert.equal(fs.existsSync(path.join(p.home, '.claude/.credentials.json')), false);
});

test('apply: login and gh only when selected', async () => {
  const { result, p } = await detectThenApply({}, ['login', 'gh']);
  assert.equal(result.results.login, 'ok');
  assert.equal(result.results.gh, 'ok');
  assert.equal(fs.readFileSync(path.join(p.home, '.claude/.credentials.json'), 'utf8'), '{"token":"old"}');
  assert.ok(fs.existsSync(path.join(p.dataRoot, '.config/gh/hosts.yml')));
  assert.equal(fs.existsSync(path.join(p.home, '.claude/CLAUDE.md')), false);
});

test('apply: never overwrites files this app already has', async () => {
  await withSupervisor({ oldOptions: OLD_OPTIONS }, async (client, p) => {
    const { offer } = await detect(client, p);
    fs.mkdirSync(path.join(p.home, '.claude/skills/shared'), { recursive: true });
    fs.writeFileSync(path.join(p.home, '.claude/skills/shared/SKILL.md'), 'new skill\n');
    await apply(client, p, offer, ['claude'], { today: '2026-10-06', pollMs: 1, log: quiet, persistInstall: 'false-bin' });
    assert.equal(fs.readFileSync(path.join(p.home, '.claude/skills/shared/SKILL.md'), 'utf8'), 'new skill\n');
  });
});

test('apply: backup failure takes over nothing and stops nothing', async () => {
  const { result, p, sup } = await detectThenApply({ failBackup: true }, ['claude', 'login', 'stop']);
  assert.equal(result.ok, false);
  assert.match(result.fatal, /backup/);
  assert.equal(fs.existsSync(path.join(p.home, '.claude/CLAUDE.md')), false);
  assert.deepEqual(sup.state.stopped, []);
  assert.equal(fs.existsSync(p.state), false);
});

test('apply: unpacks only data/, not the app image', async () => {
  await withSupervisor({ oldOptions: OLD_OPTIONS }, async (client, p) => {
    const { offer } = await detect(client, p);
    await apply(client, p, offer, ['claude'], { today: '2026-10-06', pollMs: 1, log: quiet, persistInstall: 'false-bin', keepWork: true });
    assert.ok(fs.existsSync(path.join(p.work, 'app', 'data', 'home', '.claude')));
    assert.equal(fs.existsSync(path.join(p.work, 'app', 'image.tar')), false);
  });
});

test('apply: success marks done, removes the offer and the work dir', async () => {
  const { result, p } = await detectThenApply({}, ['claude']);
  assert.equal(result.ok, true);
  assert.equal(fs.readFileSync(p.state, 'utf8').trim(), 'done');
  assert.equal(fs.existsSync(p.offer), false);
  assert.equal(fs.existsSync(p.work), false);
});

const MEMORY = '.claude/projects/-config/memory/heating.md';

test('apply: copies keep timestamps', async () => {
  const mtime = new Date('2025-01-02T03:04:05Z');
  const { p } = await detectThenApply({ fixture: { mtime } }, ['claude']);
  const got = fs.statSync(path.join(p.home, MEMORY)).mtimeMs;
  assert.ok(Math.abs(got - mtime.getTime()) <= 2000, `mtime ${got} vs ${mtime.getTime()}`);
});

test('apply: claude step reports a missing source', async () => {
  const { result } = await detectThenApply({ fixture: { omit: ['home/.claude'] } }, ['claude']);
  assert.equal(result.results.claude, 'not found');
});

// n40: the old app was installed after this one, whose status line and plugin
// had already written Claude's setup files. own: files written in this app's
// home after detect, before apply ({ rel: content }).
async function applyOverOwn(fixture, own, selected = ['claude']) {
  return withSupervisor({ oldOptions: OLD_OPTIONS, fixture }, async (client, p) => {
    const { offer } = await detect(client, p);
    for (const [rel, content] of Object.entries(own)) {
      fs.mkdirSync(path.dirname(path.join(p.home, rel)), { recursive: true });
      fs.writeFileSync(path.join(p.home, rel), content);
    }
    const lines = [];
    const result = await apply(client, p, offer, selected,
      { today: '2026-10-06', pollMs: 1, log: (l) => lines.push(l), persistInstall: 'false-bin' });
    return { result, p, log: lines.join('\n') };
  });
}
const readHome = (p, rel) => fs.readFileSync(path.join(p.home, rel), 'utf8');
const readReplaced = (p, rel) => fs.readFileSync(path.join(p.replaced, '2026-10-06', rel), 'utf8');
const PLUGIN_RECORD = '.claude/plugins/.claude-workbench-ha-plugin';
const OWN_SETUP = {
  '.claude.json': '{"own":true}',
  '.claude/settings.json': '{"statusLine":{}}',
  '.claude/plugins/installed_plugins.json': '{"own":"installed"}',
  '.claude/plugins/known_marketplaces.json': '{"own":"known"}',
  [PLUGIN_RECORD]: 'true:1.0.0\n',
};
const OLD_SETUP = {
  'home/.claude/settings.json': '{"old":"settings"}',
  'home/.claude/plugins/installed_plugins.json': '{"old":"installed"}',
  'home/.claude/plugins/known_marketplaces.json': '{"old":"known"}',
};
const takeoverLeftovers = (p) => fs.readdirSync(p.home, { recursive: true }).filter((f) => String(f).endsWith('.takeover'));

test("apply: n40 - the old app's Claude files replace the ones status line and plugin wrote", async () => {
  const { result, p, log } = await applyOverOwn({ extra: OLD_SETUP }, OWN_SETUP);
  assert.equal(result.results.claude,
    `ok (replaced this app's own Claude settings, kept in ${path.join(p.replaced, '2026-10-06')})`);
  assert.equal(readHome(p, '.claude.json'), '{"oauthAccount":{"email":"x"}}');
  assert.equal(readHome(p, '.claude/settings.json'), '{"old":"settings"}');
  assert.equal(readHome(p, '.claude/plugins/installed_plugins.json'), '{"old":"installed"}');
  assert.equal(readHome(p, '.claude/plugins/known_marketplaces.json'), '{"old":"known"}');
  assert.equal(fs.existsSync(path.join(p.home, PLUGIN_RECORD)), false);
  for (const [rel, content] of Object.entries(OWN_SETUP)) assert.equal(readReplaced(p, rel), content, rel);
  assert.match(log, /Replaced this app's own \.claude\.json, \.claude\/settings\.json, /);
  assert.deepEqual(takeoverLeftovers(p), []);
  // the rest of the old ~/.claude still arrives
  assert.equal(readHome(p, '.claude/CLAUDE.md'), 'old global instructions\n');
});

test('apply: a second takeover the same day keeps the first one\'s set-aside files', async () => {
  // An apply killed after the claude step (before state: done) is offered again;
  // what it set aside the first time must not be overwritten.
  const { result, p } = await applyOverOwn({ extra: OLD_SETUP },
    { ...OWN_SETUP, '../migration/replaced/2026-10-06/.claude.json': '{"first":true}' });
  assert.equal(readReplaced(p, '.claude.json'), '{"first":true}');
  const second = path.join(p.replaced, '2026-10-06-2');
  assert.equal(fs.readFileSync(path.join(second, '.claude.json'), 'utf8'), '{"own":true}');
  assert.equal(result.results.claude, `ok (replaced this app's own Claude settings, kept in ${second})`);
});

test('apply: an old .claude.json alone replaces only ours', async () => {
  const { result, p } = await applyOverOwn(undefined, OWN_SETUP);
  assert.match(result.results.claude, /^ok \(replaced this app's own Claude settings/);
  assert.equal(readHome(p, '.claude.json'), '{"oauthAccount":{"email":"x"}}');
  assert.equal(readReplaced(p, '.claude.json'), '{"own":true}');
  assert.equal(readHome(p, '.claude/settings.json'), '{"statusLine":{}}');
  assert.equal(readHome(p, PLUGIN_RECORD), 'true:1.0.0\n');
  assert.equal(fs.existsSync(path.join(p.replaced, '2026-10-06', '.claude')), false);
});

test('apply: old settings only - our .claude.json stays', async () => {
  const { p } = await applyOverOwn(
    { omit: ['home/.claude.json'], extra: { 'home/.claude/settings.json': '{"old":"settings"}' } },
    { '.claude.json': '{"own":true}', '.claude/settings.json': '{"statusLine":{}}' });
  assert.equal(readHome(p, '.claude.json'), '{"own":true}');
  assert.equal(readHome(p, '.claude/settings.json'), '{"old":"settings"}');
  assert.equal(readReplaced(p, '.claude/settings.json'), '{"statusLine":{}}');
  assert.equal(fs.existsSync(path.join(p.replaced, '2026-10-06', '.claude.json')), false);
});

test('apply: own login before the takeover keeps everything', async () => {
  const { result, p } = await applyOverOwn({ extra: OLD_SETUP },
    { '.claude/.credentials.json': '{"token":"new"}', '.claude.json': '{"new":true}', '.claude/settings.json': '{"statusLine":{}}' });
  assert.equal(result.results.claude, 'ok (kept existing .claude.json)');
  assert.equal(readHome(p, '.claude.json'), '{"new":true}');
  assert.equal(readHome(p, '.claude/settings.json'), '{"statusLine":{}}');
  assert.equal(fs.existsSync(p.replaced), false);
});

test('apply: nothing of ours, nothing set aside', async () => {
  const { result, p } = await applyOverOwn({ extra: OLD_SETUP }, {});
  assert.equal(result.results.claude, 'ok');
  assert.equal(readHome(p, '.claude/settings.json'), '{"old":"settings"}');
  assert.equal(fs.existsSync(p.replaced), false);
});

test('apply: no old ~/.claude moves nothing', async () => {
  const { result, p } = await applyOverOwn({ omit: ['home/.claude'] }, { '.claude/settings.json': '{"statusLine":{}}' });
  assert.equal(result.results.claude, 'not found');
  assert.equal(readHome(p, '.claude/settings.json'), '{"statusLine":{}}');
  assert.equal(fs.existsSync(p.replaced), false);
});

test('apply: Claude data not selected moves nothing', async () => {
  const { p } = await applyOverOwn({ extra: OLD_SETUP }, OWN_SETUP, ['gh']);
  assert.equal(readHome(p, '.claude.json'), '{"own":true}');
  assert.equal(readHome(p, '.claude/settings.json'), '{"statusLine":{}}');
  assert.equal(fs.existsSync(p.replaced), false);
});

test('apply: an old file that cannot be copied leaves ours in place', async () => {
  // settings.json is a directory in the old app: copying it as a file fails
  const { result, p } = await applyOverOwn({ extra: { 'home/.claude/settings.json/x': '' } },
    { '.claude.json': '{"own":true}', '.claude/settings.json': '{"statusLine":{}}' });
  assert.match(result.results.claude, /^error: /);
  assert.equal(readHome(p, '.claude.json'), '{"own":true}');
  assert.equal(readHome(p, '.claude/settings.json'), '{"statusLine":{}}');
  assert.deepEqual(takeoverLeftovers(p), []);
  assert.equal(fs.existsSync(p.replaced), false);
});

test('apply: outer backup.tar is removed before the inner archive is unpacked', async () => {
  await withSupervisor({ oldOptions: OLD_OPTIONS }, async (client, p) => {
    const { offer } = await detect(client, p);
    await apply(client, p, offer, ['claude'], { today: '2026-10-06', pollMs: 1, log: quiet, keepWork: true });
    assert.equal(fs.existsSync(path.join(p.work, 'backup.tar')), false);
  });
});

test('apply: an existing login is not overwritten', async () => {
  await withSupervisor({ oldOptions: OLD_OPTIONS }, async (client, p) => {
    const { offer } = await detect(client, p);
    fs.writeFileSync(path.join(p.home, '.claude', '.credentials.json'), '{"token":"new"}');
    const r = await apply(client, p, offer, ['login'], { today: '2026-10-06', pollMs: 1, log: quiet });
    assert.equal(r.results.login, 'ok');
    assert.equal(fs.readFileSync(path.join(p.home, '.claude/.credentials.json'), 'utf8'), '{"token":"new"}');
  });
});

test('apply: login and gh report not found when the backup lacks them', async () => {
  const { result } = await detectThenApply(
    { fixture: { omit: ['.config/gh', 'home/.claude/.credentials.json'] } }, ['login', 'gh']);
  assert.equal(result.results.login, 'not found');
  assert.equal(result.results.gh, 'not found');
});

test('apply: a failed backup keeps the offer', async () => {
  const { result, p } = await detectThenApply({ failBackup: true }, ['claude']);
  assert.equal(result.ok, false);
  assert.equal(fs.existsSync(p.offer), true);
});

test('apply: a finished job without a slug is fatal', async () => {
  const { result } = await detectThenApply({ jobNoReference: true }, ['claude']);
  assert.equal(result.ok, false);
  assert.match(result.fatal, /without a backup slug/);
});

test('apply: a failure after the backup exists deletes the backup and takes over nothing', async () => {
  const { result, p, sup } = await detectThenApply({ failDownload: true }, ['claude', 'login', 'stop']);
  assert.equal(result.ok, false);
  assert.match(result.fatal, /download failed/);
  assert.equal(result.backupDeleted, true);
  assert.deepEqual(sup.state.deletedBackups, ['bk1']);
  assert.deepEqual(sup.state.backups, []);
  assert.equal(fs.existsSync(p.offer), true);
  assert.equal(fs.existsSync(p.state), false);
  assert.equal(fs.existsSync(p.work), false);
  assert.equal(fs.existsSync(path.join(p.home, '.claude/CLAUDE.md')), false);
  assert.deepEqual(sup.state.stopped, []);
});

test('apply: too little free space for the backup is fatal before the download', async () => {
  const { result, sup } = await detectThenApply({ backupSizeMb: 1e9 }, ['claude', 'stop']);
  assert.equal(result.ok, false);
  assert.match(result.fatal, /^not enough free space in .*: need ~\d+ MB, have \d+ MB$/);
  assert.equal(result.backupDeleted, true);
  assert.deepEqual(sup.state.deletedBackups, ['bk1']);
  assert.equal(sup.state.calls.some((c) => c.url === '/backups/bk1/download'), false);
  assert.deepEqual(sup.state.stopped, []);
});

test('apply: checks the backup size before downloading it', async () => {
  const { result, sup } = await detectThenApply({}, ['claude']);
  assert.equal(result.ok, true);
  const urls = sup.state.calls.map((c) => c.url);
  assert.ok(urls.indexOf('/backups/bk1/info') >= 0, 'no size check');
  assert.ok(urls.indexOf('/backups/bk1/info') < urls.indexOf('/backups/bk1/download'));
});

test('apply: a failed backup deletion is reported, the fatal error is kept', async () => {
  const lines = [];
  const { result } = await detectThenApply({ failDownload: true, failDelete: true }, ['claude'],
    { log: (l) => lines.push(l) });
  assert.equal(result.ok, false);
  assert.match(result.fatal, /download failed/);
  assert.equal(result.backupDeleted, false);
  assert.equal(result.backupSlug, 'bk1');
  assert.match(lines.join('\n'), /delete failed/);
});

test('apply: a failed backup job reports no backup to delete', async () => {
  const { result, sup } = await detectThenApply({ failBackup: true }, ['claude']);
  assert.equal(result.backupDeleted, false);
  assert.deepEqual(sup.state.calls.filter((c) => c.method === 'DELETE'), []);
});

// A persist-install stand-in that logs its arguments and fails for "badpkg"
// (apk) or "badpy" (pip).
// sleepMs: hangs that long before exiting (for the timeout test).
function fakePersistInstall(dir, { sleepMs = 0 } = {}) {
  const log = path.join(dir, 'persist.log');
  const bin = path.join(dir, 'persist-install.js');
  fs.writeFileSync(bin, `require('fs').appendFileSync(${JSON.stringify(log)}, process.argv.slice(2).join(' ') + '\\n');
const bad = ['badpkg', 'badpy'].some((b) => process.argv.includes(b));
setTimeout(() => process.exit(bad ? 1 : 0), ${sleepMs});\n`);
  return { log, deps: { persistInstall: process.execPath, persistInstallArgs: [bin] } };
}

const persistCalls = (fake) => fs.readFileSync(fake.log, 'utf8').trim().split('\n');
const SITE_PACKAGES = 'packages/python/venv/lib/python3.12/site-packages';

test('apply: reinstalls packages from old options plus the old venv, records them', async () => {
  const fake = fakePersistInstall(tmp());
  const ownOptions = { persistent_apk_packages: ['git'], auto_launch_claude: true };
  const { result, sup } = await detectThenApply({ ownOptions }, ['packages'], fake.deps);
  assert.equal(result.results.packages, 'ok');
  // One pip call for all; idna is only a dependency (no REQUESTED), so pip pulls it in itself.
  assert.deepEqual(persistCalls(fake), ['--apk htop', '--python httpx requests']);
  assert.deepEqual(sup.state.ownOptions.persistent_apk_packages, ['git', 'htop']);
  assert.deepEqual(sup.state.ownOptions.persistent_pip_packages, ['httpx', 'requests']);
  assert.equal(sup.state.ownOptions.auto_launch_claude, true, 'unrelated own options must survive');
});

test('apply: without any REQUESTED marker every venv package is taken', async () => {
  const fake = fakePersistInstall(tmp());
  const fixture = { omit: [`${SITE_PACKAGES}/requests-2.32.0.dist-info/REQUESTED`] };
  const { sup } = await detectThenApply({ fixture }, ['packages'], fake.deps);
  assert.deepEqual(persistCalls(fake), ['--apk htop', '--python httpx idna requests']);
  assert.deepEqual(sup.state.ownOptions.persistent_pip_packages, ['httpx', 'idna', 'requests']);
});

test('apply: pip names are compared normalised, the old options spelling wins', async () => {
  const fake = fakePersistInstall(tmp());
  const oldOptions = { ...OLD_OPTIONS, persistent_pip_packages: ['httpx', 'Requests'] };
  const { sup } = await detectThenApply({ oldOptions }, ['packages'], fake.deps);
  assert.deepEqual(persistCalls(fake), ['--apk htop', '--python httpx Requests']);
  assert.deepEqual(sup.state.ownOptions.persistent_pip_packages, ['httpx', 'Requests']);
});

test('apply: a failing pip batch is retried one by one, only the good ones are recorded', async () => {
  const fake = fakePersistInstall(tmp());
  const oldOptions = { ...OLD_OPTIONS, persistent_pip_packages: ['httpx', 'badpy'] };
  const { result, sup } = await detectThenApply({ oldOptions }, ['packages'], fake.deps);
  assert.deepEqual(persistCalls(fake), [
    '--apk htop', '--python httpx badpy requests', '--python httpx', '--python badpy', '--python requests',
  ]);
  assert.match(result.results.packages, /^error: could not install badpy$/);
  assert.deepEqual(sup.state.ownOptions.persistent_pip_packages, ['httpx', 'requests']);
});

// n30: a package name reaches persist-install only after --apk/--python and
// only if it is one name; a leading - would be a flag, a bare `ha` a mode.
test('detect: only valid package names reach the offer', async () => {
  const oldOptions = { ...OLD_OPTIONS, persistent_apk_packages: ['htop', '--ha-cli', 'ha', 'git vim'],
    persistent_pip_packages: ['httpx', '-r x', 'pandas[all]'] };
  await withSupervisor({ oldOptions }, async (client, p) => {
    const { offer } = await detect(client, p);
    assert.deepEqual(offer.apk, ['htop', 'ha']);
    assert.deepEqual(offer.pip, ['httpx', 'pandas[all]']);
  });
});

test('apply: invalid names from the old venv or an older offer are skipped, not failed', async () => {
  const fake = fakePersistInstall(tmp());
  const lines = [];
  const fixture = { extra: { [`${SITE_PACKAGES}/-evil-1.0.dist-info/REQUESTED`]: '' } };
  const { result, sup } = await withSupervisor({ oldOptions: OLD_OPTIONS, fixture }, async (client, p, s) => {
    const { offer } = await detect(client, p);
    offer.apk.push('--ha-cli'); // written by a version without the check
    const r = await apply(client, p, offer, ['packages', 'stop'],
      { today: '2026-10-06', pollMs: 1, log: (l) => lines.push(l), ...fake.deps });
    return { result: r, sup: s };
  });
  assert.deepEqual(persistCalls(fake), ['--apk htop', '--python httpx requests']);
  assert.equal(result.results.packages, 'ok');
  assert.equal(result.results.stop, 'ok', 'a skipped name must not keep the old app running');
  assert.deepEqual(sup.state.ownOptions.persistent_apk_packages, ['htop']);
  assert.deepEqual(sup.state.ownOptions.persistent_pip_packages, ['httpx', 'requests']);
  assert.ok(lines.some((l) => l.includes('skipped --ha-cli (not a package name)')), lines.join('\n'));
  assert.ok(lines.some((l) => l.includes('skipped -evil (not a package name)')), lines.join('\n'));
});

test('apply: no package installed means this app\'s options are not written', async () => {
  const fake = fakePersistInstall(tmp());
  const oldOptions = { ...OLD_OPTIONS, persistent_apk_packages: ['badpkg'], persistent_pip_packages: ['badpy'] };
  const { result, sup } = await detectThenApply({ oldOptions, fixture: { omit: ['packages'] } }, ['packages'], fake.deps);
  assert.match(result.results.packages, /^error: could not install badpkg, badpy$/);
  assert.equal(sup.state.calls.some((c) => c.url === '/addons/self/options'), false);
});

test('apply: settings are merged into this app\'s options, excluded keys untouched', async () => {
  const own = { auto_launch_claude: true, use_persistent_claude: true, auto_update_claude_on_start: true };
  const { result, sup } = await detectThenApply({ ownOptions: own }, ['settings']);
  assert.equal(result.results.settings, 'ok');
  assert.deepEqual(sup.state.ownOptions, {
    auto_launch_claude: false, dangerously_skip_permissions: true, tmux_mouse: false,
    use_persistent_claude: true, auto_update_claude_on_start: true,
  });
});

test('apply: stops the old app last and disables its autostart when everything succeeded', async () => {
  const { result, sup } = await detectThenApply({}, ['claude', 'stop']);
  assert.equal(result.results.stop, 'ok');
  assert.deepEqual(sup.state.stopped, [OLD_SLUG]);
  assert.deepEqual(sup.state.oldOptionsPosted, { boot: 'manual' });
  assert.deepEqual(sup.state.calls.slice(-2).map((c) => `${c.method} ${c.url}`),
    [`POST /addons/${OLD_SLUG}/stop`, `POST /addons/${OLD_SLUG}/options`]);
});

test('apply: a failure to disable the autostart is reported, the stop stays ok', async () => {
  const { result, sup } = await detectThenApply({ failOldOptions: true }, ['claude', 'stop']);
  assert.deepEqual(sup.state.stopped, [OLD_SLUG]);
  assert.match(result.results.stop, /^ok \(stopped; could not disable autostart: .*options failed\)$/);
});

test('apply: a failing stop does not touch the autostart', async () => {
  const { sup } = await detectThenApply({ failStop: true }, ['claude', 'stop']);
  assert.equal(sup.state.oldOptionsPosted, null);
});

test('apply: all six items at once', async () => {
  const fake = fakePersistInstall(tmp());
  const ownOptions = { persistent_apk_packages: ['git'], use_persistent_claude: true };
  const all = ['claude', 'login', 'gh', 'packages', 'stop', 'settings'];
  const { result, p, sup } = await detectThenApply({ ownOptions }, all, fake.deps);
  assert.equal(result.ok, true);
  assert.deepEqual(result.results, {
    claude: 'ok', login: 'ok', gh: 'ok', packages: 'ok', settings: 'ok', stop: 'ok',
  });
  assert.deepEqual(sup.state.ownOptions, {
    persistent_apk_packages: ['git', 'htop'], persistent_pip_packages: ['httpx', 'requests'],
    use_persistent_claude: true,
    auto_launch_claude: false, dangerously_skip_permissions: true, tmux_mouse: false,
  });
  assert.deepEqual(sup.state.stopped, [OLD_SLUG]);
  assert.deepEqual(sup.state.oldOptionsPosted, { boot: 'manual' });
  assert.equal(fs.readFileSync(path.join(p.home, '.claude/.credentials.json'), 'utf8'), '{"token":"old"}');
  assert.ok(fs.existsSync(path.join(p.home, MEMORY)));
  assert.ok(fs.existsSync(path.join(p.dataRoot, '.config/gh/hosts.yml')));
  assert.equal(fs.readFileSync(p.state, 'utf8').trim(), 'done');
});

test('apply: a failed item keeps the old app running', async () => {
  const fake = fakePersistInstall(tmp());
  const oldOptions = { ...OLD_OPTIONS, persistent_apk_packages: ['badpkg'] };
  const { result, sup } = await detectThenApply({ oldOptions }, ['claude', 'packages', 'stop'], fake.deps);
  assert.match(result.results.packages, /^error: .*badpkg/);
  assert.equal(result.results.claude, 'ok');
  assert.match(result.results.stop, /^skipped/);
  assert.deepEqual(sup.state.stopped, []);
  assert.equal(sup.state.ownOptions.persistent_apk_packages.includes('badpkg'), false);
});

test('apply: a failing stop is reported as an error', async () => {
  const { result } = await detectThenApply({ failStop: true }, ['claude', 'stop']);
  assert.match(result.results.stop, /^error:/);
});

test('apply: a "not found" item does not block stopping the old app', async () => {
  const { result, sup } = await detectThenApply({ fixture: { omit: ['.config/gh'] } }, ['gh', 'stop']);
  assert.equal(result.results.gh, 'not found');
  assert.equal(result.results.stop, 'ok');
  assert.deepEqual(sup.state.stopped, [OLD_SLUG]);
});

test('apply: Claude data or login not found keeps the old app running', async () => {
  for (const selected of [['claude', 'stop'], ['login', 'stop']]) {
    const { result, sup } = await detectThenApply({ fixture: { omit: ['home/.claude'] } }, selected);
    assert.equal(result.results[selected[0]], 'not found');
    assert.equal(result.results.stop, 'skipped: Claude data or login not found in the backup, the old app keeps running');
    assert.deepEqual(sup.state.stopped, []);
  }
});

test('apply: a hanging persist-install is killed and counts as failed', async () => {
  const fake = fakePersistInstall(tmp(), { sleepMs: 5000 });
  const oldOptions = { ...OLD_OPTIONS, persistent_apk_packages: ['slowpkg'], persistent_pip_packages: [] };
  const started = Date.now();
  const { result, sup } = await detectThenApply({ oldOptions }, ['packages'],
    { ...fake.deps, installTimeoutMs: 200 });
  assert.ok(Date.now() - started < 4000, 'apply waited for the hanging install');
  assert.match(result.results.packages, /^error: .*slowpkg/);
  assert.equal((sup.state.ownOptions.persistent_apk_packages || []).includes('slowpkg'), false);
});

const { ITEMS, render, parseInput, renderSummary } = require(path.join(MOD, 'dialog'));

const OFFER = { slug: OLD_SLUG, name: 'Claude Terminal Pro', version: '2.0.13',
  repository: 'https://github.com/ESJavadex/claude-code-ha',
  apk: ['htop'], pip: ['httpx'], settings: { auto_launch_claude: false } };

test('dialog: all six items, all on, packages and settings spelled out', () => {
  const text = render(OFFER, [...ITEMS]);
  assert.match(text, /Stop the old app and disable its autostart/);
  assert.equal(ITEMS.length, 6);
  assert.equal((text.match(/\[x\]/g) || []).length, 6);
  assert.match(text, /Claude Terminal Pro 2\.0\.13 \(https:\/\/github\.com\/ESJavadex\/claude-code-ha\)/);
  assert.match(text, /apk: htop/);
  assert.match(text, /pip: httpx/);
  assert.match(text, /auto_launch_claude=false/);
});

test('dialog: digits toggle, empty line applies, s and n', () => {
  let r = parseInput('3', [...ITEMS]);
  assert.equal(r.action, 'toggle');
  assert.equal(r.selected.includes('gh'), false);
  r = parseInput(' 3 ', r.selected);
  assert.equal(r.selected.includes('gh'), true);
  assert.equal(parseInput('', ITEMS).action, 'apply');
  assert.equal(parseInput('S', ITEMS).action, 'later');
  assert.equal(parseInput('n', ITEMS).action, 'never');
  assert.equal(parseInput('9', ITEMS).action, 'invalid');
});

test('dialog: Enter with nothing selected does not apply', () => {
  assert.equal(parseInput('', []).action, 'invalid');
});

test('dialog: string settings are quoted, a notice is shown', () => {
  const offer = { ...OFFER, settings: { auto_launch_claude: false, remote_control_session_name: '' } };
  const text = render(offer, [...ITEMS], 'Type 1–6 to toggle, Enter to take over, s or n.');
  assert.match(text, /remote_control_session_name=""/);
  assert.match(text, /auto_launch_claude=false/);
  assert.match(text, /Type 1–6 to toggle/);
  assert.doesNotMatch(render(offer, [...ITEMS]), /Type 1–6 to toggle/);
});

test('cli: detect exits 0 and prints the reason when nothing is offered', () => {
  const dir = tmp();
  const r = spawnSync(process.execPath, [path.join(MOD, 'cli.js'), 'detect'], {
    encoding: 'utf8',
    env: { ...process.env, MIGRATION_DATA_ROOT: dir, SUPERVISOR_API: 'http://127.0.0.1:9', SUPERVISOR_TOKEN: 'x' },
  });
  assert.equal(r.status, 0);
  assert.match(r.stdout + r.stderr, /App migration: detection failed/);
});

test('cli: a failed detect warns and removes a stale offer', () => {
  const dir = tmp();
  const p = migrationPaths({ MIGRATION_DATA_ROOT: dir });
  fs.mkdirSync(p.dir, { recursive: true });
  fs.writeFileSync(p.offer, '{}');
  const r = spawnSync(process.execPath, [path.join(MOD, 'cli.js'), 'detect'], {
    encoding: 'utf8',
    env: { ...process.env, MIGRATION_DATA_ROOT: dir, SUPERVISOR_API: 'http://127.0.0.1:9', SUPERVISOR_TOKEN: 'x' },
  });
  assert.equal(r.status, 0);
  assert.match(r.stdout, /^WARNING: App migration: /);
  assert.equal(fs.existsSync(p.offer), false);
});

test('summary: a fatal result says whether the backup was removed', () => {
  const removed = renderSummary({ ok: false, fatal: 'download failed', backupSlug: 'bk1', backupDeleted: true, results: {} });
  assert.match(removed, /Nothing was taken over: download failed/);
  assert.match(removed, /backup .*was deleted/i);
  const kept = renderSummary({ ok: false, fatal: 'download failed', backupSlug: 'bk1', backupDeleted: false, results: {} });
  assert.match(kept, /could not be deleted/);
  assert.match(kept, /Claude Workbench – Übernahme/);
  assert.match(kept, /bk1/);
  const none = renderSummary({ ok: false, fatal: 'backup failed', backupDeleted: false, results: {} });
  assert.doesNotMatch(none, /delete/i);
});

test('summary: names failures and the kept backup', () => {
  const text = renderSummary({ ok: true, backupSlug: 'bk1', results: { claude: 'ok', packages: 'error: could not install x' } });
  assert.match(text, /Claude data: ok/);
  assert.match(text, /error: could not install x/);
  assert.match(text, /Settings → System → Backups/);
});
