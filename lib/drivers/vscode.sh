#!/usr/bin/env bash
# lib/drivers/vscode.sh — driver.kind: vscode-marketplace
# driver.extension_id: <publisher.name>  (e.g. ms-python.python)

_ucc_driver_vscode_marketplace_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ext_id ver
  ext_id="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.extension_id")"
  ver="$(_vscode_extension_cached_version "$ext_id")"
  printf '%s' "${ver:-absent}"
}

_ucc_driver_vscode_marketplace_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local ext_id
  ext_id="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.extension_id")"
  case "$action" in
    install) vscode_extension_install "$ext_id" ;;
    update)  vscode_extension_update  "$ext_id" ;;
  esac
}

_ucc_driver_vscode_marketplace_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ext_id ver
  ext_id="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.extension_id")"
  ver="$(_vscode_extension_cached_version "$ext_id")"
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
}
