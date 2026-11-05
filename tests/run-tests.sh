#!/usr/bin/env bash
set -euo pipefail

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$tests_dir/.." && pwd)

"$tests_dir/test-release-metadata.sh"
"$tests_dir/test-production-run.sh"
"$tests_dir/test-startup-timeouts.sh"
node "$tests_dir/test-terminal-clipboard.js"
node --test "$tests_dir/test-workbench-ui.js"
node --test "$tests_dir/test-app-migration.js"
node --test "$tests_dir/test-auto-continue.js"
"$tests_dir/test-startup-hardening.sh"
"$tests_dir/test-persist-install.sh"
"$tests_dir/test-alpine-migration.sh"
"$tests_dir/test-cpu-check.sh"
"$tests_dir/test-npm-cache.sh"
"$tests_dir/test-health-check.sh"
"$tests_dir/test-startup-order.sh"
"$tests_dir/test-claude-assets.sh"
"$tests_dir/test-auth-helper.sh"
"$tests_dir/test-image-retention.sh"
"$tests_dir/test-tmux-config.sh"
"$tests_dir/test-auto-continue-cmd.sh"

# The image service is the ingress entry point. Its suite needs node and the
# service's dependencies; skip loudly rather than pretend it ran.
service_dir="$repo_root/claude-workbench/image-service"
if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: node not available, image service suite not run" >&2
elif [ ! -d "$service_dir/node_modules" ]; then
    echo "SKIP: run 'npm ci' in $service_dir to enable the image service suite" >&2
else
    node --test "$tests_dir/test-image-service.js"
fi

echo "All regression suites passed"
