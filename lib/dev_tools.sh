#!/usr/bin/env bash
# lib/dev_tools.sh — Node, VSCode, CLI tools, Oh My Zsh, ariaflow targets
# Sourced by components/dev-tools.sh

# Install pyenv + plugins via brew, then append zshrc snippet if missing.
# Usage: _pyenv_install <cfg_dir> <yaml_path> <zsh_config>
_pyenv_install() {
  local cfg_dir="$1" yaml="$2" zsh_config="$3"
  local pkgs; pkgs="$(yaml_list "$cfg_dir" "$yaml" pyenv_packages 2>/dev/null | xargs)"
  # shellcheck disable=SC2086
  [[ -n "$pkgs" ]] && brew_install $pkgs
  grep -q 'pyenv init' "$HOME/$zsh_config" 2>/dev/null || \
    cat "$cfg_dir/scripts/pyenv-zshrc-snippet" >> "$HOME/$zsh_config"
}

# Upgrade pyenv + plugins via brew.
# Usage: _pyenv_upgrade <cfg_dir> <yaml_path>
_pyenv_upgrade() {
  local cfg_dir="$1" yaml="$2"
  local pkgs; pkgs="$(yaml_list "$cfg_dir" "$yaml" pyenv_packages 2>/dev/null | xargs)"
  # shellcheck disable=SC2086
  [[ -n "$pkgs" ]] && brew_upgrade $pkgs
}

# Upgrade pip bootstrap packages listed in yaml.
# Usage: _pip_bootstrap_install <cfg_dir> <yaml_path>
_pip_bootstrap_install() {
  local cfg_dir="$1" yaml="$2"
  local pkgs; pkgs="$(yaml_list "$cfg_dir" "$yaml" pip_bootstrap 2>/dev/null | xargs)"
  # shellcheck disable=SC2086
  [[ -n "$pkgs" ]] && pip install --upgrade $pkgs
}

# Create a symlink from a source binary into a target directory (idempotent).
# Adds the link directory to PATH for the current session.
# Usage: _install_cli_symlink <src_path> <link_relpath> <warn_msg>
_install_cli_symlink() {
  local src_path="$1" link_relpath="$2" warn_msg="${3:-}"
  if [[ -x "$src_path" ]]; then
    mkdir -p "$(dirname "$HOME/${link_relpath}")"
    ln -sf "$src_path" "$HOME/${link_relpath}"
    export PATH="$(dirname "$HOME/${link_relpath}"):$PATH"
    [[ -n "$warn_msg" ]] && log_warn "$warn_msg"
  else
    log_warn "Source binary not found at '${src_path}'. Install the app first."
    return 1
  fi
}

# Install Oh My Zsh via its official installer (unattended).
# Usage: _omz_install <installer_url>
_omz_install() {
  sh -c "$(curl -fsSL "$1")" "" --unattended
}

# Upgrade Oh My Zsh via its bundled upgrade script.
# Usage: _omz_upgrade <omz_dir_relpath>
_omz_upgrade() {
  local omz_dir="$HOME/$1"
  [[ -f "$omz_dir/tools/upgrade.sh" ]] && bash "$omz_dir/tools/upgrade.sh" || true
}

# Set a ZSH_THEME= line in a shell config file (update existing or append).
# Usage: _zsh_set_theme <theme> <zsh_config>
_zsh_set_theme() {
  local theme="$1" zsh_config="$HOME/$2"
  if grep -q '^ZSH_THEME=' "$zsh_config" 2>/dev/null; then
    sed -i '' "s/^ZSH_THEME=.*/ZSH_THEME=\"${theme}\"/" "$zsh_config"
  else
    printf '\nZSH_THEME="%s"\n' "$theme" >> "$zsh_config"
  fi
}

# Add a directory to PATH in a shell profile (append; idempotency enforced by oracle).
# Usage: _path_dir_add_to_profile <bin_dir> <shell_profile>
_path_dir_add_to_profile() {
  local bin_dir="$HOME/$1" shell_profile="$HOME/$2"
  mkdir -p "$bin_dir"
  printf '\nexport PATH="%s:$PATH"\n' "$bin_dir" >> "$shell_profile"
  export PATH="$bin_dir:$PATH"
}

# Install a script from cfg_dir/scripts/ into a target directory with executable permissions.
# Usage: _install_bin_script <cfg_dir> <script_name> <bin_dir>
_install_bin_script() {
  local cfg_dir="$1" script_name="$2" bin_dir="$HOME/$3"
  mkdir -p "$bin_dir"
  install -m 755 "$cfg_dir/scripts/$script_name" "$bin_dir/$script_name"
}

# Print pyenv root directory path.
pyenv_root() {
  pyenv root 2>/dev/null || true
}

# Print pyenv version string (e.g. "2.4.1").
pyenv_version() {
  pyenv --version 2>/dev/null | awk '{print $2}'
}

# Print pip version string (e.g. "24.0").
pip_version() {
  pip --version 2>/dev/null | awk '{print $2}'
}

# Print the path to the node binary, or 'none' if not installed.
node_path_or_none() {
  command -v node 2>/dev/null || printf none
}

# Return 0 if node is NOT resolved from Homebrew's opt path.
node_not_from_homebrew() {
  ! command -v node 2>/dev/null | grep -q opt/homebrew
}

# Return 0 if the given theme is active in the given zsh config.
# Usage: _zsh_theme_is_set <theme> <zsh_config>
_zsh_theme_is_set() {
  grep -q "^ZSH_THEME=\"$1\"" "$HOME/$2" 2>/dev/null
}

# Return 0 if the given bin dir is already exported in PATH in the given shell profile.
# Usage: _path_dir_in_profile <bin_dir> <shell_profile>
_path_dir_in_profile() {
  grep -q "export PATH=\"\$HOME/$1:\$PATH\"" "$HOME/$2" 2>/dev/null
}

# Populate the npm global packages cache (exports _NPM_GLOBAL_VERSIONS_CACHE).
npm_global_cache_versions() {
  export _NPM_GLOBAL_VERSIONS_CACHE
  _NPM_GLOBAL_VERSIONS_CACHE="$(
    npm ls -g --depth=0 --json 2>/dev/null | python3 -c "
import json, sys
deps = (json.load(sys.stdin) or {}).get('dependencies', {})
for name in sorted(deps):
    print(f'{name}\t{deps[name].get(\"version\", \"\")}')
" 2>/dev/null || true
  )"
}

# Install a global npm package and refresh the cache.
npm_global_install() {
  ucc_run npm install -g "$1" || return $?
  npm_global_cache_versions 2>/dev/null || true
}

# Update a global npm package and refresh the cache.
npm_global_update() {
  ucc_run npm update -g "$1" || return $?
  npm_global_cache_versions 2>/dev/null || true
}

# Return the installed version of a global npm package (uses cache when available).
npm_global_version() {
  if [[ -z "${_NPM_GLOBAL_VERSIONS_CACHE+x}" ]]; then
    npm ls -g "$1" --depth=0 --json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
deps = d.get('dependencies', {})
k = next(iter(deps), '')
if k:
    print(deps[k].get('version', ''))
" 2>/dev/null || true
    return
  fi
  awk -F'\t' -v q="$1" '$1==q {print $2; exit}' <<< "$_NPM_GLOBAL_VERSIONS_CACHE"
}

# Observe a global npm package state: <version> | absent
npm_global_observe() {
  local version; version="$(npm_global_version "$1")"
  printf '%s' "${version:-absent}"
}

# Usage: run_dev_tools_from_yaml <cfg_dir> <yaml_path>
run_dev_tools_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local _NODE_VER="24"
  local _ARIAFLOW_TAP="bonomani/ariaflow" _ARIAFLOW_FORMULA _ARIAFLOW_WEB_FORMULA
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      node_version) [[ -n "$value" ]] && _NODE_VER="$value" ;;
      ariaflow_tap) [[ -n "$value" ]] && _ARIAFLOW_TAP="$value" ;;
    esac
  done < <(yaml_get_many "$cfg_dir" "$yaml" node_version ariaflow_tap)
  _ARIAFLOW_FORMULA="${_ARIAFLOW_TAP}/ariaflow"
  _ARIAFLOW_WEB_FORMULA="${_ARIAFLOW_TAP}/ariaflow-web"
  # ---- Git ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "git"

  # ---- Python (pyenv + python version + pip) ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "pyenv"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "xz"
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)" 2>/dev/null || true
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "python"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "pip-latest"

  # ---- CLI tools (brew) ----
  local _target
  while IFS= read -r _target; do
    [[ -n "$_target" ]] && ucc_yaml_simple_target "$cfg_dir" "$yaml" "$_target"
  done < <(yaml_list "$cfg_dir" "$yaml" cli_tools)

  # ---- VSCode ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "vscode"

  # ---- code CLI symlink ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "vscode-code-cmd"

  # ---- VSCode extensions ----
  load_vscode_extensions_from_yaml "$cfg_dir" "$yaml"

  # ---- VSCode settings.json (merge, not overwrite) ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "vscode-settings"

  # ---- GUI tools (brew cask) ----
  while IFS= read -r _target; do
    [[ -n "$_target" ]] && ucc_yaml_simple_target "$cfg_dir" "$yaml" "$_target"
  done < <(yaml_list "$cfg_dir" "$yaml" casks)

  # ---- nvm + Node.js LTS ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "nvm"
  # Source nvm so node version check and npm targets see the right binary
  export NVM_DIR="$HOME/.nvm"
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" 2>/dev/null || true
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "node-lts"
  # Activate the installed version for subsequent targets
  [[ -s "$NVM_DIR/nvm.sh" ]] && nvm use "$_NODE_VER" >/dev/null 2>&1 || true

  # ---- Ensure brew's node is never on PATH (nvm owns node) ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "brew-node-unlinked"

  # ---- npm global packages ----
  npm_global_cache_versions
  while IFS= read -r _target; do
    [[ -n "$_target" ]] && ucc_yaml_simple_target "$cfg_dir" "$yaml" "$_target"
  done < <(yaml_list "$cfg_dir" "$yaml" npm_packages)

  # ---- YAML-first simple configured targets ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "oh-my-zsh"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "omz-theme-agnoster"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "home-bin-in-path"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "ai-healthcheck"

  ucc_brew_runtime_formula_target "ariaflow" "ariaflow" "$_ARIAFLOW_FORMULA" "$cfg_dir" "$yaml"
  ucc_brew_runtime_formula_target "ariaflow-web" "ariaflow-web" "$_ARIAFLOW_WEB_FORMULA" "$cfg_dir" "$yaml"
}
