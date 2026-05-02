#!/usr/bin/env bash
# lib/drivers/docker_compose_service.sh — driver.kind: docker-compose-service
# driver.service_name: <compose service name>  (e.g. flowise)
#
# Observe-only driver: checks container running state + HTTP endpoint
# probe (first endpoint) with bounded retry-with-backoff for fresh
# containers. The actual `docker compose up -d` is handled by an
# upstream compose-apply target that these per-service runtime targets
# depend on — see lib/drivers/compose_apply.sh and docs/PLAN.md's B4
# entry. No _action hook here — the framework treats this as "observe
# only, upstream already applied".
#
# Evidence: version/digest/ref from running container image metadata
# (via evidence functions defined in each component's runner lib).

_ucc_driver_docker_compose_service_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local svc
  svc="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.service_name")"
  [[ -n "$svc" ]] || return 1

  # Gate 1: container is actually running. Fail fast if not — no retry.
  if ! docker ps --filter "name=${svc}" --filter "status=running" --format '{{.Names}}' 2>/dev/null | grep -q .; then
    printf 'stopped'
    return
  fi

  # Gate 2: HTTP endpoint probe with bounded retry-with-backoff.
  #
  # On a healthy already-running service the first probe succeeds in
  # <1s and we return 'running' immediately. On a fresh `docker compose
  # up -d`, the container is running but the app inside is still
  # initializing (Open WebUI downloads models, Flowise sets up its DB,
  # etc.) so the first probe fails. Previously we'd return 'stopped'
  # here, the runtime target would be reported [fail], and the next
  # run would find the service healthy — a confusing false-negative
  # on the first post-bootstrap run of ./install.sh.
  #
  # Retry budget: up to ~64s cumulative (default delays 0,2,5,10,15,20 +
  # 2s curl max-time per probe). Healthy services pay ~1s; fresh services
  # get enough slack for typical startup; genuinely-broken services take
  # the full budget before reporting stopped.
  # Override via UCC_COMPOSE_PROBE_DELAYS (space-separated seconds).
  local delays
  read -r -a delays <<< "${UCC_COMPOSE_PROBE_DELAYS:-0 2 5 10 15 20}"
  local d
  for d in "${delays[@]}"; do
    [[ $d -gt 0 ]] && sleep "$d"
    if _ucc_http_probe_endpoint_timeout "$cfg_dir" "$yaml" "$target" "" 2; then
      printf 'running'
      return
    fi
  done

  # Container was running at Gate 1 and (typically) still is, but the HTTP
  # probe never succeeded within the retry budget. Re-check container state
  # so we report the truth: if it died during retries → 'stopped'; if it's
  # still up → 'running-degraded' (process alive, health probe failing).
  if docker ps --filter "name=${svc}" --filter "status=running" --format '{{.Names}}' 2>/dev/null | grep -q .; then
    printf 'running-degraded'
  else
    printf 'stopped'
  fi
}

# No _action hook. The apply is owned by the upstream compose-apply
# target that these runtime targets depend on. The framework's dep
# ordering ensures the stack is already up by the time observe runs.

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
