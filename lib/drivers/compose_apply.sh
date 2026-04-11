#!/usr/bin/env bash
# lib/drivers/compose_apply.sh — driver.kind: compose-apply
#
# First-class "the compose stack is up" target. Replaces the older
# sentinel-based pattern where each per-service runtime target shared a
# single install action via a hidden sentinel file in the component
# runner. With this driver, a single target owns `docker compose up -d`,
# and N pure-observe per-service targets depend on it — matching the
# docker-desktop → docker-available / pytorch → mps-available pattern
# the framework already uses at 1→1 scale.
#
# driver.path_env:        env var name holding the absolute compose file path
#                         (set by the component runner). Falls back to $COMPOSE_FILE.
# driver.pull_policy_env: optional env var name whose value gates `docker compose
#                         pull`. If the env var resolves to "always-pull", the
#                         driver runs pull before up. Any other value (or unset)
#                         means "reuse-local" — skip pull.

_ucc_driver_compose_apply_resolve_path() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local path_env
  path_env="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.path_env")"
  if [[ -n "$path_env" ]]; then
    printf '%s' "${!path_env:-}"
  else
    printf '%s' "${COMPOSE_FILE:-}"
  fi
}

_ucc_driver_compose_apply_resolve_pull_policy() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local policy_env
  policy_env="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.pull_policy_env" 2>/dev/null || true)"
  [[ -n "$policy_env" ]] || { printf ''; return; }
  printf '%s' "${!policy_env:-}"
}

_ucc_driver_compose_apply_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local compose_path
  compose_path="$(_ucc_driver_compose_apply_resolve_path "$cfg_dir" "$yaml" "$target")"
  [[ -n "$compose_path" && -f "$compose_path" ]] || { printf 'stopped'; return; }

  # Fast check: docker available at all?
  command -v docker >/dev/null 2>&1 || { printf 'stopped'; return; }

  # Get the list of services declared in the compose file. `docker compose
  # config --services` parses the file and prints one service name per line.
  local services
  services="$(docker compose -f "$compose_path" config --services 2>/dev/null)"
  [[ -n "$services" ]] || { printf 'stopped'; return; }

  # Every declared service must have a running container. The default
  # compose project name is the compose file's parent directory basename,
  # and containers are named <project>-<service>-1 or <project>_<service>_1
  # depending on compose version — so we match on the service name
  # suffix, not an exact name. Container states tracked via `docker ps
  # --filter status=running --format '{{.Names}}'`.
  local running
  running="$(docker ps --filter status=running --format '{{.Names}}' 2>/dev/null)"
  local svc
  while IFS= read -r svc; do
    [[ -n "$svc" ]] || continue
    # Accept either exact name (legacy) or compose-project-prefixed name.
    if ! printf '%s\n' "$running" | grep -qE "(^|-|_)${svc}($|-|_)"; then
      printf 'stopped'
      return
    fi
  done <<< "$services"
  printf 'running'
}

_ucc_driver_compose_apply_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local compose_path pull_policy
  compose_path="$(_ucc_driver_compose_apply_resolve_path "$cfg_dir" "$yaml" "$target")"
  pull_policy="$(_ucc_driver_compose_apply_resolve_pull_policy "$cfg_dir" "$yaml" "$target")"
  [[ -n "$compose_path" ]] || { log_warn "compose-apply: path unset"; return 1; }
  [[ -f "$compose_path" ]] || { log_warn "compose-apply: file not found: $compose_path"; return 1; }
  if [[ "$pull_policy" == "always-pull" ]]; then
    ucc_run docker compose -f "$compose_path" pull
  fi
  ucc_run docker compose -f "$compose_path" up -d
}

_ucc_driver_compose_apply_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local compose_path
  compose_path="$(_ucc_driver_compose_apply_resolve_path "$cfg_dir" "$yaml" "$target")"
  [[ -n "$compose_path" ]] || return 1
  local svc_count=0
  if [[ -f "$compose_path" ]]; then
    svc_count="$(docker compose -f "$compose_path" config --services 2>/dev/null | grep -c . || printf 0)"
  fi
  printf 'file=%s  services=%s' "$compose_path" "$svc_count"
}
