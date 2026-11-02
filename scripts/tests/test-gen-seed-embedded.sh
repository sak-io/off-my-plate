#!/usr/bin/env bash
# test-gen-seed-embedded.sh: proves gen-seed-embedded.py --check exits 0 on a clean tree, 1 when the seed JSON
# changed without regenerating, 1 when the generated file was edited, and that regenerating fixes it.
# Works on a temp copy; the real files are never modified.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
gen="$repo/scripts/gen-seed-embedded.py"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/Resources"
cp -R "$repo/core/Sources/OMPRecipes/Resources/seed" "$work/Resources/seed"
cp "$repo/core/Sources/OMPRecipes/SeedEmbedded.generated.swift" "$work/"
export OMP_RECIPES_DIR="$work"
passed=0; failed=0
expect() { # expected label
  local want="$1" label="$2" got
  set +e; python3 "$gen" --check >/dev/null 2>&1; got=$?; set -e
  if [[ "$got" -eq "$want" ]]; then echo "  ok   $label"; passed=$((passed + 1))
  else echo "  FAIL $label: expected exit $want, got $got" >&2; failed=$((failed + 1)); fi
}
echo "gen-seed-embedded.py --check"
expect 0 "a clean copy passes"
printf ' ' >> "$work/Resources/seed/catalog.json"
expect 1 "a changed seed JSON without regenerating fails"
python3 "$gen"
expect 0 "regenerating fixes it"
printf '// tampered\n' >> "$work/SeedEmbedded.generated.swift"
expect 1 "a hand-edited generated file fails"
rm "$work/SeedEmbedded.generated.swift"
expect 1 "a missing generated file fails"
echo "test-gen-seed-embedded: $passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
