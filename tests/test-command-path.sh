#!/usr/bin/env bash
# Programs that persist-install put in /data/packages/bin (and the venv's bin)
# must not shadow the system's for run.sh and the app's services (n20): bashio
# calls curl and jq by name, the panel runs node by name. A copy there used to
# come first on PATH for all of them. In the terminal session 'claude' the
# persistent programs stay first, so what the user installed still wins there.
# Idea from unsnow-iac (08686e1e, 83c6997e; miczu71's fork, history/unsnow-full).
set -euo pipefail
# Like bashio 0.19.0, which run.sh runs under.
shopt -s inherit_errexit

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
run_sh="$repo_root/claude-workbench/run.sh"
# pwd: a PATH entry must not contain a drive colon (Git Bash with TMPDIR=D:/...).
tmp_dir=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
    echo "FAIL (command path): $*" >&2
    exit 1
}

# 4a. The defaults name the three persistent folders, and login shells keep
# them first (profile script).
grep -qF 'PERSIST_PATHS="${PERSIST_PATHS:-/data/packages/bin:/data/packages/python/venv/bin:/data/home/.local/bin}"' "$run_sh" || \
    fail "run.sh does not define PERSIST_PATHS with the three persistent folders"
sed -n "/<< 'PROFILE_EOF'/,/^PROFILE_EOF/p" "$run_sh" | \
    grep -qF 'export PATH="/data/packages/bin:/data/packages/python/venv/bin:/data/home/.local/bin:$PATH"' || \
    fail "the profile script for login shells must keep the persistent folders first"
# init_environment takes its PATH from boot_path, nothing puts them first there.
init_body=$(sed -n '/^init_environment() {/,/^}/p' "$run_sh" | sed -e "/<< 'PROFILE_EOF'/,/^PROFILE_EOF/d")
grep -q 'boot_path' <<< "$init_body" || fail "init_environment does not set PATH from boot_path"
grep -E 'export PATH="\$persist_bin' <<< "$init_body" && \
    fail "init_environment still puts the persistent folders first"

persist_bin="$tmp_dir/persist/bin"
persist_venv="$tmp_dir/persist/venv/bin"
sys_bin="$tmp_dir/sys"
fake_bin="$tmp_dir/bin"
mkdir -p "$persist_bin" "$persist_venv" "$sys_bin" "$fake_bin"
for name in curl node; do
    printf '#!/usr/bin/env bash\necho persistent\n' > "$persist_bin/$name"
    printf '#!/usr/bin/env bash\necho system\n' > "$sys_bin/$name"
done
printf '#!/usr/bin/env bash\necho persistent-only\n' > "$persist_bin/only-persist"
chmod +x "$persist_bin"/* "$sys_bin"/*

# Stand-ins for tmux and ttyd: they log their arguments and their PATH. No
# session exists, so every caller creates one.
cat > "$fake_bin/tmux" << EOF
#!/usr/bin/env bash
[ "\$1" = has-session ] && exit 1
printf 'args|%s\n' "\$*" >> "$tmp_dir/tmux.log"
printf 'env|%s\n' "\$PATH" >> "$tmp_dir/tmux.log"
exit 0
EOF
cat > "$fake_bin/ttyd" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$PATH" > "$tmp_dir/ttyd.env"
exit 0
EOF
chmod +x "$fake_bin/tmux" "$fake_bin/ttyd"

bashio::log.info() { :; }
bashio::log.warning() { :; }
bashio::log.error() { :; }
bashio::config() { printf '%s\n' "${2:-}"; }
# shellcheck disable=SC2034  # read by the sourced run.sh
OPTION_READ_GAVE_UP="$tmp_dir/options-unanswered"
export PERSIST_PATHS="$persist_bin:$persist_venv"
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

# 1. The boot PATH: the system first, the persistent folders after it, each once.
system_path="$fake_bin:$sys_bin:$PATH"
PATH="$persist_bin:$system_path"
boot=$(boot_path)
[ "$boot" = "$system_path:$PERSIST_PATHS" ] || \
    fail "boot_path is '$boot', expected '$system_path:$PERSIST_PATHS'"
PATH="$boot"
[ "$(curl)" = system ] || fail "with the boot PATH, curl runs the persistent copy"
[ "$(node)" = system ] || fail "with the boot PATH, node runs the persistent copy"
[ "$(only-persist)" = persistent-only ] || fail "a program only in the persistent folder is not found"

# 2. start_web_terminal: the session gets the persistent folders first, the
# tmux server and ttyd keep the boot PATH.
expected_session="PATH=$PERSIST_PATHS:$system_path"
[ "$(terminal_path)" = "$PERSIST_PATHS:$system_path" ] || \
    fail "terminal_path is '$(terminal_path)', expected '$PERSIST_PATHS:$system_path'"
( start_web_terminal ) || fail "start_web_terminal failed"
grep '^args|new-session' "$tmp_dir/tmux.log" | grep -qF -- "-e $expected_session -s claude" || \
    fail "start_web_terminal creates the tmux session without -e $expected_session: $(grep '^args|' "$tmp_dir/tmux.log")"
grep '^env|' "$tmp_dir/tmux.log" | grep -q "^env|$persist_bin" && \
    fail "the tmux server was started with the persistent folders first"
[ -f "$tmp_dir/ttyd.env" ] || fail "ttyd was not started"
[ "$(cat "$tmp_dir/ttyd.env")" = "$boot" ] || \
    fail "ttyd does not run with the boot PATH: '$(cat "$tmp_dir/ttyd.env")'"

# 3. The wrapper ttyd runs creates the session with the same PATH.
rm -f "$tmp_dir/tmux.log"
setup_tmux
bash "$TMUX_WRAPPER_PATH" || fail "the tmux wrapper failed"
grep '^args|new-session' "$tmp_dir/tmux.log" | grep -qF -- "-e $expected_session -s claude" || \
    fail "the tmux wrapper creates the session without -e $expected_session: $(grep '^args|' "$tmp_dir/tmux.log")"

# 5. The takeover dialog is the app's own program, but runs in the session,
# where the persistent folders come first: it calls the image's node by its
# full path (review M6).
offer="$tmp_dir/offer.json"
printf '{}\n' > "$offer"
dialog=$(APP_MIGRATION_OFFER="$offer" APP_MIGRATION_CLI=/opt/x/cli.js with_migration_dialog 'clear')
[ "$dialog" = "/usr/bin/node /opt/x/cli.js dialog; clear" ] || \
    fail "the takeover dialog does not run the image's node: $dialog"

# 6. What the session's first pane really gets (3.6.3; found in the live test
# of 3.6.2 on HA-Test: the shell from the session picker had the persistent
# folders last). tmux 3.7c (spawn.c, "Then the PATH environment variable")
# builds a pane's environment from the session environment (-e) and then
# replaces PATH with the PATH of the client that runs new-session, as long as
# that client is not attached. Both places that create the session are such
# clients, and both have the boot PATH. The stand-in below does exactly that
# and runs the pane's command, which records what it got. Checking the
# arguments (cases 2 and 3) or `tmux show-environment` missed this.
spawn_bin="$tmp_dir/spawn"
mkdir -p "$spawn_bin"
cat > "$spawn_bin/tmux" << 'EOF'
#!/usr/bin/env bash
[ "$1" = has-session ] && exit 1
[ "$1" = new-session ] || exit 0
shift
env_args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -d) shift ;;
        # The session environment; PATH from it is replaced by the client's.
        -e) case "$2" in PATH=*) ;; *) env_args+=("$2") ;; esac; shift 2 ;;
        -s) shift 2 ;;
        *) break ;;
    esac
done
exec env "${env_args[@]}" "$@"
EOF
cat > "$fake_bin/record-pane" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$PATH" > "$tmp_dir/pane.path"
printf '%s\n' "\${LD_LIBRARY_PATH-}" > "$tmp_dir/pane.ld"
EOF
chmod +x "$spawn_bin/tmux" "$fake_bin/record-pane"
get_claude_launch_command() { printf 'record-pane\n'; }
PATH="$spawn_bin:$boot"
expected_pane_path=$(terminal_path)
for site in start_web_terminal wrapper; do
    rm -f "$tmp_dir/pane.path" "$tmp_dir/pane.ld"
    if [ "$site" = start_web_terminal ]; then
        ( start_web_terminal ) || fail "start_web_terminal failed with the spawning tmux"
    else
        export CLAUDE_LAUNCH_CMD=record-pane
        bash "$TMUX_WRAPPER_PATH" || fail "the tmux wrapper failed with the spawning tmux"
    fi
    [ -f "$tmp_dir/pane.path" ] || fail "$site: the pane's command did not run"
    [ "$(cat "$tmp_dir/pane.path")" = "$expected_pane_path" ] || \
        fail "$site: the session's first pane runs with PATH '$(cat "$tmp_dir/pane.path")', expected '$expected_pane_path'"
    case "$(cat "$tmp_dir/pane.ld")" in
        /data/packages/lib*) ;;
        *) fail "$site: the session's first pane lacks /data/packages/lib: '$(cat "$tmp_dir/pane.ld")'" ;;
    esac
done

echo "Command path suite passed"
