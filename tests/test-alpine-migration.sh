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

# --- Python venv after a Python upgrade (3.12 -> 3.14) ------------------------

venv="$tmp_dir/python/venv"
pending="$tmp_dir/python/.reinstall-pending"
fake_pip="$tmp_dir/fake-pip"
fake_python="$tmp_dir/fake-python"
cat > "$fake_pip" << 'FAKE'
#!/usr/bin/env bash
# pip install -q NAME; fails for the names in $PIP_FAIL
for bad in ${PIP_FAIL:-}; do
    [ "$3" = "$bad" ] && exit 1
done
printf '%s\n' "$3" >> "$PIP_LOG"
FAKE
cat > "$fake_python" << 'FAKE'
#!/usr/bin/env bash
[ "$1" = "-c" ] && { echo 3.14; exit 0; }
[ "$1 $2" = "-m venv" ] || exit 1
[ -z "${VENV_FAIL:-}" ] || exit 1
mkdir -p "$3/bin"
printf 'home = /usr/bin\nversion_info = 3.14.10\n' > "$3/pyvenv.cfg"
cp "$FAKE_PIP" "$3/bin/pip"
FAKE
chmod +x "$fake_pip" "$fake_python"
export FAKE_PIP="$fake_pip" PIP_LOG="$tmp_dir/pip.log" PERSIST_VENV="$venv" PYTHON_BIN="$fake_python"
export PIP_FAIL='' VENV_FAIL=''

# old_venv NAME:requested ... - a 3.12 venv with these dist-infos
old_venv() {
    local spec name
    rm -rf "$tmp_dir/python" "$PIP_LOG"
    mkdir -p "$venv/lib/python3.12/site-packages"
    printf 'home = /usr/bin\nversion = 3.12.16\n' > "$venv/pyvenv.cfg"
    for spec in "$@"; do
        name=${spec%%:*}
        mkdir -p "$venv/lib/python3.12/site-packages/$name-1.0.dist-info"
        # \r: METADATA written on another system must not leak into the name
        printf 'Metadata-Version: 2.1\nName: %s\r\nVersion: 1.0\n\nName: not-this\n' "$name" \
            > "$venv/lib/python3.12/site-packages/$name-1.0.dist-info/METADATA"
        [ "${spec#*:}" != requested ] || \
            : > "$venv/lib/python3.12/site-packages/$name-1.0.dist-info/REQUESTED"
    done
    : > "$warnings"
    : > "$errors"
}
pip_calls() { sort "$PIP_LOG" 2>/dev/null | tr '\n' ' '; }

# Only what was installed by name (REQUESTED) comes back; pip pulls the
# dependencies itself. pip/setuptools/wheel come with the new venv.
old_venv Requests:requested idna:dep pip:requested
migrate_python_venv
[ "$(pip_calls)" = "Requests " ] || fail "only REQUESTED packages must be reinstalled, got: $(pip_calls)"
grep -q 'version_info = 3.14' "$venv/pyvenv.cfg" || fail "the venv must be recreated for the new Python"
[ ! -e "$venv/lib/python3.12" ] || fail "the old venv must be removed"
[ ! -e "$pending" ] || fail "the reinstall list must be gone once everything is back"
grep -q 'Python changed from 3.12 to 3.14' "$warnings" || fail "the rebuild must be logged"

# A venv without any REQUESTED marker (older pip): every package comes back.
old_venv six:dep idna:dep
migrate_python_venv
[ "$(pip_calls)" = "idna six " ] || fail "without REQUESTED markers all packages must come back, got: $(pip_calls)"

# Offline first start: nothing reinstalls, the list survives, startup goes on;
# the next start with network finishes the job.
old_venv Requests:requested six:requested
PIP_FAIL='Requests six' migrate_python_venv
[ "$(sort "$pending" | tr '\n' ' ')" = "Requests six " ] || \
    fail "packages that failed to reinstall must stay on the list, got: $(cat "$pending" 2>/dev/null)"
grep -q 'persist-install --python' "$warnings" || fail "a failed reinstall must name the manual command"
rm -f "$PIP_LOG"
migrate_python_venv
[ "$(pip_calls)" = "Requests six " ] || fail "the next start must retry the list, got: $(pip_calls)"
[ ! -e "$pending" ] || fail "a finished list must be deleted"

# A venv for the current Python and no list: nothing happens.
rm -f "$PIP_LOG"
migrate_python_venv
[ ! -e "$PIP_LOG" ] || fail "a venv for the current Python must be left alone"

# The venv cannot be recreated: logged, the list stays, startup goes on.
old_venv Requests:requested
VENV_FAIL=1 migrate_python_venv
[ -s "$errors" ] || fail "a failed venv rebuild must be logged as an error"
grep -qx 'Requests' "$pending" || fail "the list must survive a failed venv rebuild"
[ ! -e "$PIP_LOG" ] || fail "nothing can be installed without a venv"
migrate_python_venv
[ "$(pip_calls)" = "Requests " ] || fail "the next start must rebuild the venv and reinstall, got: $(pip_calls)"

# Blank lines in the list never become an empty pip install.
rm -rf "$tmp_dir/python" "$PIP_LOG"
"$fake_python" -m venv "$venv"
printf '\nsix\n\n' > "$pending"
migrate_python_venv
[ "$(pip_calls)" = "six " ] || fail "blank lines in the list must be skipped, got: $(pip_calls)"

# No venv at all (persist-install --python never used): nothing happens.
rm -rf "$tmp_dir/python" "$PIP_LOG"
migrate_python_venv
[ ! -e "$tmp_dir/python" ] || fail "no venv may be created for users who never had one"

echo "Alpine migration suite passed"
