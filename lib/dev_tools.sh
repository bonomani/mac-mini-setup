#!/usr/bin/env bash
# lib/dev_tools.sh — npm cache helpers + dev-tools runner
# Sourced by components/dev-tools.sh

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

# Usage: run_dev_tools_from_yaml <cfg_dir> <yaml_path>
run_dev_tools_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local _NODE_VER="24" _NVM_DIR=".nvm" _PYENV_DIR=".pyenv"
  local _ARIAFLOW_TAP="bonomani/ariaflow" _ARIAFLOW_FORMULA _ARIAFLOW_WEB_FORMULA
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      node_version) [[ -n "$value" ]] && _NODE_VER="$value" ;;
      ariaflow_tap) [[ -n "$value" ]] && _ARIAFLOW_TAP="$value" ;;
      nvm_dir)      [[ -n "$value" ]] && _NVM_DIR="$value" ;;
      pyenv_dir)    [[ -n "$value" ]] && _PYENV_DIR="$value" ;;
    esac
  done < <(yaml_get_many "$cfg_dir" "$yaml" node_version ariaflow_tap nvm_dir pyenv_dir)
  _ARIAFLOW_FORMULA="${_ARIAFLOW_TAP}/ariaflow"
  _ARIAFLOW_WEB_FORMULA="${_ARIAFLOW_TAP}/ariaflow-web"
  # ---- Git (install + config) ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "git"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "git-global-config"

  # ---- Python (pyenv + python version + pip) ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "pyenv"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "xz"
  export PYENV_ROOT="$HOME/$_PYENV_DIR"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)" 2>/dev/null || true
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "python"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "pip-latest"

  # ---- CLI tools (brew) ----
  local _target
  while IFS= read -r _target; do
    [[ -n "$_target" ]] && ucc_yaml_simple_target "$cfg_dir" "$yaml" "$_target"
  done < <(yaml_list "$cfg_dir" "$yaml" cli_tools)

  # ---- VSCode ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "vscode"

  # ---- code CLI symlink ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "vscode-code-cmd"

  # ---- VSCode extensions ----
  load_vscode_extensions_from_yaml "$cfg_dir" "$yaml"

  # ---- VSCode settings.json (merge, not overwrite) ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "vscode-settings"

  # ---- GUI tools (brew cask) ----
  while IFS= read -r _target; do
    [[ -n "$_target" ]] && ucc_yaml_simple_target "$cfg_dir" "$yaml" "$_target"
  done < <(yaml_list "$cfg_dir" "$yaml" casks)

  # ---- nvm + Node.js LTS ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "nvm"
  # Source nvm so node version check and npm targets see the right binary
  export NVM_DIR="$HOME/$_NVM_DIR"
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" 2>/dev/null || true
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "node-lts"
  # Activate the installed version for subsequent targets
  [[ -s "$NVM_DIR/nvm.sh" ]] && nvm use "$_NODE_VER" >/dev/null 2>&1 || true

  # ---- Ensure brew's node is never on PATH (nvm owns node) ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "brew-node-unlinked"

  # ---- npm global packages ----
  npm_global_cache_versions
  while IFS= read -r _target; do
    [[ -n "$_target" ]] && ucc_yaml_simple_target "$cfg_dir" "$yaml" "$_target"
  done < <(yaml_list "$cfg_dir" "$yaml" npm_packages)

  # ---- YAML-first simple configured targets ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "oh-my-zsh"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "omz-theme-agnoster"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "home-bin-in-path"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "ai-healthcheck"

  ucc_brew_runtime_formula_target "ariaflow" "ariaflow" "$_ARIAFLOW_FORMULA" "$cfg_dir" "$yaml"
  ucc_brew_runtime_formula_target "ariaflow-web" "ariaflow-web" "$_ARIAFLOW_WEB_FORMULA" "$cfg_dir" "$yaml"
}
