#!/usr/bin/env bash
# lib/dev_tools.sh — Node, VSCode, CLI tools, Oh My Zsh, ariaflow targets
# Sourced by components/dev-tools.sh

# Install pyenv + plugins via brew, then append zshrc snippet if missing.
# Usage: _pyenv_install <cfg_dir> <yaml_path>
_pyenv_install() {
  local cfg_dir="$1" yaml="$2"
  local pkgs; pkgs="$(yaml_list "$cfg_dir" "$yaml" pyenv_packages 2>/dev/null | xargs)"
  [[ -n "$pkgs" ]] || pkgs="pyenv pyenv-virtualenv"
  # shellcheck disable=SC2086
  brew_install $pkgs
  grep -q 'pyenv init' "$HOME/.zshrc" 2>/dev/null || \
    cat "$cfg_dir/scripts/pyenv-zshrc-snippet" >> "$HOME/.zshrc"
}

# Upgrade pyenv + plugins via brew.
# Usage: _pyenv_upgrade <cfg_dir> <yaml_path>
_pyenv_upgrade() {
  local cfg_dir="$1" yaml="$2"
  local pkgs; pkgs="$(yaml_list "$cfg_dir" "$yaml" pyenv_packages 2>/dev/null | xargs)"
  [[ -n "$pkgs" ]] || pkgs="pyenv pyenv-virtualenv"
  # shellcheck disable=SC2086
  brew_upgrade $pkgs
}

# Upgrade pip bootstrap packages listed in yaml.
# Usage: _pip_bootstrap_install <cfg_dir> <yaml_path>
_pip_bootstrap_install() {
  local cfg_dir="$1" yaml="$2"
  local pkgs; pkgs="$(yaml_list "$cfg_dir" "$yaml" pip_bootstrap 2>/dev/null | xargs)"
  # shellcheck disable=SC2086
  [[ -n "$pkgs" ]] && pip install --upgrade $pkgs
}

# Create the ~/bin/code symlink pointing at the VS Code CLI binary.
# Usage: _vscode_code_cmd_install <cli_path> <link_relpath>
_vscode_code_cmd_install() {
  local cli_path="$1" link_relpath="$2"
  if [[ -x "$cli_path" ]]; then
    mkdir -p "$(dirname "$HOME/${link_relpath}")"
    ln -sf "$cli_path" "$HOME/${link_relpath}"
    export PATH="$(dirname "$HOME/${link_relpath}"):$PATH"
    log_warn "Symlink created. If 'code' is still missing in new shells, run: Cmd+Shift+P → 'Shell Command: Install code command in PATH'"
  else
    log_warn "VS Code binary not found. Open VS Code manually first."
    return 1
  fi
}

# Set ZSH_THEME in ~/.zshrc (update existing line or append).
# Usage: _omz_set_theme <theme>
_omz_set_theme() {
  local theme="$1"
  if grep -q '^ZSH_THEME=' "$HOME/.zshrc" 2>/dev/null; then
    sed -i '' "s/^ZSH_THEME=.*/ZSH_THEME=\"${theme}\"/" "$HOME/.zshrc"
  else
    printf '\nZSH_THEME="%s"\n' "$theme" >> "$HOME/.zshrc"
  fi
}

# Add ~/bin to PATH in ~/.zprofile (append only, idempotency enforced by oracle).
_home_bin_add_to_path() {
  mkdir -p "$HOME/bin"
  printf '\nexport PATH="$HOME/bin:$PATH"\n' >> "$HOME/.zprofile"
  export PATH="$HOME/bin:$PATH"
}

# Install a script from cfg_dir/scripts/ into ~/bin with executable permissions.
# Usage: _install_bin_script <cfg_dir> <script_name>
_install_bin_script() {
  local cfg_dir="$1" script_name="$2"
  mkdir -p "$HOME/bin"
  install -m 755 "$cfg_dir/scripts/$script_name" "$HOME/bin/$script_name"
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
