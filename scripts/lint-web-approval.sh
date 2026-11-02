#!/usr/bin/env bash
# lint-web-approval.sh: keeps the web app's approval path to ONE call site (W06, ADR 0008, ADR 0016).
#
# Scans platforms/web/app/src and platforms/web/app/tests of ROOT_DIR and fails when:
#   1. the facade's approve operation (the string plan.approve, not plan.approvalPreview or plan.approved)
#      appears anywhere except platforms/web/app/src/screens/plan-approve-button.ts, or appears there
#      other than exactly once;
#   2. the gesture string "confirm-button" appears anywhere except that file, or other than exactly once there;
#   3. createApproveButton is referenced outside plan-approve-button.ts and plan-approval.ts;
#   4. UserConfirmation appears anywhere in platforms/web/app (the web app never builds one; only
#      platforms/web/facade/Sources/OMPWeb/ApprovalBridge.swift does, allow-listed in lint-safety.sh);
#   5. src/screens builds a form or submits one (an implicit Enter-to-submit path to approval);
#   6. src uses innerHTML, outerHTML, insertAdjacentHTML, document.write, eval or new Function
#      (text goes in through textContent only).
# Whole-line // comments are ignored for rules 4 to 6 only; rules 1 to 3 count every occurrence, so the
# call-site file must not even mention the strings in comments. No inline allow escape: change this script
# (owner review, CODEOWNERS) if a real need appears.
# Usage: scripts/lint-web-approval.sh [ROOT_DIR]   Exit: 0 clean, 1 violations, 2 usage error.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="${1:-$repo_root}"
[[ -d "$root" ]] || { echo "lint-web-approval: '$root' is not a directory" >&2; exit 2; }
root="$(cd "$root" && pwd)"
app="platforms/web/app"
[[ -d "$root/$app/src" ]] || { echo "lint-web-approval: no $app/src under '$root'" >&2; exit 2; }

site="$app/src/screens/plan-approve-button.ts"
sheet="$app/src/screens/plan-approval.ts"
violations=0
report() { echo "lint-web-approval: $1" >&2; violations=$((violations + 1)); }

cd "$root"
scan_dirs=("$app/src")
[[ -d "$app/tests" ]] && scan_dirs+=("$app/tests")

# matches PATTERN in ts/js files; prints "file:line:text"
find_all() { grep -rnE --include='*.ts' --include='*.js' --include='*.mjs' --include='*.html' -e "$1" "${scan_dirs[@]}" 2>/dev/null || true; }
# same, minus whole-line // comments
find_code() { find_all "$1" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|/\*|\*)' || true; }

check_single_site() {  # PATTERN LABEL
  local hits other count
  hits="$(find_all "$1")"
  other="$(printf '%s\n' "$hits" | grep -v "^$site:" | grep -v '^$' || true)"
  [[ -z "$other" ]] || report "$2 outside $site:"$'\n'"$other"
  count="$(printf '%s\n' "$hits" | grep -c "^$site:" || true)"
  [[ "$count" == "1" ]] || report "$2 must appear exactly once in $site (found $count)"
}
check_single_site 'plan\.approve\b' 'the approve operation'
check_single_site '"confirm-button"|'"'confirm-button'" 'the confirm-button gesture'

users="$(find_all 'createApproveButton' | grep -v "^$site:" | grep -v "^$sheet:" | grep -v '^$' || true)"
[[ -z "$users" ]] || report "createApproveButton used outside plan-approval.ts:"$'\n'"$users"

uc="$(grep -rn 'UserConfirmation' "$app" --include='*.ts' --include='*.js' --include='*.mjs' --exclude-dir=node_modules --exclude-dir=dist 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|/\*|\*)' || true)"
[[ -z "$uc" ]] || report "UserConfirmation in the web app:"$'\n'"$uc"

forms="$(find_code '(h|createElement)\(["'"'"']form["'"'"']|requestSubmit|onsubmit|addEventListener\(["'"'"']submit' | grep "^$app/src/" || true)"
[[ -z "$forms" ]] || report "form submit path in src:"$'\n'"$forms"

html="$(find_code 'innerHTML|outerHTML|insertAdjacentHTML|document\.write|\beval\(|new Function' | grep "^$app/src/" | grep -v "^$app/src/recipes-data" || true)"
[[ -z "$html" ]] || report "HTML injection / dynamic code in src:"$'\n'"$html"

if [[ $violations -gt 0 ]]; then echo "lint-web-approval: $violations violation(s)" >&2; exit 1; fi
echo "lint-web-approval: ok"
