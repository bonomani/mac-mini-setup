#!/usr/bin/env bash
# lib/drivers/compose_file.sh — driver.kind: compose-file
# driver.path_env: <env var name holding the compose file path>  (e.g. COMPOSE_FILE)
# Falls back to $COMPOSE_FILE if driver.path_env is not set.

_ucc_driver_compose_file_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local path_env compose_path
  path_env="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.path_env")"
  compose_path="${!path_env:-${COMPOSE_FILE:-}}"
  [[ -n "$compose_path" ]] || return 1
  if [[ -f "$compose_path" ]]; then
    printf 'configured'
  else
    printf 'absent'
  fi
}

_ucc_driver_compose_file_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  # Compose file is generated externally; no action needed.
  return 1
}

_ucc_driver_compose_file_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local path_env compose_path
  path_env="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.path_env")"
  compose_path="${!path_env:-${COMPOSE_FILE:-}}"
  [[ -n "$compose_path" ]] || return 1
  printf 'path=%s' "$compose_path"
}
