#!/usr/bin/env bash
# Component: AI Applications via Docker Compose
# BGS: UCC + Basic — bash 3.2 compatible (no declare -A)
#
# BISS: Axis A = UCC (state convergence — compose file present + containers running)
#       Axis B = Basic
# Boundary: local filesystem · Docker daemon API · network (image pulls)

# Load compose config from YAML — see config/07-ai-apps.yaml
_AI_CFG_DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
_AI_CFG="$_AI_CFG_DIR/config/07-ai-apps.yaml"

_raw_compose_dir="$(python3 "$_AI_CFG_DIR/tools/read_config.py" --get "$_AI_CFG" compose_dir 2>/dev/null)"
COMPOSE_DIR="$HOME/${_raw_compose_dir:-.ai-stack}"

AI_SERVICES=()
while IFS= read -r _svc; do [[ -n "$_svc" ]] && AI_SERVICES+=("$_svc"); done \
  < <(python3 "$_AI_CFG_DIR/tools/read_config.py" --list "$_AI_CFG" services 2>/dev/null)
STACK_SERVICES="${#AI_SERVICES[@]}"

# --- Docker running -----------------------------------------
_observe_docker_running() {
  if [[ -d "/Applications/Docker.app" ]] || command -v docker >/dev/null 2>&1; then
    if docker info &>/dev/null 2>&1; then
      ucc_asm_state \
        --installation Configured \
        --runtime Running \
        --health Healthy \
        --admin Enabled \
        --dependencies DepsReady
    else
      ucc_asm_state \
        --installation Installed \
        --runtime Stopped \
        --health Unavailable \
        --admin Enabled \
        --dependencies DepsFailed
    fi
  else
    ucc_asm_state \
      --installation Absent \
      --runtime NeverStarted \
      --health Unavailable \
      --admin Enabled \
      --dependencies DepsUnknown
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
  --desired "$(ucc_asm_state --installation Configured --runtime Running --health Healthy --admin Enabled --dependencies DepsReady)" \
  --install _start_docker

# Abort component if Docker still not running after attempting to start
docker info &>/dev/null 2>&1 || { log_warn "Docker not running — skipping AI stack"; ucc_summary "07-ai-apps"; exit 0; }

COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
COMPOSE_MARKER="$(python3 "$_AI_CFG_DIR/tools/read_config.py" --get "$_AI_CFG" compose_marker 2>/dev/null)"

# ============================================================
# Compose file — deploy from repo into ~/.ai-stack/
# ============================================================
_observe_compose_file() {
  local raw
  raw=$([[ -f "$COMPOSE_FILE" ]] && grep -q "$COMPOSE_MARKER" "$COMPOSE_FILE" \
    && echo "present" || echo "absent")
  ucc_asm_config_state "$raw"
}
_evidence_compose_file() { printf 'path=%s' "$COMPOSE_FILE"; }

_write_compose_file() {
  ucc_run mkdir -p "$COMPOSE_DIR"
  # BASH_SOURCE[0] is the component script path; repo root is two dirs up
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)" \
    || repo_root="$(cd "$(dirname "$0")/.." && pwd)"
  ucc_run cp "$repo_root/stack/docker-compose.yml" "$COMPOSE_FILE"
}

ucc_target_nonruntime --name "ai-stack-compose-file" \
  --observe _observe_compose_file \
  --evidence _evidence_compose_file \
  --install _write_compose_file --update _write_compose_file

# ============================================================
# Stack running
# ============================================================
_observe_stack() {
  [[ -f "$COMPOSE_FILE" ]] || {
    ucc_asm_state \
      --installation Absent \
      --runtime Stopped \
      --health Unavailable \
      --admin Enabled \
      --dependencies DepsFailed
    return
  }
  # Check each service by name via docker inspect — avoids fragile wc -l
  # and does not depend on --status flag availability across compose versions
  local svc state
  for svc in "${AI_SERVICES[@]}"; do
    state=$(docker inspect --format '{{.State.Status}}' "$svc" 2>/dev/null) || {
      ucc_asm_state \
        --installation Configured \
        --runtime Stopped \
        --health Unavailable \
        --admin Enabled \
        --dependencies DepsFailed
      return
    }
    [[ "$state" == "running" ]] || {
      ucc_asm_state \
        --installation Configured \
        --runtime Stopped \
        --health Degraded \
        --admin Enabled \
        --dependencies DepsDegraded
      return
    }
  done
  ucc_asm_state \
    --installation Configured \
    --runtime Running \
    --health Healthy \
    --admin Enabled \
    --dependencies DepsReady
}
_evidence_stack() {
  local running=0 svc state
  for svc in "${AI_SERVICES[@]}"; do
    state=$(docker inspect --format '{{.State.Status}}' "$svc" 2>/dev/null || true)
    [[ "$state" == "running" ]] && running=$((running + 1))
  done
  printf 'running=%s/%s compose=%s' "$running" "$STACK_SERVICES" "$COMPOSE_FILE"
}

# Remove any legacy bare containers that would conflict with compose
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
  --desired "$(ucc_asm_state --installation Configured --runtime Running --health Healthy --admin Enabled --dependencies DepsReady)" \
  --install _start_stack --update _update_stack

ucc_summary "07-ai-apps"
