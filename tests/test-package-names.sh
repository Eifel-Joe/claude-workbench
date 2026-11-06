#!/usr/bin/env bash
# Package names from the options persistent_apk_packages and
# persistent_pip_packages are checked before persist-install gets them (n30).
# persist-install reads its first argument as the mode (--ha-cli, -p, but also
# ha, python, list, help), and a leading - would reach apk or pip as a flag.
# Valid names go to persist-install --apk one by one, or together to
# persist-install --python. Idea from unsnow-iac (08686e1e, 83c6997e, found in
# miczu71's fork, branch history/unsnow-full).
set -euo pipefail
# Like bashio 0.19.0, which run.sh runs under.
shopt -s inherit_errexit

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
run_sh="$repo_root/claude-workbench/run.sh"
tmp_dir=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
    echo "FAIL (package names): $*" >&2
    exit 1
}

log="$tmp_dir/log"
: > "$log"
bashio::log.info() { printf 'info|%s\n' "$*" >> "$log"; }
bashio::log.warning() { printf 'warning|%s\n' "$*" >> "$log"; }
bashio::log.error() { printf 'error|%s\n' "$*" >> "$log"; }

# shellcheck disable=SC2034  # read by the sourced run.sh
OPTION_READ_GAVE_UP="$tmp_dir/options-unanswered"
# shellcheck disable=SC2034  # read by the sourced run.sh
CLAUDE_RUN_SH_SKIP_MAIN=true
# shellcheck source=/dev/null
source "$run_sh"

# The options as bashio hands them over (JSON array or one item per line).
opt_apk=''
opt_pip=''
read_option() {
    case "$1" in
        persistent_apk_packages) printf '%s' "$opt_apk" ;;
        persistent_pip_packages) printf '%s' "$opt_pip" ;;
        *) printf '%s' "$2" ;;
    esac
}

# persist-install stand-in: "---", then one line per argument.
calls="$tmp_dir/calls"
cat > "$tmp_dir/persist-install" << EOF
#!/usr/bin/env bash
printf '%s\n' '---' "\$@" >> "$calls"
EOF
chmod +x "$tmp_dir/persist-install"
export PERSIST_INSTALL_BIN="$tmp_dir/persist-install"

run_case() {
    opt_apk="$1"
    opt_pip="$2"
    : > "$calls"
    : > "$log"
    auto_install_packages
}
expect_calls() {
    printf '%s\n' "$@" > "$tmp_dir/expected"
    cmp -s "$tmp_dir/expected" "$calls" || \
        fail "unexpected persist-install calls: expected $(tr '\n' ' ' < "$tmp_dir/expected"), got $(tr '\n' ' ' < "$calls")"
}
expect_skipped() {
    local entry
    for entry in "$@"; do
        grep -qF "warning|  Skipping '$entry': not a package name" "$log" || \
            fail "no warning for '$entry': $(cat "$log")"
    done
}

# 1. Modes and flags never reach persist-install; valid names (version pins,
#    apk's cmd: provides) go through --apk.
run_case '["--ha-cli","-p","-x foo","git","git=2.47.0-r0","cmd:ping","py3-pip"]' ''
expect_calls '---' '--apk' 'git' '---' '--apk' 'git=2.47.0-r0' '---' '--apk' 'cmd:ping' '---' '--apk' 'py3-pip'
expect_skipped '--ha-cli' '-p' '-x foo'

# 2. Names that are modes in the first position stay packages after --apk.
run_case '["ha","python"]' ''
expect_calls '---' '--apk' 'ha' '---' '--apk' 'python'
grep -q '^warning|' "$log" && fail "valid names were warned about: $(cat "$log")"

# 3. pip: flags skipped, extras and version specifiers kept, one call.
run_case '' '["-r req.txt","--index-url=x","pandas[all]","requests==2.31.0","foo>=1,<2"]'
expect_calls '---' '--python' 'pandas[all]' 'requests==2.31.0' 'foo>=1,<2'
expect_skipped '-r req.txt' '--index-url=x'

# 4. Surrounding white space is not part of the name.
run_case "$(printf '[" htop ","\\thtop2"]')" ''
expect_calls '---' '--apk' 'htop' '---' '--apk' 'htop2'
grep -q '^warning|' "$log" && fail "trimmed names were warned about: $(cat "$log")"

# 5. The newline form of the list is checked the same way.
run_case $'git\n--ha-cli' ''
expect_calls '---' '--apk' 'git'
expect_skipped '--ha-cli'

# 6. Only invalid pip entries: no persist-install --python without packages.
run_case '' '["-e ."]'
[ ! -s "$calls" ] || fail "persist-install ran for invalid pip entries only: $(cat "$calls")"
expect_skipped '-e .'

# 7. Two names in one entry: skipped with the hint, not passed as one name.
run_case '["git vim"]' ''
[ ! -s "$calls" ] || fail "'git vim' reached persist-install: $(cat "$calls")"
expect_skipped 'git vim'
grep -q 'one package per entry' "$log" || fail "the warning does not say one package per entry"

echo "Package name tests passed"
