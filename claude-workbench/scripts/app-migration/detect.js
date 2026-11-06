'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { isApkName, isPipSpec } = require('./package-names');

const OLD_SLUG_SUFFIX = '_claude_terminal_pro';
// Options worth carrying over. use_persistent_claude/auto_update_claude_on_start
// are deliberately left out: off in the old app, they froze the Claude version.
// statusline and home_assistant_plugin exist under these names in ESJavadex's
// app (2.5.x, from which ours come); our own app before the rename never had
// them (n31).
const SETTING_KEYS = [
  'auto_launch_claude', 'dangerously_skip_permissions', 'tmux_mouse',
  'remote_control', 'remote_control_session_name',
  'statusline', 'home_assistant_plugin',
];

// ESJavadex's app calls its Remote Control switch enable_remote_control
// (a797b7c6) and starts the session as --remote-control 'Home Assistant'; our
// own app before the rename had remote_control (72fcb99c), which wins when an
// app has both. Mapped to our names, so the session keeps its name (n31).
function remoteControlFromEsjavadex(options, settings) {
  if ('remote_control' in options || typeof options.enable_remote_control !== 'boolean') return settings;
  const mapped = { remote_control: options.enable_remote_control };
  if (options.enable_remote_control) mapped.remote_control_session_name = 'Home Assistant';
  return { ...settings, ...mapped };
}

function readState(p) {
  try { return fs.readFileSync(p.state, 'utf8').trim(); } catch { return ''; }
}

// init_environment always creates ~/.claude (skills, commands), so its mere
// existence says nothing; a login or a project history does.
function hasOwnClaudeData(p) {
  if (fs.existsSync(path.join(p.home, '.claude', '.credentials.json'))) return true;
  const projects = path.join(p.home, '.claude', 'projects');
  return fs.existsSync(projects) && fs.readdirSync(projects).length > 0;
}

function listOption(value) {
  return Array.isArray(value)
    ? value.filter((v) => typeof v === 'string' && v.trim()).map((v) => v.trim())
    : [];
}

function pickOldApp(apps, selfSlug) {
  const candidates = apps.filter((a) => a.slug !== selfSlug && a.slug.endsWith(OLD_SLUG_SUFFIX));
  return candidates.find((a) => a.state === 'started') || candidates[0] || null;
}

// Nothing to offer: a leftover offer.json would make the terminal show the dialog.
function noOffer(p, reason) {
  fs.rmSync(p.offer, { force: true });
  return { offered: false, reason };
}

async function detect(client, p) {
  // An apply killed mid-way (container restart, closed terminal) leaves the
  // unpacked backup behind, old login included. detect runs at startup, before
  // any dialog/apply, so nothing can be using it now.
  fs.rmSync(p.work, { recursive: true, force: true });
  if (['done', 'never'].includes(readState(p))) return noOffer(p, 'state');
  if (hasOwnClaudeData(p)) return noOffer(p, 'own-data');

  const self = await client.get('/addons/self/info');
  const { addons = [] } = await client.get('/addons');
  const old = pickOldApp(addons, self.slug);
  if (!old) return noOffer(p, 'no-old-app');

  const info = await client.get(`/addons/${old.slug}/info`);
  const options = info.options || {};
  const offer = {
    slug: old.slug,
    name: info.name || old.name || old.slug,
    version: info.version || old.version || '',
    // info.repository is the store's repository hash; url is the app's homepage.
    repository: info.url || info.repository || '',
    // Only real package names (n30): the dialog shows nothing that would be
    // skipped, apply checks again (venv names, offers from older versions).
    apk: listOption(options.persistent_apk_packages).filter(isApkName),
    pip: listOption(options.persistent_pip_packages).filter(isPipSpec),
    settings: remoteControlFromEsjavadex(options,
      // null: the Supervisor would refuse it for our schema, failing the step.
      Object.fromEntries(SETTING_KEYS.filter((k) => k in options && options[k] !== null).map((k) => [k, options[k]]))),
  };
  fs.mkdirSync(p.dir, { recursive: true });
  // Atomic: the terminal must never read a half-written offer.
  const tmp = `${p.offer}.tmp`;
  fs.writeFileSync(tmp, `${JSON.stringify(offer, null, 2)}\n`);
  fs.renameSync(tmp, p.offer);
  return { offered: true, offer };
}

module.exports = { detect, hasOwnClaudeData, SETTING_KEYS };
