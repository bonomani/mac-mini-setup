#!/usr/bin/env bash
# lib/git.sh — Git install + global config targets
# Sourced by components/git.sh

# Usage: run_git_from_yaml <cfg_dir> <yaml_path>
run_git_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "git"
}

# Usage: run_git_config_from_yaml <cfg_dir> <yaml_path>
run_git_config_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "git-global-config"
}
