#!/usr/bin/env bash
# lib/drivers/pkg_npm.sh — npm-global backend for the pkg driver.
#
# Extracted from lib/drivers/pkg.sh on 2026-04-28 (PLAN refactor #3, slice 2).
# Mechanical move — no behavior change.

# npm-global
# Split "<name>[@<version>]" honoring scoped names (@scope/name[@version]).
_pkg_npm_split_ref() {
  local ref="$1" name version=""
  if [[ "$ref" == @*/*@* ]]; then
    name="${ref%@*}"; version="${ref##*@}"
  elif [[ "$ref" != @* && "$ref" == *@* ]]; then
    name="${ref%@*}"; version="${ref##*@}"
  else
    name="$ref"
  fi
  printf '%s\t%s' "$name" "$version"
}
_pkg_npm_name()    { local s; s="$(_pkg_npm_split_ref "$1")"; printf '%s' "${s%$'\t'*}"; }
_pkg_npm_pinned()  { local s; s="$(_pkg_npm_split_ref "$1")"; printf '%s' "${s#*$'\t'}"; }
_pkg_npm_available()  { _npm_ensure_path; }
_pkg_npm_activate()   { _npm_ensure_path; }
_pkg_npm_observe()    {
  local ref="$1" name pin v
  name="$(_pkg_npm_name "$ref")"
  pin="$(_pkg_npm_pinned "$ref")"
  v="$(npm_global_version "$name")"
  [[ -z "$v" ]] && { printf 'absent'; return; }
  if [[ -n "$pin" ]]; then
    [[ "$v" == "$pin" ]] && { printf '%s' "$v"; return; }
    printf 'outdated'; return
  fi
  local policy="${UIC_PREF_TOOL_UPDATE:-always-upgrade}"
  [[ "${_PKG_UPDATE_CLASS:-tool}" == "lib" ]] && policy="${UIC_PREF_LIB_UPDATE:-install-only}"
  if [[ "$policy" == "always-upgrade" ]] && _pkg_npm_outdated "$name"; then
    printf 'outdated'
  else
    printf '%s' "$v"
  fi
}
_pkg_npm_install()    { npm_global_install "$1"; }
# Version-pinned updates are sensitive (may downgrade): require interactive
# mode. Unpinned refs follow the usual `npm update -g` path.
_pkg_npm_update()     {
  local ref="$1" name pin cur
  name="$(_pkg_npm_name "$ref")"
  pin="$(_pkg_npm_pinned "$ref")"
  if [[ -n "$pin" ]]; then
    cur="$(npm_global_version "$name")"
    if [[ "${UCC_INTERACTIVE:-0}" != "1" ]]; then
      log_warn "npm-global ${name}: pinned to ${pin} but currently ${cur:-absent}; skipping (re-run with --interactive to apply pin)"
      return 0
    fi
    npm_global_install "$ref"
    return $?
  fi
  npm_global_update "$name"
}
_pkg_npm_version()    { npm_global_version "$(_pkg_npm_name "$1")"; }


# Cache `npm outdated -g --json` once per process; opt-in via the brew
# livecheck flag (same trade-off — slow network call).
_pkg_npm_outdated() {
  [[ "${UIC_PREF_UPSTREAM_CHECK:-0}" == "1" ]] || return 1
  local pkg="$1"
  if [[ -z "${_NPM_OUTDATED_CACHE+x}" ]]; then
    export _NPM_OUTDATED_CACHE
    _NPM_OUTDATED_CACHE="$(npm outdated -g --json 2>/dev/null || true)"
  fi
  [[ -n "$_NPM_OUTDATED_CACHE" ]] || return 1
  printf '%s' "$_NPM_OUTDATED_CACHE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(0 if '$pkg' in d else 1)
" 2>/dev/null
}
