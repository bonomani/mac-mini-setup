#!/usr/bin/env bash
# lib/drivers/curl_installer.sh — driver.kind: curl-installer
# Generic driver for software installed via curl | sh pattern.
#
# driver.install_url:   URL of the installer script
# driver.bin:           binary name to check (e.g. ollama)
# driver.version_cmd:   command to get version (default: <bin> --version)
# driver.install_args:  optional args to the installer script

_ucc_driver_curl_installer_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local bin
  bin="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin")"
  [[ -n "$bin" ]] || return 1
  if ! command -v "$bin" >/dev/null 2>&1; then
    printf 'absent'
    return
  fi
  # Check if outdated — curl installers don't have a native outdated check
  # so we just report the installed version
  printf 'installed'
}

_ucc_driver_curl_installer_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local install_url install_args
  install_url="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.install_url")"
  install_args="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.install_args")"
  [[ -n "$install_url" ]] || return 1
  case "$action" in
    install|update)
      curl -fsSL "$install_url" | sh ${install_args:+$install_args}
      ;;
  esac
}

_ucc_driver_curl_installer_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local bin version_cmd ver path
  bin="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin")"
  version_cmd="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.version_cmd")"
  [[ -n "$bin" ]] || return 1
  path="$(command -v "$bin" 2>/dev/null || true)"
  if [[ -n "$version_cmd" ]]; then
    ver="$($version_cmd 2>/dev/null || true)"
  else
    ver="$("$bin" --version 2>/dev/null | awk '{print $NF}' | head -1 || true)"
  fi
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
  [[ -n "$path" ]] && printf '  path=%s' "$path"
}
