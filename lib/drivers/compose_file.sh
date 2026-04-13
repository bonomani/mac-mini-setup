#!/usr/bin/env bash
# lib/drivers/compose_file.sh — driver.kind: compose-file
# driver.path_env: <env var name holding the compose file path>  (e.g. COMPOSE_FILE)
# Falls back to $COMPOSE_FILE if driver.path_env is not set.

_compose_file_resolve_path() {
  local path_env
  path_env="$(_ucc_yaml_target_get "$1" "$2" "$3" "driver.path_env")"
  printf '%s' "${!path_env:-${COMPOSE_FILE:-}}"
}

_ucc_driver_compose_file_observe() {
  local compose_path
  compose_path="$(_compose_file_resolve_path "$1" "$2" "$3")"
  [[ -n "$compose_path" ]] || return 1
  if [[ -f "$compose_path" ]]; then
    printf 'configured'
  else
    printf 'absent'
  fi
}

_ucc_driver_compose_file_action() {
  # Compose file is generated externally; no action needed.
  return 1
}

_ucc_driver_compose_file_evidence() {
  local compose_path
  compose_path="$(_compose_file_resolve_path "$1" "$2" "$3")"
  [[ -n "$compose_path" ]] || return 1
  printf 'path=%s' "$compose_path"
}
