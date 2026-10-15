#!/usr/bin/env bash
# assert-xcresult-tests-ran.sh: fail when an `xcodebuild test` result bundle shows that no
# test ran, or that any test failed. The XCTest/XCUITest counterpart of assert-tests-ran.sh:
# a green `xcodebuild test` with zero tests (a test target dropped from the scheme, a
# filter matching nothing) must not count as a pass.
#
# Reads `xcrun xcresulttool get test-results summary --path BUNDLE` (Xcode 16 and later),
# a JSON object with totalTestCount, passedTests, failedTests, skippedTests and result.
#
# Usage: scripts/assert-xcresult-tests-ran.sh XCRESULT_BUNDLE [MIN_PASSED]  (default 1)
# Exit:  0 when passedTests >= MIN_PASSED and failedTests == 0, 1 otherwise, 2 usage error.
set -euo pipefail

bundle="${1:-}"
min="${2:-1}"
if [[ -z "$bundle" || ! -e "$bundle" ]]; then
  echo "assert-xcresult-tests-ran: usage: $0 XCRESULT_BUNDLE [MIN_PASSED] (bundle '$bundle' not found)" >&2
  exit 2
fi
if ! [[ "$min" =~ ^[0-9]+$ ]]; then
  echo "assert-xcresult-tests-ran: MIN_PASSED must be a non-negative integer, got '$min'" >&2
  exit 2
fi

summary="$(mktemp)"
trap 'rm -f "$summary"' EXIT
if ! xcrun xcresulttool get test-results summary --path "$bundle" > "$summary"; then
  echo "assert-xcresult-tests-ran: FAILED: xcresulttool could not read '$bundle'" >&2
  exit 1
fi

python3 -I - "$summary" "$min" "$bundle" <<'PY'
import json
import sys

path, minimum, bundle = sys.argv[1], int(sys.argv[2]), sys.argv[3]
try:
    with open(path, encoding="utf-8") as handle:
        summary = json.load(handle)
    total = int(summary["totalTestCount"])
    passed = int(summary["passedTests"])
    failed = int(summary["failedTests"])
    skipped = int(summary.get("skippedTests", 0))
except (OSError, ValueError, KeyError, TypeError) as error:
    print("assert-xcresult-tests-ran: FAILED: unreadable test summary for %s: %s" % (bundle, error),
          file=sys.stderr)
    sys.exit(1)

counts = "%d total, %d passed, %d failed, %d skipped" % (total, passed, failed, skipped)
if failed > 0:
    print("assert-xcresult-tests-ran: FAILED: %s (%s)" % (counts, bundle), file=sys.stderr)
    sys.exit(1)
if passed < minimum:
    print("assert-xcresult-tests-ran: FAILED: %s; expected at least %d passed (%s)"
          % (counts, minimum, bundle), file=sys.stderr)
    sys.exit(1)
print("assert-xcresult-tests-ran: OK: %s (minimum %d passed)" % (counts, minimum))
PY
