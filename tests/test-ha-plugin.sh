#!/usr/bin/env bash
# setup_ha_plugin (p19): installs the bundled Home Assistant plugin for Claude
# (ESJavadex/claude-homeassistant-plugins) once, updates it when the image ships
# a newer version, and never overrides the user's choice to disable it. It
# changes nothing while an app takeover offer is open or the options cannot be
# read, and it never ends the start. A fake `claude` records calls and keeps
# the plugin's state. Cases 1-7 adapted from ESJavadex's tests/test-ha-plugin.sh
# (ESJavadex/claude-code-ha@42c53d48).
set -euo pipefail
# Like bashio 0.19.0, which run.sh runs under.
shopt -s inherit_errexit

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# pwd: a PATH entry must not contain a drive colon (Git Bash with TMPDIR=D:/...).
tmp_dir=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
    echo "FAIL (ha plugin): $*" >&2
    exit 1
}

log="$tmp_dir/log"
: > "$log"
bashio::log.info() { printf 'info|%s\n' "$*" >> "$log"; }
bashio::log.warning() { printf 'warning|%s\n' "$*" >> "$log"; }
bashio::log.error() { printf 'error|%s\n' "$*" >> "$log"; }

# Options as the Supervisor answers them; options_unreadable=true makes every
# read fail like an unreachable Supervisor (bashio returns non-zero).
config_ha_plugin=true
options_unreadable=false
bashio::config() {
    [ "$options_unreadable" = false ] || return 1
    case "$1" in
        home_assistant_plugin) printf '%s\n' "$config_ha_plugin" ;;
        auto_launch_claude) printf 'true\n' ;;
        *) printf '%s\n' "${2:-}" ;;
    esac
}

# shellcheck disable=SC2034  # read by the sourced run.sh
OPTION_READ_GAVE_UP="$tmp_dir/options-unanswered"
# shellcheck disable=SC2034  # read by the sourced run.sh
CLAUDE_RUN_SH_SKIP_MAIN=true
# shellcheck source=/dev/null
source "$repo_root/claude-workbench/run.sh"

export HOME="$tmp_dir/home"
mkdir -p "$HOME"
export APP_MIGRATION_OFFER="$tmp_dir/offer.json"
export STARTUP_PLUGIN_TIMEOUT=1
state_file="$HOME/.claude/plugins/.claude-workbench-ha-plugin"

# Bundled marketplace
export HA_PLUGIN_MARKETPLACE_DIR="$tmp_dir/mkt"
mkdir -p "$HA_PLUGIN_MARKETPLACE_DIR/homeassistant-config/.claude-plugin"
bundle() { printf '{"name":"homeassistant-config","version":"%s"}\n' "$1" \
    > "$HA_PLUGIN_MARKETPLACE_DIR/homeassistant-config/.claude-plugin/plugin.json"; }
bundle 2.1.3

# Fake claude: state in $FAKE (installed version, enabled flag), calls in $CALLS.
# $FAKE/fail-<cmd> makes that subcommand fail, $FAKE/hang makes every call hang.
# enable/disable fail when the plugin already is in that state, like the real CLI
# (already_in_goal_state).
export FAKE="$tmp_dir/fake" CALLS="$tmp_dir/calls"
mkdir -p "$tmp_dir/bin" "$FAKE"
cat > "$tmp_dir/bin/claude" << 'SH'
#!/usr/bin/env bash
[ "$1" = plugin ] || exit 1
shift
echo "$*" >> "$CALLS"
# exec: timeout must hit the process that hangs, as with the real CLI.
[ -f "$FAKE/hang" ] && exec sleep 5
[ -f "$FAKE/fail-$1" ] && exit 1
mkt="$HA_PLUGIN_MARKETPLACE_DIR/homeassistant-config/.claude-plugin/plugin.json"
id=homeassistant-config@claude-homeassistant-plugins
case "$*" in
    "list --json")
        if [ -f "$FAKE/version" ]; then
            printf '[{"id":"%s","version":"%s","enabled":%s,"scope":"user"}]\n' \
                "$id" "$(cat "$FAKE/version")" "$(cat "$FAKE/enabled")"
        else
            echo '[]'
        fi ;;
    "marketplace add "*|"marketplace update "*) : ;;
    "install $id") jq -r .version "$mkt" > "$FAKE/version"; echo true > "$FAKE/enabled" ;;
    "update $id") jq -r .version "$mkt" > "$FAKE/version" ;;
    "disable $id") [ "$(cat "$FAKE/enabled")" = true ] || exit 1; echo false > "$FAKE/enabled" ;;
    "enable $id") [ "$(cat "$FAKE/enabled")" = false ] || exit 1; echo true > "$FAKE/enabled" ;;
    *) exit 1 ;;
esac
SH
chmod +x "$tmp_dir/bin/claude"
export PATH="$tmp_dir/bin:$PATH"

calls() { cat "$CALLS" 2>/dev/null || true; }
reset() { : > "$CALLS"; : > "$log"; }

# 1. First start installs it and remembers option and version.
reset
setup_ha_plugin || fail "setup_ha_plugin failed"
calls | grep -qx "marketplace add $HA_PLUGIN_MARKETPLACE_DIR" || fail "first start must register the marketplace: $(calls)"
calls | grep -qx 'install homeassistant-config@claude-homeassistant-plugins' || fail "first start must install: $(calls)"
[ "$(cat "$FAKE/enabled")" = true ] || fail "plugin should be enabled after install"
[ "$(cat "$state_file")" = 'true:2.1.3' ] || fail "state file should say true:2.1.3, says '$(cat "$state_file" 2>/dev/null)'"
grep -q '^info|Home Assistant plugin: installed 2.1.3' "$log" || fail "install not logged: $(cat "$log")"

# 2. Second start with the same image does nothing.
reset
setup_ha_plugin
[ -z "$(calls)" ] || fail "unchanged start must not call claude: $(calls)"
grep -q 'nothing to do' "$log" || fail "unchanged start not logged: $(cat "$log")"

# 3. User disables it with /plugin; a new image updates but keeps it disabled.
echo false > "$FAKE/enabled"
bundle 2.1.4
reset
setup_ha_plugin
calls | grep -qx 'marketplace update claude-homeassistant-plugins' || fail "new bundled version must refresh the marketplace: $(calls)"
calls | grep -qx 'update homeassistant-config@claude-homeassistant-plugins' || fail "new bundled version must update: $(calls)"
calls | grep -q '^install ' && fail "must not reinstall (that re-enables it)"
calls | grep -q '^enable ' && fail "must not re-enable a plugin the user disabled"
[ "$(cat "$FAKE/version")" = 2.1.4 ] || fail "plugin should be at 2.1.4"
[ "$(cat "$FAKE/enabled")" = false ] || fail "user's disable must survive the update"
[ "$(cat "$state_file")" = 'true:2.1.4' ] || fail "state file not updated after the update"

# 4. Option off disables it; back on enables it again.
echo true > "$FAKE/enabled"
config_ha_plugin=false
reset
setup_ha_plugin
calls | grep -qx 'disable homeassistant-config@claude-homeassistant-plugins' || fail "option off must disable: $(calls)"
[ "$(cat "$FAKE/enabled")" = false ] || fail "plugin should be disabled"
[ "$(cat "$state_file")" = 'false:2.1.4' ] || fail "state file should say false:2.1.4"
config_ha_plugin=true
reset
setup_ha_plugin
calls | grep -qx 'enable homeassistant-config@claude-homeassistant-plugins' || fail "option back on must enable: $(calls)"
[ "$(cat "$FAKE/enabled")" = true ] || fail "plugin should be enabled again"

# 5. A failed install or update writes no state, so the next start tries again.
rm -rf "${FAKE:?}"/* "$HOME/.claude"
touch "$FAKE/fail-install"
reset
setup_ha_plugin || fail "a failed install must not fail the start"
[ ! -e "$state_file" ] || fail "a failed install must not write the state file"
grep -q '^warning|Home Assistant plugin: install failed' "$log" || fail "failed install not logged: $(cat "$log")"
rm -f "$FAKE/fail-install"
reset
setup_ha_plugin
calls | grep -qx 'install homeassistant-config@claude-homeassistant-plugins' || fail "the next start must retry the install"
bundle 2.1.5
touch "$FAKE/fail-update"
reset
setup_ha_plugin || fail "a failed update must not fail the start"
[ "$(cat "$state_file")" = 'true:2.1.4' ] || fail "a failed update must keep the old state, has '$(cat "$state_file")'"
rm -f "$FAKE/fail-update"
reset
setup_ha_plugin
calls | grep -qx 'update homeassistant-config@claude-homeassistant-plugins' || fail "the next start must retry the update"
[ "$(cat "$state_file")" = 'true:2.1.5' ] || fail "state not written after the retried update"

# 6. Option off on a fresh install never installs it.
rm -rf "${FAKE:?}"/* "$HOME/.claude"
config_ha_plugin=false
reset
setup_ha_plugin
calls | grep -q '^install ' && fail "option off must not install"
config_ha_plugin=true

# 7. Not bundled or no claude: logged, no failure.
rm -rf "$HOME/.claude"
HA_PLUGIN_MARKETPLACE_DIR="$tmp_dir/missing" setup_ha_plugin || fail "missing bundle must not fail"
( PATH="/usr/bin:/bin"; setup_ha_plugin ) || fail "missing claude must not fail"

# 8. A hanging CLI is cut off; the start goes on.
rm -rf "${FAKE:?}"/* "$HOME/.claude"
touch "$FAKE/hang"
reset
started=$SECONDS
setup_ha_plugin || fail "a hanging CLI must not fail the start"
[ $((SECONDS - started)) -lt 15 ] || fail "a hanging CLI held the start for $((SECONDS - started))s"
[ ! -e "$state_file" ] || fail "a cut-off install must not write the state file"
rm -f "$FAKE/hang"

# 9. Options unreadable (Supervisor silent): no CLI call, state unchanged (R2).
reset
setup_ha_plugin
before=$(cat "$state_file")
config_ha_plugin=false
options_unreadable=true
reset
setup_ha_plugin || fail "unreadable options must not fail the start"
[ -z "$(calls)" ] || fail "unreadable options must not touch the plugin: $(calls)"
[ "$(cat "$state_file")" = "$before" ] || fail "unreadable options changed the state file"
grep -q 'could not be read' "$log" || fail "unreadable options not logged: $(cat "$log")"
options_unreadable=false
rm -f "$OPTION_READ_GAVE_UP"

# 10. An open takeover offer: nothing written to ~/.claude this start (R1).
rm -rf "${FAKE:?}"/* "$HOME/.claude"
printf '{}\n' > "$APP_MIGRATION_OFFER"
config_ha_plugin=true
reset
setup_ha_plugin || fail "an open takeover offer must not fail the start"
[ -z "$(calls)" ] || fail "an open takeover offer must not touch the plugin: $(calls)"
[ ! -e "$HOME/.claude" ] || fail "an open takeover offer must leave ~/.claude alone"
grep -q 'takeover' "$log" || fail "skipping for the takeover not logged: $(cat "$log")"
rm -f "$APP_MIGRATION_OFFER"

# 11. State file cannot be written: a warning, no failure (set -e, inherit_errexit).
rm -rf "${FAKE:?}"/* "$HOME/.claude"
mkdir -p "$HOME"
: > "$HOME/.claude"
reset
setup_ha_plugin || fail "an unwritable state file must not fail the start"
grep -q '^warning|' "$log" || fail "an unwritable state file was not reported: $(cat "$log")"
rm -f "$HOME/.claude"

echo "ha plugin setup: all checks passed"
