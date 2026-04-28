#!/usr/bin/env bash
# lib/drivers/pkg_brew.sh — brew formula + brew-cask backends.
# Extracted from lib/drivers/pkg.sh on 2026-04-28 (PLAN refactor #3, slice 4).

# brew (formula). brew_observe already returns absent/outdated/<version>.
_pkg_brew_available() { command -v brew >/dev/null 2>&1; }
_pkg_brew_activate()  { :; }
_pkg_brew_observe()   { brew_observe "$1" "${_PKG_UPDATE_CLASS:-tool}"; }
_pkg_brew_install()   { brew_install "$1"; }
_pkg_brew_update()    { brew_upgrade "$1"; }
_pkg_brew_version()   { _brew_cached_version "$1"; }
# Outdated detection: piggyback on brew_observe (returns "outdated" when
# brew outdated flags it; UIC_PREF_UPSTREAM_CHECK=1 catches formula lag).
_pkg_brew_outdated()  { [[ "$(brew_observe "$1" "${_PKG_UPDATE_CLASS:-tool}")" == "outdated" ]]; }


# brew-cask: macOS GUI apps via Homebrew Cask. Greedy mode (auto-update casks)
# is opt-in via driver.greedy_auto_updates: true at the YAML level.
_pkg_brew_cask_available() { command -v brew >/dev/null 2>&1; }
_pkg_brew_cask_activate()  { :; }
_pkg_brew_cask_observe()   {
  brew_cask_observe "$1" "${_PKG_GREEDY:-false}" "${_PKG_UPDATE_CLASS:-tool}"
}
_pkg_brew_cask_install()   { brew_cask_install "$1"; }
_pkg_brew_cask_update()    { brew_cask_upgrade "$1" "${_PKG_GREEDY:-false}"; }
_pkg_brew_cask_version()   { _brew_cask_cached_version "$1"; }
_pkg_brew_cask_outdated()  { [[ "$(brew_cask_observe "$1" "${_PKG_GREEDY:-false}" "${_PKG_UPDATE_CLASS:-tool}")" == "outdated" ]]; }
