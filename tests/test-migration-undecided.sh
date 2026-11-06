#!/usr/bin/env bash
# n33: until the takeover check has decided whether an older app is there to
# take Claude data from, the status line and the Home Assistant plugin leave
# ~/.claude alone. run.sh creates the marker before `cli.js detect`, which
# removes it once it has decided; a failed or killed check leaves it, and
# migration_offer_pending counts it like an open offer. Otherwise files they
# wrote would keep the old app's settings.json, plugin lists and .claude.json
# out of a takeover offered on a later start (the takeover never replaces
# files that exist).
set -euo pipefail
# Like bashio 0.19.0, which run.sh runs under.
shopt -s inherit_errexit

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
    echo "FAIL (migration undecided): $*" >&2
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
source "$repo_root/claude-workbench/run.sh"

export APP_MIGRATION_OFFER="$tmp_dir/migration/offer.json"
export APP_MIGRATION_UNDECIDED="$tmp_dir/migration/undecided"

# 1. Neither file: nothing pending. Either file: pending.
migration_offer_pending && fail "pending without offer or marker"
mkdir -p "$tmp_dir/migration"
: > "$APP_MIGRATION_UNDECIDED"
migration_offer_pending || fail "the undecided marker does not count as pending"
rm -f "$APP_MIGRATION_UNDECIDED"
printf '{}\n' > "$APP_MIGRATION_OFFER"
migration_offer_pending || fail "an open offer does not count as pending"
rm -rf "$tmp_dir/migration"

# A cli.js stand-in: records whether the marker was there when it ran, then
# behaves like a decision (removes it) or a failure (leaves it).
fake_cli="$tmp_dir/cli.js"
seen="$tmp_dir/seen"
cat > "$fake_cli" << 'JS'
const fs = require('fs');
const [marker, seen, mode] = [process.env.APP_MIGRATION_UNDECIDED, process.env.SEEN, process.env.MODE];
fs.writeFileSync(seen, fs.existsSync(marker) ? 'there' : 'missing');
if (mode === 'decide') { fs.rmSync(marker, { force: true }); console.log('App migration: nothing to offer (no-old-app)'); }
else console.log('WARNING: App migration: detection failed, skipping (test)');
JS
export APP_MIGRATION_CLI="$fake_cli" SEEN="$seen"
if command -v cygpath > /dev/null 2>&1; then
    # node on Windows reads paths in its own form
    APP_MIGRATION_UNDECIDED=$(cygpath -m "$APP_MIGRATION_UNDECIDED")
    SEEN=$(cygpath -m "$seen")
    export APP_MIGRATION_UNDECIDED SEEN
fi

# 2. The marker exists while the check runs; a decision removes it.
MODE=decide detect_app_migration || fail "detect_app_migration failed"
[ "$(cat "$seen")" = there ] || fail "the marker was not created before the check ran"
[ ! -e "$tmp_dir/migration/undecided" ] || fail "the marker survived a decision"
migration_offer_pending && fail "pending after a decision without an offer"
grep -q 'nothing to offer' "$log" || fail "the check's line was not logged: $(cat "$log")"

# 3. A failed check leaves the marker: pending, warning logged.
: > "$log"
MODE=fail detect_app_migration || fail "a failed check must not fail the start"
[ -e "$tmp_dir/migration/undecided" ] || fail "a failed check removed the marker"
migration_offer_pending || fail "not pending after a failed check"
grep -q '^warning|App migration: detection failed' "$log" || fail "the failure was not logged as a warning: $(cat "$log")"
rm -rf "$tmp_dir/migration"

# 4. The marker cannot be created (/data/migration is a file): a warning, the
#    start goes on and the check still runs.
: > "$tmp_dir/migration"
: > "$log"
rm -f "$seen"
MODE=decide detect_app_migration || fail "an unwritable migration folder must not fail the start"
grep -q '^warning|App migration: could not create' "$log" || fail "the unwritable marker was not reported: $(cat "$log")"
[ -e "$seen" ] || fail "the check did not run after the marker could not be created"
rm -f "$tmp_dir/migration"

# 5. Without cli.js nothing is created (no check, nothing to wait for).
APP_MIGRATION_CLI="$tmp_dir/missing.js" detect_app_migration
[ ! -e "$tmp_dir/migration/undecided" ] || fail "a marker was created although there is no check"

echo "Migration undecided tests passed"
