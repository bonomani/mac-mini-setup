#!/usr/bin/env bash
# lib/docker.sh — Docker Desktop install + daemon startup
# Sourced by components/docker.sh

# Observe docker-desktop install state: installed | absent
docker_desktop_observe() {
  command -v docker >/dev/null 2>&1 && printf 'installed' || printf 'absent'
}

# Resolve Docker settings-store.json full path from YAML.
_docker_settings_path() {
  printf '%s/%s' "$HOME" "$(_ucc_yaml_target_get "$CFG_DIR" "$YAML_PATH" "docker-resources" "driver.settings_relpath")"
}

# Read docker-resources target config (respects user prefs over YAML defaults).
_docker_resources_config() {
  local mem_gb cpu_count swap_mib disk_mib
  mem_gb="$(_ucc_yaml_target_get "$CFG_DIR" "$YAML_PATH" "docker-resources" "driver.memory_gb")"
  cpu_count="$(_ucc_yaml_target_get "$CFG_DIR" "$YAML_PATH" "docker-resources" "driver.cpu_count")"
  swap_mib="$(_ucc_yaml_target_get "$CFG_DIR" "$YAML_PATH" "docker-resources" "driver.swap_mib")"
  disk_mib="$(_ucc_yaml_target_get "$CFG_DIR" "$YAML_PATH" "docker-resources" "driver.disk_mib")"
  printf '%s\t%s\t%s\t%s' \
    "${UIC_PREF_DOCKER_MEMORY_GB:-$mem_gb}" \
    "${UIC_PREF_DOCKER_CPU_COUNT:-$cpu_count}" \
    "${UIC_PREF_DOCKER_SWAP_MIB:-$swap_mib}" \
    "${UIC_PREF_DOCKER_DISK_MIB:-$disk_mib}"
}

# Observe current Docker resource settings from settings-store.json.
docker_resources_observe() {
  local settings_path; settings_path="$(_docker_settings_path)"
  [[ -f "$settings_path" ]] || { printf 'absent'; return; }
  python3 -c "
import json, sys
d = json.loads(open(sys.argv[1]).read())
mem = int(d.get('memoryMiB', 0)) // 1024
cpu = int(d.get('cpus', 0))
swap = int(d.get('swapMiB', 0))
disk = int(d.get('diskSizeMiB', 0))
if mem == 0 and cpu == 0:
    print('absent')
else:
    print(f'mem={mem}GB cpu={cpu} swap={swap}MiB disk={disk}MiB')
" "$settings_path" 2>/dev/null || printf 'absent'
}

# Print desired Docker resource settings from target config + prefs.
docker_resources_desired() {
  local _mem _cpu _swap _disk
  IFS=$'\t' read -r _mem _cpu _swap _disk <<< "$(_docker_resources_config)"
  printf 'mem=%sGB cpu=%s swap=%sMiB disk=%sMiB' "$_mem" "$_cpu" "$_swap" "$_disk"
}

# Apply Docker resource settings via json-merge.
docker_resources_apply() {
  local settings_path; settings_path="$(_docker_settings_path)"
  [[ -f "$settings_path" ]] || { log_warn "Docker settings file not found — launch Docker first"; return 1; }
  local _mem _cpu _swap _disk
  IFS=$'\t' read -r _mem _cpu _swap _disk <<< "$(_docker_resources_config)"
  local _mem_mib=$(( _mem * 1024 ))
  local _patch_dir="$CFG_DIR/.build"
  mkdir -p "$_patch_dir"
  printf '{"memoryMiB": %d, "cpus": %d, "swapMiB": %d, "diskSizeMiB": %d}\n' \
    "$_mem_mib" "$_cpu" "$_swap" "$_disk" > "$_patch_dir/docker-resources-patch.json"
  ucc_run python3 "$CFG_DIR/tools/drivers/json_merge.py" apply "$settings_path" "$_patch_dir/docker-resources-patch.json"
  log_warn "Restart Docker Desktop to apply new resource settings"
}

# Print Docker CLI version string (e.g. "27.3.1").
docker_version() {
  docker --version 2>/dev/null | awk '{print $3}' | tr -d ','
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

  # ---- Phase 1-3: install + runtime ----
  ucc_yaml_runtime_target "$cfg_dir" "$yaml" "docker-desktop"

  # ---- Capability: docker daemon reachable ----
  ucc_yaml_runtime_target "$cfg_dir" "$yaml" "docker-available"

  # ---- Phase 4: post-runtime config (resources) ----
  ucc_yaml_parametric_target "$cfg_dir" "$yaml" "docker-resources"
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

# Strip the macOS Gatekeeper quarantine xattr from a freshly installed .app so
# the first launch does not prompt "downloaded from the Internet, Open/Cancel".
_docker_strip_quarantine() {
  local app_path="$1"
  [[ -d "$app_path" ]] || return 0
  xattr -dr com.apple.quarantine "$app_path" 2>/dev/null || true
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
    _docker_strip_quarantine "$app_path"
  elif [[ "$observed" == "outdated" ]]; then
    brew_cask_upgrade "$cask_id" "$greedy" || return 1
    _docker_strip_quarantine "$app_path"
  fi
}

# Install Docker Desktop cask only (no daemon start).
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

# Install Docker Desktop cask + start daemon.
# Uses implicit $CFG_DIR/$YAML_PATH/$TARGET_NAME context.
_docker_desktop_install_and_start() {
  _docker_desktop_install || return $?
  _docker_daemon_start
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

