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
  export DOCKER_SETTINGS_PATH="$HOME/$(yaml_get "$cfg_dir" "$yaml" settings_relpath "Library/Group Containers/group.com.docker/settings.json")"

  if [[ "${UIC_GATE_FAILED_DOCKER_SETTINGS_FILE:-0}" == "1" ]]; then
    ucc_skip_target "docker-resources" "gate=docker-settings-file:warn (launch Docker Desktop first)"
    return 0
  fi

  # Resource settings — UIC preferences take precedence; YAML provides defaults
  export DOCKER_MEM_GB="${UIC_PREF_DOCKER_MEMORY_GB:-$(yaml_get "$cfg_dir" "$yaml" memory_gb 48)}"
  export DOCKER_MEM_MIB=$(( DOCKER_MEM_GB * 1024 ))
  export DOCKER_CPU_COUNT="${UIC_PREF_DOCKER_CPU_COUNT:-$(yaml_get "$cfg_dir" "$yaml" cpu_count 10)}"
  export DOCKER_SWAP_MIB="${UIC_PREF_DOCKER_SWAP_MIB:-$(yaml_get "$cfg_dir" "$yaml" swap_mib 4096)}"
  export DOCKER_DISK_MIB="${UIC_PREF_DOCKER_DISK_MIB:-$(yaml_get "$cfg_dir" "$yaml" disk_mib 204800)}"

  ucc_yaml_parametric_target "$cfg_dir" "$yaml" "docker-resources"
}
