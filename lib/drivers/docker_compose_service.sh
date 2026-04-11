#!/usr/bin/env bash
# lib/drivers/docker_compose_service.sh — driver.kind: docker-compose-service
# driver.service_name: <compose service name>  (e.g. flowise)
#
# Observe: checks container running state + HTTP endpoint probe (first endpoint).
# Evidence: version/digest/ref from running container image metadata.
# Action: delegates to _ai_apply_compose_runtime (defined by ai_apps runner).

_ucc_driver_docker_compose_service_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local svc
  svc="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.service_name")"
  [[ -n "$svc" ]] || return 1
  if ! docker ps --filter "name=${svc}" --filter "status=running" --format '{{.Names}}' 2>/dev/null | grep -q .; then
    printf 'stopped'
    return
  fi
  if _ucc_http_probe_endpoint "$cfg_dir" "$yaml" "$target"; then
    printf 'running'
  else
    printf 'stopped'
  fi
}

_ucc_driver_docker_compose_service_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  declare -f _ai_apply_compose_runtime >/dev/null 2>&1 || return 1
  _ai_apply_compose_runtime
}

_ucc_driver_docker_compose_service_recover() {
  local cfg_dir="$1" yaml="$2" target="$3" level="$4"
  local svc
  svc="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.service_name")"
  [[ -n "$svc" ]] || return 1
  case "$level" in
    1) # Restart container
      docker compose restart "$svc" 2>/dev/null || docker restart "$svc" 2>/dev/null
      ;;
    2) # Recreate container
      docker compose down "$svc" 2>/dev/null || docker stop "$svc" 2>/dev/null
      docker compose up -d "$svc" 2>/dev/null || return 1
      ;;
    3) # Pull fresh image + recreate
      docker compose pull "$svc" 2>/dev/null || true
      docker compose down "$svc" 2>/dev/null || docker stop "$svc" 2>/dev/null
      docker compose up -d "$svc" 2>/dev/null || return 1
      ;;
    *) return 2 ;;  # level not supported
  esac
}

_ucc_driver_docker_compose_service_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local svc
  svc="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.service_name")"
  [[ -n "$svc" ]] || return 1
  declare -f _ai_service_runtime_version >/dev/null 2>&1 || return 1
  local ver digest ref out=""
  ver="$(_ai_service_runtime_version "$svc")"
  digest="$(_ai_service_runtime_digest "$svc")"
  ref="$(_ai_service_runtime_ref "$svc")"
  [[ -n "$ver"    ]] && out="version=$ver"
  [[ -n "$digest" ]] && out="${out:+$out  }digest=$digest"
  [[ -n "$ref"    ]] && out="${out:+$out  }ref=$ref"
  out="${out:+$out  }log=docker logs ${svc}"
  printf '%s' "$out"
}
