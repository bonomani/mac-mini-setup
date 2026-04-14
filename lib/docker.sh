#!/usr/bin/env bash
# lib/docker.sh — Docker Desktop app install + daemon lifecycle
# Sourced via docker.yaml libs: field
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
# ── Shutdown cascade timing (kill tests on Apple Silicon) ──
#
#   Kill target          │ Cascade │ Delay to full shutdown
#   ─────────────────────┼─────────┼───────────────────────
#   backend (root)       │ yes     │ immediate
#   backend services     │ yes     │ <5s
#   backend fork         │ yes     │ ~2s
#   Docker Desktop (GUI) │ yes     │ ~4.5s
#   com.docker.virtualization │ yes │ ~10-15s
#
# Key findings:
# - Killing ANY component triggers full shutdown (no resilience/auto-restart)
# - The backend detects child death and tears down the entire tree
# - The socket (~/.docker/run/docker.sock) is removed when backend exits
# - During shutdown, pgrep may still see backend for a few seconds after
#   the daemon is already unreachable — always probe the socket, not the PID
#

# Observe docker-desktop install state: installed | absent
# Probe the .app bundle directly. We do not check `command -v docker` because
# brew cask installs the docker CLI symlink at /usr/local/bin/docker (legacy
# Intel path), and on Apple Silicon /usr/local/bin is not always in PATH for
# the framework's observe sub-shells, which would falsely report 'absent'
# even when Docker.app is fully installed and running.
# Uses implicit $CFG_DIR/$YAML_PATH context.
docker_desktop_observe() {
  local app_path
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      docker_desktop_app_path) app_path="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" docker_desktop_app_path)
  [[ -d "$app_path" ]] && printf 'installed' || printf 'absent'
}

# Return 0 if Docker Desktop (the macOS app) is running.
# Checks for com.docker.backend, which is the root process of Docker Desktop
# (PPID 1, launched by launchd). It spawns everything else: the GUI (Electron),
# the Linux VM (com.docker.virtualization), BuildKit, and helpers.
# This is distinct from docker_daemon_is_running which checks if the docker
# API (daemon inside the VM) is reachable via the socket.
# Uses implicit $CFG_DIR/$YAML_PATH context.
docker_desktop_is_running() {
  local pattern
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      docker_desktop_process) pattern="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" docker_desktop_process)
  pgrep -q "$pattern" 2>/dev/null
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

# Observe privileged port mapping state.
# On Docker Desktop 4.x Apple Silicon, vmnetd is "theatre" — the binary
# must exist in /Library/PrivilegedHelperTools/ to satisfy the legacy
# SMJobBless check, but the launchd service does not need to stay loaded
# (Docker uses com.docker.helper at user level instead).
# Uses implicit $CFG_DIR/$YAML_PATH context.
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

# Print desired privileged port mapping state.
docker_privileged_ports_desired() {
  printf 'binary=seeded setting=enabled'
}

# Apply privileged port mapping: seed vmnetd binary + set RequireVmnetd: true.
# The binary must exist in /Library/PrivilegedHelperTools/ to satisfy
# Docker's SMJobBless check. The launchd service does not need to be
# loaded — Docker 4.x Apple Silicon uses com.docker.helper instead.
# Requires sudo for the binary copy. Uses implicit $CFG_DIR/$YAML_PATH context.
docker_privileged_ports_apply() {
  local settings_relpath app_path
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      settings_relpath)        settings_relpath="$value" ;;
      docker_desktop_app_path) app_path="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" settings_relpath docker_desktop_app_path)
  local settings_path="$HOME/$settings_relpath"

  # Seed vmnetd binary (reuses assisted-install helper)
  if [[ ! -f /Library/PrivilegedHelperTools/com.docker.vmnetd ]]; then
    _docker_assisted_seed_vmnetd "$app_path" \
      || { log_warn "vmnetd seeding failed"; return 1; }
  fi

  # Set RequireVmnetd: true in settings-store.json
  if [[ -f "$settings_path" ]]; then
    local patch_dir="$CFG_DIR/.build"
    mkdir -p "$patch_dir"
    printf '{"RequireVmnetd": true}\n' > "$patch_dir/docker-vmnetd-patch.json"
    python3 "$CFG_DIR/tools/drivers/json_merge.py" apply \
      "$settings_path" "$patch_dir/docker-vmnetd-patch.json"
    log_warn "Restart Docker Desktop to apply privileged port mapping"
  fi
}

# Print Docker CLI version string (e.g. "27.3.1").
# Queries the daemon API via socket to avoid PATH dependency.
# Falls back to docker --version if socket is unavailable.
docker_version() {
  local sock="$HOME/.docker/run/docker.sock"
  if [[ -S "$sock" ]]; then
    curl -sf --unix-socket "$sock" http://localhost/version 2>/dev/null \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('Version',''))" 2>/dev/null
  else
    docker --version 2>/dev/null | awk '{print $3}' | tr -d ','
  fi
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

# Print the PID of the Docker Desktop root process (com.docker.backend).
# This is the top-level process (PPID 1) that spawns the GUI, VM, and all
# helpers. dockerd runs inside the Linux VM and has no host-visible PID.
# Uses implicit $CFG_DIR/$YAML_PATH context.
docker_desktop_pid() {
  local pattern
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      docker_desktop_process) pattern="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" docker_desktop_process)
  pgrep -f "$pattern" 2>/dev/null | head -1
}

# Return 0 if the Docker daemon socket exists on the host.
# The daemon runs inside the Linux VM managed by Docker Desktop;
# the socket at ~/.docker/run/docker.sock is the host-side proxy.
# This avoids relying on `command -v docker` which depends on PATH
# (unreliable on Apple Silicon where /usr/local/bin is not guaranteed).
docker_daemon_configured() {
  [[ -S "$HOME/.docker/run/docker.sock" ]]
}

# Usage: run_docker_from_yaml <cfg_dir> <yaml_path>
# Registers all Docker targets. Install/start actions are wired in the
# YAML and handled by the framework:
#   docker-desktop: _docker_desktop_install (brew cask + settings patch)
#   docker-daemon:  _docker_daemon_start    (nohup open -g + /_ping poll)
run_docker_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  ucc_yaml_runtime_target "$cfg_dir" "$yaml" "docker-desktop"
  ucc_yaml_runtime_target "$cfg_dir" "$yaml" "docker-daemon"
  ucc_yaml_capability_target "$cfg_dir" "$yaml" "docker-available"
  ucc_yaml_parametric_target "$cfg_dir" "$yaml" "docker-resources"
  ucc_yaml_parametric_target "$cfg_dir" "$yaml" "docker-privileged-ports"
}

# Apply silent-start settings to the Docker settings-store JSON.
# RequireVmnetd: false suppresses the "privileged port mapping" macOS
# auth dialog that blocks Docker Desktop's startup in non-interactive
# mode. Ports >= 1024 work without vmnetd. If privileged ports are
# needed, the docker-privileged-ports-available target handles it.
# Usage: _docker_settings_store_patch <settings_store_relpath>
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

# Strip the macOS Gatekeeper quarantine xattr from a freshly installed .app so
# the first launch does not prompt "downloaded from the Internet, Open/Cancel".
_docker_strip_quarantine() {
  local app_path="$1"
  [[ -d "$app_path" ]] || return 0
  xattr -dr com.apple.quarantine "$app_path" 2>/dev/null || true
}

# Return 0 if Docker Desktop has been bootstrapped on this user account.
# Detected via the LicenseTermsVersion key in Docker's settings-store.json,
# which is only written after the user has accepted the EULA on first launch.
# Acceptance happens after the macOS Authorization Services dialog for the
# privileged helper, so if LicenseTermsVersion is set, every one-time
# interactive prompt (brew sudo for cli-plugins, helper auth, EULA) has
# already been satisfied at least once on this user account.
#
# We do NOT check /Library/PrivilegedHelperTools/com.docker.vmnetd: on
# Apple Silicon Docker Desktop 4.x uses com.docker.helper at user level,
# not vmnetd at system level, so the path is always missing on a fully
# working install.
# Uses implicit $CFG_DIR/$YAML_PATH context.
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

# Ensure cask is installed/up-to-date via brew, skipping if already present via app-bundle.
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

# Install Docker Desktop app (no daemon start — that's docker-daemon's job).
# Uses implicit $CFG_DIR/$YAML_PATH/$TARGET_NAME context.
#
# First-time install requires sudo for brew cask symlinks (cli-plugins
# into /usr/local). The `assisted` preference handles this via SUDO_ASKPASS.
# The `manual` preference (default) requires an interactive run.
_docker_desktop_install() {
  # First-time bootstrap gate: brew cask install needs sudo for
  # cli-plugins symlinks, and Docker needs EULA acceptance settings.
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
  # Ensure Docker Desktop is running — the framework expects a runtime
  # target's install action to reach Running state, not just Configured.
  _docker_strip_quarantine "$app_path"
  _docker_launch
}

# Gracefully stop Docker Desktop to avoid the stuck 500-error state.
#
# `osascript quit app` is the only reliable way to fully stop Docker
# Desktop on Apple Silicon. macOS routes the quit to the app bundle,
# which signals com.docker.backend (the root process, PPID 1) to tear
# down the entire process tree: GUI, VM, BuildKit, helpers.
# Alternatives that don't work:
#   - `pkill -f com.docker` — force-kills processes, leaves the daemon
#     API in a persistent 500-error state on restart.
#   - `osascript quit "Docker"` — partially stops it, same 500 result.
#   - `docker desktop stop` — may not be available on fresh installs.
#
# If osascript quit fails (Docker hung/unresponsive), we fall back to
# pkill as a last resort — the 500 state is better than no stop at all.
#
# Usage: _docker_kill_zombies <kill_pattern> <app_name>
_docker_kill_zombies() {
  local kill_pattern="$1" app_name="${2:-Docker Desktop}"
  osascript -e "quit app \"$app_name\"" 2>/dev/null || true
  sleep 5
  # If Docker Desktop didn't respond to the graceful quit, force-kill
  if pgrep -f "$kill_pattern" >/dev/null 2>&1; then
    pkill -f "$kill_pattern" 2>/dev/null || true
    sleep 2
  fi
}

# Launch Docker Desktop via macOS `open` and wait for the daemon API.
# We do NOT use `docker desktop start` because that CLI plugin may not
# be linked into any standard cli-plugins directory on a fresh install.
#
# We open the .app bundle directly (`open -g /path/Docker.app`) rather
# than using `-a` (`open -g -a /path/Docker.app`). The `-a` flag treats
# the path as an application name lookup, which can put Docker Desktop
# into a stuck 500-error state where the daemon API never becomes
# healthy. Opening the bundle directly is equivalent to double-clicking
# Docker.app in Finder and starts Docker reliably.
#
# `-g` launches in background without stealing focus.
# Probe Docker daemon readiness with a bounded timeout.
# `docker info` hangs during Docker Desktop's initialization phase
# (socket exists but API not yet accepting — the connection blocks
# inside the docker CLI for 30s+). Without a timeout, a single hung
# call eats the entire readiness budget.
# Probe Docker daemon readiness via the API socket directly.
# Avoids dependency on the docker CLI being in PATH (unreliable on
# Apple Silicon where /usr/local/bin is not always available).
# Falls back to docker ps -q if curl is unavailable.
_docker_ready() {
  # Default macOS Docker Desktop socket path. Override via UCC_DOCKER_SOCKET
  # for non-standard layouts (e.g. colima at $HOME/.colima/docker.sock).
  local sock="${UCC_DOCKER_SOCKET:-$HOME/.docker/run/docker.sock}"
  if [[ -S "$sock" ]]; then
    curl -sf --unix-socket "$sock" http://localhost/_ping >/dev/null 2>&1
  else
    docker ps -q >/dev/null 2>&1
  fi
}

# Uses implicit $CFG_DIR/$YAML_PATH context.
_docker_launch() {
  log_info "Starting Docker Desktop..."

  local app_path app_name
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      docker_desktop_app_path) app_path="$value" ;;
      docker_desktop_app_name) app_name="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" docker_desktop_app_path docker_desktop_app_name)

  # Pre-check: detect the stuck 500-error state from a previous
  # partial shutdown. In this state, the daemon API accepts connections
  # but always returns HTTP 500. No amount of open -g fixes it — only
  # a full `quit app` + fresh start recovers.
  # Check before opening so we don't waste 140s polling a broken daemon.
  local sock="$HOME/.docker/run/docker.sock"
  local _pre=""
  if [[ -S "$sock" ]]; then
    _pre="$(curl -s --unix-socket "$sock" http://localhost/info 2>&1)"
  else
    _pre="$(docker info 2>&1)"
  fi
  if [[ "$_pre" == *"500"* ]]; then
    log_warn "Docker daemon in 500 error state — quitting $app_name"
    osascript -e "quit app \"$app_name\"" 2>/dev/null || true
    sleep 5
  fi

  # Launch with a clean environment. install.sh accumulates hundreds of
  # exported _UCC_* variables (145+ KB) which are inherited by the nohup
  # child. Docker Desktop's com.docker.backend silently fails to start
  # when the inherited environment is too large. `env -i` strips all
  # inherited vars; we pass only HOME and PATH which Docker needs.
  log_info "Launching Docker Desktop..."
  nohup env -i HOME="$HOME" PATH="$PATH" \
    bash -c "sleep 1; open -g '$app_path'" &>/dev/null &

  # Wait up to 30s for daemon readiness. If Docker doesn't respond
  # within 30s, it's not coming up — don't waste minutes retrying.
  local i
  for i in $(seq 1 10); do
    if _docker_ready; then
      log_info "Docker daemon ready after $((i*3))s"
      return 0
    fi
    sleep 3
  done
  log_warn "Docker daemon not reachable after 30s"
  return 1
}

# Uses implicit $CFG_DIR/$YAML_PATH context.
_docker_daemon_start() {
  local settings_relpath app_path
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      settings_relpath)          settings_relpath="$value" ;;
      docker_desktop_app_path)   app_path="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" settings_relpath docker_desktop_app_path)
  # Defensive: strip Gatekeeper quarantine from the existing Docker.app before
  # launch. Covers pre-existing installs that never went through _docker_cask_ensure,
  # so `docker desktop start` does not hang on the "downloaded from the Internet"
  # prompt in --no-interactive runs.
  _docker_strip_quarantine "$app_path"
  _docker_settings_store_patch "$settings_relpath"

  _docker_launch
}

