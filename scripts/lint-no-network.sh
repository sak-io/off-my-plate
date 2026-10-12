#!/usr/bin/env bash
# lint-no-network.sh: no network code ships in v1 (ADR 0002, AC-13.2, ADR 0014).
#
# Scans every Swift file, Package.swift and XcodeGen project.yml under Packages/ and App/
# (sources AND tests) and fails when it finds:
#   1. an import (with any attributes, Swift 6 access level or import kind) of a
#      networking, web or cloud framework (Network, NetworkExtension, CFNetwork,
#      FoundationNetworking, WebKit, SafariServices, MultipeerConnectivity, CloudKit;
#      CloudKit sync is deferred, ADR 0015) or of a known analytics / crash / HTTP SDK;
#   2. a networking API symbol (URLSession*, URLRequest, NSURLRequest, NSMutableURLRequest,
#      NSURLConnection, NWConnection, NWListener, NWBrowser, NWPathMonitor, NWEndpoint,
#      CFSocket, CFStreamCreatePairWithSocket, getStreamsToHost, WKWebView,
#      SFSafariViewController, ASWebAuthenticationSession);
#   3. a remote dependency in a SwiftPM manifest (Package.swift, Package@swift-*.swift):
#      any `url: "` or registry `id: "` argument, whatever line it is on, so multi-line
#      `.package(\n url:`, `.package(name:url:)`, `.package(id:)` and remote
#      `.binaryTarget(url:)` are all caught (local `.package(path:)` is fine);
#   4. a remote package in an XcodeGen spec (project.yml / project.yaml): any `url:` or
#      `github:` key, block or flow style.
# Whole-line comments (//, ///, /*, *) are ignored. There is deliberately no inline
# "allow" escape hatch: change this script in a reviewed PR if a real need appears.
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

scan_dirs=()
for d in Packages App; do
  [[ -d "$root/$d" ]] && scan_dirs+=("$root/$d")
done
if [[ ${#scan_dirs[@]} -eq 0 ]]; then
  echo "lint-no-network: nothing to scan (no Packages/ or App/ under '$root')" >&2
  exit 2
fi

violations=0
report() {
  echo "$1" >&2
  violations=$((violations + 1))
}

comment_re='^[[:space:]]*(//|/\*|\*)'

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
    report "$file:$line: $message: $(printf '%s' "$text" | sed -E 's/^[[:space:]]+//')"
  done < <(grep -rnE "${includes[@]}" --exclude-dir=.build --exclude-dir=DerivedData \
             "$regex" "${scan_dirs[@]}" || true)
}

banned_modules='Network|NetworkExtension|CFNetwork|FoundationNetworking|WebKit|SafariServices|MultipeerConnectivity|CloudKit'
banned_sdks='Firebase[A-Za-z]*|Crashlytics|Sentry[A-Za-z]*|Amplitude[A-Za-z]*|Mixpanel|Segment|Bugsnag|AppCenter[A-Za-z]*|Datadog[A-Za-z]*|Alamofire|Moya'
import_re="^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?($banned_modules|$banned_sdks)([.[:space:]]|$)"
scan "$import_re" "network/web/analytics framework import is not allowed (ADR 0002, AC-13.2)" '*.swift'

symbols='URLSession|NSURLSession|URLRequest|NSURLRequest|NSMutableURLRequest|NSURLConnection|NWConnection|NWListener|NWBrowser|NWPathMonitor|NWEndpoint|CFSocket|CFStreamCreatePairWithSocket|getStreamsToHost|WKWebView|SFSafariViewController|ASWebAuthenticationSession'
symbol_re="(^|[^A-Za-z0-9_])($symbols)"
scan "$symbol_re" "networking API is not allowed (ADR 0002, AC-13.2)" '*.swift'

scan '(^|[^A-Za-z0-9_])(url|id)[[:space:]]*:[[:space:]]*"' \
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
