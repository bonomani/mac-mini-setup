#!/usr/bin/env bash
# Component: AI Applications via Docker Compose
# BGS: UCC + Basic  (bgs/SUITE.md §4.5 + §4.3) — bash 3.2 compatible (no declare -A)
#
# BISS: Axis A = UCC (state convergence — compose file present + containers running)
#       Axis B = Basic
# Boundary: local filesystem · Docker daemon API · network (image pulls)

COMPOSE_DIR="$HOME/.ai-stack"

# --- Docker running -----------------------------------------
_observe_docker_running() {
  docker info &>/dev/null 2>&1 && echo "running" || echo "stopped"
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

ucc_target \
  --name    "docker-running" \
  --observe _observe_docker_running \
  --desired "running" \
  --install _start_docker

# Abort component if Docker still not running after attempting to start
docker info &>/dev/null 2>&1 || { log_warn "Docker not running — skipping AI stack"; ucc_summary "07-ai-apps"; exit 0; }

COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
COMPOSE_MARKER="# ai-stack v2"   # bump to force re-deploy
STACK_SERVICES=5                 # open-webui, flowise, openhands, n8n, qdrant

# ============================================================
# Compose file — deploy from repo into ~/.ai-stack/
# ============================================================
_observe_compose_file() {
  [[ -f "$COMPOSE_FILE" ]] && grep -q "$COMPOSE_MARKER" "$COMPOSE_FILE" \
    && echo "present" || echo "absent"
}

_write_compose_file() {
  ucc_run mkdir -p "$COMPOSE_DIR"
  # BASH_SOURCE[0] is the component script path; repo root is two dirs up
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)" \
    || repo_root="$(cd "$(dirname "$0")/.." && pwd)"
  ucc_run cp "$repo_root/stack/docker-compose.yml" "$COMPOSE_FILE"
}

ucc_target --name "ai-stack-compose-file" \
  --observe _observe_compose_file --desired "present" \
  --install _write_compose_file --update _write_compose_file

# ============================================================
# Stack running
# ============================================================
_observe_stack() {
  [[ -f "$COMPOSE_FILE" ]] || { echo "stopped"; return; }
  # Check each service by name via docker inspect — avoids fragile wc -l
  # and does not depend on --status flag availability across compose versions
  local svc state
  for svc in open-webui flowise openhands n8n qdrant; do
    state=$(docker inspect --format '{{.State.Status}}' "$svc" 2>/dev/null) || { echo "stopped"; return; }
    [[ "$state" == "running" ]] || { echo "stopped"; return; }
  done
  echo "running"
}

# Remove any legacy bare containers that would conflict with compose
_remove_legacy_containers() {
  local name
  for name in open-webui flowise openhands n8n qdrant; do
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

ucc_target --name "ai-stack-running" \
  --observe _observe_stack --desired "running" \
  --install _start_stack --update _update_stack

echo ""
log_info "Open WebUI (Ollama chat) → http://localhost:3000"
log_info "Flowise (LLM flows)      → http://localhost:3001"
log_info "OpenHands (agent)        → http://localhost:3002"
log_info "n8n (automation)         → http://localhost:5678"
log_info "Qdrant (vector DB)       → http://localhost:6333"
log_info "Manage: docker compose -f $COMPOSE_FILE <up|down|ps|logs>"

ucc_summary "07-ai-apps"
