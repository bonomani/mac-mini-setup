#!/usr/bin/env bash
# lib/drivers/brew.sh — driver.kind: brew, brew-analytics

# ── brew ──────────────────────────────────────────────────────────────────────
# driver.ref:               <formula-name> or <cask-name>  (e.g. git, node@24)
# driver.cask:              true|false  (optional, default false)
# driver.greedy_auto_updates: true|false  (optional, cask only, default false)
# driver.previous_ref:      <formula@version>  (optional, unlinked before
#                           install; also forces link --overwrite after
#                           install/update)

_ucc_driver_brew_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ref cask greedy state
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  [[ -n "$ref" ]] || return 1
  cask="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.cask")"
  if [[ "$cask" == "true" ]]; then
    greedy="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.greedy_auto_updates")"
    state="$(brew_cask_observe "$ref" "$greedy")"
  else
    state="$(brew_observe "$ref")"
  fi
  _ucc_brew_state_with_upstream "$cfg_dir" "$yaml" "$target" "$state"
}

_ucc_driver_brew_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local ref cask greedy previous_ref
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  [[ -n "$ref" ]] || return 1
  cask="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.cask")"
  if [[ "$cask" == "true" ]]; then
    greedy="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.greedy_auto_updates")"
    case "$action" in
      install) brew_cask_install "$ref" ;;
      update)  brew_cask_upgrade "$ref" "$greedy" ;;
    esac
  else
    previous_ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.previous_ref")"
    case "$action" in
      install)
        [[ -n "$previous_ref" ]] && { brew unlink "$previous_ref" 2>/dev/null || true; }
        brew_install "$ref"
        [[ -n "$previous_ref" ]] && ucc_run brew link --overwrite --force "$ref"
        ;;
      update)
        brew_upgrade "$ref"
        [[ -n "$previous_ref" ]] && ucc_run brew link --overwrite --force "$ref"
        ;;
    esac
  fi
}

_ucc_driver_brew_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ref cask ver
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  [[ -n "$ref" ]] || return 1
  cask="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.cask")"
  if [[ "$cask" == "true" ]]; then
    ver="$(_brew_cask_cached_version "$ref")"
  else
    ver="$(_brew_cached_version "$ref")"
  fi
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
}

# ── brew-analytics ────────────────────────────────────────────────────────────
# No driver fields required; desired value comes from target's desired_value.

_ucc_driver_brew_analytics_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local state
  state="$(brew analytics state 2>/dev/null)" || return 1
  printf '%s' "$(echo "$state" | grep -qi disabled && echo off || echo on)"
}

_ucc_driver_brew_analytics_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  _ucc_driver_brew_analytics_apply "$cfg_dir" "$yaml" "$target"
}

_ucc_driver_brew_analytics_apply() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local desired
  desired="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "desired_value")"
  [[ -n "$desired" ]] || desired="off"
  ucc_run brew analytics "$desired"
}

_ucc_driver_brew_analytics_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local state_output
  state_output="$(brew analytics state 2>/dev/null)" || return 1
  local state
  state="$(echo "$state_output" | grep -qi disabled && printf off || printf on)"
  printf 'analytics=%s' "$state"
}
