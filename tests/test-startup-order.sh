#!/usr/bin/env bash
set -euo pipefail

# The image service is the ingress entry point. It used to start inside
# start_web_terminal, after Claude Code's update and the package installs, so
# Home Assistant showed a bare 502 for as long as those took (23 s on a real
# install, minutes on a slow link). It now starts right after the environment
# and the required tools are in place.

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
run_sh="$repo_root/claude-workbench/run.sh"

fail() {
    echo "FAIL (startup order): $*" >&2
    exit 1
}

main_body=$(sed -n '/^main() {/,/^}/p' "$run_sh")
line_of() {
    printf '%s\n' "$main_body" | grep -nx "    $1" | cut -d: -f1
}

for step in run_health_check install_tools init_auto_continue start_image_service setup_persistent_claude \
        setup_persistent_packages start_web_terminal; do
    [ -n "$(line_of "$step")" ] || fail "main() does not call $step"
done

[ "$(line_of install_tools)" -lt "$(line_of start_image_service)" ] || \
    fail "the image service needs curl from install_tools for its readiness check"
[ "$(line_of init_auto_continue)" -lt "$(line_of start_image_service)" ] || \
    fail "init_auto_continue must write the switch before the image service reads it"
[ "$(line_of start_image_service)" -lt "$(line_of setup_persistent_claude)" ] || \
    fail "the image service must start before Claude Code's update"
[ "$(line_of start_image_service)" -lt "$(line_of setup_persistent_packages)" ] || \
    fail "the image service must start before the package installs"
# The health check's network probes run up to three 15 s curls; offline, the
# panel would stay a bare 502 for that long if they ran first.
[ "$(line_of start_image_service)" -lt "$(line_of run_health_check)" ] || \
    fail "the image service must start before the health check's network probes"
# The health check runs `claude --version`; before setup_persistent_claude it
# would test a different binary than the session (and claude-doctor) uses.
[ "$(line_of setup_persistent_claude)" -lt "$(line_of run_health_check)" ] || \
    fail "the health check must run after setup_persistent_claude, on the Claude the session uses"

# Alpine release change: stale library copies leave LD_LIBRARY_PATH before
# node (the image service) starts; the warning about the rest comes after the
# package installs, which refresh the copies of the configured packages.
for step in init_environment move_stale_persisted_libs check_persisted_alpine_release; do
    [ -n "$(line_of "$step")" ] || fail "main() does not call $step"
done
[ "$(line_of init_environment)" -lt "$(line_of move_stale_persisted_libs)" ] || \
    fail "move_stale_persisted_libs needs the environment from init_environment"
[ "$(line_of move_stale_persisted_libs)" -lt "$(line_of start_image_service)" ] || \
    fail "stale library copies must leave LD_LIBRARY_PATH before node starts"
[ "$(line_of setup_persistent_packages)" -lt "$(line_of check_persisted_alpine_release)" ] || \
    fail "check_persisted_alpine_release must run after the package installs"
[ "$(line_of check_persisted_alpine_release)" -lt "$(line_of start_web_terminal)" ] || \
    fail "check_persisted_alpine_release must run before start_web_terminal (exec)"

# The venv rebuild needs the network (pip), so the panel comes first; the
# options' pip packages must land in the rebuilt venv, not the old one.
[ -n "$(line_of migrate_python_venv)" ] || fail "main() does not call migrate_python_venv"
[ "$(line_of start_image_service)" -lt "$(line_of migrate_python_venv)" ] || \
    fail "the image service must start before the venv rebuild"
[ "$(line_of migrate_python_venv)" -lt "$(line_of setup_persistent_packages)" ] || \
    fail "the venv must be rebuilt before the options' pip packages are installed"

# The Home Assistant plugin writes to ~/.claude. The takeover from Claude
# Terminal Pro copies the old ~/.claude without replacing existing files, so
# the plugin step must know whether an offer is open (detect_app_migration),
# and it runs `claude`, which setup_persistent_claude may replace (p19, R1).
[ -n "$(line_of setup_ha_plugin)" ] || fail "main() does not call setup_ha_plugin"
[ -n "$(line_of detect_app_migration)" ] || fail "main() does not call detect_app_migration"
[ "$(line_of detect_app_migration)" -lt "$(line_of setup_ha_plugin)" ] || \
    fail "setup_ha_plugin must run after detect_app_migration"
[ "$(line_of setup_persistent_claude)" -lt "$(line_of setup_ha_plugin)" ] || \
    fail "setup_ha_plugin must run after setup_persistent_claude"
[ "$(line_of setup_ha_plugin)" -lt "$(line_of start_web_terminal)" ] || \
    fail "setup_ha_plugin must run before start_web_terminal (exec)"
# The status line writes ~/.claude/settings.json too (R1), after the plugin,
# whose install also writes there.
[ -n "$(line_of setup_statusline)" ] || fail "main() does not call setup_statusline"
[ "$(line_of setup_ha_plugin)" -lt "$(line_of setup_statusline)" ] || \
    fail "setup_statusline must run after setup_ha_plugin (and so after detect_app_migration)"
[ "$(line_of setup_statusline)" -lt "$(line_of start_web_terminal)" ] || \
    fail "setup_statusline must run before start_web_terminal (exec)"

# grep without -q: an early exit would SIGPIPE sed, and under pipefail a
# found line would read as "not there".
if sed -n '/^start_web_terminal() {/,/^}/p' "$run_sh" | grep 'start_image_service' > /dev/null; then
    fail "start_web_terminal still starts the image service"
fi

echo "Startup order suite passed"
