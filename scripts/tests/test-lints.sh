#!/usr/bin/env bash
# test-lints.sh: proves each lint passes on clean input AND fails on planted violations.
#
# Every directory under scripts/tests/fixtures/<lint>/ is one case:
#   clean           -> the lint must exit 0
#   violation-*     -> the lint must exit 1 and name the offending file in its output
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

# run_case <lint script> <fixture dir or ""> <expected exit> <label> [expected text]
run_case() {
  local lint="$1" dir="$2" expected="$3" label="$4" text="${5:-}" output status
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
  if [[ -n "$text" ]] && ! printf '%s\n' "$output" | grep -qF -- "$text"; then
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
    # The offending file is the one named Bad*.swift, Package.swift or project.yml that
    # differs from the clean case; requiring "Bad" or the manifest name in the output
    # proves the lint pointed at the planted violation.
    local expect="Bad"
    case "$name" in
      *package-dependency|*package-url) expect="Package.swift" ;;
      *project-yml*) expect="project.yml" ;;
    esac
    run_case "$lint" "${case_dir%/}" 1 "$group/$name fails" "$expect"
    violations=$((violations + 1))
  done
  [[ "$violations" -gt 0 ]] || fail "$group: no violation fixtures found"
  run_case "$lint" "$fixtures/$group/does-not-exist" 2 "$group: missing directory is a usage error"
  run_case "$lint" "" 0 "$group: the repository itself passes"
}

run_fixtures lint-core-imports.sh core-imports
run_fixtures lint-no-network.sh no-network

echo "test-lints: $passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
