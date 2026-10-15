#!/usr/bin/env bash
# test-localization.sh: the localisation lint passes on a complete catalog and fails on a missing
# key, a wrong interpolation count and an unparseable call.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lint="$here/../check-localization.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_tree() { # dir, swift body, catalog strings (JSON object body)
  mkdir -p "$1/Packages/Apple/Sources/OMPUI" "$1/App/OffMyPlate"
  printf '%s\n' "$2" > "$1/Packages/Apple/Sources/OMPUI/Copy.swift"
  printf '{"sourceLanguage":"en","strings":{%s},"version":"1.0"}\n' "$3" > "$1/App/OffMyPlate/Localizable.xcstrings"
}
entry() { printf '"%s":{"localizations":{"en":{"stringUnit":{"state":"translated","value":"%s"}}}}' "$1" "$2"; }

fail=0
expect() { # label, expected exit, dir
  set +e; python3 "$lint" --root "$3" >/dev/null 2>&1; local s=$?; set -e
  if [[ "$s" -eq "$2" ]]; then echo "  ok   $1"; else echo "  FAIL $1 (exit $s, want $2)" >&2; fail=1; fi
}

echo "test-localization"
make_tree "$tmp/ok" 'let a = String(localized: "k.a", defaultValue: "Add \(count)", comment: "c")' "$(entry k.a 'Add %lld')"
expect "complete catalog passes" 0 "$tmp/ok"
make_tree "$tmp/missing" 'let a = String(localized: "k.a", defaultValue: "Hi", comment: "c")' "$(entry k.b 'Other')"
expect "missing key fails" 1 "$tmp/missing"
make_tree "$tmp/spec" 'let a = String(localized: "k.a", defaultValue: "Add \(count)", comment: "c")' "$(entry k.a 'Add')"
expect "wrong specifier count fails" 1 "$tmp/spec"
make_tree "$tmp/parse" 'let a = String(localized: key, defaultValue: "Hi")' "$(entry k.a 'Hi')"
expect "unparseable call fails" 1 "$tmp/parse"
make_tree "$tmp/fix" 'let a = String(localized: "k.a", defaultValue: "Hi", comment: "c")' ""
python3 "$lint" --root "$tmp/fix" --fix >/dev/null
expect "--fix adds the missing key" 0 "$tmp/fix"
exit "$fail"
