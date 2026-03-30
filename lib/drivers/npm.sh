#!/usr/bin/env bash
# lib/drivers/npm.sh — driver.kind: npm-global
# driver.package: <package-name>  (e.g. '@openai/codex')

_ucc_driver_npm_global_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local pkg
  pkg="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.package")"
  npm_global_observe "$pkg"
}

_ucc_driver_npm_global_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local pkg
  pkg="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.package")"
  case "$action" in
    install) npm_global_install "$pkg" ;;
    update)  npm_global_update  "$pkg" ;;
  esac
}

_ucc_driver_npm_global_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local pkg ver
  pkg="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.package")"
  ver="$(npm_global_version "$pkg")"
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
}
