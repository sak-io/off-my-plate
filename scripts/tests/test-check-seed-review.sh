#!/usr/bin/env bash
# test-check-seed-review.sh: proves scripts/check-seed-review.sh passes identical sheets,
# fails (exit 1, with a diff naming the changed line and how to regenerate) on any byte of
# difference including a missing final newline, and treats missing files as usage errors.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="$(cd "$here/.." && pwd)/check-seed-review.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
passed=0
failed=0

check() { # expected-exit label expected-text args...
  local expected="$1" label="$2" text="$3" status output
  shift 3
  set +e
  output="$("$check_script" "$@" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -ne "$expected" ]]; then
    echo "  FAIL $label: expected exit $expected, got $status" >&2
    printf '%s\n' "$output" | sed 's/^/         /' >&2
    failed=$((failed + 1))
  elif [[ -n "$text" ]] && ! printf '%s\n' "$output" | grep -qF -- "$text"; then
    echo "  FAIL $label: output does not mention '$text'" >&2
    printf '%s\n' "$output" | sed 's/^/         /' >&2
    failed=$((failed + 1))
  else
    echo "  ok   $label"
    passed=$((passed + 1))
  fi
}

printf '# Seed review\n\n| Recipe | Tags |\n| dal | milk |\n' > "$work/committed.md"
cp "$work/committed.md" "$work/same.md"
printf '# Seed review\n\n| Recipe | Tags |\n| dal | milk, wheat |\n' > "$work/changed.md"
printf '# Seed review\n\n| Recipe | Tags |\n| dal | milk |' > "$work/no-newline.md"

echo "check-seed-review.sh"
check 0 "identical sheets pass" "OK" "$work/same.md" "$work/committed.md"
check 1 "a changed line fails with a diff" "+| dal | milk, wheat |" "$work/changed.md" "$work/committed.md"
check 1 "the failure says how to regenerate" "seed-review-sheet" "$work/changed.md" "$work/committed.md"
check 1 "a missing final newline fails" "FAILED" "$work/no-newline.md" "$work/committed.md"
check 2 "a missing generated sheet is a usage error" "not found" "$work/nope.md" "$work/committed.md"
check 2 "a missing committed sheet is a usage error" "not found" "$work/same.md" "$work/nope.md"
check 2 "too many arguments is a usage error" "" "$work/same.md" "$work/committed.md" extra

echo "test-check-seed-review: $passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
