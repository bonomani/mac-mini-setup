#!/usr/bin/env bash
# lib/drivers/vscode.sh — driver.kind: vscode-marketplace, json-merge
# driver.extension_id: <publisher.name>  (e.g. ms-python.python)

_ucc_driver_vscode_marketplace_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ext_id ver
  ext_id="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.extension_id")"
  [[ -n "$ext_id" ]] || return 1
  ver="$(_vscode_extension_cached_version "$ext_id")"
  printf '%s' "${ver:-absent}"
}

_ucc_driver_vscode_marketplace_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local ext_id
  ext_id="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.extension_id")"
  [[ -n "$ext_id" ]] || return 1
  case "$action" in
    install) vscode_extension_install "$ext_id" ;;
    update)  vscode_extension_update  "$ext_id" ;;
  esac
}

_ucc_driver_vscode_marketplace_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ext_id ver
  ext_id="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.extension_id")"
  [[ -n "$ext_id" ]] || return 1
  ver="$(_vscode_extension_cached_version "$ext_id")"
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
}

# ── json-merge ────────────────────────────────────────────────────────────────
# driver.settings_relpath: path relative to $HOME
# driver.patch_relpath:    path relative to $cfg_dir

_ucc_driver_json_merge_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local rel_settings rel_patch settings_path patch_path
  rel_settings="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.settings_relpath")"
  rel_patch="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.patch_relpath")"
  [[ -n "$rel_settings" && -n "$rel_patch" ]] || return 1
  settings_path="$HOME/$rel_settings"
  patch_path="$cfg_dir/$rel_patch"
  if python3 "$cfg_dir/tools/drivers/json_merge.py" check "$settings_path" "$patch_path" 2>/dev/null; then
    printf 'configured'
  else
    printf 'absent'
  fi
}

_ucc_driver_json_merge_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local rel_settings rel_patch settings_path patch_path
  rel_settings="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.settings_relpath")"
  rel_patch="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.patch_relpath")"
  [[ -n "$rel_settings" && -n "$rel_patch" ]] || return 1
  settings_path="$HOME/$rel_settings"
  patch_path="$cfg_dir/$rel_patch"
  case "$action" in
    install|update)
      ucc_run mkdir -p "$(dirname "$settings_path")"
      ucc_run python3 "$cfg_dir/tools/drivers/json_merge.py" apply "$settings_path" "$patch_path"
      ;;
  esac
}

_ucc_driver_json_merge_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local rel_settings
  rel_settings="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.settings_relpath")"
  [[ -n "$rel_settings" ]] || return 1
  printf 'path=%s' "$HOME/$rel_settings"
}
