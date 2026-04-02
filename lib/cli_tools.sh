#!/usr/bin/env bash
# lib/cli_tools.sh — CLI tools, Git, shell config, GUI casks runner

# Usage: run_cli_tools_from_yaml <cfg_dir> <yaml_path>
run_cli_tools_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  # ---- Git (install + config) ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "git"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "git-global-config"

  # ---- CLI tools ----
  local _target
  while IFS= read -r _target; do
    [[ -n "$_target" ]] && ucc_yaml_simple_target "$cfg_dir" "$yaml" "$_target"
  done < <(yaml_list "$cfg_dir" "$yaml" cli_tools)

  # ---- Shell config ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "oh-my-zsh"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "omz-theme-agnoster"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "home-bin-in-path"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "ai-healthcheck"

  # ---- GUI casks (macOS only) ----
  if [[ "${HOST_PLATFORM:-macos}" == "macos" ]]; then
    while IFS= read -r _target; do
      [[ -n "$_target" ]] && ucc_yaml_simple_target "$cfg_dir" "$yaml" "$_target"
    done < <(yaml_list "$cfg_dir" "$yaml" casks)
  fi
}
