#!/usr/bin/env bash
# lib/docker.sh — Docker Desktop runtime + resource settings targets
# Sourced by components/docker.sh

# Usage: run_docker_from_yaml <cfg_dir> <yaml_path>
run_docker_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  local _DOCKER_CASK_ID _DOCKER_APP_NAME _DOCKER_APP_PATH
  _DOCKER_CASK_ID="$(yaml_get "$cfg_dir" "$yaml" docker_desktop_cask_id docker)"
  _DOCKER_APP_NAME="$(yaml_get "$cfg_dir" "$yaml" docker_desktop_app_name Docker)"
  _DOCKER_APP_PATH="$(yaml_get "$cfg_dir" "$yaml" docker_desktop_app_path /Applications/Docker.app)"

  _docker_desktop_version() {
    defaults read "${_DOCKER_APP_PATH}/Contents/Info" CFBundleShortVersionString 2>/dev/null \
      || docker --version 2>/dev/null | awk '{print $3}' | tr -d ','
  }
  _docker_desktop_pkg_state() {
    if [[ -d "$_DOCKER_APP_PATH" ]] && ! brew_cask_is_installed "$_DOCKER_CASK_ID"; then
      printf 'installed'
      return
    fi
    brew_cask_observe "$_DOCKER_CASK_ID"
  }
  _observe_docker_desktop() {
    local observed
    observed="$(_docker_desktop_pkg_state)"
    if [[ "$observed" == "absent" ]] && [[ ! -d "$_DOCKER_APP_PATH" ]] && ! command -v docker >/dev/null 2>&1; then
      ucc_asm_state --installation Absent --runtime NeverStarted \
        --health Unavailable --admin Enabled --dependencies DepsUnknown
      return
    fi

    if docker info &>/dev/null 2>&1; then
      if [[ "$observed" == "outdated" ]]; then
        ucc_asm_state --installation Installed --runtime Running \
          --health Degraded --admin Enabled --dependencies DepsDegraded
      else
        ucc_asm_runtime_desired
      fi
    else
      if [[ "$observed" == "outdated" ]]; then
        ucc_asm_state --installation Installed --runtime Stopped \
          --health Degraded --admin Enabled --dependencies DepsDegraded
      else
        ucc_asm_state --installation Configured --runtime Stopped \
          --health Unavailable --admin Enabled --dependencies DepsDegraded
      fi
    fi
  }
  _evidence_docker_desktop() {
    local pid ver
    pid="$(pgrep -f "$_DOCKER_APP_PATH" 2>/dev/null | head -1 || true)"
    ver="$(_docker_desktop_version)"
    [[ -n "$ver" ]] && printf 'version=%s' "$ver"
    [[ -n "$pid" ]] && printf '  pid=%s' "$pid"
  }
  _converge_docker_desktop() {
    local observed
    observed="$(_docker_desktop_pkg_state)"
    if [[ "$observed" == "absent" ]]; then
      brew_cask_install "$_DOCKER_CASK_ID" || return 1
    elif [[ "$observed" == "outdated" ]]; then
      brew_cask_upgrade "$_DOCKER_CASK_ID" || return 1
    fi
    open -a "$_DOCKER_APP_NAME"
    log_info "Waiting for Docker daemon..."
    for i in $(seq 1 24); do
      docker info &>/dev/null && return 0
      log_debug "Waiting for Docker ($i/24)..."
      sleep 5
    done
    return 1
  }

  ucc_target_service \
    --name    "docker-desktop" \
    --observe _observe_docker_desktop \
    --evidence _evidence_docker_desktop \
    --desired "$(ucc_asm_runtime_desired)" \
    --install _converge_docker_desktop \
    --update  _converge_docker_desktop
}

# Usage: run_docker_config_from_yaml <cfg_dir> <yaml_path>
run_docker_config_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  local _DOCKER_SETTINGS_PATH
  _DOCKER_SETTINGS_PATH="$HOME/$(yaml_get "$cfg_dir" "$yaml" settings_relpath "Library/Group Containers/group.com.docker/settings.json")"

  if [[ "${UIC_GATE_FAILED_DOCKER_SETTINGS_FILE:-0}" == "1" ]]; then
    ucc_skip_target "docker-resources" "gate=docker-settings-file:warn (launch Docker Desktop first)"
    return 0
  fi

  # Resource settings — UIC preferences take precedence; YAML provides defaults
  local _DOCKER_MEM_GB="${UIC_PREF_DOCKER_MEMORY_GB:-$(yaml_get "$cfg_dir" "$yaml" memory_gb 48)}"
  local _DOCKER_MEM_MIB=$(( _DOCKER_MEM_GB * 1024 ))
  local _DOCKER_CPUS="${UIC_PREF_DOCKER_CPU_COUNT:-$(yaml_get "$cfg_dir" "$yaml" cpu_count 10)}"
  local _DOCKER_SWAP_MIB="${UIC_PREF_DOCKER_SWAP_MIB:-$(yaml_get "$cfg_dir" "$yaml" swap_mib 4096)}"
  local _DOCKER_DISK_MIB="${UIC_PREF_DOCKER_DISK_MIB:-$(yaml_get "$cfg_dir" "$yaml" disk_mib 204800)}"

  _docker_settings_desired_state() {
    ucc_asm_state --installation Configured --runtime Stopped \
      --health Healthy --admin Enabled --dependencies DepsReady \
      --config-value "mem=${_DOCKER_MEM_GB}GB cpu=${_DOCKER_CPUS}"
  }
  _observe_docker_settings() {
    local f="$_DOCKER_SETTINGS_PATH"
    [[ -f "$f" ]] || {
      ucc_asm_state --installation Installed --runtime Stopped \
        --health Unavailable --admin Enabled --dependencies DepsFailed
      return
    }
    local mem cpus mem_gb
    mem=$(python3 -c "import json; d=json.load(open('$f')); print(d.get('memoryMiB',0))" 2>/dev/null)
    cpus=$(python3 -c "import json; d=json.load(open('$f')); print(d.get('cpus',0))" 2>/dev/null)
    [[ -z "$mem" ]] && return 0
    mem_gb=$(( mem / 1024 ))
    if [[ "$mem" -ge "$_DOCKER_MEM_MIB" ]]; then
      ucc_asm_state --installation Configured --runtime Stopped \
        --health Healthy --admin Enabled --dependencies DepsReady \
        --config-value "mem=${mem_gb}GB cpu=${cpus}"
    else
      ucc_asm_state --installation Installed --runtime Stopped \
        --health Degraded --admin Enabled --dependencies DepsDegraded \
        --config-value "mem=${mem_gb}GB cpu=${cpus}"
    fi
  }
  _evidence_docker_settings() {
    local f="$_DOCKER_SETTINGS_PATH" mem cpus
    [[ -f "$f" ]] || { printf 'gate=docker-settings-file:warn (launch Docker to create settings file)'; return; }
    mem=$(python3  -c "import json; d=json.load(open('$f')); print(d.get('memoryMiB',0)//1024)" 2>/dev/null)
    cpus=$(python3 -c "import json; d=json.load(open('$f')); print(d.get('cpus',0))" 2>/dev/null)
    printf 'memory=%sGB  cpus=%s' "${mem:-0}" "${cpus:-0}"
  }
  _configure_docker_settings() {
    local f="$_DOCKER_SETTINGS_PATH"
    [[ -f "$f" ]] || { log_warn "Docker settings file not found yet — launch Docker first"; return 1; }
    DOCKER_SETTINGS_PATH="$f" MEM_MIB="$_DOCKER_MEM_MIB" CPU_COUNT="$_DOCKER_CPUS" \
    SWAP_MIB="$_DOCKER_SWAP_MIB" DISK_MIB="$_DOCKER_DISK_MIB" python3 - <<'EOF'
import json, os
path = os.environ["DOCKER_SETTINGS_PATH"]
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
    --profile parametric \
    --desired "$(_docker_settings_desired_state)" \
    --install _configure_docker_settings \
    --update  _configure_docker_settings
}
