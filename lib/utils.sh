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

# Ensure pyenv shims are in PATH for every component subshell
if [[ -d "$HOME/.pyenv" ]]; then
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init --path 2>/dev/null)" || true
  eval "$(pyenv init - 2>/dev/null)" || true
fi

# Check if a command exists
is_installed() { command -v "$1" &>/dev/null; }

# Return 0 if a directory exists under $HOME at the given relative path.
# Usage: home_dir_exists <relpath>
home_dir_exists() { [[ -d "$HOME/$1" ]]; }

# Return 0 if a file exists and is executable under $HOME at the given relative path.
# Usage: home_file_is_executable <relpath>
home_file_is_executable() { [[ -x "$HOME/$1" ]]; }

# Probe the named HTTP endpoint for the current target (uses $CFG_DIR/$YAML_PATH/$TARGET_NAME).
# Intended for oracle.runtime fields — hides framework plumbing from YAML.
# Usage: http_probe_endpoint [endpoint_name]
http_probe_endpoint() {
  _ucc_http_probe_endpoint "$CFG_DIR" "$YAML_PATH" "$TARGET_NAME" "${1:-}"
}

# Return 0 if a Python module can be imported.
# Usage: python3_module_importable <module>
python3_module_importable() { python3 -c "import $1" 2>/dev/null; }

# Return 0 if an HTTP server is responding on localhost at the given port.
# Usage: http_probe_localhost <port>
http_probe_localhost() { curl -fsS --connect-timeout 5 "http://localhost:$1" >/dev/null 2>&1; }

# Print the absolute path to a command, or empty if not found.
# Usage: bin_path <cmd>
bin_path() { command -v "$1" 2>/dev/null || true; }

# Check if a brew formula is installed (uses version cache when available)
brew_is_installed() {
  if [[ -n "${_BREW_VERSIONS_CACHE+x}" ]]; then
    echo "${_BREW_VERSIONS_CACHE}" | awk -v p="$1" '$1==p{found=1} END{exit !found}'
  else
    brew list "$1" &>/dev/null 2>&1
  fi
}

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

# Handle a cask installed outside brew-cask according to preferred-driver-policy.
# Usage: desktop_app_handle_unmanaged_cask <cask_id> <display_name>
# Returns: 0=handled/ok, 1=migrate failed, 124=warn, 125=needs sudo
desktop_app_handle_unmanaged_cask() {
  local cask_id="$1" display_name="${2:-$1}"
  local policy="${UIC_PREF_PREFERRED_DRIVER_POLICY:-warn}"
  case "$policy" in
    ignore)
      log_info "${display_name} installed outside brew-cask; ignoring (policy=ignore)."
      return 0
      ;;
    warn)
      log_warn "${display_name} installed outside brew-cask; set preferred-driver-policy=migrate to adopt it."
      return 124
      ;;
    migrate)
      sudo -n true >/dev/null 2>&1 || { log_warn "Migrating ${display_name} requires admin; run: sudo -v"; return 125; }
      brew_cask_migrate_install "$cask_id" || return 1
      ;;
    *)
      log_warn "Unknown preferred-driver-policy '$policy'; treating as warn."
      return 124
      ;;
  esac
}

brew_cask_migrate_install() {
  local pkg="$1"
  ucc_run brew install --cask --force "$pkg" || return $?
  brew_refresh_caches 2>/dev/null || true
}

# yaml_get_many <cfg_dir> <yaml_path> <key1> [key2 ...]
# Output NUL-delimited tab-separated key/value rows for multiple scalar lookups.
yaml_get_many() {
  local d="$1" y="$2"
  shift 2
  python3 "$d/tools/read_config.py" --get-many "$y" "$@" 2>/dev/null
}

# yaml_target_get_many <cfg_dir> <yaml_path> <target> <key1> [key2 ...]
# Output NUL-delimited tab-separated key/value rows for multiple target scalar lookups.
yaml_target_get_many() {
  local d="$1" y="$2" t="$3"
  shift 3
  python3 "$d/tools/read_config.py" --target-get-many "$y" "$t" "$@" 2>/dev/null
}

# yaml_list <cfg_dir> <yaml_path> <section>
# Output each item in a YAML list section, one per line.
yaml_list() { python3 "$1/tools/read_config.py" --list "$2" "$3" 2>/dev/null; }

# yaml_records <cfg_dir> <yaml_path> <section> <field1> [field2 ...]
# Output tab-delimited records from a YAML list-of-dicts section.
yaml_records() { local d="$1" y="$2" s="$3"; shift 3; python3 "$d/tools/read_config.py" --records "$y" "$s" "$@" 2>/dev/null; }

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

_ucc_endpoint_url() {
  local cfg_dir="$1" yaml="$2" target="$3" endpoint_name="${4:-}"
  local row="" url="" scheme="" host="" port="" path=""
  _ucc_endpoint_fields "$cfg_dir" "$yaml" "$target" "$endpoint_name" || return 1
  row="$_UCC_ENDPOINT_FIELDS_VALUE"
  url="$(_ucc_tsv_field "$row" 2)"
  scheme="$(_ucc_tsv_field "$row" 3)"
  host="$(_ucc_tsv_field "$row" 4)"
  port="$(_ucc_tsv_field "$row" 5)"
  path="$(_ucc_tsv_field "$row" 6)"
  [[ -n "$url" ]] || {
    [[ -n "$scheme" && -n "$host" ]] || return 1
    [[ -n "$port" ]] || port="$(_ucc_endpoint_default_port "$scheme" 2>/dev/null || true)"
    url="${scheme}://${host}"
    [[ -n "$port" ]] && url="${url}:${port}"
    if [[ -n "$path" ]]; then
      [[ "$path" == /* ]] || path="/$path"
      url="${url}${path}"
    fi
  }
  printf '%s' "$url"
}

_ucc_endpoint_listener() {
  local cfg_dir="$1" yaml="$2" target="$3" endpoint_name="${4:-}"
  local row="" scheme="" host="" port=""
  _ucc_endpoint_fields "$cfg_dir" "$yaml" "$target" "$endpoint_name" || return 1
  row="$_UCC_ENDPOINT_FIELDS_VALUE"
  scheme="$(_ucc_tsv_field "$row" 3)"
  host="$(_ucc_tsv_field "$row" 4)"
  port="$(_ucc_tsv_field "$row" 5)"
  [[ -n "$host" ]] || return 1
  [[ -n "$port" ]] || port="$(_ucc_endpoint_default_port "$scheme" 2>/dev/null || true)"
  [[ -n "$port" ]] || return 1
  printf 'tcp:%s:%s' "$host" "$port"
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

# Echo a single value (use in evidence fields to expose config variables).
# Usage: echo_var <value>
echo_var() { printf '%s' "$1"; }

# Echo an absolute path under $HOME for a relative path.
# Usage: home_path <relpath>
home_path() { printf '%s' "$HOME/$1"; }

# Echo a systemd unit name with .service suffix.
# Usage: systemd_service_unit <service_name>
systemd_service_unit() { printf '%s.service' "$1"; }

# _ucc_ver_path_evidence <ver> <path> [label=path]
# Emit "version=V  label=P" evidence string (omits missing parts).
_ucc_ver_path_evidence() {
  [[ -n "$1" ]] && printf 'version=%s' "$1"
  [[ -n "$2" ]] && printf '%s%s=%s' "${1:+  }" "${3:-path}" "$2"
}

# Print the OS version string appropriate for the current platform.
# macOS: sw_vers -productVersion  Linux/WSL2: uname -r
host_os_version() {
  if [[ "${HOST_PLATFORM:-unknown}" == "macos" ]]; then
    sw_vers -productVersion 2>/dev/null || printf 'unknown'
  else
    uname -r 2>/dev/null || printf 'unknown'
  fi
}

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
    if ! sudo -n true >/dev/null 2>&1; then
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
    if ! sudo -n true >/dev/null 2>&1; then
      log_warn "Upgrading cask '$pkg' may require admin privileges; run: sudo -v and retry"
      return 125
    fi
    return $rc
  fi
  brew_refresh_caches 2>/dev/null || true
}
