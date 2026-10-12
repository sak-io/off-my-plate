#!/usr/bin/env bash
# bootstrap-swift-linux.sh: OPTIONAL, best-effort Swift toolchain for Linux sessions.
#
# Nothing in the project depends on this script: CI (.github/workflows/core-linux.yml)
# is the verification of record (plan section 9, ADR 0005). It makes one attempt each:
#   1. the official swift.org tarball for Ubuntu 24.04, verified with the swift.org
#      PGP keys (an unverified toolchain is never installed). It is extracted into a
#      staging directory next to the install directory and renamed into place only when
#      complete, so an interrupted or failed run never leaves a half-installed toolchain;
#   2. the official Docker Hub image swift:<version>-noble, if a Docker daemon is
#      running or can be started. A pull that is rate-limited (HTTP 429) is retried once
#      after a back-off. A dockerd this script started is stopped again on every path
#      except a successful pull (then it stays up for `docker run`, and its PID is printed).
# When both are blocked (the normal case in a locked-down cloud session, where
# download.swift.org returns 403) it prints what happened and exits 0.
#
# Usage: scripts/bootstrap-swift-linux.sh
# Environment:
#   OMP_SWIFT_VERSION     Swift release to fetch            (default: 6.2, matches CI)
#   OMP_SWIFT_DIR         install directory for option 1    (default: $HOME/.omp-swift)
#   OMP_SKIP_DOCKER=1     do not try option 2
#   OMP_PULL_RETRY_DELAY  seconds to wait before retrying a 429 pull (default: 30)
#   OMP_DOCKERD_WAIT      seconds to wait for a started dockerd    (default: 20)
#   OMP_OS_RELEASE        os-release file to read               (default: /etc/os-release)
#   OMP_DOCKERD_LOG       log file for a dockerd it starts      (default: /tmp/omp-dockerd.log)
#   OMP_IGNORE_SWIFT_ON_PATH=1  act as if no swift is on PATH (used by the tests, which
#                               run inside the swift CI image)
# Always exits 0; read the last line to see the outcome.
# Tested hermetically (fake curl/gpg/docker/dockerd) by scripts/tests/test-bootstrap.sh.
set -uo pipefail

version="${OMP_SWIFT_VERSION:-6.2}"
install_dir="${OMP_SWIFT_DIR:-$HOME/.omp-swift}"
install_dir="${install_dir%/}"
image="swift:${version}-noble"
pull_retry_delay="${OMP_PULL_RETRY_DELAY:-30}"
dockerd_wait="${OMP_DOCKERD_WAIT:-20}"
os_release="${OMP_OS_RELEASE:-/etc/os-release}"
dockerd_log="${OMP_DOCKERD_LOG:-/tmp/omp-dockerd.log}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

say() { printf 'bootstrap-swift-linux: %s\n' "$*"; }
finish() { say "$1"; exit 0; }

# ------------------------------------------------------- dockerd started by this script
started_dockerd_pid=""
keep_dockerd=false

stop_started_dockerd() {
  [[ -n "$started_dockerd_pid" ]] || return 0
  local pid="$started_dockerd_pid"
  started_dockerd_pid=""
  kill -TERM "$pid" 2>/dev/null || true
  local i
  for ((i = 0; i < 15; i++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
  say "docker: stopped the dockerd this script started (pid $pid)."
}

on_exit() {
  if [[ "$keep_dockerd" != true ]]; then
    stop_started_dockerd
  fi
}
trap on_exit EXIT
trap 'exit 130' INT TERM

if [[ "$(uname -s)" != "Linux" ]]; then
  finish "not Linux; on macOS use Xcode's toolchain (xcode-select -p). Nothing to do."
fi

if [[ "${OMP_IGNORE_SWIFT_ON_PATH:-}" != "1" ]] && command -v swift >/dev/null 2>&1; then
  finish "Swift is already on PATH: $(swift --version 2>&1 | head -n 1)"
fi

if [[ -x "$install_dir/usr/bin/swift" ]]; then
  finish "Swift already installed. Add it to PATH: export PATH=\"$install_dir/usr/bin:\$PATH\""
fi

# ---------------------------------------------------------------- option 1: tarball
try_tarball() {
  local tmp rc
  if ! tmp="$(mktemp -d 2>/dev/null)" || [[ -z "$tmp" || ! -d "$tmp" ]]; then
    say "tarball: could not create a temporary directory (check TMPDIR and free space)."
    return 1
  fi
  tarball_steps "$tmp"
  rc=$?
  rm -rf "$tmp"
  return "$rc"
}

# Runs in a subshell so GNUPGHOME, traps and other state never leak. $1 = scratch dir.
tarball_steps() (
  tmp="$1"
  staging=""
  # Removes a staging directory left by a failure or an interrupt. After the final
  # rename the path no longer exists, so this is a no-op on success.
  trap '[[ -n "$staging" ]] && rm -rf "$staging"' EXIT

  os_id=""
  os_version=""
  if [[ -r "$os_release" ]]; then
    os_id="$(. "$os_release" && printf '%s' "${ID:-}")"
    os_version="$(. "$os_release" && printf '%s' "${VERSION_ID:-}")"
  fi
  if [[ "$os_id" != "ubuntu" || "$os_version" != "24.04" ]]; then
    say "tarball: only Ubuntu 24.04 is supported by this script (found '$os_id $os_version')."
    return 1
  fi
  for tool in curl tar gpg; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      say "tarball: '$tool' is not installed."
      return 1
    fi
  done

  # Refuse to touch an existing, non-empty directory that is not a complete toolchain.
  if [[ -e "$install_dir" ]]; then
    if [[ -d "$install_dir" ]] && rmdir "$install_dir" 2>/dev/null; then
      : # it was an empty directory; the rename below recreates it
    else
      say "tarball: '$install_dir' exists but holds no usr/bin/swift; remove it or set OMP_SWIFT_DIR."
      return 1
    fi
  fi

  arch="$(uname -m)"
  case "$arch" in
    x86_64)  suffix="";         platform="ubuntu2404" ;;
    aarch64) suffix="-aarch64"; platform="ubuntu2404-aarch64" ;;
    *) say "tarball: unsupported CPU architecture '$arch'."; return 1 ;;
  esac
  dir="swift-${version}-RELEASE"
  base="${dir}-ubuntu24.04${suffix}"
  url="https://download.swift.org/swift-${version}-release/${platform}/${dir}/${base}.tar.gz"

  # curl --retry also retries HTTP 429 and 5xx, with exponential back-off.
  say "tarball: downloading $url"
  if ! curl -fsSL --retry 2 --connect-timeout 15 -o "$tmp/swift.tar.gz" "$url" \
     || ! curl -fsSL --retry 2 --connect-timeout 15 -o "$tmp/swift.tar.gz.sig" "$url.sig" \
     || ! curl -fsSL --retry 2 --connect-timeout 15 -o "$tmp/keys.asc" "https://swift.org/keys/all-keys.asc"; then
    say "tarball: download failed (download.swift.org is blocked in many cloud sessions)."
    return 1
  fi

  export GNUPGHOME="$tmp/gnupg"
  mkdir -m 700 "$GNUPGHOME"
  if ! gpg --batch --quiet --import "$tmp/keys.asc" 2>/dev/null \
     || ! gpg --batch --quiet --verify "$tmp/swift.tar.gz.sig" "$tmp/swift.tar.gz" 2>/dev/null; then
    say "tarball: PGP signature verification FAILED; refusing to install an unverified toolchain."
    return 1
  fi

  # Atomic install: extract next to the target (same filesystem), check, then rename.
  parent="$(dirname "$install_dir")"
  if ! mkdir -p "$parent" \
     || ! staging="$(mktemp -d "$parent/.omp-swift-staging.XXXXXX" 2>/dev/null)" \
     || [[ -z "$staging" ]]; then
    staging=""
    say "tarball: could not create a staging directory in '$parent'."
    return 1
  fi
  if ! tar -xzf "$tmp/swift.tar.gz" -C "$staging" --strip-components=1; then
    say "tarball: extraction failed; nothing was installed."
    return 1
  fi
  if [[ ! -x "$staging/usr/bin/swift" ]]; then
    say "tarball: the archive has no usr/bin/swift; nothing was installed."
    return 1
  fi
  if ! mv "$staging" "$install_dir"; then
    say "tarball: could not move the toolchain into '$install_dir'; nothing was installed."
    return 1
  fi
  staging=""
  say "tarball: installed Swift $version to $install_dir (signature verified)."
  say "Some system libraries may be missing; see https://www.swift.org/install/linux/ for the list."
  say "Next: export PATH=\"$install_dir/usr/bin:\$PATH\" && scripts/check-core.sh"
  return 0
)

# ---------------------------------------------------------------- option 2: Docker
docker_running() { docker info >/dev/null 2>&1; }

# Pulls the image; retries once after a back-off when Docker Hub rate-limits (429).
pull_image() {
  local attempt out
  for attempt in 1 2; do
    if out="$(docker pull "$image" 2>&1)"; then
      printf '%s\n' "$out"
      return 0
    fi
    printf '%s\n' "$out"
    if [[ "$attempt" -eq 1 ]] && grep -qiE 'toomanyrequests|429|rate limit' <<<"$out"; then
      say "docker: rate-limited by the registry (HTTP 429); retrying once in ${pull_retry_delay}s."
      sleep "$pull_retry_delay"
      continue
    fi
    return 1
  done
  return 1
}

try_docker() {
  if [[ "${OMP_SKIP_DOCKER:-}" == "1" ]]; then
    say "docker: skipped (OMP_SKIP_DOCKER=1)."
    return 1
  fi
  if ! command -v docker >/dev/null 2>&1; then
    say "docker: the docker CLI is not installed."
    return 1
  fi
  if ! docker_running; then
    if [[ "$(id -u)" -eq 0 ]] && command -v dockerd >/dev/null 2>&1; then
      say "docker: daemon not running; trying to start dockerd (log: $dockerd_log)."
      nohup dockerd >"$dockerd_log" 2>&1 &
      started_dockerd_pid=$!
      local i
      for ((i = 0; i < dockerd_wait; i++)); do
        docker_running && break
        sleep 1
      done
      if ! docker_running; then
        say "docker: dockerd did not start; last log line: $(tail -n 1 "$dockerd_log" 2>/dev/null)"
        stop_started_dockerd
      fi
    fi
    if ! docker_running; then
      say "docker: no Docker daemon is available."
      return 1
    fi
  fi
  say "docker: pulling $image"
  if ! pull_image; then
    say "docker: pulling $image failed (Docker Hub may be blocked)."
    stop_started_dockerd
    return 1
  fi
  if [[ -n "$started_dockerd_pid" ]]; then
    keep_dockerd=true
    say "docker: the dockerd this script started is still running (pid $started_dockerd_pid); stop it with: kill $started_dockerd_pid"
  fi
  say "docker: ready. Run the Core checks inside the container with:"
  say "  docker run --rm -v \"$repo_root\":/src -w /src $image scripts/check-core.sh"
  return 0
}

if try_tarball; then
  finish "done (tarball)."
fi
if try_docker; then
  finish "done (docker image $image)."
fi
finish "could not obtain a Swift toolchain (both options blocked). This is fine: CI is the verifier. Run scripts/check-core.sh --lint-only locally."
