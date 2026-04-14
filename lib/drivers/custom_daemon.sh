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
  # Determine running state.
  local process running=0
  process="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.process")"
  if [[ -n "$process" ]] && pgrep -f "$process" >/dev/null 2>&1; then
    running=1
  fi
  # Outdated check: when driver.github_repo is set and the binary reports
  # a parseable version, compare against the latest GitHub release tag.
  # Reuses _pkg_github_latest_tag + _pkg_version_lt helpers from pkg.sh.
  if [[ "${UIC_PREF_UPSTREAM_CHECK:-0}" == "1" ]]; then
    local repo; repo="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.github_repo" 2>/dev/null || true)"
    if [[ -n "$repo" ]] && declare -f _pkg_github_latest_tag >/dev/null 2>&1; then
      local installed latest
      installed="$("$bin" --version 2>/dev/null | head -1 \
        | grep -oE '[0-9]+(\.[0-9]+){1,3}' | head -1)"
      latest="$(_pkg_github_latest_tag "$repo" 2>/dev/null)"
      if [[ -n "$installed" && -n "$latest" ]] \
         && declare -f _pkg_version_lt >/dev/null 2>&1 \
         && _pkg_version_lt "$installed" "$latest"; then
        printf 'outdated'
        return
      fi
    fi
  fi
  if (( running )); then
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
  # Fall back to top-level fallback_start_cmd when driver.start_cmd unset
  # (e.g. ollama: app-installed, no per-driver start; rely on top-level cmd).
  if [[ -z "$start_cmd" ]]; then
    while IFS=$'\t' read -r -d '' key value; do
      [[ "$key" == "fallback_start_cmd" ]] && start_cmd="$value"
    done < <(yaml_get_many "$cfg_dir" "$yaml" fallback_start_cmd 2>/dev/null || true)
  fi
  # Still no start_cmd → return 124 (warn) instead of 1 (fail). The daemon
  # is meant to be started externally (launchd, manual). Reporting "fail"
  # confused operators when the daemon was actually running via Ollama.app
  # but pgrep raced with our observe.
  [[ -n "$start_cmd" ]] || return 124
  ucc_run sh -c "$start_cmd" || return $?
  # Wait for the process to appear, so observe sees "running".
  # Bumped from 5s → 15s: `open -a` is async on macOS and the daemon helper
  # process can take several seconds to spawn under load.
  if [[ -n "$process" ]]; then
    local i=0
    while (( i < 30 )); do
      pgrep -f "$process" >/dev/null 2>&1 && return 0
      sleep 0.5
      i=$((i + 1))
    done
    log_warn "custom-daemon: ${target} start_cmd ran but process '${process}' did not appear within 15s — returning warn (rc=124) instead of fail"
    return 124
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
