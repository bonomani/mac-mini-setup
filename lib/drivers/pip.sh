#!/usr/bin/env bash
# lib/drivers/pip.sh — driver.kind: pip
# driver.probe_pkg:       primary package to probe for presence/version
# driver.install_packages: space-separated list of packages to install/upgrade
# driver.min_version:     minimum required version (empty = no constraint)

_ucc_driver_pip_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local probe min_ver ver
  probe="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.probe_pkg")"
  min_ver="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.min_version")"
  ver="$(_pip_cached_version "$probe")"
  if [[ -z "$ver" ]]; then
    printf 'absent'
    return
  fi
  if [[ -n "$min_ver" ]]; then
    if python3 -c \
      "from packaging.version import Version; import sys; raise SystemExit(0 if Version('$min_ver') <= Version(sys.argv[1]) else 1)" \
      "$ver" 2>/dev/null; then
      printf '%s' "$ver"
    else
      printf 'absent'
    fi
  else
    printf '%s' "$ver"
  fi
}

_ucc_driver_pip_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local pkgs
  pkgs="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.install_packages")"
  case "$action" in
    install) ucc_run pip install -q $pkgs && pip_cache_versions ;;
    update)  ucc_run pip install -q --upgrade $pkgs && pip_cache_versions ;;
  esac
}

_ucc_driver_pip_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local probe ver
  probe="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.probe_pkg")"
  ver="$(_pip_cached_version "$probe")"
  printf 'version=%s  pkg=%s' "${ver:-absent}" "$probe"
}
