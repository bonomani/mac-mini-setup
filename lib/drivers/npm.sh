#!/usr/bin/env bash
# lib/drivers/npm.sh — driver.kind: npm-global
# driver.package: <package-name>  (e.g. '@openai/codex')

# ── npm-global helpers (always loaded with the driver) ────────────────────────
# Populate the npm global packages cache (exports _NPM_GLOBAL_VERSIONS_CACHE).
npm_global_cache_versions() {
  export _NPM_GLOBAL_VERSIONS_CACHE
  _NPM_GLOBAL_VERSIONS_CACHE="$(
    npm ls -g --depth=0 --json 2>/dev/null | python3 -c "
import json, sys
deps = (json.load(sys.stdin) or {}).get('dependencies', {})
for name in sorted(deps):
    print(f'{name}\t{deps[name].get(\"version\", \"\")}')
" 2>/dev/null || true
  )"
}

# Install a global npm package and refresh the cache.
npm_global_install() {
  ucc_run npm install -g "$1" || return $?
  npm_global_cache_versions 2>/dev/null || true
}

# Update a global npm package and refresh the cache.
npm_global_update() {
  ucc_run npm update -g "$1" || return $?
  npm_global_cache_versions 2>/dev/null || true
}

# Return the installed version of a global npm package (uses cache when available).
npm_global_version() {
  if [[ -z "${_NPM_GLOBAL_VERSIONS_CACHE+x}" ]]; then
    npm ls -g "$1" --depth=0 --json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
deps = d.get('dependencies', {})
k = next(iter(deps), '')
if k:
    print(deps[k].get('version', ''))
" 2>/dev/null || true
    return
  fi
  awk -F'\t' -v q="$1" '$1==q {print $2; exit}' <<< "$_NPM_GLOBAL_VERSIONS_CACHE"
}

# Observe a global npm package state: <version> | absent
npm_global_observe() {
  local version; version="$(npm_global_version "$1")"
  printf '%s' "${version:-absent}"
}

# ── Driver interface ──────────────────────────────────────────────────────────
_ucc_driver_npm_global_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local pkg
  pkg="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.package")"
  [[ -n "$pkg" ]] || return 1
  npm_global_observe "$pkg"
}

_ucc_driver_npm_global_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local pkg
  pkg="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.package")"
  [[ -n "$pkg" ]] || return 1
  case "$action" in
    install) npm_global_install "$pkg" ;;
    update)  npm_global_update  "$pkg" ;;
  esac
}

_ucc_driver_npm_global_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local pkg ver
  pkg="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.package")"
  [[ -n "$pkg" ]] || return 1
  ver="$(npm_global_version "$pkg")"
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
}
