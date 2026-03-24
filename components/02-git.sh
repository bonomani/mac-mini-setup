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
_evidence_git() {
  local ver path
  ver=$(git --version 2>/dev/null | awk '{print $3}')
  path=$(command -v git 2>/dev/null || true)
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
  [[ -n "$path" ]] && printf '%s path=%s' "${ver:+ }" "$path"
}

_install_git() { brew_install git; }
_update_git()  { brew_upgrade  git; }

ucc_target_nonruntime \
  --name    "git" \
  --observe _observe_git \
  --evidence _evidence_git \
  --install _install_git \
  --update  _update_git

# --- Git global config (interactive, skipped in dry-run) ----
_observe_git_user() {
  local raw
  raw=$(git config --global user.name &>/dev/null && echo "configured" || echo "absent")
  ucc_asm_config_state "$raw"
}
_evidence_git_user() {
  local name email
  name=$(git config --global user.name 2>/dev/null || true)
  email=$(git config --global user.email 2>/dev/null || true)
  [[ -n "$name" ]] && printf 'user=%s' "$name"
  [[ -n "$email" ]] && printf '%s email=%s' "${name:+ }" "$email"
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
  # Apply non-interactive defaults from config YAML
  local _cfg_dir="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  while IFS='|' read -r cfg_key cfg_val; do
    [[ -n "$cfg_key" ]] && git config --global "$cfg_key" "$cfg_val"
  done < <(python3 "$_cfg_dir/tools/read_config.py" --records \
      "$_cfg_dir/config/02-git.yaml" global_config key value 2>/dev/null)
}

if [[ "$UCC_DRY_RUN" != "1" ]]; then
  ucc_target_nonruntime \
    --name    "git-global-config" \
    --observe _observe_git_user \
    --evidence _evidence_git_user \
        --install _configure_git
fi

ucc_summary "02-git"
