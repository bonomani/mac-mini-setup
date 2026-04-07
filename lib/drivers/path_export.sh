#!/usr/bin/env bash
# lib/drivers/path_export.sh — driver.kind: path-export
# driver.bin_dir:       relative path from $HOME to add to PATH
# driver.shell_profile: relative path from $HOME to the shell profile

_ucc_driver_path_export_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local bin_dir shell_profile
  bin_dir="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin_dir")"
  shell_profile="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.shell_profile")"
  [[ -n "$bin_dir" && -n "$shell_profile" ]] || return 1
  if grep -q "export PATH=\"\$HOME/$bin_dir:\$PATH\"" "$HOME/$shell_profile" 2>/dev/null; then
    printf 'configured'
  else
    printf 'absent'
  fi
}

_ucc_driver_path_export_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local bin_dir shell_profile
  bin_dir="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin_dir")"
  shell_profile="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.shell_profile")"
  [[ -n "$bin_dir" && -n "$shell_profile" ]] || return 1
  mkdir -p "$HOME/$bin_dir"
  _cfg_backup "$HOME/$shell_profile"
  printf '\nexport PATH="%s:$PATH"\n' "$HOME/$bin_dir" >> "$HOME/$shell_profile"
  export PATH="$HOME/$bin_dir:$PATH"
}

_ucc_driver_path_export_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local bin_dir
  bin_dir="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin_dir")"
  [[ -n "$bin_dir" ]] || return 1
  printf 'path=%s/%s' "$HOME" "$bin_dir"
}
