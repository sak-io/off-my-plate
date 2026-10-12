#!/usr/bin/env bash
# lint-core-imports.sh: keep Packages/Core portable (ADR 0004, ADR 0005).
#
# Fails when:
#   1. a file under Sources/ imports anything other than Foundation or a sibling Core
#      module (a directory under Sources/), e.g. UIKit, SwiftUI, CryptoKit, os, Testing;
#   2. a file under Tests/ imports anything other than the above plus Testing;
#   3. a file under Sources/ uses an API that ADR 0005 rules out because it behaves
#      differently (or not at all) on Linux Foundation: NSLocalizedString,
#      String(localized:), NSPredicate, DateFormatter, NumberFormatter;
#   4. Package.swift declares any package dependency (Core has zero dependencies).
#
# Usage: scripts/lint-core-imports.sh [CORE_PACKAGE_DIR]   (default: Packages/Core)
# Exit:  0 clean, 1 violations found, 2 usage error.
# Portable: bash 3.2+, POSIX grep/sed (works on Linux CI and macOS).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core_dir="${1:-$repo_root/Packages/Core}"

if [[ ! -d "$core_dir/Sources" || ! -f "$core_dir/Package.swift" ]]; then
  echo "lint-core-imports: '$core_dir' is not a Swift package with a Sources/ directory" >&2
  exit 2
fi

violations=0
report() {
  echo "$1" >&2
  violations=$((violations + 1))
}

# Every directory under Sources/ is a Core module; Core modules may import each other.
core_modules=""
for d in "$core_dir"/Sources/*/; do
  [[ -d "$d" ]] && core_modules="$core_modules $(basename "$d")"
done

# An import line: optional attributes (@testable, @preconcurrency, @_exported, ...),
# the keyword, an optional import kind (struct, class, func, ...), then Module[.Sub].
import_line_re='^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*import[[:space:]]'
module_sed='s/^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*$/\5/'

is_allowed() { # module, space-separated allow list
  local m
  for m in $2; do
    [[ "$1" == "$m" ]] && return 0
  done
  return 1
}

check_imports() { # dir, allow list, label
  local dir="$1" allowed="$2" label="$3" file line text module
  [[ -d "$dir" ]] || return 0
  while IFS= read -r hit; do
    file="${hit%%:*}"
    rest="${hit#*:}"
    line="${rest%%:*}"
    text="${rest#*:}"
    module="$(printf '%s\n' "$text" | sed -E "$module_sed")"
    if ! is_allowed "$module" "$allowed"; then
      report "$file:$line: import of '$module' is not allowed in Core $label (allowed: $allowed)"
    fi
  done < <(grep -rnE --include='*.swift' --exclude-dir=.build "$import_line_re" "$dir" || true)
}

check_imports "$core_dir/Sources" "Foundation$core_modules" "sources"
check_imports "$core_dir/Tests" "Foundation Testing$core_modules" "tests"

# Platform- or locale-dependent APIs (ADR 0005). Whole-line comments are ignored.
banned_api_re='(^|[^A-Za-z0-9_])(NSLocalizedString|NSPredicate|DateFormatter|NumberFormatter)([^A-Za-z0-9_]|$)|String\(localized:'
while IFS= read -r hit; do
  file="${hit%%:*}"
  rest="${hit#*:}"
  line="${rest%%:*}"
  text="${rest#*:}"
  if printf '%s\n' "$text" | grep -qE '^[[:space:]]*(//|/\*|\*)'; then
    continue
  fi
  api="$(printf '%s\n' "$text" | grep -oE 'NSLocalizedString|NSPredicate|DateFormatter|NumberFormatter|String\(localized:' | head -n 1)"
  report "$file:$line: '$api' is not allowed in Core sources (ADR 0005: not portable or locale-dependent; return structured values and localise in the UI)"
done < <(grep -rnE --include='*.swift' --exclude-dir=.build "$banned_api_re" "$core_dir/Sources" || true)

# Zero package dependencies (ADR 0005).
while IFS= read -r hit; do
  report "$core_dir/Package.swift:${hit%%:*}: Core must have zero package dependencies (ADR 0005)"
done < <(grep -nE '\.package[[:space:]]*\(' "$core_dir/Package.swift" || true)

if [[ "$violations" -gt 0 ]]; then
  echo "lint-core-imports: FAILED with $violations violation(s)" >&2
  exit 1
fi
echo "lint-core-imports: OK ($core_dir)"
