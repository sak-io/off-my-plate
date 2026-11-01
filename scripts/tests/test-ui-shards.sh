#!/usr/bin/env bash
# Self-test for scripts/ui-shard-classes.sh: the real repo is covered, and a new unlisted class is caught.
set -euo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "test-ui-shards FAIL: $*" >&2; exit 1; }
"$here/scripts/ui-shard-classes.sh" --check >/dev/null || fail "the real repo is not fully covered"
[[ -n "$("$here/scripts/ui-shard-classes.sh" 1)" ]] || fail "shard 1 empty"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/platforms/ios/App/OffMyPlateUITests"
for c in SettingsUITests PantryUITests ImportUITests OnboardingUITests AppShellUITests ShoppingUITests PlanUITests OfflineAndPerformanceUITests; do
  printf 'final class %s: XCTestCase {}\n' "$c" > "$tmp/platforms/ios/App/OffMyPlateUITests/$c.swift"
done
UI_SHARD_ROOT="$tmp" "$here/scripts/ui-shard-classes.sh" --check >/dev/null || fail "complete fixture rejected"
printf 'final class BrandNewUITests: XCTestCase {}\n' > "$tmp/platforms/ios/App/OffMyPlateUITests/BrandNew.swift"
if UI_SHARD_ROOT="$tmp" "$here/scripts/ui-shard-classes.sh" --check >/dev/null 2>&1; then fail "an unlisted class was not caught"; fi
rm "$tmp/platforms/ios/App/OffMyPlateUITests/BrandNew.swift" "$tmp/platforms/ios/App/OffMyPlateUITests/PlanUITests.swift"
if UI_SHARD_ROOT="$tmp" "$here/scripts/ui-shard-classes.sh" --check >/dev/null 2>&1; then fail "a listed-but-missing class was not caught"; fi
echo "test-ui-shards: OK"
