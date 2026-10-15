#!/usr/bin/env bash
# lint-no-network.sh: no network code ships in v1 (ADR 0002, AC-13.2, ADR 0014).
#
# Scans every Swift file, Package.swift and XcodeGen project.yml under Packages/ and App/
# (sources AND tests) and fails when it finds:
#   1. an import (with any attributes, Swift 6 access level or import kind; also after a
#      `;` or a closed /* */ comment on the same line) of a
#      networking, web or cloud framework (Network, NetworkExtension, CFNetwork,
#      FoundationNetworking, WebKit, SafariServices, MultipeerConnectivity, CloudKit;
#      CloudKit sync is deferred, ADR 0015) or of a known analytics / crash / HTTP SDK;
#   2. a networking API symbol (URLSession*, URLRequest, NSURLRequest, NSMutableURLRequest,
#      NSURLConnection, NWConnection, NWListener, NWBrowser, NWPathMonitor, NWEndpoint,
#      CFSocket, CFStreamCreatePairWithSocket, getStreamsToHost, WKWebView,
#      SFSafariViewController, ASWebAuthenticationSession);
#   3. a remote dependency in a SwiftPM manifest (Package.swift, Package@swift-*.swift):
#      any `url:` or registry `id:` argument, whatever line it is on and whatever its
#      value (string literal, raw string, variable), so multi-line `.package(\n url:`,
#      `.package(name:url:)`, `.package(url: someVar)`, `.package(id:)` and remote
#      `.binaryTarget(url:)` are all caught (local `.package(path:)` is fine);
#   4. a remote package in an XcodeGen spec (project.yml / project.yaml): any `url:` or
#      `github:` key, block or flow style.
# Whole-line comments (//, ///, /*, *) are ignored. There is deliberately no inline
# "allow" escape hatch: change this script in a reviewed PR if a real need appears.
#
# Fail-safe by design: this is text matching, not a parser, so a banned name inside a
# string literal may be reported (a false positive); it is never silently skipped.
#
# Usage: scripts/lint-no-network.sh [ROOT_DIR]   (default: repository root)
# Exit:  0 clean, 1 violations found, 2 usage error.
# Portable: bash 3.2+, POSIX grep/sed (works on Linux CI and macOS).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="${1:-$repo_root}"

if [[ ! -d "$root" ]]; then
  echo "lint-no-network: '$root' is not a directory" >&2
  exit 2
fi
root="$(cd "$root" && pwd)"

scan_dirs=()
for d in Packages App; do
  [[ -d "$root/$d" ]] && scan_dirs+=("$root/$d")
done
if [[ ${#scan_dirs[@]} -eq 0 ]]; then
  echo "lint-no-network: nothing to scan (no Packages/ or App/ under '$root')" >&2
  exit 2
fi

violations=0
skip_file=""
only_file=""
report() {
  echo "$1" >&2
  violations=$((violations + 1))
}

closed_comment='/\*([^*]|\*+[^*/])*\*+/'
# Whole-line comments: //, /// and * continuation lines, a /* that stays open, and a
# line that is nothing but closed /* */ comments. Code after a closed comment is checked.
comment_re="^[[:space:]]*(//|\\*|/\\*([^*]|\\*+[^*/])*\\**\$|(${closed_comment}[[:space:]]*)+\$)"

# hit = file:line:text ; prints violations for non-comment lines.
scan() { # regex, message, include-glob...
  local regex="$1" message="$2" hit file rest line text glob
  shift 2
  local includes=()
  for glob in "$@"; do
    includes+=("--include=$glob")
  done
  while IFS= read -r hit; do
    file="${hit%%:*}"
    rest="${hit#*:}"
    line="${rest%%:*}"
    text="${rest#*:}"
    if printf '%s\n' "$text" | grep -qE "$comment_re"; then
      continue
    fi
    if [[ -n "$skip_file" && "$file" == "$skip_file" ]]; then
      continue
    fi
    if [[ -n "$only_file" && "$file" != "$only_file" ]]; then
      continue
    fi
    report "$file:$line: $message: $(printf '%s' "$text" | sed -E 's/^[[:space:]]+//')"
  done < <(grep -rnE "${includes[@]}" --exclude-dir=.build --exclude-dir=DerivedData \
             "$regex" "${scan_dirs[@]}" || true)
}

banned_modules='Network|NetworkExtension|CFNetwork|FoundationNetworking|WebKit|SafariServices|MultipeerConnectivity|CloudKit'
banned_sdks='Firebase[A-Za-z]*|Crashlytics|Sentry[A-Za-z]*|Amplitude[A-Za-z]*|Mixpanel|Segment|Bugsnag|AppCenter[A-Za-z]*|Datadog[A-Za-z]*|Alamofire|Moya'
import_re="(^|;)[[:space:]]*(${closed_comment}[[:space:]]*)*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?($banned_modules|$banned_sdks)([.[:space:]]|$)"
scan "$import_re" "network/web/analytics framework import is not allowed (ADR 0002, AC-13.2)" '*.swift'

symbols='URLSession|NSURLSession|URLRequest|NSURLRequest|NSMutableURLRequest|NSURLConnection|NWConnection|NWListener|NWBrowser|NWPathMonitor|NWEndpoint|CFSocket|CFStreamCreatePairWithSocket|getStreamsToHost|WKWebView|SFSafariViewController|ASWebAuthenticationSession'
symbol_re="(^|[^A-Za-z0-9_])($symbols)"
# One reviewed exception (T28, AC-13.2): the DEBUG-only network-denial probe must name
# `URLRequest` because `URLProtocol.canInit(with:)` takes one. That single file is exempt from
# the URLRequest symbol ONLY (every other symbol is still banned there); no other file is.
probe_rel="App/OffMyPlate/DebugNetworkDenial.swift"
symbols_probe='URLSession|NSURLSession|NSURLRequest|NSMutableURLRequest|NSURLConnection|NWConnection|NWListener|NWBrowser|NWPathMonitor|NWEndpoint|CFSocket|CFStreamCreatePairWithSocket|getStreamsToHost|WKWebView|SFSafariViewController|ASWebAuthenticationSession'
symbol_probe_re="(^|[^A-Za-z0-9_])($symbols_probe|WebSocket)|https?://"
# First pass: every file but the probe. Second pass: the probe, without URLRequest.
skip_file="$root/$probe_rel"
scan "$symbol_re" "networking API is not allowed (ADR 0002, AC-13.2)" '*.swift'
skip_file=""
if [[ -f "$root/$probe_rel" ]]; then
  only_file="$root/$probe_rel"
  scan "$symbol_probe_re" "networking API is not allowed (ADR 0002, AC-13.2)" '*.swift'
  only_file=""
  # The probe must be Debug-only: wrapped in #if DEBUG ... #endif, and every use of its symbols in
  # App/OffMyPlate must sit inside #if DEBUG too, so it can never reach a Release build.
  probe="$root/$probe_rel"
  first="$(grep -vE '^[[:space:]]*(//.*)?$' "$probe" | head -n 1 | sed -E 's/[[:space:]]+$//')"
  last="$(grep -vE '^[[:space:]]*(//.*)?$' "$probe" | tail -n 1 | sed -E 's/[[:space:]]+$//')"
  if [[ "$first" != "#if DEBUG" || "$last" != "#endif" ]]; then
    report "$probe:1: the network-denial probe must be wrapped in #if DEBUG ... #endif"
  fi
  for user in "$root"/App/OffMyPlate/*.swift; do
    [[ "$user" == "$probe" ]] && continue
    awk -v f="$user" '
      /^[[:space:]]*#if[[:space:]]+DEBUG[[:space:]]*$/ { d++; st[d]=1; next }
      /^[[:space:]]*#if/ { d++; st[d]=0; next }
      /^[[:space:]]*#else/ { if (d>0) st[d]=0; next }
      /^[[:space:]]*#endif/ { if (d>0) d--; next }
      /^[[:space:]]*\/\// { next }
      /DebugNetworkDenial|DebugNetworkAttemptsProbe/ {
        ok=0; for (i=1;i<=d;i++) if (st[i]) ok=1
        if (!ok) { printf "%s:%d: probe symbol used outside #if DEBUG\n", f, NR > "/dev/stderr"; bad=1 }
      }
      END { exit bad }' "$user" || violations=$((violations + 1))
  done
fi

scan '(^|[^A-Za-z0-9_])(url|id)[[:space:]]*:' \
  "remote dependency in a package manifest is not allowed (zero third-party packages)" \
  'Package.swift' 'Package@swift-*.swift'
scan '(^|[^A-Za-z0-9_])(url|github)[[:space:]]*:' \
  "remote package in an XcodeGen spec is not allowed (zero third-party packages)" \
  'project.yml' 'project.yaml'

if [[ "$violations" -gt 0 ]]; then
  echo "lint-no-network: FAILED with $violations violation(s)" >&2
  exit 1
fi
echo "lint-no-network: OK (${scan_dirs[*]})"
