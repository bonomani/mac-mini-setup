#!/usr/bin/env bash
# Component: Homebrew — package manager
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — brew present/absent)
#       Axis B = Basic
# Boundary: local filesystem · network (brew installer + package index)
#           · macOS system (xcode-select)
# Note: "brew update" is GIC (observable side-effect, not a convergence target)

# --- Step 0: Precondition — Xcode Command Line Tools --------
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
  return 1  # Force exit — user must re-run after CLT installs
}

ucc_target_nonruntime \
  --name    "xcode-command-line-tools" \
  --observe _observe_xcode_clt \
  --evidence _evidence_xcode_clt \
  --install _install_xcode_clt

# Abort if CLT just got triggered (install_fn returned 1)
xcode-select -p >/dev/null 2>&1 || { ucc_summary "01-homebrew"; exit 1; }

# --- Homebrew -----------------------------------------------
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

_install_brew() {
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  _setup_brew_path
}

_setup_brew_path() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    # Apple Silicon — guard against duplicate entries (idempotent)
    if ! grep -q 'opt/homebrew/bin/brew shellenv' ~/.zprofile 2>/dev/null; then
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    fi
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    # Intel Mac — guard against duplicate entries (idempotent)
    if ! grep -q 'usr/local/bin/brew shellenv' ~/.zprofile 2>/dev/null; then
      echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
    fi
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

_update_brew() {
  brew update && brew upgrade
}

ucc_target_nonruntime \
  --name    "homebrew" \
  --observe _observe_brew \
  --evidence _evidence_brew \
  --install _install_brew \
  --update  _update_brew

# Ensure brew is in PATH for the rest of this session
if ! is_installed brew; then
  _setup_brew_path
fi

# Update package index — skipped when always-upgrade (install.sh already ran brew update)
# brew update has no observable desired state — it is a GIC action, not a UCC target.
if is_installed brew && [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" != "always-upgrade" ]]; then
  log_info "Updating Homebrew package index..."
  ucc_run brew update
fi

# --- Disable analytics (observable state → ucc_target) -----
_observe_brew_analytics() {
  local raw
  raw=$(brew analytics state 2>/dev/null | grep -qi "disabled" && echo "off" || echo "on")
  ucc_asm_config_state "$raw" "off"   # parametric: desired value "off" embedded in state
}
_evidence_brew_analytics() {
  local val
  val=$(brew analytics state 2>/dev/null | grep -qi "disabled" && echo "off" || echo "on")
  printf 'analytics=%s' "$val"
}
_disable_brew_analytics() { ucc_run brew analytics off; }

if is_installed brew; then
  ucc_target_nonruntime \
    --name    "brew-analytics=off" \
    --observe _observe_brew_analytics \
    --evidence _evidence_brew_analytics \
    --desired "$(ucc_asm_config_desired "off")" \
    --install _disable_brew_analytics \
    --update  _disable_brew_analytics
fi

ucc_summary "01-homebrew"
