#!/usr/bin/env bash
# The Home Assistant status line under Claude's prompt (p18):
# scripts/ha-statusline.sh draws it, setup_statusline in run.sh installs it.
# Most cases come from ESJavadex's tests/test-statusline.sh
# (ESJavadex/claude-code-ha@ae4f88ec, dde63c98, 7b558af0, 6422e800; the
# context icon spacing from Neil Sleightholm, 823f14da). Added here: the
# Supervisor token goes only to the absolute curl (HA_STATUSLINE_CURL) and only
# on stdin; setup_statusline never ends the start (set -e, inherit_errexit),
# changes nothing while the options cannot be read or a data takeover offer
# is open.
set -euo pipefail
# Like bashio 0.19.0, which run.sh runs under.
shopt -s inherit_errexit

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# pwd: a PATH entry must not contain a drive colon (Git Bash with TMPDIR=D:/...).
tmp_dir=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$tmp_dir"' EXIT
script="$repo_root/claude-workbench/scripts/ha-statusline.sh"

fail() {
    echo "FAIL (status line): $*" >&2
    exit 1
}

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }
# A file:// URL curl can read: Windows builds of curl need the drive letter.
file_url() {
    if command -v cygpath > /dev/null 2>&1; then
        printf 'file:///%s' "$(cygpath -m "$1")"
    else
        printf 'file://%s' "$1"
    fi
}

[ -f "$script" ] || fail "claude-workbench/scripts/ha-statusline.sh is missing"

# --- ha-statusline: the script Claude Code runs -----------------------------

real_curl=$(command -v curl) || fail "the tests need curl"
export HA_STATUSLINE_CURL="$real_curl"
export HA_STATUSLINE_CACHE_DIR="$tmp_dir/cache"
export HA_STATUSLINE_CONFIG="$tmp_dir/ha-statusline.json"
HA_STATUSLINE_API=$(file_url "$tmp_dir/api")
HA_STATUSLINE_SUPERVISOR_API=$(file_url "$tmp_dir/sup")
export HA_STATUSLINE_API HA_STATUSLINE_SUPERVISOR_API
export SUPERVISOR_TOKEN=test-token
export TZ=UTC
# The folder piece shows a git branch; the temp folder may sit inside a
# checkout (.tmp in the repo), so git must not look above it.
export GIT_CEILING_DIRECTORIES="${tmp_dir%/*}"
mkdir -p "$tmp_dir/api" "$tmp_dir/sup/core" "$tmp_dir/sup/host" "$tmp_dir/sup/resolution"

# A friendly name carrying an escape sequence must not reach the terminal
cat > "$tmp_dir/api/states" << 'STATES'
[
  {"entity_id": "person.ana", "state": "home", "attributes": {}},
  {"entity_id": "person.ben", "state": "not_home", "attributes": {}},
  {"entity_id": "light.hall", "state": "unavailable", "attributes": {}},
  {"entity_id": "automation.broken", "state": "unavailable", "attributes": {}},
  {"entity_id": "automation.fine", "state": "on", "attributes": {}},
  {"entity_id": "sensor.door_battery", "state": "12", "attributes": {"device_class": "battery", "friendly_name": "Door\u001b]0;pwned\u0007"}},
  {"entity_id": "sensor.ok_battery", "state": "90", "attributes": {"device_class": "battery"}},
  {"entity_id": "sensor.gone_battery", "state": "unknown", "attributes": {"device_class": "battery"}},
  {"entity_id": "sensor.car_battery", "state": "8", "attributes": {"device_class": "battery"}, "last_reported": "STALE"},
  {"entity_id": "binary_sensor.smoke", "state": "on", "attributes": {"device_class": "smoke", "friendly_name": "Kitchen smoke"}},
  {"entity_id": "binary_sensor.motion", "state": "on", "attributes": {"device_class": "motion"}},
  {"entity_id": "update.core", "state": "on", "attributes": {}},
  {"entity_id": "weather.home", "state": "sunny", "attributes": {"temperature": 18, "temperature_unit": "°C"}},
  {"entity_id": "sensor.co2", "state": "820", "attributes": {"unit_of_measurement": "ppm", "friendly_name": "Living CO2"}}
]
STATES
# The parked car last reported three days ago: its level is old news
sed -i "s/STALE/$(date -u -d "@$(( $(date +%s) - 3 * 86400 ))" +%Y-%m-%dT%H:%M:%S.123456+00:00)/" "$tmp_dir/api/states"
old_backup=$(date -u -d "@$(( $(date +%s) - 10 * 86400 ))" +%Y-%m-%dT%H:%M:%S.123456+00:00)
printf '{"result":"ok","data":{"version":"2026.10.3","version_latest":"2026.11.0","update_available":true}}' > "$tmp_dir/sup/core/info"
printf '{"result":"ok","data":{"disk_total":100,"disk_used":91}}' > "$tmp_dir/sup/host/info"
printf '{"result":"ok","data":{"backups":[{"date":"%s"}]}}' "$old_backup" > "$tmp_dir/sup/backups"
# no_current_backup is left to the backup piece
printf '{"result":"ok","data":{"unhealthy":[],"unsupported":[],"issues":[{"type":"no_current_backup"},{"type":"multiple_data_disks"}]}}' > "$tmp_dir/sup/resolution/info"

all_home='alerts repairs automations backup disk core updates unavailable battery people weather'
printf '%s' "$all_home" | jq -Rc 'split(" ") | map({s: .}) + [{s: "entity", id: "sensor.co2", label: "CO2"}, {s: "entity", id: "sensor.nope", label: ""}] | {layout: .}' \
    > "$HA_STATUSLINE_CONFIG"

"$script" --refresh || fail "--refresh failed against the test API"
home=$("$script" --home)
case "$home" in *$'\e]'*|*$'\a'*) fail "escape sequence from an entity name reached the output" ;; esac
home=$(strip_ansi <<< "$home")
for want in "🏠 🚨 Kitchen smoke" "🩺 multiple data disks" "🤖 1 broken" "💾 10d" "💽 91%" "⬆ HA 2026.11.0" \
            "📦 1" "⚠ 2 unavailable" "🔋 Door]0;pwned" "👥 1/2" "☀ 18°C" "CO2 820 ppm" "sensor.nope missing"; do
    [[ "$home" == *"$want"* ]] || fail "home line lacks '$want': $home"
done
[[ "$home" != *motion* ]] || fail "motion is not an alert: $home"
[[ "$home" != *"no current backup"* ]] || fail "no_current_backup is the backup piece's job: $home"

# Excluded entities leave the home pieces; an entity piece still shows
jq '.exclude = ["light.*", "sensor.door_*", "sensor.co2"]' "$HA_STATUSLINE_CONFIG" > "$tmp_dir/x.json" \
    && cp "$tmp_dir/x.json" "$HA_STATUSLINE_CONFIG"
"$script" --refresh || fail "--refresh with exclusions failed"
home=$("$script" --home | strip_ansi)
[[ "$home" == *"⚠ 1 unavailable"* ]] || fail "light.* should be excluded from unavailable: $home"
[[ "$home" != *"🔋"* ]] || fail "excluded and stale batteries should not show: $home"
[[ "$home" == *"CO2 820 ppm"* ]] || fail "an exclusion must not hide an entity piece: $home"
jq 'del(.exclude)' "$HA_STATUSLINE_CONFIG" > "$tmp_dir/x.json" && cp "$tmp_dir/x.json" "$HA_STATUSLINE_CONFIG"
"$script" --refresh || fail "refresh failed"
[ "$(wc -l <<< "$home")" -eq 1 ] || fail "--home should be one line"

# Default layout: two short lines, Claude then the home. Pieces with nothing
# to say are left out; a reset time only shows once half the limit is used.
# Two spaces after the context icon: xterm.js gives ✍️ one cell (nsleigh).
rm -f "$HA_STATUSLINE_CONFIG"
claude_json=$(jq -nc --arg d "$tmp_dir" '{model: {display_name: "Opus"}, workspace: {current_dir: $d},
    context_window: {used_percentage: 63.4, total_input_tokens: 45210, total_output_tokens: 3100},
    cost: {total_duration_ms: 4320000, total_lines_added: 12, total_lines_removed: 3},
    rate_limits: {five_hour: {used_percentage: 38, resets_at: 1800000000},
                  seven_day: {used_percentage: 95, resets_at: 1800000000}}}')
# The weekday name follows the machine's locale (jq's strflocaltime).
reset_at=$(jq -rn '1800000000 | strflocaltime("%a %H:%M")')
out=$("$script" <<< "$claude_json" | strip_ansi)
[ "$(wc -l <<< "$out")" -eq 2 ] || fail "expected two lines: $out"
[ "$(sed -n 1p <<< "$out")" = "Opus │ ✍️  37% │ $(basename "$tmp_dir") │ 5h 62% │ 7d 5% ⟳ $reset_at" ] || \
    fail "line 1 wrong: $(sed -n 1p <<< "$out")"
[[ "$(sed -n 2p <<< "$out")" == "🏠 🚨 Kitchen smoke │ 🩺 multiple data disks"* ]] || fail "line 2 wrong: $(sed -n 2p <<< "$out")"
[[ "$out" != *"👥"* && "$out" != *"☀"* && "$out" != *"unavailable"* ]] || \
    fail "people, weather and unavailable are not in the default layout: $out"

# API-key users have no rate limits: the cost is shown instead
out=$(jq -c 'del(.rate_limits) | .cost.total_cost_usd = 0.4213' <<< "$claude_json" | "$script" | strip_ansi)
[[ "$(sed -n 1p <<< "$out")" == *'│ $0.42' ]] || fail "cost not shown: $(sed -n 1p <<< "$out")"

# A new session: empty pieces disappear
out=$("$script" < /dev/null | strip_ansi)
[ "$(sed -n 1p <<< "$out")" = "Claude │ ✍️  100%" ] || fail "empty input line 1: $(sed -n 1p <<< "$out")"
[ "$(wc -l <<< "$out")" -eq 2 ] || fail "expected the Claude line and the home line: $out"

# A line that only has Claude pieces with nothing to say is dropped
printf '{"layout":[{"s":"model"},{"s":"---"},{"s":"usage"},{"s":"tokens"}]}' > "$HA_STATUSLINE_CONFIG"
[ "$("$script" < /dev/null | strip_ansi)" = "Claude" ] || fail "an empty line should be dropped"
rm -f "$HA_STATUSLINE_CONFIG"

# All fine at home: a short check mark
printf '[]' > "$tmp_dir/api/states"
printf '{"result":"ok","data":{"disk_total":100,"disk_used":40}}' > "$tmp_dir/sup/host/info"
printf '{"result":"ok","data":{"backups":[{"date":"%s"}]}}' "$(date -u +%Y-%m-%dT%H:%M:%S+00:00)" > "$tmp_dir/sup/backups"
printf '{"result":"ok","data":{"update_available":false}}' > "$tmp_dir/sup/core/info"
printf '{"result":"ok","data":{"unhealthy":[],"issues":[]}}' > "$tmp_dir/sup/resolution/info"
HA_STATUSLINE_SUPERVISOR_TTL=0 "$script" --refresh || fail "refresh failed"
[ "$("$script" --home | strip_ansi)" = "🏠 ✓" ] || fail "a healthy home should be just 🏠 ✓: $("$script" --home | strip_ansi)"

# Home Assistant down: an error line, never a failure
HA_STATUSLINE_API=$(file_url "$tmp_dir/missing") "$script" --refresh 2>/dev/null && \
    fail "--refresh should fail when Home Assistant is unreachable"
[ "$("$script" --home | strip_ansi)" = "🏠 Home Assistant unreachable" ] || fail "unreachable HA should say so"

# No cache yet: a background refresh starts and the line doesn't wait for it
rm -rf "$HA_STATUSLINE_CACHE_DIR"
[ "$("$script" --home | strip_ansi)" = "🏠 …" ] || fail "first run should show the loading mark"
for _ in $(seq 1 20); do
    [ -s "$HA_STATUSLINE_CACHE_DIR/states.json" ] && break
    sleep 0.3
done
[ -s "$HA_STATUSLINE_CACHE_DIR/states.json" ] || fail "background refresh never wrote the cache"

# A layout with only Claude pieces never touches Home Assistant
rm -rf "$HA_STATUSLINE_CACHE_DIR"
printf '{"layout":[{"s":"model"}]}' > "$HA_STATUSLINE_CONFIG"
[ "$("$script" < /dev/null | strip_ansi)" = "Claude" ] || fail "model-only layout"
sleep 0.5
[ ! -e "$HA_STATUSLINE_CACHE_DIR/states.json" ] || fail "a Claude-only layout should not refresh"
rm -f "$HA_STATUSLINE_CONFIG"

# --- The Supervisor token ---------------------------------------------------

# A curl stand-in that records its arguments and what it got on stdin.
mkdir -p "$tmp_dir/fakebin" "$tmp_dir/pathbin"
cat > "$tmp_dir/fakebin/curl" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp_dir/curl-args"
cat >> "$tmp_dir/curl-stdin"
exit 1
EOF
# A curl planted on PATH (e.g. by persist-install) must never run: the script
# calls the absolute HA_STATUSLINE_CURL.
cat > "$tmp_dir/pathbin/curl" << EOF
#!/usr/bin/env bash
touch "$tmp_dir/path-curl-called"
exit 1
EOF
chmod +x "$tmp_dir/fakebin/curl" "$tmp_dir/pathbin/curl"

# Any URL but http(s)://supervisor is refused before curl runs
for url in "https://evil.example/api" "http://supervisor.evil.example/core/api" "http://supervisor@evil.example/" \
        "http://supervisor:8123/core/api" "http://supervisor/core/api?x=@evil.example"; do
    rm -f "$tmp_dir/curl-args"
    err=$(HA_STATUSLINE_CURL="$tmp_dir/fakebin/curl" HA_STATUSLINE_API="$url" HA_STATUSLINE_SUPERVISOR_API="$url" \
        "$script" --refresh 2>&1) && fail "$url accepted"
    [[ "$err" == *"refusing to send the Supervisor token"* ]] || fail "$url: no refusal message: $err"
    [ ! -e "$tmp_dir/curl-args" ] || fail "curl ran for $url"
done

# The real Supervisor URL: the token reaches curl on stdin, never in its
# arguments (ps would show them); redirects are not followed.
rm -f "$tmp_dir/curl-args" "$tmp_dir/curl-stdin"
rm -rf "$HA_STATUSLINE_CACHE_DIR"
PATH="$tmp_dir/pathbin:$PATH" HA_STATUSLINE_CURL="$tmp_dir/fakebin/curl" \
    HA_STATUSLINE_API="http://supervisor/core/api" HA_STATUSLINE_SUPERVISOR_API="http://supervisor" \
    "$script" --refresh 2>/dev/null || true
[ -e "$tmp_dir/curl-args" ] || fail "the real Supervisor URL should be allowed"
grep -q 'test-token' "$tmp_dir/curl-args" && fail "the token is in curl's arguments: $(cat "$tmp_dir/curl-args")"
grep -q 'Authorization: Bearer test-token' "$tmp_dir/curl-stdin" || \
    fail "the token did not reach curl on stdin: $(cat "$tmp_dir/curl-stdin" 2>/dev/null)"
grep -qE '(^| )(-L|--location)( |$)' "$tmp_dir/curl-args" && fail "curl follows redirects: $(cat "$tmp_dir/curl-args")"
[ ! -e "$tmp_dir/path-curl-called" ] || fail "a curl planted on PATH received the Supervisor request"
grep -q "http://supervisor/core/api/states" "$tmp_dir/curl-args" || fail "states were not requested: $(cat "$tmp_dir/curl-args")"
# The default is the image's curl, by absolute path.
grep -qF 'CURL="${HA_STATUSLINE_CURL:-/usr/bin/curl}"' "$script" || \
    fail "the script must default to /usr/bin/curl, not curl from PATH"

# --- setup_statusline in run.sh ---------------------------------------------

: > "$tmp_dir/info"
: > "$tmp_dir/warnings"
bashio::log.info() { printf '%s\n' "$*" >> "$tmp_dir/info"; }
bashio::log.warning() { printf '%s\n' "$*" >> "$tmp_dir/warnings"; }
bashio::log.error() { printf '%s\n' "$*" >> "$tmp_dir/warnings"; }
config_statusline=''
options_unreadable=false
bashio::config() {
    [ "$options_unreadable" = false ] || return 1
    case "$1" in
        statusline) printf '%s\n' "$config_statusline" ;;
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

HOME="$tmp_dir/home"
# Relative, and the user's command below has no leading slash: Git Bash turns a
# /d/... argument for the native Windows jq into D:/..., and the stored
# command would no longer match. Same meaning on Linux.
cd "$tmp_dir"
export HA_STATUSLINE_BIN="bin/ha-statusline"
export HA_STATUSLINE_SOURCE="$script"
export APP_MIGRATION_OFFER="$tmp_dir/offer.json"
settings="$HOME/.claude/settings.json"
mkdir -p "$tmp_dir/bin"

# No settings yet: ours is added, with the default layout
setup_statusline || fail "setup_statusline failed"
[ -x "$HA_STATUSLINE_BIN" ] || fail "script not installed"
[ "$(jq -r '.statusLine.command' "$settings")" = "$HA_STATUSLINE_BIN" ] || fail "status line not added"
[ "$(jq -r '.statusLine.refreshInterval' "$settings")" = 30 ] || fail "refreshInterval not set"
[ "$(jq -c '.layout' "$HA_STATUSLINE_CONFIG")" = null ] || fail "empty option should mean the default layout"

# A missing option (bashio prints "null", read_option makes it empty) is the
# default too, never a piece named null
config_statusline=null
: > "$tmp_dir/warnings"
setup_statusline
[ "$(jq -c '.layout' "$HA_STATUSLINE_CONFIG")" = null ] || fail "null option should mean the default layout"
grep -q null "$tmp_dir/warnings" && fail "a missing option was read as a piece named null"

# Other settings survive
jq '.theme = "dark"' "$settings" > "$settings.new" && mv "$settings.new" "$settings"
setup_statusline
[ "$(jq -r '.theme' "$settings")" = dark ] || fail "other settings were lost"

# The user's pieces, in order: names, line breaks, entities with and without
# labels. Anything else is skipped with a warning.
: > "$tmp_dir/warnings"
config_statusline='["model", " context ", "---", "CO₂=sensor.air_co2", "sensor.temp", "people", "$(reboot)", "Bad=../../etc", "nonsense", "-sensor.car_*", " -light.coffee_machine ", "-$(reboot)", "-*"]'
setup_statusline
[ "$(jq -c '.layout' "$HA_STATUSLINE_CONFIG")" = \
  '[{"s":"model"},{"s":"context"},{"s":"---"},{"s":"entity","id":"sensor.air_co2","label":"CO₂"},{"s":"entity","id":"sensor.temp","label":""},{"s":"people"}]' ] || \
    fail "layout parsed wrong: $(jq -c '.layout' "$HA_STATUSLINE_CONFIG")"
[ "$(jq -c '.exclude' "$HA_STATUSLINE_CONFIG")" = '["sensor.car_*","light.coffee_machine"]' ] || \
    fail "exclusions parsed wrong: $(jq -c '.exclude' "$HA_STATUSLINE_CONFIG")"
[ "$(grep -c skipping "$tmp_dir/warnings")" -eq 5 ] || fail "invalid items should be warned about"

# Only exclusions: the default layout, with them applied
config_statusline='["-sensor.car_*"]'
setup_statusline
[ "$(jq -c '[.layout, .exclude]' "$HA_STATUSLINE_CONFIG")" = '[null,["sensor.car_*"]]' ] || \
    fail "exclusions alone should keep the default layout"

# off removes ours only, and keeps other settings
config_statusline='["off"]'
setup_statusline
[ "$(jq -r 'has("statusLine")' "$settings")" = false ] || fail "off should remove our status line"
[ "$(jq -r '.theme' "$settings")" = dark ] || fail "off lost other settings"

# A status line the user made (e.g. with /statusline) is never touched.
# Its command may carry a secret, so it never reaches the log.
user_cmd="my-statusline --token s3cr3t-value"
jq --arg c "$user_cmd" '.statusLine = {type: "command", command: $c}' "$settings" > "$settings.new" \
    && mv "$settings.new" "$settings"
config_statusline=''
: > "$tmp_dir/info"
setup_statusline
[ "$(jq -r '.statusLine.command' "$settings")" = "$user_cmd" ] || fail "user status line replaced"
grep -q 'keeping your own' "$tmp_dir/info" || fail "keeping the user's status line should be logged"
grep -q 's3cr3t-value' "$tmp_dir/info" "$tmp_dir/warnings" && fail "the user's status line command reached the log"
config_statusline='["off"]'
setup_statusline
[ "$(jq -r '.statusLine.command' "$settings")" = "$user_cmd" ] || fail "off removed the user's status line"

# Invalid JSON is left as it is
printf '{ broken' > "$settings"
config_statusline=''
setup_statusline
[ "$(cat "$settings")" = '{ broken' ] || fail "invalid settings.json was rewritten"

# off with no settings file creates nothing
rm -f "$settings"
config_statusline='["off"]'
setup_statusline
[ ! -e "$settings" ] || fail "off should not create settings.json"

# Options unreadable (Supervisor silent): settings.json and the layout stay
# as they are (R2); the script is installed anyway.
config_statusline=''
setup_statusline
cp "$settings" "$tmp_dir/settings.before"
cp "$HA_STATUSLINE_CONFIG" "$tmp_dir/config.before"
config_statusline='["off"]'
options_unreadable=true
rm -f "$HA_STATUSLINE_BIN"
: > "$tmp_dir/warnings"
setup_statusline || fail "unreadable options must not fail the start"
cmp -s "$settings" "$tmp_dir/settings.before" || fail "unreadable options changed settings.json"
cmp -s "$HA_STATUSLINE_CONFIG" "$tmp_dir/config.before" || fail "unreadable options changed the layout"
[ -x "$HA_STATUSLINE_BIN" ] || fail "the script must be installed even when the options cannot be read"
grep -q 'could not be read' "$tmp_dir/warnings" || fail "unreadable options not logged"
options_unreadable=false
rm -f "$OPTION_READ_GAVE_UP"

# An open data takeover offer: no settings.json written this start (R1)
rm -rf "$HOME/.claude"
printf '{}\n' > "$APP_MIGRATION_OFFER"
config_statusline=''
setup_statusline || fail "an open takeover offer must not fail the start"
[ ! -e "$settings" ] || fail "an open takeover offer must leave ~/.claude alone"
[ -x "$HA_STATUSLINE_BIN" ] || fail "the script must be installed while a takeover offer is open"
rm -f "$APP_MIGRATION_OFFER"

# Nothing can be written (e.g. /data full): warnings, never the end of the start
: > "$HOME/.claude"
HA_STATUSLINE_CONFIG="$tmp_dir/no-such-dir-file/x/ha-statusline.json"
: > "$tmp_dir/no-such-dir-file"
: > "$tmp_dir/warnings"
setup_statusline || fail "an unwritable settings folder must not fail the start"
grep -q . "$tmp_dir/warnings" || fail "an unwritable settings folder was not reported"
HA_STATUSLINE_BIN="$tmp_dir/no-such-dir-file/ha-statusline" setup_statusline || \
    fail "an uninstallable script must not fail the start"
rm -f "$HOME/.claude"

echo "Status line tests passed"
