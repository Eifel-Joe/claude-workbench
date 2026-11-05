#!/usr/bin/env bash
# Migration steps for a new Alpine release of the base image (3.21 -> 3.24):
# persist-install copies in /data/packages and the Python venv. They run in
# run.sh under bashio's shell options, so this suite runs under the same ones
# (bashio 0.19.0: errexit, nounset, pipefail, inherit_errexit). A step that
# trips over a missing file or a failing cmp would end startup.
set -euo pipefail
shopt -s inherit_errexit

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
    echo "FAIL (Alpine migration): $*" >&2
    exit 1
}

warnings="$tmp_dir/warnings"
errors="$tmp_dir/errors"
bashio::log.info() { :; }
bashio::log.warning() { printf '%s\n' "$*" >> "$warnings"; }
bashio::log.error() { printf '%s\n' "$*" >> "$errors"; }
bashio::config() { printf '%s\n' "${2:-}"; }

CLAUDE_RUN_SH_SKIP_MAIN=true
source "$repo_root/claude-workbench/run.sh"

# --- Persisted copies after a release change ---------------------------------

persist="$tmp_dir/packages"
system="$tmp_dir/system"
release_file="$tmp_dir/alpine-release"
export PERSIST_ROOT="$persist" SYSTEM_ROOT="$system" ALPINE_RELEASE_FILE="$release_file"

reset_tree() {
    rm -rf "$persist" "$system"
    mkdir -p "$persist/bin" "$persist/lib/pkgconfig" "$system/usr/lib" "$system/lib" \
        "$system/usr/bin"
    : > "$warnings"
}

# A copy of a system library from 3.21 sits first on LD_LIBRARY_PATH and would
# break node (the panel) on 3.24: it is moved aside, not deleted.
reset_tree
printf '3.24.1\n' > "$release_file"
printf 'old\n' > "$persist/lib/libstdc++.so.6"
printf 'new\n' > "$system/usr/lib/libstdc++.so.6"
printf 'own\n' > "$persist/lib/libfoo.so.1"
printf 'same\n' > "$persist/lib/libz.so.1"
printf 'same\n' > "$system/lib/libz.so.1"
printf 'pc\n' > "$persist/lib/pkgconfig/foo.pc"
move_stale_persisted_libs
[ -f "$persist/stale-alpine-3.21/lib/libstdc++.so.6" ] || \
    fail "a stale copy of a system library must be moved to stale-alpine-3.21/lib"
[ ! -e "$persist/lib/libstdc++.so.6" ] || fail "the stale copy must leave LD_LIBRARY_PATH"
grep -q 'libstdc++.so.6' "$warnings" || fail "the moved library must be named in the log"
[ -f "$persist/lib/libfoo.so.1" ] || fail "a library without a system copy must stay"
[ -f "$persist/lib/libz.so.1" ] || fail "a library identical to the system copy must stay"
[ -f "$persist/lib/pkgconfig/foo.pc" ] || fail "subdirectories of lib must be left alone"

# The same release as recorded: nothing moves, nothing is logged.
reset_tree
printf '3.24\n' > "$persist/.alpine-release"
printf 'old\n' > "$persist/lib/libstdc++.so.6"
printf 'new\n' > "$system/usr/lib/libstdc++.so.6"
move_stale_persisted_libs
[ -f "$persist/lib/libstdc++.so.6" ] || fail "nothing may move while the release is unchanged"
[ ! -s "$warnings" ] || fail "an unchanged release must not warn"

# An unreadable release file is no reason to touch anything (or to fail).
reset_tree
printf 'old\n' > "$persist/lib/libstdc++.so.6"
printf 'new\n' > "$system/usr/lib/libstdc++.so.6"
rm -f "$release_file"
move_stale_persisted_libs
check_persisted_alpine_release
[ -f "$persist/lib/libstdc++.so.6" ] || fail "without a release file nothing may move"
[ ! -e "$persist/.alpine-release" ] || fail "without a release file no marker may be written"

# After the package installs: files without an identical system copy are
# named once, then the release is recorded. bin/ha from persist-install
# --ha-cli is a static download, not tied to the Alpine release.
reset_tree
printf '3.24.1\n' > "$release_file"
printf 'old htop\n' > "$persist/bin/htop"
printf 'ssh\n' > "$persist/bin/ssh"
printf 'ssh\n' > "$system/usr/bin/ssh"
printf 'ha\n' > "$persist/bin/ha"
printf '4.40.0\n' > "$persist/bin/.ha-version"
printf 'own\n' > "$persist/lib/libfoo.so.1"
check_persisted_alpine_release
grep -q 'from Alpine 3.21 to 3.24.*htop.*libfoo.so.1' "$warnings" || \
    fail "files installed on 3.21 must be named after the move to 3.24, got: $(cat "$warnings")"
! grep -qw 'ssh' "$warnings" || fail "a file just reinstalled from the options must not be named"
! grep -qw 'ha' "$warnings" || fail "the ha CLI from persist-install --ha-cli must not be named"
[ "$(cat "$persist/.alpine-release")" = "3.24" ] || fail "the current release must be recorded"
: > "$warnings"
check_persisted_alpine_release
[ ! -s "$warnings" ] || fail "a recorded release must not warn again"

# A fresh install without bin or lib: no warning, the release is recorded.
rm -rf "$persist"
: > "$warnings"
check_persisted_alpine_release
[ ! -s "$warnings" ] || fail "an empty package tree must not warn"
[ "$(cat "$persist/.alpine-release")" = "3.24" ] || fail "a fresh install must record the release"

echo "Alpine migration suite passed"
