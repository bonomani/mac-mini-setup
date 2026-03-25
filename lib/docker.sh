#!/usr/bin/env bash
# lib/docker.sh — Docker Desktop + resource settings targets
# Sourced by components/docker.sh

# Usage: run_docker_from_yaml <cfg_dir> <yaml_path>
run_docker_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  _observe_docker_app() {
    if [[ -d "/Applications/Docker.app" ]] && ! brew_cask_is_installed docker; then
      ucc_asm_state \
        --installation Installed --runtime NeverStarted \
        --health Unknown --admin Enabled --dependencies DepsUnknown
      return
    fi
    local observed; observed=$(brew_cask_observe docker)
    case "$observed" in
      absent)
        ucc_asm_state --installation Absent --runtime NeverStarted \
          --health Unavailable --admin Enabled --dependencies DepsUnknown ;;
      outdated)
        ucc_asm_state --installation Upgrading --runtime Stopped \
          --health Degraded --admin Enabled --dependencies DepsDegraded ;;
      *)
        ucc_asm_state --installation Installed --runtime NeverStarted \
          --health Unknown --admin Enabled --dependencies DepsUnknown ;;
    esac
  }
  _evidence_docker_app() {
    local ver
    ver=$(defaults read "/Applications/Docker.app/Contents/Info" CFBundleShortVersionString 2>/dev/null \
      || docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
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
    --desired "$(ucc_asm_state --installation Installed --runtime NeverStarted \
                               --health Unknown --admin Enabled --dependencies DepsUnknown)" \
    --install _install_docker \
    --update  _upgrade_docker
}

# Usage: run_docker_config_from_yaml <cfg_dir> <yaml_path>
run_docker_config_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  # Resource settings — UIC preferences take precedence; YAML provides defaults
  local _DOCKER_MEM_GB="${UIC_PREF_DOCKER_MEMORY_GB:-$(yaml_get "$cfg_dir" "$yaml" memory_gb 48)}"
  local _DOCKER_MEM_MIB=$(( _DOCKER_MEM_GB * 1024 ))
  local _DOCKER_CPUS="${UIC_PREF_DOCKER_CPU_COUNT:-$(yaml_get "$cfg_dir" "$yaml" cpu_count 10)}"
  local _DOCKER_SWAP_MIB="${UIC_PREF_DOCKER_SWAP_MIB:-$(yaml_get "$cfg_dir" "$yaml" swap_mib 4096)}"
  local _DOCKER_DISK_MIB="${UIC_PREF_DOCKER_DISK_MIB:-$(yaml_get "$cfg_dir" "$yaml" disk_mib 204800)}"

  _docker_settings_desired_state() {
    if [[ "${UIC_GATE_FAILED_DOCKER_SETTINGS_FILE:-0}" == "1" ]]; then
      ucc_asm_state --installation Installed --runtime Stopped \
        --health Unavailable --admin Enabled --dependencies DepsFailed
    else
      ucc_asm_state --installation Configured --runtime Stopped \
        --health Healthy --admin Enabled --dependencies DepsReady
    fi
  }
  _observe_docker_settings() {
    local f="$HOME/Library/Group Containers/group.com.docker/settings.json"
    [[ -f "$f" ]] || {
      ucc_asm_state --installation Installed --runtime Stopped \
        --health Unavailable --admin Enabled --dependencies DepsFailed
      return
    }
    local mem
    mem=$(python3 -c "import json; d=json.load(open('$f')); print(d.get('memoryMiB',0))" 2>/dev/null)
    [[ -z "$mem" ]] && return 0
    if [[ "$mem" -ge "$_DOCKER_MEM_MIB" ]]; then
      ucc_asm_state --installation Configured --runtime Stopped \
        --health Healthy --admin Enabled --dependencies DepsReady
    else
      ucc_asm_state --installation Installed --runtime Stopped \
        --health Degraded --admin Enabled --dependencies DepsDegraded
    fi
  }
  _evidence_docker_settings() {
    local f="$HOME/Library/Group Containers/group.com.docker/settings.json" mem cpus
    [[ -f "$f" ]] || { printf 'settings=missing path=%s' "$f"; return; }
    mem=$(python3  -c "import json; d=json.load(open('$f')); print(d.get('memoryMiB',0)//1024)" 2>/dev/null)
    cpus=$(python3 -c "import json; d=json.load(open('$f')); print(d.get('cpus',0))" 2>/dev/null)
    printf 'memory=%sGB cpus=%s' "${mem:-0}" "${cpus:-0}"
  }
  _configure_docker_settings() {
    local f="$HOME/Library/Group Containers/group.com.docker/settings.json"
    [[ -f "$f" ]] || { log_warn "Docker settings file not found yet — launch Docker first"; return 1; }
    MEM_MIB="$_DOCKER_MEM_MIB" CPU_COUNT="$_DOCKER_CPUS" \
    SWAP_MIB="$_DOCKER_SWAP_MIB" DISK_MIB="$_DOCKER_DISK_MIB" python3 - <<'EOF'
import json, os
path = os.path.expanduser("~/Library/Group Containers/group.com.docker/settings.json")
with open(path) as f:
    s = json.load(f)
s["memoryMiB"]   = int(os.environ["MEM_MIB"])
s["cpus"]        = int(os.environ["CPU_COUNT"])
s["swapMiB"]     = int(os.environ["SWAP_MIB"])
s["diskSizeMiB"] = int(os.environ["DISK_MIB"])
with open(path, "w") as f:
    json.dump(s, f, indent=2)
EOF
    log_warn "Restart Docker Desktop to apply new resource settings"
    log_info "Docker resources set: memory=${_DOCKER_MEM_GB}GB cpus=${_DOCKER_CPUS} swap=${_DOCKER_SWAP_MIB}MiB disk=${_DOCKER_DISK_MIB}MiB"
  }

  ucc_target \
    --name    "docker-resources" \
    --observe _observe_docker_settings \
    --evidence _evidence_docker_settings \
    --axes    "$UCC_ASM_CONFIGURED_AXES" \
    --desired "$(_docker_settings_desired_state)" \
    --install _configure_docker_settings \
    --update  _configure_docker_settings
}
