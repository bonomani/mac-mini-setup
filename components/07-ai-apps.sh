#!/usr/bin/env bash
# Component: AI Applications via Docker
# UCC + Basic

docker info &>/dev/null || log_error "Docker must be running first (run 03-docker.sh)"

# Each app: name, image, port mapping, volumes, env
declare -A APP_IMAGE=(
  ["open-webui"]="ghcr.io/open-webui/open-webui:main"
  ["n8n"]="docker.n8n.io/n8nio/n8n"
  ["qdrant"]="qdrant/qdrant"
  ["flowise"]="flowiseai/flowise"
)

declare -A APP_PORTS=(
  ["open-webui"]="3000:8080"
  ["n8n"]="5678:5678"
  ["qdrant"]="6333:6333"
  ["flowise"]="3001:3000"
)

declare -A APP_VOLUMES=(
  ["open-webui"]="open-webui:/app/backend/data"
  ["n8n"]="n8n_data:/home/node/.n8n"
  ["qdrant"]="qdrant_storage:/qdrant/storage"
  ["flowise"]="flowise_data:/root/.flowise"
)

declare -A APP_ENV=(
  ["open-webui"]="-e OLLAMA_BASE_URL=http://host.docker.internal:11434"
  ["n8n"]=""
  ["qdrant"]=""
  ["flowise"]=""
)

for app in open-webui n8n qdrant flowise; do
  _app="$app"  # capture for closure

  eval "_observe_${app//-/_}() {
    docker_is_running '$_app' && echo 'running' \
    || (docker_exists '$_app' && echo 'stopped' || echo 'absent')
  }"

  eval "_install_${app//-/_}() {
    local img='${APP_IMAGE[$_app]}'
    local port='${APP_PORTS[$_app]}'
    local vol='${APP_VOLUMES[$_app]}'
    local env='${APP_ENV[$_app]}'
    # Remove stopped container if it exists
    docker_exists '$_app' && docker rm '$_app' 2>/dev/null || true
    ucc_run docker run -d \
      --name '$_app' \
      --restart always \
      -p \"\$port\" \
      -v \"\$vol\" \
      \$env \
      \"\$img\"
  }"

  eval "_update_${app//-/_}() {
    local img='${APP_IMAGE[$_app]}'
    ucc_run docker pull \"\$img\"
    ucc_run docker stop '$_app' 2>/dev/null || true
    ucc_run docker rm   '$_app' 2>/dev/null || true
    _install_${app//-/_}
  }"

  ucc_target \
    --name    "docker-$app" \
    --observe "_observe_${app//-/_}" \
    --desired "running" \
    --install "_install_${app//-/_}" \
    --update  "_update_${app//-/_}"
done

echo ""
log_info "Open WebUI (Ollama chat) → http://localhost:3000"
log_info "Flowise (LLM flows)      → http://localhost:3001"
log_info "n8n (automation)         → http://localhost:5678"
log_info "Qdrant (vector DB)       → http://localhost:6333"

ucc_summary "07-ai-apps"
