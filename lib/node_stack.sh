#!/usr/bin/env bash
# lib/node_stack.sh — nvm, Node.js, npm global packages runner
# Note: npm_global_* helpers moved to lib/drivers/npm.sh (always loaded).

# Usage: run_node_stack_from_yaml <cfg_dir> <yaml_path>
run_node_stack_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local _NODE_VER="24" _NVM_DIR=".nvm"
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      node_version) [[ -n "$value" ]] && _NODE_VER="$value" ;;
      nvm_dir)      [[ -n "$value" ]] && _NVM_DIR="$value" ;;
    esac
  done < <(yaml_get_many "$cfg_dir" "$yaml" node_version nvm_dir)

  # ---- nvm + Node.js LTS ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "nvm"
  export NVM_DIR="$HOME/$_NVM_DIR"
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" 2>/dev/null || true
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "node-lts"
  [[ -s "$NVM_DIR/nvm.sh" ]] && nvm use "$_NODE_VER" >/dev/null 2>&1 || true

  # ---- Ensure brew's node is never on PATH ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "brew-node-unlinked"

  # ---- npm global packages ----
  npm_global_cache_versions
  local _target
  while IFS= read -r -u 3 _target; do
    [[ -n "$_target" ]] && ucc_yaml_simple_target "$cfg_dir" "$yaml" "$_target"
  done 3< <(yaml_list "$cfg_dir" "$yaml" npm_packages)

}
