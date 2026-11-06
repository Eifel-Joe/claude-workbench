#!/usr/bin/env bash
set -euo pipefail

# Regression suite for persist-install --python: a failing pip (or venv setup)
# must make the script exit non-zero. It used to end with an `echo`, so the app
# migration recorded packages as installed although pip had failed.

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
    echo "FAIL (persist-install): $*" >&2
    exit 1
}

script="$repo_root/claude-workbench/scripts/persist-install"
fake_bin="$tmp_dir/bin"
pip_log="$tmp_dir/pip.log"
mkdir -p "$fake_bin"

# Fake pip: logs its arguments; the self-upgrade always succeeds, the real
# install exits with $FAKE_PIP_STATUS.
cat > "$fake_bin/pip" <<PIP
#!/bin/sh
printf '%s\n' "\$*" >> "$pip_log"
case "\$*" in
    *--upgrade\ pip*) exit 0 ;;
esac
exit "\${FAKE_PIP_STATUS:-0}"
PIP
chmod +x "$fake_bin/pip"

# Fake python3 for the "no venv yet" case: venv creation fails.
cat > "$fake_bin/python3" <<'PY'
#!/bin/sh
exit 1
PY
chmod +x "$fake_bin/python3"

# A data root whose venv already exists (activate is sourced, so keep it empty).
make_data_root() {
    local root="$1"
    mkdir -p "$root/packages/python/venv/bin"
    : > "$root/packages/python/venv/bin/python"
    : > "$root/packages/python/venv/bin/activate"
}

run_persist_install() {
    local root="$1" status="$2"
    shift 2
    PATH="$fake_bin:$PATH" PERSIST_DATA_ROOT="$root" FAKE_PIP_STATUS="$status" \
        bash "$script" "$@" > "$tmp_dir/out.log" 2>&1
}

# pip fails -> non-zero
make_data_root "$tmp_dir/data-fail"
: > "$pip_log"
if run_persist_install "$tmp_dir/data-fail" 1 --python foo; then
    fail "exit 0 although pip install failed: $(cat "$tmp_dir/out.log")"
fi
grep -qx 'install foo' "$pip_log" || fail "pip install foo was not called: $(cat "$pip_log")"
grep -q '❌' "$tmp_dir/out.log" || fail "no error message when pip failed: $(cat "$tmp_dir/out.log")"

# pip succeeds -> zero
make_data_root "$tmp_dir/data-ok"
: > "$pip_log"
run_persist_install "$tmp_dir/data-ok" 0 --python foo || \
    fail "non-zero exit although pip install succeeded: $(cat "$tmp_dir/out.log")"
grep -qx 'install foo' "$pip_log" || fail "pip install foo was not called: $(cat "$pip_log")"

# no venv yet and `python3 -m venv` fails -> non-zero, pip never runs
mkdir -p "$tmp_dir/data-novenv"
: > "$pip_log"
if run_persist_install "$tmp_dir/data-novenv" 0 --python foo; then
    fail "exit 0 although creating the venv failed: $(cat "$tmp_dir/out.log")"
fi
[ ! -s "$pip_log" ] || fail "pip ran although the venv could not be created: $(cat "$pip_log")"

# --- persist-install --ha-cli -------------------------------------------------
# The CLI comes from the latest GitHub release, like the Dockerfile. A pinned
# 4.46.0 once downgraded it: the copy in /data/packages/bin sits in PATH ahead
# of the newer one shipped in the image.
curl_log="$tmp_dir/curl.log"

# The ha binary the fake download delivers. Like the real CLI (4.x and 5.x)
# it has no --version flag; `help` works offline. Padded past persist-install's
# 1 MB size check, with a shebang because Git Bash only treats files with one
# as executable.
fake_ha="$tmp_dir/fake-ha"
{
    printf '#!/bin/sh\n'
    printf 'case "$1" in --version) echo "Error: unknown flag: --version" >&2; echo "Usage:"; exit 1 ;; esac\n'
    printf 'echo fake-ha\nexit 0\n#'
    head -c 1100000 /dev/zero | tr '\0' x
    printf '\n'
} > "$fake_ha"

cat > "$fake_bin/curl" <<CURL
#!/bin/sh
printf '%s\n' "\$*" >> "$curl_log"
# Release lookup: persist-install asks curl where releases/latest redirects to.
# Like real curl, the URL is printed even when -f makes it fail.
case "\$*" in
    *url_effective*)
        printf '%s' "\${FAKE_LATEST_URL:-}"
        exit "\${FAKE_LATEST_STATUS:-0}"
        ;;
esac
out=""
prev=""
for arg in "\$@"; do
    [ "\$prev" = "-o" ] && out="\$arg"
    prev="\$arg"
done
if [ -n "\$out" ]; then
    [ "\${FAKE_DL_STATUS:-0}" -eq 0 ] || exit "\$FAKE_DL_STATUS"
    cp "$fake_ha" "\$out"
    exit 0
fi
exit 0
CURL
chmod +x "$fake_bin/curl"
latest_tag_url="https://github.com/home-assistant/cli/releases/tag/9.9.1"

case "$(uname -m)" in
    x86_64) want_arch=amd64 ;;
    aarch64) want_arch=aarch64 ;;
    *) want_arch="" ;;
esac

run_ha_cli() {
    local root="$1"
    shift
    mkdir -p "$root"
    : > "$curl_log"
    PATH="$fake_bin:$PATH" PERSIST_DATA_ROOT="$root" \
        bash "$script" --ha-cli "${@---force}" > "$tmp_dir/out.log" 2>&1
}

# An earlier --force left an old copy in /data/packages/bin.
make_old_copy() {
    mkdir -p "$1/packages/bin"
    printf '#!/bin/sh\ncase "$1" in --version) echo "Usage:"; exit 1 ;; esac\necho old-ha\n' > "$1/packages/bin/ha"
    chmod +x "$1/packages/bin/ha"
}

# ha has no --version flag; asking for it printed "unknown flag" and the usage
# text where a version belonged.
assert_no_version_flag_noise() {
    if grep -qE 'unknown flag|Usage:' "$tmp_dir/out.log"; then
        fail "$1 called 'ha --version': $(cat "$tmp_dir/out.log")"
    fi
}

if [ -n "$want_arch" ]; then
    # Latest release read from where releases/latest redirects to
    if ! FAKE_LATEST_URL="$latest_tag_url" run_ha_cli "$tmp_dir/ha-ok"; then
        fail "--ha-cli failed although releases/latest redirected to a tag: $(cat "$tmp_dir/out.log")"
    fi
    if grep -q 'api\.github\.com' "$curl_log"; then
        fail "--ha-cli queried the rate-limited REST API: $(cat "$curl_log")"
    fi
    grep -q 'github.com/home-assistant/cli/releases/latest' "$curl_log" || \
        fail "--ha-cli did not look up releases/latest: $(cat "$curl_log")"
    grep -q "releases/download/9.9.1/ha_${want_arch}" "$curl_log" || \
        fail "--ha-cli did not download the latest release: $(cat "$curl_log")"
    [ -x "$tmp_dir/ha-ok/packages/bin/ha" ] || fail "--ha-cli left no binary"
    assert_no_version_flag_noise "--ha-cli after installing"
    [ "$(cat "$tmp_dir/ha-ok/packages/bin/.ha-version" 2>/dev/null)" = "9.9.1" ] || \
        fail "--ha-cli did not record the installed version in .ha-version"

    # Lookup fails (no network) -> non-zero, nothing downloaded. Real curl
    # still prints the URL it got to, which may look like a tag.
    if FAKE_LATEST_URL="$latest_tag_url" FAKE_LATEST_STATUS=22 run_ha_cli "$tmp_dir/ha-down"; then
        fail "--ha-cli exited 0 although the version lookup failed: $(cat "$tmp_dir/out.log")"
    fi
    if grep -q 'releases/download' "$curl_log"; then
        fail "--ha-cli downloaded although the version lookup failed: $(cat "$curl_log")"
    fi
    [ ! -e "$tmp_dir/ha-down/packages/bin/ha" ] || fail "--ha-cli left a binary after a failed lookup"

    # Redirect ends somewhere that is not a release tag -> non-zero, no
    # download, and an existing copy stays as it is.
    make_old_copy "$tmp_dir/ha-notag"
    for bad_url in "" "https://github.com/home-assistant/cli/releases" \
                   "https://github.com/home-assistant/cli/releases/tag/" \
                   "https://github.com/home-assistant/cli/releases/tag/9.9.1/" \
                   "https://github.com/home-assistant/cli/releases/tag/9.9.1?x=1" \
                   "https://github.com/home-assistant/cli/releases/tag/9.9.1#top"; do
        if FAKE_LATEST_URL="$bad_url" run_ha_cli "$tmp_dir/ha-notag"; then
            fail "--ha-cli exited 0 although releases/latest resolved to '$bad_url'"
        fi
        if grep -q 'releases/download' "$curl_log"; then
            fail "--ha-cli downloaded although releases/latest resolved to '$bad_url': $(cat "$curl_log")"
        fi
        grep -q 'old-ha' "$tmp_dir/ha-notag/packages/bin/ha" || \
            fail "--ha-cli touched the existing copy although releases/latest resolved to '$bad_url'"
    done

    # --force replaces an old copy with the latest release; that old copy is
    # exactly what the 4.46.0 pin left behind.
    make_old_copy "$tmp_dir/ha-replace"
    if ! FAKE_LATEST_URL="$latest_tag_url" run_ha_cli "$tmp_dir/ha-replace"; then
        fail "--ha-cli --force failed to replace an old copy: $(cat "$tmp_dir/out.log")"
    fi
    grep -q "releases/download/9.9.1/ha_${want_arch}" "$curl_log" || \
        fail "--ha-cli --force did not download the latest release over an old copy: $(cat "$tmp_dir/out.log")"
    if grep -q 'old-ha' "$tmp_dir/ha-replace/packages/bin/ha"; then
        fail "--ha-cli --force kept the old copy: $(cat "$tmp_dir/out.log")"
    fi
    [ "$(cat "$tmp_dir/ha-replace/packages/bin/.ha-version" 2>/dev/null)" = "9.9.1" ] || \
        fail "--ha-cli --force did not record the new version"

    # Without --force an existing copy stays, and nothing goes to the network.
    make_old_copy "$tmp_dir/ha-keep"
    run_ha_cli "$tmp_dir/ha-keep" "" || \
        fail "--ha-cli without --force failed on an existing copy: $(cat "$tmp_dir/out.log")"
    [ ! -s "$curl_log" ] || fail "--ha-cli without --force called curl on an existing copy: $(cat "$curl_log")"
    grep -q 'old-ha' "$tmp_dir/ha-keep/packages/bin/ha" || fail "--ha-cli without --force touched the existing copy"
    assert_no_version_flag_noise "--ha-cli on an existing copy"
    grep -q 'unknown version, installed before 2.3.1' "$tmp_dir/out.log" || \
        fail "--ha-cli did not flag a copy without .ha-version as old: $(cat "$tmp_dir/out.log")"

    # A copy with a recorded version reports it.
    make_old_copy "$tmp_dir/ha-known"
    printf '9.9.0\n' > "$tmp_dir/ha-known/packages/bin/.ha-version"
    run_ha_cli "$tmp_dir/ha-known" "" || fail "--ha-cli failed on a recorded copy"
    grep -q 'v9.9.0' "$tmp_dir/out.log" || \
        fail "--ha-cli did not report the recorded version: $(cat "$tmp_dir/out.log")"

    # A failed download with --force keeps the old copy instead of deleting it.
    make_old_copy "$tmp_dir/ha-dlfail"
    if FAKE_LATEST_URL="$latest_tag_url" FAKE_DL_STATUS=22 run_ha_cli "$tmp_dir/ha-dlfail"; then
        fail "--ha-cli --force exited 0 although the download failed"
    fi
    grep -q 'old-ha' "$tmp_dir/ha-dlfail/packages/bin/ha" 2>/dev/null || \
        fail "--ha-cli --force lost the old copy after a failed download"
fi

# --- image ships ha, a copy in /data/packages/bin shadows it -------------------
# The app image has /usr/bin/ha. Without --force persist-install stops there,
# but a copy left in /data/packages/bin (an old 4.46.0 from before 2.3.1)
# comes first in PATH. "Nothing to do" was wrong in that case.
fake_image_ha="$tmp_dir/image-ha"
printf '#!/bin/sh\necho image-ha\n' > "$fake_image_ha"
chmod +x "$fake_image_ha"

run_with_image_ha() {
    local root="$1"
    mkdir -p "$root"
    : > "$curl_log"
    PATH="$fake_bin:$PATH" PERSIST_DATA_ROOT="$root" PERSIST_IMAGE_HA="$fake_image_ha" \
        bash "$script" --ha-cli > "$tmp_dir/out.log" 2>&1
}

# Image only: nothing to do, as before.
run_with_image_ha "$tmp_dir/img-only" || fail "--ha-cli failed with only the image CLI"
grep -q 'Nothing to do' "$tmp_dir/out.log" || \
    fail "--ha-cli with only the image CLI did not say there is nothing to do: $(cat "$tmp_dir/out.log")"
[ ! -s "$curl_log" ] || fail "--ha-cli with only the image CLI went to the network"

# Image plus an old, unrecorded copy: name the copy and both ways out.
make_old_copy "$tmp_dir/img-shadow"
run_with_image_ha "$tmp_dir/img-shadow" || fail "--ha-cli failed with a shadowing copy"
if grep -q 'Nothing to do' "$tmp_dir/out.log"; then
    fail "--ha-cli said 'Nothing to do' although a copy shadows the image CLI: $(cat "$tmp_dir/out.log")"
fi
for want in "$tmp_dir/img-shadow/packages/bin/ha" 'unknown version, installed before 2.3.1' \
            'persist-install --ha-cli --force' "rm $tmp_dir/img-shadow/packages/bin/ha"; do
    grep -qF "$want" "$tmp_dir/out.log" || \
        fail "--ha-cli with a shadowing copy did not mention '$want': $(cat "$tmp_dir/out.log")"
done
assert_no_version_flag_noise "--ha-cli with a shadowing copy"
[ ! -s "$curl_log" ] || fail "--ha-cli with a shadowing copy went to the network"

# Image plus a recorded copy: show its version.
make_old_copy "$tmp_dir/img-known"
printf '9.9.0\n' > "$tmp_dir/img-known/packages/bin/.ha-version"
run_with_image_ha "$tmp_dir/img-known" || fail "--ha-cli failed with a recorded shadowing copy"
grep -q 'v9.9.0' "$tmp_dir/out.log" || \
    fail "--ha-cli did not show the shadowing copy's version: $(cat "$tmp_dir/out.log")"

# --- persist-install --apk (n30) ----------------------------------------------
# The explicit form the app uses for names from its options: the name after
# --apk is always a package, never a mode (ha, python, help, list are modes
# in the first position).
apk_log="$tmp_dir/apk.log"
cat > "$fake_bin/apk" <<APK
#!/bin/sh
printf '%s\n' "\$*" >> "$apk_log"
exit 0
APK
chmod +x "$fake_bin/apk"
mkdir -p "$tmp_dir/data-apk"
for name in ha python help list; do
    : > "$apk_log"
    run_persist_install "$tmp_dir/data-apk" 0 --apk "$name" || \
        fail "--apk $name failed: $(cat "$tmp_dir/out.log")"
    grep -qx "add --no-cache $name" "$apk_log" || \
        fail "--apk $name did not reach apk as a package: $(cat "$apk_log")"
done
grep -q 'Home Assistant CLI' "$tmp_dir/out.log" && fail "--apk ha started the ha CLI install"
: > "$apk_log"
run_persist_install "$tmp_dir/data-apk" 0 --apk git vim || fail "--apk with two packages failed"
grep -qx 'add --no-cache git vim' "$apk_log" || fail "--apk git vim: $(cat "$apk_log")"
: > "$apk_log"
if run_persist_install "$tmp_dir/data-apk" 0 --apk; then
    fail "--apk without a package must fail"
fi
[ ! -s "$apk_log" ] || fail "--apk without a package ran apk: $(cat "$apk_log")"

echo "persist-install tests passed"
