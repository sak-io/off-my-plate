#!/usr/bin/env bash
# test-lints.sh: proves each lint passes on clean input AND fails on planted violations.
#
# Every directory under scripts/tests/fixtures/<lint>/ is one case:
#   clean           -> the lint must exit 0
#   violation-*     -> the lint must exit 1 and name the offending file in its output;
#                      if the case has an expected-output.txt, EVERY line of it must
#                      appear in the output (proves the exact file:line and reason)
# The lints are also run against the real repository (must pass) and against a
# missing directory (must exit 2, usage error).
#
# Usage: scripts/tests/test-lints.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scripts="$(cd "$here/.." && pwd)"
fixtures="$here/fixtures"

passed=0
failed=0
pass() { echo "  ok   $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL $1" >&2; failed=$((failed + 1)); }

# run_case <lint script> <fixture dir or ""> <expected exit> <label> [expected text|@file]
# "@file" means: every non-empty line of that file must appear in the output.
run_case() {
  local lint="$1" dir="$2" expected="$3" label="$4" text="${5:-}" output status want
  set +e
  if [[ -n "$dir" ]]; then
    output="$("$scripts/$lint" "$dir" 2>&1)"
  else
    output="$("$scripts/$lint" 2>&1)"
  fi
  status=$?
  set -e
  if [[ "$status" -ne "$expected" ]]; then
    fail "$label: expected exit $expected, got $status"
    printf '%s\n' "$output" | sed 's/^/         /' >&2
    return
  fi
  if [[ "$text" == @* ]]; then
    while IFS= read -r want || [[ -n "$want" ]]; do
      [[ -n "$want" ]] || continue
      if ! printf '%s\n' "$output" | grep -qF -- "$want"; then
        fail "$label: output does not contain '$want'"
        printf '%s\n' "$output" | sed 's/^/         /' >&2
        return
      fi
    done < "${text#@}"
  elif [[ -n "$text" ]] && ! printf '%s\n' "$output" | grep -qF -- "$text"; then
    fail "$label: output does not mention '$text'"
    printf '%s\n' "$output" | sed 's/^/         /' >&2
    return
  fi
  pass "$label"
}

# run_fixtures <lint script> <fixture group>
run_fixtures() {
  local lint="$1" group="$2" case_dir name violations=0
  echo "$lint"
  [[ -d "$fixtures/$group/clean" ]] || { fail "$group: missing clean fixture"; return; }
  run_case "$lint" "$fixtures/$group/clean" 0 "$group/clean passes"
  for case_dir in "$fixtures/$group"/violation-*/; do
    [[ -d "$case_dir" ]] || continue
    name="$(basename "$case_dir")"
    # Without an expected-output.txt the planted file is named Bad*.swift, so requiring
    # "Bad" in the output proves the lint pointed at the planted violation.
    local expect="Bad"
    if [[ -f "${case_dir}expected-output.txt" ]]; then
      expect="@${case_dir}expected-output.txt"
    fi
    run_case "$lint" "${case_dir%/}" 1 "$group/$name fails" "$expect"
    violations=$((violations + 1))
  done
  [[ "$violations" -gt 0 ]] || fail "$group: no violation fixtures found"
  run_case "$lint" "$fixtures/$group/does-not-exist" 2 "$group: missing directory is a usage error"
  run_case "$lint" "" 0 "$group: the repository itself passes"
}

# Git cannot commit an empty directory, so a fixture that relies on one passes locally
# but breaks on a fresh checkout (CI). Put a placeholder file in it instead.
echo "fixtures"
empty_dirs="$(find "$fixtures" -type d -empty)"
if [[ -n "$empty_dirs" ]]; then
  fail "fixtures contain empty directories (lost on checkout): $empty_dirs"
else
  pass "no empty fixture directories"
fi

run_fixtures lint-core-imports.sh core-imports
run_fixtures lint-no-network.sh no-network
run_fixtures lint-safety.sh safety

echo "test-lints: $passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
