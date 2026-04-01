#!/usr/bin/env bash
# lib/drivers/zsh_config.sh — driver.kind: zsh-config
# driver.key:        the config key to set (e.g. ZSH_THEME)
# driver.value:      the desired value
# driver.config_file: relative path from $HOME to the zsh config file

_ucc_driver_zsh_config_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local key value config_file
  key="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.key")"
  value="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.value")"
  config_file="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.config_file")"
  [[ -n "$key" && -n "$value" && -n "$config_file" ]] || return 1
  if grep -q "^${key}=\"${value}\"" "$HOME/$config_file" 2>/dev/null; then
    printf 'configured'
  else
    printf 'absent'
  fi
}

_ucc_driver_zsh_config_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local key value config_file
  key="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.key")"
  value="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.value")"
  config_file="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.config_file")"
  [[ -n "$key" && -n "$value" && -n "$config_file" ]] || return 1
  local file="$HOME/$config_file"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i '' "s/^${key}=.*/${key}=\"${value}\"/" "$file"
  else
    printf '\n%s="%s"\n' "$key" "$value" >> "$file"
  fi
}

_ucc_driver_zsh_config_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local key value config_file
  key="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.key")"
  value="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.value")"
  config_file="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.config_file")"
  [[ -n "$key" ]] || return 1
  printf '%s=%s  file=%s/%s' "$key" "$value" "$HOME" "$config_file"
}
