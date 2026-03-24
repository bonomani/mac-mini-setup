#!/usr/bin/env bash
# lib/ai_apps.sh — Docker Compose AI stack targets
# Sourced by components/07-ai-apps.sh

# Usage: run_ai_apps_from_yaml <cfg_dir> <yaml_path>
run_ai_apps_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local _raw_compose_dir
  _raw_compose_dir="$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" compose_dir 2>/dev/null)"
  COMPOSE_DIR="$HOME/${_raw_compose_dir:-.ai-stack}"
  COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
  COMPOSE_MARKER="$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" compose_marker 2>/dev/null)"

  AI_SERVICES=()
  while IFS= read -r _svc; do [[ -n "$_svc" ]] && AI_SERVICES+=("$_svc"); done \
    < <(python3 "$cfg_dir/tools/read_config.py" --list "$yaml" services 2>/dev/null)
  STACK_SERVICES="${#AI_SERVICES[@]}"

  # Store cfg_dir for use by _write_compose_file (bash functions are global)
  _AI_APPS_CFG_DIR="$cfg_dir"

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
  _evidence_docker_running() {
    local ver
    ver=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
    [[ -n "$ver" ]] && printf 'version=%s daemon=running' "$ver" || printf 'daemon=running'
  }
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
    --desired "$(ucc_asm_state --installation Configured --runtime Running \
                               --health Healthy --admin Enabled --dependencies DepsReady)" \
    --install _start_docker

  # Abort if Docker still not running
  docker info &>/dev/null 2>&1 || {
    log_warn "Docker not running — skipping AI stack"
    return 1
  }

  # ---- Compose file ----
  _observe_compose_file() {
    local raw
    raw=$([[ -f "$COMPOSE_FILE" ]] && grep -q "$COMPOSE_MARKER" "$COMPOSE_FILE" \
      && echo "present" || echo "absent")
    ucc_asm_config_state "$raw"
  }
  _evidence_compose_file() { printf 'path=%s' "$COMPOSE_FILE"; }
  _write_compose_file() {
    ucc_run mkdir -p "$COMPOSE_DIR"
    ucc_run cp "$_AI_APPS_CFG_DIR/stack/docker-compose.yml" "$COMPOSE_FILE"
  }

  ucc_target_nonruntime --name "ai-stack-compose-file" \
    --observe _observe_compose_file \
    --evidence _evidence_compose_file \
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
    printf 'running=%s/%s compose=%s' "$running" "$STACK_SERVICES" "$COMPOSE_FILE"
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
    ucc_run docker compose -f "$COMPOSE_FILE" up -d
  }
  _update_stack() {
    ucc_run docker compose -f "$COMPOSE_FILE" pull
    ucc_run docker compose -f "$COMPOSE_FILE" up -d
  }

  ucc_target_service --name "ai-stack-running" \
    --observe _observe_stack \
    --evidence _evidence_stack \
    --desired "$(ucc_asm_state --installation Configured --runtime Running \
                               --health Healthy --admin Enabled --dependencies DepsReady)" \
    --install _start_stack --update _update_stack
}
