#!/usr/bin/env bash
# lib/homebrew.sh — Homebrew + Xcode CLT targets
# Sourced by components/homebrew.sh

# Observe Xcode CLT state: absent | outdated | <version>
xcode_clt_observe() {
  if ! xcode-select -p >/dev/null 2>&1; then
    printf 'absent'
  elif softwareupdate --list 2>/dev/null | grep -qi 'Command Line Tools for Xcode'; then
    printf 'outdated'
  else
    local ver; ver="$(xcode_clt_version)"
    printf '%s' "${ver:-present}"
  fi
}

# Observe Homebrew state: absent | <version>
homebrew_observe() {
  if is_installed brew; then
    homebrew_version
  else
    printf 'absent'
  fi
}

# Return 0 if Xcode CLT developer directory is present.
xcode_clt_is_installed() {
  xcode-select -p >/dev/null 2>&1
}

# Print the active Xcode developer directory path (empty if not installed).
xcode_clt_path() {
  xcode-select -p 2>/dev/null || true
}

# Print Xcode CLT version string from pkgutil (empty if not installed).
xcode_clt_version() {
  pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null | awk '/^version:/ {print $2}'
}

# Print Homebrew version string (empty if not installed).
homebrew_version() {
  brew --version 2>/dev/null | awk 'NR==1 {print $2}'
}

# Trigger Xcode CLT installation and exit with instructions.
_xcode_clt_trigger() {
  log_info "Triggering Xcode Command Line Tools install..."
  xcode-select --install 2>/dev/null || true
  log_warn "Xcode CLT installation triggered. Wait for it to complete, then re-run this script."
  return 1
}

# Return the softwareupdate label of the first item matching a pattern.
# Usage: softwareupdate_first_label_matching <pattern>
softwareupdate_first_label_matching() {
  local pattern="$1"
  softwareupdate --list 2>/dev/null | awk -v pat="$pattern" '
    /^\* Label: / {
      label = $0
      sub(/^\* Label: /, "", label)
      if (label ~ pat) {
        print label
        exit
      }
    }
  ' || true
}

# Return the softwareupdate label for the pending Xcode CLT update (empty if none).
xcode_clt_update_label() {
  softwareupdate_first_label_matching 'Command Line Tools for Xcode'
}

# Install the pending Xcode CLT update via softwareupdate.
xcode_clt_update() {
  local label; label="$(xcode_clt_update_label)"
  if [[ -z "$label" ]]; then
    log_warn "No Command Line Tools for Xcode update label found in softwareupdate --list."
    return 1
  fi
  if ucc_run softwareupdate --install "$label"; then
    return 0
  fi
  if sudo_is_available; then
    ucc_run sudo softwareupdate --install "$label"
    return $?
  fi
  return 1
}

# Append a brew shellenv eval line to a shell config if not already present, then eval it.
# Usage: _homebrew_shellenv_entry <brew_bin> <shell_config_relpath>
_homebrew_shellenv_entry() {
  local brew_bin="$1" sc="$HOME/$2"
  grep -q "${brew_bin} shellenv" "$sc" 2>/dev/null || \
    printf '\neval "$(%s shellenv)"\n' "$brew_bin" >> "$sc"
  eval "$("$brew_bin" shellenv)"
}

# Ensure brew shellenv is sourced and appended to shell config (idempotent).
# Usage: _homebrew_ensure_shellenv <shell_config>
_homebrew_ensure_shellenv() {
  local sc="$1"
  [[ "${HOST_PLATFORM:-macos}" != "macos" && "$sc" == ".zprofile" ]] && sc=".profile"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    _homebrew_shellenv_entry /opt/homebrew/bin/brew "$sc"
  elif [[ -x /usr/local/bin/brew ]]; then
    _homebrew_shellenv_entry /usr/local/bin/brew "$sc"
  elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    _homebrew_shellenv_entry /home/linuxbrew/.linuxbrew/bin/brew "$sc"
  fi
}

# Install Homebrew via the official installer, then configure shellenv.
# Uses implicit $CFG_DIR/$YAML_PATH context.
_homebrew_install() {
  local shell_config installer_url
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      shell_config_file) shell_config="$value" ;;
      installer_url) installer_url="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" shell_config_file installer_url)
  /bin/bash -c "$(curl -fsSL "$installer_url")"
  _homebrew_ensure_shellenv "$shell_config"
}

# Ensure shellenv is configured, then update and upgrade all formulae.
# Uses implicit $CFG_DIR/$YAML_PATH context.
_homebrew_upgrade() {
  local shell_config
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      shell_config_file) shell_config="$value" ;;
    esac
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" shell_config_file)
  _homebrew_ensure_shellenv "$shell_config"
  brew update && brew upgrade
}

# Usage: run_homebrew_from_yaml <cfg_dir> <yaml_path>
run_homebrew_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  local shell_config=".zprofile"

  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      shell_config_file) [[ -n "$value" ]] && shell_config="$value" ;;
    esac
  done < <(yaml_get_many "$cfg_dir" "$yaml" shell_config_file)

  # ---- Network connectivity check ----
  ucc_yaml_runtime_target "$cfg_dir" "$yaml" "network-available"

  # ---- Step 0: Platform-specific build prerequisites ----
  if [[ "${HOST_PLATFORM:-macos}" == "macos" ]]; then
    ucc_skip_target "build-deps" "not applicable on macOS (xcode-clt provides build tools)"
    ucc_yaml_simple_target "$cfg_dir" "$yaml" "xcode-command-line-tools"
    # Abort if CLT just got triggered
    xcode-select -p >/dev/null 2>&1 || return 1
  else
    ucc_skip_target "xcode-command-line-tools" "not applicable on ${HOST_PLATFORM:-unknown}"
    ucc_yaml_simple_target "$cfg_dir" "$yaml" "build-deps"
  fi

  # ---- Homebrew ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "homebrew"

  # Ensure brew is in PATH for the rest of this session
  is_installed brew || _homebrew_ensure_shellenv "$shell_config"

  # ---- Disable analytics ----
  ucc_yaml_parametric_target "$cfg_dir" "$yaml" "brew-analytics=off"
}
