#!/usr/bin/with-contenv bashio

# Enable strict error handling
set -e
set -o pipefail

# Time limits for startup steps that touch the network. They all run before the
# web terminal starts, so a hung registry or mirror would leave the panel blank
# for good. pip gets longer: on a Pi it may compile wheels on first install.
# Overridable only so the tests can use a 1 s limit.
STARTUP_NPM_TIMEOUT="${STARTUP_NPM_TIMEOUT:-300}"
STARTUP_APK_TIMEOUT="${STARTUP_APK_TIMEOUT:-300}"
STARTUP_PIP_TIMEOUT="${STARTUP_PIP_TIMEOUT:-900}"
# One `claude plugin ...` call while setting up the Home Assistant plugin.
STARTUP_PLUGIN_TIMEOUT="${STARTUP_PLUGIN_TIMEOUT:-60}"

# Time limit for one app option read from the Supervisor, and the marker that
# says it ran out this start (see read_option). 10 s like the app migration's
# Supervisor check (DETECT_TIMEOUT_MS). Overridable only for the tests.
OPTION_READ_TIMEOUT="${OPTION_READ_TIMEOUT:-10}"
OPTION_READ_GAVE_UP="${OPTION_READ_GAVE_UP:-/tmp/.claude-workbench-options-unanswered}"

# The folders persist-install fills with programs: last on PATH for run.sh and
# the app's services, first in the terminal session (boot_path, terminal_path).
# Overridable for tests only (tests/test-command-path.sh).
PERSIST_PATHS="${PERSIST_PATHS:-/data/packages/bin:/data/packages/python/venv/bin:/data/home/.local/bin}"

# What counts as one package in persistent_apk_packages / persistent_pip_packages
# (n30, auto_install_packages). Both must start with a letter or digit, so no
# entry can reach persist-install, apk or pip as a flag. apk: name, version pin
# (git=2.47.0-r0), cmd:/so: provides, @repository tags. pip: name with extras and
# version specifiers (pandas[all], foo>=1,<2). In variables without backslashes:
# `]` first in the class is a literal `]`, `-` last a literal `-`.
# From unsnow-iac (08686e1e, 83c6997e, found in miczu71's fork, branch
# history/unsnow-full); `:` and `@` added for apk here. The app takeover uses
# the same rules in scripts/app-migration/package-names.js
# (tests/test-package-names.sh compares both).
APK_NAME_RE='^[A-Za-z0-9][A-Za-z0-9._+=<>~:@-]*$'
PIP_SPEC_RE='^[A-Za-z0-9][]A-Za-z0-9._+=!~,<>[-]*$'

# npm's download cache; overridable for tests only (tests/test-npm-cache.sh).
NPM_CACHE_DIR="${NPM_CACHE_DIR:-/tmp/npm-cache}"
NPM_LEGACY_CACHE_DIR="${NPM_LEGACY_CACHE_DIR:-/data/home/.npm}"

# Claude Code commands and skills shipped in the image; overridable for tests
# only (tests/test-claude-assets.sh).
SHIPPED_CLAUDE_DIR="${SHIPPED_CLAUDE_DIR:-/opt/.claude}"

# Where the image service stores pasted images; overridable for tests only
# (tests/test-image-retention.sh).
IMAGE_UPLOAD_DIR="${IMAGE_UPLOAD_DIR:-/data/images}"

# Auto-continue's switch ("on"/"off"), read by the image service on every poll
# and flipped by the auto-continue command. init_auto_continue rewrites it on
# every start, so the option decides again after a restart
# (image-service/auto-continue.js).
AUTO_CONTINUE_DIR="${AUTO_CONTINUE_DIR:-/run/claude-workbench}"

# CPU check shared with the session picker and health check (cpu-check.sh).
# shellcheck source=/dev/null
[ -f "${CPU_CHECK_SCRIPT:-/opt/scripts/cpu-check.sh}" ] && . "${CPU_CHECK_SCRIPT:-/opt/scripts/cpu-check.sh}"

# Run a startup step under a time limit and return its own status. A cut-off is
# told by the elapsed time, not the exit code: GNU timeout returns 124, BusyBox
# timeout (Alpine) does not promise that.
run_with_timeout() {
    local seconds="$1"
    local label="$2"
    local started=$SECONDS
    local status=0
    shift 2

    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" "$@" || status=$?
    else
        "$@" || status=$?
    fi

    if [ "$status" -ne 0 ] && [ $((SECONDS - started)) -ge "$seconds" ]; then
        bashio::log.warning "$label timed out after ${seconds}s"
    fi
    return "$status"
}

# Read an app option: the value, or $2 when the read fails or comes back empty.
# Every option read in this file goes through here, and nothing else calls
# bashio::config.
#
# Root cause: bashio 0.19.0 (Alpine 3.24 base) enables `shopt -s
# inherit_errexit` (hassio-addons/bashio#192). When the Supervisor API call
# inside bashio::config fails, a bare `x=$(bashio::config ...)` now fails too:
# set -e ended startup before the panel, and inside
# "$(get_claude_launch_command)" it silently emptied the launch command. On the
# left of || (or in an if) bash ignores errexit, so bashio::config instead
# returns 0 with EMPTY output (the empty API answer), not its default - that is
# why `x=$(bashio::config k d) || x=d` is not enough and `${value:-$2}` is
# needed. Rejected: the `|| x=d` pattern of heytcass 78d7b12f and nsleigh
# a1f0f2da alone (empty auto_launch_claude opened the session picker instead
# of Claude). No option has a non-empty default that a user could want to
# replace with an empty value. tests/test-production-run.sh covers both
# failure modes.
#
# Time limit (n11). Root cause: bashio::api.supervisor runs curl with no
# --max-time, so a Supervisor that accepts the connection but never answers
# held startup forever and the panel stayed blank. Fix: inside this command
# substitution only, a curl function adds --max-time; curl ends itself, bashio
# reports a failed call, the default applies. bashio caches no failure, so every
# later read would wait again (13 reads); a read that ran into the limit leaves
# a marker file - a variable would be lost, read_option always runs in $(...) -
# and later reads take their default at once. main removes the marker. A fast
# failure leaves none: every read tries on its own, as before. Told by the
# elapsed time, because bashio does not pass curl's exit status on.
# Rejected: `timeout` around the read (it cannot run a function, and through
# `bash -c` it kills only bash: the orphaned curl keeps the $(...) pipe open
# and the read still hangs), a watchdog subshell (same orphan), a curlrc
# (applies to every curl of the environment). tests/test-option-timeout.sh.
#
# "null" (n21). Root cause: bashio 0.19.0 sets `default_value=${2:-null}`
# (lib/config.sh), so an option missing from the configuration, or set to JSON
# null, came back from `read_option x ''` as the word "null", not empty.
# Affected were all reads with an empty default: Claude started with
# `--remote-control null`, the package lists ran `persist-install null`.
# Fix: "null" counts as empty here, for every option at once, instead of a
# check in each caller (as upstream does). Accepted: an option whose value is
# literally "null" reads as unset. Rejected: bashio::config.exists first (a
# second Supervisor request, and the time limit above would apply twice).
# The Supervisor normally fills in config.yaml's defaults, so this is a guard.
# tests/test-option-null.sh.
read_option() {
    local value=''
    local started=$SECONDS
    if [ ! -e "$OPTION_READ_GAVE_UP" ]; then
        value=$(
            curl() { command curl --max-time "$OPTION_READ_TIMEOUT" "$@"; }
            bashio::config "$1" "$2"
        ) || value=''
        if [ -z "$value" ] && [ $((SECONDS - started)) -ge "$OPTION_READ_TIMEOUT" ]; then
            { : > "$OPTION_READ_GAVE_UP"; } 2>/dev/null || true
            bashio::log.warning "The Supervisor did not answer within ${OPTION_READ_TIMEOUT}s; the app options use their defaults for this start"
        fi
    fi
    if [ "$value" = null ]; then
        value=''
    fi
    printf '%s\n' "${value:-$2}"
}

# npm keeps only a download cache. Under HOME=/data/home it landed in
# /data/home/.npm and so in every backup of the app (115 MB on a real install;
# heytcass/home-assistant-addons#105). /tmp is emptied on every restart, at
# the price of a full download (~113 MB, measured) for the update on start.
setup_npm_cache() {
    export npm_config_cache="$NPM_CACHE_DIR"
    if [ -d "$NPM_LEGACY_CACHE_DIR" ]; then
        rm -rf "$NPM_LEGACY_CACHE_DIR"
        bashio::log.info "Removed the old npm cache from $NPM_LEGACY_CACHE_DIR (kept it out of backups)"
    fi
}

# Copy the shipped commands and skills over $HOME/.claude on every start. They
# used to be copied only into a missing $HOME/.claude, so existing installs kept
# their first version for good. Only the shipped files are written; logins,
# projects, settings and the user's own skills stay as they are. A failed copy
# (e.g. /data full) is logged, not fatal: run.sh runs under set -e, and this runs
# before the panel is served (tests/test-claude-assets.sh).
install_shipped_claude_assets() {
    local target="$1"

    [ -d "$SHIPPED_CLAUDE_DIR" ] || return 0
    if ! { mkdir -p "$target" && cp -R "$SHIPPED_CLAUDE_DIR/." "$target/"; }; then
        bashio::log.warning "Could not refresh Claude Code skills & commands in $target"
        return 0
    fi
    bashio::log.info "  - Claude Code skills & commands: up to date"
}

# Initialize environment for Claude Code CLI using /data (HA best practice)
init_environment() {
    # Use /data exclusively - guaranteed writable by HA Supervisor
    local data_home="/data/home"
    local config_dir="/data/.config"
    local cache_dir="/data/.cache"
    local state_dir="/data/.local/state"
    local claude_config_dir="/data/.config/claude"
    local gh_config_dir="/data/.config/gh"
    local persist_root="/data/packages"
    local persist_bin="$persist_root/bin"
    local persist_lib="$persist_root/lib"
    local persist_python="$persist_root/python"

    bashio::log.info "Initializing Claude Code environment in /data..."

    # Create all required directories
    if ! mkdir -p "$data_home" "$config_dir/claude" "$config_dir/gh" "$cache_dir" "$state_dir" "/data/.local" \
                  "$persist_bin" "$persist_lib" "$persist_python"; then
        bashio::log.error "Failed to create directories in /data"
        exit 1
    fi

    # Set permissions
    chmod 755 "$data_home" "$config_dir" "$cache_dir" "$state_dir" "$claude_config_dir" "$gh_config_dir" \
              "$persist_root" "$persist_bin" "$persist_lib" "$persist_python"

    # Ensure Claude native binary is available at $HOME/.local/bin/claude
    # The native installer places it at /root/.local/bin/claude during Docker build,
    # but at runtime HOME=/data/home, so Claude's self-check looks in /data/home/.local/bin/
    local native_bin_dir="$data_home/.local/bin"
    if [ ! -d "$native_bin_dir" ]; then
        mkdir -p "$native_bin_dir"
    fi
    if [ -f /root/.local/bin/claude ] && [ ! -f "$native_bin_dir/claude" ]; then
        ln -sf /root/.local/bin/claude "$native_bin_dir/claude"
        bashio::log.info "  - Claude native binary linked: $native_bin_dir/claude"
    fi

    # Set XDG and application environment variables
    export HOME="$data_home"
    export XDG_CONFIG_HOME="$config_dir"
    export XDG_CACHE_HOME="$cache_dir"
    export XDG_STATE_HOME="$state_dir"
    export XDG_DATA_HOME="/data/.local/share"
    setup_npm_cache

    # Claude-specific environment variables
    export ANTHROPIC_CONFIG_DIR="$claude_config_dir"
    export ANTHROPIC_HOME="/data"

    # Disable auto-updates: binary is baked into the container image,
    # updates are delivered via app releases, not CLI self-update
    export DISABLE_AUTOUPDATER=1

    # GitHub CLI persistent configuration
    export GH_CONFIG_DIR="$gh_config_dir"

    # Get dangerously-skip-permissions configuration (read_option: see there)
    local dangerously_skip_permissions
    dangerously_skip_permissions=$(read_option 'dangerously_skip_permissions' 'false')
    export CLAUDE_DANGEROUS_MODE="$dangerously_skip_permissions"

    # This app always runs as root inside an HA supervisor container.
    # IS_SANDBOX=1 tells Claude Code that root is expected (container sandbox),
    # so it won't refuse to start. This is independent of --dangerously-skip-permissions
    # (which controls permission prompts, not whether Claude can launch).
    export IS_SANDBOX=1

    # The system's programs first, the persistent folders after them (n20,
    # boot_path); the terminal session gets them first (terminal_path).
    local boot
    boot=$(boot_path)
    export PATH="$boot"
    # $persist_lib is deliberately NOT on run.sh's own LD_LIBRARY_PATH (n10):
    # the loader searches it before the system's libraries, so one broken copy
    # from persist-install took down node (the panel), ttyd and the tmux
    # server. The terminal session gets it instead (terminal_library_path),
    # login shells from the profile script below. Idea from unsnow-iac
    # (commit 08686e1e, found in miczu71's fork, branch history/unsnow-full),
    # who re-added it before exec ttyd;
    # here ttyd and the tmux server stay without it too.
    export PKG_CONFIG_PATH="$persist_lib/pkgconfig:${PKG_CONFIG_PATH:-}"

    # Python virtual environment if it exists
    if [ -d "$persist_python/venv" ]; then
        export VIRTUAL_ENV="$persist_python/venv"
        bashio::log.info "  - Python venv: active"
    fi

    # Create profile script for persistent environment variables
    # This ensures ALL bash sessions (including ttyd shells) have correct PATH
    cat > /etc/profile.d/persistent-packages.sh << 'PROFILE_EOF'
# Persistent package environment - auto-loaded for all bash sessions
export HOME="/data/home"
export XDG_CONFIG_HOME="/data/.config"
export XDG_CACHE_HOME="/data/.cache"
export XDG_STATE_HOME="/data/.local/state"
export XDG_DATA_HOME="/data/.local/share"
export ANTHROPIC_CONFIG_DIR="/data/.config/claude"
export ANTHROPIC_HOME="/data"

# Disable auto-updates inside container (updates via app releases)
export DISABLE_AUTOUPDATER=1

# Always running as root inside HA supervisor container — IS_SANDBOX=1 allows Claude to start
export IS_SANDBOX=1

# GitHub CLI persistent configuration
export GH_CONFIG_DIR="/data/.config/gh"

# npm's download cache stays out of /data (and so out of backups)
export npm_config_cache="/tmp/npm-cache"

# Persistent package paths and native Claude binary (HIGHEST PRIORITY)
export PATH="/data/packages/bin:/data/packages/python/venv/bin:/data/home/.local/bin:$PATH"
export LD_LIBRARY_PATH="/data/packages/lib:${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="/data/packages/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

# Python virtual environment if it exists
if [ -d "/data/packages/python/venv" ]; then
    export VIRTUAL_ENV="/data/packages/python/venv"
fi
PROFILE_EOF

    chmod 644 /etc/profile.d/persistent-packages.sh
    bashio::log.info "  - Profile script created: /etc/profile.d/persistent-packages.sh"

    # Migrate any existing authentication files from legacy locations
    migrate_legacy_auth_files "$claude_config_dir"

    # Setup Claude Code skills and commands
    install_shipped_claude_assets "$data_home/.claude"

    bashio::log.info "Environment initialized:"
    bashio::log.info "  - Home: $HOME"
    bashio::log.info "  - Config: $XDG_CONFIG_HOME"
    bashio::log.info "  - Claude config: $ANTHROPIC_CONFIG_DIR"
    bashio::log.info "  - GitHub config: $GH_CONFIG_DIR"
    bashio::log.info "  - Cache: $XDG_CACHE_HOME"
    bashio::log.info "  - Persistent packages: $persist_root"
}

# One-time migration of existing authentication files
migrate_legacy_auth_files() {
    local target_dir="$1"
    local marker="${AUTH_MIGRATION_MARKER:-/data/.auth-migration-complete}"
    local migrated=false

    # This must run exactly once. It copies legacy credential files over the
    # live ones in /data, so re-running it on every start lets a stale file left
    # behind in /config silently overwrite current, working credentials.
    if [ -f "$marker" ]; then
        bashio::log.info "Legacy auth migration already completed on $(cat "$marker" 2>/dev/null), skipping"
        return 0
    fi

    bashio::log.info "Checking for existing authentication files to migrate..."

    # Check common legacy locations.
    # AUTH_LEGACY_LOCATIONS is a test seam: a newline-separated directory list.
    local -a legacy_locations
    if [ -n "${AUTH_LEGACY_LOCATIONS:-}" ]; then
        mapfile -t legacy_locations <<< "$AUTH_LEGACY_LOCATIONS"
    else
        legacy_locations=(
            "/root/.config/anthropic"
            "/root/.anthropic"
            "/config/claude-config"
            "/tmp/claude-config"
        )
    fi

    for legacy_path in "${legacy_locations[@]}"; do
        if [ -d "$legacy_path" ] && [ "$(ls -A "$legacy_path" 2>/dev/null)" ]; then
            bashio::log.info "Migrating auth files from: $legacy_path"
            
            # Copy files to the new location, dotfiles included, never
            # overwriting what is already there.
            #
            # Two separate bugs met here. `"$legacy_path"/*` does not match
            # dotfiles, so this silently skipped exactly the files it exists for
            # (.credentials.json, .claude.json) — "/." copies hidden entries.
            # But simply fixing the glob would make this overwrite live
            # credentials in /data with a stale legacy copy the first time it
            # ran. -n makes migration fill in only what is missing, which is all
            # a migration should ever do.
            if cp -a -n "$legacy_path/." "$target_dir/" 2>/dev/null; then
                # Set proper permissions
                find "$target_dir" -type f -exec chmod 600 {} \;
                
                # Create compatibility symlink if this is a standard location
                if [[ "$legacy_path" == "/root/.config/anthropic" ]] || [[ "$legacy_path" == "/root/.anthropic" ]]; then
                    rm -rf "$legacy_path"
                    ln -sf "$target_dir" "$legacy_path"
                    bashio::log.info "Created compatibility symlink: $legacy_path -> $target_dir"
                fi
                
                migrated=true
                bashio::log.info "Migration completed from: $legacy_path"
            else
                bashio::log.warning "Failed to migrate from: $legacy_path"
            fi
        fi
    done

    if [ "$migrated" = false ]; then
        bashio::log.info "No existing authentication files found to migrate"
    fi

    # Record completion whether or not anything was found, so a legacy file
    # appearing in /config later can never clobber live credentials.
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "$marker" 2>/dev/null || \
        bashio::log.warning "Could not write migration marker: $marker"
}

# Verify required tools, installing only what the image is missing.
#
# ttyd, tmux, jq and curl are all baked into the image by the Dockerfile. This
# used to run an unconditional `apk add` on every container start, which made
# startup depend on the Alpine mirrors being reachable and aborted the app
# outright when they were not. The apk path is kept purely as a fallback for
# images built before these packages were baked in.
install_tools() {
    local -a missing=()
    local tool

    for tool in ttyd tmux jq curl; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        bashio::log.info "Required tools present in image (no download needed)"
        return 0
    fi

    bashio::log.warning "Tools missing from image, installing at runtime: ${missing[*]}"
    if ! run_with_timeout "$STARTUP_APK_TIMEOUT" "Installing missing tools" \
            apk add --no-cache "${missing[@]}"; then
        bashio::log.error "Failed to install required tools: ${missing[*]}"
        exit 1
    fi
    bashio::log.info "Tools installed successfully"
}

# The Alpine release of the base image (X.Y) and the one /data/packages was
# last checked against. Without a marker it is 3.21: every release before 3.6.0
# was built on it. Sets ALPINE_RELEASE_CURRENT (empty when unreadable) and
# ALPINE_RELEASE_PREVIOUS. PERSIST_ROOT, SYSTEM_ROOT and ALPINE_RELEASE_FILE
# are overridable for tests only (tests/test-alpine-migration.sh).
persisted_alpine_releases() {
    local root="${PERSIST_ROOT:-/data/packages}"
    ALPINE_RELEASE_CURRENT=$(cut -d. -f1,2 "${ALPINE_RELEASE_FILE:-/etc/alpine-release}" 2>/dev/null) || \
        ALPINE_RELEASE_CURRENT=''
    ALPINE_RELEASE_PREVIOUS=$(cat "$root/.alpine-release" 2>/dev/null) || ALPINE_RELEASE_PREVIOUS=''
    [ -n "$ALPINE_RELEASE_PREVIOUS" ] || ALPINE_RELEASE_PREVIOUS='3.21'
}

# persist-install copies a package's shared libraries into /data/packages/lib,
# which the terminal session puts FIRST on LD_LIBRARY_PATH (terminal_library_path;
# up to 3.6.0 run.sh did so for node, the panel's entry point, as well). After
# the base image moves to a new Alpine release, an old copy of a library the
# system also has (libstdc++, sqlite-libs ...) would be loaded instead of the
# system's own: Claude and the user's programs can fail to start. So, once per release
# change and before the image service starts, move every copy whose name the
# system also has, with different content, to stale-alpine-<old>/lib. Nothing is
# deleted. Copies without a system counterpart stay; check_persisted_alpine_release
# names them later. Rejected: only warning (nsleigh's version) - the panel breaks
# before anyone reads the log. bin is never moved: a newer `ha` from
# persist-install --ha-cli is there on purpose (tests/test-alpine-migration.sh).
move_stale_persisted_libs() {
    local root="${PERSIST_ROOT:-/data/packages}"
    local system="${SYSTEM_ROOT:-}"
    local quarantine file name copy has_system identical target
    local -a moved=()

    persisted_alpine_releases
    [ -n "$ALPINE_RELEASE_CURRENT" ] || return 0
    [ "$ALPINE_RELEASE_PREVIOUS" != "$ALPINE_RELEASE_CURRENT" ] || return 0
    quarantine="$root/stale-alpine-$ALPINE_RELEASE_PREVIOUS/lib"

    for file in "$root"/lib/*; do
        [ -f "$file" ] || continue
        name=${file##*/}
        has_system=false
        identical=false
        for copy in "$system/usr/lib/$name" "$system/lib/$name"; do
            [ -f "$copy" ] || continue
            has_system=true
            if cmp -s "$file" "$copy"; then
                identical=true
            fi
        done
        [ "$has_system" = true ] && [ "$identical" = false ] || continue
        # Never overwrite an earlier quarantined copy of the same name.
        target="$quarantine/$name"
        [ ! -e "$target" ] || target="$quarantine/$name.$(date +%s).$$"
        if mkdir -p "$quarantine" && mv "$file" "$target"; then
            moved+=("$name")
        else
            bashio::log.warning "Could not move the stale library copy $file out of the way"
        fi
    done

    if [ "${#moved[@]}" -gt 0 ]; then
        bashio::log.warning "The base image moved from Alpine $ALPINE_RELEASE_PREVIOUS to $ALPINE_RELEASE_CURRENT. These library copies from persist-install would have replaced the system's own and were moved to $quarantine: ${moved[*]}"
    fi
}

# After the package installs: name the files persist-install copied on an
# older Alpine release, so they can be reinstalled, then record the current
# release. Packages from the app options were just installed into the system
# and copied again, so an identical system file means the copy is current.
# bin/ha from persist-install --ha-cli is a static download, not tied to the
# release. Adapted from nsleigh (ESJavadex/claude-code-ha@a1f0f2da).
check_persisted_alpine_release() {
    local root="${PERSIST_ROOT:-/data/packages}"
    local system="${SYSTEM_ROOT:-}"
    local file name dir current
    local -a stale=()

    persisted_alpine_releases
    [ -n "$ALPINE_RELEASE_CURRENT" ] || return 0

    if [ "$ALPINE_RELEASE_PREVIOUS" != "$ALPINE_RELEASE_CURRENT" ]; then
        for file in "$root"/bin/* "$root"/lib/*; do
            [ -f "$file" ] || continue
            name=${file##*/}
            if [ "$file" = "$root/bin/ha" ] && [ -f "$root/bin/.ha-version" ]; then
                continue
            fi
            current=false
            for dir in usr/bin usr/sbin bin sbin usr/lib lib; do
                if cmp -s "$file" "$system/$dir/$name"; then
                    current=true
                    break
                fi
            done
            [ "$current" = true ] || stale+=("$name")
        done
        if [ "${#stale[@]}" -gt 0 ]; then
            bashio::log.warning "The base image moved from Alpine $ALPINE_RELEASE_PREVIOUS to $ALPINE_RELEASE_CURRENT. These files were installed with persist-install on $ALPINE_RELEASE_PREVIOUS and may not work; reinstall their packages: ${stale[*]}"
        fi
    fi

    if [ "$(cat "$root/.alpine-release" 2>/dev/null || true)" != "$ALPINE_RELEASE_CURRENT" ]; then
        if ! { mkdir -p "$root" && printf '%s\n' "$ALPINE_RELEASE_CURRENT" > "$root/.alpine-release"; } 2>/dev/null; then
            bashio::log.warning "Could not record the Alpine release in $root/.alpine-release"
        fi
    fi
}

# The persist-install venv in /data belongs to the Python that created it. When
# the base image brings a new one (Alpine 3.21's 3.12 -> 3.24's 3.14), its
# packages stop importing and its own pip breaks, while venv/bin/python still
# resolves - to the new interpreter. So: list what was installed by name (pip's
# REQUESTED marker, the same rule as app-migration/apply.js; dependencies come
# back with them; no marker at all means everything), write that list to
# .reinstall-pending next to the venv, recreate the venv, then work the list
# off. Whatever fails (no network at boot) stays on the list and is retried on
# the next start, so an offline start does not lose the packages; after three
# failed starts the rest moves to .reinstall-failed, so a package that can't
# come back (no build for the new Python) does not delay every start for good.
# Packages installed from a path, URL or git (PEP 610 direct_url.json) are not
# fetched by name - PyPI would serve a different package of that name, or
# none - but named for a manual reinstall. Runs after the panel is up and
# before the options' pip packages are installed. Adapted from nsleigh
# (ESJavadex/claude-code-ha@a1f0f2da); the REQUESTED rule, the retry list and
# the direct_url check are our own (tests/test-alpine-migration.sh).
# PERSIST_VENV and PYTHON_BIN are overridable for tests only.
migrate_python_venv() {
    local venv="${PERSIST_VENV:-/data/packages/python/venv}"
    local python="${PYTHON_BIN:-python3}"
    local state_dir="${venv%/*}"
    local pending="$state_dir/.reinstall-pending"
    local tries_file="$state_dir/.reinstall-tries"
    local given_up="$state_dir/.reinstall-failed"
    local max_tries=3
    local old new meta name tries has_requested=false
    local -a all=() requested=() manual=() list=() failed=()

    if [ -f "$venv/pyvenv.cfg" ]; then
        old=$(sed -n -E '/^version(_info)? *=/{s/^version(_info)? *= *([0-9]+\.[0-9]+).*/\2/p;q;}' \
            "$venv/pyvenv.cfg") || old=''
        new=$("$python" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null) || new=''
        if [ -n "$old" ] && [ -n "$new" ] && [ "$old" != "$new" ]; then
            for meta in "$venv/lib/python$old/site-packages"/*.dist-info/METADATA; do
                [ -f "$meta" ] || continue
                name=$(sed -n '/^Name:/{s/^Name:[[:space:]]*//;p;q;}' "$meta" | tr -d '\r[:space:]') || name=''
                case "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" in
                    ''|pip|setuptools|wheel) continue ;;
                esac
                if [ -f "${meta%/METADATA}/REQUESTED" ]; then
                    has_requested=true
                fi
                if [ -f "${meta%/METADATA}/direct_url.json" ]; then
                    manual+=("$name")
                    continue
                fi
                all+=("$name")
                if [ -f "${meta%/METADATA}/REQUESTED" ]; then
                    requested+=("$name")
                fi
            done
            if [ "$has_requested" = true ]; then
                list=("${requested[@]}")
            else
                list=("${all[@]}")
            fi
            # Written to a new file and renamed, so a full disk never leaves a
            # cut-off name on the list.
            if [ "${#list[@]}" -gt 0 ] && ! { { cat "$pending" 2>/dev/null || true; printf '%s\n' "${list[@]}"; } \
                    > "$pending.new" && mv -f "$pending.new" "$pending"; } 2>/dev/null; then
                rm -f "$pending.new"
                bashio::log.error "Python changed from $old to $new, but the package list could not be saved to $pending; keeping the old venv"
                return 0
            fi
            bashio::log.warning "Python changed from $old to $new: rebuilding the persist-install venv in $venv"
            if [ "${#manual[@]}" -gt 0 ]; then
                bashio::log.warning "Installed from a path, URL or git, so not reinstalled automatically - reinstall by hand with persist-install --python: ${manual[*]}"
            fi
            rm -rf "$venv"
            if ! "$python" -m venv "$venv"; then
                rm -rf "$venv"
                bashio::log.error "Could not create the Python venv in $venv; its packages stay listed in $pending for the next start"
                return 0
            fi
        fi
    fi

    [ -f "$pending" ] || return 0
    if [ ! -x "$venv/bin/pip" ]; then
        rm -rf "$venv"
        if ! "$python" -m venv "$venv"; then
            rm -rf "$venv"
            bashio::log.error "Could not create the Python venv in $venv; its packages stay listed in $pending for the next start"
            return 0
        fi
    fi

    bashio::log.info "Reinstalling Python packages into the persist-install venv..."
    while IFS= read -r name || [ -n "$name" ]; do
        name=${name//[[:space:]]/}
        [ -n "$name" ] || continue
        bashio::log.info "  Reinstalling: $name"
        # stdin from /dev/null: pip must not eat the rest of the list
        run_with_timeout "$STARTUP_PIP_TIMEOUT" "Reinstall of $name" \
            "$venv/bin/pip" install -q "$name" < /dev/null || failed+=("$name")
    done < "$pending"

    if [ "${#failed[@]}" -eq 0 ]; then
        rm -f "$pending" "$tries_file"
        return 0
    fi

    tries=$(cat "$tries_file" 2>/dev/null) || tries=0
    case "$tries" in ''|*[!0-9]*) tries=0 ;; esac
    tries=$((tries + 1))
    if [ "$tries" -ge "$max_tries" ]; then
        if ! { printf '%s\n' "${failed[@]}" >> "$given_up" && rm -f "$pending" "$tries_file"; } 2>/dev/null; then
            bashio::log.warning "Could not move the reinstall list to $given_up"
        fi
        bashio::log.warning "Gave up reinstalling after $max_tries starts: ${failed[*]} (listed in $given_up). Reinstall by hand with: persist-install --python ${failed[*]}"
        return 0
    fi
    if ! { printf '%s\n' "${failed[@]}" > "$pending.new" && mv -f "$pending.new" "$pending" \
            && printf '%s\n' "$tries" > "$tries_file"; } 2>/dev/null; then
        bashio::log.warning "Could not update $pending"
    fi
    bashio::log.warning "Could not reinstall: ${failed[*]}. The next start tries again (attempt $tries of $max_tries), or run: persist-install --python ${failed[*]}"
}

# Setup tmux configuration and session wrapper
setup_tmux() {
    local tmux_conf="${HOME}/.tmux.conf"
    local tmux_mouse
    local tmux_wrapper="${TMUX_WRAPPER_PATH:-/usr/local/bin/tmux-claude}"

    tmux_mouse=$(read_option 'tmux_mouse' 'false')
    case "${tmux_mouse:-false}" in
        true|on|yes|1) tmux_mouse="on" ;;
        *) tmux_mouse="off" ;;
    esac
    bashio::log.info "Setting up tmux..."

    cat > "$tmux_conf" << TMUX_EOF
# Mouse mode is disabled by default so ttyd/browser copy and paste keeps working.
set -g mouse ${tmux_mouse}

# Let applications in the pane (Claude Code's /copy) set the clipboard through
# OSC 52 and forward it out to ttyd. The default 'external' drops what they send.
set -g set-clipboard on

# tmux only emits OSC 52 when the outer terminal advertises the 'Ms' capability.
# ttyd's frontend always accepts it, so declare it instead of trusting terminfo.
set -as terminal-features ',*:clipboard'

# Large scrollback buffer
set -g history-limit 50000

# Reduce escape-time so claude/vim feel responsive inside tmux
set -g escape-time 20

# Pass focus in/out events on, so Claude Code and vim notice when the
# terminal gains or loses focus
set -g focus-events on

# Start window and pane numbering at 1 (easier to reach on keyboard)
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on

# Status bar
set -g status-bg colour235
set -g status-fg colour136
set -g status-left '[#S] '
set -g status-right '%H:%M'

# Own settings: this file is rewritten on every start, ~/.tmux.conf.local is
# never touched by the app. Loaded last, so it overrides everything above
# (owine's fork, commit 1175851a).
source-file -q ~/.tmux.conf.local
TMUX_EOF

    # Wrapper: attach to existing 'claude' session, or create a fresh one that runs the launch command
    # Creates the session again once it ended; same session environment as in
    # start_web_terminal: the same functions, copied in (declare -f), with
    # PERSIST_PATHS as run.sh has it. ttyd runs the wrapper with the boot PATH.
    {
        printf '#!/bin/bash\n'
        printf 'PERSIST_PATHS=%q\n' "$PERSIST_PATHS"
        declare -f terminal_library_path path_without_persist terminal_path
        cat << 'WRAPPER_EOF'
if tmux has-session -t claude 2>/dev/null; then
    exec tmux attach-session -t claude
else
    exec tmux new-session -e "LD_LIBRARY_PATH=$(terminal_library_path)" \
        -e "PATH=$(terminal_path)" -s claude \
        /usr/bin/env "PATH=$(terminal_path)" /bin/bash -c 'eval "$CLAUDE_LAUNCH_CMD"'
fi
WRAPPER_EOF
    } > "$tmux_wrapper"
    chmod +x "$tmux_wrapper"

    bashio::log.info "tmux configured (${tmux_conf})"
}

# Configure optional persistent Claude Code override in /data
setup_persistent_claude() {
    local use_persistent_claude
    local auto_update_claude_on_start
    local persistent_root="${PERSISTENT_CLAUDE_ROOT:-/data/npm}"
    local persistent_bin="$persistent_root/bin/claude"
    local persistent_package="$persistent_root/lib/node_modules/@anthropic-ai/claude-code/package.json"
    local claude_link="${CLAUDE_BIN_LINK:-/usr/local/bin/claude}"
    # The native binary's symlink lives in $HOME/.local/bin, which the terminal
    # session and login shells put ahead of /usr/local/bin on PATH (terminal_path,
    # profile script). Overwrite it too, or "claude" typed there keeps resolving
    # to the stale build-time binary even after this override activates.
    local native_bin_link="${CLAUDE_NATIVE_BIN_LINK:-/data/home/.local/bin/claude}"
    local claude_npm_spec="@anthropic-ai/claude-code@latest"

    use_persistent_claude=$(read_option 'use_persistent_claude' 'false')
    auto_update_claude_on_start=$(read_option 'auto_update_claude_on_start' 'false')

    # Exported so the session picker knows whether to offer a manual
    # "Update Claude Code" menu option.
    export USE_PERSISTENT_CLAUDE="$use_persistent_claude"

    if [ "$use_persistent_claude" != "true" ]; then
        bashio::log.info "Persistent Claude override: disabled"
        return 0
    fi

    mkdir -p "$persistent_root"

    # Exported so the session picker's manual update option can reuse the
    # same install path/spec instead of duplicating them.
    export PERSISTENT_CLAUDE_ROOT="$persistent_root"
    export CLAUDE_BIN_LINK="$claude_link"
    export CLAUDE_NPM_SPEC="$claude_npm_spec"

    if [ "$auto_update_claude_on_start" = "true" ]; then
        bashio::log.info "Persistent Claude override: updating Claude Code in /data/npm..."
        if run_with_timeout "$STARTUP_NPM_TIMEOUT" "Persistent Claude override: npm update" \
                env NPM_CONFIG_PREFIX="$persistent_root" npm install -g "$claude_npm_spec" --prefer-online; then
            bashio::log.info "Persistent Claude override: update completed"
        else
            # A cut-off npm can leave /data/npm half-replaced, and later updates
            # may then keep failing; a fresh install is the way out.
            bashio::log.warning "Persistent Claude override: update failed, continuing with existing version if present. If this keeps happening, delete /data/npm and restart the app to reinstall"
        fi
    fi

    # On a CPU without x86-64-v2 (cpu-check.sh) `--version` hangs into the
    # timeout below and the install gets blamed; name the real cause instead.
    if command -v claude_cpu_missing_flags >/dev/null 2>&1; then
        local cpu_missing
        cpu_missing=$(claude_cpu_missing_flags)
        if [ -n "$cpu_missing" ]; then
            bashio::log.warning "Persistent Claude override: skipped, Claude Code cannot run on this CPU (missing: ${cpu_missing}; needs x86-64-v2)"
            return 0
        fi
    fi

    # Smoke-test the persistent binary before trusting it: this rejects a stale
    # or wrong-architecture install (e.g. an amd64 binary left in /data on a Pi).
    # Run under a timeout so a hung `--version` can never block app startup.
    local -a version_check=("$persistent_bin" --version)
    if command -v timeout >/dev/null 2>&1; then
        version_check=(timeout 15 "$persistent_bin" --version)
    fi

    if [ -x "$persistent_bin" ] && \
       [ -f "$persistent_package" ] && \
       "${version_check[@]}" >/dev/null 2>&1; then
        ln -sf "$persistent_bin" "$claude_link"
        ln -sf "$persistent_bin" "$native_bin_link"
        bashio::log.info "Persistent Claude override active: $claude_link -> $persistent_bin"
        bashio::log.info "  - Also overrode $native_bin_link (earlier on PATH than $claude_link)"
    else
        bashio::log.warning "Persistent Claude override enabled but no working persistent Claude install found at $persistent_root"
        bashio::log.warning "Install it manually once with: NPM_CONFIG_PREFIX=/data/npm npm install -g $claude_npm_spec"
    fi
}

# An offer to take over Claude data from an older app installed alongside waits for the
# terminal (detect_app_migration writes it, with_migration_dialog shows it).
# Undecided counts as pending too (n33): while the check could not decide
# (Supervisor error, time limit, crash), an old app may be there, and an offer
# made on a later start would find what the status line and the plugin wrote
# (settings.json, plugin lists, ~/.claude.json from `claude plugin`) and keep
# the old app's files out - the takeover never replaces existing files.
# Rejected: merging those files during the takeover (three formats that Claude
# owns and changes). An offer that still comes after the setup (the old app
# installed later, n40) has the old files replace ours as whole files
# (app-migration/apply.js setAsideOwnSetup). tests/test-migration-undecided.sh.
migration_offer_pending() {
    [ -f "${APP_MIGRATION_OFFER:-/data/migration/offer.json}" ] \
        || [ -f "${APP_MIGRATION_UNDECIDED:-/data/migration/undecided}" ]
}

# Whether the Supervisor answered the option request this start. read_option
# hands back the default on any failure, so a probe reads auto_launch_claude -
# in every answer, because the Supervisor fills in config.yaml's defaults
# (supervisor/apps/app.py, App.options) - with a placeholder default. A
# successful answer is cached by bashio, so this adds no request. Rejected:
# the placeholder on the option itself (an empty list reads as the default,
# so `statusline: []` would look unreadable).
options_readable() {
    local probe
    probe=$(read_option 'auto_launch_claude' '__unreadable__')
    [ "$probe" != '__unreadable__' ]
}

# One `claude plugin` call for setup_ha_plugin, time-limited, quiet.
# After one call ran into the time limit, the others of this start are skipped
# (HA_PLUGIN_CLI_GAVE_UP): a hanging CLI costs one time limit, not three. Runs
# in the caller's shell, so the flag survives between calls.
ha_plugin_cli() {
    local started=$SECONDS status=0
    [ "${HA_PLUGIN_CLI_GAVE_UP:-false}" = false ] || return 1
    run_with_timeout "$STARTUP_PLUGIN_TIMEOUT" "Home Assistant plugin: claude plugin $1" \
        claude plugin "$@" < /dev/null > /dev/null 2>&1 || status=$?
    if [ "$status" -ne 0 ] && [ $((SECONDS - started)) -ge "$STARTUP_PLUGIN_TIMEOUT" ]; then
        HA_PLUGIN_CLI_GAVE_UP=true
    fi
    return "$status"
}

# The Home Assistant plugin for Claude Code (p19): homeassistant-config from
# ESJavadex/claude-homeassistant-plugins (MIT), copied into the image at build
# time (Dockerfile). It teaches Claude current Home Assistant syntax, checks
# every YAML file Claude edits (PostToolUse hook) and adds /ha-check,
# /ha-upgrade and /ha-find-duplicates. No network: the marketplace is a local
# folder.
#   - first start: register the marketplace, install the plugin
#   - a newer bundled version: `claude plugin update`, never `install`, which
#     would switch on a plugin the user turned off with /plugin
#   - home_assistant_plugin off: disable it (not uninstall); on again: enable
# Works only when option or bundled version changed (state file). Adapted from
# ESJavadex (ESJavadex/claude-code-ha@42c53d48). Our changes: read_option
# instead of `bashio::config ... || x=true` (empty under bashio 0.19.0);
# run_with_timeout; the state file is written only after success, so a failed
# install or update is retried on the next start; every step is guarded, the
# function always returns 0 (set -e, inherit_errexit); nothing is written
# while a takeover offer is open - the takeover copies the old ~/.claude
# without replacing existing files, so a settings.json written now would hide
# the user's old one (R1) - or when the options could not be read, so a silent
# Supervisor cannot switch on a plugin the user turned off (R2).
# tests/test-ha-plugin.sh, tests/ci-boot-smoke.sh.
setup_ha_plugin() {
    local marketplace_dir="${HA_PLUGIN_MARKETPLACE_DIR:-/opt/claude-plugins/claude-homeassistant-plugins}"
    local marketplace="claude-homeassistant-plugins"
    local plugin_id="homeassistant-config@${marketplace}"
    local manifest="$marketplace_dir/homeassistant-config/.claude-plugin/plugin.json"
    local state_file="${HA_PLUGIN_STATE:-$HOME/.claude/plugins/.claude-workbench-ha-plugin}"
    # ESJavadex's app keeps the same "<on>:<version>" record here (42c53d48);
    # the data takeover copies it along with ~/.claude (n31).
    local old_state_file="${HA_PLUGIN_OLD_STATE:-$HOME/.claude/plugins/.addon-ha-plugin}"
    local enabled bundled wanted previous='' installed='' list

    if [ ! -f "$manifest" ]; then
        bashio::log.info "Home Assistant plugin: not bundled in this image"
        return 0
    fi
    if ! command -v claude > /dev/null 2>&1; then
        bashio::log.warning "Home Assistant plugin: claude not found, skipping"
        return 0
    fi
    # Claude hangs on a CPU without x86-64-v2 (cpu-check.sh); every call would
    # run into the time limit, on every start. Same check as
    # setup_persistent_claude.
    if command -v claude_cpu_missing_flags > /dev/null 2>&1; then
        local cpu_missing
        cpu_missing=$(claude_cpu_missing_flags)
        if [ -n "$cpu_missing" ]; then
            bashio::log.warning "Home Assistant plugin: skipped, Claude Code cannot run on this CPU (missing: ${cpu_missing})"
            return 0
        fi
    fi
    if migration_offer_pending; then
        bashio::log.info "Home Assistant plugin: a data takeover offer is open or could not be checked, set up on the next start"
        return 0
    fi
    if ! options_readable; then
        bashio::log.warning "Home Assistant plugin: the app options could not be read, plugin unchanged this start"
        return 0
    fi
    enabled=$(read_option 'home_assistant_plugin' 'true')
    [ "$enabled" = false ] || enabled=true

    bundled=$(jq -r '.version // empty' "$manifest" 2> /dev/null) || bundled=''
    if [ -z "$bundled" ]; then
        bashio::log.warning "Home Assistant plugin: no version in $manifest, skipping"
        return 0
    fi
    wanted="${enabled}:${bundled}"
    if [ -f "$state_file" ]; then
        previous=$(cat "$state_file" 2> /dev/null) || previous=''
    elif [ -f "$old_state_file" ]; then
        # Taken over from ESJavadex's app (n31): without its record a plugin
        # the user removed there by hand would be installed again, and one the
        # old option had switched off would not be switched on by ours.
        previous=$(cat "$old_state_file" 2> /dev/null) || previous=''
    fi
    if [ "$previous" = "$wanted" ]; then
        bashio::log.info "Home Assistant plugin: ${bundled}, home_assistant_plugin=${enabled}, nothing to do"
        return 0
    fi

    if ! list=$(run_with_timeout "$STARTUP_PLUGIN_TIMEOUT" "Home Assistant plugin: claude plugin list" \
            claude plugin list --json < /dev/null 2> /dev/null); then
        bashio::log.warning "Home Assistant plugin: could not list Claude's plugins, will retry on next start"
        return 0
    fi
    # Only an array is understood. Anything else would read as "not
    # installed", and install switches a plugin back on that the user turned
    # off; so nothing is done and the next start checks again.
    if ! installed=$(jq -er --arg id "$plugin_id" \
            'if type == "array" then (first(.[] | select(.id == $id) | .version) // "") else error end' \
            <<< "$list" 2> /dev/null); then
        bashio::log.warning "Home Assistant plugin: unexpected answer from claude plugin list, plugin unchanged this start"
        return 0
    fi

    HA_PLUGIN_CLI_GAVE_UP=false
    if [ "$enabled" = true ]; then
        if [ -z "$installed" ] && [ "${previous%%:*}" = true ]; then
            # We installed it before and it is gone: the user removed it with
            # /plugin. A newer bundled version must not bring it back; the
            # option off and on again reinstalls it.
            bashio::log.info "Home Assistant plugin: removed by hand, leaving it out (switch home_assistant_plugin off and on to reinstall)"
            if ! { mkdir -p "${state_file%/*}" && printf '%s\n' "$wanted" > "$state_file"; } 2> /dev/null; then
                bashio::log.warning "Home Assistant plugin: could not write ${state_file}"
            fi
            return 0
        fi
        ha_plugin_cli marketplace add "$marketplace_dir" || true
        if [ -z "$installed" ]; then
            if ! ha_plugin_cli install "$plugin_id"; then
                bashio::log.warning "Home Assistant plugin: install failed, will retry on next start"
                return 0
            fi
            bashio::log.info "Home Assistant plugin: installed ${bundled} (turn off with the home_assistant_plugin option or /plugin)"
        else
            if [ "$installed" != "$bundled" ]; then
                ha_plugin_cli marketplace update "$marketplace" || true
                if ! ha_plugin_cli update "$plugin_id"; then
                    bashio::log.warning "Home Assistant plugin: update failed, keeping ${installed}; will retry on next start"
                    return 0
                fi
                bashio::log.info "Home Assistant plugin: updated ${installed} -> ${bundled}"
            fi
            # Switched back on through the option. enable fails on a plugin that
            # is already on (already_in_goal_state), which is fine.
            if [ "${previous%%:*}" = false ]; then
                ha_plugin_cli enable "$plugin_id" || true
                bashio::log.info "Home Assistant plugin: enabled by the home_assistant_plugin option"
            fi
        fi
    elif [ -n "$installed" ]; then
        ha_plugin_cli disable "$plugin_id" || true
        bashio::log.info "Home Assistant plugin: disabled by the home_assistant_plugin option"
    fi

    if ! { mkdir -p "${state_file%/*}" && printf '%s\n' "$wanted" > "$state_file"; } 2> /dev/null; then
        bashio::log.warning "Home Assistant plugin: could not write ${state_file}; the next start checks the plugin again"
    fi
    return 0
}

# The Home Assistant status line under Claude's prompt (p18;
# scripts/ha-statusline.sh). The statusline option is a list of pieces in
# display order: a piece name (ha-statusline --segments), --- for a new line,
# an entity as sensor.x or Label=sensor.x; -sensor.car_* leaves entities out
# of the home pieces. Empty means the default layout, off turns it off.
# The script is always installed, so a status line of the user's own can show
# the home with `ha-statusline --home`. ~/.claude/settings.json only gets our
# statusLine when it has none or already has ours: one made with /statusline
# or by hand is never replaced, and off only removes ours.
# By ESJavadex (ESJavadex/claude-code-ha@ae4f88ec, dde63c98; 7b558af0: the
# user's command is never logged, it may carry a token). Our changes:
# read_option in its own assignment (as an argument a failed read vanished);
# every step guarded, the function always returns 0 (set -e, inherit_errexit:
# an unguarded mktemp or jq would have ended the start before ttyd); nothing
# but the script is written while a takeover offer is open (R1) or the options
# cannot be read (R2), see setup_ha_plugin. tests/test-statusline.sh.
setup_statusline() {
    local script_source="${HA_STATUSLINE_SOURCE:-/opt/scripts/ha-statusline.sh}"
    local script_bin="${HA_STATUSLINE_BIN:-/usr/local/bin/ha-statusline}"
    local config_file="${HA_STATUSLINE_CONFIG:-/data/.config/ha-statusline.json}"
    local settings_file="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"
    local raw='' items='' item label entity_id segments='' current tmp next enabled=true
    local layout='[]' exclude='[]'

    if [ -f "$script_source" ]; then
        if ! { cp "$script_source" "$script_bin" && chmod 755 "$script_bin"; } 2> /dev/null; then
            bashio::log.warning "Status line: could not install $script_bin"
            return 0
        fi
    fi
    if migration_offer_pending; then
        bashio::log.info "Status line: a data takeover offer is open or could not be checked, set up on the next start"
        return 0
    fi
    if ! options_readable; then
        bashio::log.warning "Status line: the app options could not be read, status line unchanged this start"
        return 0
    fi

    segments=$("$script_bin" --segments 2> /dev/null | tr '\n' ' ') || segments=''
    segments=" $segments "
    raw=$(read_option 'statusline' '')
    items=$(normalize_config_list "$raw") || items=''
    while IFS= read -r item; do
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        [ -n "$item" ] || continue
        if [ "$item" = 'off' ]; then
            enabled=false
        elif [ "$item" = '---' ] || [[ "$segments" == *" $item "* ]]; then
            if next=$(jq -c --arg s "$item" '. + [{s: $s}]' <<< "$layout"); then
                layout="$next"
            fi
        elif [[ "$item" == -* ]]; then
            item="${item//[[:space:]]/}"
            if [[ ! "$item" =~ ^-[a-z0-9_*]+\.[a-z0-9_*]+$ ]]; then
                bashio::log.warning "  Status line: skipping '$item' (to leave entities out, write -sensor.car_battery or -sensor.car_*)"
                continue
            fi
            if next=$(jq -c --arg p "${item#-}" '. + [$p]' <<< "$exclude"); then
                exclude="$next"
            fi
        else
            if [[ "$item" == *=* ]]; then
                label="${item%%=*}"
                entity_id="${item#*=}"
            else
                label=''
                entity_id="$item"
            fi
            entity_id="${entity_id//[[:space:]]/}"
            if [[ ! "$entity_id" =~ ^[a-z0-9_]+\.[a-z0-9_]+$ ]]; then
                bashio::log.warning "  Status line: skipping '$item' (not a piece name or an entity ID like sensor.living_room_co2)"
                continue
            fi
            if next=$(jq -c --arg id "$entity_id" --arg label "$label" \
                    '. + [{s: "entity", id: $id, label: ($label | gsub("^\\s+|\\s+$"; "") | .[0:16])}]' <<< "$layout"); then
                layout="$next"
            fi
        fi
    done <<< "$items"

    # No pieces (only exclusions, or only invalid items) means the default layout
    if ! { mkdir -p "${config_file%/*}" \
            && jq -n --argjson l "$layout" --argjson x "$exclude" \
                '{layout: (if ($l | length) > 0 then $l else null end), exclude: $x}' > "$config_file"; } 2> /dev/null; then
        bashio::log.warning "Status line: could not write $config_file"
    fi

    if ! mkdir -p "${settings_file%/*}" 2> /dev/null; then
        bashio::log.warning "Status line: could not create ${settings_file%/*}"
        return 0
    fi
    if [ ! -s "$settings_file" ]; then
        [ "$enabled" = true ] || return 0
        if ! { printf '{}\n' > "$settings_file"; } 2> /dev/null; then
            bashio::log.warning "Status line: could not write $settings_file"
            return 0
        fi
    fi
    if ! current=$(jq -r '.statusLine.command // empty' "$settings_file" 2> /dev/null); then
        bashio::log.warning "Status line: $settings_file is not valid JSON, leaving it alone"
        return 0
    fi
    if ! tmp=$(mktemp "$settings_file.XXXXXX" 2> /dev/null); then
        bashio::log.warning "Status line: could not write next to $settings_file"
        return 0
    fi
    if [ "$enabled" != true ]; then
        if [ "$current" = "$script_bin" ]; then
            if jq 'del(.statusLine)' "$settings_file" > "$tmp" 2> /dev/null && mv -f "$tmp" "$settings_file"; then
                bashio::log.info "Home Assistant status line turned off"
            else
                bashio::log.warning "Status line: could not update $settings_file"
            fi
        fi
    elif [ -z "$current" ] || [ "$current" = "$script_bin" ]; then
        if jq --arg cmd "$script_bin" \
                '.statusLine = {type: "command", command: $cmd, padding: 0, refreshInterval: 30}' \
                "$settings_file" > "$tmp" 2> /dev/null && mv -f "$tmp" "$settings_file"; then
            bashio::log.info "Home Assistant status line enabled"
        else
            bashio::log.warning "Status line: could not update $settings_file"
        fi
    else
        # Not the command itself: it may carry a token in its arguments
        bashio::log.info "Status line: keeping your own. Add the home to it with: ha-statusline --home"
    fi
    rm -f "$tmp"
    return 0
}

# Setup session picker script
setup_session_picker() {
    # Copy session picker script from built-in location
    if [ -f "/opt/scripts/claude-session-picker.sh" ]; then
        if ! cp /opt/scripts/claude-session-picker.sh /usr/local/bin/claude-session-picker; then
            bashio::log.error "Failed to copy claude-session-picker script"
            exit 1
        fi
        chmod +x /usr/local/bin/claude-session-picker
        bashio::log.info "Session picker script installed successfully"
    else
        bashio::log.warning "Session picker script not found, using auto-launch mode only"
    fi

    # Setup authentication helper if it exists
    if [ -f "/opt/scripts/claude-auth-helper.sh" ]; then
        chmod +x /opt/scripts/claude-auth-helper.sh
        bashio::log.info "Authentication helper script ready"
    fi
}

# Setup persistent package manager
setup_persistent_packages() {
    local persist_install="${PERSIST_INSTALL_BIN:-/usr/local/bin/persist-install}"
    local persist_install_source="${PERSIST_INSTALL_SOURCE:-/opt/scripts/persist-install}"

    # Install persist-install command globally
    if [ -f "$persist_install_source" ]; then
        cp "$persist_install_source" "$persist_install"
        chmod +x "$persist_install"
        bashio::log.info "Persistent package manager installed: 'persist-install'"
    fi

    # Auto-install packages from configuration
    auto_install_packages
}

# Normalize both Bashio list formats seen across Supervisor generations:
# newline-separated values and JSON arrays.
normalize_config_list() {
    local raw="$1"

    if [ -z "$raw" ] || [ "$raw" = "[]" ]; then
        return 0
    fi

    if printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
        printf '%s' "$raw" | jq -r '.[]'
    else
        printf '%s\n' "$raw"
    fi
}

# Auto-install packages from app configuration
auto_install_packages() {
    local apk_packages
    local pip_packages
    local package
    local persist_install="${PERSIST_INSTALL_BIN:-/usr/local/bin/persist-install}"
    local -a pip_package_list=()
    local apk_raw pip_raw

    # Read into own assignments: as an argument of normalize_config_list a
    # failed read would vanish without a trace (see read_option).
    apk_raw=$(read_option 'persistent_apk_packages' '')
    pip_raw=$(read_option 'persistent_pip_packages' '')
    apk_packages=$(normalize_config_list "$apk_raw")
    pip_packages=$(normalize_config_list "$pip_raw")

    # Every entry is checked before persist-install gets it (n30). Its first
    # argument picks the mode, so an entry like --ha-cli or -p, but also ha or
    # python, started another mode, and an entry starting with - reached apk or
    # pip as a flag. Entries that are not one package name are skipped with a
    # warning (APK_NAME_RE, PIP_SPEC_RE); apk names go after --apk, where
    # every name is a package. Rejected: checking in persist-install itself,
    # which would also block deliberate manual calls such as
    # `persist-install --python git+https://...`. Idea from unsnow-iac
    # (08686e1e, 83c6997e). tests/test-package-names.sh.
    if [ -n "$apk_packages" ]; then
        bashio::log.info "Auto-installing system packages from config..."
        while IFS= read -r package; do
            package="${package#"${package%%[![:space:]]*}"}"
            package="${package%"${package##*[![:space:]]}"}"
            [ -n "$package" ] || continue
            if [[ ! "$package" =~ $APK_NAME_RE ]]; then
                bashio::log.warning "  Skipping '$package': not a package name (one package per entry)"
                continue
            fi
            bashio::log.info "  Installing: $package"
            run_with_timeout "$STARTUP_APK_TIMEOUT" "Auto-install of $package" \
                "$persist_install" --apk "$package" || bashio::log.warning "Failed to install: $package"
        done <<< "$apk_packages"
    fi

    if [ -n "$pip_packages" ]; then
        bashio::log.info "Auto-installing Python packages from config..."
        while IFS= read -r package; do
            package="${package#"${package%%[![:space:]]*}"}"
            package="${package%"${package##*[![:space:]]}"}"
            [ -n "$package" ] || continue
            if [[ ! "$package" =~ $PIP_SPEC_RE ]]; then
                bashio::log.warning "  Skipping '$package': not a package name (one package per entry)"
                continue
            fi
            pip_package_list+=("$package")
        done <<< "$pip_packages"

        if [ "${#pip_package_list[@]}" -gt 0 ]; then
            bashio::log.info "  Installing: ${pip_package_list[*]}"
            run_with_timeout "$STARTUP_PIP_TIMEOUT" "Auto-install of Python packages" \
                "$persist_install" --python "${pip_package_list[@]}" || \
                bashio::log.warning "Failed to install Python packages"
        fi
    fi
}

# Legacy monitoring functions removed - using simplified /data approach

# Determine Claude launch command based on configuration
# Session picker handles its own loop, so Claude exiting returns to the menu (#6)
get_claude_launch_command() {
    local auto_launch_claude
    local dangerously_skip_permissions
    local remote_control
    local remote_control_session_name
    local claude_flags=""

    # Get configuration values
    auto_launch_claude=$(read_option 'auto_launch_claude' 'true')
    dangerously_skip_permissions=$(read_option 'dangerously_skip_permissions' 'false')
    remote_control=$(read_option 'remote_control' 'false')
    remote_control_session_name=$(read_option 'remote_control_session_name' '')

    # Claude Code hangs without a word on CPUs without x86-64-v2 (cpu-check.sh);
    # open the session picker instead, which explains it.
    local cpu_missing=""
    if command -v claude_cpu_missing_flags >/dev/null 2>&1; then
        cpu_missing=$(claude_cpu_missing_flags)
    fi
    if [ -n "$cpu_missing" ]; then
        bashio::log.warning "Claude Code cannot run on this CPU (missing: ${cpu_missing}; needs x86-64-v2). Not starting it; see Troubleshooting in the app documentation."
        if [ -f /usr/local/bin/claude-session-picker ]; then
            echo "clear && /usr/local/bin/claude-session-picker"
        else
            echo "clear && bash -l"
        fi
        return 0
    fi

    # Build Claude flags
    if [ "$dangerously_skip_permissions" = "true" ]; then
        claude_flags="--dangerously-skip-permissions"
        bashio::log.warning "Claude will run with --dangerously-skip-permissions (unrestricted file access)"
    fi

    # Remote Control: start the auto-launched interactive session already paired
    # with claude.ai/code and the Claude mobile app (same as `claude --remote-control`),
    # so a phone or browser can drive it without opening the web terminal first.
    # Only affects the auto-launch path below; the session picker builds its own
    # commands. Needs a claude.ai OAuth login and Claude Code v2.1.51+.
    if [ "$remote_control" = "true" ]; then
        claude_flags="${claude_flags:+${claude_flags} }--remote-control"
        if [ -n "$remote_control_session_name" ]; then
            # printf %q shell-quotes the name so spaces (and any other special
            # characters) survive the eval in the tmux wrapper as a single argument.
            claude_flags="${claude_flags} $(printf '%q' "$remote_control_session_name")"
        fi
        bashio::log.info "Remote Control enabled: Claude will start with --remote-control"
        if [ "$auto_launch_claude" != "true" ]; then
            bashio::log.warning "remote_control is set but has no effect while auto_launch_claude is false"
        fi
    fi

    if [ "$auto_launch_claude" = "true" ]; then
        # Auto-launch Claude first, then fall back to session picker on exit
        if [ -f /usr/local/bin/claude-session-picker ]; then
            echo "clear && echo 'Welcome to Claude Workbench!' && echo '' && echo 'Starting Claude...' && sleep 1 && /usr/local/bin/claude ${claude_flags}; /usr/local/bin/claude-session-picker"
        else
            echo "clear && echo 'Welcome to Claude Workbench!' && echo '' && echo 'Starting Claude...' && sleep 1 && /usr/local/bin/claude ${claude_flags}"
        fi
    else
        # Show interactive session picker (has its own while-true loop)
        if [ -f /usr/local/bin/claude-session-picker ]; then
            echo "clear && /usr/local/bin/claude-session-picker"
        else
            bashio::log.warning "Session picker not found, falling back to auto-launch"
            echo "clear && echo 'Welcome to Claude Workbench!' && echo '' && echo 'Starting Claude...' && sleep 1 && /usr/local/bin/claude"
        fi
    fi
}


# Pasted and dropped images land in /data/images and go into every backup of the
# app. Delete the image service's own pasted-* files older than
# image_retention_days (0 keeps all). Anything but a whole number from 0 to 3650
# (the schema's range) deletes nothing - for a deletion that is the only safe
# default. The cap matters: BusyBox find keeps -mtime in 32 bits, so a huge value
# would wrap to +0 and delete every image older than a day. A failing find is
# logged, not fatal: run.sh runs under set -e, and this runs before the panel is
# served (owine's fork, PR #380; tests/test-image-retention.sh).
prune_uploaded_images() {
    local value days removed

    # No default here: this option deletes. If the read fails, the schema
    # default 30 would delete images of a user who set 0 (keep all), so an
    # unreadable value deletes nothing this time (tests/test-production-run.sh).
    value=$(read_option 'image_retention_days' '')
    if [ -z "$value" ]; then
        bashio::log.warning "image_retention_days could not be read; keeping all uploaded images this time"
        return 0
    fi
    case "$value" in
        ''|*[!0-9]*) days=-1 ;;
        *) [ "${#value}" -le 4 ] && days=$((10#$value)) || days=-1 ;;
    esac
    if [ "$days" -lt 0 ] || [ "$days" -gt 3650 ]; then
        bashio::log.warning "image_retention_days '${value}' is not a whole number from 0 to 3650; keeping all uploaded images"
        return 0
    fi
    [ "$days" -gt 0 ] || return 0
    [ -d "$IMAGE_UPLOAD_DIR" ] || return 0

    # -mtime +N matches files whose age in whole days exceeds N, so +(days-1)
    # means "at least days old".
    if ! removed=$(find "$IMAGE_UPLOAD_DIR" -maxdepth 1 -type f -name 'pasted-*' \
            -mtime "+$((days - 1))" -print -delete | wc -l); then
        bashio::log.warning "Could not clean up old uploaded images in ${IMAGE_UPLOAD_DIR}"
        return 0
    fi
    removed=$((removed))
    if [ "$removed" -gt 0 ]; then
        bashio::log.info "Removed ${removed} uploaded image(s) older than ${days} day(s) from ${IMAGE_UPLOAD_DIR}"
    fi
}

# Write auto-continue's initial state from the option. Must run before the
# image service starts; a failure only logs, the panel matters more.
init_auto_continue() {
    local state=off value

    value=$(read_option 'auto_continue' 'false')
    [ "$value" = "true" ] && state=on
    if ! { mkdir -p "$AUTO_CONTINUE_DIR" && printf '%s\n' "$state" > "$AUTO_CONTINUE_DIR/auto-continue"; } 2>/dev/null; then
        bashio::log.warning "Could not write the auto-continue switch to ${AUTO_CONTINUE_DIR}; auto-continue stays off"
        return 0
    fi
    rm -f "$AUTO_CONTINUE_DIR/auto-continue.status"
    if [ "$state" = "on" ]; then
        bashio::log.info "Auto-continue after a usage limit is on (switch it with: auto-continue on|off)"
    fi
}

# Start image upload service
start_image_service() {
    local image_port=7680
    local ttyd_port=7681
    local upload_dir="/data/images"
    local service_dir="/opt/image-service"
    local server_file="${service_dir}/server.js"

    bashio::log.info "Starting image upload service on port ${image_port}..."

    # Create upload directory if it doesn't exist
    mkdir -p "${upload_dir}"
    chmod 755 "${upload_dir}"

    # Export environment variables for the image service
    export IMAGE_SERVICE_PORT="${image_port}"
    export TTYD_PORT="${ttyd_port}"
    export UPLOAD_DIR="${upload_dir}"

    # Check if server.js exists
    if [ ! -f "${server_file}" ]; then
        bashio::log.error "server.js not found at ${server_file}"
        ls -la "${service_dir}"
        return 1
    fi

    # Check if node_modules exists
    if [ ! -d "${service_dir}/node_modules" ]; then
        bashio::log.error "node_modules not found in ${service_dir}"
        bashio::log.info "Attempting to install dependencies..."
        cd "${service_dir}" && \
            run_with_timeout "$STARTUP_NPM_TIMEOUT" "Image service: npm install" npm install || \
            bashio::log.error "npm install failed"
        cd - > /dev/null
    fi

    # Start the service under a supervisor and wait for it to actually answer.
    #
    # The previous implementation piped node into a `while read` loop and stored
    # $! as "the service PID". In bash, $! after a pipeline is the PID of the
    # LAST element, so it captured the logging loop, not node. That loop outlives
    # a node that dies instantly, which made the `kill -0` readiness check pass
    # unconditionally: "Image service is running successfully" was printed even
    # when the service was already dead. Readiness is now proven by an actual
    # /health response.
    bashio::log.info "Starting Node.js service from ${server_file}..."
    run_image_service_supervised "${server_file}" &
    IMAGE_SERVICE_SUPERVISOR_PID=$!
    export IMAGE_SERVICE_SUPERVISOR_PID

    if wait_for_image_service "${image_port}" "${IMAGE_SERVICE_SUPERVISOR_PID}"; then
        bashio::log.info "Image service is healthy on port ${image_port}"
        return 0
    fi

    bashio::log.error "Image service never became healthy on port ${image_port}."
    bashio::log.error "It serves the ingress entry point, so the app panel would be blank."
    return 1
}

# Forward image-service output into the app log, one line at a time.
log_image_service_output() {
    local line
    while IFS= read -r line; do
        bashio::log.info "[Image Service] $line"
    done
}

# Keep the image service alive: it serves the ingress entry point and proxies
# the terminal, so if it dies the app panel goes blank until someone
# restarts the app by hand. Backoff is capped so a hard failure does not
# spin the CPU on a Raspberry Pi.
run_image_service_supervised() {
    local server_file="$1"
    local backoff=1
    local exit_code

    while true; do
        exit_code=0
        node "${server_file}" > >(log_image_service_output) 2>&1 || exit_code=$?
        bashio::log.warning "Image service exited (code ${exit_code}); restarting in ${backoff}s"
        sleep "${backoff}"
        if [ "${backoff}" -lt 30 ]; then
            backoff=$(( backoff * 2 ))
        fi
    done
}

# Poll /health until the service answers, the supervisor dies, or we time out.
wait_for_image_service() {
    local port="$1"
    local supervisor_pid="$2"
    local attempts="${IMAGE_SERVICE_HEALTH_ATTEMPTS:-30}"
    local attempt

    for (( attempt = 1; attempt <= attempts; attempt++ )); do
        if [ -n "$supervisor_pid" ] && ! kill -0 "$supervisor_pid" 2>/dev/null; then
            bashio::log.error "Image service supervisor exited before becoming healthy"
            return 1
        fi

        if curl -fsS --max-time 2 "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
            bashio::log.info "Image service answered /health after ${attempt} attempt(s)"
            return 0
        fi

        sleep 1
    done

    return 1
}

# Offer to take over Claude data from another Claude Terminal Pro app (e.g. the
# ESJavadex original) installed alongside. Detection only reads the Supervisor
# API and writes an offer file; the selection window runs in the terminal.
detect_app_migration() {
    local cli="${APP_MIGRATION_CLI:-/opt/scripts/app-migration/cli.js}"
    local undecided="${APP_MIGRATION_UNDECIDED:-/data/migration/undecided}"
    [ -f "$cli" ] || return 0
    local line
    # Undecided until cli.js has decided and removes it (n33, see
    # migration_offer_pending); a check that fails or is killed leaves it.
    if ! { mkdir -p "${undecided%/*}" && : > "$undecided"; } 2> /dev/null; then
        bashio::log.warning "App migration: could not create $undecided"
    fi
    while IFS= read -r line; do
        case "$line" in
            WARNING:*) bashio::log.warning "${line#WARNING: }" ;;
            *) bashio::log.info "$line" ;;
        esac
    done < <(node "$cli" detect 2>&1 || true)
}

# Prefixes the launch command with the selection window while an offer exists.
# The window runs in the terminal session, where persist-install's folders come
# first on PATH (terminal_path), so it calls the image's node by its full path,
# like /usr/local/bin/claude in the launch command (n20).
with_migration_dialog() {
    local launch_command="$1"
    local offer="${APP_MIGRATION_OFFER:-/data/migration/offer.json}"
    local cli="${APP_MIGRATION_CLI:-/opt/scripts/app-migration/cli.js}"
    if [ -f "$offer" ]; then
        printf '/usr/bin/node %s dialog; %s\n' "$cli" "$launch_command"
    else
        printf '%s\n' "$launch_command"
    fi
}

# LD_LIBRARY_PATH for the tmux session 'claude' (n10): the persist-install
# libraries first, then whatever run.sh had. `tmux new-session -e` sets it in
# the session environment, so every pane and window of the session has it -
# Claude, which starts the user's programs (Bash commands, MCP servers, hooks),
# the session picker and its bash - but not the tmux server, ttyd or node.
# Claude keeps it: without it, a persist-install program whose libraries exist
# only in /data/packages/lib would fail inside Claude. Rejected: CLAUDE_ENV_FILE
# for Claude's Bash commands only (its interplay with SessionStart hooks is not
# documented, MCP servers and hooks would still lack the folder). Ending the
# session keeps the panel working: the session picker follows with a bash.
# Keep in step with the tmux-claude wrapper (setup_tmux).
# tests/test-library-path.sh, tests/ci-boot-smoke.sh.
terminal_library_path() {
    printf '%s\n' "/data/packages/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
}

# PATH order (n20). Root cause: init_environment put PERSIST_PATHS first on
# run.sh's own PATH, so every program run.sh and its services start by name -
# bashio's curl and jq, node for the panel, npm, apk, python3, tmux, ttyd,
# claude - would run a same-named copy from /data/packages/bin (writable,
# survives restarts) instead of the image's. Fix: run.sh and its services run
# with boot_path (the system first, the persistent folders after it, so a
# program only persist-install has is still found); the tmux session 'claude'
# gets terminal_path (the persistent folders first) in its session
# environment, from both places that create it, like terminal_library_path.
# Login shells keep them first through the profile script. Idea from
# unsnow-iac (08686e1e, 83c6997e: one PERSIST_PATHS, no duplicate entries;
# miczu71's fork, branch history/unsnow-full), who put them first again before
# exec ttyd; here ttyd and the tmux server stay on the boot PATH.
# Both functions are copied into the tmux-claude wrapper (setup_tmux).
#
# The first pane (3.6.3). Root cause: tmux 3.7c builds a pane's environment
# from the session environment and then replaces PATH with the PATH of the
# client running new-session, as long as that client is not attached
# (spawn.c, "Then the PATH environment variable"). Both places that create
# the session are such clients with the boot PATH, so `-e PATH=...` reached
# the session environment (new windows) but not the first pane, where Claude
# and the session picker run: 3.6.2 had the persistent folders last there.
# Fix: the pane's command sets PATH itself, through /usr/bin/env, and runs
# /bin/bash by its full path (a bash from persist-install does not replace
# the session's). -e PATH stays for later windows. Only PATH is special in
# tmux; -e LD_LIBRARY_PATH reaches the pane. Rejected: running new-session
# with PATH=terminal_path in front - in start_web_terminal that call starts
# the tmux server, which would then run with the persistent folders first.
# tests/test-command-path.sh (case 6), tests/ci-boot-smoke.sh (pane's
# /proc/<pid>/environ).
path_without_persist() {
    local entry rest='' p skip
    local -a persist_dirs path_parts
    IFS=: read -ra persist_dirs <<< "$PERSIST_PATHS"
    IFS=: read -ra path_parts <<< "$PATH"
    for entry in "${path_parts[@]}"; do
        [ -n "$entry" ] || continue
        skip=false
        for p in "${persist_dirs[@]}"; do
            if [ "$entry" = "$p" ]; then
                skip=true
            fi
        done
        if [ "$skip" = false ]; then
            rest="${rest:+$rest:}$entry"
        fi
    done
    printf '%s\n' "$rest"
}

boot_path() {
    local rest
    rest=$(path_without_persist)
    printf '%s\n' "${rest:+$rest:}$PERSIST_PATHS"
}

terminal_path() {
    local rest
    rest=$(path_without_persist)
    printf '%s\n' "$PERSIST_PATHS${rest:+:$rest}"
}

# Start main web terminal
start_web_terminal() {
    local port=7681
    bashio::log.info "Starting web terminal on port ${port}..."

    # Log environment information for debugging
    bashio::log.info "Environment variables:"
    bashio::log.info "ANTHROPIC_CONFIG_DIR=${ANTHROPIC_CONFIG_DIR}"
    bashio::log.info "HOME=${HOME}"

    # Get the appropriate launch command based on configuration
    local launch_command
    launch_command=$(with_migration_dialog "$(get_claude_launch_command)")

    # Log the configuration being used
    local auto_launch_claude
    auto_launch_claude=$(read_option 'auto_launch_claude' 'true')
    bashio::log.info "Auto-launch Claude: ${auto_launch_claude}"

    # Export launch command so the tmux-claude wrapper and session can access it
    export CLAUDE_LAUNCH_CMD="$launch_command"

    # Pre-create the persistent tmux session so the first browser connection is instant
    if ! tmux has-session -t claude 2>/dev/null; then
        bashio::log.info "Creating persistent tmux session 'claude'..."
        tmux new-session -d -e "LD_LIBRARY_PATH=$(terminal_library_path)" \
            -e "PATH=$(terminal_path)" -s claude \
            /usr/bin/env "PATH=$(terminal_path)" /bin/bash -c 'eval "$CLAUDE_LAUNCH_CMD"'
    else
        bashio::log.info "Reusing existing tmux session 'claude'..."
    fi

    # ttyd attaches every browser connection to the persistent tmux session.
    # If Claude is running and you close the browser tab, it keeps running.
    # Reopening the tab re-attaches to the same session.
    # Bind ttyd to the loopback interface only.
    #
    # ttyd runs --writable with no credentials, so anything that can reach this
    # socket gets an unauthenticated root shell in a container holding /config
    # read-write and SUPERVISOR_TOKEN. The only legitimate consumer is the image
    # service, which proxies /terminal over localhost, and Home Assistant
    # ingress terminates on the image service port instead. Nothing outside the
    # container needs to reach this port.
    exec ttyd \
        --port "${port}" \
        --interface 127.0.0.1 \
        --writable \
        --ping-interval 30 \
        --client-option reconnect=5 \
        "${TMUX_WRAPPER_PATH:-/usr/local/bin/tmux-claude}"
}

# Run health check
run_health_check() {
    if [ -f "/opt/scripts/health-check.sh" ]; then
        bashio::log.info "Running system health check..."
        chmod +x /opt/scripts/health-check.sh
        /opt/scripts/health-check.sh || bashio::log.warning "Some health checks failed but continuing..."
    fi
}

# Main execution
main() {
    # A restart in the same container asks the Supervisor again (read_option).
    rm -f "$OPTION_READ_GAVE_UP"
    bashio::log.info "Initializing Claude Workbench app..."

    init_environment
    install_tools
    move_stale_persisted_libs
    prune_uploaded_images
    init_auto_continue
    # Serve the panel before the slow, network-bound steps below - the health
    # check's network probes included (up to three 15 s curls when offline);
    # until ttyd starts last, the terminal frame shows a start page
    # (image-service/server.js) (owine's fork, PR #380; tests/test-startup-order.sh).
    start_image_service

    setup_tmux
    setup_persistent_claude

    # Diagnostics (especially helpful for VirtualBox issues); they only log.
    # After setup_persistent_claude, so `claude --version` tests the binary
    # the session and claude-doctor use (tests/test-startup-order.sh).
    run_health_check

    setup_session_picker
    migrate_python_venv
    setup_persistent_packages
    check_persisted_alpine_release
    detect_app_migration
    # After detect_app_migration: they leave ~/.claude alone while a takeover
    # offer is open (R1) or the check could not decide (n33).
    setup_ha_plugin
    setup_statusline
    start_web_terminal
}

# Execute main function
if [ "${CLAUDE_RUN_SH_SKIP_MAIN:-false}" != "true" ]; then
    main "$@"
fi
