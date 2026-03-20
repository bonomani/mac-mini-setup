#!/usr/bin/env bash
# Component: AI Applications via Docker
# UCC + Basic — bash 3.2 compatible (no declare -A)

docker info &>/dev/null || log_error "Docker must be running first (run 03-docker.sh)"

# Stop and remove any container currently occupying a host port
_free_host_port() {
  local port="$1"
  local cid
  cid=$(docker ps --format '{{.ID}} {{.Ports}}' 2>/dev/null \
    | awk -v p=":${port}->" '$0 ~ p {print $1}')
  if [[ -n "$cid" ]]; then
    log_info "Freeing host port ${port} (container ${cid})..."
    docker stop "$cid" 2>/dev/null || true
    docker rm   "$cid" 2>/dev/null || true
  fi
}

# ============================================================
# open-webui — chat UI for Ollama (port 3000)
# ============================================================
_observe_open_webui() {
  if docker_is_running 'open-webui'; then
    local img; img=$(docker inspect --format '{{.Config.Image}}' open-webui 2>/dev/null)
    [[ "$img" == "ghcr.io/open-webui/open-webui:main" ]] && echo 'running' || echo 'absent'
  elif docker_exists 'open-webui'; then echo 'stopped'
  else echo 'absent'
  fi
}
_install_open_webui() {
  _free_host_port 3000
  docker stop 'open-webui' 2>/dev/null || true
  docker_exists 'open-webui' && docker rm 'open-webui' 2>/dev/null || true
  ucc_run docker run -d \
    --name open-webui --restart always \
    -p 3000:8080 \
    -v open-webui:/app/backend/data \
    -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
    ghcr.io/open-webui/open-webui:main
}
_update_open_webui() {
  ucc_run docker pull ghcr.io/open-webui/open-webui:main
  docker stop open-webui 2>/dev/null || true
  docker rm   open-webui 2>/dev/null || true
  _install_open_webui
}
ucc_target --name "docker-open-webui" \
  --observe _observe_open_webui --desired "running" \
  --install _install_open_webui --update _update_open_webui

# ============================================================
# n8n — workflow automation (port 5678)
# ============================================================
_observe_n8n() {
  if docker_is_running 'n8n'; then
    local img; img=$(docker inspect --format '{{.Config.Image}}' n8n 2>/dev/null)
    [[ "$img" == "docker.n8n.io/n8nio/n8n" ]] && echo 'running' || echo 'absent'
  elif docker_exists 'n8n'; then echo 'stopped'
  else echo 'absent'
  fi
}
_install_n8n() {
  _free_host_port 5678
  docker stop 'n8n' 2>/dev/null || true
  docker_exists 'n8n' && docker rm 'n8n' 2>/dev/null || true
  ucc_run docker run -d \
    --name n8n --restart always \
    -p 5678:5678 \
    -v n8n_data:/home/node/.n8n \
    docker.n8n.io/n8nio/n8n
}
_update_n8n() {
  ucc_run docker pull docker.n8n.io/n8nio/n8n
  docker stop n8n 2>/dev/null || true
  docker rm   n8n 2>/dev/null || true
  _install_n8n
}
ucc_target --name "docker-n8n" \
  --observe _observe_n8n --desired "running" \
  --install _install_n8n --update _update_n8n

# ============================================================
# qdrant — vector database (port 6333)
# ============================================================
_observe_qdrant() {
  if docker_is_running 'qdrant'; then
    local img; img=$(docker inspect --format '{{.Config.Image}}' qdrant 2>/dev/null)
    [[ "$img" == "qdrant/qdrant" ]] && echo 'running' || echo 'absent'
  elif docker_exists 'qdrant'; then echo 'stopped'
  else echo 'absent'
  fi
}
_install_qdrant() {
  _free_host_port 6333
  docker stop 'qdrant' 2>/dev/null || true
  docker_exists 'qdrant' && docker rm 'qdrant' 2>/dev/null || true
  ucc_run docker run -d \
    --name qdrant --restart always \
    -p 6333:6333 \
    -v qdrant_storage:/qdrant/storage \
    qdrant/qdrant
}
_update_qdrant() {
  ucc_run docker pull qdrant/qdrant
  docker stop qdrant 2>/dev/null || true
  docker rm   qdrant 2>/dev/null || true
  _install_qdrant
}
ucc_target --name "docker-qdrant" \
  --observe _observe_qdrant --desired "running" \
  --install _install_qdrant --update _update_qdrant

# ============================================================
# flowise — LLM flow builder (port 3001)
# ============================================================
_observe_flowise() {
  if docker_is_running 'flowise'; then
    local img; img=$(docker inspect --format '{{.Config.Image}}' flowise 2>/dev/null)
    [[ "$img" == "flowiseai/flowise" ]] && echo 'running' || echo 'absent'
  elif docker_exists 'flowise'; then echo 'stopped'
  else echo 'absent'
  fi
}
_install_flowise() {
  _free_host_port 3001
  docker stop 'flowise' 2>/dev/null || true
  docker_exists 'flowise' && docker rm 'flowise' 2>/dev/null || true
  ucc_run docker run -d \
    --name flowise --restart always \
    -p 3001:3000 \
    -v flowise_data:/root/.flowise \
    flowiseai/flowise
}
_update_flowise() {
  ucc_run docker pull flowiseai/flowise
  docker stop flowise 2>/dev/null || true
  docker rm   flowise 2>/dev/null || true
  _install_flowise
}
ucc_target --name "docker-flowise" \
  --observe _observe_flowise --desired "running" \
  --install _install_flowise --update _update_flowise

echo ""
log_info "Open WebUI (Ollama chat) → http://localhost:3000"
log_info "Flowise (LLM flows)      → http://localhost:3001"
log_info "n8n (automation)         → http://localhost:5678"
log_info "Qdrant (vector DB)       → http://localhost:6333"

ucc_summary "07-ai-apps"
