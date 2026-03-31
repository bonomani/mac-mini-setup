#!/usr/bin/env bash
# lib/drivers/macos_defaults.sh — driver.kind: user-defaults, pmset

# ── user-defaults ──────────────────────────────────────────────────────────────
# driver.domain: <defaults domain>
# driver.key:    <defaults key>
# driver.value:  <desired value>
# driver.type:   bool|int|string  (default: bool)

_ucc_driver_user_defaults_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local domain key
  domain="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.domain")"
  key="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.key")"
  [[ -n "$domain" && -n "$key" ]] || return 1
  defaults read "$domain" "$key" 2>/dev/null || printf '0'
}

_ucc_driver_user_defaults_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local domain key value type
  domain="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.domain")"
  key="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.key")"
  value="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.value")"
  type="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.type")"
  [[ -n "$domain" && -n "$key" && -n "$value" ]] || return 1
  [[ -n "$type" ]] || type="bool"
  case "$action" in
    install|update) ucc_run defaults write "$domain" "$key" -"$type" "$value" ;;
  esac
}

_ucc_driver_user_defaults_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local domain key val
  domain="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.domain")"
  key="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.key")"
  [[ -n "$domain" && -n "$key" ]] || return 1
  val="$(defaults read "$domain" "$key" 2>/dev/null || true)"
  printf '%s=%s' "$key" "$val"
}

# ── pmset ──────────────────────────────────────────────────────────────────────
# driver.setting: <pmset setting name>
# driver.value:   <desired value>

_ucc_driver_pmset_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local setting
  setting="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.setting")"
  [[ -n "$setting" ]] || return 1
  pmset -g | awk -v s="$setting" '$1==s{print $2; found=1} END{if(!found) print 0}'
}

_ucc_driver_pmset_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local setting value
  setting="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.setting")"
  value="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.value")"
  [[ -n "$setting" && -n "$value" ]] || return 1
  case "$action" in
    install|update) ucc_run sudo pmset -c "$setting" "$value" ;;
  esac
}

_ucc_driver_pmset_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local setting val
  setting="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.setting")"
  [[ -n "$setting" ]] || return 1
  val="$(pmset -g | awk -v s="$setting" '$1==s{print $2}')"
  printf '%s=%s' "$setting" "$val"
}
