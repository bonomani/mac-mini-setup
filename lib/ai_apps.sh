#!/usr/bin/env bash
# lib/ai_apps.sh — Docker Compose AI stack targets
# Sourced by components/ai-apps.sh

# Usage: run_ai_apps_from_yaml <cfg_dir> <yaml_path>
run_ai_apps_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local compose_dir_rel compose_file_name stack_template_rel
  compose_dir_rel="$(yaml_get "$cfg_dir" "$yaml" stack.compose_dir)"
  [[ -n "$compose_dir_rel" ]] || compose_dir_rel="$(yaml_get "$cfg_dir" "$yaml" compose_dir .ai-stack)"
  compose_file_name="$(yaml_get "$cfg_dir" "$yaml" stack.compose_file docker-compose.yml)"
  stack_template_rel="$(yaml_get "$cfg_dir" "$yaml" stack.definition_template stack/docker-compose.yml)"

  COMPOSE_DIR="$HOME/${compose_dir_rel}"
  COMPOSE_FILE="$COMPOSE_DIR/${compose_file_name}"
  COMPOSE_MARKER="$(yaml_get "$cfg_dir" "$yaml" stack.marker)"
  [[ -n "$COMPOSE_MARKER" ]] || COMPOSE_MARKER="$(yaml_get "$cfg_dir" "$yaml" compose_marker "")"

  AI_SERVICES=()
  while IFS= read -r _svc; do [[ -n "$_svc" ]] && AI_SERVICES+=("$_svc"); done \
    < <(yaml_list "$cfg_dir" "$yaml" stack.services)
  if [[ ${#AI_SERVICES[@]} -eq 0 ]]; then
    while IFS= read -r _svc; do [[ -n "$_svc" ]] && AI_SERVICES+=("$_svc"); done \
      < <(yaml_list "$cfg_dir" "$yaml" services)
  fi
  STACK_SERVICES="${#AI_SERVICES[@]}"
  STACK_SIGNATURE="$(printf '%s\n' "${AI_SERVICES[@]}" | LC_ALL=C sort | paste -sd, -)"
  STACK_DEFINITION_VALUE="marker=${COMPOSE_MARKER} services=${STACK_SIGNATURE}"
  IMAGE_POLICY="${UIC_PREF_AI_APPS_IMAGE_POLICY:-reuse-local}"

  # Store cfg_dir for use by _write_compose_file (bash functions are global)
  _AI_APPS_CFG_DIR="$cfg_dir"

  _ai_stack_signature() {
    local file="$1"
    python3 - "$file" <<'PY' 2>/dev/null
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
if not path.exists():
    raise SystemExit(1)

data = yaml.safe_load(path.read_text()) or {}
services = data.get("services")
if not isinstance(services, dict):
    raise SystemExit(1)

print(",".join(sorted(services.keys())))
PY
  }

  # ---- Docker running ----
  _observe_docker_running() {
    if [[ -d "/Applications/Docker.app" ]] || command -v docker >/dev/null 2>&1; then
      if docker info &>/dev/null 2>&1; then
        ucc_asm_state --installation Configured --runtime Running \
          --health Healthy --admin Enabled --dependencies DepsReady
      else
        ucc_asm_state --installation Installed --runtime Stopped \
          --health Unavailable --admin Enabled --dependencies DepsFailed
      fi
    else
      ucc_asm_state --installation Absent --runtime NeverStarted \
        --health Unavailable --admin Enabled --dependencies DepsUnknown
    fi
  }
  _evidence_docker_running() { ucc_eval_evidence_from_yaml "$cfg_dir" "$yaml" "docker-running"; }
  _start_docker() {
    if [[ "${UIC_PREF_SERVICE_POLICY:-autostart}" != "autostart" ]]; then
      log_warn "Docker not running — start it manually (service-policy=manual)"
      return 1
    fi
    log_info "Starting Docker Desktop (service-policy=autostart)..."
    open -a Docker
    for i in $(seq 1 24); do
      docker info &>/dev/null 2>&1 && return 0
      log_debug "Waiting for Docker daemon ($i/24)..."
      sleep 5
    done
    log_warn "Docker daemon did not start in time"
    return 1
  }

  ucc_target_service \
    --name    "docker-running" \
    --observe _observe_docker_running \
    --evidence _evidence_docker_running \
    --desired "$(ucc_asm_runtime_desired)" \
    --install _start_docker

  # Abort if Docker still not running
  docker info &>/dev/null 2>&1 || {
    log_warn "Docker not running — skipping AI stack"
    return 1
  }

  # ---- Compose file ----
  _observe_compose_file() {
    local actual_sig=""
    [[ -f "$COMPOSE_FILE" ]] || {
      ucc_asm_config_state "absent" "$STACK_DEFINITION_VALUE"
      return
    }

    actual_sig="$(_ai_stack_signature "$COMPOSE_FILE" || true)"
    if [[ -z "$actual_sig" ]]; then
      ucc_asm_config_state "needs-update" "$STACK_DEFINITION_VALUE"
      return
    fi

    if grep -qF "$COMPOSE_MARKER" "$COMPOSE_FILE" 2>/dev/null && [[ "$actual_sig" == "$STACK_SIGNATURE" ]]; then
      ucc_asm_config_state "$STACK_DEFINITION_VALUE" "$STACK_DEFINITION_VALUE"
    else
      ucc_asm_config_state "marker=$(grep -qF "$COMPOSE_MARKER" "$COMPOSE_FILE" 2>/dev/null && echo present || echo missing) services=${actual_sig}" "$STACK_DEFINITION_VALUE"
    fi
  }
  _evidence_compose_file() {
    local actual_sig=""
    actual_sig="$(_ai_stack_signature "$COMPOSE_FILE" || true)"
    printf 'path=%s  services=%s' "$COMPOSE_FILE" "${actual_sig:-unknown}"
  }
  _write_compose_file() {
    ucc_run mkdir -p "$COMPOSE_DIR"
    ucc_run cp "$_AI_APPS_CFG_DIR/${stack_template_rel}" "$COMPOSE_FILE"
  }

  ucc_target --name "ai-stack-compose-file" \
    --profile parametric \
    --observe _observe_compose_file \
    --evidence _evidence_compose_file \
    --desired "$(ucc_asm_config_desired "$STACK_DEFINITION_VALUE")" \
    --install _write_compose_file --update _write_compose_file

  # ---- Stack running ----
  _observe_stack() {
    [[ -f "$COMPOSE_FILE" ]] || {
      ucc_asm_state --installation Absent --runtime Stopped \
        --health Unavailable --admin Enabled --dependencies DepsFailed
      return
    }
    local svc state
    for svc in "${AI_SERVICES[@]}"; do
      state=$(docker inspect --format '{{.State.Status}}' "$svc" 2>/dev/null) || {
        ucc_asm_state --installation Configured --runtime Stopped \
          --health Unavailable --admin Enabled --dependencies DepsFailed
        return
      }
      [[ "$state" == "running" ]] || {
        ucc_asm_state --installation Configured --runtime Stopped \
          --health Degraded --admin Enabled --dependencies DepsDegraded
        return
      }
    done
    ucc_asm_state --installation Configured --runtime Running \
      --health Healthy --admin Enabled --dependencies DepsReady
  }
  _evidence_stack() {
    local running=0 svc state
    for svc in "${AI_SERVICES[@]}"; do
      state=$(docker inspect --format '{{.State.Status}}' "$svc" 2>/dev/null || true)
      [[ "$state" == "running" ]] && running=$((running + 1))
    done
    printf 'running=%s/%s  compose=%s' "$running" "$STACK_SERVICES" "$COMPOSE_FILE"
  }
  _remove_legacy_containers() {
    local name
    for name in "${AI_SERVICES[@]}"; do
      if docker inspect "$name" &>/dev/null 2>&1; then
        log_info "Removing legacy container: $name"
        docker stop "$name" 2>/dev/null || true
        docker rm   "$name" 2>/dev/null || true
      fi
    done
  }
  _start_stack() {
    _remove_legacy_containers
    if [[ "$IMAGE_POLICY" == "always-pull" ]]; then
      ucc_run docker compose -f "$COMPOSE_FILE" pull
    fi
    ucc_run docker compose -f "$COMPOSE_FILE" up -d
  }
  _update_stack() {
    if [[ "$IMAGE_POLICY" == "always-pull" ]]; then
      ucc_run docker compose -f "$COMPOSE_FILE" pull
    fi
    ucc_run docker compose -f "$COMPOSE_FILE" up -d
  }

  ucc_target_service --name "ai-stack-running" \
    --observe _observe_stack \
    --evidence _evidence_stack \
    --desired "$(ucc_asm_runtime_desired)" \
    --install _start_stack --update _update_stack
}
