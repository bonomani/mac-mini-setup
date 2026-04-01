#!/usr/bin/env bash
# lib/docker.sh — Docker Desktop install + daemon startup
# Sourced by components/docker.sh

# Usage: run_docker_from_yaml <cfg_dir> <yaml_path>
run_docker_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  ucc_yaml_simple_target  "$cfg_dir" "$yaml" "docker-desktop"
  ucc_yaml_runtime_target "$cfg_dir" "$yaml" "docker-daemon"
}

_docker_settings_store_patch() {
  local store="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
  if [[ -f "$store" ]]; then
    local tmp; tmp="$(mktemp)"
    jq '. + {"OpenUIOnStartupDisabled": true, "DisplayedOnboarding": true, "ShowInstallScreen": false}' \
      "$store" > "$tmp" && mv "$tmp" "$store" || rm -f "$tmp"
  else
    mkdir -p "$(dirname "$store")"
    printf '{"OpenUIOnStartupDisabled":true,"DisplayedOnboarding":true,"ShowInstallScreen":false}\n' > "$store"
  fi
}

_docker_desktop_install() {
  local cask_id="$1" app_path="$2" greedy="$3"
  local policy="${UIC_PREF_PREFERRED_DRIVER_POLICY:-warn}"
  local install_source; install_source="$(desktop_app_install_source "$cask_id" "$app_path")"

  if [[ "$install_source" == "app-bundle" ]]; then
    case "$policy" in
      ignore)
        log_info "Docker Desktop installed outside brew-cask; ignoring (policy=ignore)."
        return 0
        ;;
      warn)
        log_warn "Docker Desktop installed outside brew-cask; set preferred-driver-policy=migrate to adopt it."
        return 124
        ;;
      migrate)
        sudo -n true >/dev/null 2>&1 || { log_warn "Migrating Docker Desktop requires admin; run: sudo -v"; return 125; }
        brew_cask_migrate_install "$cask_id" || return 1
        ;;
      *)
        log_warn "Unknown preferred-driver-policy '$policy'; treating as warn."
        return 124
        ;;
    esac
  fi

  local observed; observed="$(brew_cask_observe "$cask_id" "$greedy")"
  [[ "$observed" == "absent" && -d "$app_path" ]] && observed="installed"
  if [[ "$observed" == "absent" ]]; then
    brew_cask_install "$cask_id" || return 1
  elif [[ "$observed" == "outdated" ]]; then
    brew_cask_upgrade "$cask_id" "$greedy" || return 1
  fi

  _docker_settings_store_patch
}

_docker_daemon_start() {
  _docker_settings_store_patch
  pkill -f com.docker 2>/dev/null || true
  sleep 2
  log_info "Starting Docker Desktop..."
  env -i HOME="$HOME" PATH="$PATH" USER="$USER" TERM="${TERM:-}" \
    script -q /dev/null docker desktop start
}

# Usage: run_docker_config_from_yaml <cfg_dir> <yaml_path>
run_docker_config_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  local settings_relpath="Library/Group Containers/group.com.docker/settings.json"
  local memory_gb="48" cpu_count="10" swap_mib="4096" disk_mib="204800"
  while IFS=$'\t' read -r -d '' key value; do
    [[ -n "$value" ]] || continue
    case "$key" in
      settings_relpath) settings_relpath="$value" ;;
      memory_gb)        memory_gb="$value" ;;
      cpu_count)        cpu_count="$value" ;;
      swap_mib)         swap_mib="$value" ;;
      disk_mib)         disk_mib="$value" ;;
    esac
  done < <(yaml_get_many "$cfg_dir" "$yaml" settings_relpath memory_gb cpu_count swap_mib disk_mib)
  export DOCKER_SETTINGS_PATH="$HOME/${settings_relpath}"

  if [[ "${UIC_GATE_FAILED_DOCKER_SETTINGS_FILE:-0}" == "1" ]]; then
    ucc_skip_target "docker-resources" "gate=docker-settings-file:warn (launch Docker Desktop first)"
    return 0
  fi

  export DOCKER_MEM_GB="${UIC_PREF_DOCKER_MEMORY_GB:-$memory_gb}"
  export DOCKER_MEM_MIB=$(( DOCKER_MEM_GB * 1024 ))
  export DOCKER_CPU_COUNT="${UIC_PREF_DOCKER_CPU_COUNT:-$cpu_count}"
  export DOCKER_SWAP_MIB="${UIC_PREF_DOCKER_SWAP_MIB:-$swap_mib}"
  export DOCKER_DISK_MIB="${UIC_PREF_DOCKER_DISK_MIB:-$disk_mib}"

  ucc_yaml_parametric_target "$cfg_dir" "$yaml" "docker-resources"
}
