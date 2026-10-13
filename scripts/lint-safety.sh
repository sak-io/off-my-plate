#!/usr/bin/env bash
# lint-safety.sh: the build-failing safety checks of ADR 0007 / ADR 0008 (T12).
#
# Scans every Swift file under Packages/ and App/ of ROOT_DIR (paths below are relative to
# it) and fails when:
#   1. a public/package/open function under Packages/Core/Sources/OMPDomain/Planner/ has no
#      `SafetyClearance` parameter (non-optional), unless it is a listed non-entry-point
#      helper (PLANNER_HELPERS below) that cannot produce or edit a plan;
#   2. `SafetyClearance(` (or `SafetyClearance.init(`) or `extension SafetyClearance` appears
#      outside Packages/Core/Sources/OMPDomain/Safety/SafetyGate.swift;
#   3. `ValidationReport(` (or `.init(`, or `.init(planId:`) or `extension ValidationReport`
#      appears outside Packages/Core/Sources/OMPSafetyCheck/ and tests (the extension is also
#      allowed in its own file, Safety/ValidationReport.swift);
#   4. `PlanApproval(`, a `status = .approved` assignment, `status: .approved` (initialiser
#      argument) or `blockedBySafety = false` appears outside
#      Packages/Core/Sources/OMPDomain/Plan/PlanLifecycle.swift, the OMPData mapping files
#      (Packages/Apple/Sources/OMPData/Mapping/) and tests. One reviewed exception:
#      `blockedBySafety = false` in Planner/WeekPlanner+Editing.swift (a meal whose recipe the
#      planner replaced from the hard filter is no longer the meal that was blocked; the
#      result is a draft that is validated again before display);
#   5. `UserConfirmation(` (or `.init(`, or `confirmation: .init(`) appears outside tests and
#      the approval sheet (Packages/Apple/Sources/OMPFeatures/**/Approval*.swift);
#   6. the safety suite (Packages/Core/Tests/OMPSafetySuiteTests/) contains `.disabled`,
#      `withKnownIssue`, `.enabled(` or `#if`: nothing in it may be skipped, expected to
#      fail or compiled out.
# Tests are files under Packages/<package>/Tests/ or App/<target>Tests/.
# Whole-line comments (//, ///, /*, *) are ignored. There is deliberately no inline "allow"
# escape hatch: change this script in a reviewed PR if a real need appears.
#
# Fail-safe by design: this is text matching, not a parser, so a banned pattern inside a
# string literal may be reported (a false positive); it is never silently skipped.
#
# Usage: scripts/lint-safety.sh [ROOT_DIR]   (default: repository root)
# Exit:  0 clean, 1 violations found, 2 usage error.
# Portable: bash 3.2+, POSIX grep/sed/awk (works on Linux CI and macOS).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="${1:-$repo_root}"

if [[ ! -d "$root" ]]; then
  echo "lint-safety: '$root' is not a directory" >&2
  exit 2
fi
root="$(cd "$root" && pwd)"

scan_dirs=()
for d in Packages App; do
  [[ -d "$root/$d" ]] && scan_dirs+=("$root/$d")
done
if [[ ${#scan_dirs[@]} -eq 0 ]]; then
  echo "lint-safety: nothing to scan (no Packages/ or App/ under '$root')" >&2
  exit 2
fi

violations=0
report() {
  echo "$1" >&2
  violations=$((violations + 1))
}

planner_dir="Packages/Core/Sources/OMPDomain/Planner"
gate_file="Packages/Core/Sources/OMPDomain/Safety/SafetyGate.swift"
report_file="Packages/Core/Sources/OMPDomain/Safety/ValidationReport.swift"
lifecycle_file="Packages/Core/Sources/OMPDomain/Plan/PlanLifecycle.swift"
planner_editing_file="$planner_dir/WeekPlanner+Editing.swift"
suite_dir="Packages/Core/Tests/OMPSafetySuiteTests/"

# Public planner functions that are not entry points: they cannot produce or edit a plan
# (pure helpers for dates, slots, scoring, lookups and seeds). "file-relative-to-Planner:name".
PLANNER_HELPERS="
HardFilter.swift:fits
PlanDateRange.swift:startDate
PlanDateRange.swift:dates
PlannerLibrary.swift:entry
PlannerScoring.swift:score
SlotExpansion.swift:needsLunchbox
SlotExpansion.swift:slots
WeekPlanner.swift:derived
WeekPlanner+Editing.swift:replacingRecipe
"

closed_comment='/\*([^*]|\*+[^*/])*\*+/'
# Whole-line comments: //, /// and * continuation lines, a /* that stays open, and a
# line that is nothing but closed /* */ comments. Code after a closed comment is checked.
comment_re="^[[:space:]]*(//|\\*|/\\*([^*]|\\*+[^*/])*\\**\$|(${closed_comment}[[:space:]]*)+\$)"

is_test() { # relative path
  [[ "$1" =~ ^Packages/[^/]+/Tests/ || "$1" =~ ^App/[^/]*Tests/ ]]
}

# scan <regex> <message> <allowed-predicate>: reports every non-comment match in a Swift
# file for which the predicate (a function taking the relative path) fails.
scan() {
  local regex="$1" message="$2" allowed="$3" hit file rel rest line text
  while IFS= read -r hit; do
    file="${hit%%:*}"
    rest="${hit#*:}"
    line="${rest%%:*}"
    text="${rest#*:}"
    if printf '%s\n' "$text" | grep -qE "$comment_re"; then
      continue
    fi
    rel="${file#"$root"/}"
    if "$allowed" "$rel"; then
      continue
    fi
    report "$rel:$line: $message: $(printf '%s' "$text" | sed -E 's/^[[:space:]]+//')"
  done < <(grep -rnE --include='*.swift' --exclude-dir=.build --exclude-dir=DerivedData \
             "$regex" "${scan_dirs[@]}" || true)
}

w='[^A-Za-z0-9_]'

# 2. SafetyClearance is constructed only by the gate.
in_gate() { [[ "$1" == "$gate_file" ]]; }
scan "(^|$w)SafetyClearance[[:space:]]*(\\.init)?[[:space:]]*\\(|(^|$w)extension[[:space:]]+SafetyClearance($w|\$)" \
  "SafetyClearance may be created only in $gate_file (ADR 0007)" in_gate

# 3. ValidationReport is built only by the validator (and tests).
report_allowed() {
  [[ "$1" == Packages/Core/Sources/OMPSafetyCheck/* ]] || is_test "$1"
}
scan "(^|$w)ValidationReport[[:space:]]*(\\.init)?[[:space:]]*\\(|\\.init\\([[:space:]]*planId[[:space:]]*:" \
  "ValidationReport may be created only in Packages/Core/Sources/OMPSafetyCheck/ and tests (ADR 0007)" report_allowed
report_extension_allowed() {
  report_allowed "$1" || [[ "$1" == "$report_file" ]]
}
scan "(^|$w)extension[[:space:]]+ValidationReport($w|\$)" \
  "ValidationReport may be extended only in its own file, Packages/Core/Sources/OMPSafetyCheck/ and tests (ADR 0007)" \
  report_extension_allowed

# 4. Approval state is written only by the lifecycle, the persistence mapping and tests.
approval_allowed() {
  [[ "$1" == "$lifecycle_file" || "$1" == Packages/Apple/Sources/OMPData/Mapping/* ]] || is_test "$1"
}
scan "(^|$w)PlanApproval[[:space:]]*(\\.init)?[[:space:]]*\\(" \
  "PlanApproval may be created only in $lifecycle_file, the OMPData mapping and tests (ADR 0008)" approval_allowed
scan "(^|$w)status[[:space:]]*=[[:space:]]*(PlanStatus)?\\.approved($w|\$)|(^|$w)status[[:space:]]*:[[:space:]]*(PlanStatus)?\\.approved($w|\$)" \
  "a plan may be marked approved only in $lifecycle_file, the OMPData mapping and tests (ADR 0008)" approval_allowed
unblock_allowed() {
  approval_allowed "$1" || [[ "$1" == "$planner_editing_file" ]]
}
scan "(^|$w)blockedBySafety[[:space:]]*=[[:space:]]*false($w|\$)" \
  "a safety block may be cleared only in $lifecycle_file, the OMPData mapping and tests (ADR 0008, R1)" unblock_allowed

# 5. UserConfirmation is created only by the approval sheet's button (and tests).
confirmation_allowed() {
  is_test "$1" && return 0
  [[ "$1" == Packages/Apple/Sources/OMPFeatures/* ]] || return 1
  case "$(basename "$1")" in
    Approval*.swift) return 0 ;;
  esac
  return 1
}
scan "(^|$w)UserConfirmation[[:space:]]*(\\.init)?[[:space:]]*\\(|(^|$w)confirmation[[:space:]]*:[[:space:]]*\\.init[[:space:]]*\\(" \
  "UserConfirmation may be created only in the approval sheet (OMPFeatures/**/Approval*.swift) and tests (ADR 0008, AC-5.6)" \
  confirmation_allowed

# 6. Nothing in the safety suite may be disabled, expected to fail or compiled out.
not_in_suite() { [[ "$1" != "$suite_dir"* ]]; }
scan "\\.disabled($w|\$)|(^|$w)withKnownIssue($w|\$)|\\.enabled[[:space:]]*\\(|^[[:space:]]*#if($w|\$)" \
  "the safety suite must not be disabled, conditional or marked as a known issue (T12)" not_in_suite

# 1. Every public planner function takes a SafetyClearance, unless it is a listed helper.
if [[ -d "$root/$planner_dir" ]]; then
  while IFS= read -r file; do
    rel="${file#"$root/$planner_dir"/}"
    while IFS=$'\t' read -r line name signature; do
      [[ -n "$line" ]] || continue
      if printf '%s\n' "$PLANNER_HELPERS" | grep -qxF -- "$rel:$name"; then
        continue
      fi
      if printf '%s\n' "$signature" \
        | grep -qE ":[[:space:]]*((borrowing|consuming|sending)[[:space:]]+)?SafetyClearance([^?!A-Za-z0-9_.]|\$)"; then
        continue
      fi
      report "$planner_dir/$rel:$line: public planner function '$name' has no SafetyClearance parameter (ADR 0007): every planner entry point must take a clearance"
    done < <(awk '
      # Prints "line<TAB>name<TAB>signature" for every public/package/open func; the signature
      # runs from the func keyword to the first "{" (or the end of the file), with // comments
      # removed. Whole-line comments are skipped. Only [ \t] and plain ERE are used, so this
      # runs on mawk, gawk and the BSD awk of macOS.
      function flush() {
        if (collecting) { printf "%d\t%s\t%s\n", start, name, sig }
        collecting = 0; sig = ""
      }
      /^[ \t]*(\/\/|\*|\/\*)/ { next }
      {
        text = " " $0
        sub(/\/\/.*$/, "", text)
        pos = match(text, /[^A-Za-z0-9_]func[ \t]/)
        if (!collecting && pos > 0) {
          head = substr(text, 1, pos) " "
          if (head ~ /[^A-Za-z0-9_](public|package|open)[^A-Za-z0-9_(]/) {
            collecting = 1; start = NR
            rest = substr(text, pos + RLENGTH)
            sub(/^[ \t]+/, "", rest)
            name = rest
            sub(/[^A-Za-z0-9_].*$/, "", name)
            sig = rest
            if (index(rest, "{") > 0) { sig = substr(rest, 1, index(rest, "{") - 1); flush() }
            next
          }
        }
        if (collecting) {
          if (index(text, "{") > 0) { sig = sig " " substr(text, 1, index(text, "{") - 1); flush() }
          else { sig = sig " " text }
        }
      }
      END { flush() }
    ' "$file")
  done < <(find "$root/$planner_dir" -name '*.swift' -type f | LC_ALL=C sort)
fi

if [[ "$violations" -gt 0 ]]; then
  echo "lint-safety: FAILED with $violations violation(s)" >&2
  exit 1
fi
echo "lint-safety: OK (${scan_dirs[*]})"
