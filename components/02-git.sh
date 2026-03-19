#!/usr/bin/env bash
# Component: Git — version control
# UCC + Basic

_observe_git() {
  is_installed git && echo "installed" || echo "absent"
}

_install_git() {
  brew install git
}

_update_git() {
  brew upgrade git 2>/dev/null || brew install git
}

ucc_target \
  --name    "git" \
  --observe _observe_git \
  --desired "installed" \
  --install _install_git \
  --update  _update_git

# --- Git global config (interactive, skipped in dry-run) ----
_observe_git_user() {
  git config --global user.name &>/dev/null && echo "configured" || echo "absent"
}

_configure_git() {
  read -rp "Git username: " GIT_USER
  read -rp "Git email:    " GIT_EMAIL
  git config --global user.name  "$GIT_USER"
  git config --global user.email "$GIT_EMAIL"
  git config --global init.defaultBranch main
  git config --global pull.rebase false
  git config --global core.autocrlf input
}

if [[ "$UCC_DRY_RUN" != "1" ]]; then
  ucc_target \
    --name    "git-global-config" \
    --observe _observe_git_user \
    --desired "configured" \
    --install _configure_git
fi

ucc_summary "02-git"
