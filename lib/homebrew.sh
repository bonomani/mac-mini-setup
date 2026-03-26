#!/usr/bin/env bash
# lib/homebrew.sh — Homebrew + Xcode CLT targets
# Sourced by components/homebrew.sh

# Usage: run_homebrew_from_yaml <cfg_dir> <yaml_path>
run_homebrew_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local _hb_installer_url _hb_shell_config
  _hb_installer_url="$(yaml_get "$cfg_dir" "$yaml" installer_url "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh")"
  _hb_shell_config="$(yaml_get "$cfg_dir" "$yaml" shell_config_file .zprofile)"
  [[ "${HOST_PLATFORM:-macos}" != "macos" && "$_hb_shell_config" == ".zprofile" ]] && _hb_shell_config=".profile"

  # ---- Step 0: Xcode Command Line Tools ----
  if [[ "${HOST_PLATFORM:-macos}" == "macos" ]]; then
    _observe_xcode_clt() {
      local raw
      raw=$(xcode-select -p >/dev/null 2>&1 \
        && (pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null | awk '/^version:/ {print $2}') \
        || echo "absent")
      ucc_asm_package_state "$raw"
    }
    _evidence_xcode_clt() {
      _ucc_ver_path_evidence \
        "$(pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null | awk '/^version:/ {print $2}')" \
        "$(xcode-select -p 2>/dev/null || true)"
    }
    _install_xcode_clt() {
      log_info "Triggering Xcode Command Line Tools install..."
      xcode-select --install 2>/dev/null || true
      log_warn "Xcode CLT installation triggered. Wait for it to complete, then re-run this script."
      return 1
    }

    ucc_target_nonruntime \
      --name    "xcode-command-line-tools" \
      --observe _observe_xcode_clt \
      --evidence _evidence_xcode_clt \
      --install _install_xcode_clt

    # Abort if CLT just got triggered
    xcode-select -p >/dev/null 2>&1 || return 1
  else
    ucc_skip_target "xcode-command-line-tools" "not applicable on ${HOST_PLATFORM:-unknown}"
  fi

  # ---- Homebrew ----
  _observe_brew() { ucc_asm_package_state "$(is_installed brew && brew --version 2>/dev/null | awk 'NR==1 {print $2}' || echo "absent")"; }
  _evidence_brew() {
    _ucc_ver_path_evidence \
      "$(brew --version 2>/dev/null | awk 'NR==1 {print $2}')" \
      "$(command -v brew 2>/dev/null || true)"
  }
  _setup_brew_path() {
    if [[ -x /opt/homebrew/bin/brew ]]; then
      if ! grep -q 'opt/homebrew/bin/brew shellenv' "$HOME/${_hb_shell_config}" 2>/dev/null; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/${_hb_shell_config}"
      fi
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      if ! grep -q 'usr/local/bin/brew shellenv' "$HOME/${_hb_shell_config}" 2>/dev/null; then
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> "$HOME/${_hb_shell_config}"
      fi
      eval "$(/usr/local/bin/brew shellenv)"
    elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
      if ! grep -q 'linuxbrew/.linuxbrew/bin/brew shellenv' "$HOME/${_hb_shell_config}" 2>/dev/null; then
        echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "$HOME/${_hb_shell_config}"
      fi
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
  }
  _install_brew() {
    /bin/bash -c "$(curl -fsSL "$_hb_installer_url")"
    _setup_brew_path
  }
  _update_brew() { brew update && brew upgrade; }

  ucc_target_nonruntime \
    --name    "homebrew" \
    --observe _observe_brew \
    --evidence _evidence_brew \
    --install _install_brew \
    --update  _update_brew

  # Ensure brew is in PATH for the rest of this session
  is_installed brew || _setup_brew_path

  # Refresh outdated cache after homebrew target (covers first-install and
  # the case where install.sh ran before brew was in PATH).
  if is_installed brew && [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" == "always-upgrade" ]]; then
    brew_cache_outdated 2>/dev/null || true
  fi

  # ---- Disable analytics ----
  if is_installed brew; then
    local _analytics_desired
    _analytics_desired="$(yaml_get "$cfg_dir" "$yaml" analytics_desired off)"

    eval "_obs_ba()  { ucc_asm_config_state \"\$(brew analytics state 2>/dev/null | grep -qi disabled && echo off || echo on)\" '${_analytics_desired}'; }"
    eval "_evd_ba()  { printf 'analytics=%s' \"\$(brew analytics state 2>/dev/null | grep -qi disabled && echo off || echo on)\"; }"
    eval "_fix_ba()  { ucc_run brew analytics off; }"

    ucc_target \
      --name    "brew-analytics=${_analytics_desired}" \
      --profile  parametric \
      --observe  _obs_ba \
      --evidence _evd_ba \
      --desired  "$(ucc_asm_config_desired "$_analytics_desired")" \
      --install  _fix_ba \
      --update   _fix_ba
  fi
}
