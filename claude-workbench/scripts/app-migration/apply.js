'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { isApkName, isPipSpec } = require('./package-names');
const { hasOwnClaudeData } = require('./detect');

// Verified on HA-Test (plan Task 0): the partial backup is a tar holding
// <slug>.tar.gz, whose data/ is the app's /data. That archive also carries
// image.tar, the locally built Docker image (hundreds of MB), so only data/ is
// extracted.
const INNER_DATA_PREFIX = 'data';
const innerArchiveName = (slug) => `${slug}.tar.gz`;

function run(cmd, args) {
  const r = spawnSync(cmd, args, { encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`${cmd} ${args.join(' ')} failed: ${(r.stderr || '').trim()}`);
}

function today() { return new Date().toISOString().slice(0, 10); }

const POLL_MS = 2000;
const BACKUP_TIMEOUT_MS = 60 * 60 * 1000;
const INSTALL_TIMEOUT_MS = 15 * 60 * 1000; // per persist-install call
const PROGRESS_EVERY_MS = 15 * 1000;
// Peak disk use is while the outer tar (about the backup size) is unpacked:
// the inner <slug>.tar.gz it yields is about as large again, and the outer tar
// is removed only afterwards. 0.2 is headroom for the unpacked data/ and the
// copies into /data.
const FREE_SPACE_FACTOR = 2.2;

// A synchronous backup request only answers once the backup is written; with the
// app image inside that can take longer than fetch's 300 s header timeout on slow
// hardware. So run it as a Supervisor background job and poll /jobs/<id>, whose
// "reference" is the backup slug once done (supervisor api/backups.py, jobs).
// Progress goes to the terminal: the backup alone can take many minutes, and a
// silent screen looks like a hang.
async function createBackup(client, offer, { date, pollMs, log, progressEveryMs }) {
  log('  Creating a partial backup of the old app...');
  const created = await client.post('/backups/new/partial', {
    name: `Claude Workbench – Übernahme ${date}`,
    addons: [offer.slug],
    homeassistant: false,
    background: true,
  });
  if (created.slug) return created.slug; // finished before the request returned
  const started = Date.now();
  const deadline = started + BACKUP_TIMEOUT_MS;
  let lastProgress = started;
  for (;;) {
    const job = await client.get(`/jobs/${created.job_id}`);
    if (job.done) {
      if (job.errors && job.errors.length) {
        throw new Error(`backup failed: ${job.errors.map((e) => e.message).join('; ')}`);
      }
      if (!job.reference) throw new Error('backup finished without a backup slug');
      return job.reference;
    }
    const now = Date.now();
    if (now > deadline) throw new Error('backup still running after 60 minutes');
    if (now - lastProgress >= progressEveryMs) {
      log(`  Still creating the backup… ${Math.round((now - started) / 1000)} s`);
      lastProgress = now;
    }
    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }
}

// Fails before the download: a full /data breaks Claude and this app, not
// only the migration. Supervisor reports the backup size in MB.
async function checkFreeSpace(client, p, slug) {
  const { size } = await client.get(`/backups/${slug}/info`);
  const st = fs.statfsSync(p.dataRoot);
  const haveMb = (Number(st.bavail) * Number(st.bsize)) / (1024 * 1024);
  const needMb = (Number(size) || 0) * FREE_SPACE_FACTOR;
  if (haveMb < needMb) {
    throw new Error(`not enough free space in ${p.dataRoot}: need ~${Math.ceil(needMb)} MB, have ${Math.floor(haveMb)} MB`);
  }
}

async function fetchOldData(client, offer, p, slug, opts) {
  await checkFreeSpace(client, p, slug);
  fs.rmSync(p.work, { recursive: true, force: true });
  fs.mkdirSync(p.work, { recursive: true });
  const outer = path.join(p.work, 'backup.tar');
  opts.log('  Downloading the backup...');
  await client.download(`/backups/${slug}/download`, outer);
  opts.log('  Unpacking the backup...');
  run('tar', ['-xf', outer, '-C', p.work]);
  fs.rmSync(outer, { force: true }); // halves peak disk use before the inner archive is unpacked
  const inner = path.join(p.work, innerArchiveName(offer.slug));
  if (!fs.existsSync(inner)) throw new Error(`backup has no ${innerArchiveName(offer.slug)}`);
  const extracted = path.join(p.work, 'app');
  fs.mkdirSync(extracted);
  run('tar', ['-xzf', inner, '-C', extracted, INNER_DATA_PREFIX]);
  return { backupSlug: slug, oldData: path.join(extracted, INNER_DATA_PREFIX) };
}

// A backup nobody can use (download/unpack failed) is only a full copy of the
// old login plus the app image; the next start asks again and creates a new one.
// A failing delete must not hide the original error, so it is only logged.
async function deleteBackup(client, slug, log) {
  try {
    await client.del(`/backups/${slug}`);
    return true;
  } catch (e) {
    log(`  Could not delete the backup ${slug}: ${e.message}`);
    return false;
  }
}

// Copies src to dst without replacing anything that already exists there.
// Returns false when the source does not exist.
function copyMissing(src, dst, filter) {
  if (!fs.existsSync(src)) return false;
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.cpSync(src, dst, { recursive: true, force: false, errorOnExist: false,
    preserveTimestamps: true, verbatimSymlinks: true, filter });
  return true;
}

// n40: an old app installed after this one is offered only on a later start,
// when the status line and the plugin have already written Claude's setup
// files (settings.json, the plugin lists, ~/.claude.json from `claude plugin`)
// and copyMissing would keep the old ones out. An offer exists only without a
// login and a project history (detect.js hasOwnClaudeData), so ours hold what
// this app and the CLI wrote, and the old ones replace them as whole files.
//   - ~/.claude.json only when the old app has one: without it, a leftover
//     ~/.claude/backups/.claude.json.backup.* makes every `claude` call warn
//     (checked with Claude Code 2.1.119).
//   - settings.json (enabledPlugins, extraKnownMarketplaces), both plugin lists
//     and our plugin record only together: they are right only as a set, and
//     without our record the next start sets the plugin up from the old
//     record (.addon-ha-plugin, n31) or anew (run.sh setup_ha_plugin).
// Copy first, then swap: a copy failing half-way would otherwise leave Claude
// without ~/.claude.json or with half a plugin set. Ours are moved, never
// deleted. Rejected: merging the files or checking whether ours hold only app
// entries - both read three formats Claude owns and changes (spec 3.6.4 n33,
// 3.6.5). tests/test-app-migration.js "n40".
const CLAUDE_JSON = '.claude.json';
const SETUP_FILES = ['.claude/settings.json', '.claude/plugins/installed_plugins.json',
  '.claude/plugins/known_marketplaces.json'];
const PLUGIN_RECORD = '.claude/plugins/.claude-workbench-ha-plugin'; // run.sh setup_ha_plugin, HA_PLUGIN_STATE

// A folder of its own per takeover: one killed after the claude step (before
// state: done) is offered again, and its second run must not rename over what
// the first one set aside (review 3.6.5).
function freeReplacedDir(p, date) {
  let dir = path.join(p.replaced, date);
  for (let n = 2; fs.existsSync(dir); n += 1) dir = path.join(p.replaced, `${date}-${n}`);
  return dir;
}

// Returns the paths (relative to the home) of ours that were set aside and the
// folder they went to.
function setAsideOwnSetup(p, oldHome, date) {
  const none = { moved: [], kept: '' };
  if (hasOwnClaudeData(p)) return none;
  const has = (home, rel) => fs.existsSync(path.join(home, rel));
  const swap = [];
  if (has(oldHome, CLAUDE_JSON)) swap.push(CLAUDE_JSON);
  if (SETUP_FILES.some((rel) => has(oldHome, rel))) swap.push(...SETUP_FILES, PLUGIN_RECORD);
  if (!swap.some((rel) => has(p.home, rel))) return none; // nothing of ours: copyMissing does it all

  const staged = [];
  try {
    for (const rel of swap.filter((r) => has(oldHome, r))) {
      const tmp = `${path.join(p.home, rel)}.takeover`;
      fs.mkdirSync(path.dirname(tmp), { recursive: true });
      staged.push(tmp);
      fs.cpSync(path.join(oldHome, rel), tmp, { preserveTimestamps: true, verbatimSymlinks: true });
    }
  } catch (e) {
    for (const tmp of staged) fs.rmSync(tmp, { recursive: true, force: true });
    throw e;
  }
  const kept = freeReplacedDir(p, date);
  const moved = [];
  for (const rel of swap) {
    const own = path.join(p.home, rel);
    if (fs.existsSync(own)) {
      fs.mkdirSync(path.dirname(path.join(kept, rel)), { recursive: true });
      fs.renameSync(own, path.join(kept, rel));
      moved.push(rel);
    }
    if (fs.existsSync(`${own}.takeover`)) fs.renameSync(`${own}.takeover`, own);
  }
  return { moved, kept };
}

const PIP_BOOTSTRAP = new Set(['pip', 'setuptools', 'wheel']);
const unique = (list) => [...new Set(list)];

// PEP 503: "Foo_Bar", "foo.bar" and "foo-bar" are the same project.
const normalisePip = (name) => name.toLowerCase().replace(/[-_.]+/g, '-');

// First spelling wins, duplicates by normalised name dropped.
function uniquePip(list) {
  const seen = new Set();
  return list.filter((name) => {
    const key = normalisePip(name);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

// Package names (normalised) from the old venv's *.dist-info directories.
// pip marks packages installed by name with a REQUESTED file; their
// dependencies lack it and are pulled in again by pip itself. A venv without
// any marker (older pip, other installer) falls back to every package.
function pipNamesFromVenv(oldData) {
  const lib = path.join(oldData, 'packages', 'python', 'venv', 'lib');
  if (!fs.existsSync(lib)) return [];
  const all = [];
  for (const py of fs.readdirSync(lib)) {
    const sitePackages = path.join(lib, py, 'site-packages');
    if (!fs.existsSync(sitePackages)) continue;
    for (const entry of fs.readdirSync(sitePackages)) {
      const m = /^(.+?)-[^-]+\.dist-info$/.exec(entry);
      if (!m) continue;
      const name = normalisePip(m[1]);
      if (PIP_BOOTSTRAP.has(name)) continue;
      all.push({ name, requested: fs.existsSync(path.join(sitePackages, entry, 'REQUESTED')) });
    }
  }
  const requested = all.filter((d) => d.requested);
  // readdir order is not sorted on every filesystem (ext4).
  return (requested.length ? requested : all).map((d) => d.name).sort();
}

// Supervisor replaces the whole option set, so merge into the current one.
// Known and accepted: /addons/self/info returns the options with the schema
// defaults merged in, so writing them back pins today's defaults as if the
// user had set them. There is no API that returns only user-set options.
async function mergeOwnOptions(client, change) {
  const self = await client.get('/addons/self/info');
  const current = self.options || {};
  await client.post('/addons/self/options', { options: { ...current, ...change(current) } });
}

async function apply(client, p, offer, selected, deps = {}) {
  const results = {};
  const log = deps.log || console.log;
  const opts = {
    date: deps.today || today(),
    pollMs: deps.pollMs || POLL_MS,
    log,
    progressEveryMs: deps.progressEveryMs ?? PROGRESS_EVERY_MS,
  };
  let backupSlug;
  let old;
  try {
    backupSlug = await createBackup(client, offer, opts);
    old = await fetchOldData(client, offer, p, backupSlug, opts);
  } catch (e) {
    fs.rmSync(p.work, { recursive: true, force: true });
    const backupDeleted = backupSlug ? await deleteBackup(client, backupSlug, log) : false;
    return { ok: false, fatal: e.message, backupSlug, backupDeleted, results };
  }
  const oldHome = path.join(old.oldData, 'home');

  async function step(name, fn) {
    if (!selected.includes(name)) return;
    // A step may return a status string ('not found'); anything else (API
    // responses, undefined) counts as 'ok', so results stay plain strings.
    try {
      const r = await fn();
      results[name] = typeof r === 'string' ? r : 'ok';
    } catch (e) { results[name] = `error: ${e.message}`; }
  }

  await step('claude', () => {
    if (!fs.existsSync(path.join(oldHome, '.claude'))) return 'not found';
    const { moved, kept } = setAsideOwnSetup(p, oldHome, opts.date);
    if (moved.length) log(`  Replaced this app's own ${moved.join(', ')} (kept in ${kept})`);
    copyMissing(path.join(oldHome, '.claude'), path.join(p.home, '.claude'),
      (src) => path.basename(src) !== '.credentials.json');
    const keptJson = fs.existsSync(path.join(p.home, '.claude.json'));
    copyMissing(path.join(oldHome, '.claude.json'), path.join(p.home, '.claude.json'));
    if (moved.length) return `ok (replaced this app's own Claude settings, kept in ${kept})`;
    return keptJson ? 'ok (kept existing .claude.json)' : 'ok';
  });
  await step('login', () => (copyMissing(path.join(oldHome, '.claude', '.credentials.json'),
    path.join(p.home, '.claude', '.credentials.json')) ? 'ok' : 'not found'));
  await step('gh', () => (copyMissing(path.join(old.oldData, '.config', 'gh'),
    path.join(p.dataRoot, '.config', 'gh')) ? 'ok' : 'not found'));

  const persistInstall = deps.persistInstall || '/usr/local/bin/persist-install';
  const persistArgs = deps.persistInstallArgs || [];
  // Bounded: a hanging apk/pip (mirror down, prompt) must not keep the dialog,
  // and with it Claude, blocked forever. A killed run has status null.
  const installTimeoutMs = deps.installTimeoutMs || INSTALL_TIMEOUT_MS;
  const install = (args) => {
    const r = spawnSync(persistInstall, [...persistArgs, ...args],
      { stdio: 'inherit', timeout: installTimeoutMs, killSignal: 'SIGKILL' });
    return !r.error && r.status === 0;
  };

  await step('packages', async () => {
    const failed = [];
    // n30: a name that is not one package (a leading - would be a flag for
    // persist-install, apk or pip) is skipped with a line, not counted as a
    // failure: a typo in the old app's list must not keep it running. detect
    // filters the options already; the venv's directory names and an offer
    // written by an older version are checked here. apk names go after --apk,
    // where `ha` or `python` can no longer start another persist-install mode.
    const keep = (check) => (name) => check(name) || (log(`  skipped ${name} (not a package name)`), false);
    const apkWanted = offer.apk.filter(keep(isApkName));
    const pipWanted = uniquePip([...offer.pip, ...pipNamesFromVenv(old.oldData)]).filter(keep(isPipSpec));
    log(`  Installing packages: apk: ${apkWanted.join(' ') || '-'} | pip: ${pipWanted.join(' ') || '-'}`);
    const apk = apkWanted.filter((pkg) => install(['--apk', pkg]) || (failed.push(pkg), false));
    // One pip run resolves all versions together and is much faster; only if
    // it fails, retry one by one to find the culprit(s).
    const pip = pipWanted.length && install(['--python', ...pipWanted])
      ? pipWanted
      : pipWanted.filter((pkg) => install(['--python', pkg]) || (failed.push(pkg), false));
    // Nothing installed: writing the options back would only pin today's
    // schema defaults (see mergeOwnOptions) for no gain.
    if (apk.length || pip.length) {
      await mergeOwnOptions(client, (cur) => ({
        persistent_apk_packages: unique([...(cur.persistent_apk_packages || []), ...apk]),
        persistent_pip_packages: uniquePip([...(cur.persistent_pip_packages || []), ...pip]),
      }));
    }
    if (failed.length) throw new Error(`could not install ${failed.join(', ')}`);
  });

  await step('settings', () => mergeOwnOptions(client, () => offer.settings));

  // Last, and only if nothing failed: the old app is the fallback. A selected
  // Claude data/login item that found nothing means the backup did not hold
  // what the user came for (other layout, empty app), so keep it too.
  if (selected.includes('stop')) {
    const missing = ['claude', 'login'].some((k) => results[k] === 'not found');
    if (Object.values(results).some((r) => r.startsWith('error'))) {
      results.stop = 'skipped: an earlier item failed, the old app keeps running';
    } else if (missing) {
      results.stop = 'skipped: Claude data or login not found in the backup, the old app keeps running';
    } else {
      // Both apps share one Claude OAuth login; an old app that boots again
      // after a host reboot could refresh (rotate) it under this app. The
      // options endpoint accepts boot alone and changes nothing else.
      await step('stop', async () => {
        await client.post(`/addons/${offer.slug}/stop`);
        try {
          await client.post(`/addons/${offer.slug}/options`, { boot: 'manual' });
        } catch (e) {
          return `ok (stopped; could not disable autostart: ${e.message})`;
        }
        return 'ok';
      });
    }
  }

  if (!deps.keepWork) fs.rmSync(p.work, { recursive: true, force: true }); // keepWork: tests only
  fs.writeFileSync(p.state, 'done\n');
  fs.rmSync(p.offer, { force: true });
  return { ok: true, backupSlug: old.backupSlug, results };
}

module.exports = { apply };
