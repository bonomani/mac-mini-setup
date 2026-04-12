#!/usr/bin/env bash
# lib/docker.sh — Docker Desktop install + daemon startup
# Sourced by components/docker.sh

# Observe docker-desktop install state: installed | absent
# Probe the .app bundle directly. We do not check `command -v docker` because
# brew cask installs the docker CLI symlink at /usr/local/bin/docker (legacy
# Intel path), and on Apple Silicon /usr/local/bin is not always in PATH for
# the framework's observe sub-shells, which would falsely report 'absent'
# even when Docker.app is fully installed and running.
docker_desktop_observe() {
  [[ -d /Applications/Docker.app ]] && printf 'installed' || printf 'absent'
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
  ucc_yaml_capability_target "$cfg_dir" "$yaml" "docker-available"

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
_docker_bootstrap_complete() {
  local settings="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
  [[ -f "$settings" ]] && grep -q '"LicenseTermsVersion"' "$settings" 2>/dev/null
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
  local cask_id app_path settings_relpath
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      docker_desktop_cask_id) cask_id="$value" ;;
      docker_desktop_app_path) app_path="$value" ;;
      settings_relpath)       settings_relpath="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" docker_desktop_cask_id docker_desktop_app_path settings_relpath)
  local greedy; greedy="$(_ucc_yaml_target_get "$CFG_DIR" "$YAML_PATH" "$TARGET_NAME" "driver.greedy_auto_updates")"
  _docker_cask_ensure "$cask_id" "$app_path" "$greedy" || return $?
  _docker_settings_store_patch "$settings_relpath"
}

# Install Docker Desktop cask + start daemon.
# Uses implicit $CFG_DIR/$YAML_PATH/$TARGET_NAME context.
_docker_desktop_install_and_start() {
  # First-time Docker Desktop setup on macOS requires interactive input at
  # three points that have no straightforward CLI bypass:
  #   1. brew cask install symlinks Docker's CLI plugins into
  #      /usr/local/cli-plugins (a system path), which prompts sudo.
  #      Cached sudo would satisfy this except Homebrew issue #17915
  #      invalidates the user's sudo ticket on every brew invocation.
  #   2. Docker.app's first launch installs a privileged helper via macOS
  #      Authorization Services (a Cocoa dialog). Not a sudo prompt — a
  #      separate authentication subsystem with no CLI bypass.
  #   3. Docker shows the Subscription Service Agreement; if not accepted,
  #      the daemon shuts itself down.
  # In non-interactive mode none of these can be satisfied under the
  # default (manual) preference, so the run would hang or leave Docker
  # half-installed. Bail out cleanly with a clear message instead.
  # The experimental `assisted` preference (see lib/docker_unattended.sh)
  # bypasses all three with an askpass shim + EULA pre-write + vmnetd
  # seeding — opted into via UIC_PREF_DOCKER_FIRST_INSTALL=assisted.
  if ! _docker_bootstrap_complete; then
    if [[ "${UIC_PREF_DOCKER_FIRST_INSTALL:-manual}" == "assisted" ]]; then
      _docker_assisted_install
      return $?
    fi
    if [[ "${UCC_INTERACTIVE:-1}" != "1" ]]; then
      log_warn "Docker Desktop has not been bootstrapped on this user yet."
      log_warn "First-time setup requires an interactive run for:"
      log_warn "  - sudo password (brew cask /usr/local/cli-plugins symlinks)"
      log_warn "  - macOS Authorization Services dialog (privileged helper)"
      log_warn "  - Docker EULA acceptance dialog"
      log_warn "Re-run interactively (./install.sh docker-desktop) to complete setup,"
      log_warn "or opt into the experimental assisted recipe via:"
      log_warn "  UCC_SUDO_PASS='...' ./install.sh --pref docker-first-install=assisted --no-interactive docker-desktop"
      log_warn "Subsequent --no-interactive runs will work normally."
      return 1
    fi
    log_info "First-time Docker Desktop setup will prompt for admin password and EULA acceptance."
  fi
  _docker_desktop_install || return $?
  _docker_daemon_start
}

# Gracefully stop Docker Desktop to avoid the stuck 500-error state.
#
# `osascript quit "Docker Desktop"` is the only reliable way to fully
# stop Docker Desktop on Apple Silicon. Alternatives that don't work:
#   - `pkill -f com.docker` — force-kills processes, leaves the daemon
#     API in a persistent 500-error state on restart.
#   - `osascript quit "Docker"` — partially stops it, same 500 result.
#   - `docker desktop stop` — may not be available on fresh installs.
#
# If osascript quit fails (Docker hung/unresponsive), we fall back to
# pkill as a last resort — the 500 state is better than no stop at all.
#
# Usage: _docker_kill_zombies <kill_pattern>
_docker_kill_zombies() {
  osascript -e 'quit app "Docker Desktop"' 2>/dev/null || true
  sleep 5
  # If Docker Desktop didn't respond to the graceful quit, force-kill
  if pgrep -f "$1" >/dev/null 2>&1; then
    pkill -f "$1" 2>/dev/null || true
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
#
# GNU `timeout` is not available on macOS by default, so we use a
# portable background+kill pattern: run docker info in background,
# poll its PID for up to 5s, kill if it's still hanging.
_docker_ready() {
  docker info >/dev/null 2>&1 &
  local _pid=$!
  local _t=0
  while (( _t++ < 5 )); do
    if ! kill -0 "$_pid" 2>/dev/null; then
      wait "$_pid" 2>/dev/null
      return $?
    fi
    sleep 1
  done
  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  return 1
}

_docker_launch() {
  log_info "Starting Docker Desktop..."

  # Pre-check: detect the stuck 500-error state from a previous
  # partial shutdown. In this state, the daemon API accepts connections
  # but always returns HTTP 500. No amount of open -g fixes it — only
  # a full `quit app "Docker Desktop"` + fresh start recovers.
  # Check before opening so we don't waste 140s polling a broken daemon.
  local _pre
  _pre="$(docker info 2>&1)"
  if [[ "$_pre" == *"500 Internal Server Error"* ]]; then
    log_warn "Docker daemon in 500 error state — quitting Docker Desktop"
    osascript -e 'quit app "Docker Desktop"' 2>/dev/null || true
    sleep 5
  fi

  open -g /Applications/Docker.app || return $?

  # Wait for the daemon API to respond (max ~140s).
  #
  # We use `docker info` (via _docker_ready) rather than probing a
  # specific socket path because Docker Desktop 4.x on Apple Silicon
  # does NOT always use ~/.docker/run/docker.sock. The actual socket
  # location depends on the docker CLI context (e.g. "desktop-linux"
  # context routes to the containerized VM socket). `docker info`
  # respects the active context and always finds the right endpoint.
  #
  # Each _docker_ready call is bounded to ~5s. With 2s sleep between
  # iterations, each cycle is ~7s max. 20 iterations = ~140s budget.
  local i
  for i in $(seq 1 20); do
    if _docker_ready; then
      log_info "Docker daemon ready after ~$((i*7))s"
      return 0
    fi
    # Mid-loop 500 detection: if Docker entered the 500 state during
    # startup (shouldn't happen on a clean start, but defensive), bail
    # early rather than burning the remaining budget.
    _pre="$(docker info 2>&1)"
    if [[ "$_pre" == *"500 Internal Server Error"* ]]; then
      log_warn "Docker daemon entered 500 error state during startup"
      return 1
    fi
    sleep 2
  done
  log_warn "Docker daemon not reachable after ~140s"
  return 1
}

# Uses implicit $CFG_DIR/$YAML_PATH context.
_docker_daemon_start() {
  local settings_relpath kill_pattern app_path
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      settings_relpath)          settings_relpath="$value" ;;
      docker_kill_pattern)       kill_pattern="$value" ;;
      docker_desktop_app_path)   app_path="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" settings_relpath docker_kill_pattern docker_desktop_app_path)
  # Defensive: strip Gatekeeper quarantine from the existing Docker.app before
  # launch. Covers pre-existing installs that never went through _docker_cask_ensure,
  # so `docker desktop start` does not hang on the "downloaded from the Internet"
  # prompt in --no-interactive runs.
  _docker_strip_quarantine "$app_path"
  _docker_settings_store_patch "$settings_relpath"

  # Try a soft start first — launch Docker.app and wait for the daemon
  # API to become reachable. Only if the soft start fails (daemon
  # unreachable after 120s), kill all Docker processes and retry.
  #
  # Previously we always ran _docker_kill_zombies before _docker_launch,
  # which was reliable for existing-and-running Docker (the kill+restart
  # cleared XPC state). But on a fresh install or cold start, `open -a`
  # after `pkill -f com.docker` can leave Docker in a half-dead state
  # where the app opens but the daemon never comes up — macOS's
  # LaunchServices doesn't always treat a pkill'd app as fully exited,
  # so `open -a` may not trigger a clean startup.
  #
  # Soft-first fixes the common case (Docker not running → open -a
  # starts it cleanly) while keeping the kill+retry as a fallback for
  # genuine IPC hangs.
  if _docker_launch; then
    return 0
  fi
  log_warn "Docker soft start failed — killing processes and retrying"
  _docker_kill_zombies "$kill_pattern"
  _docker_launch
}

