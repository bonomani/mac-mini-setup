#!/usr/bin/env bash
# lib/drivers/pyenv_brew.sh — driver.kind: pyenv-brew
# Installs pyenv + plugins via brew, adds shell init snippet.
# Reads pyenv_packages and zsh_config from YAML.

_ucc_driver_pyenv_brew_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  brew_observe pyenv
}

_ucc_driver_pyenv_brew_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local pkgs zsh_config
  pkgs="$(yaml_list "$cfg_dir" "$yaml" pyenv_packages 2>/dev/null | xargs)"
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in zsh_config) zsh_config="$value" ;; esac
  done < <(yaml_get_many "$cfg_dir" "$yaml" zsh_config)
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
}

_ucc_driver_pyenv_brew_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ver root
  ver="$(pyenv --version 2>/dev/null | awk '{print $2}')"
  root="$(pyenv root 2>/dev/null || true)"
  [[ -n "$ver" ]] && printf 'version=%s  root=%s' "$ver" "$root"
}
