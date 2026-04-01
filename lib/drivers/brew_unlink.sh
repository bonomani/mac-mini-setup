#!/usr/bin/env bash
# lib/drivers/brew_unlink.sh — driver.kind: brew-unlink
# driver.formula: formula name to ensure is unlinked

_ucc_driver_brew_unlink_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local formula
  formula="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.formula")"
  [[ -n "$formula" ]] || return 1
  if ! command -v node 2>/dev/null | grep -q opt/homebrew; then
    printf 'configured'
  else
    printf 'linked'
  fi
}

_ucc_driver_brew_unlink_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local formula
  formula="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.formula")"
  [[ -n "$formula" ]] || return 1
  brew_formula_unlink "$formula"
}

_ucc_driver_brew_unlink_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local node_path
  node_path="$(command -v node 2>/dev/null || printf none)"
  printf 'node_path=%s' "$node_path"
}
