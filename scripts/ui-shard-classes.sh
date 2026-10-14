#!/usr/bin/env bash
# ui-shard-classes.sh: which XCUITest classes a CI shard runs (apple-macos.yml, job ui-test).
#
# Usage:  scripts/ui-shard-classes.sh <1|2|3>   print the classes of that shard, one per line
#         scripts/ui-shard-classes.sh --check   fail unless EVERY test class under
#                                               App/OffMyPlateUITests is in exactly one shard
#
# The shards are balanced by measured run time (batch 4: Settings ~7 min, the rest ~4-9 min).
# A test class missing here would silently never run in CI, hence --check (also run by
# scripts/tests/test-ui-shards.sh in the Linux lint step).
set -euo pipefail
root="${UI_SHARD_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

shard1="SettingsUITests"
shard2="PantryUITests ImportUITests OnboardingUITests AppShellUITests"
shard3="ShoppingUITests PlanUITests OfflineAndPerformanceUITests"

case "${1:-}" in
  1) printf '%s\n' $shard1 ;;
  2) printf '%s\n' $shard2 ;;
  3) printf '%s\n' $shard3 ;;
  --check)
    declared="$(printf '%s\n' $shard1 $shard2 $shard3 | sort)"
    dups="$(printf '%s\n' "$declared" | uniq -d)"
    found="$(grep -rhoE '^(final )?class [A-Za-z0-9_]+: XCTestCase' "$root/App/OffMyPlateUITests" \
      | sed -E 's/^(final )?class ([A-Za-z0-9_]+):.*/\2/' | sort -u)"
    status=0
    if [[ -n "$dups" ]]; then echo "ui-shard-classes: listed in more than one shard: $dups" >&2; status=1; fi
    missing="$(comm -13 <(printf '%s\n' "$declared" | sort -u) <(printf '%s\n' "$found"))"
    extra="$(comm -23 <(printf '%s\n' "$declared" | sort -u) <(printf '%s\n' "$found"))"
    if [[ -n "$missing" ]]; then echo "ui-shard-classes: test classes in NO shard (they would never run): $missing" >&2; status=1; fi
    if [[ -n "$extra" ]]; then echo "ui-shard-classes: shard lists classes that do not exist: $extra" >&2; status=1; fi
    [[ $status -eq 0 ]] && echo "ui-shard-classes: OK ($(printf '%s\n' "$found" | wc -l | tr -d ' ') classes in 3 shards)"
    exit $status ;;
  *) echo "usage: $0 <1|2|3|--check>" >&2; exit 2 ;;
esac
