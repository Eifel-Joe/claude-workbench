# Changelog

## 3.5.0

### ✨ New Feature - Key bar for phones
- **Esc, ↑, ↓, ↵, ⇧Tab and ^C** in a row above the on-screen keyboard, on
  touch devices only: cancel a reply, move through Claude's menus and
  questions, switch the mode with Shift+Tab, stop a command in the shell
  (mattbsea, mattbsea's heytcass fork, commit `ed215953`; weiting-tw
  `fe0a4ec9`; marcjay `f6674b77`).
- **The keyboard stays open** while you tap the keys.
- **^C is guarded**: a second ^C within two seconds is not sent, because two
  in a row quit Claude Code and end the session.

## 3.4.1

### 🐛 Bug Fix - Auto-continue waited a day for a reset that had just passed
- **A limit message first seen after its reset time** - auto-continue
  switched on late, or the reset fell between two checks - was planned for
  the same time the next day. A reset time more than 12 hours ahead now
  counts as just passed, so `continue` follows one minute later (Claude's
  5-hour limit never resets further ahead). Found on the test instance with
  3.4.0, which was not released on its own.

## 3.4.0

### ✨ New Feature - Auto-continue after a usage limit
- **Opt-in, off by default** (`auto_continue`): when Claude reports a usage
  limit ("5-hour limit reached ∙ resets 3pm"), the app types `continue` into
  the Claude session one minute after the reset, so a long task goes on
  unattended (mattbsea, mattbsea's heytcass fork, commits `16847c88`,
  `533ae0ef`, `5924cd08`, `00e22fc0` - his message parser is used as is;
  the app only counts messages at the start of a line).
- **Switch it at runtime** with the new ⏩ button in the panel header (shows
  off/on and the planned time) or `auto-continue on|off|status` in the
  terminal; after a restart the option applies again.
- **Only where it is safe**: it types into a pane of the `claude` session
  only if Claude is the foreground program there, the limit message is
  still on screen and it is Claude's own message at the start of a line
  (an answer that mentions "rate limit reached" mid-line does not count),
  never twice for the same message.

### ✨ New Feature - Shift+Enter inserts a newline
- **Shift+Enter** no longer submits in the panel: it inserts a line break in
  Claude's input (backslash + Enter, which Claude Code understands in any
  terminal) (mattbsea, mattbsea's heytcass fork, commit `6e44e41f`).

## 3.3.0

### ✨ New Feature - `claude-doctor`
- **The health check is now a terminal command**: `claude-doctor` runs the
  same checks the app runs on every start — memory, disk, Node.js, Claude
  Code, CPU and network — and sums up the failures (owine,
  owine/claude-terminal-home-assistant `cc0d74e7`).

### ✨ New Feature - Own tmux settings
- **`~/.tmux.conf.local`** is loaded last, so it overrides the app's tmux
  defaults and survives restarts and updates; `~/.tmux.conf` itself is still
  rewritten on every start (owine, owine/claude-terminal-home-assistant
  `1175851a`; also BartBourgeois and Maheidem).
- **Focus events** are passed on, so Claude Code and vim notice when the
  terminal gains or loses focus (owine `1e0a33e2`).

### 🐛 Bug Fix - Health check tells whether Claude Code really starts
- It checked only that `claude` exists and is executable, so a binary that
  cannot start (library mismatch, CPU without x86-64-v2) got a green tick. It
  now runs `claude --version` under a 10 s limit and shows the real error; on
  a CPU that cannot run Claude it says so instead of waiting. The "Attempting
  to install" line, which never installed anything, now points at a restart
  (umrath, heytcass/home-assistant-addons `ff4ebec`; owine `cc0d74e7`).
- Node.js and npm are checked the same way; a broken `node` used to log
  "Node.js installed:  ✓".
- On start the check now runs after the persistent Claude Code is set up, so
  it tests the binary the session uses.

### 🐛 Bug Fix - No stale panel files after an update
- The panel's files are served with `Cache-Control: no-cache`, so a browser
  cannot combine an old script with the new page after an update (owine
  `67dd7e55`).

### 📚 Documentation - Who can open the panel
- The README's security section said "Version 1.0.2 includes …". It now
  states that every signed-in Home Assistant user can open the panel —
  `panel_admin` only hides the sidebar entry — and what is behind it, with
  sources (umrath, heytcass/home-assistant-addons `8e65403`). DOCS has a
  short version; the volume list names `/addon_configs` instead of `/addons`.

### 🔧 Technical - CI runners pinned
- The workflows run on `ubuntu-24.04` instead of `ubuntu-latest`, which
  becomes Ubuntu 26 on 2026-10-19.

## 3.2.0

### ✨ New Feature - Old pasted images are cleaned up
- **New option `image_retention_days`** (default 30, up to 3650, `0` keeps
  everything): images pasted or dropped into the panel land in `/data/images`,
  which is part of every backup of the app, and nothing ever removed them. On
  start the app now deletes its own pasted images older than that — so the
  first start after this update removes those older than 30 days (owine,
  owine/claude-terminal-home-assistant#380; also suggested by msvinth and
  mattbsea).

### 🐛 Bug Fix - Panel answers while the app is still starting
- The panel only came up after the startup health check (whose network probes
  can take up to 45 s when offline), Claude Code's update and the package
  installs; until then Home Assistant showed a bare 502 (23 s on a real
  install). It now comes up before all of these, and the terminal shows
  "Claude Workbench is starting…" until it is ready (owine,
  owine/claude-terminal-home-assistant#380).

### 🐛 Bug Fix - Health check runs every check
- The startup health check stopped at the first failing check, so the rest of
  the diagnosis and the summary were missing from the log (owine,
  owine/claude-terminal-home-assistant#374).

### 🐛 Bug Fix - Shipped commands and skills stay current
- The `/install`, `/install-python` and `/list-packages` commands and the
  persistent-package skill were only copied into a new install, so existing
  installs never got updates. They are now refreshed on every start, which
  overwrites edits to these four files; everything else in `~/.claude` (your
  own commands and skills, logins, settings) stays untouched.

### 🔒 Security - Safer upload names, no leftover login code
- Uploaded images get their extension from the image type, not from the file
  name the browser sends; that name ended up in the path pasted into the
  terminal. A rejected file type now answers 400 instead of 500 (owine,
  owine/claude-terminal-home-assistant#379).
- The authentication helper no longer leaves the login code in
  `/tmp/claude-auth-code`, and removes `/config/auth-code.txt` before Claude
  starts rather than after (owine, owine/claude-terminal-home-assistant@96ccd0d).

## 3.1.3

### 🛠️ Improvement - Smaller backups: npm's cache no longer lives in /data
- npm kept its download cache in `/data/home/.npm` (about 115 MB), so it went
  into every backup of the app — including the one Home Assistant makes before
  each app update. It now lives in `/tmp/npm-cache` and is gone after a
  restart; the old folder is removed once on start (heytcass,
  heytcass/home-assistant-addons#105).
- Trade-off: with `auto_update_claude_on_start` (on by default), every start now downloads
  Claude Code again (about 113 MB, about 16 s longer start, measured), even
  without a new version.

### 🔒 Security - No access to Home Assistant's password check
- Dropped the `auth_api` permission. It only lets an app check Home Assistant
  usernames and passwords, which Claude Workbench never does (heytcass,
  heytcass/home-assistant-addons@3a6ee0d).

## 3.1.2

### 🐛 Bug Fix - Update menu no longer claims "up to date" without knowing
- With `use_persistent_claude`, the session menu's **🔄 Update Claude Code**
  item showed the latest release as "up to date" whenever the installed
  version was unknown: on a CPU without x86-64-v2 (where the app does not run
  Claude to ask) or when the binary was missing. It now says the installed
  version was not checked on this CPU, or is unknown.

## 3.1.1

### 🐛 Bug Fix - Clear message instead of a silent hang on older virtual CPUs
- Claude Code needs an x86-64-v2 CPU (SSE4.2, POPCNT). On a Proxmox VM with
  CPU type `kvm64` it hung without a word. The app now checks the CPU: the log
  and the terminal say what is missing and how to fix it (CPU type `host` or
  `x86-64-v2-AES`), and the session menu (including the auth helper) no
  longer hangs. With `use_persistent_claude` the start no longer waits 15 s
  for a hung version check and then wrongly tells you to reinstall. Verified:
  Claude Code runs on `x86-64-v2-AES` without AVX/AVX2.

### 📚 Documentation
- Troubleshooting no longer suggests `node /usr/local/bin/claude -i`, which
  does not work with the native Claude binary.

## 3.1.0

### ✨ New Feature - Every option explained
- The app's Configuration tab shows a name and a short explanation for each
  option, in English and German, instead of bare names like `tmux_mouse`.

### 🐛 Bug Fix - No more warnings in the logs
- **App log**: the image service no longer logs `DEP0060 util._extend`. It
  came from `http-proxy`, unmaintained since 2020, pulled in by
  `http-proxy-middleware` 2; version 4 uses `httpxy` instead.
- **Supervisor log**: no more "uses deprecated map option 'config'". The Home
  Assistant configuration is mapped as `homeassistant_config`, still at
  `/config`, so nothing changes in the terminal.

### 🐛 Bug Fix - Terminal panel no longer dies on a dropped connection
- When ttyd dropped a connection after it had started answering, the image
  service crashed (`ERR_HTTP_HEADERS_SENT`) and the panel stayed blank until
  the app was restarted. It now just closes that one response.

## 3.0.0

### ✨ New Feature - Claude Terminal Pro is now Claude Workbench
- **Own name, slug and repository**: the app is called Claude Workbench
  (slug `claude_workbench`) and lives in `Eifel-Joe/claude-workbench`, so it
  is no longer mistaken for ESJavadex's Claude Terminal Pro. New logo: the
  Claude spark and a `>_` prompt in a terminal window.
- **Breaking**: Home Assistant treats it as a new app. Install Claude Workbench
  next to the old app; on the first panel open it takes over memories,
  `CLAUDE.md`, history, logins, packages and settings from any
  `*_claude_terminal_pro` app (ESJavadex's or this project's before 3.0.0).
  Then uninstall the old app and remove the old repository entry. Install the
  Claude Workbench whose app page address ends in `0e003122_claude_workbench`
  (the new repository); the old entry lists it too, through GitHub's redirect.

### 📚 Documentation
- README and store docs describe Claude Workbench as an app of its own, with
  credits to Javier Santos (Claude Terminal Pro) and Tom Cassady (Claude
  Terminal) and a trademark note.
- LICENSE names its copyright holders instead of a template placeholder.
- `PERSISTENT_PACKAGES.md` no longer suggests editing an `options.json` that
  does not exist; options are set in the app's Configuration tab.

### 🔧 Technical
- App folder renamed to `claude-workbench/`; `tools/make-logo.py` rebuilds
  icon and logo.

## 2.3.4

### 🐛 Bug Fix - HA CLI and GitHub CLI lookups no longer hit GitHub's API limit
- The image build and `persist-install --ha-cli` asked GitHub's REST API for
  the latest release. Without a token it allows 60 requests per hour per IP,
  and a build failed with 403. They now read the version from where
  `github.com/<repo>/releases/latest` redirects to, which has no such limit.
  If that redirect does not end in a release tag, nothing is downloaded: the
  image build stops with an error, and `persist-install` keeps an existing
  copy.

### 🛠️ Improvement - Mac clipboard monitor removed
- `mac-clipboard-monitor.py` uploaded to `<host>:8123/upload`, which is Home
  Assistant itself, or to the direct port closed in 2.1.0, so it could not
  reach the app. Paste (Ctrl+V / Cmd+V) or drop an image into the terminal
  instead; it lands in `/data/images` the same way.

### 🔧 Technical
- The migration tests remove their temporary directories.
- `DEVELOPMENT.md` suggests another host port instead of `sudo kill -9` when
  7680 is busy.

## 2.3.3

### 🐛 Bug Fix - `persist-install --ha-cli` said "Nothing to do" over an active old copy
- Because the image ships `ha`, `persist-install --ha-cli` (without `--force`)
  stopped with "Nothing to do" even when a copy in `/data/packages/bin` - such
  as the 4.46.0 an earlier `--force` installed - takes priority in PATH.
- It now names that copy with its version (or "unknown version, installed
  before 2.3.1") and shows both ways out: `persist-install --ha-cli --force`
  for the latest release, or `rm` to use the image's CLI.

## 2.3.2

### 🐛 Bug Fix - `persist-install --ha-cli` printed an error instead of a version
- The `ha` CLI has no `--version` flag (neither 4.x nor 5.x), so after an
  install, and when reporting an existing copy, it showed
  `Error: unknown flag: --version` and the usage text.
- The install now records the version it downloaded in
  `/data/packages/bin/.ha-version` and shows it; an existing copy without that
  record is reported as `unknown (installed before 2.3.1)`, which hints at the
  old pinned 4.46.0. The post-install check runs `ha help`, which works
  offline.

## 2.3.1

### 🐛 Bug Fix - `persist-install --ha-cli --force` installed an old HA CLI
- It always installed version 4.46.0, a pin meant for 32-bit builds, on every
  architecture (the current release is 5.x). That copy lives in
  `/data/packages/bin`, ahead of the image's newer `ha` in PATH, so it silently
  downgraded the CLI. It now installs the latest release, like the image build,
  and stops with an error if the version lookup fails.
- `--force` now replaces an existing copy (it used to keep it and report
  "already installed"); a failed download leaves the existing copy in place.
  If you used `--force` before, run `persist-install --ha-cli --force` again to
  get the latest release, or remove the copy with `rm /data/packages/bin/ha` to
  use the one shipped in the image.

### 🔧 Technical - Cleanup after dropping armv7
- Removed the remaining 32-bit branches at runtime (Claude Code 1.0.128 pin)
  and the unused `install-ha-cli.sh` (pinned HA CLI 4.42.0).
- CI: actions moved to their Node 24 releases, test suites run on Node 22 like
  the image.

## 2.3.0

### 🔧 Technical - Build parameters moved into the Dockerfile
- The Supervisor warned on every install and update that `build.yaml` is
  deprecated and will stop reading it. The Dockerfile now names the base image
  (`ghcr.io/home-assistant/base:3.21`, multi-arch) and the image labels itself;
  `build.yaml` is gone. Nothing changes in how the app runs.

### 🔧 Technical - armv7 is no longer built (breaking for 32-bit systems)
- Home Assistant ended support for 32-bit systems with 2025.12; the Supervisor
  there no longer offers app updates, and the new base image has no armv7
  variant. 2.2.2 stays the last release for armv7; existing installations keep
  running on it.
- The pinned 32-bit tool versions (Claude Code 1.0.128, HA CLI 4.46.0, gh armv6)
  are removed from the image build.

### 📚 Documentation
- The development guide and project notes build without a base-image argument
  and keep test credentials under `/data`, where the app reads them. They no
  longer suggest an `options.json` for local runs: bashio reads options from the
  Supervisor API, so a run without the Supervisor uses the defaults.
  The stale `DEVELOPMENT_STATUS.md` and an unlinked old copy of `DOCS.md` are
  removed.

## 2.2.2

### 🐛 Bug Fix - A hung download could keep the panel blank
- Before the terminal starts, the app updates Claude Code (on by default) and
  installs the packages from `persistent_apk_packages` / `persistent_pip_packages`.
  None of these had a time limit, so a stuck npm registry or package mirror left
  the panel blank with nothing in the log saying why.
- They now give up and log `… timed out after Ns`: 300 s for the Claude Code
  update and for each apk package, 900 s for the pip install (a Pi may compile
  packages on first install). The app then starts as usual, with the built-in
  Claude Code if the update did not finish.
- The image now ships GNU `coreutils`: BusyBox `timeout` stops only the process it
  started, so a stuck `apk add` behind `persist-install` would have kept running
  and locked the package database for every later package.
- If the Claude Code update keeps failing after a cut-off, the log now says how
  to recover: delete `/data/npm` and restart the app to reinstall.
- The rarely used fallback that installs tools missing from the image (ttyd,
  tmux, jq, curl) has the same 300 s limit; it fails the start, so the watchdog
  restarts the app instead of it hanging.

### 📚 Documentation
- The app description said credentials are stored in `/config/claude-config/`.
  They are in the app's private `/data` (`/data/home/.claude`), as the
  documentation already said.

## 2.2.1

### 🐛 Bug Fix - Clicking a wrapped link opened only part of it
- Claude Code and tmux break a long URL (such as the login link) across rows. The
  terminal's built-in link detection only joins rows it wrapped itself, so a click
  on the first row opened a cut-off URL and the other rows were not clickable.
- Every row of such a link is now clickable and opens the full URL, rebuilt the
  same way **🔗 Copy link** rebuilds it. Not with `tmux_mouse` enabled (clicks go to
  tmux then) and not by tapping on a phone - use **🔗 Copy link** there.

## 2.2.0

### ✨ New Feature - Switch from another Claude Terminal Pro app in one step
- On first start the app looks for another installed Claude Terminal Pro app (for
  example the ESJavadex original). When you open the panel, a window offers to take
  over Claude data (memories, `CLAUDE.md`, history, settings), the Claude and GitHub
  logins, packages (reinstalled, not copied; only explicitly installed pip packages,
  all packages if the old pip did not mark them) and app settings, and to stop the
  old app and disable its autostart (both apps share one Claude login, which a
  restarted old app could refresh).
- Works through a partial backup of the old app, created via the Supervisor API
  (progress is shown while it runs) and kept as a fallback; apart from being stopped
  (if chosen), the old app is never modified. The backup includes the old app's
  image (several hundred MB) and the old login - delete it under Settings → System →
  Backups once you no longer need it. If any item fails, the old app is not
  stopped. Nothing that already exists in this app is overwritten.

### 🐛 Bug Fix - persist-install reported failed Python installs as success
- `persist-install --python` did not check for errors and ended with an `echo`, so it
  always exited 0. Failed packages looked installed, also during the automatic
  package installation at startup.
- It now exits non-zero with a ❌ message when installing python3, creating or
  activating the venv, or `pip install` fails.

### 📝 Wording
- "Add-on" is now "app" throughout, as in Home Assistant since 2026.

## 2.1.0

> **First release from [Eifel-Joe/claude-code-ha](https://github.com/Eifel-Joe/claude-code-ha).**
> Upstream (ESJavadex) had been inactive for months; this release collects the
> fixes published in its community forks. Each entry names where it came from.

### ✨ New models: keep Claude Code current (Fable, Opus 5, Opus 5.5, …)
New models need a newer Claude Code CLI, and the add-on was stuck on whatever
version was current when its image was first built.
- **The persistent Claude override now actually runs** (marcjay). `use_persistent_claude`
  + `auto_update_claude_on_start` installed a fresh Claude Code into `/data/npm`, but
  `$HOME/.local/bin/claude` (the baked binary) came first on `PATH`, so the old
  version kept starting. Both links are now replaced.
- **Auto-launch and the version line use the persistent binary** (nsleigh).
- **New menu item "🔄 Update Claude Code"** in the session picker, showing installed vs.
  latest version (nsleigh). Shown when `use_persistent_claude` is enabled. Also
  relinks the native path, so `claude` in the bash shell gets the new version too.
- **`use_persistent_claude` and `auto_update_claude_on_start` now default to `true`**,
  so every start pulls the latest Claude Code. Set them to `false` to stay on the
  version baked into the image.

### 🐛 Bug Fix - Rebuilding the add-on hung forever
- The official `install.sh` ends with `claude install`, an interactive TUI that never
  finishes in a Docker build. The build sat at *"Setting up Claude Code..."* and the
  npm fallback never ran (ESJavadex/claude-code-ha#44). The installer now times out
  after 300 s and the npm fallback takes over; a half-installed binary is removed first.

### ✨ New Feature - Remote Control
- **`remote_control`** and **`remote_control_session_name`** options start the
  auto-launched session with `--remote-control`, so it can be driven from
  claude.ai/code or the Claude mobile app (martinboksa, ESJavadex/claude-code-ha#28).

### ✨ New Feature - Access to other apps' configuration
- **`all_app_configs:rw`** is mapped, giving Claude access to the config folders of
  AppDaemon, Node-RED, ESPHome and other apps (requested in ESJavadex/claude-code-ha#9, #11).

### 🐛 Bug Fix - Image and text paste inside the terminal
- Paste handlers now run inside the ttyd iframe, Ctrl+V no longer reaches xterm as
  `^V` ("No image found in clipboard"), and uploaded image paths are inserted with
  `term.paste()` instead of overwriting the clipboard (nsleigh).

### 🔒 Security - The add-on no longer publishes a root shell on your LAN (Moulbi)
- **Breaking, and deliberate: no host ports are published any more.** `config.yaml`
  mapped `7680` and `7681` to the host. Home Assistant publishes declared ports by
  default, and `ttyd` runs `--writable` with no credentials, so anyone who could
  reach `http://<home-assistant>:7681` got an unauthenticated **root shell** in a
  container holding `/config` read-write, `hassio_role: manager`, the Home
  Assistant API and `SUPERVISOR_TOKEN`. Ingress authentication was simply bypassed.
  - Ingress reaches the container over the internal Docker network and needs no
    host port, so nothing legitimate is lost.
  - **If you were opening the add-on by IP and port, use the sidebar panel instead.**
- **ttyd now binds `127.0.0.1`** instead of `0.0.0.0`. Its only legitimate consumer
  is the image service, which proxies `/terminal` over the loopback.
- **Local add-on state is no longer tracked in git** (`config/claude-config/`,
  `config/options.json`). That directory is where Claude and `gh` drop credential
  files, and nothing stopped one from being committed.
- **Dependencies**: `multer` 1.x (deprecated, known DoS advisories) upgraded to 2.x,
  and `qs` pinned to a patched release. `npm audit` is clean, with no major
  framework upgrade.

### 🐛 Bug Fix - The image service health check was always green
- **`$!` after a pipeline is the wrong PID.** The service was started as
  `node ... | while read`, and `$!` captured the logging loop, not node. The
  `kill -0` readiness probe therefore passed unconditionally: *"Image service is
  running successfully"* was logged even when the service had already died.
  Readiness is now proven by an actual `/health` response.
- **The image service is now supervised and restarted** with capped backoff.
  Previously, if it died the ingress panel went blank until a manual restart,
  because it serves the entry point and proxies the terminal.

### 🐛 Bug Fix - Credential migration never migrated credentials, then overwrote them
- **Hidden files were skipped.** The migration copied `"$legacy_path"/*`, a glob
  that does not match dotfiles — so it skipped exactly the files it exists for
  (`.credentials.json`, `.claude.json`). It now copies `"$legacy_path/."`.
- **Fixing that glob alone would have been worse than the bug.** Correctly copying
  dotfiles would, once, overwrite working credentials in `/data` with the stale
  copy in `/config`. Migration now runs with `cp -a -n`: it only fills in files
  that are missing, which is all a migration should ever do.
- **It ran on every start.** Described as one-time in a comment but not in code, it
  re-copied legacy files over `/data` at each boot, letting a stale file left in
  `/config` overwrite freshly obtained credentials. It now records a marker in
  `/data` and runs exactly once.

### 🐛 Bug Fix - A WebSocket arriving first was never proxied
- `http-proxy-middleware` only subscribes to `upgrade` lazily, on the first HTTP
  request through the middleware. A terminal reconnect that opened with the
  WebSocket handshake hung until timeout. The server now subscribes explicitly.

### 🛠️ Improvement - Startup no longer depends on the Alpine mirrors
- **`ttyd` and `tmux` are baked into the image.** `run.sh` ran an unconditional
  `apk add ttyd jq curl tmux` on *every* container start, with `exit 1` on failure:
  the add-on refused to start whenever the mirrors were unreachable, and paid the
  download on each boot. `jq` and `curl` were already in the image and were being
  re-fetched for nothing. The runtime `apk` path remains only as a fallback for
  images built before this change.

### 🛠️ Improvement - `persist-install`
- **`--ha-cli` no longer downgrades the bundled CLI.** It installed a hardcoded
  `4.42.0` into `/data/packages/bin`, which comes *first* in `PATH` and therefore
  shadowed the newer `ha` shipped in the image. It now detects the bundled CLI and
  declines, with `--force` as an escape hatch.
- **A failed `apk add` no longer killed the caller's shell** (`exit 1` → `return 1`).
- **Honest limits**: installing system packages now states that only executables and
  shared libraries are copied, so packages needing data files may not survive a
  restart from the persistent copy alone.

### 🔧 Technical - Tests and CI
- **Continuous integration added.** Nothing ran the existing test suite; the only
  workflow was the `@claude` mention handler. Pull requests and pushes now run
  shellcheck, hadolint, the shell suites, the Node suite and a real image build.
- **The image service has tests for the first time** (9 cases): health, config,
  upload, rejection of non-image payloads, hostile filenames, the HTTP proxy and
  the WebSocket upgrade — including the first-request upgrade regression above.
- **Regression tests for every fix in this release**: tool installation, migration
  idempotence, dotfile migration, and readiness probing.
- **Release metadata is enforced**: `config.yaml`, `build.yaml` and `CHANGELOG.md`
  must agree on the version, every declared architecture must have a base image,
  and the security invariants above are asserted in CI.
- **Dead code removed.** `scripts/persistent-packages.sh` (201 lines) was never
  called by `run.sh`, which carries its own copy of those functions — yet half the
  test suite exercised only that dead file. Its real equivalent in `run.sh` is
  already covered by `test-production-run.sh`.
- **Reproducible dependency installs**: `package-lock.json` is now committed and the
  image builds with `npm ci`, so two images tagged with the same version contain the
  same dependency tree.

### 🐛 Bug Fix - Copying out of the terminal did nothing (#30)
- **Mouse selection now really reaches the clipboard.** ttyd 1.7.7 — the newest
  release, and the one Alpine 3.21 ships — copies a selection with
  `document.execCommand('copy')`. xterm.js keeps its selection internally and
  paints it on a canvas, so there is no DOM selection to copy: the call was a
  no-op, yet ttyd showed its `✂` overlay every time. Selections are now read with
  `terminal.getSelection()` and written with `navigator.clipboard.writeText()`,
  falling back to a hidden textarea where that API does not exist.
- **`/copy` works.** ttyd 1.7.7 loads no clipboard addon, so the OSC 52 sequence
  Claude Code emits was silently discarded. The add-on now registers its own
  OSC 52 handler on ttyd's terminal, sharing the same clipboard writer.
- **tmux forwards OSC 52.** `set -g set-clipboard on` replaces tmux's default
  `external`, which drops what applications in the pane send, and
  `set -as terminal-features ',*:clipboard'` makes tmux emit the sequence outwards
  without depending on `$TERM`'s terminfo carrying `Ms`.
- **The `✂` overlay is now honest** — it appears only after the clipboard write
  actually succeeded, instead of on every selection.
- **No ttyd fork and no frontend rebuild.** ttyd exports its xterm.js instance as
  `window.term` and is already proxied same-origin at `/terminal/`, so the fix is
  one vanilla-JS file, `image-service/public/terminal-clipboard.js`. Upgrading ttyd
  would not have helped: 1.7.7 is the latest release and still has both bugs.

### ✨ New Feature - Copying on a phone
- **`📋 Copy` button and dialog.** xterm.js registers no touch handlers in its
  selection service and paints to a canvas, so a finger can select nothing in the
  terminal at all — on a phone there was no way to copy anything. The button reads
  the text out of the xterm.js buffer into a textarea, where a long-press gives
  the native selection handles, with a one-tap "Copy all" and a
  visible-screen/full-scrollback switch.
- **`🔗 Copy link` appears by itself when a link is on screen.** Copying an OAuth
  login URL is one tap, no selecting. It names the host it copied, since a phone
  has no hover to check with.
- **Split links are put back together.** A link that the terminal broke across
  rows used to be copied as whatever fitted on one row. Rebuilding it needs the
  row geometry, and three different splits were measured live in this add-on's
  own terminal, each leaving a different trace:
  - a hard wrap fills the row and re-indents the remainder, so joining rows
    verbatim drops the indent into the middle of the URL;
  - Claude Code's renderer breaks a long URL at a `/` when the next segment would
    not fit, leaving a row that is *not* full;
  - and it lays its output out one column short of the pane, so any rule keyed on
    the pane width never fires. The wrap column is now measured from the rows
    themselves rather than assumed.
- **A cut-off link is refused, not copied.** Trailing `…`, a cut percent-escape,
  a dangling `?`/`&`/`=`, or a link still running at the edge of the rows read all
  mean "widen the search, then say it is cut off" — pasting half a URL fails with
  nothing on screen explaining why.
- **Swiping scrolls the terminal.** xterm.js 5.5 drops `touchstart`/`touchmove`
  outright while the application has mouse reporting on, and never turns touch
  into a mouse report — so on a phone or a touch PC the history could not be
  scrolled at all. The wheel has its own code path, which is why a mouse always
  worked. Swipes are now translated into wheel events, so xterm.js encodes them
  exactly as it would a real wheel. Vertical is claimed only once a full row of
  movement has built up; pinch-zoom and horizontal panning stay with the browser.
  A swipe is ignored when the buffer has no scrollback: xterm.js turns a wheel
  event into arrow keys there and sends them as *input*, so under tmux every
  swipe walked Claude Code's message history into the prompt. Scrolling a
  full-screen app needs real mouse reporting — turn on the `tmux_mouse` option.
- **The on-screen keyboard no longer covers the prompt.** It shrinks the visual
  viewport but leaves `100vh` alone, so the terminal kept its full height and its
  bottom rows — where you type — sat behind the keyboard. The page follows
  `visualViewport` instead, which makes ttyd refit to what is actually visible.


### 🔧 Technical
- Header buttons have a fixed height and a separately sized icon. Emoji sit on a
  larger em box than the label text, so each button was taking its height and
  width from its own glyph and the row came out ragged.
- Plain-HTTP limitation documented in `DOCS.md`: `navigator.clipboard` is a
  secure-context API, so over `http://homeassistant.local:8123` the fallback needs
  a user gesture. Every button tap is one; an OSC 52 sequence arriving from the
  terminal is not, so `/copy` is refused there and the page says so in words and
  points at `📋`. Serving Home Assistant over HTTPS enables it.
- OSC 52 *read* requests are swallowed instead of answered, so a program running
  in the terminal cannot read the host clipboard.
- New regression coverage: 72 Node tests for the clipboard bridge
  (`tests/test-terminal-clipboard.js`, wired into `tests/run-tests.sh`) plus tmux
  clipboard assertions in `tests/test-production-run.sh`. The link-rebuilding
  fixtures are the literal rows captured from a running terminal.

## 2.0.13

### Bug fixes
- Disabled tmux mouse capture by default so browser paste, including OAuth codes, is reliable; added the `tmux_mouse` option for users who want it (#26).
- Fixed configured APK and pip package installation by handling Bashio's newline-separated list output directly instead of parsing it as JSON (#25).
- Updated persistent Claude detection for current npm releases, which provide `bin/claude` instead of the removed `cli.js` entry point (#21).
- Restored ARMv7 builds after upstream asset changes: Claude Code uses the final portable JavaScript release (`1.0.128`), HA CLI stays on the last release that still ships the ARMv7 asset (`4.46.0`), and GitHub CLI uses its ARMv6-compatible binary pinned to a version verified to publish it. The 64-bit builds continue using current native releases.
- Fixed the architecture detection at the root: the Dockerfile now resolves the target from Home Assistant's `BUILD_ARCH` build argument (falling back to BuildKit's `TARGETARCH`/`TARGETVARIANT` and finally `uname`). The previous `TARGETARCH = "arm/v7"` check never matched — BuildKit reports 32-bit ARM as `TARGETARCH=arm` with `TARGETVARIANT=v7` — so ARMv7 builds silently fell through to the "unsupported architecture" error and the Claude version pin was ignored.
- Persistent Claude overrides are now activated only after the installed binary passes a version check (run under a `timeout` so a hung `--version` cannot block startup); 32-bit ARM startup updates stay on the portable release instead of replacing it with an unsupported native wrapper.

## 2.0.12

### 🐛 Bug Fix - Claude Code ≥2.1.181 crashes with `statx: symbol not found`
- **Bumped base image from Alpine 3.19 to Alpine 3.21** (musl 1.2.4 → musl 1.2.5)
  - Claude Code's native Bun binary began referencing the `statx` libc wrapper at
    v2.1.181. musl only added this wrapper in 1.2.5 (Alpine 3.20+); Alpine 3.19
    (musl 1.2.4) does not export it, causing every version ≥2.1.181 to fail at
    dynamic-link time with `Error relocating … statx: symbol not found` (exit 127).
  - The host Linux kernel has had the `statx` *syscall* since 4.11; only the
    userspace musl wrapper was missing.
  - With musl 1.2.5 present, Claude Code ≥2.1.181 (and the current latest) loads
    and runs correctly.
- **Note on AVX2**: The crash was a linker error, **not** a CPU instruction issue.
  The existing 2.1.179 binary already runs on non-AVX2 hardware (e.g. AMD GX-415).


## 2.0.11

### ✨ New Feature - Optional Persistent Claude Code Override
- **Safe-by-default persistent Claude support**: Added optional `use_persistent_claude` mode that lets advanced users run a Claude Code version installed under `/data/npm/`
  - **Default remains unchanged**: the add-on still uses the Claude version baked into the image unless explicitly enabled
  - **Official startup-managed symlink**: `/usr/local/bin/claude` now points to the persistent install during startup when present
  - **No self-modifying menu scripts**: persistent override is handled in `run.sh`, keeping behavior deterministic and easier to support
- **Optional startup updates**: Added `auto_update_claude_on_start` (default: `false`)
  - When enabled together with `use_persistent_claude`, the add-on runs `npm install -g @anthropic-ai/claude-code@latest` into `/data/npm/` at startup
  - If the update fails, startup continues and uses the previously installed persistent version when available
- **Session picker version visibility**: Interactive menu now shows the active Claude Code version at the top

## 2.0.10

### 🐛 Bug Fix - CPU Compatibility with AVX Fallback
- **Native installer with automatic npm fallback**: Fixed Docker build failure on CPUs without AVX support (#5)
  - **How it works**: Tries native installer first (Bun-based, recommended by Anthropic); if it fails (e.g., CPU lacks AVX), automatically falls back to npm installation
  - **Affected hardware**: Older NUCs, Intel Atom/Celeron processors, some virtualized environments (Proxmox, VirtualBox on older hosts)
  - **Modern hardware**: No change — continues using the native installer as before
  - **Result**: Add-on now builds on all CPUs without sacrificing the recommended install method for capable hardware

## 2.0.9

### 🐛 Bug Fix - First Connection Drop on Terminal Load
- **Removed invalid ttyd client options**: `enableReconnect` and `reconnectInterval` are hterm options not supported by ttyd 1.7.4 (xterm.js-based), causing the WebSocket client to error and disconnect on first load
  - Kept only valid options: `--ping-interval 30` and `--client-option reconnect=5`
  - First connection now establishes cleanly without requiring a retry

## 2.0.8

### 🐛 Bug Fix - Image Service Crash on WebSocket Errors (#8)
- **Fixed `res.status is not a function` crash**: The proxy `onError` handler in `server.js` now checks whether `res` is an Express response (HTTP) or a raw socket (WebSocket) before calling `.status()`
  - Previously, WebSocket proxy errors crashed the entire image service process
  - Now gracefully handles both HTTP and WebSocket error scenarios

### 🐛 Bug Fix - Disable Auto-Update Nag Inside Container (#7)
- **Suppressed Claude CLI update prompts**: Set `DISABLE_AUTOUPDATER=1` in both runtime environment and profile script
  - Claude Code binary is baked into the container image; updates are delivered via add-on releases
  - Eliminates the persistent "update available" banner on every session start

### 🐛 Bug Fix - Session Reconnection After Disconnect (#6)
- **Fixed "Press return to reconnect" not working**: Removed `exec` from session picker launch functions so Claude exiting returns to the menu instead of terminating the process
  - When Claude CLI exits (via `/exit`, Escape, or crash), the session picker menu now reappears automatically
  - Bash shell sessions also return to menu on `exit`
  - Removed aggressive EXIT trap that was killing the session picker prematurely
- **Added ttyd keepalive and auto-reconnect**: Configured `--ping-interval 30` and client-side reconnect options to prevent WebSocket idle disconnects and automatically recover from network interruptions

## 2.0.7

### 🐛 Bug Fix - Native Install Path Mismatch
- **Fixed "installMethod is native, but directory does not exist" error**: Claude binary now available at `$HOME/.local/bin/claude` at runtime
  - **Root cause**: Native installer places Claude at `/root/.local/bin/claude` during Docker build, but at runtime `HOME=/data/home`, so Claude's self-check looks in `/data/home/.local/bin/claude` which didn't exist
  - **Solution**: Symlink created from `/data/home/.local/bin/claude` → `/root/.local/bin/claude` on startup
  - **PATH updated**: Added `/data/home/.local/bin` to PATH in both runtime and profile script
  - **Result**: Claude native binary resolves correctly regardless of HOME directory change

## 2.0.6

### 🛠️ Improvement - Native Claude Code Installation
- **Migrated to native installer**: Claude Code now installed using Anthropic's recommended native binary installer
  - Replaces npm installation (`@anthropic-ai/claude-code`) with `curl -fsSL https://claude.ai/install.sh | bash`
  - More reliable builds (no npm retry logic needed)
  - Follows Anthropic's official distribution method
  - npm installation is deprecated by Anthropic
- **Updated health checks**: Network connectivity now validates `claude.ai` instead of npm registry
- **Simplified run.sh**: Removed `node $(which claude)` wrapper, now calls `claude` directly

## 2.0.5

### 🐛 Bug Fix - Claude CLI Not Found
- **Fixed session picker failing to launch Claude**: Used full path `/usr/local/bin/claude`
  - ttyd bash sessions don't inherit full PATH from parent process
  - All claude invocations now use absolute path for reliability

## 2.0.4

### ✨ New Feature - GitHub CLI Pre-installed
- **GitHub CLI (gh) included**: GitHub's official CLI tool now pre-installed in Docker image
  - Create, view, and manage GitHub issues and pull requests
  - Work with GitHub repositories directly from the terminal
  - Authenticate with `gh auth login`
  - Essential for git workflows: `gh pr create`, `gh issue list`, `gh repo clone`
  - Automatically fetches latest version during build

### 🛠️ Improvement - Persistent GitHub Authentication
- **GitHub credentials survive reboots**: `GH_CONFIG_DIR` set to `/data/.config/gh`
  - Login once with `gh auth login`, credentials persist across container restarts
  - Consistent with Claude credential persistence approach
  - No need to re-authenticate after Home Assistant updates
- **Session picker menu option**: New "🐙 GitHub CLI login" option (choice 6)
  - Guided authentication flow with browser or token options
  - Shows current auth status before prompting
  - Instructions for creating GitHub personal access tokens

## 2.0.3

### ✨ New Features - Enhanced Developer Toolkit
- **Pre-installed Python libraries**: Common libraries for Home Assistant scripting
  - `py3-requests` - HTTP library for API calls
  - `py3-aiohttp` - Async HTTP client/server
  - `py3-yaml` - YAML parsing for HA configuration
  - `py3-beautifulsoup4` - HTML/XML parsing
- **Additional system tools**: More utilities available out-of-the-box
  - `vim` - Advanced text editor
  - `wget` - File download utility
  - `tree` - Directory tree visualization
  - `yq` - YAML processor (essential for Home Assistant configs)

### 📚 Documentation
- **Community Tools section**: Added links to community-built tools in README
  - Featured: `ha-ws-client-go` by @schoolboyqueue for WebSocket API access

### 🔗 PR Attribution
- Incorporates contributions from PR #1 (adapted to current codebase)

## 2.0.2

### 🐛 Bug Fix - Claude CLI Launch Failure
- **Fixed session picker dropping to Node.js REPL**: Claude Code CLI now launches correctly
  - **Root cause**: Scripts incorrectly used `node "$(which claude)"` which passes the claude binary path to Node.js as if it were a JS file to execute
  - **Symptom**: Selecting "New interactive session" showed `Welcome to Node.js v20.15.1` and `>` prompt instead of launching Claude
  - **Solution**: Changed all invocations to use `exec claude $flags` directly, since `claude` is already a properly wrapped executable
  - **Affected scripts**: `claude-session-picker.sh`, `claude-auth-helper.sh`
  - **Result**: All session picker options now correctly launch Claude Code CLI

## 2.0.1

### 🐛 Bug Fix - Build Error
- **Removed unpublished plugin from Dockerfile**: Fixed Docker build failure
  - Plugin `@ESJavadex/claude-homeassistant-plugins` not yet in registry
  - Plugins now recommended for manual installation
  - Build process works correctly again

## 2.0.0

### 🎉 Major Release - Enhanced Developer Experience

### ✨ New Features

- **Git Pre-installed**: Git version control included in base Docker image
  - No need to use `persist-install git` anymore
  - Available immediately on fresh installs
  - Enables version control workflows within the terminal

### 📦 Recommended Plugins

For an enhanced experience, manually install the Claude Home Assistant Plugins:

```bash
npx claude-plugins install @ESJavadex/claude-homeassistant-plugins/homeassistant-config
```

See [claude-homeassistant-plugins](https://github.com/ESJavadex/claude-homeassistant-plugins) for details.

## 1.7.1

### ✨ Improvement - Auto-Copy & Focus for Image Uploads
- **Streamlined image workflow**: Path automatically copied and terminal focused after upload
  - **Auto-copy to clipboard**: File path instantly copied when image uploaded
  - **Auto-focus terminal**: Terminal iframe automatically focused and ready
  - **Auto-paste attempt**: Tries to paste path directly (may be blocked by browser security)
  - **Clear status**: Shows "Ready to use! (path in clipboard)"
  - **Workflow**: Upload image → Press Cmd+V → Done!
  - **Fallback**: If auto-paste blocked, just press Cmd+V (clipboard already has path)

**How it works now**:
1. Paste/drag/upload an image
2. Path is automatically copied to clipboard
3. Terminal is automatically focused
4. Just press Cmd+V to paste the path
5. Ask Claude to analyze it!

This makes the image workflow nearly seamless - you don't need to click anything after uploading!

## 1.7.0

### ✨ New Feature - Voice Input with Web Speech API
- **Talk to Claude instead of typing**: Built-in speech-to-text using Chrome's Web Speech API
  - **Press-to-talk button**: Click 🎤 Voice Input button in header
  - **Real-time transcription**: See your speech converted to text as you speak
  - **Continuous recording**: Keeps listening until you stop
  - **Editable transcript**: Edit the transcribed text before copying
  - **Copy to clipboard**: One-click copy to paste into Claude Terminal
  - **Keyboard shortcuts**:
    - `Space` - Start/stop recording
    - `Enter` - Copy transcript
    - `Escape` - Close modal
  - **Error handling**: Clear messages for microphone issues, permissions, etc.
  - **No external services**: Uses browser's built-in speech recognition (Chrome, Edge, Safari)
  - **Perfect for**: Long questions, complex queries, hands-free operation

- **How to use**:
  1. Click 🎤 Voice Input button
  2. Click "Start Recording" and speak
  3. Click "Stop Recording" when done
  4. Edit text if needed
  5. Click "Copy Text"
  6. Paste into Claude Terminal!

**Browser support**: Chrome, Edge, Safari (requires microphone permissions)

## 1.6.6

### 🐛 Bug Fix - Clipboard API in Home Assistant Ingress
- **Fixed clipboard copy in iframe context**: Added fallback methods for copying file path
  - **Root cause**: `navigator.clipboard` API is blocked in Home Assistant ingress iframes
  - **Error**: "Cannot read properties of undefined (reading 'writeText')"
  - **Solution**: Multi-tier fallback approach:
    1. Try modern Clipboard API if available
    2. Fallback to `document.execCommand('copy')` with text selection
    3. Final fallback: Select text for manual Cmd+C copy
  - **User feedback**: Shows "✓ Copied!" or "✓ Selected! Press Cmd+C to copy"
  - **Result**: Path copying now works in all contexts (direct access, ingress, iframes)

**Technical note**: Browser security restrictions prevent clipboard access in cross-origin iframes. The new implementation uses progressive enhancement to provide the best experience available in each context.

## 1.6.5

### ✨ UX Improvement - Better Path Visibility for Manual Copy
- **Enhanced upload status display**: Full file path now shown prominently with click-to-copy functionality
  - **Previous**: Only showed filename ("Uploaded: pasted-123.png")
  - **Now**: Shows full path with icon ("📋 /data/images/pasted-123.png (click to copy)")
  - **Persistent display**: Path remains visible until next upload (no auto-hide)
  - **Click-to-copy**: Click the status text to copy path to clipboard
  - **Visual feedback**: Shows "✓ Copied to clipboard!" confirmation
  - **Fallback**: If clipboard API fails, shows error and allows manual selection
  - **User-friendly**: Hover effect and cursor pointer indicate clickability

This improvement addresses the issue where users couldn't easily see or copy the full file path to manually paste into Claude Code CLI.

## 1.6.4

### 🐛 Critical Fix - Home Assistant Ingress Compatibility
- **Fixed 404 errors and config loading failures**: Changed all paths to relative for ingress compatibility
  - **Root cause**: Absolute paths (`/config`, `/terminal/`, `/upload`) don't work with Home Assistant ingress
  - **Impact**: All API endpoints returned 404, terminal wouldn't load, uploads failed
  - **Solution**: Changed to relative paths (`config`, `terminal/`, `upload`)
  - **Why**: Home Assistant ingress adds path prefix `/api/hassio_ingress/TOKEN/` to all requests
  - **Result**: All features now work correctly through Home Assistant ingress

**Technical note**: This is a common Home Assistant add-on issue. When using ingress, all fetch calls and iframe sources must use relative paths (without leading `/`) to work correctly with the ingress path prefix.

## 1.6.3

### 🐛 Bug Fix - Image Service Startup Logging
- **Improved error visibility**: Node.js console output now shown directly in add-on logs
  - **Previous issue**: Errors were hidden in /var/log/image-service.log
  - **Solution**: Pipe Node.js stdout/stderr directly to add-on logs with `[Image Service]` prefix
  - **Added checks**: Verify server.js and node_modules exist before starting
  - **Auto-recovery**: Attempt `npm install` if node_modules is missing
  - **Result**: All startup errors now visible in `ha addons logs`

This will help diagnose why the image service isn't starting properly.

## 1.6.2

### 🐛 Critical Bug Fix - Express Route Order
- **Fixed 404 errors on API endpoints**: API routes now registered before static file middleware
  - **Root cause**: Static file middleware was placed before API routes in Express app
  - **Impact**: `/config` returned HTML instead of JSON, `/terminal` returned 404
  - **Solution**: Moved all API routes (/health, /config, /upload, /terminal) before static middleware
  - **Result**: All endpoints now work correctly

This is a common Express.js gotcha - middleware order matters! Static file middleware should come AFTER API routes to prevent it from intercepting API requests.

## 1.6.1

### 🐛 Bug Fixes - Image Paste Service
- **Fixed upload JSON parse errors**: Server now returns proper JSON error responses instead of HTML
  - **Root cause**: Multer errors were not caught, Express returned default HTML error pages
  - **Solution**: Added Multer-specific error handling middleware
  - **Impact**: Upload errors now show clear, actionable messages

- **Fixed terminal not loading through Home Assistant ingress**: Terminal now loads via proxy endpoint
  - **Root cause**: iframe tried to access ttyd on port 7681 directly, incompatible with ingress
  - **Solution**: Added http-proxy-middleware with WebSocket support, created /terminal/ proxy endpoint
  - **Impact**: Terminal works correctly through Home Assistant ingress

- **Improved paste event detection**: Better debugging and compatibility
  - Added detailed console logging for troubleshooting
  - Added window-level paste handler as fallback
  - Enhanced error handling in upload function

### 📦 Dependencies
- Added `http-proxy-middleware@^2.0.6` for WebSocket-capable terminal proxying

## 1.6.0

### ✨ New Feature - Image Paste Support
- **Paste images directly in the terminal**: Upload images via paste (Ctrl+V), drag-drop, or upload button
  - **Lightweight Node.js service**: ~10MB RAM overhead, ARM-compatible for Raspberry Pi
  - **Multiple upload methods**: Clipboard paste, drag-and-drop, or button click
  - **Persistent storage**: Images saved to `/data/images/` (survives restarts)
  - **Claude integration**: Use uploaded images with Claude Code CLI for analysis, OCR, etc.
  - **File formats**: Supports JPEG, PNG, GIF, WebP, SVG (10MB limit)

- **Architecture changes**:
  - New image upload service on port 7680 (Express + Multer)
  - Custom HTML interface embeds ttyd terminal (port 7681)
  - Home Assistant ingress now points to port 7680
  - Both services run concurrently in the container

- **User experience**:
  - Copy image → Paste in terminal → Automatic upload
  - File path shown in status bar: `/data/images/pasted-<timestamp>.png`
  - Use with Claude: `analyze /data/images/pasted-123.png`

### 📚 Documentation
- Added `IMAGE_PASTE.md` with complete feature documentation
- Updated CLAUDE.md with image paste development notes
- Documented troubleshooting and browser compatibility

### 🔧 Technical Details
- Dependencies: Express (4.18.2), Multer (1.4.5-lts.1)
- Security: MIME type validation, 10MB size limit, isolated storage
- Performance: Minimal CPU usage, only active during uploads
- Compatibility: All supported architectures (amd64, aarch64, armv7)

## 1.5.2

### 🐛 Critical Bug Fix - Persistent Packages PATH
- **Fixed persistent packages not available in terminal**: Packages installed via `persist-install` are now correctly available in all bash sessions
  - **Root cause**: Environment variables (PATH, LD_LIBRARY_PATH) were only set in parent run.sh process
  - **Solution**: Created `/etc/profile.d/persistent-packages.sh` which is auto-sourced by all bash shells
  - **Impact**: `python3`, `ha`, and other installed packages now work immediately after installation
  - **Affected versions**: 1.4.0 - 1.5.1 (packages were installed correctly but not in PATH)

- **Technical details**:
  - ttyd spawns bash sessions that don't inherit parent process environment variables
  - Standard Linux solution: Use `/etc/profile.d/` for system-wide environment configuration
  - Profile script sets HOME, XDG variables, and persistent package paths for all sessions
  - No changes needed to existing installations - automatic on container restart

### 📚 Documentation Updates
- Added troubleshooting section for PATH issues in CLAUDE.md
- Documented the fix and migration path from older versions
- Updated development notes with container testing workflow

## 1.5.1

### 🐛 Bug Fixes
- Improved Home Assistant CLI installation verification
- Enhanced error handling for ha command checks

## 1.5.0

### ✨ New Features
- **Official Home Assistant CLI support**: Install with `persist-install --ha-cli`
  - Auto-detects architecture (amd64, aarch64, armv7, armhf, i386)
  - Downloads binary from official GitHub releases
  - Provides full access to Home Assistant management commands
  - Alternative to Supervisor REST API for programmatic access

## 1.4.0

### ✨ New Features - Persistent Package System
- **`persist-install` command**: Install packages that survive container restarts!
  - Simple syntax: `persist-install python3 git vim`
  - Python packages: `persist-install --python homeassistant-cli requests`
  - List installed: `persist-install --list`
  - Packages stored in `/data/packages` (persistent Home Assistant storage)
  - No need to rebuild Docker image for new tools

- **Auto-install packages on startup**: Configure packages in add-on settings
  - `persistent_apk_packages`: System packages (git, vim, htop, etc.)
  - `persistent_pip_packages`: Python packages (homeassistant-cli, requests, etc.)
  - Automatically installed on every container startup
  - Perfect for your essential toolkit

- **Python virtual environment**: Persistent Python environment
  - Located at `/data/packages/python/venv`
  - Automatically activated when packages are installed
  - Survives reboots and container recreations

### 🏗️ Architecture Improvements
- **Scalable package management**: No longer requires Dockerfile modifications
  - Add packages via terminal command or config
  - Instant package installation without rebuilding
  - Reduced image size (only core tools in image)
  - User-specific package installations

- **Smart PATH management**: Persistent binaries take priority
  - `/data/packages/bin` added to PATH
  - Python venv automatically activated
  - Library paths configured for compiled packages

### 📚 Documentation
- **Container architecture explained**: Comprehensive guide to persistence
  - Why runtime installations (apk add) disappear
  - Difference between image layers and volume layers
  - How persistent storage solves the problem
  - Migration from Dockerfile-based approach to persistent storage

## 1.3.2

### 🐛 Bug Fixes
- **Improved installation reliability** (#16): Enhanced resilience for network issues during installation
  - Added retry logic (3 attempts) for npm package installation
  - Configured npm with longer timeouts for slow/unstable connections
  - Explicitly set npm registry to avoid DNS resolution issues
  - Added 10-second delay between retry attempts

### 🛠️ Improvements
- **Enhanced network diagnostics**: Better troubleshooting for connection issues
  - Added DNS resolution checks to identify network configuration problems
  - Check connectivity to GitHub Container Registry (ghcr.io)
  - Extended connection timeouts for virtualized environments
  - More detailed error messages with specific solutions
- **Better virtualization support**: Improved guidance for VirtualBox and Proxmox users
  - Enhanced VirtualBox detection with detailed configuration requirements
  - Added Proxmox/QEMU environment detection
  - Specific network adapter recommendations for VM installations
  - Clear guidance on minimum resource requirements (2GB RAM, 8GB disk)

## 1.3.1

### 🐛 Critical Fix
- **Restored config directory access**: Fixed regression where add-on couldn't access Home Assistant configuration files
  - Re-added `config:rw` volume mapping that was accidentally removed in 1.2.0
  - Users can now properly access and edit their configuration files again

## 1.3.0

### ✨ New Features
- **Full Home Assistant API Access**: Enabled complete API access for automations and entity control
  - Added `hassio_api`, `homeassistant_api`, and `auth_api` permissions
  - Set `hassio_role` to 'manager' for full Supervisor access
  - Created comprehensive API examples script (`ha-api-examples.sh`)
  - Includes Supervisor API, Core API, and WebSocket examples
  - Python and bash code examples for entity control

### 🐛 Bug Fixes
- **Fixed authentication paste issues** (#14): Added authentication helper for clipboard problems
  - New authentication helper script with multiple input methods
  - Manual code entry option when clipboard paste fails
  - File-based authentication via `/config/auth-code.txt`
  - Integrated into session picker as menu option

### 🛠️ Improvements
- **Enhanced diagnostics** (#16): Added comprehensive health check system
  - System resource monitoring (memory, disk space)
  - Permission and dependency validation
  - VirtualBox-specific troubleshooting guidance
  - Automatic health check on startup
  - Improved error handling with strict mode

## 1.2.1

### 🔧 Internal Changes
- Fixed YAML formatting issues for better compatibility
- Added document start marker and fixed line lengths

## 1.2.0

### 🔒 Authentication Persistence Fix (PR #15)
- **Fixed OAuth token persistence**: Tokens now survive container restarts
  - Switched from `/config` to `/data` directory (Home Assistant best practice)
  - Implemented XDG Base Directory specification compliance
  - Added automatic migration for existing authentication files
  - Removed complex symlink/monitoring systems for simplicity
  - Maintains full backward compatibility

## 1.1.4

### 🧹 Maintenance
- **Cleaned up repository**: Removed erroneously committed test files (thanks @lox!)
- **Improved codebase hygiene**: Cleared unnecessary temporary and test configuration files

## 1.1.3

### 🐛 Bug Fixes
- **Fixed session picker input capture**: Resolved issue with ttyd intercepting stdin, preventing proper user input
- **Improved terminal interaction**: Session picker now correctly captures user choices in web terminal environment

## 1.1.2

### 🐛 Bug Fixes
- **Fixed session picker input handling**: Improved compatibility with ttyd web terminal environment
- **Enhanced input processing**: Better handling of user input with whitespace trimming
- **Improved error messages**: Added debugging output showing actual invalid input values
- **Better terminal compatibility**: Replaced `echo -n` with `printf` for web terminals

## 1.1.1

### 🐛 Bug Fixes  
- **Fixed session picker not found**: Moved scripts from `/config/scripts/` to `/opt/scripts/` to avoid volume mapping conflicts
- **Fixed authentication persistence**: Improved credential directory setup with proper symlink recreation
- **Enhanced credential management**: Added proper file permissions (600) and logging for debugging
- **Resolved volume mapping issues**: Scripts now persist correctly without being overwritten

## 1.1.0

### ✨ New Features
- **Interactive Session Picker**: New menu-driven interface for choosing Claude session types
  - 🆕 New interactive session (default)
  - ⏩ Continue most recent conversation (-c)
  - 📋 Resume from conversation list (-r) 
  - ⚙️ Custom Claude command with manual flags
  - 🐚 Drop to bash shell
  - ❌ Exit option
- **Configurable auto-launch**: New `auto_launch_claude` setting (default: true for backward compatibility)
- **Added nano text editor**: Enables `/memory` functionality and general text editing

### 🛠️ Architecture Changes
- **Simplified credential management**: Removed complex modular credential system
- **Streamlined startup process**: Eliminated problematic background services
- **Cleaner configuration**: Reduced complexity while maintaining functionality
- **Improved reliability**: Removed sources of startup failures from missing script dependencies

### 🔧 Improvements
- **Better startup logging**: More informative messages about configuration and setup
- **Enhanced backward compatibility**: Existing users see no change in behavior by default
- **Improved error handling**: Better fallback behavior when optional components are missing

## 1.0.2

### 🔒 Security Fixes
- **CRITICAL**: Fixed dangerous filesystem operations that could delete system files
- Limited credential searches to safe directories only (`/root`, `/home`, `/tmp`, `/config`)
- Replaced unsafe `find /` commands with targeted directory searches
- Added proper exclusions and safety checks in cleanup scripts

### 🐛 Bug Fixes
- **Fixed architecture mismatch**: Added missing `armv7` support to match build configuration
- **Fixed NPM package installation**: Pinned Claude Code package version for reliable builds
- **Fixed permission conflicts**: Standardized credential file permissions (600) across all scripts
- **Fixed race conditions**: Added proper startup delays for credential management service
- **Fixed script fallbacks**: Implemented embedded scripts when modules aren't found

### 🛠️ Improvements
- Added comprehensive error handling for all critical operations
- Improved build reliability with better package management
- Enhanced credential management with consistent permission handling
- Added proper validation for script copying and execution
- Improved startup logging for better debugging

### 🧪 Development
- Updated development environment to use Podman instead of Docker
- Added proper build arguments for local testing
- Created comprehensive testing framework with Nix development shell
- Added container policy configuration for rootless operation

## 1.0.0

- First stable release of Claude Terminal add-on:
  - Web-based terminal interface using ttyd
  - Pre-installed Claude Code CLI
  - User-friendly interface with clean welcome message
  - Simple claude-logout command for authentication
  - Direct access to Home Assistant configuration
  - OAuth authentication with Anthropic account
  - Auto-launches Claude in interactive mode
