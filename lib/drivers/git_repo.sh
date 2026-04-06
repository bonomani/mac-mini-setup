#!/usr/bin/env bash
# lib/drivers/git_repo.sh — driver.kind: git-repo
# Clone a git repository and keep it up to date.
#
# driver.repo:       GitHub repo (owner/name) or full URL
# driver.dest:       destination path relative to $HOME
# driver.branch:     branch to track (default: main)

_git_repo_url() {
  local repo="$1"
  # If already a URL, use as-is
  [[ "$repo" == http* || "$repo" == git@* ]] && { printf '%s' "$repo"; return; }
  # Otherwise, assume GitHub — prefer SSH (uses user's key, no prompt)
  printf 'git@github.com:%s.git' "$repo"
}

_ucc_driver_git_repo_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local dest repo
  repo="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.repo")"
  dest="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.dest")"
  [[ -n "$repo" && -n "$dest" ]] || return 1
  local dir="$HOME/$dest"
  if [[ ! -d "$dir/.git" ]]; then
    printf 'absent'
    return
  fi
  # Check if behind remote
  local local_head remote_head
  local_head="$(git -C "$dir" rev-parse HEAD 2>/dev/null)"
  git -C "$dir" fetch --quiet 2>/dev/null || true
  local branch; branch="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.branch" 2>/dev/null)"
  branch="${branch:-main}"
  remote_head="$(git -C "$dir" rev-parse "origin/$branch" 2>/dev/null || true)"
  if [[ -n "$remote_head" && "$local_head" != "$remote_head" ]]; then
    printf 'outdated'
  else
    printf 'installed'
  fi
}

_ucc_driver_git_repo_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local repo dest branch url upstream
  repo="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.repo")"
  dest="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.dest")"
  branch="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.branch" 2>/dev/null)"
  upstream="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.upstream" 2>/dev/null)"
  branch="${branch:-main}"
  [[ -n "$repo" && -n "$dest" ]] || return 1
  url="$(_git_repo_url "$repo")"
  local dir="$HOME/$dest"
  case "$action" in
    install)
      mkdir -p "$(dirname "$dir")"
      # Prefer gh repo clone (uses gh auth, works for private repos)
      if command -v gh >/dev/null 2>&1 && [[ "$repo" != http* && "$repo" != git@* ]]; then
        ucc_run gh repo clone "$repo" "$dir" -- --branch "$branch"
      else
        ucc_run git clone --branch "$branch" "$url" "$dir"
      fi
      if [[ -n "$upstream" ]]; then
        ucc_run git -C "$dir" remote add upstream "$(_git_repo_url "$upstream")"
      fi
      ;;
    update)
      ucc_run git -C "$dir" pull --ff-only origin "$branch"
      ;;
  esac
}

_ucc_driver_git_repo_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local dest repo branch
  repo="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.repo")"
  dest="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.dest")"
  branch="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.branch" 2>/dev/null)"
  branch="${branch:-main}"
  [[ -n "$dest" ]] || return 1
  local dir="$HOME/$dest"
  [[ -d "$dir/.git" ]] || return 1
  local ver; ver="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || true)"
  printf 'commit=%s  branch=%s  path=%s' "$ver" "$branch" "$dir"
}
