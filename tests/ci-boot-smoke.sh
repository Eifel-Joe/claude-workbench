#!/usr/bin/env bash
# CI only (needs Docker; not part of run-tests.sh): boot the real image the way
# the Supervisor would, but WITHOUT a Supervisor. Every bashio::config call then
# fails, which is exactly the path bashio 0.19.0 (Alpine 3.24 base) turned into
# a startup abort. /data is seeded like an install coming from Alpine 3.21: a
# Python 3.12 venv with one package, and a broken copy of libstdc++ that
# persist-install might have left first on LD_LIBRARY_PATH (it would kill node,
# the panel's entry point, if it stayed there).
#
# Approach from heytcass (d50e6c0d, heytcass/home-assistant-addons#139: boot
# without a Supervisor) and unsnow-iac (4eaad373: run `claude --version` to
# catch musl loader errors).
#
# Usage: tests/ci-boot-smoke.sh IMAGE
set -euo pipefail

image="${1:?usage: ci-boot-smoke.sh IMAGE}"
name=wb-boot
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
    docker rm -f "$name" >/dev/null 2>&1 || true
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
: > "$site/REQUESTED"
printf 'not a library\n' > "$data/packages/lib/libstdc++.so.6"

# --- 3. Boot without a Supervisor ---------------------------------------------

docker run -d --name "$name" -v "$data:/data" -v "$config:/config" "$image" >/dev/null

up=false
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

# --- 4. What startup did -------------------------------------------------------

log=$(docker logs "$name" 2>&1)
grep -q 'Something went wrong contacting the API' <<< "$log" || \
    fail "no failed Supervisor API call in the log: the option-read path was not exercised"
grep -q 'Starting web terminal' <<< "$log" || fail "startup never reached the web terminal"
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

echo "Boot smoke test passed"
