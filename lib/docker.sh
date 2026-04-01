#!/usr/bin/env bash
# lib/docker.sh — Docker Desktop install + daemon startup
# Sourced by components/docker.sh

# Observe docker-desktop install state: installed | absent
docker_desktop_observe() {
  command -v docker >/dev/null 2>&1 && printf 'installed' || printf 'absent'
}

# Print Docker CLI version string (e.g. "27.3.1").
docker_version() {
  docker --version 2>/dev/null | awk '{print $3}' | tr -d ','
}

# Print a docker-settings desired-state string for memory and CPU.
# Usage: docker_desired_resources <mem_gb> <cpu_count>
docker_desired_resources() {
  printf 'mem=%sGB cpu=%s' "$1" "$2"
}

# Return 0 if the Docker daemon is reachable (docker info succeeds).
docker_daemon_is_running() {
  docker info >/dev/null 2>&1
}

# Print the install source of Docker Desktop if it is not absent/brew-cask.
# Uses implicit $CFG_DIR/$YAML_PATH context.
docker_install_source_observe() {
  local cask_id app_path
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      docker_desktop_cask_id) cask_id="$value" ;;
      docker_desktop_app_path) app_path="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" docker_desktop_cask_id docker_desktop_app_path)
  local src; src="$(desktop_app_install_source "$cask_id" "$app_path")"
  [[ "$src" != "absent" && "$src" != "brew-cask" ]] && printf '%s' "$src" || true
}

# Print the PID of the Docker backend process (empty if not running).
# Uses implicit $CFG_DIR/$YAML_PATH context.
docker_daemon_pid() {
  local pattern
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      docker_backend_process) pattern="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" docker_backend_process)
  pgrep -f "$pattern" 2>/dev/null | head -1
}

# Usage: run_docker_from_yaml <cfg_dir> <yaml_path>
run_docker_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  ucc_yaml_simple_target  "$cfg_dir" "$yaml" "docker-desktop"
  ucc_yaml_runtime_target "$cfg_dir" "$yaml" "docker-daemon"
}

# Apply silent-start settings to the Docker settings-store JSON.
# Usage: _docker_settings_store_patch <settings_store_relpath>
_docker_settings_store_patch() {
  local store="$HOME/$1"
  if [[ -f "$store" ]]; then
    local tmp; tmp="$(mktemp)"
    jq '. + {"OpenUIOnStartupDisabled": true, "DisplayedOnboarding": true, "ShowInstallScreen": false}' \
      "$store" > "$tmp" && mv "$tmp" "$store" || rm -f "$tmp"
  else
    mkdir -p "$(dirname "$store")"
    printf '{"OpenUIOnStartupDisabled":true,"DisplayedOnboarding":true,"ShowInstallScreen":false}\n' > "$store"
  fi
}

# Ensure cask is installed/up-to-date via brew, skipping if already present via app-bundle.
_docker_cask_ensure() {
  local cask_id="$1" app_path="$2" greedy="$3"
  local install_source; install_source="$(desktop_app_install_source "$cask_id" "$app_path")"
  if [[ "$install_source" == "app-bundle" ]]; then
    desktop_app_handle_unmanaged_cask "$cask_id" "Docker Desktop" || return $?
    return 0
  fi
  local observed; observed="$(brew_cask_observe "$cask_id" "$greedy")"
  [[ "$observed" == "absent" && -d "$app_path" ]] && observed="installed"
  if [[ "$observed" == "absent" ]]; then
    brew_cask_install "$cask_id" || return 1
  elif [[ "$observed" == "outdated" ]]; then
    brew_cask_upgrade "$cask_id" "$greedy" || return 1
  fi
}

# Uses implicit $CFG_DIR/$YAML_PATH/$TARGET_NAME context.
_docker_desktop_install() {
  local cask_id app_path settings_store_relpath
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      docker_desktop_cask_id) cask_id="$value" ;;
      docker_desktop_app_path) app_path="$value" ;;
      docker_settings_store_relpath) settings_store_relpath="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" docker_desktop_cask_id docker_desktop_app_path docker_settings_store_relpath)
  local greedy; greedy="$(_ucc_yaml_target_get "$CFG_DIR" "$YAML_PATH" "$TARGET_NAME" "driver.greedy_auto_updates")"
  _docker_cask_ensure "$cask_id" "$app_path" "$greedy" || return $?
  _docker_settings_store_patch "$settings_store_relpath"
}

# Kill all running Docker processes to avoid XPC/IPC hangs on restart.
# Usage: _docker_kill_zombies <kill_pattern>
_docker_kill_zombies() {
  pkill -f "$1" 2>/dev/null || true
  sleep 2
}

# Launch Docker Desktop in a clean environment with a PTY (required by docker desktop start).
_docker_launch() {
  log_info "Starting Docker Desktop..."
  env -i HOME="$HOME" PATH="$PATH" USER="$USER" TERM="${TERM:-}" \
    script -q /dev/null docker desktop start
}

# Uses implicit $CFG_DIR/$YAML_PATH context.
_docker_daemon_start() {
  local settings_store_relpath kill_pattern
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      docker_settings_store_relpath) settings_store_relpath="$value" ;;
      docker_kill_pattern) kill_pattern="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" docker_settings_store_relpath docker_kill_pattern)
  _docker_settings_store_patch "$settings_store_relpath"
  _docker_kill_zombies "$kill_pattern"
  _docker_launch
}

# Usage: run_docker_config_from_yaml <cfg_dir> <yaml_path>
run_docker_config_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  local settings_relpath memory_gb cpu_count swap_mib disk_mib
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
