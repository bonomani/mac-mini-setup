#!/usr/bin/env bash
# lib/docker.sh — Docker Desktop install + daemon startup
# Sourced by components/docker.sh

# Usage: run_docker_from_yaml <cfg_dir> <yaml_path>
run_docker_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  ucc_yaml_simple_target  "$cfg_dir" "$yaml" "docker-desktop"
  ucc_yaml_runtime_target "$cfg_dir" "$yaml" "docker-daemon"
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
