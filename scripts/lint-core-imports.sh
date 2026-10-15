#!/usr/bin/env bash
# lint-core-imports.sh: keep Packages/Core portable (ADR 0004, ADR 0005).
#
# Fails when:
#   1. a file under Sources/ imports anything other than Foundation or a sibling Core
#      module (a directory under Sources/), e.g. UIKit, SwiftUI, CryptoKit, os, Testing;
#   2. a file under Tests/ imports anything other than the above plus Testing;
#   3. a file under Sources/ uses an API that ADR 0005 rules out because it behaves
#      differently (or not at all) on Linux Foundation, or depends on the device locale,
#      calendar or time zone: NSLocalizedString, String(localized:), NSPredicate, every
#      Foundation *Formatter class, .formatted(...), Calendar/Locale/TimeZone
#      .current/.autoupdatingCurrent, the implicit forms `: TimeZone = .current` and
#      `timeZone: .current` (also calendar/locale), and NSTimeZone/NSLocale/NSCalendar
#      .local/.system/.default/.current/.autoupdatingCurrent (inject an explicit
#      TimeZone/Calendar instead);
#   4. Package.swift (or a Package@swift-*.swift variant) declares any package
#      dependency (Core has zero dependencies).
# Imports are recognised with attributes (@testable, @preconcurrency, ...), Swift 6
# access levels (public/package/internal/fileprivate/private import) and import kinds
# (import struct Foundation.Date), also after a `;` or a closed /* ... */ comment on the
# same line (`import Foundation; import UIKit`, `/* x */ import UIKit`).
#
# Fail-safe by design: this is text matching, not a parser, so a banned name inside a
# string literal may be reported (a false positive); it is never silently skipped.
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

# An import line: optional attributes (@testable, @preconcurrency, @_exported, ...), an
# optional Swift 6 access level, the keyword, an optional import kind (struct, func, ...),
# then Module[.Sub]. Groups: 1-2 attributes, 3-4 access level, 5-6 kind, 7 module.
import_prefix='^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+'
# A statement starts at the line start or after `;`, optionally after closed /* */ comments.
closed_comment='/\*([^*]|\*+[^*/])*\*+/'
stmt_start="(^|;)[[:space:]]*(${closed_comment}[[:space:]]*)*"
import_line_re="${stmt_start}${import_prefix#^}"
# Whole-line comments: //, /// and * continuation lines, a /* that stays open, and a
# line that is nothing but closed /* */ comments. Code after a closed comment is checked.
comment_only_re="^[[:space:]]*(//|\\*|/\\*([^*]|\\*+[^*/])*\\**\$|(${closed_comment}[[:space:]]*)+\$)"
module_sed="s/${import_prefix}((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*\$/\\7/"

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
    if grep -qE "$comment_only_re" <<<"$text"; then
      continue
    fi
    # One report per import statement on the line (split on `;`, drop leading comments).
    while IFS= read -r segment; do
      segment="$(sed -E "s#^[[:space:]]*(${closed_comment}[[:space:]]*)*##" <<<"$segment")"
      grep -qE "$import_prefix" <<<"$segment" || continue
      module="$(sed -E "$module_sed" <<<"$segment")"
      if ! is_allowed "$module" "$allowed"; then
        report "$file:$line: import of '$module' is not allowed in Core $label (allowed: $allowed)"
      fi
    done < <(tr ';' '\n' <<<"$text")
  done < <(grep -rnE --include='*.swift' --exclude-dir=.build "$import_line_re" "$dir" || true)
}

check_imports "$core_dir/Sources" "Foundation$core_modules" "sources"
check_imports "$core_dir/Tests" "Foundation Testing$core_modules" "tests"

# Platform- or locale-dependent APIs (ADR 0005). Whole-line comments are ignored.
formatters='DateFormatter|DateComponentsFormatter|DateIntervalFormatter|ISO8601DateFormatter|RelativeDateTimeFormatter|NumberFormatter|MeasurementFormatter|ByteCountFormatter|PersonNameComponentsFormatter|ListFormatter|LengthFormatter|MassFormatter|EnergyFormatter'
cur='(current|autoupdatingCurrent)'
# Implicit member forms: `: TimeZone = .current` (also ? and !), and a timeZone/calendar/
# locale label, assignment or comparison: `timeZone: .current`, `c.timeZone = .current`,
# `x.timeZone == .current`, `x.timeZone != .current`.
implicit_current="(TimeZone|Calendar|Locale)[?!]?[[:space:]]*=[[:space:]]*\\.$cur|(timeZone|calendar|locale)[[:space:]]*(:|[!=]?=)[[:space:]]*\\.$cur|NS(TimeZone|Locale|Calendar)\\.(local|system|default|current|autoupdatingCurrent)"
banned_api_re="(^|[^A-Za-z0-9_])(NSLocalizedString|NSPredicate|$formatters)([^A-Za-z0-9_]|\$)|String\\(localized:|\\.formatted\\(|(^|[^A-Za-z0-9_])(Calendar|Locale|TimeZone)\\.$cur([^A-Za-z0-9_]|\$)|(^|[^A-Za-z0-9_])($implicit_current)([^A-Za-z0-9_]|\$)"
banned_api_only="NSLocalizedString|NSPredicate|$formatters|String\\(localized:|\\.formatted\\(|$implicit_current|(Calendar|Locale|TimeZone)\\.$cur"
while IFS= read -r hit; do
  file="${hit%%:*}"
  rest="${hit#*:}"
  line="${rest%%:*}"
  text="${rest#*:}"
  if grep -qE "$comment_only_re" <<<"$text"; then
    continue
  fi
  api="$(printf '%s\n' "$text" | grep -oE "$banned_api_only" | head -n 1)"
  report "$file:$line: '$api' is not allowed in Core sources (ADR 0005: not portable or locale-dependent; return structured values and localise in the UI)"
done < <(grep -rnE --include='*.swift' --exclude-dir=.build "$banned_api_re" "$core_dir/Sources" || true)

# Zero package dependencies (ADR 0005), in the manifest and any version-specific variant.
# `.package(` starts every dependency form (url:, path:, id:, name:+url:), even when the
# arguments continue on the next lines.
for manifest in "$core_dir"/Package.swift "$core_dir"/Package@swift-*.swift; do
  [[ -f "$manifest" ]] || continue
  while IFS= read -r hit; do
    report "$manifest:${hit%%:*}: Core must have zero package dependencies (ADR 0005)"
  done < <(grep -nE '\.package[[:space:]]*\(' "$manifest" || true)
done

if [[ "$violations" -gt 0 ]]; then
  echo "lint-core-imports: FAILED with $violations violation(s)" >&2
  exit 1
fi
echo "lint-core-imports: OK ($core_dir)"
