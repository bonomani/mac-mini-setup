#!/usr/bin/env bash
# Component: Git — version control
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — git present/absent + config configured/absent)
#       Axis B = Basic
# Boundary: local filesystem · brew (git binary)

_observe_git() {
  local raw
  raw=$(is_installed git && git --version 2>/dev/null | awk '{print $3}' || echo "absent")
  ucc_asm_package_state "$raw"
}

_install_git() { brew_install git; }
_update_git()  { brew_upgrade  git; }

ucc_target_nonruntime \
  --name    "git" \
  --observe _observe_git \
  --install _install_git \
  --update  _update_git

# --- Git global config (interactive, skipped in dry-run) ----
_observe_git_user() {
  local raw
  raw=$(git config --global user.name &>/dev/null && echo "configured" || echo "absent")
  ucc_asm_config_state "$raw"
}

_configure_git() {
  # OBS-1 compliance: observe is read-only; interactive input is in install only.
  # Guard: skip silently in non-interactive shells (CI, subshells without a tty).
  if [[ ! -t 0 ]]; then
    log_warn "git-global-config: non-interactive shell — skipping. Set manually:"
    log_warn "  git config --global user.name  'Your Name'"
    log_warn "  git config --global user.email 'you@example.com'"
    return 1
  fi
  read -rp "Git username: " GIT_USER
  read -rp "Git email:    " GIT_EMAIL
  git config --global user.name  "$GIT_USER"
  git config --global user.email "$GIT_EMAIL"
  git config --global init.defaultBranch main
  git config --global pull.rebase false
  git config --global core.autocrlf input
}

if [[ "$UCC_DRY_RUN" != "1" ]]; then
  ucc_target_nonruntime \
    --name    "git-global-config" \
    --observe _observe_git_user \
        --install _configure_git
fi

ucc_summary "02-git"
