#!/usr/bin/env bash
# lib/drivers/macos_swupdate.sh — driver.kind: softwareupdate-defaults

# ── softwareupdate-defaults ────────────────────────────────────────────────────
# driver.domain: <defaults domain>
# driver.key:    <defaults key>
# driver.value:  <desired value>  (default: 1)

_ucc_driver_softwareupdate_defaults_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local domain key
  domain="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.domain")"
  key="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.key")"
  [[ -n "$domain" && -n "$key" ]] || return 1
  if defaults read "$domain" "$key" 2>/dev/null | grep -qiE '^1$|^true$'; then
    printf '1'
  else
    printf '0'
  fi
}

_ucc_driver_softwareupdate_defaults_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local domain key value
  domain="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.domain")"
  key="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.key")"
  value="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.value")"
  [[ -n "$domain" && -n "$key" ]] || return 1
  [[ -n "$value" ]] || value="1"
  local bool_flag="true"
  [[ "$value" == "0" || "$value" == "false" ]] && bool_flag="false"
  case "$action" in
    install|update) ucc_run sudo defaults write "$domain" "$key" -bool "$bool_flag" ;;
  esac
}

_ucc_driver_softwareupdate_defaults_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local domain key val
  domain="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.domain")"
  key="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.key")"
  [[ -n "$domain" && -n "$key" ]] || return 1
  val="$(defaults read "$domain" "$key" 2>/dev/null || echo 0)"
  printf '%s=%s' "$key" "$val"
}
