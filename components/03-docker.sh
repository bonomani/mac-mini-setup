#!/usr/bin/env bash
# Component: Docker Desktop
# UCC + Basic

_observe_docker_app() {
  brew_cask_is_installed docker && echo "installed" || echo "absent"
}

_install_docker() {
  brew install --cask docker
  open -a Docker
  log_info "Waiting for Docker daemon..."
  for i in $(seq 1 12); do
    docker info &>/dev/null && return 0
    log_debug "Waiting for Docker ($i/12)..."
    sleep 5
  done
  return 1
}

_update_docker() {
  brew upgrade --cask docker 2>/dev/null || true
}

ucc_target \
  --name    "docker-desktop" \
  --observe _observe_docker_app \
  --desired "installed" \
  --install _install_docker \
  --update  _update_docker

# --- Docker resource settings (48 GB RAM for AI workloads) --
_observe_docker_settings() {
  local f="$HOME/Library/Group Containers/group.com.docker/settings.json"
  [[ -f "$f" ]] || { echo "absent"; return 0; }
  local mem
  mem=$(python3 -c "import json; d=json.load(open('$f')); print(d.get('memoryMiB',0))" 2>/dev/null)
  # Return non-zero (indeterminate) if python3 failed or output is empty
  [[ -z "$mem" ]] && return 1
  [[ "$mem" -ge 49152 ]] && echo "configured" || echo "needs-update"
}

_configure_docker_settings() {
  local f="$HOME/Library/Group Containers/group.com.docker/settings.json"
  [[ -f "$f" ]] || { log_warn "Docker settings file not found yet — launch Docker first"; return 1; }
  python3 - <<'EOF'
import json, os
path = os.path.expanduser("~/Library/Group Containers/group.com.docker/settings.json")
with open(path) as f:
    s = json.load(f)
s["memoryMiB"]   = 49152   # 48 GB
s["cpus"]        = 12
s["swapMiB"]     = 4096
s["diskSizeMiB"] = 204800  # 200 GB
with open(path, "w") as f:
    json.dump(s, f, indent=2)
EOF
  log_warn "Restart Docker Desktop to apply new resource settings"
}

ucc_target \
  --name    "docker-resources-48gb" \
  --observe _observe_docker_settings \
  --desired "configured" \
  --install _configure_docker_settings \
  --update  _configure_docker_settings

ucc_summary "03-docker"
