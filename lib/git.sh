#!/usr/bin/env bash
# lib/git.sh — Git install + global config targets
# Sourced by components/git.sh

# Interactively prompt for git user.name + user.email, then apply global_config records.
# Non-interactive shells print instructions and return 1.
# Usage: _git_global_config_interactive <cfg_dir> <yaml_path>
_git_global_config_interactive() {
  local cfg_dir="$1" yaml="$2"
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

# Return 0 if git global user.name is set.
git_global_user_name_is_set() {
  git config --global user.name >/dev/null 2>&1
}

# Print git global user.name (empty if not set).
git_global_user_name() {
  git config --global user.name 2>/dev/null || true
}

# Print git global user.email (empty if not set).
git_global_user_email() {
  git config --global user.email 2>/dev/null || true
}

# Usage: run_git_from_yaml <cfg_dir> <yaml_path>
run_git_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "git"
}

# Usage: run_git_config_from_yaml <cfg_dir> <yaml_path>
run_git_config_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "git-global-config"
}
