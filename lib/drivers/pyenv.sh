#!/usr/bin/env bash
# lib/drivers/pyenv.sh — driver.kind: pyenv-version
# driver.version: <python-version>  (e.g. 3.12.3)
#                 Falls back to UIC_PREF_PYTHON_VERSION env var if set.

_ucc_driver_pyenv_version_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ver driver_ver
  driver_ver="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.version")"
  [[ -n "$driver_ver" ]] || return 1
  ver="${UIC_PREF_PYTHON_VERSION:-$driver_ver}"
  log_debug "pyenv-version[$target] observe: ver='$ver'"
  if pyenv versions 2>/dev/null | grep -q "$ver"; then
    printf '%s' "$ver"
  else
    printf 'absent'
  fi
}

_ucc_driver_pyenv_version_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local ver driver_ver
  driver_ver="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.version")"
  [[ -n "$driver_ver" ]] || return 1
  ver="${UIC_PREF_PYTHON_VERSION:-$driver_ver}"
  log_debug "pyenv-version[$target] action=$action: ver='$ver'"
  case "$action" in
    install) ucc_run pyenv install "$ver" && ucc_run pyenv global "$ver" ;;
    update)  ucc_run pyenv install --skip-existing "$ver" && ucc_run pyenv global "$ver" ;;
  esac
}

_ucc_driver_pyenv_version_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local driver_ver ver path
  driver_ver="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.version")"
  [[ -n "$driver_ver" ]] || return 1
  ver="$(python3 --version 2>/dev/null | awk '{print $2}')"
  path="$(pyenv which python3 2>/dev/null || command -v python3 2>/dev/null || true)"
  [[ -n "$ver" ]] || return 1
  printf 'version=%s  path=%s' "$ver" "$path"
}
