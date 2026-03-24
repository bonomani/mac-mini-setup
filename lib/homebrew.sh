#!/usr/bin/env bash
# lib/homebrew.sh — Homebrew + Xcode CLT targets
# Sourced by components/01-homebrew.sh

# Usage: run_homebrew_from_yaml <cfg_dir> <yaml_path>
run_homebrew_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local _hb_installer_url
  _hb_installer_url="$(yaml_get "$cfg_dir" "$yaml" installer_url "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh")"

  # ---- Step 0: Xcode Command Line Tools ----
  _observe_xcode_clt() {
    local raw
    raw=$(xcode-select -p >/dev/null 2>&1 \
      && (pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null | awk '/^version:/ {print $2}') \
      || echo "absent")
    ucc_asm_package_state "$raw"
  }
  _evidence_xcode_clt() {
    local ver path
    ver=$(pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null | awk '/^version:/ {print $2}')
    path=$(xcode-select -p 2>/dev/null || true)
    [[ -n "$ver" ]] && printf 'version=%s' "$ver"
    [[ -n "$path" ]] && printf '%s path=%s' "${ver:+ }" "$path"
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

  # ---- Homebrew ----
  _observe_brew() {
    local raw
    raw=$(is_installed brew && brew --version 2>/dev/null | awk 'NR==1 {print $2}' || echo "absent")
    ucc_asm_package_state "$raw"
  }
  _evidence_brew() {
    local ver path
    ver=$(brew --version 2>/dev/null | awk 'NR==1 {print $2}')
    path=$(command -v brew 2>/dev/null || true)
    [[ -n "$ver" ]] && printf 'version=%s' "$ver"
    [[ -n "$path" ]] && printf '%s path=%s' "${ver:+ }" "$path"
  }
  _setup_brew_path() {
    if [[ -x /opt/homebrew/bin/brew ]]; then
      if ! grep -q 'opt/homebrew/bin/brew shellenv' ~/.zprofile 2>/dev/null; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
      fi
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      if ! grep -q 'usr/local/bin/brew shellenv' ~/.zprofile 2>/dev/null; then
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
      fi
      eval "$(/usr/local/bin/brew shellenv)"
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

  # Update package index (GIC action, not a UCC target)
  if is_installed brew && [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" != "always-upgrade" ]]; then
    log_info "Updating Homebrew package index..."
    ucc_run brew update
  fi

  # ---- Disable analytics ----
  if is_installed brew; then
    local _analytics_desired
    _analytics_desired="$(yaml_get "$cfg_dir" "$yaml" analytics_desired off)"

    _observe_brew_analytics() {
      local raw
      raw=$(brew analytics state 2>/dev/null | grep -qi "disabled" && echo "off" || echo "on")
      ucc_asm_config_state "$raw" "$_analytics_desired"
    }
    _evidence_brew_analytics() {
      local val
      val=$(brew analytics state 2>/dev/null | grep -qi "disabled" && echo "off" || echo "on")
      printf 'analytics=%s' "$val"
    }
    _disable_brew_analytics() { ucc_run brew analytics off; }

    ucc_target_nonruntime \
      --name    "brew-analytics=${_analytics_desired}" \
      --observe _observe_brew_analytics \
      --evidence _evidence_brew_analytics \
      --desired "$(ucc_asm_config_desired "$_analytics_desired")" \
      --install _disable_brew_analytics \
      --update  _disable_brew_analytics
  fi
}
