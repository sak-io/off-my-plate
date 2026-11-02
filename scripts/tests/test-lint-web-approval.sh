#!/usr/bin/env bash
# test-lint-web-approval.sh: proves lint-web-approval.sh passes on the real web app and fails on planted
# violations (each case copies the real app into a temp dir and breaks one rule).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lint="$here/../lint-web-approval.sh"
repo="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
passed=0; failed=0

fresh() {  # copies the real app sources into $tmp/case
  rm -rf "$tmp/case"; mkdir -p "$tmp/case/platforms/web/app"
  cp -R "$repo/platforms/web/app/src" "$tmp/case/platforms/web/app/src"
  [[ -d "$repo/platforms/web/app/tests" ]] && cp -R "$repo/platforms/web/app/tests" "$tmp/case/platforms/web/app/tests"
  return 0
}
expect() {  # label, expected exit, expected text
  local out status
  set +e; out="$("$lint" "$tmp/case" 2>&1)"; status=$?; set -e
  if [[ "$status" -eq "$2" && ( -z "${3:-}" || "$out" == *"$3"* ) ]]; then echo "  ok   $1"; passed=$((passed + 1))
  else echo "  FAIL $1 (exit $status, wanted $2 ${3:-})" >&2; echo "$out" | sed 's/^/         /' >&2; failed=$((failed + 1)); fi
}
app="$tmp/case/platforms/web/app"

fresh; expect "real app is clean" 0 "ok"
fresh; printf 'export const x = host.op("plan.approve", {});\n' > "$app/src/screens/plan.ts"; expect "approve op in another file" 1 "outside"
fresh; printf 'const t = "plan.approve";\n' > "$app/src/other.ts"; expect "approve op in a new file" 1 "the approve operation outside"
fresh; mkdir -p "$app/tests"; printf 'await op("plan.approve");\n' > "$app/tests/x.spec.ts"; expect "approve op in a test" 1 "outside"
fresh; printf '// plan.approve\n' >> "$app/src/screens/plan-approve-button.ts"; expect "approve op twice in the call-site file" 1 "exactly once"
fresh; printf 'const g = "confirm-button";\n' > "$app/src/g.ts"; expect "gesture string elsewhere" 1 "gesture"
fresh; printf 'import { createApproveButton } from "./screens/plan-approve-button.js";\n' > "$app/src/m.ts"; expect "button factory used elsewhere" 1 "createApproveButton"
fresh; printf 'const c = new UserConfirmation();\n' > "$app/src/u.ts"; expect "UserConfirmation in the app" 1 "UserConfirmation"
fresh; printf 'el.innerHTML = data;\n' > "$app/src/i.ts"; expect "innerHTML" 1 "HTML injection"
fresh; printf 'const f = h("form", {});\n' > "$app/src/screens/f.ts"; expect "form in screens" 1 "form submit"
fresh; printf '// innerHTML is banned\n' > "$app/src/c.ts"; expect "comment mentioning innerHTML is fine" 0 "ok"
set +e; "$lint" "$tmp/nonexistent" >/dev/null 2>&1; s=$?; set -e
if [[ $s -eq 2 ]]; then echo "  ok   missing dir is a usage error"; passed=$((passed + 1)); else echo "  FAIL missing dir (exit $s)" >&2; failed=$((failed + 1)); fi
echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
