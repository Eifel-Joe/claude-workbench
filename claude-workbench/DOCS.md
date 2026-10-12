# Claude Workbench

A workbench for Anthropic's Claude Code CLI in Home Assistant.

## About

Claude Workbench provides a web-based terminal with Claude Code CLI pre-installed plus persistent package management. It grew out of Claude Terminal Pro (ESJavadex) and the original Claude Terminal (heytcass). Access Claude directly from your Home Assistant dashboard and install packages that persist across restarts.

## Installation

1. Add this repository to your Home Assistant app store:
   - Go to Settings → Apps → App Store
   - Click the menu (⋮) and select Repositories
   - Add: `https://github.com/Eifel-Joe/claude-workbench`
2. Install the Claude Workbench app
3. Start the app
4. Click "OPEN WEB UI" to access the terminal
5. On first use, follow the OAuth prompts to log in to your Anthropic account

### Switching from Claude Terminal Pro

If a Claude Terminal Pro app is installed — ESJavadex's, or this project's own app
before 3.0.0 — Claude Workbench offers on the first panel open to take over its
data. Choose with the digits 1–6, then press Enter:

1. Claude data (memories, `CLAUDE.md`, history, settings) · 2. Claude login ·
3. GitHub login · 4. reinstall packages (only explicitly installed pip packages; all
if the old pip did not mark them) · 5. stop the old app and disable its autostart, so
a host reboot does not bring it back with the shared login (skipped if any item
failed or Claude data/login was not found) · 6. settings (`auto_launch_claude`,
`dangerously_skip_permissions`, `tmux_mouse`, `remote_control*`; applied after the
next restart)

A partial backup of the old app is created first (progress is shown) and kept under
Settings → System → Backups. It includes the old app's image (several hundred MB)
and the old login, so delete it once you no longer need it. `s` asks again on the
next start, `n` never asks again.

Coming from this project's old app, the store lists Claude Workbench twice: install
the one whose app page address ends in `0e003122_claude_workbench` (from the new
repository URL above). The other one, `6ef0b4d0_claude_workbench`, comes through the
old address, and its repository entry could then never be removed.

Afterwards uninstall the old app and remove its repository entry (Settings → Apps →
App Store → ⋮ → Repositories). GitHub redirects this project's old URL to the new
one, so Claude Workbench would otherwise show up twice.

## Configuration

The app offers several configuration options:

### Auto Launch Claude
- **Default**: `true`
- When enabled, Claude starts automatically when you open the terminal
- When disabled, shows an interactive session picker menu

### Remote Control
- **Default**: `remote_control: false`
- When enabled, the auto-launched Claude session starts with the `--remote-control` flag, pairing it with [claude.ai/code](https://claude.ai/code) and the Claude mobile app so you can drive the session from your phone, tablet, or another browser without opening the web terminal first (equivalent to running `claude --remote-control`)
- Only applies while `auto_launch_claude: true`; it has no effect on the interactive session picker
- Optionally set `remote_control_session_name` to give the session a fixed title in the session list; leave it empty to let Claude auto-generate one
- **Requires** a claude.ai OAuth login (API keys are not supported) and Claude Code v2.1.51 or later
- See Anthropic's [Remote Control guide](https://code.claude.com/docs/en/remote-control) for details

### Dangerously Skip Permissions
- **Default**: `false`
- When enabled, Claude runs with `--dangerously-skip-permissions` flag
- **⚠️ WARNING**: This gives Claude unrestricted file system access
- Use only if you understand the security implications
- Useful for advanced users who need full file access

### tmux Mouse Mode
- **Default**: `false`
- Keep disabled for reliable native browser copy/paste in the ttyd terminal, including OAuth codes
- Enable only if you prefer tmux mouse selection, scrolling, and pane controls

### Own tmux Settings
- The app rewrites `~/.tmux.conf` on every start. Put your own settings in
  `~/.tmux.conf.local` (that is `/data/home/.tmux.conf.local`): it is loaded
  last, so it overrides the defaults, and it survives restarts and updates
- Example – a green status bar:
  ```bash
  echo 'set -g status-bg colour22' >> ~/.tmux.conf.local
  tmux source-file ~/.tmux.conf
  ```
- Restarting the app loads it as well

### Copying Text Out of the Terminal

There are five ways, and which ones you need depends on the device:

- **Click the link** in the terminal (desktop, with `tmux_mouse` off): any row of
  a link that wraps over several rows opens the whole URL in a new tab.
- **`🔗 Copy link`** appears in the header on its own whenever a link is on
  screen. One tap copies it, and the status line names the host it took. This is
  the quickest way to get an OAuth login URL out, on any device.
- **`📋 Copy`** opens the terminal's text in a box you can select from. On a
  phone this is the only way to copy arbitrary text: xterm.js has no touch
  support in its selection code and draws to a canvas, so a finger cannot select
  anything in the terminal itself. Long-press in the box for the native selection
  handles, or use **Copy all**. The switch chooses the visible screen or the
  whole scrollback.
- **Mouse selection** copies automatically on a computer. The scissors overlay
  (`✂`) appears only when the clipboard was actually written.
- **Claude Code's `/copy`** emits an OSC 52 escape sequence; tmux forwards it
  (`set-clipboard on`) and the browser writes it to the clipboard.

**Long links.** The terminal breaks a long URL across rows, and the app puts
it back together — including the case where the tail is re-indented, which would
otherwise leave spaces inside the link. If a link is cut off at the edge of the
screen it is refused rather than copied in half, and the status line says so;
scroll until all of it is visible.

**Plain HTTP.** Over `http://homeassistant.local:8123` browsers do not expose
`navigator.clipboard` at all — that API is restricted to secure contexts. The
app falls back to a hidden-textarea copy, which Chrome only permits while it
is handling a user gesture:

- Every **button** works, because your tap is the gesture. So does mouse
  selection, because releasing the button is one.
- **`/copy` does not.** It arrives from the terminal with no tap behind it, so
  the browser refuses it; the app says so and points at `📋`. Nothing the page
  can do changes this — it is the browser's security model, not a bug.
- Serving Home Assistant over HTTPS makes `/copy` work too.

### Scrolling on a Phone or Touch Screen

Swipe up and down over the terminal. A mouse wheel has always worked, but touch
did not: xterm.js ignores touch entirely while the program in the terminal has
taken over the mouse, which Claude Code does. Swipes are now translated into
wheel events, so they behave the same as a wheel.

Pinch-zoom and horizontal panning still belong to the browser, and putting a
second finger down stops the scroll — so a pinch is not read as a drag.

### Reading the Clipboard

**Reading** the clipboard *from* the terminal is deliberately not implemented:
OSC 52 read requests (`\e]52;c;?\a`) are swallowed rather than answered, so a
program in the terminal cannot exfiltrate your clipboard.

### Persistent Packages
- Configure APK and pip packages to auto-install on startup
- Packages are stored in `/data/packages` and survive restarts
- The app's own Claude Code commands (`/install`, `/install-python`, `/list-packages`) and its persistent-package skill are refreshed in `~/.claude` on every start; save your own variants under a different name

### Optional Persistent Claude Code
- **Default**: `use_persistent_claude: true`
- When enabled, the app will look for a Claude Code install in `/data/npm/` and use it instead of the version baked into the image
- Together with startup updates this keeps Claude Code current, which is what makes new models (e.g. Opus 5.5, Fable) available
- Set it to `false` to stay on the version baked into the image

### Optional Startup Updates
- **Default**: `auto_update_claude_on_start: true`
- Only relevant if `use_persistent_claude: true`
- When enabled, the app will update Claude Code in `/data/npm/` on each startup
- Turn it off to update only manually, via **🔄 Update Claude Code** in the session picker

### Pasted Images
- **Default**: `image_retention_days: 30`
- Images you paste or drop into the panel are stored in `/data/images`, which is part of every backup of the app
- On start, the app deletes its own pasted images older than this many days (up to 3650); `0` keeps them all

### Auto-Continue After a Usage Limit
- **Default**: `auto_continue: false`
- When Claude reports a usage limit, the app types `continue` into the Claude
  session one minute after the reset (up to 30 s later, it checks every 30 s)
- Switch it while the app runs with the ⏩ button in the panel header or
  `auto-continue on|off|status` in the terminal (in Claude: `!auto-continue on`);
  after a restart the option applies again
- It only types into a pane of the `claude` tmux session where Claude is the
  foreground program and the limit message is still on screen
- Only Claude's own limit message counts: it has to start its screen line (after
  frame glyphs such as `⎿` or `●`), so an answer that merely mentions
  "rate limit reached" mid-line does not trigger it
- Claude then works on unattended - with `dangerously_skip_permissions` it
  also runs commands without asking

**Example Configuration**:
```yaml
auto_launch_claude: false
remote_control: false
remote_control_session_name: ""
tmux_mouse: false
dangerously_skip_permissions: true
persistent_apk_packages:
  - python3
  - git
persistent_pip_packages:
  - requests
use_persistent_claude: true
auto_update_claude_on_start: true
image_retention_days: 30
auto_continue: false
```

Your OAuth credentials are stored in the app's private `/data` (under `/data/home/.claude`), not in `/config`, and persist across app updates and restarts, so you won't need to log in again. Credentials an older release left in `/config/claude-config` are copied into `/data` once on start; you can delete that folder afterwards.

If you enable `use_persistent_claude`, install the persistent Claude Code version once from a shell inside the app:

```bash
NPM_CONFIG_PREFIX=/data/npm npm install -g @anthropic-ai/claude-code@latest --prefer-online
```

After that, restarts will continue using the persistent version automatically.

## Usage

Claude launches automatically when you open the terminal. You can also start Claude manually with:

```bash
node /usr/local/bin/claude
```

### Common Commands

- `claude -i` - Start an interactive Claude session
- `claude --help` - See all available commands
- `claude "your prompt"` - Ask Claude a single question
- `claude process myfile.py` - Have Claude analyze a file
- `claude --editor` - Start an interactive editor session

The terminal starts directly in your `/config` directory, giving you immediate access to all your Home Assistant configuration files. This makes it easy to get help with your configuration, create automations, and troubleshoot issues.

### Keyboard
- **Shift+Enter** inserts a new line in Claude's input instead of sending it.
- **Key bar on phones and tablets:** a row of keys above the on-screen
  keyboard, shown on touch devices only (touchscreen laptops included).
  **Esc** cancels a reply or closes a
  dialog, **↑ ↓ ↵** move through Claude's menus and questions (`/model`,
  `/resume`), **⇧Tab** switches the mode (normal, auto, plan), and **^C**
  stops a command in the shell. The on-screen keyboard stays open while you
  tap them.
- **^C on the key bar** is sent at most once every two seconds: two Ctrl+C in
  a row quit Claude Code and end the session (your history stays available
  through `/resume`).

## Features

### Core Features
- **Web Terminal**: Access a full terminal environment via your browser
- **Auto-Launching**: Claude starts automatically when you open the terminal
- **Claude AI**: Access Claude's AI capabilities for programming, troubleshooting and more
- **Direct Config Access**: Terminal starts in `/config` for immediate access to all Home Assistant files
- **Simple Setup**: Uses OAuth for easy authentication
- **Home Assistant Integration**: Access directly from your dashboard

### Enhanced Features (Pro)
- **Persistent Packages**: Install system (APK) and Python (pip) packages that survive restarts
- **Auto-Install Configuration**: Set packages to auto-install on startup
- **Simple Management**: Use `persist-install` command for easy package installation
- **Python Virtual Environment**: Isolated Python environment in `/data/packages`

## Security

**Every signed-in Home Assistant user can open this terminal, not only
administrators.** `panel_admin: true` only hides the sidebar entry; Home
Assistant lets any signed-in user open an app's ingress page. Behind it is a
root shell that can write your whole configuration and use the Supervisor
API. If you hand out limited accounts, stop or uninstall the app. Details and
sources: the
[Security section of the README](https://github.com/Eifel-Joe/claude-workbench/blob/main/claude-workbench/README.md#security).

## Troubleshooting

- **Run `claude-doctor`** in the terminal (session menu → "🐚 Drop to bash
  shell") for the health check the app runs on every start: memory, disk,
  Node.js, whether Claude Code actually starts, the CPU and the network. The
  last line sums up how many checks failed.
- **Claude does not start on a virtual machine (blank panel or "cannot run on this CPU")**:
  Claude Code needs an x86-64-v2 CPU (SSE4.2 and POPCNT). Proxmox's default
  CPU type `kvm64` lacks both. Set the VM's CPU type to `host` (or at least
  `x86-64-v2-AES`) and restart the VM. The app shows this hint in the log and
  the terminal; the shell, `ha`, `gh` and your packages keep working.
- If Claude doesn't start automatically, choose "🐚 Drop to bash shell" in the session menu and run `claude` to see its output
- If you see permission errors, try restarting the app
- If you have authentication issues, try logging out and back in
- Check the app logs for any error messages

## Credits

**Maintainer:** [@Eifel-Joe](https://github.com/Eifel-Joe)
**Claude Terminal Pro:** Javier Santos ([@ESJavadex](https://github.com/ESJavadex)) — persistent package management and many enhancements Claude Workbench builds on
**Original Claude Terminal:** Tom Cassady ([@heytcass](https://github.com/heytcass)) — the initial app

Claude, Claude Code and the Claude spark logo are trademarks of Anthropic. Claude Workbench is an independent community project and is not made or endorsed by Anthropic.

This app was created and enhanced with the assistance of Claude Code itself! The development process, debugging, and documentation were all completed using Claude's AI capabilities - a perfect demonstration of what this app can help you accomplish.
