#!/usr/bin/env bash
# Shared shell utilities (non-UCC helpers)
# Logging must go through lib/ucc.sh — do not redefine log_* here.

# Ensure brew is in PATH for every component subshell (Apple Silicon / Intel)
for _bp in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
  if [[ -x "$_bp" ]] && ! command -v brew &>/dev/null; then
    eval "$("$_bp" shellenv)"
    break
  fi
done
unset _bp

# Ensure pyenv shims are in PATH for every component subshell.
# Wrap both eval calls to absorb any stderr the generated init script
# emits (e.g. on shells where some helper functions fail to define), so
# sourcing utils.sh stays silent in tests/probes.
if [[ -d "$HOME/.pyenv" ]]; then
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  { eval "$(pyenv init --path 2>/dev/null)" || true; } 2>/dev/null
  { eval "$(pyenv init - 2>/dev/null)" || true; } 2>/dev/null
fi

# Stable interpreter for framework-internal manifest queries (validate_targets_manifest.py,
# read_config.py). Pinned away from pyenv shims so a broken/PyYAML-less user Python
# can't crash the framework. Override with UCC_FRAMEWORK_PYTHON to force a specific path.
if [[ -z "${UCC_FRAMEWORK_PYTHON:-}" ]]; then
  for _fp in /usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    if [[ -x "$_fp" ]] && "$_fp" -c 'import yaml' 2>/dev/null; then
      export UCC_FRAMEWORK_PYTHON="$_fp"
      break
    fi
  done
  : "${UCC_FRAMEWORK_PYTHON:=python3}"
  export UCC_FRAMEWORK_PYTHON
fi
unset _fp

# Check if a command exists
is_installed() { command -v "$1" &>/dev/null; }

# Return 0 if a command is NOT installed.
is_not_installed() { ! command -v "$1" &>/dev/null; }

# Probe the named HTTP endpoint for the current target (uses $CFG_DIR/$YAML_PATH/$TARGET_NAME).
# Intended for oracle.runtime fields — hides framework plumbing from YAML.
# Usage: http_probe_endpoint [endpoint_name]
http_probe_endpoint() {
  _ucc_http_probe_endpoint "$CFG_DIR" "$YAML_PATH" "$TARGET_NAME" "${1:-}"
}

# Return 0 if a Python module can be imported.
# Usage: python3_module_importable <module>
python3_module_importable() { python3 -c "import $1" 2>/dev/null; }

# ── Capability probes ──────────────────────────────────────────────────────────

# Return 0 if PyTorch Metal MPS is available on this host.
torch_mps_available() {
  python3 -c "import torch; raise SystemExit(0 if torch.backends.mps.is_available() else 1)" 2>/dev/null
}

# Print 'available' or 'unavailable (CPU only)' depending on MPS support.
torch_mps_status() {
  python3 -c "import torch; print('available' if torch.backends.mps.is_available() else 'unavailable (CPU only)')" \
    2>/dev/null || printf 'unavailable (CPU only)'
}

# Return 0 if NVIDIA CUDA is available via PyTorch.
torch_cuda_available() {
  python3 -c "import torch; raise SystemExit(0 if torch.cuda.is_available() else 1)" 2>/dev/null
}

# Print CUDA status string.
torch_cuda_status() {
  python3 -c "
import torch
if torch.cuda.is_available():
    print(f'available ({torch.cuda.get_device_name(0)})')
else:
    print('unavailable (CPU only)')
" 2>/dev/null || printf 'unavailable (no PyTorch)'
}

# Print CUDA device name or 'none'.
torch_cuda_device_name() {
  python3 -c "import torch; print(torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'none')" 2>/dev/null || printf 'none'
}

# Return 0 if the Docker daemon (inside the VM) is reachable via API.
# Probes the socket directly via curl /_ping to avoid dependency on the
# docker CLI being in PATH (unreliable on Apple Silicon where
# /usr/local/bin is not always available in sub-shells).
docker_daemon_is_running() {
  local sock="$HOME/.docker/run/docker.sock"
  if [[ -S "$sock" ]]; then
    curl -sf --unix-socket "$sock" http://localhost/_ping >/dev/null 2>&1
  else
    docker info >/dev/null 2>&1
  fi
}

# Print Docker daemon status string.
docker_daemon_status() {
  if docker_daemon_is_running; then
    printf 'running'
  else
    printf 'stopped'
  fi
}

# Return 0 if the network is reachable (can resolve + connect to a public host).
# Probe URL is configurable via UCC_NETWORK_PROBE_URL — defaults to GitHub
# because the framework already requires github.com reachability for
# pkg/github-release backends and pyenv plugins.
network_is_available() {
  local url="${UCC_NETWORK_PROBE_URL:-https://github.com}"
  curl -fsS --connect-timeout "$(_ucc_curl_timeout probe)" --max-time "$(_ucc_curl_timeout endpoint)" "$url" >/dev/null 2>&1
}

# Print network connectivity status.
network_status() {
  if network_is_available; then
    printf 'connected'
  else
    printf 'offline'
  fi
}

# Return 0 if Ollama can load at least one model (list is non-empty).
# Endpoint defaults to localhost:11434 (matches ucc/software/ai-apps.yaml's
# api_host/api_port). Override via UCC_OLLAMA_ENDPOINT env for non-default
# deployments.
ollama_model_loadable() {
  local endpoint="${UCC_OLLAMA_ENDPOINT:-http://127.0.0.1:11434}"
  local tags; tags="$(curl -fsS --max-time "$(_ucc_curl_timeout endpoint)" "${endpoint%/}/api/tags" 2>/dev/null)"
  [[ -n "$tags" ]] && echo "$tags" | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('models') else 1)" 2>/dev/null
}

# Return 0 if all running Docker Compose services are healthy or running.
docker_compose_services_healthy() {
  docker compose ps --format json 2>/dev/null | python3 -c "
import sys, json
lines = sys.stdin.read().strip()
if not lines: sys.exit(1)
for line in lines.splitlines():
    svc = json.loads(line)
    state = svc.get('State', '')
    if state not in ('running', 'healthy'): sys.exit(1)
" 2>/dev/null
}

# Return 0 if a VS Code extension is installed.
# Usage: vscode_extension_installed <extension_id>
vscode_extension_installed() { code --list-extensions 2>/dev/null | grep -qi "^${1}$"; }

# Return 0 if node is managed by nvm (resolves under $NVM_DIR or ~/.nvm).
node_via_nvm_check() {
  local np; np="$(command -v node 2>/dev/null || true)"
  [[ -n "$np" ]] && [[ "$np" == *nvm* || "$np" == *".nvm"* ]]
}

# Return 0 if no Docker Compose services are currently running.
_tic_no_running_compose_services() {
  local count; count="$(docker compose ps -q 2>/dev/null | wc -l)"
  [[ "${count:-0}" -eq 0 ]]
}

# Return 0 if the current platform is NOT macOS.
_tic_not_macos() {
  [[ "${HOST_PLATFORM:-unknown}" != "macos" ]]
}

# Return 0 if the current platform IS macOS.
_tic_is_macos() {
  [[ "${HOST_PLATFORM:-unknown}" == "macos" ]]
}

# Return 0 if elevated privileges are available (root or cached sudo ticket).
# When running inside install.sh, _UCC_SUDO_AVAILABLE is pre-set at startup
# (in the main shell with tty access) because sudo -n true inside $()
# subshells loses the tty-bound ticket on macOS.
sudo_is_available() { [[ $EUID -eq 0 ]] || [[ "${_UCC_SUDO_AVAILABLE:-}" == "1" ]] || sudo -n true 2>/dev/null; }

# Return 0 if elevated privileges are NOT available.
sudo_not_available() { ! sudo_is_available; }

# Run a command with elevated privileges (sudo when not root, direct when root).
# Uses sudo -n (non-interactive) to avoid password prompts in automated runs.
# Usage: run_elevated <cmd> [args...]
run_elevated() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo -n "$@"
  fi
}

# Return 0 if the networkQuality command exists (macOS only).
networkquality_is_available() { command -v networkQuality >/dev/null 2>&1; }

# Return 0 if an mDNS/Bonjour backend is available.
# macOS: dns-sd (built-in). Linux: avahi-publish-service. WSL2: dns-sd.exe via interop.
mdns_is_available() {
  command -v dns-sd >/dev/null 2>&1 \
    || command -v dns-sd.exe >/dev/null 2>&1 \
    || command -v avahi-publish-service >/dev/null 2>&1
}

# Return 0 if Python's stdlib venv module is usable end-to-end on this host.
# Covers seven failure modes: (1) venv module missing (Debian splits python3-venv
# into a separate apt package), (2) ensurepip missing, (3) broken _ssl/_hashlib
# (Python compiled without OpenSSL headers), (4) broken _ctypes (without libffi),
# (5-7) smoke test creating a throwaway venv and running its pip to surface
# permissions, disk space, and ensurepip-bootstrap failures.
# Cached per process to avoid paying the smoke test twice (probe + evidence).
python_venv_is_available() {
  if [[ -n "${_PYTHON_VENV_AVAIL+x}" ]]; then
    return "$_PYTHON_VENV_AVAIL"
  fi
  _python_venv_probe
  export _PYTHON_VENV_AVAIL=$?
  return "$_PYTHON_VENV_AVAIL"
}

_python_venv_probe() {
  command -v python >/dev/null 2>&1 || return 1
  python -m venv --help >/dev/null 2>&1 || return 1
  python -c 'import ensurepip, ssl, hashlib, ctypes' 2>/dev/null || return 1
  local tmp rc=0
  tmp="$(mktemp -d)" || return 1
  python -m venv "$tmp/v" >/dev/null 2>&1 || rc=1
  if [[ $rc -eq 0 ]]; then
    "$tmp/v/bin/pip" --version >/dev/null 2>&1 || rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
}

# Print human-readable status for the python-venv-available capability.
python_venv_status() {
  if python_venv_is_available; then
    printf 'healthy'
  else
    printf 'broken'
  fi
}

# Return 0 if a file exists at the given path under $HOME.
# Usage: home_file_exists <relpath>
home_file_exists() { [[ -f "$HOME/$1" ]]; }

# Return 0 if the compose template file exists.
# Uses implicit $CFG_DIR context.
ai_apps_template_exists() {
  local tpl
  tpl="$("${UCC_FRAMEWORK_PYTHON:-python3}" "$CFG_DIR/tools/read_config.py" --get "$CFG_DIR/ucc/software/ai-apps.yaml" stack.definition_template 2>/dev/null || true)"
  [[ -n "$tpl" ]] && [[ -f "$CFG_DIR/$tpl" ]]
}

# Return 0 if the Ollama process is NOT running.
_tic_ollama_not_running() {
  ! pgrep -f 'ollama' >/dev/null 2>&1
}

# Return 0 if an HTTP server is responding on localhost at the given port.
# Usage: http_probe_localhost <port>
http_probe_localhost() { curl -fsS --connect-timeout 5 "http://localhost:$1" >/dev/null 2>&1; }

# Return 0 if a pip package is installed at or above the given minimum version.
# Works standalone (no cache required); pip_group.sh overrides with cached version.
# Usage: pip_package_min_version <pkg> <min_version>
pip_package_min_version() {
  local ver; ver="$(pip show "$1" 2>/dev/null | awk '/^Version:/{print $2}')"
  [[ -n "$ver" ]] || return 1
  python3 -c "
from packaging.version import Version; import sys
raise SystemExit(0 if Version(sys.argv[1]) <= Version(sys.argv[2]) else 1)
" "$2" "$ver" 2>/dev/null
}

# Print the absolute path to a command, or empty if not found.
# Usage: bin_path <cmd>
bin_path() { command -v "$1" 2>/dev/null || true; }

# Check if a brew cask is installed (uses version cache when available)
brew_cask_is_installed() {
  if [[ -n "${_BREW_CASK_VERSIONS_CACHE+x}" ]]; then
    echo "${_BREW_CASK_VERSIONS_CACHE}" | awk -v p="$1" '$1==p{found=1} END{exit !found}'
  else
    brew list --cask "$1" &>/dev/null 2>&1
  fi
}

desktop_app_install_source() {
  local pkg="$1" app_path="$2"
  if [[ -n "$pkg" ]] && brew_cask_is_installed "$pkg"; then
    printf 'brew-cask'
  elif [[ -n "$app_path" && -d "$app_path" ]]; then
    printf 'app-bundle'
  else
    printf 'absent'
  fi
}

# Generic foreign-install handler. Reads UIC_PREF_PREFERRED_DRIVER_POLICY and
# either ignores, warns (with a hint), or invokes the supplied migrator.
#
# Non-destructive contract: a migrator MUST only remove artifacts owned by the
# foreign package manager (binaries, libs, manpages under its prefix). It MUST
# NOT touch anything under $HOME — user config, caches, data, dotfiles, app
# state — even if the foreign PM offered to. The new driver is expected to
# read the same user files transparently.
#
# Safety gate: callers declare whether the migration is "safe" (PM-only,
# reversible, no user data touched) or "destructive" (anything else). Safe
# migrations bypass the warn gate and auto-migrate on the default policy,
# because the worst case is reinstalling a binary. Destructive migrations
# require explicit policy=migrate.
#
# Usage: handle_foreign_install <display_name> <foreign_owner> <safety> <warn_hint> <migrator_fn> [migrator_args...]
#   <foreign_owner>   short tag identifying who owns the conflicting artifact
#                     (e.g. "brew", "brew-cask", "pip"); used in log messages.
#                     Empty means no conflict — returns 0 immediately.
#   <safety>          "safe" or "destructive".
#   <warn_hint>       full command suggestion shown to the user under policy=warn.
#   <migrator_fn>     function to call under policy=migrate; must return 0 on
#                     success, non-zero on failure.
#
# Returns: 0=handled/no-op, 1=migrate failed, 124=warn (caller should abort
#          install), 125=migrate needs sudo.
handle_foreign_install() {
  local display_name="$1" owner="$2" safety="$3" hint="$4" migrator="$5"
  shift 5
  [[ -z "$owner" ]] && return 0
  local policy="${UIC_PREF_PREFERRED_DRIVER_POLICY:-warn}"
  # Safe migrations skip the warn gate.
  if [[ "$safety" == "safe" && "$policy" == "warn" ]]; then
    log_info "${display_name} installed via ${owner}; auto-migrating (safe, no user data touched)."
    "$migrator" "$@" || return 1
    return 0
  fi
  case "$policy" in
    ignore)
      log_info "${display_name} installed via ${owner}; ignoring (policy=ignore)."
      return 0
      ;;
    warn)
      log_warn "${display_name} installed via ${owner}. To migrate: ${hint}"
      return 124
      ;;
    migrate)
      "$migrator" "$@" || return 1
      ;;
    *)
      log_warn "Unknown preferred-driver-policy '$policy'; treating as warn."
      return 124
      ;;
  esac
}

# Handle a cask installed outside brew-cask according to preferred-driver-policy.
# Usage: desktop_app_handle_unmanaged_cask <cask_id> <display_name>
# Returns: 0=handled/ok, 1=migrate failed, 124=warn, 125=needs sudo
desktop_app_handle_unmanaged_cask() {
  local cask_id="$1" display_name="${2:-$1}"
  local hint="brew install --cask ${cask_id} (or: ./install.sh --pref preferred-driver-policy=migrate ${cask_id})"
  if [[ "${UIC_PREF_PREFERRED_DRIVER_POLICY:-warn}" == "migrate" ]]; then
    sudo_is_available || { log_warn "Migrating ${display_name} requires admin; run: sudo -v"; return 125; }
  fi
  handle_foreign_install "$display_name" "outside brew-cask" "destructive" "$hint" \
    brew_cask_migrate_install "$cask_id"
}

# ── Config backup helper ──────────────────────────────────────────────────────
# _cfg_backup <file>
# If <file> exists and hasn't been backed up in the last hour, copies it to
# <file>.bak.<YYYYMMDD-HHMMSS>. Idempotent on hot loops; cheap when nothing
# to back up. Used by config-writer drivers before they edit a tracked file
# under $HOME (.zshrc, .zprofile, settings.json, etc.).
_cfg_backup() {
  local file="$1"
  [[ -n "$file" && -f "$file" ]] || return 0
  local recent
  recent="$(find "${file}.bak."* -newer "$file" -mmin -60 2>/dev/null | head -1)"
  [[ -n "$recent" ]] && return 0
  local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
  cp -p "$file" "${file}.bak.${stamp}" 2>/dev/null || true
}

# ── Disk cache with TTL (network check results) ───────────────────────────────
# Caches slow network-bound command output under ~/.ai-stack/cache/ with a TTL.
# Used to avoid re-running `brew livecheck`, `pip list --outdated`, etc. on
# every invocation when the answer rarely changes.
#
# UCC_CACHE_DIR defaults to ~/.ai-stack/cache
# UCC_CACHE_TTL_MIN defaults to 60 minutes
#
# Bypass the cache by setting UCC_NO_CACHE=1 (forces refresh).
#
# ── Subshell cache discipline ─────────────────────────────────────────────────
# In-memory cache vars (e.g. _BREW_VERSIONS_CACHE, _PIP_OUTDATED_CACHE,
# _NPM_GLOBAL_VERSIONS_CACHE, _PIPX_CACHE, _PKG_*_OUTDATED_CACHE) MUST be
# `export`ed (or use `declare -g`). The framework calls observe functions
# inside subshells via `observed=$($observe_fn)`. Vars set inside a subshell
# are NOT visible to the parent — so a non-exported cache populated in
# observe is invisible to the next observe and gets re-computed.
#
# This caused regression #38: pip-outdated cache populated in subshell,
# action invalidation only touched the (empty) parent var, then verify
# re-ran observe in another subshell which re-populated from disk where
# the pre-upgrade snapshot was still fresh. Fix: invalidate the disk cache
# in the action (parent shell) so the verify subshell finds it stale.
#
# Audit confirmed (2026-04-15): all session-level caches in lib/ucc_brew.sh,
# lib/drivers/{pip,pkg,package,npm,pip_bootstrap}.sh use `export` correctly.
# `_PIP_ISO_KIND`/`_PIP_ISO_NAME` in pip.sh are intentionally locals (not
# cached across calls — re-parsed each time via `_pip_parse_isolation`).

_ucc_cache_dir() {
  printf '%s' "${UCC_CACHE_DIR:-$HOME/.ai-stack/cache}"
}

_ucc_cache_path() {
  printf '%s/%s' "$(_ucc_cache_dir)" "$1"
}

# Return 0 if cache file exists and is younger than TTL (default 60 min).
_ucc_cache_fresh() {
  local path="$1"
  local ttl="${2:-${UCC_CACHE_TTL_MIN:-60}}"
  [[ "${UCC_NO_CACHE:-0}" == "1" ]] && return 1
  [[ -f "$path" ]] || return 1
  # find -mmin -N → modified within the last N minutes
  [[ -n "$(find "$path" -mmin "-$ttl" 2>/dev/null | head -1)" ]]
}

# Read cache content (caller must check freshness first).
_ucc_cache_read() {
  local path; path="$(_ucc_cache_path "$1")"
  [[ -f "$path" ]] && cat "$path"
}

# Write content (from stdin) to cache file, creating dir as needed.
_ucc_cache_write() {
  local path; path="$(_ucc_cache_path "$1")"
  mkdir -p "$(dirname "$path")" 2>/dev/null || return 1
  cat > "$path"
}

# Invalidate (delete) a cache file. Called after a state-changing action
# whose disk-cached observation would otherwise be stale (e.g. after
# `pip install --upgrade`, the cached `pip list --outdated` result is no
# longer accurate until it refreshes on next observe).
_ucc_cache_invalidate() {
  local path; path="$(_ucc_cache_path "$1")"
  rm -f "$path" 2>/dev/null || true
}

# Bulk invalidate caches matching a glob pattern. Useful for "wipe all
# upstream-check caches" or "reset everything" scenarios.
# Usage:
#   _ucc_cache_invalidate_glob 'pip-outdated-*'   # all pip outdated caches
#   _ucc_cache_invalidate_glob '*'                # nuke all caches
_ucc_cache_invalidate_glob() {
  local pattern="$1"
  local dir; dir="$(_ucc_cache_dir)"
  [[ -d "$dir" ]] || return 0
  # Use find to avoid shell-glob issues with no-match
  find "$dir" -maxdepth 1 -name "$pattern" -delete 2>/dev/null || true
}

# ── Migration safety probes ───────────────────────────────────────────────────
# Per-process cache: lines of "<owner>:<ref>\t<verdict>\t<evidence>"
_MIGRATION_SAFETY_CACHE=""

# Echoes "safe" or "destructive". Cached per (owner, ref).
# Side-effect: emits one log_info line on first assessment with the evidence.
_assess_migration_safety() {
  local owner="$1" ref="$2"
  local key="${owner}:${ref}" cached
  cached=$(printf '%s\n' "$_MIGRATION_SAFETY_CACHE" \
    | awk -F'\t' -v k="$key" '$1==k{print $2; exit}')
  if [[ -n "$cached" ]]; then
    printf '%s' "$cached"
    return
  fi
  local fn="_migration_safety_${owner//-/_}"
  local verdict evidence
  if declare -f "$fn" >/dev/null 2>&1; then
    # Probe must echo "<verdict>\t<evidence>"
    local out; out="$("$fn" "$ref")"
    verdict="${out%%	*}"
    evidence="${out#*	}"
  else
    verdict=destructive
    evidence="unknown owner"
  fi
  [[ "$verdict" != "safe" && "$verdict" != "destructive" ]] && verdict=destructive
  _MIGRATION_SAFETY_CACHE="${_MIGRATION_SAFETY_CACHE:+${_MIGRATION_SAFETY_CACHE}
}${key}	${verdict}	${evidence}"
  log_info "migration-safety: ${owner}/${ref} → ${verdict} (${evidence})"
  printf '%s' "$verdict"
}

# brew formula probe
_migration_safety_brew() {
  local ref="$1"
  local dependents services sysetc plists orphan_risk
  dependents="$(brew uses --installed --recursive "$ref" 2>/dev/null | head -1)"
  # Orphan check: would removing <ref> leave critical leaves (e.g. node) with
  # no dependents? Those are exactly what `brew autoremove` would purge.
  # Even with HOMEBREW_NO_AUTOREMOVE=1 in our migrator, we err on the side of
  # caution: if removing <ref> would orphan node/python/git/etc., classify
  # destructive so the user explicitly opts in.
  orphan_risk=""
  local crit
  for crit in node python python@3 git ruby; do
    brew list --formula "$crit" >/dev/null 2>&1 || continue
    # Is <crit> only depended on by <ref> (transitively)?
    local users
    users="$(brew uses --installed --recursive "$crit" 2>/dev/null | grep -vxF "$ref" | head -1)"
    if [[ -z "$users" ]]; then
      orphan_risk="$crit"
      break
    fi
  done
  services="$(brew services list 2>/dev/null | awk -v r="$ref" '$1==r{print; exit}')"
  local prefix; prefix="$(brew --prefix 2>/dev/null)"
  sysetc=""
  if [[ -n "$prefix" && -d "$prefix/etc/$ref" ]]; then
    [[ -n "$(ls -A "$prefix/etc/$ref" 2>/dev/null)" ]] && sysetc="$prefix/etc/$ref"
  fi
  plists=""
  if [[ -n "$prefix" ]]; then
    plists="$(grep -lr --include='*.plist' -F "$prefix/opt/$ref" \
      /Library/LaunchDaemons /Library/LaunchAgents "$HOME/Library/LaunchAgents" 2>/dev/null | head -1)"
  fi
  if [[ -z "$dependents" && -z "$services" && -z "$sysetc" && -z "$plists" && -z "$orphan_risk" ]]; then
    printf 'safe\tdependents=0 services=none system_config=none launchd=none orphans=none'
  else
    local why=""
    [[ -n "$dependents" ]]  && why+="dependents "
    [[ -n "$services" ]]    && why+="brew-services "
    [[ -n "$sysetc" ]]      && why+="system-config "
    [[ -n "$plists" ]]      && why+="launchd "
    [[ -n "$orphan_risk" ]] && why+="would-orphan=${orphan_risk} "
    printf 'destructive\t%s' "${why% }"
  fi
}

# brew cask probe — always destructive (system-wide /Applications, kexts, etc.)
_migration_safety_brew_cask() {
  printf 'destructive\t/Applications scope'
}

# unknown / curl-installed probe — never auto-migrate
_migration_safety_external() {
  printf 'destructive\tunknown footprint'
}

# Resolve effective safety: probe + per-target YAML override.
# Usage: _migration_safety_for_target <cfg_dir> <yaml> <target> <owner> <ref>
_migration_safety_for_target() {
  local cfg_dir="$1" yaml="$2" target="$3" owner="$4" ref="$5"
  local override
  override="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.migration_safety" 2>/dev/null || true)"
  if [[ -n "$override" && "$override" != "auto" ]]; then
    log_info "migration-safety: ${target} pinned to '${override}' via driver.migration_safety"
    printf '%s' "$override"
    return
  fi
  _assess_migration_safety "$owner" "$ref"
}

brew_cask_migrate_install() {
  local pkg="$1"
  ucc_run brew install --cask --force "$pkg" || return $?
  brew_refresh_caches 2>/dev/null || true
}

# Detect install source for a CLI binary: brew (formula), brew-cask, external, or absent.
# Usage: cli_install_source <binary> [brew_formula]
cli_install_source() {
  local bin="$1" formula="${2:-}"
  if ! command -v "$bin" >/dev/null 2>&1; then
    printf 'absent'
  elif [[ -n "$formula" ]] && is_installed brew && brew list "$formula" >/dev/null 2>&1; then
    printf 'brew'
  else
    printf 'external'
  fi
}

# Add a target to the per-target preferred-driver ignore list.
# Persists to ~/.ai-stack/target-overrides.yaml.
_preferred_driver_ignore_add() {
  local target="$1"
  local overrides_file="${UIC_PREF_FILE%/*}/target-overrides.yaml"
  mkdir -p "$(dirname "$overrides_file")"
  python3 -c "
import yaml, sys, os
path, target = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    with open(path) as f:
        data = yaml.safe_load(f) or {}
ignored = data.get('preferred-driver-ignore') or []
if target not in ignored:
    ignored.append(target)
    data['preferred-driver-ignore'] = ignored
    with open(path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)
" "$overrides_file" "$target" 2>/dev/null
}

# Handle a CLI tool installed outside brew.
# Per-target ignore list overrides the global preferred-driver-policy.
# In interactive mode, prompts the user inline with migrate/ignore/warn choices.
# Usage: handle_unmanaged_brew_package <formula> <display_name>
handle_unmanaged_brew_package() {
  local formula="$1" display_name="${2:-$1}"
  # Check per-target ignore list first
  if [[ -n "${UCC_PREFERRED_DRIVER_IGNORED:-}" && "${UCC_PREFERRED_DRIVER_IGNORED}" == *"|${formula}|"* ]]; then
    return 0
  fi
  # Interactive mode: prompt inline
  if [[ "${UCC_INTERACTIVE:-0}" == "1" && -c /dev/tty ]]; then
    printf '\n  [?] %s is installed outside brew, but the preferred driver is brew.\n' "$display_name"
    printf '      Options:\n'
    printf '        1) migrate — uninstall and reinstall via brew (this run only)\n'
    printf '        2) ignore  — accept the current install permanently (saved)\n'
    printf '       *3) warn    — show this warning again next run\n'
    printf '      → '
    local _choice; read -r _choice < /dev/tty
    case "$_choice" in
      1)
        sudo_is_available || { log_warn "Migrating ${display_name} requires admin; run: sudo -v"; return 125; }
        ucc_run brew install "$formula" || return 1
        return 0
        ;;
      2)
        _preferred_driver_ignore_add "$formula"
        UCC_PREFERRED_DRIVER_IGNORED="${UCC_PREFERRED_DRIVER_IGNORED}${formula}|"
        export UCC_PREFERRED_DRIVER_IGNORED
        log_info "${display_name} added to ignore list (~/.ai-stack/target-overrides.yaml)"
        return 0
        ;;
      *)
        log_warn "${display_name} installed outside brew. Will ask again next run."
        return 124
        ;;
    esac
  fi
  # Non-interactive: fall back to global policy
  local policy="${UIC_PREF_PREFERRED_DRIVER_POLICY:-warn}"
  case "$policy" in
    ignore)
      log_info "${display_name} installed outside brew; ignoring (policy=ignore)."
      return 0
      ;;
    warn)
      log_warn "${display_name} installed outside brew. To migrate: brew install ${formula} (or: ./install.sh --pref preferred-driver-policy=migrate ${formula})"
      return 124
      ;;
    migrate)
      sudo_is_available || { log_warn "Migrating ${display_name} requires admin; run: sudo -v"; return 125; }
      ucc_run brew install "$formula" || return 1
      ;;
    *)
      log_warn "Unknown preferred-driver-policy '$policy'; treating as warn."
      return 124
      ;;
  esac
}

# yaml_get_many <cfg_dir> <yaml_path> <key1> [key2 ...]
# Output NUL-delimited tab-separated key/value rows for multiple scalar lookups.
yaml_get_many() {
  local d="$1" y="$2"
  shift 2
  "${UCC_FRAMEWORK_PYTHON:-python3}" "$d/tools/read_config.py" --get-many "$y" "$@" 2>/dev/null
}

# yaml_target_get_many <cfg_dir> <yaml_path> <target> <key1> [key2 ...]
# Output NUL-delimited tab-separated key/value rows for multiple target scalar lookups.
yaml_target_get_many() {
  local d="$1" y="$2" t="$3"
  shift 3
  "${UCC_FRAMEWORK_PYTHON:-python3}" "$d/tools/read_config.py" --target-get-many "$y" "$t" "$@" 2>/dev/null
}

# yaml_list <cfg_dir> <yaml_path> <section>
# Output each item in a YAML list section, one per line.
yaml_list() { "${UCC_FRAMEWORK_PYTHON:-python3}" "$1/tools/read_config.py" --list "$2" "$3" 2>/dev/null; }

# yaml_records <cfg_dir> <yaml_path> <section> <field1> [field2 ...]
# Output tab-delimited records from a YAML list-of-dicts section.
yaml_records() { local d="$1" y="$2" s="$3"; shift 3; "${UCC_FRAMEWORK_PYTHON:-python3}" "$d/tools/read_config.py" --records "$y" "$s" "$@" 2>/dev/null; }

_ucc_endpoint_default_port() {
  case "${1:-}" in
    http) printf '80' ;;
    https) printf '443' ;;
    *) return 1 ;;
  esac
}

_UCC_ENDPOINT_CACHE_KEYS=()
_UCC_ENDPOINT_CACHE_VALUES=()
_UCC_ENDPOINT_FIELDS_VALUE=""

_ucc_tsv_field() {
  local row="$1" index="$2" i
  for ((i = 1; i < index; i++)); do
    [[ "$row" == *$'\t'* ]] || { printf ''; return 0; }
    row="${row#*$'\t'}"
  done
  if [[ "$row" == *$'\t'* ]]; then
    printf '%s' "${row%%$'\t'*}"
  else
    printf '%s' "$row"
  fi
}

_ucc_endpoint_fields() {
  local cfg_dir="$1" yaml="$2" target="$3" endpoint_name="${4:-}"
  local row="" row_name="" key="" idx
  _UCC_ENDPOINT_FIELDS_VALUE=""
  key="${cfg_dir}|${yaml}|${target}|${endpoint_name}"
  for idx in "${!_UCC_ENDPOINT_CACHE_KEYS[@]}"; do
    if [[ "${_UCC_ENDPOINT_CACHE_KEYS[$idx]}" == "$key" ]]; then
      _UCC_ENDPOINT_FIELDS_VALUE="${_UCC_ENDPOINT_CACHE_VALUES[$idx]}"
      return 0
    fi
  done
  while IFS= read -r row; do
    row_name="$(_ucc_tsv_field "$row" 1)"
    [[ -n "$row_name" ]] || continue
    if [[ -z "$endpoint_name" || "$row_name" == "$endpoint_name" ]]; then
      _UCC_ENDPOINT_CACHE_KEYS+=("$key")
      _UCC_ENDPOINT_CACHE_VALUES+=("$row")
      _UCC_ENDPOINT_FIELDS_VALUE="$row"
      return 0
    fi
  done < <(yaml_records "$cfg_dir" "$yaml" "targets.${target}.endpoints" name url scheme host port path note)
  return 1
}

# Return "scheme://host[:port]" for the named (or first) endpoint of a target.
# Derives port from scheme when the port field is empty. Returns 1 if the
# endpoint declares a full `url` instead of scheme/host/port, or has neither.
_ucc_endpoint_base_url() {
  local cfg_dir="$1" yaml="$2" target="$3" endpoint_name="${4:-}"
  local row scheme host port
  _ucc_endpoint_fields "$cfg_dir" "$yaml" "$target" "$endpoint_name" || return 1
  row="$_UCC_ENDPOINT_FIELDS_VALUE"
  scheme="$(_ucc_tsv_field "$row" 3)"
  host="$(_ucc_tsv_field "$row" 4)"
  port="$(_ucc_tsv_field "$row" 5)"
  [[ -n "$scheme" && -n "$host" ]] || return 1
  [[ -n "$port" ]] || port="$(_ucc_endpoint_default_port "$scheme" 2>/dev/null || true)"
  if [[ -n "$port" ]]; then
    printf '%s://%s:%s' "$scheme" "$host" "$port"
  else
    printf '%s://%s' "$scheme" "$host"
  fi
}

_ucc_endpoint_url() {
  local cfg_dir="$1" yaml="$2" target="$3" endpoint_name="${4:-}"
  local row url path base
  _ucc_endpoint_fields "$cfg_dir" "$yaml" "$target" "$endpoint_name" || return 1
  row="$_UCC_ENDPOINT_FIELDS_VALUE"
  url="$(_ucc_tsv_field "$row" 2)"
  if [[ -n "$url" ]]; then
    printf '%s' "$url"
    return 0
  fi
  base="$(_ucc_endpoint_base_url "$cfg_dir" "$yaml" "$target" "$endpoint_name")" || return 1
  path="$(_ucc_tsv_field "$row" 6)"
  if [[ -n "$path" ]]; then
    [[ "$path" == /* ]] || path="/$path"
  fi
  printf '%s%s' "$base" "$path"
}

# Poll <cmd ...> until it exits 0 or <timeout-s> seconds elapse. Interval
# may be fractional (sleep(1) accepts it on macOS + Linux). Returns 0 on
# success, 1 on timeout. Example:
#   _ucc_wait_until 15 0.5 pgrep -f "$process"
#   _ucc_wait_until 60 0.5 _version_changed
_ucc_wait_until() {
  local timeout="$1" interval="$2"; shift 2
  local deadline=$(( $(date +%s) + timeout ))
  while (( $(date +%s) < deadline )); do
    "$@" >/dev/null 2>&1 && return 0
    sleep "$interval"
  done
  return 1
}

# Extract the first dotted-int version substring from stdin (1-3 dots,
# i.e. N, N.N, N.N.N, or N.N.N.N). Prints the match; returns 1 if none.
# Pipe usage: `ver="$(cmd | _ucc_parse_version)"`.
_ucc_parse_version() {
  local ver
  ver="$(grep -oE '[0-9]+(\.[0-9]+){1,3}' | head -1)"
  [[ -n "$ver" ]] || return 1
  printf '%s' "$ver"
}

_ucc_http_probe_endpoint() {
  local cfg_dir="$1" yaml="$2" target="$3" endpoint_name="${4:-}"
  _ucc_http_probe_endpoint_timeout "$cfg_dir" "$yaml" "$target" "$endpoint_name" 5
}

_ucc_http_probe_endpoint_timeout() {
  local cfg_dir="$1" yaml="$2" target="$3" endpoint_name="${4:-}" max_time="${5:-5}"
  local url=""
  url="$(_ucc_endpoint_url "$cfg_dir" "$yaml" "$target" "$endpoint_name")" || return 1
  curl -fsS --max-time "$max_time" "$url" >/dev/null 2>&1
}

# ── Curl timeout categories ───────────────────────────────────────────────────
# Centralized per-category timeouts for network calls. Categories reflect
# expected response size + criticality:
#   probe       (5s)   — health probes, registry metadata (github API, pypi)
#   endpoint    (10s)  — service API responses (ollama tags)
#   metadata    (30s)  — app-bundle update API JSON (vscode, etc.)
#   download    (300s) — actual binary/dmg/zip download
#
# Override per-category via UCC_CURL_TIMEOUT_<CAT>=<seconds>:
#   UCC_CURL_TIMEOUT_PROBE=10 ./install.sh ...   # double probes
_ucc_curl_timeout() {
  local category="$1"
  case "$category" in
    probe)    printf '%s' "${UCC_CURL_TIMEOUT_PROBE:-5}" ;;
    endpoint) printf '%s' "${UCC_CURL_TIMEOUT_ENDPOINT:-10}" ;;
    metadata) printf '%s' "${UCC_CURL_TIMEOUT_METADATA:-30}" ;;
    download) printf '%s' "${UCC_CURL_TIMEOUT_DOWNLOAD:-300}" ;;
    *)        printf '5' ;;
  esac
}

# Echo a single value (use in evidence fields to expose config variables).
# Usage: echo_var <value>
echo_var() { printf '%s' "$1"; }

# Echo an absolute path under $HOME for a relative path.
# Usage: home_path <relpath>
home_path() { printf '%s' "$HOME/$1"; }

# Echo a systemd unit name with .service suffix.
# Usage: systemd_service_unit <service_name>
systemd_service_unit() { printf '%s.service' "$1"; }

# Unlink a brew formula so its binaries are not on PATH (idempotent).
brew_formula_unlink() {
  brew unlink "$1" 2>/dev/null || true
}

# Install a brew formula (package is absent)
brew_install() {
  ucc_run brew install "$@" || return $?
  brew_refresh_caches 2>/dev/null || true
}

# Upgrade a brew formula (package is present but outdated)
brew_upgrade() {
  ucc_run brew upgrade "$@" || return $?
  # Invalidate the disk-cached livecheck result — it would otherwise
  # still report the pre-upgrade "outdated" until TTL expires.
  _ucc_cache_invalidate "brew-livecheck"
  brew_refresh_caches 2>/dev/null || true
}

# Install a brew cask (cask is absent)
brew_cask_install() {
  local rc
  # NONINTERACTIVE=1 prevents brew from prompting; sudo internally uses -A/-n
  # so if a ticket is absent and the cask needs /Applications/, brew exits non-zero.
  NONINTERACTIVE=1 ucc_run brew install --cask "$@"; rc=$?
  if [[ $rc -ne 0 ]]; then
    # If no sudo ticket and brew failed, surface a clear policy message
    if sudo_not_available; then
      log_warn "Installing cask '$1' may require admin privileges; run: sudo -v and retry"
      return 125
    fi
    return $rc
  fi
  brew_refresh_caches 2>/dev/null || true
}

# Upgrade a brew cask (cask is present but outdated)
brew_cask_upgrade() {
  local pkg="$1" greedy_auto_updates="${2:-false}" rc
  if _brew_flag_true "$greedy_auto_updates"; then
    NONINTERACTIVE=1 ucc_run brew upgrade --cask --greedy-auto-updates "$pkg"; rc=$?
  else
    NONINTERACTIVE=1 ucc_run brew upgrade --cask "$pkg"; rc=$?
  fi
  if [[ $rc -ne 0 ]]; then
    if sudo_not_available; then
      log_warn "Upgrading cask '$pkg' may require admin privileges; run: sudo -v and retry"
      return 125
    fi
    return $rc
  fi
  # Invalidate the disk-cached livecheck result after a successful cask upgrade.
  _ucc_cache_invalidate "brew-livecheck"
  brew_refresh_caches 2>/dev/null || true
}
