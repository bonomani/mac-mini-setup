#!/usr/bin/env bash
# Component: Docker Desktop
# BGS: UCC + Basic  (bgs/SUITE.md §4.5 + §4.3)
#
# BISS: Axis A = UCC (state convergence — app installed/absent + resources configured)
#       Axis B = Basic
# Boundary: local filesystem · brew cask · Docker daemon API · macOS launchd

_observe_docker_app() {
  # Manual install counts as current — brew cask tracks upgrades for brew-installed only
  if [[ -d "/Applications/Docker.app" ]] && ! brew_cask_is_installed docker; then
    echo "current"; return
  fi
  brew_cask_observe docker
}

_install_docker() {
  brew_cask_install docker
  open -a Docker
  log_info "Waiting for Docker daemon..."
  for i in $(seq 1 12); do
    docker info &>/dev/null && return 0
    log_debug "Waiting for Docker ($i/12)..."
    sleep 5
  done
  return 1
}

_upgrade_docker() {
  brew_cask_upgrade docker 2>/dev/null || true
  log_warn "Restart Docker Desktop to apply the upgrade"
}

ucc_target \
  --name    "docker-desktop" \
  --observe _observe_docker_app \
  --desired "current" \
  --install _install_docker \
  --update  _upgrade_docker

# --- Docker resource settings (48 GB RAM for AI workloads) --
# UIC preferences: docker-memory-gb (safe default=48) and docker-cpu-count (safe default=10)
_DOCKER_MEM_GB="${UIC_PREF_DOCKER_MEMORY_GB:-48}"
_DOCKER_MEM_MIB=$(( _DOCKER_MEM_GB * 1024 ))
_DOCKER_CPUS="${UIC_PREF_DOCKER_CPU_COUNT:-10}"

_observe_docker_settings() {
  local f="$HOME/Library/Group Containers/group.com.docker/settings.json"
  # File only exists after Docker Desktop is opened at least once.
  # When absent: gate 'docker-settings-file' already warned the user — treat as converged (no-op).
  [[ -f "$f" ]] || { echo "configured"; return; }
  local mem
  mem=$(python3 -c "import json; d=json.load(open('$f')); print(d.get('memoryMiB',0))" 2>/dev/null)
  [[ -z "$mem" ]] && return 0   # python3 failed → indeterminate
  [[ "$mem" -ge "$_DOCKER_MEM_MIB" ]] && echo "configured" || echo "needs-update"
}

_configure_docker_settings() {
  local f="$HOME/Library/Group Containers/group.com.docker/settings.json"
  [[ -f "$f" ]] || { log_warn "Docker settings file not found yet — launch Docker first"; return 1; }
  MEM_MIB="$_DOCKER_MEM_MIB" CPU_COUNT="$_DOCKER_CPUS" python3 - <<'EOF'
import json, os
path = os.path.expanduser("~/Library/Group Containers/group.com.docker/settings.json")
with open(path) as f:
    s = json.load(f)
s["memoryMiB"]   = int(os.environ["MEM_MIB"])
s["cpus"]        = int(os.environ["CPU_COUNT"])
s["swapMiB"]     = 4096
s["diskSizeMiB"] = 204800  # 200 GB
with open(path, "w") as f:
    json.dump(s, f, indent=2)
EOF
  log_warn "Restart Docker Desktop to apply new resource settings"
  log_info "Docker resources set: memory=${_DOCKER_MEM_GB}GB cpus=${_DOCKER_CPUS}"
}

ucc_target \
  --name    "docker-resources-48gb" \
  --observe _observe_docker_settings \
  --desired "configured" \
  --install _configure_docker_settings \
  --update  _configure_docker_settings

ucc_summary "03-docker"
