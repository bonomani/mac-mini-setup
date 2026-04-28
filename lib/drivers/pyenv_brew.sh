#!/usr/bin/env bash
# lib/drivers/pyenv_brew.sh — driver.kind: pyenv-brew
# Installs pyenv + plugins. On macOS via brew; on Linux/WSL via git clone
# (upstream-recommended path; Ubuntu universe does not ship pyenv).
# Reads pyenv_packages, pyenv_git_sources, and zsh_config from YAML.

# Upstream git sources for the git-clone path. Keyed by pyenv_packages entry.
_ucc_pyenv_git_url() {
  local cfg_dir="$1" yaml="$2" pkg="$3" name url dest
  while IFS=$'\t' read -r name url dest; do
    [[ "$name" == "$pkg" ]] || continue
    printf '%s' "$url"
    return 0
  done < <(yaml_records "$cfg_dir" "$yaml" pyenv_git_sources name url dest)
  return 1
}

# Resolve clone destination under $PYENV_ROOT (main) or its plugins dir.
_ucc_pyenv_git_dest() {
  local cfg_dir="$1" yaml="$2" pkg="$3" root="${PYENV_ROOT:-$HOME/.pyenv}" name url dest
  while IFS=$'\t' read -r name url dest; do
    [[ "$name" == "$pkg" ]] || continue
    [[ -n "$dest" ]] || return 1
    if [[ "$dest" == "." ]]; then
      printf '%s' "$root"
      return 0
    fi
    printf '%s/%s' "$root" "${dest#./}"
    return 0
  done < <(yaml_records "$cfg_dir" "$yaml" pyenv_git_sources name url dest)
  return 1
}

_ucc_driver_pyenv_brew_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  if [[ "${HOST_PLATFORM:-macos}" == "macos" ]]; then
    brew_observe pyenv
    return
  fi
  local root="${PYENV_ROOT:-$HOME/.pyenv}"
  if [[ -x "$root/bin/pyenv" && -d "$root/.git" ]]; then
    local ver
    ver="$("$root/bin/pyenv" --version 2>/dev/null | awk '{print $2}')"
    printf '%s' "${ver:-installed}"
  else
    printf 'absent'
  fi
}

_ucc_driver_pyenv_brew_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local pkgs zsh_config
  pkgs="$(yaml_list "$cfg_dir" "$yaml" pyenv_packages 2>/dev/null | xargs)"
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in zsh_config) zsh_config="$value" ;; esac
  done < <(yaml_get_many "$cfg_dir" "$yaml" zsh_config)

  if [[ "${HOST_PLATFORM:-macos}" == "macos" ]]; then
    case "$action" in
      install)
        # shellcheck disable=SC2086
        [[ -n "$pkgs" ]] && brew_install $pkgs
        [[ -n "$zsh_config" ]] && grep -q 'pyenv init' "$HOME/$zsh_config" 2>/dev/null || \
          cat "$cfg_dir/scripts/pyenv-zshrc-snippet" >> "$HOME/$zsh_config"
        ;;
      update)
        # shellcheck disable=SC2086
        [[ -n "$pkgs" ]] && brew_upgrade $pkgs
        ;;
    esac
    return
  fi

  # Non-macOS: git-clone each package in pyenv_packages into PYENV_ROOT.
  command -v git >/dev/null 2>&1 || { log_error "pyenv: git required for non-macOS install"; return 1; }
  local pkg url dest
  for pkg in $pkgs; do
    url="$(_ucc_pyenv_git_url "$cfg_dir" "$yaml" "$pkg")"  || { log_warn "pyenv: unknown git source for '$pkg'"; continue; }
    dest="$(_ucc_pyenv_git_dest "$cfg_dir" "$yaml" "$pkg")" || continue
    case "$action" in
      install)
        if [[ -d "$dest/.git" ]]; then
          ucc_run git -C "$dest" fetch --quiet --tags origin || true
        else
          ucc_run mkdir -p "$(dirname "$dest")"
          ucc_run git clone --depth 1 "$url" "$dest" || return 1
        fi
        ;;
      update)
        if [[ -d "$dest/.git" ]]; then
          ucc_run git -C "$dest" pull --ff-only --quiet || return 1
        else
          ucc_run git clone --depth 1 "$url" "$dest" || return 1
        fi
        ;;
    esac
  done
}

_ucc_driver_pyenv_brew_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ver root
  root="${PYENV_ROOT:-$HOME/.pyenv}"
  if command -v pyenv >/dev/null 2>&1; then
    ver="$(pyenv --version 2>/dev/null | awk '{print $2}')"
    root="$(pyenv root 2>/dev/null || printf '%s' "$root")"
  elif [[ -x "$root/bin/pyenv" ]]; then
    ver="$("$root/bin/pyenv" --version 2>/dev/null | awk '{print $2}')"
  fi
  local backend
  case "${HOST_PLATFORM:-macos}" in
    macos) backend=brew ;;
    *)     backend=git  ;;
  esac
  printf 'backend=%s' "$backend"
  [[ -n "$ver" ]]  && printf '  version=%s' "$ver"
  [[ -n "$root" ]] && printf '  root=%s' "$root"
}
