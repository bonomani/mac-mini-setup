#!/usr/bin/env bash
# lib/ucc_brew.sh — Brew package outdated cache and observe helpers
# Sourced by lib/ucc.sh

# Populated once in install.sh; exported so component subshells
# can read it without repeating the network call.
brew_cache_outdated() {
  export _BREW_OUTDATED_CACHE
  export _BREW_CASK_OUTDATED_CACHE
  export _BREW_VERSIONS_CACHE
  export _BREW_CASK_VERSIONS_CACHE
  _BREW_OUTDATED_CACHE=$(brew outdated --quiet 2>/dev/null || true)
  _BREW_CASK_OUTDATED_CACHE=$(brew outdated --cask --quiet 2>/dev/null || true)
  _BREW_VERSIONS_CACHE=$(brew list --versions 2>/dev/null || true)
  _BREW_CASK_VERSIONS_CACHE=$(brew list --cask --versions 2>/dev/null || true)
}

# Match short name ("ariaflow") or full tap name ("bonomani/ariaflow/ariaflow")
_brew_is_outdated()      { echo "${_BREW_OUTDATED_CACHE:-}"      | grep -qE "(^|/)${1}$"; }
_brew_cask_is_outdated() { echo "${_BREW_CASK_OUTDATED_CACHE:-}" | grep -qE "(^|/)${1}$"; }

# Generic observe helpers — return: absent | outdated | current
# Respect UIC_PREF_PACKAGE_UPDATE_POLICY (install-only | always-upgrade).
# brew_is_installed / brew_cask_is_installed are defined in lib/utils.sh
# which is always sourced before these helpers are called.
_brew_refresh_if_stale() {
  [[ "${_BREW_OUTDATED_STALE:-0}" == "1" ]] || return 0
  brew_cache_outdated 2>/dev/null || true
  _BREW_OUTDATED_STALE=0
}

# Lookup version from cache (no brew subprocess)
_brew_cached_version()      { echo "${_BREW_VERSIONS_CACHE:-}"      | awk -v p="$1" '$1==p{print $NF}'; }
_brew_cask_cached_version() { echo "${_BREW_CASK_VERSIONS_CACHE:-}" | awk -v p="$1" '$1==p{v=$NF; sub(/,.*$/,"",v); print v}'; }

brew_observe() {
  local pkg="$1" ver
  # Use version cache for presence check — avoids `brew list <pkg>` subprocess
  ver=$(_brew_cached_version "$pkg")
  [[ -z "$ver" ]] && { echo "absent"; return; }
  if [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" == "always-upgrade" ]]; then
    _brew_refresh_if_stale
    _brew_is_outdated "$pkg" && { echo "outdated"; return; }
  fi
  echo "$ver"
}

brew_cask_observe() {
  local pkg="$1" ver
  ver=$(_brew_cask_cached_version "$pkg")
  [[ -z "$ver" ]] && { echo "absent"; return; }
  if [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" == "always-upgrade" ]]; then
    _brew_refresh_if_stale
    _brew_cask_is_outdated "$pkg" && { echo "outdated"; return; }
  fi
  echo "$ver"
}
