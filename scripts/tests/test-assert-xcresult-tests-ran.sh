#!/usr/bin/env bash
# test-assert-xcresult-tests-ran.sh: hermetic tests for scripts/assert-xcresult-tests-ran.sh.
# A fake `xcrun` first on PATH prints a recorded `xcresulttool get test-results summary`
# JSON (FAKE_SUMMARY) or fails (FAKE_XCRUN=fail), so this runs on Linux without Xcode.
#
# Needs python3: skipped (exit 0) when it is missing, unless OMP_REQUIRE_PYTHON=1 (set by
# the macOS CI job, which relies on the script).
#
# Usage: scripts/tests/test-assert-xcresult-tests-ran.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$(cd "$here/.." && pwd)/assert-xcresult-tests-ran.sh"
fixtures="$here/fixtures/xcresult"

if ! command -v python3 >/dev/null 2>&1; then
  if [[ "${OMP_REQUIRE_PYTHON:-0}" == 1 ]]; then
    echo "test-assert-xcresult-tests-ran: FAILED: python3 is required (OMP_REQUIRE_PYTHON=1)" >&2
    exit 1
  fi
  echo "test-assert-xcresult-tests-ran: skipped (no python3 on this machine)"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/Test.xcresult"
cat > "$work/bin/xcrun" <<'FAKE'
#!/usr/bin/env bash
# fake xcrun: only `xcresulttool get test-results summary --path X` is supported.
[[ "${FAKE_XCRUN:-ok}" == fail ]] && { echo "xcresulttool: error: invalid bundle" >&2; exit 1; }
[[ "$1 $2 $3 $4 $5" == "xcresulttool get test-results summary --path" ]] || { echo "fake xcrun: unexpected args: $*" >&2; exit 64; }
cat "$FAKE_SUMMARY"
FAKE
chmod +x "$work/bin/xcrun"

passed=0
failed=0
pass() { echo "  ok   $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL $1" >&2; failed=$((failed + 1)); }

# expect <label> <summary fixture> <expected exit> <expected output substring> [args...]
expect() {
  local label="$1" summary="$2" want_status="$3" want_text="$4" output status
  shift 4
  set +e
  output="$(PATH="$work/bin:$PATH" FAKE_SUMMARY="$summary" "$script" "$@" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -ne "$want_status" ]]; then
    fail "$label: expected exit $want_status, got $status"; printf '%s\n' "$output" | sed 's/^/         /' >&2
  elif ! printf '%s\n' "$output" | grep -qF -- "$want_text"; then
    fail "$label: output does not mention '$want_text'"; printf '%s\n' "$output" | sed 's/^/         /' >&2
  else
    pass "$label"
  fi
}

bundle="$work/Test.xcresult"
echo "assert-xcresult-tests-ran.sh"
expect "one passing test passes" "$fixtures/pass-one.json" 0 "OK: 1 total, 1 passed, 0 failed" "$bundle"
expect "zero tests fail" "$fixtures/zero-tests.json" 1 "expected at least 1 passed" "$bundle"
expect "a failed test fails even when others passed" "$fixtures/one-failed.json" 1 "1 failed" "$bundle"
expect "only skipped tests fail" "$fixtures/all-skipped.json" 1 "2 skipped; expected at least 1 passed" "$bundle"
expect "MIN_PASSED is enforced" "$fixtures/pass-one.json" 1 "expected at least 2 passed" "$bundle" 2
expect "a summary without counts fails" "$fixtures/missing-counts.json" 1 "unreadable test summary" "$bundle"
FAKE_XCRUN=fail expect "xcresulttool failure fails" "$fixtures/pass-one.json" 1 "could not read" "$bundle"
expect "missing bundle is a usage error" "$fixtures/pass-one.json" 2 "not found" "$work/Nope.xcresult"
expect "no arguments is a usage error" "$fixtures/pass-one.json" 2 "usage"
expect "non-numeric MIN_PASSED is a usage error" "$fixtures/pass-one.json" 2 "non-negative integer" "$bundle" one

echo "test-assert-xcresult-tests-ran: $passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
