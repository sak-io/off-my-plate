#!/usr/bin/env bash
# test-bootstrap.sh: hermetic tests for scripts/bootstrap-swift-linux.sh.
#
# Fake curl, gpg, docker, dockerd and id are put first on PATH, so no network, no real
# toolchain and no real Docker daemon are ever touched. The fake dockerd is a `sleep`
# process; every case checks that the script leaves none behind unless it says so.
# Covers: exit 0 on every path, signature failure, atomic install (success, corrupt
# archive, interrupted extract leaves nothing), non-empty install dir, mktemp failure,
# dockerd stopped when it never becomes ready and when the pull fails, one retry on 429.
#
# Usage: scripts/tests/test-bootstrap.sh     (Linux only; skips elsewhere)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$(cd "$here/.." && pwd)/bootstrap-swift-linux.sh"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "test-bootstrap: skipped (the bootstrap script only acts on Linux)"
  exit 0
fi

work="$(mktemp -d)"
cleanup() {
  # Belt and braces: never leave a fake dockerd behind, even if a case fails.
  # Every fake dockerd ever started appends its pid to all-dockerd.pids.
  if [[ -f "$work/all-dockerd.pids" ]]; then
    while read -r p; do kill "$p" 2>/dev/null || true; done < "$work/all-dockerd.pids"
  fi
  rm -rf "$work"
}
trap cleanup EXIT

fake="$work/bin"
mkdir -p "$fake"

# ---- fakes -----------------------------------------------------------------
cat > "$fake/curl" <<'EOF'
#!/usr/bin/env bash
# fake curl: -o FILE URL. FAKE_CURL=fail -> exit 22 like a 403.
out=""; url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    --retry|--connect-timeout) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
[[ "${FAKE_CURL:-ok}" == fail ]] && { echo "curl: (22) The requested URL returned error: 403" >&2; exit 22; }
case "$url" in
  *.tar.gz) cp "$FAKE_TARBALL" "$out" ;;
  *) echo "fake" > "$out" ;;
esac
EOF
cat > "$fake/gpg" <<'EOF'
#!/usr/bin/env bash
[[ "${FAKE_GPG:-ok}" == ok ]]
EOF
cat > "$fake/id" <<'EOF'
#!/usr/bin/env bash
echo 0
EOF
cat > "$fake/dockerd" <<'EOF'
#!/usr/bin/env bash
# fake dockerd: becomes "ready" unless FAKE_DOCKERD=never, then idles.
echo $$ > "$FAKE_STATE/dockerd.pid"
echo $$ >> "$FAKE_STATE/../all-dockerd.pids"
[[ "${FAKE_DOCKERD:-ready}" == ready ]] && touch "$FAKE_STATE/dockerd.ready"
exec sleep 300
EOF
cat > "$fake/docker" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  info) [[ -f "$FAKE_STATE/dockerd.ready" ]] ;;
  pull)
    echo pull >> "$FAKE_STATE/pulls"
    case "${FAKE_PULL:-ok}" in
      ok) echo "pulled $2" ;;
      429) echo "Error response from daemon: toomanyrequests: You have reached your pull rate limit" >&2; exit 1 ;;
      *) echo "Error response from daemon: Get https://registry-1.docker.io/v2/: Forbidden" >&2; exit 1 ;;
    esac ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$fake"/*

printf 'ID=ubuntu\nVERSION_ID="24.04"\n' > "$work/os-release"

# A good tarball has a top-level dir containing usr/bin/swift; a corrupt one does not.
mkdir -p "$work/src/good/swift-x/usr/bin" "$work/src/bad/swift-x/usr/lib"
printf '#!/bin/sh\necho fake swift\n' > "$work/src/good/swift-x/usr/bin/swift"
chmod +x "$work/src/good/swift-x/usr/bin/swift"
tar -czf "$work/good.tar.gz" -C "$work/src/good" swift-x
tar -czf "$work/bad.tar.gz" -C "$work/src/bad" swift-x
printf 'not a gzip archive' > "$work/truncated.tar.gz"

passed=0
failed=0
ok()   { echo "  ok   $1"; passed=$((passed + 1)); }
bad()  { echo "  FAIL $1" >&2; printf '%s\n' "$output" | sed 's/^/         /' >&2; failed=$((failed + 1)); }

# run_bootstrap: fresh state, fakes first on PATH, any real swift ignored; output in $output.
run_bootstrap() {
  rm -rf "$work/state" "$work/home"
  mkdir -p "$work/state" "$work/home"
  set +e
  output="$(env -i HOME="$work/home" PATH="$fake:/usr/bin:/bin" TMPDIR="${T_TMPDIR:-$work/tmp}" \
    FAKE_STATE="$work/state" FAKE_TARBALL="${T_TARBALL:-$work/good.tar.gz}" \
    FAKE_CURL="${T_CURL:-ok}" FAKE_GPG="${T_GPG:-ok}" FAKE_DOCKERD="${T_DOCKERD:-ready}" \
    FAKE_PULL="${T_PULL:-ok}" OMP_SKIP_DOCKER="${T_SKIP_DOCKER:-}" \
    OMP_OS_RELEASE="$work/os-release" OMP_SWIFT_DIR="${T_DIR:-$work/home/.omp-swift}" \
    OMP_IGNORE_SWIFT_ON_PATH=1 OMP_PULL_RETRY_DELAY=0 OMP_DOCKERD_WAIT=2 OMP_DOCKERD_LOG="$work/state/dockerd.log" \
    bash "$script" 2>&1)"
  status=$?
  set -e
}
mkdir -p "$work/tmp"

dockerd_gone() {
  [[ -f "$work/state/dockerd.pid" ]] || return 0
  ! kill -0 "$(cat "$work/state/dockerd.pid")" 2>/dev/null
}
no_staging_left() { ! ls -d "$work/home"/.omp-swift-staging.* >/dev/null 2>&1; }

echo "bootstrap-swift-linux.sh"

# 1. tarball success: installed atomically, exit 0
run_bootstrap
if [[ $status -eq 0 && -x "$work/home/.omp-swift/usr/bin/swift" ]] && no_staging_left \
   && grep -q "signature verified" <<<"$output"; then ok "verified tarball installs atomically, exit 0"
else bad "verified tarball installs atomically, exit 0"; fi

# 2. signature failure: nothing installed
T_GPG=fail T_SKIP_DOCKER=1 run_bootstrap
if [[ $status -eq 0 && ! -e "$work/home/.omp-swift" ]] && no_staging_left \
   && grep -q "refusing to install an unverified toolchain" <<<"$output"; then ok "bad signature installs nothing, exit 0"
else bad "bad signature installs nothing, exit 0"; fi

# 3. archive without usr/bin/swift: nothing installed, no staging left
T_TARBALL="$work/bad.tar.gz" T_SKIP_DOCKER=1 run_bootstrap
if [[ $status -eq 0 && ! -e "$work/home/.omp-swift" ]] && no_staging_left \
   && grep -q "has no usr/bin/swift" <<<"$output"; then ok "incomplete archive installs nothing"
else bad "incomplete archive installs nothing"; fi

# 4. extraction fails midway (corrupt archive): nothing installed, no staging left
T_TARBALL="$work/truncated.tar.gz" T_SKIP_DOCKER=1 run_bootstrap
if [[ $status -eq 0 && ! -e "$work/home/.omp-swift" ]] && no_staging_left \
   && grep -q "extraction failed" <<<"$output"; then ok "failed extraction leaves no partial install"
else bad "failed extraction leaves no partial install"; fi

# 5. existing non-empty install dir without swift: left untouched
mkdir -p "$work/keep/.omp-swift"; echo precious > "$work/keep/.omp-swift/file"
T_DIR="$work/keep/.omp-swift" T_SKIP_DOCKER=1 run_bootstrap
if [[ $status -eq 0 && "$(cat "$work/keep/.omp-swift/file")" == precious \
   && ! -e "$work/keep/.omp-swift/usr" ]] && grep -q "exists but holds no usr/bin/swift" <<<"$output"
then ok "non-empty install dir is never overwritten"
else bad "non-empty install dir is never overwritten"; fi

# 6. mktemp failure: clear message, exit 0
T_TMPDIR="$work/does-not-exist" T_SKIP_DOCKER=1 run_bootstrap
if [[ $status -eq 0 ]] && grep -q "could not create a temporary directory" <<<"$output"
then ok "mktemp failure is reported, exit 0"
else bad "mktemp failure is reported, exit 0"; fi

# 7. download blocked + dockerd never ready: dockerd stopped, exit 0
T_CURL=fail T_DOCKERD=never run_bootstrap
if [[ $status -eq 0 ]] && dockerd_gone && grep -q "stopped the dockerd this script started" <<<"$output" \
   && grep -q "could not obtain a Swift toolchain" <<<"$output"; then ok "dockerd that never becomes ready is stopped"
else bad "dockerd that never becomes ready is stopped"; fi

# 8. pull rate-limited twice: exactly one retry, dockerd stopped, exit 0
T_CURL=fail T_PULL=429 run_bootstrap
pulls="$(wc -l < "$work/state/pulls" 2>/dev/null | tr -d ' ' || echo 0)"
if [[ $status -eq 0 && "$pulls" == 2 ]] && dockerd_gone \
   && grep -q "retrying once" <<<"$output" && grep -q "stopped the dockerd this script started" <<<"$output"
then ok "429 pull retried once, then dockerd stopped"
else bad "429 pull retried once, then dockerd stopped (pulls=$pulls)"; fi

# 9. pull forbidden: no retry, dockerd stopped
T_CURL=fail T_PULL=forbidden run_bootstrap
pulls="$(wc -l < "$work/state/pulls" 2>/dev/null | tr -d ' ' || echo 0)"
if [[ $status -eq 0 && "$pulls" == 1 ]] && dockerd_gone; then ok "non-429 pull failure: no retry, dockerd stopped"
else bad "non-429 pull failure: no retry, dockerd stopped (pulls=$pulls)"; fi

# 10. pull succeeds: dockerd deliberately kept running and its PID reported
T_CURL=fail run_bootstrap
pid="$(cat "$work/state/dockerd.pid" 2>/dev/null || echo none)"
if [[ $status -eq 0 ]] && kill -0 "$pid" 2>/dev/null && grep -q "still running (pid $pid)" <<<"$output"
then ok "successful pull keeps the started dockerd and reports its pid"
else bad "successful pull keeps the started dockerd and reports its pid"; fi
kill "$pid" 2>/dev/null || true

echo "test-bootstrap: $passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
