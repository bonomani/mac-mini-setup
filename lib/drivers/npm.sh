#!/usr/bin/env bash
# lib/drivers/npm.sh — driver.kind: npm-global
# driver.package: <package-name>  (e.g. '@openai/codex')

# ── npm-global helpers (always loaded with the driver) ────────────────────────
# Ensure `npm` is on PATH. Components that don't run the node-stack runner
# (e.g. cli-tools) never source nvm; do it here on demand. Idempotent.
_npm_ensure_path() {
  command -v npm >/dev/null 2>&1 && return 0
  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  if [[ -s "$nvm_dir/nvm.sh" ]]; then
    export NVM_DIR="$nvm_dir"
    # shellcheck disable=SC1090,SC1091
    source "$nvm_dir/nvm.sh" 2>/dev/null || true
    nvm use --silent default >/dev/null 2>&1 || nvm use --silent node >/dev/null 2>&1 || true
  fi
  command -v npm >/dev/null 2>&1
}

# Populate the npm global packages cache (exports _NPM_GLOBAL_VERSIONS_CACHE).
npm_global_cache_versions() {
  _npm_ensure_path || return 0
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
  _npm_ensure_path || { log_warn "npm not available (no nvm/node on PATH)"; return 1; }
  ucc_run npm install -g "$1" || return $?
  npm_global_cache_versions 2>/dev/null || true
}

# Update a global npm package and refresh the cache.
npm_global_update() {
  _npm_ensure_path || { log_warn "npm not available (no nvm/node on PATH)"; return 1; }
  ucc_run npm update -g "$1" || return $?
  npm_global_cache_versions 2>/dev/null || true
}

# Return the installed version of a global npm package (uses cache when available).
npm_global_version() {
  _npm_ensure_path || { printf ''; return 0; }
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

# ── Foreign-install helpers (used by pkg dispatcher's foreign-install path) ──
# Detect a conflicting binary owned by another package manager.
# Echoes a short owner tag (brew, brew-cask, external) or empty when no conflict.
_npm_global_foreign_owner() {
  local bin="$1"
  [[ -n "$bin" ]] || return 0
  command -v "$bin" >/dev/null 2>&1 || return 0
  if command -v brew >/dev/null 2>&1; then
    if brew list --formula "$bin" >/dev/null 2>&1; then
      printf 'brew'; return 0
    fi
    if brew list --cask "$bin" >/dev/null 2>&1; then
      printf 'brew-cask'; return 0
    fi
  fi
  printf 'external'
}

# Migrate away from a foreign install so npm-global can take over.
# Usage: _npm_global_migrate <owner> <bin> <pkg>
# IMPORTANT: HOMEBREW_NO_AUTOREMOVE=1 prevents brew from cascading the
# uninstall to orphaned leaves like `node` (which would yank npm itself).
_npm_global_migrate() {
  local owner="$1" bin="$2" pkg="$3"
  case "$owner" in
    brew)
      HOMEBREW_NO_AUTOREMOVE=1 ucc_run brew uninstall --formula "$bin" || return 1
      brew_refresh_caches 2>/dev/null || true
      ;;
    brew-cask)
      HOMEBREW_NO_AUTOREMOVE=1 ucc_run brew uninstall --cask "$bin" || return 1
      brew_refresh_caches 2>/dev/null || true
      ;;
    *)
      log_warn "npm-global: cannot auto-migrate ${bin} owned by '${owner}'; remove it manually."
      return 1
      ;;
  esac
}

