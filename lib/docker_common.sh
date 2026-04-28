#!/usr/bin/env bash
# lib/docker_common.sh — portable Docker daemon helpers (macOS + Linux + WSL).
#
# Holds only socket-level / API-level probes and the cross-platform
# `_docker_daemon_start` dispatcher. Platform-specific app logic lives in
# `lib/docker_desktop_macos.sh` and `lib/docker_engine.sh`.

# Return 0 if the Docker daemon socket exists on the host.
docker_daemon_configured() {
  [[ -S "$(docker_socket_path)" ]]
}

# Print Docker daemon version (e.g. "27.3.1") via socket; falls back to CLI.
docker_version() {
  local sock; sock="$(docker_socket_path)"
  if [[ -S "$sock" ]]; then
    curl -sf --unix-socket "$sock" http://localhost/version 2>/dev/null \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('Version',''))" 2>/dev/null
  else
    docker --version 2>/dev/null | awk '{print $3}' | tr -d ','
  fi
}

# Probe Docker daemon readiness via the API socket; falls back to CLI.
_docker_ready() {
  local sock; sock="$(docker_socket_path)"
  if [[ -S "$sock" ]]; then
    curl -sf --unix-socket "$sock" http://localhost/_ping >/dev/null 2>&1
  else
    docker ps -q >/dev/null 2>&1
  fi
}

# Register all Docker targets. Portable; per-target `requires:` gates
# macOS-only targets at the YAML layer.
run_docker_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  ucc_yaml_runtime_target "$cfg_dir" "$yaml" "docker-desktop"
  ucc_yaml_runtime_target "$cfg_dir" "$yaml" "docker-daemon"
  ucc_yaml_capability_target "$cfg_dir" "$yaml" "docker-available"
  ucc_yaml_parametric_target "$cfg_dir" "$yaml" "docker-resources"
  ucc_yaml_parametric_target "$cfg_dir" "$yaml" "docker-privileged-ports"
}

# Dispatcher: routes to Docker Desktop launch on macOS, or to existing
# Docker Engine on Linux/WSL. Uses implicit $CFG_DIR/$YAML_PATH context.
_docker_daemon_start() {
  if [[ "${HOST_PLATFORM:-macos}" != "macos" ]]; then
    _docker_engine_start
    return $?
  fi

  local settings_relpath app_path
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      settings_relpath)          settings_relpath="$value" ;;
      docker_desktop_app_path)   app_path="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" settings_relpath docker_desktop_app_path)
  _docker_strip_quarantine "$app_path"
  _docker_settings_store_patch "$settings_relpath"

  _docker_launch
}
