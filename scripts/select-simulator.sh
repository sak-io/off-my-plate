#!/usr/bin/env bash
# select-simulator.sh: print the UDID of an available iOS simulator for CI (apple-macos.yml).
#
# Runner images change their simulator runtimes and device names over time, so CI does not
# hardcode "OS=18.x". Instead it reads `xcrun simctl list -j devices available` and picks:
#   1. a device named exactly PREFERRED_NAME, on the newest iOS runtime >= MIN_IOS that has
#      one; otherwise
#   2. the first device (by name) of FAMILY on the newest iOS runtime >= MIN_IOS, with a
#      GitHub Actions ::warning:: saying the preferred device was missing.
# Only devices marked available are considered. Non-iOS runtimes are ignored.
#
# Usage: scripts/select-simulator.sh FAMILY PREFERRED_NAME [MIN_IOS]
#   FAMILY          iphone | ipad
#   PREFERRED_NAME  e.g. "iPhone 16", "iPad (A16)"
#   MIN_IOS         minimum iOS major version (default 18, the deployment target, ADR 0001)
# Env:  SIMCTL_JSON=FILE reads the device list from FILE instead of running xcrun (tests).
# Out:  stdout: the UDID only (use as -destination "id=<UDID>"); stderr: what was chosen.
# Exit: 0 found, 1 no matching simulator, 2 usage error or unreadable device list.
set -euo pipefail

family="${1:-}"
preferred="${2:-}"
min_ios="${3:-18}"
case "$family" in
  iphone|ipad) ;;
  *) echo "select-simulator: usage: $0 iphone|ipad PREFERRED_NAME [MIN_IOS]" >&2; exit 2 ;;
esac
if [[ -z "$preferred" ]] || ! [[ "$min_ios" =~ ^[0-9]+$ ]]; then
  echo "select-simulator: usage: $0 iphone|ipad PREFERRED_NAME [MIN_IOS]" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "select-simulator: python3 is required" >&2
  exit 2
fi

list="$(mktemp)"
trap 'rm -f "$list"' EXIT
if [[ -n "${SIMCTL_JSON:-}" ]]; then
  [[ -f "$SIMCTL_JSON" ]] || { echo "select-simulator: SIMCTL_JSON '$SIMCTL_JSON' not found" >&2; exit 2; }
  cp "$SIMCTL_JSON" "$list"
elif ! xcrun simctl list -j devices available > "$list"; then
  echo "select-simulator: 'xcrun simctl list' failed" >&2
  exit 2
fi

# -I: isolated mode (ignores PYTHON* variables and the current directory). Written for
# Python 3.9+ (the macOS system python3).
python3 -I - "$family" "$preferred" "$min_ios" "$list" <<'PY'
import json
import re
import sys

family, preferred, min_ios, path = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
try:
    with open(path, encoding="utf-8") as handle:
        devices = json.load(handle)["devices"]
    runtime_items = list(devices.items())
except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
    print("select-simulator: cannot read the simulator list: %s" % error, file=sys.stderr)
    sys.exit(2)

runtime_re = re.compile(r"^com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+)-(\d+)(?:-(\d+))?$")
prefix = "iPhone" if family == "iphone" else "iPad"

runtimes = []  # (version tuple, label, usable devices)
for runtime_id, entries in runtime_items:
    match = runtime_re.match(runtime_id)
    if not match or not isinstance(entries, list):
        continue
    version = tuple(int(part) if part else 0 for part in match.groups())
    if version[0] < min_ios:
        continue
    usable = [
        d for d in entries
        if isinstance(d, dict)
        and d.get("isAvailable", True) is True
        and d.get("udid")
        and str(d.get("name", "")).startswith(prefix)
    ]
    if usable:
        label = "iOS %d.%d" % (version[0], version[1])
        if version[2]:
            label += ".%d" % version[2]
        runtimes.append((version, label, usable))

if not runtimes:
    print("select-simulator: no available %s simulator on iOS %d or later" % (prefix, min_ios),
          file=sys.stderr)
    sys.exit(1)

runtimes.sort(key=lambda runtime: runtime[0], reverse=True)


def report(device, label):
    print("select-simulator: %s (%s) %s" % (device["name"], label, device["udid"]), file=sys.stderr)
    print(device["udid"])


for version, label, usable in runtimes:
    exact = sorted((d for d in usable if d["name"] == preferred), key=lambda d: d["udid"])
    if exact:
        report(exact[0], label)
        sys.exit(0)

version, label, usable = runtimes[0]
chosen = sorted(usable, key=lambda d: (d["name"], d["udid"]))[0]
print('::warning::select-simulator: no available "%s" simulator; falling back to %s (%s)'
      % (preferred, chosen["name"], label), file=sys.stderr)
report(chosen, label)
PY
