#!/usr/bin/env bash
# Component: Homebrew — package manager
# UCC + Basic

# --- Step 0: Precondition — Xcode Command Line Tools --------
_observe_xcode_clt() {
  xcode-select -p >/dev/null 2>&1 && echo "installed" || echo "absent"
}

_install_xcode_clt() {
  log_info "Triggering Xcode Command Line Tools install..."
  xcode-select --install 2>/dev/null || true
  log_warn "Xcode CLT installation triggered. Wait for it to complete, then re-run this script."
  return 1  # Force exit — user must re-run after CLT installs
}

ucc_target \
  --name    "xcode-command-line-tools" \
  --observe _observe_xcode_clt \
  --desired "installed" \
  --install _install_xcode_clt

# Abort if CLT just got triggered (install_fn returned 1)
xcode-select -p >/dev/null 2>&1 || { ucc_summary "01-homebrew"; exit 1; }

# --- Homebrew -----------------------------------------------
_observe_brew() {
  is_installed brew && echo "installed" || echo "absent"
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

ucc_target \
  --name    "homebrew" \
  --observe _observe_brew \
  --desired "installed" \
  --install _install_brew \
  --update  _update_brew

# Ensure brew is in PATH for the rest of this session
if ! is_installed brew; then
  _setup_brew_path
fi

# Always update package index after install (not upgrade)
# brew update has no observable desired state to diff — it is a GIC action,
# not a UCC convergence target. We log and run it unconditionally.
if is_installed brew && [[ "$UCC_MODE" == "install" ]]; then
  log_info "Updating Homebrew package index..."
  ucc_run brew update
fi

# --- Disable analytics (observable state → ucc_target) -----
_observe_brew_analytics() {
  brew analytics state 2>/dev/null | grep -qi "disabled" && echo "off" || echo "on"
}
_disable_brew_analytics() { ucc_run brew analytics off; }

if is_installed brew; then
  ucc_target \
    --name    "brew-analytics=off" \
    --observe _observe_brew_analytics \
    --desired "off" \
    --install _disable_brew_analytics \
    --update  _disable_brew_analytics
fi

ucc_summary "01-homebrew"
