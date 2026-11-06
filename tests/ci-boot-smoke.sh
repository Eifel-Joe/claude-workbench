#!/usr/bin/env bash
# CI only (needs Docker; not part of run-tests.sh): boot the real image the way
# the Supervisor would, but against a Supervisor that accepts connections and
# never answers (3.6.1, n11). The first option read runs into read_option's
# time limit and fails - the path bashio 0.19.0 (Alpine 3.24 base) turned into
# a startup abort - and the others take their default at once. /data is seeded like an
# install coming from Alpine 3.21: a Python 3.12 venv with one package, and a
# broken copy of libstdc++ that persist-install might have left in
# /data/packages/lib. A second start then finds a broken copy again WITHOUT a
# release change (n10): the app's services must not load it.
#
# Approach from heytcass (d50e6c0d, heytcass/home-assistant-addons#139: boot
# without a Supervisor) and unsnow-iac (4eaad373: run `claude --version` to
# catch musl loader errors).
#
# Usage: tests/ci-boot-smoke.sh IMAGE
set -euo pipefail

image="${1:?usage: ci-boot-smoke.sh IMAGE}"
name=wb-boot
silent=wb-supervisor
network=wb-net
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/wb-boot.XXXXXX")
data="$work/data"
config="$work/config"

fail() {
    echo "::error::$*"
    echo "=== container log ==="
    docker logs "$name" 2>&1 || true
    exit 1
}
cleanup() {
    docker rm -f "$name" "$silent" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT

in_image() {
    docker run --rm --entrypoint /bin/sh "$image" -c "$1"
}
in_container() {
    docker exec "$name" /bin/sh -c "$1"
}

# --- 1. What the image contains -----------------------------------------------

release=$(in_image 'cat /etc/alpine-release')
case "$release" in
    3.24.*) ;;
    *) fail "base image is Alpine $release, expected 3.24.x" ;;
esac
python=$(in_image "python3 -c 'import sys; print(\"%d.%d\" % sys.version_info[:2])'")
[ "$python" = "3.14" ] || fail "python3 is $python, expected 3.14"
node_major=$(in_image "node -p 'process.versions.node.split(\".\")[0]'")
[ "$node_major" = "24" ] || fail "node major is $node_major, expected 24"
tmux_version=$(in_image 'tmux -V')
case "$tmux_version" in
    "tmux 3.7"*) ;;
    *) fail "tmux is '$tmux_version', expected 3.7" ;;
esac
# Claude Code's native binary needs musl 1.2.5 or newer.
musl=$(in_image 'ldd 2>&1 || true' | sed -n 's/^Version \([0-9.]*\).*/\1/p')
[ -n "$musl" ] || fail "could not read the musl version"
[ "$(printf '%s\n' 1.2.5 "$musl" | sort -V | head -n 1)" = "1.2.5" ] || \
    fail "musl $musl is older than 1.2.5"
if ! claude_out=$(timeout 60 docker run --rm --entrypoint claude \
        -e HOME=/tmp -e DISABLE_AUTOUPDATER=1 "$image" --version 2>&1); then
    fail "claude --version failed: $claude_out"
fi
case "$claude_out" in
    *"symbol not found"*|*"Error relocating"*) fail "musl loader error: $claude_out" ;;
esac
echo "Image: Alpine $release, Python $python, Node $node_major, $tmux_version, musl $musl, claude $claude_out"

# --- 2. /data as Alpine 3.21 left it -----------------------------------------

site="$data/packages/python/venv/lib/python3.12/site-packages/six-1.16.0.dist-info"
mkdir -p "$site" "$data/packages/lib" "$config"
printf 'home = /usr/bin\ninclude-system-site-packages = false\nversion = 3.12.16\n' \
    > "$data/packages/python/venv/pyvenv.cfg"
printf 'Metadata-Version: 2.1\nName: six\nVersion: 1.16.0\n' > "$site/METADATA"
# Like a real venv: bin/python3 points at the system interpreter.
mkdir -p "$data/packages/python/venv/bin"
ln -s /usr/bin/python3 "$data/packages/python/venv/bin/python3"
: > "$site/REQUESTED"
printf 'not a library\n' > "$data/packages/lib/libstdc++.so.6"

# --- 3. Boot against a Supervisor that never answers --------------------------

# The app reaches the Supervisor as http://supervisor (bashio's default). This
# one accepts every connection on port 80 and never sends a byte back.
docker network create "$network" >/dev/null
docker run -d --name "$silent" --network "$network" --network-alias supervisor \
    --entrypoint node "$image" \
    -e "require('net').createServer(() => {}).listen(80)" >/dev/null
# Wait until it listens: a read that finds the port closed fails at once and
# would never reach the time limit.
listening=false
for _ in $(seq 1 30); do
    if docker exec "$silent" node -e \
            "require('net').connect(80, '127.0.0.1').on('connect', () => process.exit(0)).on('error', () => process.exit(1))" \
            >/dev/null 2>&1; then
        listening=true
        break
    fi
    sleep 1
done
[ "$listening" = true ] || fail "the stand-in Supervisor does not listen on port 80"

# Starts the app container and waits for the panel and ttyd.
boot() {
    local up=false
    docker run -d --name "$name" --network "$network" \
        -v "$data:/data" -v "$config:/config" "$image" >/dev/null
    for _ in $(seq 1 90); do
        if [ "$(docker inspect -f '{{.State.Running}}' "$name")" != "true" ]; then
            fail "the container stopped during startup"
        fi
        if in_container 'curl -fsS --max-time 2 http://127.0.0.1:7680/health' >/dev/null 2>&1 && \
                in_container 'pgrep -x ttyd' >/dev/null 2>&1; then
            up=true
            break
        fi
        sleep 2
    done
    [ "$up" = true ] || fail "the panel (/health on 7680) and ttyd did not both come up within 180 s"
}

boot

# --- 4. What startup did -------------------------------------------------------

log=$(docker logs "$name" 2>&1)
grep -q 'Something went wrong contacting the API' <<< "$log" || \
    fail "no failed Supervisor API call in the log: the option-read path was not exercised"
# One wait for the silent Supervisor, then defaults at once (read_option).
timeouts=$(grep -c 'The Supervisor did not answer within 10s' <<< "$log" || true)
[ "$timeouts" = 1 ] || \
    fail "expected the option read to run into its time limit exactly once, saw it $timeouts times"
grep -q 'Starting web terminal' <<< "$log" || fail "startup never reached the web terminal"
# A failed read must come back as the default, not empty (bashio returns empty
# output with status 0 when read on the left of ||).
grep -q 'Auto-launch Claude: true' <<< "$log" || \
    fail "auto_launch_claude did not fall back to its default 'true'"
in_container 'tmux has-session -t claude' || \
    fail "the tmux session 'claude' is gone (empty launch command?)"
in_container 'tmux source-file /data/home/.tmux.conf' || \
    fail "tmux 3.7 rejects the generated /data/home/.tmux.conf"
in_container "grep -qE '^version(_info)? *= *3\\.14' /data/packages/python/venv/pyvenv.cfg" || \
    fail "the persist-install venv was not rebuilt for Python 3.14"
in_container "/data/packages/python/venv/bin/python -c 'import six'" || \
    fail "the package from the 3.12 venv was not reinstalled"
in_container '[ ! -e /data/packages/python/.reinstall-pending ]' || \
    fail "the reinstall list is still pending"
in_container '[ -f /data/packages/stale-alpine-3.21/lib/libstdc++.so.6 ]' || \
    fail "the stale libstdc++ copy was not moved out of LD_LIBRARY_PATH"
[ "$(in_container 'cat /data/packages/.alpine-release')" = "3.24" ] || \
    fail "the Alpine release was not recorded"

# --- 5. Second start: a broken library copy, no release change (n10) ----------

# The quarantine only runs on a release change, so this copy stays where it is.
# The app's own services must not load it; the terminal session still gets the
# folder.
in_container "printf 'not a library\\n' > /data/packages/lib/libstdc++.so.6"
docker rm -f "$name" >/dev/null
boot

in_container '[ -f /data/packages/lib/libstdc++.so.6 ]' || \
    fail "the broken copy was moved: this start was meant to run without a release change"
library_path_of() {
    in_container "tr '\\000' '\\n' < /proc/$1/environ | grep '^LD_LIBRARY_PATH=' || true"
}
node_pid=$(in_container "pgrep -o -f 'node /opt/image-service/server.js'") || \
    fail "the image service (node) is not running"
ttyd_pid=$(in_container 'pgrep -o -x ttyd') || fail "ttyd is not running"
tmux_pid=$(in_container "tmux display-message -p -t claude '#{pid}'") || \
    fail "the tmux server does not answer"
for service in "node:$node_pid" "ttyd:$ttyd_pid" "tmux server:$tmux_pid"; do
    service_env=$(library_path_of "${service#*:}")
    case "$service_env" in
        */data/packages/lib*) fail "${service%%:*} runs with /data/packages/lib on LD_LIBRARY_PATH ($service_env)" ;;
    esac
done
session_env=$(in_container 'tmux show-environment -t claude LD_LIBRARY_PATH') || \
    fail "the tmux session 'claude' has no LD_LIBRARY_PATH"
case "$session_env" in
    LD_LIBRARY_PATH=/data/packages/lib*) ;;
    *) fail "the tmux session 'claude' lacks /data/packages/lib: $session_env" ;;
esac
login_env=$(in_container "bash -lc 'printf %s \"\$LD_LIBRARY_PATH\"'")
case "$login_env" in
    /data/packages/lib*) ;;
    *) fail "a login shell lacks /data/packages/lib: '$login_env'" ;;
esac

echo "Boot smoke test passed"
