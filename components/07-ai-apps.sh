#!/usr/bin/env bash
# Component: AI Applications via Docker Compose
# UCC + Basic — bash 3.2 compatible (no declare -A)

docker info &>/dev/null || log_error "Docker must be running first (run 03-docker.sh)"

COMPOSE_DIR="$HOME/.ai-stack"
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
  local running
  running=$(docker compose -f "$COMPOSE_FILE" ps --status running --quiet 2>/dev/null | wc -l | tr -d ' ')
  [[ "$running" -ge "$STACK_SERVICES" ]] && echo "running" || echo "stopped"
}

_start_stack() {
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
log_info ""
log_info "Manage: docker compose -f $COMPOSE_FILE <up|down|ps|logs>"

ucc_summary "07-ai-apps"
