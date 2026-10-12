#!/usr/bin/env bash
# assert-tests-ran.sh: fail when a `swift test` log shows that no Swift Testing test ran.
#
# A green `swift test` with zero tests (a test target not picked up, a filter matching
# nothing, a suite accidentally compiled out) must not count as a pass. Core uses Swift
# Testing only (ADR 0005), so this reads Swift Testing's run summary, for example:
#   ✔ Test run with 2 tests in 1 suite passed after 0.002 seconds.   (Swift 6.1+)
#   ✔ Test run with 1 test passed after 0.001 seconds.               (Swift 6.0)
# The leading symbol differs by platform (an SF Symbol on macOS) and ANSI colours may be
# present, so only the text "Test run with N test(s)" is matched. XCTest's own summary
# ("Executed 0 tests, with 0 failures ...", printed when a target has no XCTest cases)
# is deliberately ignored, so it can neither fail nor satisfy this check.
#
# Usage: scripts/assert-tests-ran.sh LOG_FILE [MIN_TESTS]   (MIN_TESTS default: 1)
# Exit:  0 when the summed Swift Testing count >= MIN_TESTS, 1 otherwise, 2 usage error.
set -euo pipefail

log="${1:-}"
min="${2:-1}"
if [[ -z "$log" || ! -f "$log" ]]; then
  echo "assert-tests-ran: usage: $0 LOG_FILE [MIN_TESTS] (log file '$log' not found)" >&2
  exit 2
fi
if ! [[ "$min" =~ ^[0-9]+$ ]]; then
  echo "assert-tests-ran: MIN_TESTS must be a non-negative integer, got '$min'" >&2
  exit 2
fi

esc=$'\033'
counts="$(sed -E "s/${esc}\\[[0-9;]*[A-Za-z]//g" "$log" \
  | grep -oE 'Test run with [0-9]+ tests?' \
  | grep -oE '[0-9]+' || true)"

if [[ -z "$counts" ]]; then
  echo "assert-tests-ran: FAILED: no Swift Testing run summary ('Test run with N tests') in $log" >&2
  exit 1
fi

total=0
runs=0
for n in $counts; do
  total=$((total + n))
  runs=$((runs + 1))
done

if [[ "$total" -lt "$min" ]]; then
  echo "assert-tests-ran: FAILED: $total Swift Testing test(s) ran in $runs run(s); expected at least $min" >&2
  exit 1
fi
echo "assert-tests-ran: OK: $total Swift Testing test(s) ran in $runs run(s) (minimum $min)"
