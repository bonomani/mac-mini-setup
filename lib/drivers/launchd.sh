#!/usr/bin/env bash
# lib/drivers/launchd.sh — driver.kind: launchd
# driver.plist: <launchd label>  (e.g. ai.unsloth.studio)

_ucc_driver_launchd_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local plist
  plist="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.plist")"
  [[ -n "$plist" ]] || return 1
  local plist_file="$HOME/Library/LaunchAgents/${plist}.plist"
  if [[ ! -f "$plist_file" ]]; then
    printf 'absent'
    return
  fi
  if launchctl list 2>/dev/null | grep -q "$plist"; then
    printf 'running'
  else
    printf 'stopped'
  fi
}

_ucc_driver_launchd_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local plist
  plist="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.plist")"
  [[ -n "$plist" ]] || return 1
  local plist_file="$HOME/Library/LaunchAgents/${plist}.plist"
  case "$action" in
    install) ucc_run launchctl load "$plist_file" ;;
    update)  ucc_run launchctl unload "$plist_file" 2>/dev/null || true
             ucc_run launchctl load "$plist_file" ;;
  esac
}

_ucc_driver_launchd_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local plist
  plist="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.plist")"
  [[ -n "$plist" ]] || return 1
  printf 'plist=%s/Library/LaunchAgents/%s.plist' "$HOME" "$plist"
}
