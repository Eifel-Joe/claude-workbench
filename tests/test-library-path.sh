#!/usr/bin/env bash
# /data/packages/lib (libraries copied by persist-install) must reach only the
# programs in the terminal session, never the app's own services (n10): one
# broken copy there used to take down node (the panel's entry point), ttyd and
# the tmux server. The session 'claude' gets it through its tmux session
# environment, from both places that create the session.
set -euo pipefail
# Like bashio 0.19.0, which run.sh runs under.
shopt -s inherit_errexit

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
run_sh="$repo_root/claude-workbench/run.sh"
# pwd: a PATH entry must not contain a drive colon (Git Bash with TMPDIR=D:/...).
tmp_dir=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
    echo "FAIL (library path): $*" >&2
    exit 1
}

persist_lib=/data/packages/lib

# 1. run.sh sets LD_LIBRARY_PATH for nothing it starts itself, in any form
# (export, a prefix assignment, env). Allowed: the profile script for login
# shells, the tmux-claude wrapper and the `new-session -e` value - all for the
# terminal session. Comments do not count.
own_settings=$(sed -e "/<< 'PROFILE_EOF'/,/^PROFILE_EOF/d" \
        -e "/<< 'WRAPPER_EOF'/,/^WRAPPER_EOF/d" "$run_sh" | \
    grep -vE '^[[:space:]]*#' | \
    grep -E 'LD_LIBRARY_PATH=|export[[:space:]]+LD_LIBRARY_PATH' | \
    grep -vF -- '-e "LD_LIBRARY_PATH=$(terminal_library_path)"' || true)
[ -z "$own_settings" ] || \
    fail "run.sh sets LD_LIBRARY_PATH for its own processes (node, ttyd, tmux server): $own_settings"
sed -n "/<< 'PROFILE_EOF'/,/^PROFILE_EOF/p" "$run_sh" | \
    grep -q "^export LD_LIBRARY_PATH=\"$persist_lib:" || \
    fail "the profile script for login shells must keep $persist_lib"

# Stand-ins for tmux and ttyd: they log their arguments and what they see in
# LD_LIBRARY_PATH. No session exists, so every caller creates one.
fake_bin="$tmp_dir/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/tmux" << EOF
#!/usr/bin/env bash
[ "\$1" = has-session ] && exit 1
printf 'args|%s\n' "\$*" >> "$tmp_dir/tmux.log"
printf 'env|%s\n' "\${LD_LIBRARY_PATH-}" >> "$tmp_dir/tmux.log"
exit 0
EOF
cat > "$fake_bin/ttyd" << EOF
#!/usr/bin/env bash
printf '%s\n' "\${LD_LIBRARY_PATH-}" > "$tmp_dir/ttyd.env"
exit 0
EOF
chmod +x "$fake_bin/tmux" "$fake_bin/ttyd"

bashio::log.info() { :; }
bashio::log.warning() { :; }
bashio::log.error() { :; }
bashio::config() { printf '%s\n' "${2:-}"; }
# shellcheck disable=SC2034  # read by the sourced run.sh
OPTION_READ_GAVE_UP="$tmp_dir/options-unanswered"
# shellcheck disable=SC2034  # read by the sourced run.sh
CLAUDE_RUN_SH_SKIP_MAIN=true
# shellcheck source=/dev/null
source "$run_sh"

HOME="$tmp_dir/home"
# shellcheck disable=SC2034  # read by the sourced run.sh
ANTHROPIC_CONFIG_DIR="$tmp_dir/claude"
mkdir -p "$HOME"
TMUX_WRAPPER_PATH="$tmp_dir/tmux-claude"
# shellcheck disable=SC2034  # read by the sourced run.sh
APP_MIGRATION_OFFER="$tmp_dir/no-offer.json"
PATH="$fake_bin:$PATH"
# Whatever run.sh itself has stays behind the folder in the session.
export LD_LIBRARY_PATH=/opt/system-extra
expected_session="LD_LIBRARY_PATH=$persist_lib:/opt/system-extra"

# 2. start_web_terminal: the session gets the folder, tmux server and ttyd not.
( start_web_terminal ) || fail "start_web_terminal failed"
grep '^args|new-session' "$tmp_dir/tmux.log" | grep -qF -- "-e $expected_session" || \
    fail "start_web_terminal creates the tmux session without -e $expected_session: $(grep '^args|' "$tmp_dir/tmux.log")"
grep -q "^env|.*$persist_lib" "$tmp_dir/tmux.log" && \
    fail "the tmux server was started with $persist_lib on LD_LIBRARY_PATH"
[ -f "$tmp_dir/ttyd.env" ] || fail "ttyd was not started"
grep -q "$persist_lib" "$tmp_dir/ttyd.env" && fail "ttyd was started with $persist_lib on LD_LIBRARY_PATH"
[ "$(cat "$tmp_dir/ttyd.env")" = /opt/system-extra ] || \
    fail "ttyd lost the LD_LIBRARY_PATH run.sh had: '$(cat "$tmp_dir/ttyd.env")'"

# 3. The wrapper ttyd runs creates the session again after Claude's session ended.
rm -f "$tmp_dir/tmux.log"
setup_tmux
bash "$TMUX_WRAPPER_PATH" || fail "the tmux wrapper failed"
grep '^args|new-session' "$tmp_dir/tmux.log" | grep -qF -- "-e $expected_session" || \
    fail "the tmux wrapper creates the session without -e $expected_session: $(grep '^args|' "$tmp_dir/tmux.log")"

echo "Library path suite passed"
