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
# driver.version_probe_path: optional HTTP path on the first endpoint
#                   returning JSON `{"version":"X.Y.Z"}`. When set and
#                   the daemon is running, this is the source of truth
#                   for the installed version (CLI binary may differ
#                   from the running daemon — e.g. Ollama.app bundle
#                   vs. brew-installed CLI). Falls back to `bin --version`.
# driver.install_app_path: optional filesystem path that, when it
#                   exists, signals the daemon is installed as a
#                   macOS .app bundle (self-updating via Squirrel).
#                   Surfaced in evidence as `install=app` vs `install=cli`.
# driver.pending_update_glob: optional filesystem glob pointing to a
#                   staged update bundle (e.g. Squirrel's downloaded
#                   `.zip` in `~/Library/Caches/<app>/updates/*/`).
#                   Surfaced in evidence as `update=pending` when a
#                   match exists. Applying the staged update is the
#                   caller's responsibility — Squirrel-managed apps
#                   need `quitAndInstall()` semantics that can't be
#                   replicated generically across daemons.

_ucc_driver_custom_daemon_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local bin
  bin="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin")"
  [[ -n "$bin" ]] || return 1
  if ! command -v "$bin" >/dev/null 2>&1; then
    printf 'absent'
    return
  fi
  local running=0
  _ucc_driver_custom_daemon_running "$cfg_dir" "$yaml" "$target" && running=1
  # Outdated check: when driver.github_repo is set and a parseable version
  # can be obtained, compare against the latest GitHub release tag.
  # Reuses _pkg_github_latest_tag + _pkg_version_lt helpers from pkg.sh.
  # Version source preference:
  #   1. driver.version_probe_path (authoritative — running daemon version)
  #   2. `bin --version` (CLI binary — may differ from daemon, e.g. Ollama.app)
  if [[ "${UIC_PREF_UPSTREAM_CHECK:-0}" == "1" ]]; then
    local repo; repo="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.github_repo" 2>/dev/null || true)"
    if [[ -n "$repo" ]] && declare -f _pkg_github_latest_tag >/dev/null 2>&1; then
      local installed latest
      installed="$(_ucc_driver_custom_daemon_version "$cfg_dir" "$yaml" "$target" "$running")"
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
  # Default 15s window (30 × 0.5s) — `open -a` is async on macOS and the
  # daemon helper process can take several seconds to spawn under load.
  # Override via UCC_DAEMON_WAIT_S=<seconds>.
  if [[ -n "$process" ]]; then
    local _wait_s="${UCC_DAEMON_WAIT_S:-15}"
    local _attempts=$(( _wait_s * 2 ))  # 0.5s sleeps
    local i=0
    while (( i < _attempts )); do
      pgrep -f "$process" >/dev/null 2>&1 && return 0
      sleep 0.5
      i=$((i + 1))
    done
    log_warn "custom-daemon: ${target} start_cmd ran but process '${process}' did not appear within ${_wait_s}s — returning warn (rc=124) instead of fail"
    return 124
  fi
  return 0
}

# Return 0 iff a file matches the glob (tilde expanded).
# Single responsibility: answer "is an update staged?" for the caller.
_ucc_driver_custom_daemon_pending_update() {
  local glob="$1"
  [[ -n "$glob" ]] || return 1
  # Expand ~ via eval — glob comes from YAML (trusted config), not user input.
  local expanded
  eval "expanded=$glob" 2>/dev/null || return 1
  compgen -G "$expanded" >/dev/null 2>&1
}

# Return 0 iff the daemon is running. Two signals, checked in order:
#   1. pgrep matches driver.process pattern (cheap, local)
#   2. HTTP probe on first endpoint (authoritative, catches externally-
#      managed daemons where the pgrep pattern races or misses — e.g.
#      Ollama.app vs. brew install; both expose the same API, but pgrep
#      matches only one at a time during start/restart transitions).
_ucc_driver_custom_daemon_running() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local process
  process="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.process" 2>/dev/null || true)"
  [[ -n "$process" ]] && pgrep -f "$process" >/dev/null 2>&1 && return 0
  declare -f _ucc_http_probe_endpoint >/dev/null 2>&1 || return 1
  _ucc_http_probe_endpoint "$cfg_dir" "$yaml" "$target" "" 2>/dev/null
}

# Resolve the installed version of the daemon.
# Preference: driver.version_probe_path (when the daemon is running) →
# `bin --version` fallback. Caller passes `running` flag (0|1) so we skip
# the HTTP probe when the daemon is known to be down.
_ucc_driver_custom_daemon_version() {
  local cfg_dir="$1" yaml="$2" target="$3" running="${4:-0}"
  local probe_path ver bin
  probe_path="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.version_probe_path" 2>/dev/null || true)"
  if [[ -n "$probe_path" && "$running" == "1" ]]; then
    local base url
    if base="$(_ucc_endpoint_base_url "$cfg_dir" "$yaml" "$target" "" 2>/dev/null)"; then
      [[ "$probe_path" == /* ]] || probe_path="/$probe_path"
      url="${base}${probe_path}"
      ver="$(curl -fsS --max-time "$(_ucc_curl_timeout probe)" "$url" 2>/dev/null \
        | grep -oE '[0-9]+(\.[0-9]+){1,3}' | head -1)"
    fi
  fi
  if [[ -z "$ver" ]]; then
    bin="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin" 2>/dev/null || true)"
    [[ -n "$bin" ]] || return 1
    ver="$("$bin" --version 2>/dev/null | head -1 \
      | grep -oE '[0-9]+(\.[0-9]+){1,3}' | head -1)"
  fi
  [[ -n "$ver" ]] || return 1
  printf '%s' "$ver"
}

_ucc_driver_custom_daemon_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local bin ver path log_path app_path running=0 install_kind glob update_state
  bin="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin")"
  [[ -n "$bin" ]] || return 1
  _ucc_driver_custom_daemon_running "$cfg_dir" "$yaml" "$target" && running=1
  ver="$(_ucc_driver_custom_daemon_version "$cfg_dir" "$yaml" "$target" "$running" 2>/dev/null || true)"
  path="$(command -v "$bin" 2>/dev/null || true)"
  log_path="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.log_path" 2>/dev/null || true)"
  app_path="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.install_app_path" 2>/dev/null || true)"
  if [[ -n "$app_path" && -e "$app_path" ]]; then
    install_kind="app"
  elif [[ -n "$app_path" ]]; then
    install_kind="cli"
  fi
  glob="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.pending_update_glob" 2>/dev/null || true)"
  if [[ -n "$glob" ]] && _ucc_driver_custom_daemon_pending_update "$glob"; then
    update_state="pending"
  fi
  [[ -n "$ver" ]] || return 1
  printf 'version=%s' "$ver"
  [[ -n "$install_kind" ]] && printf '  install=%s' "$install_kind"
  [[ -n "$update_state" ]] && printf '  update=%s' "$update_state"
  [[ -n "$path"         ]] && printf '  path=%s' "$path"
  [[ -n "$log_path"     ]] && printf '  log=%s' "$log_path"
  # latest= appended by generic _ucc_driver_github_latest in ucc_drivers.sh
}
