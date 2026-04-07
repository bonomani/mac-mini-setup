#!/usr/bin/env bash
# lib/drivers/custom_daemon.sh — driver.kind: custom-daemon
# driver.process:  <pgrep pattern>  (e.g. "ollama (serve|app)")
# driver.bin:      <binary name>    (e.g. ollama)
# driver.log_path: optional log file path (surfaced in evidence)
# driver.start_cmd: optional command to start the daemon (e.g.
#                   "open -a Ollama"). When set, the install action
#                   runs it and waits up to 5s for the process to
#                   appear. When unset, action stays a no-op
#                   (backward compatible).

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
  local start_cmd process
  start_cmd="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.start_cmd" 2>/dev/null || true)"
  process="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.process" 2>/dev/null || true)"
  # No start_cmd → keep historical no-op behavior (the daemon is started
  # externally — launchd, manual, or the package's own install hook).
  [[ -n "$start_cmd" ]] || return 1
  ucc_run sh -c "$start_cmd" || return $?
  # Wait briefly for the process to appear, so observe sees "running".
  if [[ -n "$process" ]]; then
    local i=0
    while (( i < 10 )); do
      pgrep -f "$process" >/dev/null 2>&1 && return 0
      sleep 0.5
      i=$((i + 1))
    done
    log_warn "custom-daemon: ${target} start_cmd ran but process '${process}' did not appear within 5s"
    return 1
  fi
  return 0
}

_ucc_driver_custom_daemon_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local bin ver path log_path
  bin="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin")"
  [[ -n "$bin" ]] || return 1
  ver="$("$bin" --version 2>/dev/null | head -1 | awk '{print $NF}')"
  path="$(command -v "$bin" 2>/dev/null || true)"
  log_path="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.log_path" 2>/dev/null || true)"
  [[ -n "$ver" ]] || return 1
  printf 'version=%s' "$ver"
  [[ -n "$path"     ]] && printf '  path=%s' "$path"
  [[ -n "$log_path" ]] && printf '  log=%s' "$log_path"
  # latest= appended by generic _ucc_driver_github_latest in ucc_drivers.sh
}
