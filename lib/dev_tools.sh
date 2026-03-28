#!/usr/bin/env bash
# lib/dev_tools.sh — Node, VSCode, CLI tools, Oh My Zsh, ariaflow targets
# Sourced by components/dev-tools.sh

# Usage: run_dev_tools_from_yaml <cfg_dir> <yaml_path>
run_dev_tools_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local _NODE_VER="24"
  local _ARIAFLOW_TAP="bonomani/ariaflow" _ARIAFLOW_FORMULA _ARIAFLOW_WEB_FORMULA
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      node_version) [[ -n "$value" ]] && _NODE_VER="$value" ;;
      ariaflow_tap) [[ -n "$value" ]] && _ARIAFLOW_TAP="$value" ;;
    esac
  done < <(yaml_get_many "$cfg_dir" "$yaml" node_version ariaflow_tap)
  _ARIAFLOW_FORMULA="${_ARIAFLOW_TAP}/ariaflow"
  _ARIAFLOW_WEB_FORMULA="${_ARIAFLOW_TAP}/ariaflow-web"
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

  # ---- Node.js LTS ----
  # Ensure node@N is first in PATH before observe so version check sees the right binary
  if [[ -d "/opt/homebrew/opt/node@${_NODE_VER}/bin" ]]; then
    export PATH="/opt/homebrew/opt/node@${_NODE_VER}/bin:$PATH"
  elif [[ -d "/usr/local/opt/node@${_NODE_VER}/bin" ]]; then
    export PATH="/usr/local/opt/node@${_NODE_VER}/bin:$PATH"
  fi
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "node-lts"

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
