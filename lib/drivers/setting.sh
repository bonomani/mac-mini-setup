#!/usr/bin/env bash
# lib/drivers/setting.sh — driver.kind: setting
# Unified key/value setting driver. Replaces user-defaults, pmset, and
# softwareupdate-defaults — all three share the same shape (read with tool X,
# write with tool X, single key).
#
#  driver.backend:        defaults | pmset
#  driver.domain:         (defaults only) defaults domain
#  driver.key:            key (defaults) or setting name (pmset)
#  driver.value:          desired value
#  driver.type:           bool|int|string  (defaults only, default bool)
#  driver.requires_sudo:  true|false       (default false)
#
# Examples:
#   user-defaults equivalent:
#     driver: { kind: setting, backend: defaults, domain: com.foo, key: bar, value: 1 }
#   pmset equivalent:
#     driver: { kind: setting, backend: pmset, key: displaysleep, value: 30, requires_sudo: true }
#   softwareupdate-defaults equivalent:
#     driver: { kind: setting, backend: defaults, domain: /Library/Preferences/com.apple.SoftwareUpdate,
#               key: AutomaticCheckEnabled, value: 1, requires_sudo: true }

_setting_get_fields() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _SETTING_BACKEND="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.backend")"
  _SETTING_DOMAIN="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.domain")"
  _SETTING_KEY="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.key")"
  _SETTING_VALUE="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.value")"
  _SETTING_TYPE="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.type")"
  _SETTING_SUDO="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.requires_sudo")"
  [[ -n "$_SETTING_TYPE" ]] || _SETTING_TYPE="bool"
}

_setting_read_value() {
  _setting_get_fields "$1" "$2" "$3"
  case "$_SETTING_BACKEND" in
    defaults)
      [[ -n "$_SETTING_DOMAIN" && -n "$_SETTING_KEY" ]] || return 1
      defaults read "$_SETTING_DOMAIN" "$_SETTING_KEY" 2>/dev/null || printf '0'
      ;;
    pmset)
      [[ -n "$_SETTING_KEY" ]] || return 1
      pmset -g | awk -v s="$_SETTING_KEY" '$1==s{print $2; found=1} END{if(!found) print 0}'
      ;;
    *) return 1 ;;
  esac
}

_ucc_driver_setting_observe() {
  _setting_read_value "$1" "$2" "$3"
}

_ucc_driver_setting_action() {
  _ucc_driver_setting_apply "$1" "$2" "$3"
}

_ucc_driver_setting_apply() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _setting_get_fields "$cfg_dir" "$yaml" "$target"
  [[ -n "$_SETTING_KEY" && -n "$_SETTING_VALUE" ]] || return 1
  # macOS defaults -bool requires true/false/yes/no, not 1/0
  if [[ "$_SETTING_TYPE" == "bool" ]]; then
    case "$_SETTING_VALUE" in 1|yes|YES) _SETTING_VALUE="true" ;; 0|no|NO) _SETTING_VALUE="false" ;; esac
  fi
  local needs_sudo=0
  case "$_SETTING_SUDO" in 1|true|TRUE|yes|YES) needs_sudo=1 ;; esac
  case "$_SETTING_BACKEND" in
    defaults)
      [[ -n "$_SETTING_DOMAIN" ]] || return 1
      if [[ "$needs_sudo" == "1" ]]; then
        sudo_is_available || { log_warn "setting/defaults requires sudo (${_SETTING_DOMAIN}/${_SETTING_KEY})"; return 1; }
        ucc_run run_elevated defaults write "$_SETTING_DOMAIN" "$_SETTING_KEY" -"$_SETTING_TYPE" "$_SETTING_VALUE"
      else
        ucc_run defaults write "$_SETTING_DOMAIN" "$_SETTING_KEY" -"$_SETTING_TYPE" "$_SETTING_VALUE"
      fi
      ;;
    pmset)
      sudo_is_available || { log_warn "setting/pmset requires sudo (${_SETTING_KEY})"; return 1; }
      ucc_run run_elevated pmset -c "$_SETTING_KEY" "$_SETTING_VALUE"
      ;;
    *) return 1 ;;
  esac
}

_ucc_driver_setting_evidence() {
  local val
  val="$(_setting_read_value "$1" "$2" "$3")"
  printf '%s=%s' "$_SETTING_KEY" "$val"
}
