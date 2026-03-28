#!/usr/bin/env bash
# lib/docker.sh — Docker Desktop runtime + resource settings targets
# Sourced by components/docker.sh

# Usage: run_docker_from_yaml <cfg_dir> <yaml_path>
run_docker_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  ucc_yaml_runtime_target "$cfg_dir" "$yaml" "docker-desktop"
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
