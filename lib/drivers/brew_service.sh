#!/usr/bin/env bash
# lib/drivers/brew_service.sh — driver.kind: brew-service
# driver.ref: <service-name>  (e.g. ariaflow)

_ucc_driver_brew_service_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ref state
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  [[ -n "$ref" ]] || return 1
  if ! brew list "$ref" >/dev/null 2>&1; then
    printf 'absent'
    return
  fi
  if brew_service_is_started "$ref"; then
    printf 'running'
  else
    printf 'stopped'
  fi
}

_ucc_driver_brew_service_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local ref
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  [[ -n "$ref" ]] || return 1
  case "$action" in
    install) ucc_run brew services start "$ref" ;;
    update)  ucc_run brew services restart "$ref" ;;
  esac
}

_ucc_driver_brew_service_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ref ver
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  [[ -n "$ref" ]] || return 1
  ver="$(_brew_cached_version "$ref")"
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
}
