#!/usr/bin/env bash
# bashio 0.19.0 turns an empty default into the word "null"
# (`local default_value=${2:-null}` in lib/config.sh): an option that is
# missing from the configuration, or set to JSON null, came back from
# `read_option 'x' ''` as "null" (n21). Claude then started with
# `--remote-control null`, and the package lists ran `persist-install null`.
# The stand-in below follows bashio 0.19.0's bashio::config line by line, with
# the options read from a JSON file instead of the Supervisor.
set -euo pipefail
# Like bashio 0.19.0, which run.sh runs under.
shopt -s inherit_errexit

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
run_sh="$repo_root/claude-workbench/run.sh"
tmp_dir=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
    echo "FAIL (option null): $*" >&2
    exit 1
}

log="$tmp_dir/log"
: > "$log"
bashio::log.info() { printf 'info|%s\n' "$*" >> "$log"; }
bashio::log.warning() { printf 'warning|%s\n' "$*" >> "$log"; }
bashio::log.error() { printf 'error|%s\n' "$*" >> "$log"; }

options_json="$tmp_dir/options.json"
# bashio::config 0.19.0: same null handling, same default. Its jq query is
# replayed in node (jq is not on every developer machine): missing or null ->
# "null", a string as is, a boolean as true/false, an array one item per line
# (none for []), anything else as JSON.
bashio::config() {
    local key=${1}
    local default_value=${2:-null}
    local result
    result=$(node -e '
        const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
        const v = o[process.argv[2]];
        let out;
        if (v === undefined || v === null) out = "null";
        else if (typeof v === "string" || typeof v === "boolean") out = String(v);
        else if (Array.isArray(v)) out = v.map((x) => typeof x === "string" ? x : JSON.stringify(x)).join("\n");
        else out = JSON.stringify(v);
        process.stdout.write(out);' "$options_json" "$key")
    if [[ "${result}" == "null" ]]; then
        echo "${default_value}"
    else
        printf "%s" "${result}"
    fi
    return 0
}
set_options() { printf '%s\n' "$1" > "$options_json"; }

# shellcheck disable=SC2034  # read by the sourced run.sh
OPTION_READ_GAVE_UP="$tmp_dir/options-unanswered"
# shellcheck disable=SC2034  # read by the sourced run.sh
CLAUDE_RUN_SH_SKIP_MAIN=true
# shellcheck source=/dev/null
source "$run_sh"

# 1. A missing text option with an empty default reads as empty.
set_options '{}'
value=$(read_option 'remote_control_session_name' '')
[ "$value" = '' ] || fail "read_option returned '$value' for a missing option (expected empty)"

# 2. An explicit JSON null reads as empty too.
set_options '{"remote_control_session_name": null}'
value=$(read_option 'remote_control_session_name' '')
[ "$value" = '' ] || fail "read_option returned '$value' for a null option (expected empty)"

# A non-empty default still comes through for a missing option.
set_options '{}'
value=$(read_option 'auto_launch_claude' 'true')
[ "$value" = 'true' ] || fail "read_option lost the default 'true': '$value'"

# 3. Remote Control without a session name: no "null" in the launch command.
set_options '{"auto_launch_claude": true, "remote_control": true}'
launch=$(get_claude_launch_command)
case "$launch" in
    *"--remote-control"*) ;;
    *) fail "Remote Control flag missing from the launch command: $launch" ;;
esac
case "$launch" in
    *" null"*) fail "the launch command passes 'null' as the session name: $launch" ;;
esac

# 6a. A set session name arrives quoted, in one piece.
set_options '{"auto_launch_claude": true, "remote_control": true, "remote_control_session_name": "Wohnzimmer Pi"}'
launch=$(get_claude_launch_command)
case "$launch" in
    *"--remote-control Wohnzimmer\\ Pi"*) ;;
    *) fail "the session name did not arrive as one argument: $launch" ;;
esac

# 4. Missing package lists install nothing.
persist_log="$tmp_dir/persist-install.log"
: > "$persist_log"
cat > "$tmp_dir/persist-install" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$persist_log"
EOF
chmod +x "$tmp_dir/persist-install"
export PERSIST_INSTALL_BIN="$tmp_dir/persist-install"
set_options '{}'
auto_install_packages
[ ! -s "$persist_log" ] || fail "missing package lists ran persist-install: $(cat "$persist_log")"
grep -q 'Installing: null' "$log" && fail "the log shows an install of a package named null"

# 6b. Set package lists still install.
set_options '{"persistent_apk_packages": ["git"], "persistent_pip_packages": ["requests"]}'
auto_install_packages
grep -qx -- '--apk git' "$persist_log" || fail "the apk package list was not installed: $(cat "$persist_log")"
grep -qx -- '--python requests' "$persist_log" || \
    fail "the pip package list was not installed: $(cat "$persist_log")"

# 5. A missing image_retention_days counts as unreadable and deletes nothing.
export IMAGE_UPLOAD_DIR="$tmp_dir/images"
mkdir -p "$IMAGE_UPLOAD_DIR"
touch -d '400 days ago' "$IMAGE_UPLOAD_DIR/pasted-old.png"
: > "$log"
set_options '{}'
prune_uploaded_images
[ -e "$IMAGE_UPLOAD_DIR/pasted-old.png" ] || fail "a missing image_retention_days deleted an image"
grep -q 'image_retention_days could not be read' "$log" || \
    fail "a missing image_retention_days was not reported as unreadable: $(cat "$log")"

echo "Option null tests passed"
