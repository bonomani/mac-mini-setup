#!/usr/bin/env bash
# lib/drivers/bin_script.sh — driver.kind: bin-script
# driver.script_name: name of the script in $CFG_DIR/scripts/
# driver.bin_dir:     relative path from $HOME where the script is installed

_ucc_driver_bin_script_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local script_name bin_dir
  script_name="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.script_name")"
  bin_dir="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin_dir")"
  [[ -n "$script_name" && -n "$bin_dir" ]] || return 1
  if [[ -x "$HOME/$bin_dir/$script_name" ]]; then
    printf 'installed'
  else
    printf 'absent'
  fi
}

_ucc_driver_bin_script_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local script_name bin_dir
  script_name="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.script_name")"
  bin_dir="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin_dir")"
  [[ -n "$script_name" && -n "$bin_dir" ]] || return 1
  mkdir -p "$HOME/$bin_dir"
  install -m 755 "$cfg_dir/scripts/$script_name" "$HOME/$bin_dir/$script_name"
}

_ucc_driver_bin_script_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local script_name bin_dir
  script_name="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.script_name")"
  bin_dir="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin_dir")"
  [[ -n "$script_name" && -n "$bin_dir" ]] || return 1
  local file="$HOME/$bin_dir/$script_name"
  local md5=""
  if [[ -f "$file" ]]; then
    md5="$(md5sum "$file" 2>/dev/null | awk '{print substr($1,1,8)}' || md5 -q "$file" 2>/dev/null | cut -c1-8)"
  fi
  printf 'path=%s' "$file"
  [[ -n "$md5" ]] && printf '  md5=%s' "$md5"
}
