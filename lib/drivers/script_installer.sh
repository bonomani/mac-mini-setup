#!/usr/bin/env bash
# lib/drivers/script_installer.sh — driver.kind: script-installer
# driver.install_url:    URL of the installer script
# driver.install_dir:    relative path from $HOME to check for existence
# driver.install_args:   optional args passed to the installer (default: --unattended)
# driver.upgrade_script: relative path from $HOME to the upgrade script (optional)

_ucc_driver_script_installer_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local install_dir
  install_dir="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.install_dir")"
  [[ -n "$install_dir" ]] || return 1
  if [[ -d "$HOME/$install_dir" ]]; then
    printf 'installed'
  else
    printf 'absent'
  fi
}

_ucc_driver_script_installer_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local install_url install_args upgrade_script install_dir
  install_url="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.install_url")"
  install_args="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.install_args")"
  upgrade_script="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.upgrade_script")"
  install_dir="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.install_dir")"
  [[ -n "$install_args" ]] || install_args="--unattended"
  case "$action" in
    install)
      [[ -n "$install_url" ]] || return 1
      sh -c "$(curl -fsSL "$install_url")" "" $install_args
      ;;
    update)
      if [[ -n "$upgrade_script" && -f "$HOME/$install_dir/$upgrade_script" ]]; then
        bash "$HOME/$install_dir/$upgrade_script" || true
      elif [[ -n "$install_url" ]]; then
        sh -c "$(curl -fsSL "$install_url")" "" $install_args
      fi
      ;;
  esac
}

_ucc_driver_script_installer_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local install_dir
  install_dir="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.install_dir")"
  [[ -n "$install_dir" ]] || return 1
  local ver=""
  if [[ -d "$HOME/$install_dir/.git" ]]; then
    ver="$(git -C "$HOME/$install_dir" describe --tags --abbrev=0 2>/dev/null || \
           git -C "$HOME/$install_dir" rev-parse --short HEAD 2>/dev/null || true)"
  fi
  printf 'folder=%s/%s' "$HOME" "$install_dir"
  [[ -n "$ver" ]] && printf '  version=%s' "$ver"
}
