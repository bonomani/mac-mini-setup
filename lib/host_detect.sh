#!/usr/bin/env bash
# lib/host_detect.sh — Host platform/arch/OS/PM/init-system detection
# Sourced by install.sh before any other library.
#
# Exports (after sourcing):
#   HOST_PLATFORM          — macos | linux | wsl | unknown
#   HOST_PLATFORM_VARIANT  — macos | linux | wsl1 | wsl2 | unknown
#   HOST_ARCH              — arm64 | x86_64 | ...
#   HOST_OS_ID             — macos-15.4 | ubuntu-22.04 | ...
#   HOST_PACKAGE_MANAGER   — brew | apt | dnf | pacman | zypper | unknown
#   HOST_FINGERPRINT       — composite: os/ver/arch/pm/init
#
# Used by targets' `requires:` and conditional `depends_on?<value>` syntax.
# See CLAUDE.md Rule 11 for the fingerprint segments.

_detect_host_platform() {
  case "$(uname)" in
    Darwin) echo "macos" ;;
    Linux)
      if grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null \
         || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        echo "wsl"
      else
        echo "linux"
      fi
      ;;
    *) echo "unknown" ;;
  esac
}

_detect_host_platform_variant() {
  case "$(uname)" in
    Darwin) echo "macos" ;;
    Linux)
      if grep -qiE 'wsl2' /proc/sys/kernel/osrelease 2>/dev/null \
         || grep -qiE 'wsl2' /proc/version 2>/dev/null; then
        echo "wsl2"
      elif grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null \
         || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        echo "wsl1"
      else
        echo "linux"
      fi
      ;;
    *) echo "unknown" ;;
  esac
}

_detect_host_arch() { uname -m; }

_detect_host_os_id() {
  case "$(uname)" in
    Darwin) printf 'macos-%s' "$(sw_vers -productVersion 2>/dev/null || echo unknown)" ;;
    Linux)
      if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        printf '%s-%s' "${ID:-unknown}" "${VERSION_ID:-unknown}"
      else
        printf 'linux-unknown'
      fi
      ;;
    *) printf 'unknown' ;;
  esac
}

_detect_host_package_manager() {
  if command -v brew >/dev/null 2>&1; then printf 'brew'
  elif command -v apt-get >/dev/null 2>&1; then printf 'apt'
  elif command -v dnf >/dev/null 2>&1; then printf 'dnf'
  elif command -v pacman >/dev/null 2>&1; then printf 'pacman'
  elif command -v zypper >/dev/null 2>&1; then printf 'zypper'
  else printf 'unknown'
  fi
}

# Detect the host's init/service-manager subsystem. Returned value is added
# to HOST_FINGERPRINT so YAML targets can declare `requires: launchd,systemd`
# and gracefully skip on hosts where neither is available (e.g. default WSL2
# without systemd, where `brew services` will not work).
_detect_init_system() {
  case "$HOST_PLATFORM" in
    macos) printf 'launchd' ;;
    *)
      if [[ -d /run/systemd/system ]] || \
         { command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; }; then
        printf 'systemd'
      else
        printf 'no-init-system'
      fi
      ;;
  esac
}

_build_host_fingerprint() {
  local os ver arch pm init
  arch="$HOST_ARCH"
  pm="$HOST_PACKAGE_MANAGER"
  init="$(_detect_init_system)"
  case "$HOST_PLATFORM" in
    macos)
      os="macos"
      ver="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
      ;;
    wsl)
      # wsl2-ubuntu/22.04 or wsl1-debian/12
      if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        os="${HOST_PLATFORM_VARIANT}-${ID:-linux}"
        ver="${VERSION_ID:-unknown}"
      else
        os="${HOST_PLATFORM_VARIANT}-linux"
        ver="unknown"
      fi
      # Detect Windows host version
      local _winver; _winver="$(cmd.exe /c ver 2>/dev/null | tr -d '\r' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
      if [[ -n "$_winver" ]]; then
        local _build; _build="$(echo "$_winver" | cut -d. -f3)"
        [[ "${_build:-0}" -ge 22000 ]] && pm="${pm}@windows-11" || pm="${pm}@windows-10"
      fi
      ;;
    linux)
      if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        os="${ID:-linux}"
        ver="${VERSION_ID:-unknown}"
      else
        os="linux"
        ver="unknown"
      fi
      ;;
    *) os="unknown"; ver="unknown" ;;
  esac
  printf '%s/%s/%s/%s/%s' "$os" "$ver" "$arch" "$pm" "$init"
}

# Populate all HOST_* exports. Caller (install.sh) sources this once.
host_detect_export_all() {
  export HOST_PLATFORM="$(_detect_host_platform)"
  export HOST_PLATFORM_VARIANT="$(_detect_host_platform_variant)"
  export HOST_ARCH="$(_detect_host_arch)"
  export HOST_OS_ID="$(_detect_host_os_id)"
  export HOST_PACKAGE_MANAGER="$(_detect_host_package_manager)"
  export HOST_FINGERPRINT="$(_build_host_fingerprint)"
}
