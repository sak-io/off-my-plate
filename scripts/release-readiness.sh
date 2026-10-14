#!/usr/bin/env bash
# release-readiness.sh: fails while the seed content is not signed off (G1) or the
# restriction/keyword definitions are not signed off (R4/G4). Run it before every TestFlight upload.
#
# Checks:
#   1. seed sheet: every recipe is signed off (header "signed off: N, draft: 0", no "Review: draft" line)
#   2. restriction sign-off record: the "definitions approved" checkbox is ticked with a reviewer and an ISO date
#   3. with --app-store: the two App Store-only G4 lines are ticked as well (TestFlight beta may proceed without)
# Unverified ingredients are reported as a warning (AC-4.3 already excludes them for hard rules).
#
# Usage: scripts/release-readiness.sh [--app-store] [SEED-REVIEW.md [RESTRICTION-SIGNOFF.md]]
# Exit: 0 ready, 1 not ready, 2 usage error (missing file).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_store=false
if [[ "${1:-}" == "--app-store" ]]; then app_store=true; shift; fi
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -gt 2 ]]; then sed -n '2,13p' "$0"; exit 2; fi
sheet="${1:-$repo_root/docs/content/seed-review.md}"
record="${2:-$repo_root/docs/content/restriction-signoff.md}"
for f in "$sheet" "$record"; do
  [[ -f "$f" ]] || { echo "release-readiness: '$f' not found" >&2; exit 2; }
done

problems=0
fail() { echo "release-readiness: NOT READY: $1" >&2; problems=$((problems + 1)); }

# 1. recipes (G1)
summary="$(grep -m1 -E '^Recipes: [0-9]+ \(signed off: [0-9]+, draft: [0-9]+\)$' "$sheet" || true)"
if [[ -z "$summary" ]]; then
  fail "$sheet has no 'Recipes: N (signed off: S, draft: D)' line"
else
  total="$(sed -E 's/^Recipes: ([0-9]+) .*/\1/' <<<"$summary")"
  drafts="$(sed -E 's/.*draft: ([0-9]+)\)$/\1/' <<<"$summary")"
  [[ "$total" -gt 0 ]] || fail "the seed sheet lists no recipes"
  [[ "$drafts" -eq 0 ]] || fail "$drafts of $total seed recipes are not signed off (G1)"
fi
listed_drafts="$(grep -c -E '^- Review: draft' "$sheet" || true)"
[[ "$listed_drafts" -eq 0 ]] || fail "$listed_drafts recipe sections still say 'Review: draft' (G1)"
unverified="$(grep -m1 -E '^Ingredients: .*\(unverified: [0-9]+\)' "$sheet" | sed -E 's/.*unverified: ([0-9]+)\).*/\1/' || true)"
if [[ -n "$unverified" && "$unverified" -gt 0 ]]; then
  echo "release-readiness: warning: $unverified ingredients have unverified allergen tags" >&2
fi

# 2/3. sign-off lines (R4/G4): ticked box, a reviewer name, an ISO date
ticked() { # label-regex
  grep -E "^- \[[xX]\] $1" "$record" | grep -qE 'Reviewer: [^_ ][^ ]*.* Date: [0-9]{4}-[0-9]{2}-[0-9]{2}' 
}
ticked 'Restriction and keyword definitions approved' \
  || fail "restriction/keyword definitions are not signed off in $record (R4/G4)"
if $app_store; then
  ticked 'Privacy policy, data map and disclaimer' || fail "privacy policy/data map/disclaimer review missing (G4, App Store)"
  ticked 'Recipe allergen tags spot-checked' || fail "dietitian spot-check missing (G4, App Store)"
fi

if [[ "$problems" -gt 0 ]]; then
  echo "release-readiness: $problems problem(s); do not upload" >&2
  exit 1
fi
echo "release-readiness: OK"
