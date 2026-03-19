#!/usr/bin/env bash
# Component: Homebrew — package manager
# UCC + Basic

_observe_brew() {
  is_installed brew && echo "installed" || echo "absent"
}

_install_brew() {
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # PATH for Apple Silicon
  if [[ -f /opt/homebrew/bin/brew ]]; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
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

# Disable analytics (idempotent — always safe to run)
if is_installed brew; then
  ucc_run brew analytics off
fi

ucc_summary "01-homebrew"
