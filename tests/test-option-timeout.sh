#!/usr/bin/env bash
# read_option must not wait forever for a Supervisor that accepts the
# connection but never answers (n11). bashio 0.19.0 calls curl by name with no
# time limit, so a stand-in for bashio::config does the same against a local
# server that never answers. Every case runs under the shell options bashio
# 0.19.0 sets, in a background subshell with a watchdog, so the hang the fix
# removes ends the test instead of hanging it.
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
server_pid=''
cleanup() {
    [ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

fail() {
    echo "FAIL (option read timeout): $*" >&2
    exit 1
}

command -v node >/dev/null 2>&1 || fail "node is needed for the fake Supervisor"
command -v curl >/dev/null 2>&1 || fail "curl is needed (bashio calls it)"

# /hang accepts and never answers, /ok answers at once, /fail answers 500 at once.
cat > "$tmp_dir/server.js" << 'EOF'
const http = require('node:http');
const fs = require('node:fs');
const [portFile, countFile] = process.argv.slice(2);
let hangs = 0;
http.createServer((req, res) => {
  if (req.url === '/hang') {
    hangs += 1;
    fs.writeFileSync(countFile, String(hangs));
    return;
  }
  if (req.url === '/ok') {
    res.end('false');
    return;
  }
  res.statusCode = 500;
  res.end('error');
}).listen(0, '127.0.0.1', function () {
  fs.writeFileSync(portFile, String(this.address().port));
});
EOF
node "$tmp_dir/server.js" "$tmp_dir/port" "$tmp_dir/hangs" &
server_pid=$!
for _ in $(seq 1 50); do
    [ -s "$tmp_dir/port" ] && break
    sleep 0.1
done
[ -s "$tmp_dir/port" ] || fail "the fake Supervisor did not start"
base="http://127.0.0.1:$(cat "$tmp_dir/port")"

warnings="$tmp_dir/warnings"
reason="$tmp_dir/reason"
bashio::log.info() { :; }
bashio::log.warning() { printf '%s\n' "$*" >> "$warnings"; }
bashio::log.error() { :; }
# Like bashio::api.supervisor: curl by name, a failed request is an error.
fake_url="$base/ok"
bashio::config() {
    local response
    if ! response=$(curl --silent --show-error --fail "$fake_url" 2>/dev/null); then
        return 1
    fi
    printf '%s' "${response:-$2}"
}

# shellcheck disable=SC2034  # read by the sourced run.sh
OPTION_READ_TIMEOUT=2
# shellcheck disable=SC2034  # read by the sourced run.sh
OPTION_READ_GAVE_UP="$tmp_dir/options-unanswered"
# shellcheck disable=SC2034  # read by the sourced run.sh
CLAUDE_RUN_SH_SKIP_MAIN=true
# shellcheck source=/dev/null
source "$repo_root/claude-workbench/run.sh"

expect() {
    local message="$1"
    shift
    if ! "$@"; then
        printf '%s\n' "$message" > "$reason"
        return 1
    fi
}

hangs() { cat "$tmp_dir/hangs" 2>/dev/null || echo 0; }

# Runs "$@" under bashio's shell options; a watchdog ends it after 20 s.
guarded() {
    local pid dog status=0
    rm -f "$reason" "$warnings" "$OPTION_READ_GAVE_UP" "$tmp_dir/hangs"
    (
        set -euo pipefail
        shopt -s inherit_errexit
        "$@"
    ) &
    pid=$!
    # The watchdog ends its own sleep when stopped, so no orphaned sleep keeps
    # a pipe on this suite's output open; nor do its descriptors.
    (
        trap 'kill "$nap" 2>/dev/null; exit 0' TERM
        sleep 20 &
        nap=$!
        wait "$nap"
        kill "$pid" 2>/dev/null
    ) > /dev/null 2>&1 &
    dog=$!
    wait "$pid" || status=$?
    kill "$dog" 2>/dev/null || true
    wait "$dog" 2>/dev/null || true
    if [ "$status" -ne 0 ]; then
        fail "$1: $(cat "$reason" 2>/dev/null || echo "ended with status $status (hung and killed by the watchdog?)")"
    fi
}

# 1-3: a silent Supervisor costs one wait up to the limit, then defaults at once.
case_silent_supervisor() {
    local started value
    fake_url="$base/hang"
    started=$SECONDS
    value=$(read_option 'auto_launch_claude' 'true')
    expect "the first read returned '$value', not its default" [ "$value" = true ]
    expect "the first read took $((SECONDS - started)) s, limit is ${OPTION_READ_TIMEOUT} s" \
        [ $((SECONDS - started)) -le $((OPTION_READ_TIMEOUT + 3)) ]
    started=$SECONDS
    value=$(read_option 'tmux_mouse' 'false')
    expect "the second read returned '$value', not its default" [ "$value" = false ]
    expect "the second read waited again ($((SECONDS - started)) s)" [ $((SECONDS - started)) -le 1 ]
    expect "the Supervisor was asked $(hangs) times, expected once" [ "$(hangs)" = 1 ]
    expect "expected exactly one warning, got: $(cat "$warnings" 2>/dev/null)" \
        [ "$(grep -c 'did not answer' "$warnings" 2>/dev/null)" = 1 ]
}
guarded case_silent_supervisor

# 4: a fast failure is not a silent Supervisor; the next read asks again.
case_fast_failure() {
    local value
    fake_url="$base/fail"
    value=$(read_option 'auto_launch_claude' 'true')
    expect "a failed read returned '$value', not its default" [ "$value" = true ]
    expect "a fast failure must not stop later reads" [ ! -e "$OPTION_READ_GAVE_UP" ]
    fake_url="$base/ok"
    value=$(read_option 'auto_launch_claude' 'true')
    expect "the read after a fast failure returned '$value', not the answer 'false'" [ "$value" = false ]
}
guarded case_fast_failure

# 5: a normal answer still comes through.
case_answer() {
    local value
    fake_url="$base/ok"
    value=$(read_option 'auto_launch_claude' 'true')
    expect "an answered read returned '$value', not 'false'" [ "$value" = false ]
}
guarded case_answer

# 6: a new start asks the Supervisor again.
main_body=$(sed -n '/^main() {/,/^}/p' "$repo_root/claude-workbench/run.sh")
first_command=$(printf '%s\n' "$main_body" | sed -n '2,$p' | grep -vE '^[[:space:]]*(#|$)' | head -n 1)
[[ "$first_command" == *'rm -f "$OPTION_READ_GAVE_UP"'* ]] || \
    fail "main must clear the 'Supervisor did not answer' marker first (first command: $first_command)"

echo "Option read timeout suite passed"
