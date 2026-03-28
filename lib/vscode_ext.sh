#!/usr/bin/env bash
# lib/vscode_ext.sh — helper for YAML-driven VSCode extension targets
# Sourced by components/dev-tools.sh

# Runner: load all VSCode extension targets from a YAML config file.
# Usage: load_vscode_extensions_from_yaml <cfg_dir> <yaml_path>
load_vscode_extensions_from_yaml() {
  local cfg_dir="$1" yaml="$2" target=""
  vscode_extensions_cache_versions
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    ucc_yaml_simple_target "$cfg_dir" "$yaml" "$target"
  done < <(yaml_list "$cfg_dir" "$yaml" vscode_extensions)
}
