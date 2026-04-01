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

# Ensure brew shellenv is sourced and appended to shell config (idempotent).
# Usage: _homebrew_ensure_shellenv <shell_config>
_homebrew_ensure_shellenv() {
  local sc="$1"
  [[ "${HOST_PLATFORM:-macos}" != "macos" && "$sc" == ".zprofile" ]] && sc=".profile"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    grep -q 'opt/homebrew/bin/brew shellenv' "$HOME/${sc}" 2>/dev/null || \
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/${sc}"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    grep -q 'usr/local/bin/brew shellenv' "$HOME/${sc}" 2>/dev/null || \
      echo 'eval "$(/usr/local/bin/brew shellenv)"' >> "$HOME/${sc}"
    eval "$(/usr/local/bin/brew shellenv)"
  elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    grep -q 'linuxbrew/.linuxbrew/bin/brew shellenv' "$HOME/${sc}" 2>/dev/null || \
      echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "$HOME/${sc}"
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
}

# Install Homebrew via the official installer, then configure shellenv.
# Usage: _homebrew_install <shell_config> <installer_url>
_homebrew_install() {
  /bin/bash -c "$(curl -fsSL "$2")"
  _homebrew_ensure_shellenv "$1"
}

# Ensure shellenv is configured, then update and upgrade all formulae.
# Usage: _homebrew_upgrade <shell_config>
_homebrew_upgrade() {
  _homebrew_ensure_shellenv "$1"
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

  # ---- Step 0: Xcode Command Line Tools ----
  if [[ "${HOST_PLATFORM:-macos}" == "macos" ]]; then
    ucc_yaml_simple_target "$cfg_dir" "$yaml" "xcode-command-line-tools"

    # Abort if CLT just got triggered
    xcode-select -p >/dev/null 2>&1 || return 1
  else
    ucc_skip_target "xcode-command-line-tools" "not applicable on ${HOST_PLATFORM:-unknown}"
  fi

  # ---- Homebrew ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "homebrew"

  # Ensure brew is in PATH for the rest of this session
  is_installed brew || _homebrew_ensure_shellenv "$shell_config"

  # ---- Disable analytics ----
  ucc_yaml_parametric_target "$cfg_dir" "$yaml" "brew-analytics=off"
}
