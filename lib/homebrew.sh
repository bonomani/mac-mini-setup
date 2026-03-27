#!/usr/bin/env bash
# lib/homebrew.sh — Homebrew + Xcode CLT targets
# Sourced by components/homebrew.sh

# Usage: run_homebrew_from_yaml <cfg_dir> <yaml_path>
run_homebrew_from_yaml() {
  local cfg_dir="$1" yaml="$2"

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
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "homebrew"

  _homebrew_shellenv() {
    local shell_config
    shell_config="$(yaml_get "$cfg_dir" "$yaml" shell_config_file .zprofile)"
    [[ "${HOST_PLATFORM:-macos}" != "macos" && "$shell_config" == ".zprofile" ]] && shell_config=".profile"
    if [[ -x /opt/homebrew/bin/brew ]]; then
      if ! grep -q 'opt/homebrew/bin/brew shellenv' "$HOME/${shell_config}" 2>/dev/null; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/${shell_config}"
      fi
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      if ! grep -q 'usr/local/bin/brew shellenv' "$HOME/${shell_config}" 2>/dev/null; then
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> "$HOME/${shell_config}"
      fi
      eval "$(/usr/local/bin/brew shellenv)"
    elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
      if ! grep -q 'linuxbrew/.linuxbrew/bin/brew shellenv' "$HOME/${shell_config}" 2>/dev/null; then
        echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "$HOME/${shell_config}"
      fi
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
  }

  # Ensure brew is in PATH for the rest of this session
  is_installed brew || _homebrew_shellenv

  # ---- Disable analytics ----
  ucc_yaml_parametric_target "$cfg_dir" "$yaml" "brew-analytics=off"
}
