#!/usr/bin/env bash
# lib/drivers/custom_daemon.sh — driver.kind: custom-daemon
# driver.process: <pgrep pattern>  (e.g. "ollama (serve|app)")
# driver.bin:     <binary name>    (e.g. ollama)

_ucc_driver_custom_daemon_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local bin
  bin="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin")"
  [[ -n "$bin" ]] || return 1
  if ! command -v "$bin" >/dev/null 2>&1; then
    printf 'absent'
    return
  fi
  local process
  process="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.process")"
  if [[ -n "$process" ]] && pgrep -f "$process" >/dev/null 2>&1; then
    printf 'running'
  else
    printf 'stopped'
  fi
}

_ucc_driver_custom_daemon_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  # Custom daemons are started externally (launchd / manual); no-op here.
  return 1
}

_ucc_driver_custom_daemon_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local bin ver path
  bin="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin")"
  [[ -n "$bin" ]] || return 1
  ver="$("$bin" --version 2>/dev/null | head -1 | awk '{print $NF}')"
  path="$(command -v "$bin" 2>/dev/null || true)"
  [[ -n "$ver" ]] || return 1
  printf 'version=%s  path=%s' "$ver" "$path"
}
