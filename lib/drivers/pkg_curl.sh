#!/usr/bin/env bash
# lib/drivers/pkg_curl.sh — curl (script installer) backend for the pkg driver.
#
# Extracted from lib/drivers/pkg.sh on 2026-04-28 (PLAN refactor #3, slice 3).
# Mechanical move — no behavior change.

# curl (script installer fallback). Presence by default; outdated detection
# is opt-in via driver.github_repo + UIC_PREF_UPSTREAM_CHECK=1.
_pkg_curl_available() { command -v curl >/dev/null 2>&1; }
_pkg_curl_activate()  { :; }
_pkg_curl_observe()   {
  local bin="${_PKG_BIN:-}"
  [[ -n "$bin" ]] || return 1
  command -v "$bin" >/dev/null 2>&1 || { printf 'absent'; return; }
  if _pkg_curl_outdated; then
    printf 'outdated'
  else
    printf 'installed'
  fi
}
_pkg_curl_install() {
  local url="$1"
  local args="${_PKG_CURL_ARGS:-}"
  if [[ -n "$args" ]]; then
    ucc_run sh -c "curl -fsSL '$url' | sh -s -- $args"
  else
    ucc_run sh -c "curl -fsSL '$url' | sh"
  fi
}
_pkg_curl_update()  { _pkg_curl_install "$1"; }
_pkg_curl_version() {
  local bin="${_PKG_BIN:-}"
  [[ -n "$bin" ]] || return 0
  "$bin" --version 2>/dev/null | head -1 | _ucc_parse_version
}
# True (0) if upstream GitHub release is strictly newer than installed binary.
# Gated on UIC_PREF_UPSTREAM_CHECK=1 (network call). Reads driver.github_repo
# from _PKG_GITHUB_REPO stashed by the dispatcher.
_pkg_curl_outdated() {
  [[ "${UIC_PREF_UPSTREAM_CHECK:-0}" == "1" ]] || return 1
  [[ -n "${_PKG_GITHUB_REPO:-}" ]] || return 1
  local installed latest
  installed="$(_pkg_curl_version)"
  [[ -n "$installed" ]] || return 1
  latest="$(_pkg_github_latest_tag "$_PKG_GITHUB_REPO")"
  [[ -n "$latest" ]] || return 1
  _pkg_version_lt "$installed" "$latest"
}
