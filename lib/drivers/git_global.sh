#!/usr/bin/env bash
# lib/drivers/git_global.sh — driver.kind: git-global
# Manages git global user.name + user.email + global_config records.

_git_global_read() {
  local user email
  user="$(git config --global user.name 2>/dev/null || true)"
  email="$(git config --global user.email 2>/dev/null || true)"
  _GIT_GLOBAL_USER="$user"
  _GIT_GLOBAL_EMAIL="$email"
}

_ucc_driver_git_global_observe() {
  _git_global_read
  if [[ -n "$_GIT_GLOBAL_USER" ]]; then
    printf 'configured'
  else
    printf 'absent'
  fi
}

_ucc_driver_git_global_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  if [[ ! -t 0 ]]; then
    log_warn "git-global-config: non-interactive shell — skipping. Set manually:"
    log_warn "  git config --global user.name  'Your Name'"
    log_warn "  git config --global user.email 'you@example.com'"
    return 1
  fi
  local git_user git_email
  read -rp "Git username: " git_user
  read -rp "Git email:    " git_email
  git config --global user.name  "$git_user"
  git config --global user.email "$git_email"
  local cfg_key cfg_val
  while IFS=$'\t' read -r cfg_key cfg_val; do
    [[ -n "$cfg_key" ]] && git config --global "$cfg_key" "$cfg_val"
  done < <(yaml_records "$cfg_dir" "$yaml" global_config key value)
}

_ucc_driver_git_global_evidence() {
  _git_global_read
  [[ -n "$_GIT_GLOBAL_USER" ]] && printf 'user=%s  email=%s' "$_GIT_GLOBAL_USER" "$_GIT_GLOBAL_EMAIL"
}
