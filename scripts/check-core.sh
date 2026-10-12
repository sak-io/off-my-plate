#!/usr/bin/env bash
# check-core.sh: everything a Core change must pass, in CI order.
#
#   1. lint self-tests (each lint passes on clean fixtures and fails on planted violations)
#   2. every scripts/lint-*.sh against the repository
#   3. swift build (including tests) of Packages/Core
#   4. swift test of Packages/Core
#
# Usage: scripts/check-core.sh [--lint-only]
#   --lint-only   run steps 1-2 only (for machines without a Swift toolchain)
# Exit: 0 when every step passed, non-zero otherwise.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core_dir="$repo_root/Packages/Core"

lint_only=false
case "${1:-}" in
  "") ;;
  --lint-only) lint_only=true ;;
  -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
  *) echo "check-core: unknown option '$1' (try --help)" >&2; exit 2 ;;
esac

step() { printf '\n==> %s\n' "$1"; }

step "Lint self-tests"
"$repo_root/scripts/tests/test-lints.sh"

for lint in "$repo_root"/scripts/lint-*.sh; do
  step "$(basename "$lint")"
  "$lint"
done

if [[ "$lint_only" == true ]]; then
  printf '\ncheck-core: lints OK (Swift build and tests skipped: --lint-only)\n'
  exit 0
fi

if ! command -v swift >/dev/null 2>&1; then
  cat >&2 <<'MSG'

check-core: no Swift toolchain on PATH, so Core was NOT built or tested.
  - Try scripts/bootstrap-swift-linux.sh (best-effort; often blocked in cloud sessions), or
  - rely on CI (.github/workflows/core-linux.yml) as the verification of record, and
  - run scripts/check-core.sh --lint-only to check the lints locally.
MSG
  exit 1
fi

step "swift --version"
swift --version

step "swift build (Packages/Core, including tests)"
swift build --package-path "$core_dir" --build-tests

step "swift test (Packages/Core)"
swift test --package-path "$core_dir" --skip-build

printf '\ncheck-core: all checks passed\n'
