#!/usr/bin/env bash
# bootstrap-swift-linux.sh: OPTIONAL, best-effort Swift toolchain for Linux sessions.
#
# Nothing in the project depends on this script: CI (.github/workflows/core-linux.yml)
# is the verification of record (plan section 9, ADR 0005). It makes one attempt each:
#   1. the official swift.org tarball for Ubuntu 24.04, verified with the swift.org
#      PGP keys (an unverified toolchain is never installed);
#   2. the official Docker Hub image swift:<version>-noble, if a Docker daemon is
#      running or can be started.
# When both are blocked (the normal case in a locked-down cloud session, where
# download.swift.org returns 403) it prints what happened and exits 0.
#
# Usage: scripts/bootstrap-swift-linux.sh
# Environment:
#   OMP_SWIFT_VERSION   Swift release to fetch          (default: 6.2, matches CI)
#   OMP_SWIFT_DIR       install directory for option 1  (default: $HOME/.omp-swift)
#   OMP_SKIP_DOCKER=1   do not try option 2
# Always exits 0; read the last line to see the outcome.
set -uo pipefail

version="${OMP_SWIFT_VERSION:-6.2}"
install_dir="${OMP_SWIFT_DIR:-$HOME/.omp-swift}"
image="swift:${version}-noble"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

say() { printf 'bootstrap-swift-linux: %s\n' "$*"; }
finish() { say "$1"; exit 0; }

if [[ "$(uname -s)" != "Linux" ]]; then
  finish "not Linux; on macOS use Xcode's toolchain (xcode-select -p). Nothing to do."
fi

if command -v swift >/dev/null 2>&1; then
  finish "Swift is already on PATH: $(swift --version 2>&1 | head -n 1)"
fi

if [[ -x "$install_dir/usr/bin/swift" ]]; then
  finish "Swift already installed. Add it to PATH: export PATH=\"$install_dir/usr/bin:\$PATH\""
fi

# ---------------------------------------------------------------- option 1: tarball
try_tarball() {
  local tmp rc
  tmp="$(mktemp -d)"
  tarball_steps "$tmp"
  rc=$?
  rm -rf "$tmp"
  return "$rc"
}

# Runs in a subshell so GNUPGHOME and other state never leak. $1 = scratch directory.
tarball_steps() (
  tmp="$1"
  os_id=""
  os_version=""
  if [[ -r /etc/os-release ]]; then
    os_id="$(. /etc/os-release && printf '%s' "${ID:-}")"
    os_version="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
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

  arch="$(uname -m)"
  case "$arch" in
    x86_64)  suffix="";         platform="ubuntu2404" ;;
    aarch64) suffix="-aarch64"; platform="ubuntu2404-aarch64" ;;
    *) say "tarball: unsupported CPU architecture '$arch'."; return 1 ;;
  esac
  dir="swift-${version}-RELEASE"
  base="${dir}-ubuntu24.04${suffix}"
  url="https://download.swift.org/swift-${version}-release/${platform}/${dir}/${base}.tar.gz"

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

  mkdir -p "$install_dir"
  if ! tar -xzf "$tmp/swift.tar.gz" -C "$install_dir" --strip-components=1; then
    say "tarball: extraction failed."
    return 1
  fi
  say "tarball: installed Swift $version to $install_dir (signature verified)."
  say "Some system libraries may be missing; see https://www.swift.org/install/linux/ for the list."
  say "Next: export PATH=\"$install_dir/usr/bin:\$PATH\" && scripts/check-core.sh"
  return 0
)

# ---------------------------------------------------------------- option 2: Docker
docker_running() { docker info >/dev/null 2>&1; }

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
      say "docker: daemon not running; trying to start dockerd (log: /tmp/omp-dockerd.log)."
      nohup dockerd >/tmp/omp-dockerd.log 2>&1 &
      local dockerd_pid=$!
      for _ in $(seq 1 20); do
        docker_running && break
        sleep 1
      done
      if ! docker_running; then
        # Never leave a half-started daemon behind.
        kill "$dockerd_pid" 2>/dev/null || true
        say "docker: dockerd did not start; last log line: $(tail -n 1 /tmp/omp-dockerd.log 2>/dev/null)"
      fi
    fi
    if ! docker_running; then
      say "docker: no Docker daemon is available."
      return 1
    fi
  fi
  say "docker: pulling $image"
  if ! docker pull "$image"; then
    say "docker: pulling $image failed (Docker Hub may be blocked)."
    return 1
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
