#!/usr/bin/env bash
# test-select-simulator.sh: hermetic tests for scripts/select-simulator.sh, fed with
# recorded `xcrun simctl list -j devices available` fixtures (SIMCTL_JSON), so they run on
# Linux without Xcode.
#
# Needs python3. Where it is missing (the swift:6.2-noble image may not have it) the test
# reports a skip and exits 0, unless OMP_REQUIRE_PYTHON=1: the macOS CI job sets that and
# runs this test before it relies on the script.
#
# Usage: scripts/tests/test-select-simulator.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$(cd "$here/.." && pwd)/select-simulator.sh"
fixtures="$here/fixtures/simctl"

if ! command -v python3 >/dev/null 2>&1; then
  if [[ "${OMP_REQUIRE_PYTHON:-0}" == 1 ]]; then
    echo "test-select-simulator: FAILED: python3 is required (OMP_REQUIRE_PYTHON=1)" >&2
    exit 1
  fi
  echo "test-select-simulator: skipped (no python3 on this machine)"
  exit 0
fi

passed=0
failed=0
pass() { echo "  ok   $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL $1" >&2; failed=$((failed + 1)); }

# expect <label> <fixture> <expected exit> <expected stdout> <expected stderr substring> -- args...
expect() {
  local label="$1" fixture="$2" want_status="$3" want_out="$4" want_err="$5" out err status
  shift 6
  err="$(mktemp)"
  set +e
  out="$(SIMCTL_JSON="$fixture" "$script" "$@" 2>"$err")"
  status=$?
  set -e
  if [[ "$status" -ne "$want_status" ]]; then
    fail "$label: expected exit $want_status, got $status"; sed 's/^/         /' "$err" >&2
  elif [[ "$out" != "$want_out" ]]; then
    fail "$label: expected stdout '$want_out', got '$out'"
  elif [[ -n "$want_err" ]] && ! grep -qF -- "$want_err" "$err"; then
    fail "$label: stderr does not mention '$want_err'"; sed 's/^/         /' "$err" >&2
  else
    pass "$label"
  fi
  rm -f "$err"
}

echo "select-simulator.sh"
expect "preferred iPhone on the newest iOS runtime that has it" \
  "$fixtures/runner.json" 0 "IOS262-IPHONE16" "iPhone 16 (iOS 26.2) IOS262-IPHONE16" -- iphone "iPhone 16"
expect "preferred iPad on an older runtime beats a fallback on the newest" \
  "$fixtures/runner.json" 0 "IOS186-IPADA16" "iPad (A16) (iOS 18.6)" -- ipad "iPad (A16)"
expect "missing preferred device falls back to the newest runtime, first by name, with a warning" \
  "$fixtures/runner.json" 0 "IOS262-IPADAIR" '::warning::select-simulator: no available "iPad mini (A17 Pro)"' -- ipad "iPad mini (A17 Pro)"
expect "MIN_IOS excludes older runtimes" \
  "$fixtures/runner.json" 0 "IOS262-IPHONE16" "" -- iphone "iPhone 16" 26
expect "non-iOS runtimes are ignored" \
  "$fixtures/runner.json" 1 "" "no available iPhone simulator on iOS 27" -- iphone "iPhone 16" 27
expect "unavailable devices are never chosen" \
  "$fixtures/unavailable.json" 0 "IOS262-IPHONE16E" "falling back to iPhone 16e" -- iphone "iPhone 16"
expect "only runtimes below the minimum: no simulator" \
  "$fixtures/old-only.json" 1 "" "on iOS 18 or later" -- iphone "iPhone 16"
expect "unreadable device list is an error" \
  "$fixtures/garbage.json" 2 "" "cannot read the simulator list" -- iphone "iPhone 16"
expect "missing device list file is an error" \
  "$fixtures/does-not-exist.json" 2 "" "not found" -- iphone "iPhone 16"
expect "unknown family is a usage error" \
  "$fixtures/runner.json" 2 "" "usage" -- watch "Apple Watch"
expect "missing preferred name is a usage error" \
  "$fixtures/runner.json" 2 "" "usage" -- iphone
expect "non-numeric MIN_IOS is a usage error" \
  "$fixtures/runner.json" 2 "" "usage" -- iphone "iPhone 16" eighteen

echo "test-select-simulator: $passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
