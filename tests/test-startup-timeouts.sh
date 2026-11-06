#!/usr/bin/env bash
set -euo pipefail

# Startup steps that touch the network run before the web terminal starts, so
# one that hangs must be cut off. A hang is a stub sleeping far past a 1 s limit.

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
    echo "FAIL (startup timeouts): $*" >&2
    exit 1
}

log="$tmp_dir/log"
: > "$log"
bashio::log.info() { printf 'info|%s\n' "$*" >> "$log"; }
bashio::log.warning() { printf 'warning|%s\n' "$*" >> "$log"; }
bashio::log.error() { printf 'error|%s\n' "$*" >> "$log"; }

config_apk_packages=''
config_pip_packages=''
bashio::config() {
    case "$1" in
        use_persistent_claude) printf '%s\n' true ;;
        auto_update_claude_on_start) printf '%s\n' true ;;
        persistent_apk_packages) printf '%s\n' "$config_apk_packages" ;;
        persistent_pip_packages) printf '%s\n' "$config_pip_packages" ;;
        *) printf '%s\n' "${2:-}" ;;
    esac
}

export STARTUP_NPM_TIMEOUT=1 STARTUP_APK_TIMEOUT=1 STARTUP_PIP_TIMEOUT=1

# shellcheck disable=SC2034  # read by the sourced run.sh
CLAUDE_RUN_SH_SKIP_MAIN=true
# shellcheck source=/dev/null
source "$repo_root/claude-workbench/run.sh"

# --- run_with_timeout ---

run_with_timeout 5 "fast step" true || fail "a quick success must return 0"
! grep -q 'timed out' "$log" || fail "a quick success must not be reported as a timeout"

status=0
run_with_timeout 5 "failing step" sh -c 'exit 3' || status=$?
[ "$status" -eq 3 ] || fail "the command's own status must come back (got $status)"
! grep -q 'timed out' "$log" || fail "a quick failure is not a timeout"

status=0
started=$SECONDS
run_with_timeout 1 "hanging step" sleep 30 || status=$?
[ $((SECONDS - started)) -lt 10 ] || fail "a hanging command must be cut off"
[ "$status" -ne 0 ] || fail "a cut-off command must not report success"
grep -qx 'warning|hanging step timed out after 1s' "$log" || \
    fail "a cut-off command must be logged as a timeout"

# --- Claude Code update on start ---

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"
printf '#!/bin/sh\nexec sleep 30\n' > "$stub_bin/npm"
chmod +x "$stub_bin/npm"
PATH="$stub_bin:$PATH"

# shellcheck disable=SC2034  # read by the sourced run.sh
PERSISTENT_CLAUDE_ROOT="$tmp_dir/npm"
# shellcheck disable=SC2034
CLAUDE_BIN_LINK="$tmp_dir/claude"
# shellcheck disable=SC2034
CLAUDE_NATIVE_BIN_LINK="$tmp_dir/native/claude"
: > "$log"
started=$SECONDS
setup_persistent_claude
[ $((SECONDS - started)) -lt 10 ] || fail "a hanging Claude Code update must not block startup"
grep -qx 'warning|Persistent Claude override: npm update timed out after 1s' "$log" || \
    fail "a hanging Claude Code update must be logged as a timeout"

# start_web_terminal launches servers, so check the call instead of running it.
# shellcheck disable=SC2016  # the literal $STARTUP_NPM_TIMEOUT is what is searched for
grep -q 'run_with_timeout "$STARTUP_NPM_TIMEOUT" "Image service: npm install" npm install' \
    "$repo_root/claude-workbench/run.sh" || \
    fail "the image service's npm install must run under the time limit"

# --- Package auto-install ---

PERSIST_INSTALL_LOG="$tmp_dir/persist-install.log"
export PERSIST_INSTALL_LOG
PERSIST_INSTALL_BIN="$stub_bin/persist-install"
cat > "$PERSIST_INSTALL_BIN" << 'STUB_EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PERSIST_INSTALL_LOG"
for argument in "$@"; do
    if [ "$argument" = hang ]; then exec sleep 30; fi
done
STUB_EOF
chmod +x "$PERSIST_INSTALL_BIN"

config_apk_packages=$'hang\ngit'
config_pip_packages=''
: > "$log"
: > "$PERSIST_INSTALL_LOG"
started=$SECONDS
auto_install_packages
[ $((SECONDS - started)) -lt 10 ] || fail "a hanging apk package must not block startup"
grep -qx -- '--apk git' "$PERSIST_INSTALL_LOG" || fail "the package after a hanging one must still be installed"
grep -qx "warning|Auto-install of hang timed out after 1s" "$log" || \
    fail "a hanging apk package must be logged as a timeout"

config_apk_packages=''
config_pip_packages=$'requests\nhang'
: > "$log"
started=$SECONDS
auto_install_packages
[ $((SECONDS - started)) -lt 10 ] || fail "a hanging pip install must not block startup"
grep -qx 'warning|Auto-install of Python packages timed out after 1s' "$log" || \
    fail "a hanging pip install must be logged as a timeout"

# A cut-off must take the step's children with it: persist-install is a script
# around apk/pip, and an orphaned `apk add` keeps the apk database locked for
# every later package. GNU timeout signals the process group; BusyBox timeout
# (coreutils/timeout.c: kill(parent, signo)) only the process it started.
grep -qE '^[[:space:]]+coreutils[[:space:]]*\\?$' "$repo_root/claude-workbench/Dockerfile" || \
    fail "the image must install coreutils: BusyBox timeout leaves the step's children running"

cat > "$PERSIST_INSTALL_BIN" << 'STUB_EOF'
#!/usr/bin/env bash
sleep 30 &
printf '%s\n' "$!" > "$PERSIST_INSTALL_LOG.child"
wait
STUB_EOF
config_apk_packages='child'
config_pip_packages=''
auto_install_packages
child_pid=$(cat "$PERSIST_INSTALL_LOG.child")
sleep 1
! kill -0 "$child_pid" 2>/dev/null || fail "a cut-off package install must not leave its children running"

# A half-finished npm update can keep failing later ones; say how to recover.
: > "$log"
setup_persistent_claude
grep -q 'warning|Persistent Claude override: update failed.*delete /data/npm and restart' "$log" || \
    fail "a failed Claude Code update must say how to recover"

# install_tools is the fallback for tools missing from the image. It exits on
# failure, which lets the watchdog restart the app instead of hanging forever.
tools_bin="$tmp_dir/tools-bin"
mkdir -p "$tools_bin"
printf '#!/bin/sh\nexec sleep 30\n' > "$tools_bin/apk"
chmod +x "$tools_bin/apk"
# The fallback only runs when a tool is missing; ttyd is not on test machines.
! command -v ttyd >/dev/null 2>&1 || fail "install_tools test needs a machine without ttyd"
: > "$log"
started=$SECONDS
status=0
( PATH="$tools_bin:$PATH"; install_tools ) || status=$?
[ $((SECONDS - started)) -lt 10 ] || fail "a hanging apk in install_tools must not block startup"
[ "$status" -ne 0 ] || fail "install_tools must fail when the tools could not be installed"

echo "Startup timeout suite passed"
