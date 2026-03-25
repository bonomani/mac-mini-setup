#!/usr/bin/env bash
# lib/git.sh — Git install + global config targets
# Sourced by components/git.sh

# Usage: run_git_from_yaml <cfg_dir> <yaml_path>
run_git_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  ucc_brew_target "git" "git"
}

# Usage: run_git_config_from_yaml <cfg_dir> <yaml_path>
run_git_config_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  [[ "$UCC_DRY_RUN" == "1" ]] && return 0

  _observe_git_user()  { ucc_asm_config_state "$(git config --global user.name &>/dev/null && echo "configured" || echo "absent")"; }
  _evidence_git_user() {
    local name email
    name=$(git config --global user.name 2>/dev/null || true)
    email=$(git config --global user.email 2>/dev/null || true)
    [[ -n "$name" ]] && printf 'user=%s' "$name"
    [[ -n "$email" ]] && printf '%s email=%s' "${name:+ }" "$email"
  }
  _configure_git() {
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
    while IFS=$'\t' read -r cfg_key cfg_val; do
      [[ -n "$cfg_key" ]] && git config --global "$cfg_key" "$cfg_val"
    done < <(yaml_records "$cfg_dir" "$yaml" global_config key value)
  }

  ucc_target_nonruntime \
    --name     "git-global-config" \
    --observe  _observe_git_user \
    --evidence _evidence_git_user \
    --install  _configure_git
}
