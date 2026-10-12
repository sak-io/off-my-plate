#!/usr/bin/env bash
# test-assert-tests-ran.sh: proves scripts/assert-tests-ran.sh accepts real Swift Testing
# summaries (Linux 6.2, macOS SF Symbol + ANSI, 6.0 singular) and rejects zero tests,
# XCTest-only output, a too-high minimum and a missing log.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assert="$(cd "$here/.." && pwd)/assert-tests-ran.sh"
logs="$here/fixtures/test-logs"
passed=0
failed=0

check() { # expected-exit label args...
  local expected="$1" label="$2" status output
  shift 2
  set +e
  output="$("$assert" "$@" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq "$expected" ]]; then
    echo "  ok   $label"
    passed=$((passed + 1))
  else
    echo "  FAIL $label: expected exit $expected, got $status" >&2
    printf '%s\n' "$output" | sed 's/^/         /' >&2
    failed=$((failed + 1))
  fi
}

echo "assert-tests-ran.sh"
check 0 "Linux Swift 6.2 log with XCTest 'Executed 0 tests' passes" "$logs/pass-linux-swift62.log"
check 0 "macOS log with SF Symbol and ANSI colours passes" "$logs/pass-macos-sfsymbol-ansi.log"
check 0 "Swift 6.0 singular 'Test run with 1 test' passes" "$logs/pass-swift60-singular.log"
check 0 "minimum equal to the count passes" "$logs/pass-linux-swift62.log" 2
check 1 "minimum above the count fails" "$logs/pass-linux-swift62.log" 3
check 1 "zero Swift Testing tests fails" "$logs/fail-zero-tests.log"
check 1 "XCTest-only output (no Swift Testing summary) fails" "$logs/fail-xctest-only.log"
check 2 "missing log is a usage error" "$logs/does-not-exist.log"
check 2 "non-numeric minimum is a usage error" "$logs/pass-linux-swift62.log" two

echo "test-assert-tests-ran: $passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
