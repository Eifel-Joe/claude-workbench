#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
    echo "FAIL (production run.sh): $*" >&2
    exit 1
}

bashio::log.info() { :; }
bashio::log.warning() { :; }
bashio::log.error() { :; }

config_tmux_mouse=false
config_use_persistent_claude=true
config_auto_update_claude_on_start=false
config_apk_packages=''
config_pip_packages=''
bashio::config() {
    case "$1" in
        tmux_mouse) printf '%s\n' "$config_tmux_mouse" ;;
        use_persistent_claude) printf '%s\n' "$config_use_persistent_claude" ;;
        auto_update_claude_on_start) printf '%s\n' "$config_auto_update_claude_on_start" ;;
        persistent_apk_packages) printf '%s\n' "$config_apk_packages" ;;
        persistent_pip_packages) printf '%s\n' "$config_pip_packages" ;;
        *) printf '%s\n' "${2:-}" ;;
    esac
}

# Load only the production entrypoint. No helper script may redefine its functions.
CLAUDE_RUN_SH_SKIP_MAIN=true
source "$repo_root/claude-workbench/run.sh"

HOME="$tmp_dir/home"
TMUX_WRAPPER_PATH="$tmp_dir/tmux-claude"
mkdir -p "$HOME"
setup_tmux
grep -qx 'set -g mouse off' "$HOME/.tmux.conf" || fail "tmux mouse should default to off"

config_tmux_mouse=true
setup_tmux
grep -qx 'set -g mouse on' "$HOME/.tmux.conf" || fail "tmux mouse option should enable mouse mode"

config_tmux_mouse=''
setup_tmux
grep -qx 'set -g mouse off' "$HOME/.tmux.conf" || fail "empty optional bool should safely disable mouse mode"

# Claude Code's /copy emits OSC 52. tmux defaults to set-clipboard=external, which
# drops what applications in the pane send, and only emits OSC 52 outwards when the
# outer terminal advertises the Ms capability.
grep -qx 'set -g set-clipboard on' "$HOME/.tmux.conf" || \
    fail "tmux must accept and forward OSC 52 from applications"
grep -qx "set -as terminal-features ',\*:clipboard'" "$HOME/.tmux.conf" || \
    fail "tmux must advertise the clipboard capability so OSC 52 reaches ttyd"

# The frontend fix has to be reachable from the page that embeds ttyd.
clipboard_bridge="$repo_root/claude-workbench/image-service/public/terminal-clipboard.js"
terminal_page="$repo_root/claude-workbench/image-service/public/index.html"
[ -f "$clipboard_bridge" ] || fail "clipboard bridge is missing"
grep -q 'src="terminal-clipboard.js"' "$terminal_page" || \
    fail "terminal page must load the clipboard bridge"
grep -q 'installTerminalClipboard(iframe)' "$terminal_page" || \
    fail "terminal page must attach the clipboard bridge to the ttyd iframe"

# The on-screen keyboard shrinks the visual viewport but not 100vh, so without
# this the prompt ends up behind the keyboard.
grep -q 'window.visualViewport' "$terminal_page" || \
    fail "terminal page must follow the visual viewport so the keyboard cannot cover the prompt"
grep -q 'interactive-widget=resizes-content' "$terminal_page" || \
    fail "the viewport must shrink with the on-screen keyboard, not sit behind it"

PERSISTENT_CLAUDE_ROOT="$tmp_dir/npm"
CLAUDE_BIN_LINK="$tmp_dir/claude"
# $HOME/.local/bin precedes /usr/local/bin on PATH, so the override must
# replace the native link too or a plain "claude" keeps the baked binary.
CLAUDE_NATIVE_BIN_LINK="$tmp_dir/native-bin/claude"
mkdir -p "$tmp_dir/native-bin"
mkdir -p "$PERSISTENT_CLAUDE_ROOT/bin" \
    "$PERSISTENT_CLAUDE_ROOT/lib/node_modules/@anthropic-ai/claude-code"
printf '#!/bin/sh\n' > "$PERSISTENT_CLAUDE_ROOT/bin/claude"
chmod +x "$PERSISTENT_CLAUDE_ROOT/bin/claude"
printf '{}\n' > "$PERSISTENT_CLAUDE_ROOT/lib/node_modules/@anthropic-ai/claude-code/package.json"
setup_persistent_claude
[ "$(readlink "$CLAUDE_BIN_LINK")" = "$PERSISTENT_CLAUDE_ROOT/bin/claude" ] || \
    fail "current npm Claude layout was not activated"
[ "$(readlink "$CLAUDE_NATIVE_BIN_LINK")" = "$PERSISTENT_CLAUDE_ROOT/bin/claude" ] || \
    fail "persistent Claude must also replace the native link that is earlier on PATH"

rm "$PERSISTENT_CLAUDE_ROOT/bin/claude"
printf '#!/usr/bin/env node\n' > "$PERSISTENT_CLAUDE_ROOT/lib/node_modules/@anthropic-ai/claude-code/cli.js"
chmod +x "$PERSISTENT_CLAUDE_ROOT/lib/node_modules/@anthropic-ai/claude-code/cli.js"
ln -s ../lib/node_modules/@anthropic-ai/claude-code/cli.js "$PERSISTENT_CLAUDE_ROOT/bin/claude"
setup_persistent_claude
[ "$(readlink "$CLAUDE_BIN_LINK")" = "$PERSISTENT_CLAUDE_ROOT/bin/claude" ] || \
    fail "legacy npm Claude layout was not activated"

# A package can look installed while its architecture-specific binary is absent.
rm "$CLAUDE_BIN_LINK" "$CLAUDE_NATIVE_BIN_LINK" "$PERSISTENT_CLAUDE_ROOT/bin/claude"
printf '#!/bin/sh\nexit 1\n' > "$PERSISTENT_CLAUDE_ROOT/bin/claude"
chmod +x "$PERSISTENT_CLAUDE_ROOT/bin/claude"
setup_persistent_claude
[ ! -e "$CLAUDE_BIN_LINK" ] || fail "non-working persistent Claude should not replace the baked binary"
[ ! -e "$CLAUDE_NATIVE_BIN_LINK" ] || fail "non-working persistent Claude should not replace the native link"

PERSIST_INSTALL_LOG="$tmp_dir/persist-install.log"
PERSIST_INSTALL_BIN="$tmp_dir/persist-install"
PERSIST_INSTALL_SOURCE="$tmp_dir/no-bundled-installer"
export PERSIST_INSTALL_LOG
cat > "$PERSIST_INSTALL_BIN" << 'CAPTURE_EOF'
#!/usr/bin/env bash
printf '%s\n' '---' "$@" >> "$PERSIST_INSTALL_LOG"
for argument in "$@"; do
    if [ -n "${PERSIST_INSTALL_FAIL_ON:-}" ] && [ "$argument" = "$PERSIST_INSTALL_FAIL_ON" ]; then
        exit 1
    fi
done
CAPTURE_EOF
chmod +x "$PERSIST_INSTALL_BIN"

config_apk_packages=$'tmux\nopenssh-client'
config_pip_packages=$'requests\nyaml'
setup_persistent_packages
printf '%s\n' '---' '--apk' 'tmux' '---' '--apk' 'openssh-client' '---' '--python' 'requests' 'yaml' > "$tmp_dir/expected.log"
cmp -s "$tmp_dir/expected.log" "$PERSIST_INSTALL_LOG" || fail "newline Bashio lists were not installed correctly"

config_apk_packages='["git","nano"]'
config_pip_packages='["httpx","ruff"]'
: > "$PERSIST_INSTALL_LOG"
setup_persistent_packages
printf '%s\n' '---' '--apk' 'git' '---' '--apk' 'nano' '---' '--python' 'httpx' 'ruff' > "$tmp_dir/expected.log"
cmp -s "$tmp_dir/expected.log" "$PERSIST_INSTALL_LOG" || fail "JSON Bashio lists were not installed correctly"

config_apk_packages='[]'
config_pip_packages=''
: > "$PERSIST_INSTALL_LOG"
setup_persistent_packages
[ ! -s "$PERSIST_INSTALL_LOG" ] || fail "empty package options should be a no-op"

# One optional package failure must not terminate add-on startup or skip the rest.
config_apk_packages=$'missing-package\ngit'
config_pip_packages=''
PERSIST_INSTALL_FAIL_ON='missing-package'
export PERSIST_INSTALL_FAIL_ON
: > "$PERSIST_INSTALL_LOG"
setup_persistent_packages
printf '%s\n' '---' '--apk' 'missing-package' '---' '--apk' 'git' > "$tmp_dir/expected.log"
cmp -s "$tmp_dir/expected.log" "$PERSIST_INSTALL_LOG" || fail "package failure did not continue safely"

# A pending migration offer puts the selection window in front of Claude.
APP_MIGRATION_OFFER="$tmp_dir/offer.json"
APP_MIGRATION_CLI="/opt/scripts/app-migration/cli.js"
[ "$(with_migration_dialog 'clear && picker')" = 'clear && picker' ] || \
    fail "launch command must stay unchanged without a migration offer"
printf '{}\n' > "$APP_MIGRATION_OFFER"
[ "$(with_migration_dialog 'clear && picker')" = "/usr/bin/node $APP_MIGRATION_CLI dialog; clear && picker" ] || \
    fail "a pending migration offer must show the dialog before the launch command"

# Detection output: "WARNING:" lines become log warnings (prefix stripped).
APP_MIGRATION_CLI="$tmp_dir/cli.js"
# The marker detect_app_migration creates first (n33); /data does not exist here.
APP_MIGRATION_UNDECIDED="$tmp_dir/migration/undecided"
: > "$APP_MIGRATION_CLI"
node() { printf '%s\n' 'App migration: nothing to offer (state)' 'WARNING: App migration: detection failed, skipping (x)'; }
bashio::log.info() { printf 'info|%s\n' "$*" >> "$tmp_dir/migration.log"; }
bashio::log.warning() { printf 'warning|%s\n' "$*" >> "$tmp_dir/migration.log"; }
detect_app_migration
unset -f node
bashio::log.info() { :; }
bashio::log.warning() { :; }
printf '%s\n' 'info|App migration: nothing to offer (state)' \
    'warning|App migration: detection failed, skipping (x)' > "$tmp_dir/migration.expected"
cmp -s "$tmp_dir/migration.expected" "$tmp_dir/migration.log" || \
    fail "detect_app_migration must log WARNING: lines as warnings"

# bashio 0.19.0 (Alpine 3.24 base) runs run.sh with inherit_errexit. When the
# Supervisor API call inside bashio::config fails, the read either aborts (a
# bare `x=$(bashio::config ...)`: set -e ends startup) or, on the left of || or
# inside if, returns 0 with EMPTY output, since bash ignores errexit there and
# bashio then prints the empty API answer. Either way the default is lost, and
# inside "$(get_claude_launch_command)" an abort silently emptied the launch
# command. Every read goes through read_option, which falls back to the
# default in both cases. Both stub variants model the real bashio: "abort" is
# the bare-read behaviour, "empty" the || behaviour (o=$(false) fails the stub
# only where errexit is active, exactly like bashio's options=$(...)). The
# subshell runs in the background because bash ignores set -e in a subshell
# tested with || or if (technique from nsleigh, ESJavadex/claude-code-ha@a1f0f2da).
for variant in abort empty; do
    uploads="$tmp_dir/uploads-$variant"
    reads_log="$tmp_dir/option-reads-$variant.warnings"
    mkdir -p "$uploads"
    touch -d '40 days ago' "$uploads/pasted-old.png"
    touch "$uploads/pasted-new.png"
    rm -f "$tmp_dir/option-reads"
    (
        set -euo pipefail
        shopt -s inherit_errexit
        if [ "$variant" = abort ]; then
            bashio::config() { return 1; }
        else
            bashio::config() { local options; options=$(false); printf '%s' "$options"; }
        fi
        bashio::log.warning() { printf '%s\n' "$*" >> "$reads_log"; }
        [ "$(read_option 'auto_launch_claude' 'true')" = true ]
        [ "$(read_option 'image_retention_days' '30')" = 30 ]
        setup_tmux
        grep -qx 'set -g mouse off' "$HOME/.tmux.conf"
        launch=$(get_claude_launch_command)
        [[ "$launch" == *"Starting Claude"* ]]
        setup_persistent_claude
        [ "$USE_PERSISTENT_CLAUDE" = false ]
        PERSIST_INSTALL_LOG="$tmp_dir/option-reads-install.log"
        auto_install_packages
        [ ! -e "$PERSIST_INSTALL_LOG" ]
        # A deletion must not run on a guessed value: a user who set 0 (keep
        # all) would lose images to the default 30 whenever the read fails.
        IMAGE_UPLOAD_DIR="$uploads" prune_uploaded_images
        [ -e "$uploads/pasted-old.png" ]
        grep -q 'image_retention_days could not be read' "$reads_log"
        AUTO_CONTINUE_DIR="$tmp_dir/auto-continue" init_auto_continue
        [ "$(cat "$tmp_dir/auto-continue/auto-continue")" = off ]
        echo survived > "$tmp_dir/option-reads"
    ) &
    wait $! || true
    [ "$(cat "$tmp_dir/option-reads" 2>/dev/null)" = "survived" ] || \
        fail "a failed option read ($variant) must fall back to its default, not end startup or come back empty"
    # An empty auto_launch_claude would open the session picker (or this
    # warning without one) instead of Claude.
    ! grep -q 'falling back to auto-launch' "$reads_log" 2>/dev/null || \
        fail "a failed read ($variant) left auto_launch_claude empty"
done

# A set value wins over the default; only a failed or empty read falls back.
(
    set -euo pipefail
    shopt -s inherit_errexit
    bashio::config() { printf '%s' false; }
    [ "$(read_option 'auto_launch_claude' 'true')" = false ]
    bashio::config() { printf '%s' 0; }
    [ "$(read_option 'image_retention_days' '30')" = 0 ]
    echo survived > "$tmp_dir/option-values"
) &
wait $! || true
[ "$(cat "$tmp_dir/option-values" 2>/dev/null)" = "survived" ] || \
    fail "read_option must return a value that was read"

# bashio::config is called in exactly one place, read_option; every option
# read goes through it.
config_calls=$(grep -E 'bashio::config ' "$repo_root/claude-workbench/run.sh" | grep -vcE '^[[:space:]]*#')
[ "$config_calls" -eq 1 ] || fail "bashio::config must only be called inside read_option ($config_calls calls)"
# grep without -q: an early exit would SIGPIPE sed under pipefail.
sed -n '/^read_option() {/,/^}/p' "$repo_root/claude-workbench/run.sh" | grep 'bashio::config ' > /dev/null || \
    fail "read_option must be the one place that calls bashio::config"

echo "Production run.sh regression suite passed"
