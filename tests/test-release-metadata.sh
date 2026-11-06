#!/usr/bin/env bash
set -euo pipefail

# Enforces the release rule stated in CLAUDE.md: every change ships with a
# version bump and a matching changelog entry. config.yaml and CHANGELOG.md
# have to agree, and nothing checked this before, so they drifted silently.

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
addon_dir="$repo_root/claude-workbench"

fail() {
    echo "FAIL (release metadata): $*" >&2
    exit 1
}

config_version=$(sed -n 's/^version: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$addon_dir/config.yaml")
[ -n "$config_version" ] || fail "could not read version from config.yaml"

case "$config_version" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) fail "config.yaml version '$config_version' is not semver" ;;
esac

# build.yaml is deprecated: the Supervisor warns on every build and will stop
# reading it. The Dockerfile carries the base image and labels, the version
# lives only in config.yaml (the Supervisor labels the image with it).
[ ! -e "$addon_dir/build.yaml" ] || \
    fail "claude-workbench/build.yaml exists; build parameters belong in the Dockerfile"

dockerfile="$addon_dir/Dockerfile"
# Dockerfile keywords are case-insensitive; a second stage would make the final
# image something other than the pinned base.
from_lines=$(grep -iE '^[[:space:]]*FROM[[:space:]]' "$dockerfile" || true)
[ "$(printf '%s\n' "$from_lines" | grep -c .)" -eq 1 ] || \
    fail "Dockerfile must have exactly one FROM; found: $(printf '%s' "$from_lines" | tr '\n' '|')"
printf '%s\n' "$from_lines" | grep -qE '^FROM ghcr\.io/home-assistant/base:[0-9]+\.[0-9]+' || \
    fail "Dockerfile must start from a tagged ghcr.io/home-assistant/base image"
# Alpine 3.21 is out of security support since 2026-11-01: never fall back
# below 3.24. The docs that name the base must follow the Dockerfile.
base_tag=$(printf '%s\n' "$from_lines" | sed -nE 's/^FROM ghcr\.io\/home-assistant\/base:([0-9]+\.[0-9]+).*/\1/p')
[ "$(printf '%s\n' 3.24 "$base_tag" | sort -V | head -n 1)" = "3.24" ] || \
    fail "Dockerfile base $base_tag is older than Alpine 3.24 (3.21 is end of life)"
grep -q "badge/base-Alpine%20${base_tag}-" "$repo_root/README.md" || \
    fail "README.md base image badge does not show Alpine $base_tag"
grep -qF "Alpine Linux base (${base_tag})" "$addon_dir/README.md" || \
    fail "claude-workbench/README.md does not name Alpine $base_tag as its base"
grep -qF "base:${base_tag}" "$repo_root/CLAUDE.md" || \
    fail "CLAUDE.md does not name ghcr.io/home-assistant/base:$base_tag"

# Without build.yaml, older Supervisor versions still pass BUILD_FROM
# ({arch}-base:latest, the newest Alpine). An ARG would let that replace the
# pinned base without anyone noticing.
if grep -niE '^[[:space:]]*ARG[[:space:]]+BUILD_FROM' "$dockerfile"; then
    fail "Dockerfile declares ARG BUILD_FROM; a Supervisor-supplied value would swap the base image"
fi

# The multi-arch base image covers amd64 and arm64 only, and Home Assistant
# ended 32-bit support with 2025.12 (no more app updates there). The list must
# be in block form ("  - amd64"): a flow list would slip past this check, so an
# empty result fails too.
arches=$(sed -n '/^arch:/,/^[a-z]/{s/^  - //p;}' "$addon_dir/config.yaml")
[ -n "$arches" ] || \
    fail "config.yaml has no arch list in block form (\"  - amd64\")"
while IFS= read -r arch; do
    case "$arch" in
        amd64|aarch64) ;;
        *) fail "config.yaml declares arch '$arch'; only amd64 and aarch64 have a base image" ;;
    esac
done <<< "$arches"

if grep -nE 'armv7|armhf|armv6|i386|1\.0\.128' "$dockerfile"; then
    fail "Dockerfile still carries 32-bit branches"
fi

# The runtime scripts had their own 32-bit branches and pins (Claude 1.0.128,
# HA CLI 4.46.0); with only 64-bit images they are dead code at best, and the
# HA CLI pin downgraded `persist-install --ha-cli --force` on every arch.
if grep -rniE 'armv7|armv6|armhf|i386|i686|1\.0\.128|4\.46\.0' \
        "$addon_dir/run.sh" "$addon_dir/scripts"; then
    fail "run.sh or scripts/ still carry 32-bit branches or pins"
fi

grep -qx "## $config_version" "$addon_dir/CHANGELOG.md" || \
    fail "CHANGELOG.md has no '## $config_version' section for the current version"

# The newest changelog section must be the current version, so a bump cannot
# land with its notes buried under an older release.
newest=$(grep -m1 '^## ' "$addon_dir/CHANGELOG.md" | sed 's/^## //')
[ "$newest" = "$config_version" ] || \
    fail "newest CHANGELOG entry is '$newest' but config.yaml is at '$config_version'"

# The README version badge drifted before (it showed 2.2.0 while 2.2.2 shipped).
grep -q "badge/version-${config_version}-" "$repo_root/README.md" || \
    fail "README.md version badge does not show $config_version"

# Publishing a host port would bypass Home Assistant ingress authentication and
# expose ttyd's unauthenticated root shell on the LAN. Keep that closed.
if grep -qE '^\s+[0-9]+/tcp: *[0-9]+' "$addon_dir/config.yaml"; then
    fail "config.yaml publishes a host port; ttyd runs --writable with no auth, use ingress only"
fi

# auth_api only opens the Supervisor's username/password check; nothing in the
# app uses it (dropped in 3.1.3, heytcass/home-assistant-addons@3a6ee0d).
if grep -qE '^auth_api:' "$addon_dir/config.yaml"; then
    fail "config.yaml requests auth_api; the app never checks HA passwords"
fi

grep -q 'interface 127.0.0.1' "$addon_dir/run.sh" || \
    fail "ttyd must bind 127.0.0.1 only; it runs --writable with no credentials"

# Credentials live in the app's private /data (HOME=/data/home). The store page
# and the project instructions kept naming /config/claude-config/.
for doc in "$addon_dir/README.md" "$repo_root/CLAUDE.md"; do
    if grep -nE '(stored|storage|saved)[^.]*/config/claude-config|=/config/claude-config' "$doc"; then
        fail "$(basename "$doc") names /config/claude-config as where credentials live; they are in /data/home/.claude"
    fi
done

# Local builds need no build argument any more; docs and tooling that still
# pass the old one send developers to a base image the app no longer uses.
for f in "$repo_root/CLAUDE.md" "$repo_root/DEVELOPMENT.md" "$repo_root/flake.nix" \
         "$repo_root/.github/workflows/ci.yml"; do
    if grep -n 'BUILD_FROM' "$f"; then
        fail "$(basename "$f") still passes BUILD_FROM; the Dockerfile pins the base image"
    fi
done

# The developer guide set up credentials under /config/claude-config; they live
# in the app's private /data (/data/home/.claude).
if grep -n 'claude-config' "$repo_root/DEVELOPMENT.md"; then
    fail "DEVELOPMENT.md still uses /config/claude-config; credentials live in /data/home/.claude"
fi

# README keeps one sentence saying armv7 is unsupported, so only its
# architecture table is checked; DOCS.md must not mention armv7 at all.
if grep -nE '^\| `armv7`' "$repo_root/README.md"; then
    fail "README.md still lists armv7 in the architecture table"
fi
if grep -niE 'armv7' "$addon_dir/DOCS.md"; then
    fail "DOCS.md still describes armv7, which is no longer built"
fi

# Release versions come from github.com's releases/latest redirect. The REST
# API allows 60 unauthenticated requests per hour per IP; a CI image build
# failed on its 403 (run 37584251742).
for f in "$addon_dir/Dockerfile" "$addon_dir/scripts/persist-install"; do
    if grep -n 'api\.github\.com' "$f"; then
        fail "$(basename "$f") queries api.github.com; read the tag from the releases/latest redirect"
    fi
done

# The Mac clipboard monitor uploaded to <host>:8123/upload (HA Core, not the
# app) or the direct port that 2.1.0 closed; pasting into the terminal
# replaces it.
for f in mac-clipboard-monitor.py MAC_CLIPBOARD_MONITOR.md; do
    [ ! -e "$repo_root/$f" ] || fail "$f is back; it cannot reach the app since 2.1.0"
done

# Claude Workbench is an app of its own (spec 2026-10-07-claude-workbench-rename):
# own name, slug and repository, so it is not mistaken for ESJavadex's
# Claude Terminal Pro. The takeover keeps finding *_claude_terminal_pro apps.
config_field() {
    sed -n "s/^$1: *\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$addon_dir/config.yaml"
}
new_repo_url="https://github.com/Eifel-Joe/claude-workbench"
[ "$(config_field name)" = "Claude Workbench" ] || \
    fail "config.yaml name is '$(config_field name)', expected 'Claude Workbench'"
[ "$(config_field slug)" = "claude_workbench" ] || \
    fail "config.yaml slug is '$(config_field slug)', expected 'claude_workbench'"
[ "$(config_field panel_title)" = "Claude Workbench" ] || \
    fail "config.yaml panel_title is '$(config_field panel_title)', expected 'Claude Workbench'"
[ "$(config_field url)" = "$new_repo_url" ] || \
    fail "config.yaml url is '$(config_field url)', expected $new_repo_url"
grep -qx "url: $new_repo_url" "$repo_root/repository.yaml" || \
    fail "repository.yaml does not point to $new_repo_url"
grep -qx 'name: Claude Workbench for Home Assistant' "$repo_root/repository.yaml" || \
    fail "repository.yaml name is not 'Claude Workbench for Home Assistant'"
grep -q 'image.title="Home Assistant App: Claude Workbench"' "$dockerfile" || \
    fail "Dockerfile image.title label does not name Claude Workbench"
grep -q "image.source=\"$new_repo_url\"" "$dockerfile" || \
    fail "Dockerfile image.source label does not point to $new_repo_url"

# The app calls itself Claude Workbench. "Claude Terminal" stays only where the
# old app is meant ("another Claude Terminal Pro app", the takeover code).
# Case-insensitive, so an identifier like "claude-terminal:" is caught too; a
# missing path would make grep fail and the check pass without looking.
self_name_paths=("$addon_dir/run.sh" "$addon_dir/scripts" \
    "$addon_dir/image-service/server.js" "$addon_dir/image-service/public")
for p in "${self_name_paths[@]}"; do
    [ -e "$p" ] || fail "$p is missing; the self-name check would look at nothing"
done
if grep -rniE 'claude[- ]terminal' "${self_name_paths[@]}" --exclude-dir=app-migration | \
        grep -v 'Claude Terminal Pro app'; then
    fail "the app still calls itself Claude Terminal (see lines above)"
fi
grep -q '"name": "claude-workbench-image-service"' "$addon_dir/image-service/package.json" || \
    fail "image-service/package.json is not named claude-workbench-image-service"

# Icon and logo come from tools/make-logo.py (original spark plus ">_" in a
# terminal window). Home Assistant expects a 128x128 icon.
png_size() {
    od -An -tu1 -j16 -N8 "$1" | \
        awk '{print ($1*16777216+$2*65536+$3*256+$4) "x" ($5*16777216+$6*65536+$7*256+$8)}'
}
[ "$(png_size "$addon_dir/icon.png")" = "128x128" ] || \
    fail "icon.png is $(png_size "$addon_dir/icon.png"), expected 128x128 (tools/make-logo.py)"
[ "$(png_size "$addon_dir/logo.png")" = "256x256" ] || \
    fail "logo.png is $(png_size "$addon_dir/logo.png"), expected 256x256 (tools/make-logo.py)"
[ -f "$repo_root/tools/logo/claude-spark.png" ] || \
    fail "tools/logo/claude-spark.png (logo source) is missing"

# After the GitHub rename the old repository URL only works through GitHub's
# redirect; links and the "add repository" button must use the new one.
# docs/ and the changelog keep history as it was.
# git grep exits 1 for "no match" but 128 outside a repository or on a bad
# pathspec; only 1 may count as a pass.
old_url_rc=0
old_url_hits=$(git -C "$repo_root" grep -nE 'Eifel-Joe(/|%2F)claude-code-ha' -- . ':!docs' \
    ':!claude-workbench/CHANGELOG.md' ':!tests/test-release-metadata.sh') || old_url_rc=$?
if [ "$old_url_rc" -eq 0 ]; then
    printf '%s\n' "$old_url_hits"
    fail "the old repository URL Eifel-Joe/claude-code-ha is still used (see lines above)"
fi
[ "$old_url_rc" -eq 1 ] || fail "git grep for the old repository URL failed (exit $old_url_rc)"

# Home Assistant names an installed app <first 8 hex of sha1(lower-cased
# repository URL)>_<slug>. After the rename the old repository entry lists
# Claude Workbench too (GitHub redirects), as 6ef0b4d0_claude_workbench;
# installed from there, the old entry can never be removed. The switching guide
# names the right one, and it has to match the repository URL.
new_app_slug="$(printf '%s' "$new_repo_url" | tr 'A-Z' 'a-z' | sha1sum | cut -c1-8)_claude_workbench"
for doc in README.md claude-workbench/README.md claude-workbench/DOCS.md docs/release-notes-3.0.0.md; do
    grep -q "$new_app_slug" "$repo_root/$doc" || \
        fail "$doc does not tell users to install $new_app_slug"
done
# The MIT license must name its copyright holders, not the template placeholder.
if grep -n 'Your Name' "$repo_root/LICENSE"; then
    fail "LICENSE still carries the template placeholder instead of the copyright holders"
fi
grep -q 'Switching from Claude Terminal Pro' "$repo_root/README.md" || \
    fail "README.md has no 'Switching from Claude Terminal Pro' section"

# http-proxy 1.x is unmaintained and calls util._extend (DEP0060 in the app
# log); http-proxy-middleware 4 replaced it with httpxy.
# Without the leading quote a nested node_modules/<pkg>/node_modules/http-proxy
# is caught too.
if grep -n 'node_modules/http-proxy"' "$addon_dir/image-service/package-lock.json"; then
    fail "image-service still installs http-proxy (util._extend, DEP0060); use http-proxy-middleware 4"
fi
# http-proxy-middleware 4 is ESM-only: below Node 22.12 require() throws
# ERR_REQUIRE_ESM and the image service (the terminal panel) never starts;
# 22.12 still warns. Keep the declared floor at the library's own.
grep -q '"node": ">=22.15"' "$addon_dir/image-service/package.json" || \
    fail "image-service/package.json engines.node must be >=22.15 (http-proxy-middleware 4)"

# Supervisor 2023-10: "config" became "homeassistant_config" and logs a
# deprecation warning on every store reload. Without an explicit path that
# mount lands in /homeassistant, while the terminal, the docs and every user
# expect the Home Assistant configuration in /config.
if grep -nE '^\s+-\s+config(:(rw|ro))?(\s|$)' "$addon_dir/config.yaml"; then
    fail "config.yaml maps the deprecated 'config' option; use homeassistant_config with path /config"
fi
ha_map=$(grep -A2 -E '^\s+- type: homeassistant_config\s*$' "$addon_dir/config.yaml" || true)
printf '%s\n' "$ha_map" | grep -qE '^\s+read_only: false\s*$' && \
    printf '%s\n' "$ha_map" | grep -qE '^\s+path: /config\s*$' || \
    fail "config.yaml needs '- type: homeassistant_config' with read_only: false and path: /config"

# Without translations Home Assistant shows bare option names (tmux_mouse …)
# with no explanation. Every option needs a name and a description in each
# language, so a new option cannot ship unexplained. Keys come from schema:,
# which also lists options without a default.
option_keys=$(sed -n '/^schema:/,/^[a-z]/{s/^  \([A-Za-z0-9_]*\):.*/\1/p;}' "$addon_dir/config.yaml")
[ -n "$option_keys" ] || fail "could not read the option names from config.yaml"
for lang in en de; do
    tr_file="$addon_dir/translations/$lang.yaml"
    [ -f "$tr_file" ] || fail "translations/$lang.yaml is missing; Home Assistant shows bare option names without it"
    while IFS= read -r key; do
        entry=$(grep -A2 -E "^  $key:\s*$" "$tr_file" || true)
        printf '%s\n' "$entry" | grep -qE '^    name: .+' && \
            printf '%s\n' "$entry" | grep -qE '^    description: .+' || \
            fail "translations/$lang.yaml has no name and description for '$key'"
    done <<< "$option_keys"
done

# ubuntu-latest moves to the next Ubuntu release without notice (Ubuntu 26
# from 2026-10-19). Pin the runner image so a switch is a deliberate change.
if grep -n 'ubuntu-latest' "$repo_root"/.github/workflows/*.yml; then
    fail "a workflow runs on ubuntu-latest; pin the runner image (ubuntu-24.04)"
fi

# claude-doctor makes the startup health check callable from the terminal;
# nobody knows /opt/scripts/health-check.sh by heart.
grep -qE '^\s*(RUN |&& )?ln -sf /opt/scripts/health-check\.sh /usr/local/bin/claude-doctor' "$addon_dir/Dockerfile" || \
    fail "Dockerfile does not link /usr/local/bin/claude-doctor to /opt/scripts/health-check.sh"

# auto-continue switches auto-continue at runtime from the terminal.
grep -qE '^\s*(RUN |&& )?ln -sf /opt/scripts/auto-continue\.sh /usr/local/bin/auto-continue' "$addon_dir/Dockerfile" || \
    fail "Dockerfile does not link /usr/local/bin/auto-continue to /opt/scripts/auto-continue.sh"

# The old "Version 1.0.2 includes …" security section described 2025 and kept
# quiet about who can open the panel. The current one must say it.
if grep -n 'Version 1.0.2 includes' "$addon_dir/README.md"; then
    fail "README.md still carries the outdated 'Version 1.0.2' security section"
fi
grep -q 'every signed-in Home Assistant user' "$addon_dir/README.md" || \
    fail "README.md security section does not say who can open the panel"

# The Home Assistant plugin for Claude (p19): on by default (the user's choice
# for 3.6.2), pinned to a tag AND its commit, so a moved tag fails the build
# instead of shipping other code; its MIT LICENSE stays in the image copy.
grep -qE '^  home_assistant_plugin: true\s*$' "$addon_dir/config.yaml" || \
    fail "config.yaml options need 'home_assistant_plugin: true'"
grep -qE '^  home_assistant_plugin: bool\?\s*$' "$addon_dir/config.yaml" || \
    fail "config.yaml schema needs 'home_assistant_plugin: bool?'"
grep -qE '^ARG HA_PLUGINS_REF=v[0-9]+\.[0-9]+\.[0-9]+$' "$dockerfile" || \
    fail "Dockerfile does not pin the plugin release (ARG HA_PLUGINS_REF=vX.Y.Z)"
grep -qE '^ARG HA_PLUGINS_COMMIT=[0-9a-f]{40}$' "$dockerfile" || \
    fail "Dockerfile does not pin the plugin release's commit (ARG HA_PLUGINS_COMMIT=<sha>)"
grep -q 'rev-parse HEAD' "$dockerfile" || \
    fail "Dockerfile does not check the cloned plugin against HA_PLUGINS_COMMIT"
if grep -E 'rm -rf .*LICENSE' "$dockerfile"; then
    fail "Dockerfile removes the plugin's LICENSE; MIT requires the notice to ship"
fi

# The Home Assistant status line (p18): on by default with the default layout
# (the user's choice for 3.6.2), a list of pieces like upstream's option.
grep -qE '^  statusline: \[\]\s*$' "$addon_dir/config.yaml" || \
    fail "config.yaml options need 'statusline: []'"
sed -n '/^schema:/,/^[a-z]/p' "$addon_dir/config.yaml" | grep -A1 -E '^  statusline:\s*$' | \
    grep -qE '^    - str\?\s*$' || fail "config.yaml schema needs 'statusline:' as a list of 'str?'"

echo "Release metadata suite passed (version $config_version)"
