#!/usr/bin/env bash
# lib/drivers/brew.sh — driver.kind: brew-formula, brew-cask

# ── brew-formula ──────────────────────────────────────────────────────────────
# driver.ref: <formula-name>

_ucc_driver_brew_formula_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ref
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  [[ -n "$ref" ]] || return 1
  brew_observe "$ref"
}

_ucc_driver_brew_formula_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local ref
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  [[ -n "$ref" ]] || return 1
  case "$action" in
    install) brew_install "$ref" ;;
    update)  brew_upgrade "$ref" ;;
  esac
}

_ucc_driver_brew_formula_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ref ver
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  [[ -n "$ref" ]] || return 1
  ver="$(_brew_cached_version "$ref")"
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
}

# ── brew-cask ─────────────────────────────────────────────────────────────────
# driver.ref:                <cask-name>
# driver.greedy_auto_updates: true|false  (optional, default false)

_ucc_driver_brew_cask_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ref greedy
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  [[ -n "$ref" ]] || return 1
  greedy="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.greedy_auto_updates")"
  brew_cask_observe "$ref" "$greedy"
}

_ucc_driver_brew_cask_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local ref greedy
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  [[ -n "$ref" ]] || return 1
  greedy="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.greedy_auto_updates")"
  case "$action" in
    install) brew_cask_install "$ref" ;;
    update)  brew_cask_upgrade "$ref" "$greedy" ;;
  esac
}

_ucc_driver_brew_cask_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ref ver
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  [[ -n "$ref" ]] || return 1
  ver="$(_brew_cask_cached_version "$ref")"
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
}
