#!/usr/bin/env bash
# check-seed-review.sh: the committed seed sign-off sheet must be exactly what the code prints
# (ADR 0010, G1; T06 handoff follow-up, T12).
#
# docs/content/seed-review.md is what the owner signs off; it must match
# `swift run seed-review-sheet` byte for byte, so the sheet can never drift from the bundled
# seed content. On a difference this prints a unified diff and how to regenerate the file.
# Regenerating is a deliberate human step (the owner re-reviews the changed sheet), so this
# check never rewrites the file itself.
#
# Usage: scripts/check-seed-review.sh [GENERATED.md [COMMITTED.md]]
#   GENERATED.md  an already generated sheet (default: run `swift run seed-review-sheet`)
#   COMMITTED.md  the committed sheet (default: docs/content/seed-review.md)
# Exit: 0 identical, 1 different, 2 usage error (missing file, no Swift toolchain, build failure).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
generated="${1:-}"
committed="${2:-$repo_root/docs/content/seed-review.md}"

if [[ $# -gt 2 || "$generated" == "-h" || "$generated" == "--help" ]]; then
  sed -n '2,15p' "$0"
  exit 2
fi
if [[ ! -f "$committed" ]]; then
  echo "check-seed-review: committed sheet '$committed' not found" >&2
  exit 2
fi

if [[ -z "$generated" ]]; then
  if ! command -v swift >/dev/null 2>&1; then
    echo "check-seed-review: no Swift toolchain on PATH (pass an already generated sheet instead)" >&2
    exit 2
  fi
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  generated="$tmp_dir/seed-review.md"
  if ! swift run --package-path "$repo_root/Packages/Core" seed-review-sheet "$generated" >&2; then
    echo "check-seed-review: 'swift run seed-review-sheet' failed" >&2
    exit 2
  fi
fi
if [[ ! -f "$generated" ]]; then
  echo "check-seed-review: generated sheet '$generated' not found" >&2
  exit 2
fi

if cmp -s "$committed" "$generated"; then
  echo "check-seed-review: OK ($committed matches seed-review-sheet output)"
  exit 0
fi

{
  echo "check-seed-review: FAILED: $committed differs from 'swift run seed-review-sheet' output."
  echo "  ('-' lines are in the committed file, '+' lines are what the code prints now)"
  diff -u -L "committed: $committed" -L "generated: seed-review-sheet" "$committed" "$generated" || true
  cat <<'HOW'

To fix: regenerate the sheet, review the change with the owner (it is the seed sign-off
sheet, ADR 0010), and commit it:
  swift run --package-path Packages/Core seed-review-sheet "$PWD/docs/content/seed-review.md"
HOW
} >&2
exit 1
