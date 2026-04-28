#!/usr/bin/env bash
# lib/docker_desktop_macos.sh — Docker Desktop app install + launch (macOS only).
#
# Sourced via docker.yaml libs: field through lib/docker.sh loader.
# Cross-platform daemon helpers live in lib/docker_common.sh; Linux/WSL
# engine support lives in lib/docker_engine.sh. Functions here assume
# macOS-only tooling (osascript, open, xattr, brew cask, /Applications,
# Docker Desktop's settings-store.json).
#
# ── Docker Desktop process architecture (macOS, verified 2026-04-13) ──
#
# com.docker.backend is the root process (PPID 1, launched by launchd via
# `open -g /Applications/Docker.app`). It spawns two direct children:
#
#   com.docker.backend (PPID 1)          ← root, launched by launchd
#   ├── backend services                  ← manages the VM
#   │   └── com.docker.virtualization     ← Linux VM (Apple Virtualization.framework)
#   │       └── dockerd (inside VM)       ← the actual Docker daemon (no host PID)
#   └── backend fork                      ← manages everything else
#       ├── com.docker.build              ← BuildKit
#       ├── docker-sandbox
#       ├── Docker Desktop (Electron GUI) ← child of backend, NOT the other way around
#       │   └── Helper, Renderer, docker CLI instances
#       └── docker-agent                  ← Gordon AI
#
# Killing ANY component triggers full shutdown (no resilience/auto-restart).
# The socket (~/.docker/run/docker.sock) is removed when backend exits.
# During shutdown, pgrep may still see backend for a few seconds after the
# daemon is unreachable — always probe the socket, not the PID.

# Observe docker-desktop install state: installed | absent.
# Probes the .app bundle directly; PATH is unreliable on Apple Silicon.
docker_desktop_observe() {
  local app_path
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      docker_desktop_app_path) app_path="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" docker_desktop_app_path)
  [[ -d "$app_path" ]] && printf 'installed' || printf 'absent'
}

# Return 0 if Docker Desktop (the macOS app) is running. Checks for
# com.docker.backend, the root process. Distinct from the daemon-API check.
docker_desktop_is_running() {
  local pattern
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      docker_desktop_process) pattern="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" docker_desktop_process)
  pgrep -q "$pattern" 2>/dev/null
}

_docker_settings_path() {
  printf '%s/%s' "$HOME" "$(_ucc_yaml_target_get "$CFG_DIR" "$YAML_PATH" "docker-resources" "driver.settings_relpath")"
}

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

docker_resources_desired() {
  local _mem _cpu _swap _disk
  IFS=$'\t' read -r _mem _cpu _swap _disk <<< "$(_docker_resources_config)"
  printf 'mem=%sGB cpu=%s swap=%sMiB disk=%sMiB' "$_mem" "$_cpu" "$_swap" "$_disk"
}

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

# Observe privileged port mapping state (vmnetd binary + RequireVmnetd setting).
docker_privileged_ports_observe() {
  local settings_relpath
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      settings_relpath) settings_relpath="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" settings_relpath)
  local settings_path="$HOME/$settings_relpath"

  local bin_ok="false" cfg_ok="false"

  [[ -f /Library/PrivilegedHelperTools/com.docker.vmnetd ]] && bin_ok="true"

  if [[ -f "$settings_path" ]]; then
    python3 -c "
import json, sys
d = json.loads(open(sys.argv[1]).read())
sys.exit(0 if d.get('RequireVmnetd') is True else 1)
" "$settings_path" 2>/dev/null && cfg_ok="true"
  fi

  if [[ "$bin_ok" == "true" && "$cfg_ok" == "true" ]]; then
    printf 'binary=seeded setting=enabled'
  elif [[ "$bin_ok" == "false" && "$cfg_ok" == "false" ]]; then
    printf 'absent'
  else
    printf 'binary=%s setting=%s' \
      "$( [[ "$bin_ok" == "true" ]] && echo seeded || echo missing )" \
      "$( [[ "$cfg_ok" == "true" ]] && echo enabled || echo disabled )"
  fi
}

docker_privileged_ports_desired() {
  printf 'binary=seeded setting=enabled'
}

docker_privileged_ports_apply() {
  local settings_relpath app_path
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      settings_relpath)        settings_relpath="$value" ;;
      docker_desktop_app_path) app_path="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" settings_relpath docker_desktop_app_path)
  local settings_path="$HOME/$settings_relpath"

  if [[ ! -f /Library/PrivilegedHelperTools/com.docker.vmnetd ]]; then
    _docker_assisted_seed_vmnetd "$app_path" \
      || { log_warn "vmnetd seeding failed"; return 1; }
  fi

  if [[ -f "$settings_path" ]]; then
    local patch_dir="$CFG_DIR/.build"
    mkdir -p "$patch_dir"
    printf '{"RequireVmnetd": true}\n' > "$patch_dir/docker-vmnetd-patch.json"
    python3 "$CFG_DIR/tools/drivers/json_merge.py" apply \
      "$settings_path" "$patch_dir/docker-vmnetd-patch.json"
    log_warn "Restart Docker Desktop to apply privileged port mapping"
  fi
}

# Print non-cask install source of Docker Desktop (e.g. app-bundle), or empty.
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

# Print PID of com.docker.backend (root Docker Desktop process).
docker_desktop_pid() {
  local pattern
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      docker_desktop_process) pattern="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" docker_desktop_process)
  pgrep -f "$pattern" 2>/dev/null | head -1
}

# Apply silent-start settings to Docker's settings-store.json. Suppresses
# the privileged-port auth dialog that blocks startup non-interactively.
_docker_settings_store_patch() {
  local store="$HOME/$1"
  if [[ -f "$store" ]]; then
    local tmp; tmp="$(mktemp)"
    jq '. + {"OpenUIOnStartupDisabled": true, "DisplayedOnboarding": true, "ShowInstallScreen": false, "RequireVmnetd": false}' \
      "$store" > "$tmp" && mv "$tmp" "$store" || rm -f "$tmp"
  else
    mkdir -p "$(dirname "$store")"
    printf '{"OpenUIOnStartupDisabled":true,"DisplayedOnboarding":true,"ShowInstallScreen":false,"RequireVmnetd":false}\n' > "$store"
  fi
}

# Strip macOS Gatekeeper quarantine xattr from a freshly installed .app.
_docker_strip_quarantine() {
  local app_path="$1"
  [[ -d "$app_path" ]] || return 0
  xattr -dr com.apple.quarantine "$app_path" 2>/dev/null || true
}

# Return 0 if Docker Desktop has been bootstrapped (EULA accepted) on this user.
_docker_bootstrap_complete() {
  local settings_relpath
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      settings_relpath) settings_relpath="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" settings_relpath)
  local settings="$HOME/$settings_relpath"
  [[ -f "$settings" ]] && grep -q '"LicenseTermsVersion"' "$settings" 2>/dev/null
}

# Ensure cask is installed/up-to-date via brew, skipping if app-bundle install present.
_docker_cask_ensure() {
  local cask_id="$1" app_path="$2" greedy="$3" display_name="$4"
  local install_source; install_source="$(desktop_app_install_source "$cask_id" "$app_path")"
  if [[ "$install_source" == "app-bundle" ]]; then
    desktop_app_handle_unmanaged_cask "$cask_id" "$display_name" || return $?
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

# Install Docker Desktop app (cask + settings patch + launch).
_docker_desktop_install() {
  if ! _docker_bootstrap_complete; then
    if [[ "${UIC_PREF_DOCKER_FIRST_INSTALL:-manual}" == "assisted" ]]; then
      _docker_assisted_install
      return $?
    fi
    if [[ "${UCC_INTERACTIVE:-1}" != "1" ]]; then
      log_warn "Docker Desktop has not been bootstrapped on this user yet."
      log_warn "First-time setup requires an interactive run for:"
      log_warn "  - sudo password (brew cask /usr/local/cli-plugins symlinks)"
      log_warn "  - Docker EULA acceptance dialog"
      log_warn "Re-run interactively (./install.sh docker-desktop) to complete setup,"
      log_warn "or opt into the experimental assisted recipe via:"
      log_warn "  UCC_SUDO_PASS='...' ./install.sh --pref docker-first-install=assisted --no-interactive docker-desktop"
      log_warn "Subsequent --no-interactive runs will work normally."
      return 1
    fi
    log_info "First-time Docker Desktop setup will prompt for admin password and EULA acceptance."
  fi
  local cask_id app_path settings_relpath
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      docker_desktop_cask_id)  cask_id="$value" ;;
      docker_desktop_app_path) app_path="$value" ;;
      settings_relpath)        settings_relpath="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" docker_desktop_cask_id docker_desktop_app_path settings_relpath)
  local greedy; greedy="$(_ucc_yaml_target_get "$CFG_DIR" "$YAML_PATH" "$TARGET_NAME" "driver.greedy_auto_updates")"
  _docker_cask_ensure "$cask_id" "$app_path" "$greedy" "Docker Desktop"
  _docker_settings_store_patch "$settings_relpath"
  _docker_strip_quarantine "$app_path"
  _docker_launch
}

# Gracefully stop Docker Desktop (osascript quit; pkill fallback).
_docker_kill_zombies() {
  local kill_pattern="$1" app_name="${2:-Docker Desktop}"
  osascript -e "quit app \"$app_name\"" 2>/dev/null || true
  sleep 5
  if pgrep -f "$kill_pattern" >/dev/null 2>&1; then
    pkill -f "$kill_pattern" 2>/dev/null || true
    sleep 2
  fi
}

# Launch Docker Desktop via macOS `open` and wait for the daemon API.
# Uses implicit $CFG_DIR/$YAML_PATH context.
_docker_launch() {
  [[ "${HOST_PLATFORM:-macos}" == "macos" ]] || {
    log_warn "Docker Desktop launch is macOS-only; use _docker_engine_start for Linux/WSL Docker Engine"
    return 125
  }
  log_info "Starting Docker Desktop..."

  local app_path app_name
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      docker_desktop_app_path) app_path="$value" ;;
      docker_desktop_app_name) app_name="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" docker_desktop_app_path docker_desktop_app_name)

  # Pre-check: detect 500-error stuck state from a prior partial shutdown.
  local sock; sock="$(docker_socket_path)"
  local _pre=""
  if [[ -S "$sock" ]]; then
    _pre="$(curl -s --unix-socket "$sock" http://localhost/info 2>&1)"
  else
    _pre="$(docker info 2>&1)"
  fi
  if [[ "$_pre" == *"500"* ]]; then
    log_warn "Docker daemon in 500 error state — quitting $app_name"
    osascript -e "quit app \"$app_name\"" 2>/dev/null || true
    sleep "${UCC_DOCKER_QUIT_WAIT_S:-5}"
  fi

  # Launch with a clean environment. install.sh accumulates 145+ KB of
  # exported _UCC_* vars; Docker Desktop's com.docker.backend silently
  # fails to start when the inherited environment is too large.
  log_info "Launching Docker Desktop..."
  nohup env -i HOME="$HOME" PATH="$PATH" \
    bash -c "sleep 1; open -g '$app_path'" &>/dev/null &

  local _interval="${UCC_DOCKER_READY_INTERVAL_S:-3}"
  local _attempts="${UCC_DOCKER_READY_ATTEMPTS:-10}"
  local i
  for i in $(seq 1 "$_attempts"); do
    if _docker_ready; then
      log_info "Docker daemon ready after $((i * _interval))s"
      return 0
    fi
    sleep "$_interval"
  done
  log_warn "Docker daemon not reachable after $((_attempts * _interval))s"
  return 1
}
