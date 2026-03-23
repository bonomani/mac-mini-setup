#!/usr/bin/env bash
# Component: Docker Desktop
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — app installed/absent + resources configured)
#       Axis B = Basic
# Boundary: local filesystem · brew cask · Docker daemon API · macOS launchd

_observe_docker_app() {
  # Manual install counts as current — brew cask tracks upgrades for brew-installed only
  if [[ -d "/Applications/Docker.app" ]] && ! brew_cask_is_installed docker; then
    ucc_asm_state \
      --installation Installed \
      --runtime NeverStarted \
      --health Unknown \
      --admin Enabled \
      --dependencies DepsUnknown
    return
  fi
  local observed
  observed=$(brew_cask_observe docker)
  case "$observed" in
    absent)
      ucc_asm_state \
        --installation Absent \
        --runtime NeverStarted \
        --health Unavailable \
        --admin Enabled \
        --dependencies DepsUnknown
      ;;
    outdated)
      ucc_asm_state \
        --installation Upgrading \
        --runtime Stopped \
        --health Degraded \
        --admin Enabled \
        --dependencies DepsDegraded
      ;;
    *)
      ucc_asm_state \
        --installation Installed \
        --runtime NeverStarted \
        --health Unknown \
        --admin Enabled \
        --dependencies DepsUnknown
      ;;
  esac
}
_evidence_docker_app() {
  local ver
  ver=$(defaults read "/Applications/Docker.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
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
  --evidence _evidence_docker_app \
  --axes    "$UCC_ASM_CONFIGURED_AXES" \
  --desired "$(ucc_asm_state --installation Installed --runtime NeverStarted --health Unknown --admin Enabled --dependencies DepsUnknown)" \
  --install _install_docker \
  --update  _upgrade_docker

# --- Docker resource settings (48 GB RAM for AI workloads) --
# UIC preferences: docker-memory-gb (safe default=48) and docker-cpu-count (safe default=10)
_DOCKER_MEM_GB="${UIC_PREF_DOCKER_MEMORY_GB:-48}"
_DOCKER_MEM_MIB=$(( _DOCKER_MEM_GB * 1024 ))
_DOCKER_CPUS="${UIC_PREF_DOCKER_CPU_COUNT:-10}"

_docker_settings_desired_state() {
  if [[ "${UIC_GATE_FAILED_DOCKER_SETTINGS_FILE:-0}" == "1" ]]; then
    ucc_asm_state \
      --installation Installed \
      --runtime Stopped \
      --health Unavailable \
      --admin Enabled \
      --dependencies DepsFailed
  else
    ucc_asm_state \
      --installation Configured \
      --runtime Stopped \
      --health Healthy \
      --admin Enabled \
      --dependencies DepsReady
  fi
}

_observe_docker_settings() {
  local f="$HOME/Library/Group Containers/group.com.docker/settings.json"
  # File only exists after Docker Desktop is opened at least once.
  [[ -f "$f" ]] || {
    ucc_asm_state \
      --installation Installed \
      --runtime Stopped \
      --health Unavailable \
      --admin Enabled \
      --dependencies DepsFailed
    return
  }
  local mem
  mem=$(python3 -c "import json; d=json.load(open('$f')); print(d.get('memoryMiB',0))" 2>/dev/null)
  [[ -z "$mem" ]] && return 0   # python3 failed → indeterminate
  if [[ "$mem" -ge "$_DOCKER_MEM_MIB" ]]; then
    ucc_asm_state \
      --installation Configured \
      --runtime Stopped \
      --health Healthy \
      --admin Enabled \
      --dependencies DepsReady
  else
    ucc_asm_state \
      --installation Installed \
      --runtime Stopped \
      --health Degraded \
      --admin Enabled \
      --dependencies DepsDegraded
  fi
}
_evidence_docker_settings() {
  local f="$HOME/Library/Group Containers/group.com.docker/settings.json" mem cpus
  [[ -f "$f" ]] || { printf 'settings=%s' "$f"; return; }
  mem=$(python3 -c "import json; d=json.load(open('$f')); print(d.get('memoryMiB',0)//1024)" 2>/dev/null)
  cpus=$(python3 -c "import json; d=json.load(open('$f')); print(d.get('cpus',0))" 2>/dev/null)
  printf 'memory=%sGB cpus=%s settings=%s' "${mem:-0}" "${cpus:-0}" "$f"
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
  --evidence _evidence_docker_settings \
  --axes    "$UCC_ASM_CONFIGURED_AXES" \
  --desired "$(_docker_settings_desired_state)" \
  --install _configure_docker_settings \
  --update  _configure_docker_settings

ucc_summary "03-docker"
