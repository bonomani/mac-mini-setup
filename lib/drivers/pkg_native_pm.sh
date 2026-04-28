#!/usr/bin/env bash
# lib/drivers/pkg_native_pm.sh — Linux/WSL2 platform PM backend (apt/dnf/pacman/zypper).
# Extracted from lib/drivers/pkg.sh on 2026-04-28 (PLAN refactor #3, slice 5).

# native-pm: Linux/WSL2 platform-aware package manager (apt/dnf/pacman/zypper).
# Delegates to the helpers in lib/drivers/package.sh which already implement
# per-PM is_installed/install/upgrade/version. The backend is "available" only
# on non-macOS hosts (and only when a real PM is detected, not 'unknown').
_pkg_native_pm_available() {
  [[ "${HOST_PLATFORM:-macos}" != "macos" ]] || return 1
  declare -f _pkg_native_backend >/dev/null 2>&1 || return 1
  local be; be="$(_pkg_native_backend)"
  [[ "$be" != "unknown" && "$be" != "brew" ]]
}
_pkg_native_pm_activate() { :; }
_pkg_native_pm_observe() {
  local ref="$1" be ver
  be="$(_pkg_native_backend)"
  if ! _pkg_native_is_installed "$be" "$ref"; then
    printf 'absent'
    return
  fi
  if _pkg_native_is_outdated "$be" "$ref"; then
    printf 'outdated'
    return
  fi
  ver="$(_pkg_native_version "$be" "$ref")"
  printf '%s' "${ver:-installed}"
}
_pkg_native_pm_install()  { _pkg_native_install "$(_pkg_native_backend)" "$1"; }
_pkg_native_pm_update()   { _pkg_native_upgrade "$(_pkg_native_backend)" "$1"; }
_pkg_native_pm_version()  { _pkg_native_version "$(_pkg_native_backend)" "$1"; }
_pkg_native_pm_outdated() { _pkg_native_is_outdated "$(_pkg_native_backend)" "$1"; }
