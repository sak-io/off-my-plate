#!/usr/bin/env bash
# test-release-readiness.sh: proves scripts/release-readiness.sh fails on a draft recipe, on an
# unsigned restriction record and on the committed (still unsigned) content, and passes on a
# fully signed-off fixture.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$(cd "$here/.." && pwd)/release-readiness.sh"
fx="$here/fixtures/release-readiness"
passed=0; failed=0

check() { # expected-exit label expected-text args...
  local expected="$1" label="$2" text="$3" status output
  shift 3
  set +e; output="$("$script" "$@" 2>&1)"; status=$?; set -e
  if [[ "$status" -ne "$expected" ]]; then
    echo "  FAIL $label: expected exit $expected, got $status" >&2
    printf '%s\n' "$output" | sed 's/^/         /' >&2; failed=$((failed + 1))
  elif [[ -n "$text" ]] && ! grep -qF -- "$text" <<<"$output"; then
    echo "  FAIL $label: output does not mention '$text'" >&2
    printf '%s\n' "$output" | sed 's/^/         /' >&2; failed=$((failed + 1))
  else
    echo "  ok   $label"; passed=$((passed + 1))
  fi
}

echo "release-readiness.sh"
check 0 "signed-off fixture passes" "OK" "$fx/signed-sheet.md" "$fx/signed-record.md"
check 1 "a draft recipe fails (G1)" "not signed off (G1)" "$fx/draft-sheet.md" "$fx/signed-record.md"
check 1 "an unsigned restriction record fails (R4/G4)" "not signed off in" "$fx/signed-sheet.md" "$fx/unsigned-record.md"
check 1 "month 99 is rejected" "not signed off in" "$fx/signed-sheet.md" "$fx/baddate-record.md"
check 1 "Feb 30 is rejected" "not signed off in" "$fx/signed-sheet.md" "$fx/feb30-record.md"
check 0 "a leap day is accepted" "OK" "$fx/signed-sheet.md" "$fx/leap-record.md"
check 1 "App Store mode needs the G4 reviews" "G4, App Store" --app-store "$fx/signed-sheet.md" "$fx/signed-record.md"
check 0 "App Store mode passes when all signed" "OK" --app-store "$fx/signed-sheet.md" "$fx/appstore-record.md"
check 1 "the committed content is not ready yet" "NOT READY"
check 2 "a missing file is a usage error" "not found" "$fx/nope.md" "$fx/signed-record.md"
echo "test-release-readiness: $passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
