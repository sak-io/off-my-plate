#!/usr/bin/env bash
# lint-ui-test-hooks.sh: UI-test launch hooks must not exist in Release builds (security audit M2).
#
# Fails when the text `OMPUITest` (the prefix of the `-OMPUITestSeed|Inbox|Speech` launch
# arguments) appears in a Swift file under Packages/ or App/ outside a plain `#if DEBUG` region
# (the `#else` / `#elseif` branch of it does not count; `#if !DEBUG` does not count; a nested
# `#if` inside a DEBUG region does). Test code is not scanned, because it is never linked into
# the app: any directory named `Tests`, `*Tests` (App/OffMyPlateUITests) and SwiftPM manifests
# (Package*.swift). Whole-line // comments are ignored (they never reach the binary).
# This is a cheap Linux check; the macOS CI job `release-hygiene` proves it on the built Release
# binary with `strings`.
#
# Usage: scripts/lint-ui-test-hooks.sh [ROOT_DIR]   (default: repository root)
# Exit:  0 clean, 1 violations found, 2 usage error.
# Portable: bash 3.2+, POSIX find/awk (Linux CI and macOS).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="${1:-$repo_root}"
if [[ ! -d "$root" ]]; then
  echo "lint-ui-test-hooks: '$root' is not a directory" >&2
  exit 2
fi
root="$(cd "$root" && pwd)"

scan_dirs=()
for d in Packages App; do
  [[ -d "$root/$d" ]] && scan_dirs+=("$root/$d")
done
if [[ ${#scan_dirs[@]} -eq 0 ]]; then
  echo "lint-ui-test-hooks: nothing to scan (no Packages/ or App/ under '$root')" >&2
  exit 2
fi

violations=0
while IFS= read -r file; do
  rel="${file#"$root"/}"
  # Test code and manifests never ship in the app binary.
  case "/$rel" in
    */Tests/*|*Tests/*|*/Package*.swift|*/.build/*|*/DerivedData/*) continue ;;
  esac
  out="$(awk -v rel="$rel" '
    function active(   i) { for (i = 1; i <= depth; i++) if (dbg[i]) return 1; return 0 }
    {
      line = $0
      if (line ~ /^[ \t]*#if[ \t]+DEBUG[ \t]*(\/\/.*)?$/) { depth++; dbg[depth] = 1; next }
      if (line ~ /^[ \t]*#if([ \t(!]|$)/) { depth++; dbg[depth] = 0; next }
      if (line ~ /^[ \t]*#(else|elseif)([ \t(]|$)/) { if (depth > 0) dbg[depth] = 0; next }
      if (line ~ /^[ \t]*#endif/) { if (depth > 0) depth--; next }
      if (line ~ /^[ \t]*\/\//) next
      if (index(line, "OMPUITest") > 0 && !active()) {
        sub(/^[ \t]+/, "", line)
        printf "%s:%d: OMPUITest hook outside a #if DEBUG region (Release builds must not contain it): %s\n", rel, NR, line
      }
    }
  ' "$file")"
  if [[ -n "$out" ]]; then
    echo "$out" >&2
    violations=$((violations + $(printf '%s\n' "$out" | wc -l)))
  fi
done < <(find "${scan_dirs[@]}" -name '*.swift' -type f | LC_ALL=C sort)

if [[ "$violations" -gt 0 ]]; then
  echo "lint-ui-test-hooks: FAILED with $violations violation(s)" >&2
  exit 1
fi
echo "lint-ui-test-hooks: OK (${scan_dirs[*]})"
