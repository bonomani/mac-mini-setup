#!/usr/bin/env bash
# lib/docker.sh — Docker Desktop runtime + resource settings targets
# Sourced by components/docker.sh

# Usage: run_docker_from_yaml <cfg_dir> <yaml_path>
run_docker_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "docker-desktop"
  _run_docker_daemon "$cfg_dir" "$yaml"
}

_run_docker_daemon() {
  local cfg_dir="$1" yaml="$2"
  local socket wait_attempts wait_interval settings_store
  socket=$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" docker_socket 2>/dev/null)
  socket="${socket/\$HOME/$HOME}"
  wait_attempts=$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" docker_runtime_wait_attempts 2>/dev/null)
  wait_interval=$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" docker_runtime_wait_interval 2>/dev/null)
  settings_store=$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" docker_settings_store 2>/dev/null)
  settings_store="${settings_store/\$HOME/$HOME}"

  # Check if already running
  if [[ -S "$socket" ]] && docker info >/dev/null 2>&1; then
    local pid; pid=$(pgrep -f "com.docker.backend" 2>/dev/null | head -1)
    printf '      [%-8s] %-30s %s\n' "ok" "Docker Daemon" "socket=$socket  pid=${pid:-?}"
    return 0
  fi

  # Patch settings-store to suppress onboarding UI
  if [[ -f "$settings_store" ]]; then
    local _tmp; _tmp="$(mktemp)"
    jq '. + {"OpenUIOnStartupDisabled": true, "DisplayedOnboarding": true, "ShowInstallScreen": false}' \
      "$settings_store" > "$_tmp" && mv "$_tmp" "$settings_store" || rm -f "$_tmp"
  else
    mkdir -p "$(dirname "$settings_store")"
    printf '{"OpenUIOnStartupDisabled":true,"DisplayedOnboarding":true,"ShowInstallScreen":false}\n' > "$settings_store"
  fi

  # Start daemon
  if ! pgrep -f "com.docker.backend" >/dev/null 2>&1; then
    log_info "Starting Docker Desktop..."
    (docker desktop start >/dev/null 2>&1 &)
  fi

  # Wait for socket
  log_info "Waiting for Docker daemon (${wait_attempts}x${wait_interval}s)..."
  log_info "Probing: socket=$socket"
  local i
  for ((i=1; i<=wait_attempts; i++)); do
    log_info "  attempt $i — socket: $(ls "$socket" 2>/dev/null && echo present || echo absent) | docker info: $(docker info >/dev/null 2>&1 && echo ok || echo fail)"
    if [[ -S "$socket" ]] && docker info >/dev/null 2>&1; then
      local pid; pid=$(pgrep -f "com.docker.backend" 2>/dev/null | head -1)
      printf '      [%-8s] %-30s %s\n' "ok" "Docker Daemon" "socket=$socket  pid=${pid:-?}"
      return 0
    fi
    sleep "$wait_interval"
  done

  log_warn "Docker daemon not ready yet — re-run once Docker Desktop has finished starting."
  printf '      [%-8s] %-30s %s\n' "warn" "Docker Daemon" "socket not ready"
  return 0
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
      memory_gb) memory_gb="$value" ;;
      cpu_count) cpu_count="$value" ;;
      swap_mib) swap_mib="$value" ;;
      disk_mib) disk_mib="$value" ;;
    esac
  done < <(yaml_get_many "$cfg_dir" "$yaml" settings_relpath memory_gb cpu_count swap_mib disk_mib)
  export DOCKER_SETTINGS_PATH="$HOME/${settings_relpath}"

  if [[ "${UIC_GATE_FAILED_DOCKER_SETTINGS_FILE:-0}" == "1" ]]; then
    ucc_skip_target "docker-resources" "gate=docker-settings-file:warn (launch Docker Desktop first)"
    return 0
  fi

  # Resource settings — UIC preferences take precedence; YAML provides defaults
  export DOCKER_MEM_GB="${UIC_PREF_DOCKER_MEMORY_GB:-$memory_gb}"
  export DOCKER_MEM_MIB=$(( DOCKER_MEM_GB * 1024 ))
  export DOCKER_CPU_COUNT="${UIC_PREF_DOCKER_CPU_COUNT:-$cpu_count}"
  export DOCKER_SWAP_MIB="${UIC_PREF_DOCKER_SWAP_MIB:-$swap_mib}"
  export DOCKER_DISK_MIB="${UIC_PREF_DOCKER_DISK_MIB:-$disk_mib}"

  ucc_yaml_parametric_target "$cfg_dir" "$yaml" "docker-resources"
}
