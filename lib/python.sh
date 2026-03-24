#!/usr/bin/env bash
# lib/python.sh — pyenv + Python + pip targets
# Sourced by components/04-python.sh

# Usage: run_python_from_yaml <cfg_dir> <yaml_path>
run_python_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local _pyenv_pkgs=() _pip_bootstrap=()
  while IFS= read -r p; do [[ -n "$p" ]] && _pyenv_pkgs+=("$p"); done \
    < <(python3 "$cfg_dir/tools/read_config.py" --list "$yaml" pyenv_packages 2>/dev/null)
  [[ ${#_pyenv_pkgs[@]} -gt 0 ]] || _pyenv_pkgs=(pyenv pyenv-virtualenv)

  while IFS= read -r p; do [[ -n "$p" ]] && _pip_bootstrap+=("$p"); done \
    < <(python3 "$cfg_dir/tools/read_config.py" --list "$yaml" pip_bootstrap 2>/dev/null)
  [[ ${#_pip_bootstrap[@]} -gt 0 ]] || _pip_bootstrap=(pip setuptools wheel)

  local python_version="${UIC_PREF_PYTHON_VERSION:-3.12.3}"

  # ---- pyenv ----
  _observe_pyenv() { ucc_asm_package_state "$(brew_observe pyenv)"; }
  _evidence_pyenv() {
    local ver path
    ver=$(pyenv --version 2>/dev/null | awk '{print $2}')
    path=$(pyenv root 2>/dev/null || true)
    [[ -n "$ver" ]] && printf 'version=%s' "$ver"
    [[ -n "$path" ]] && printf '%s root=%s' "${ver:+ }" "$path"
  }
  _install_pyenv() {
    brew_install "${_pyenv_pkgs[@]}"
    if ! grep -q 'pyenv init' ~/.zshrc 2>/dev/null; then
      cat "$cfg_dir/scripts/pyenv-zshrc-snippet" >> ~/.zshrc
    fi
  }
  _update_pyenv() { brew_upgrade "${_pyenv_pkgs[@]}"; }

  ucc_target_nonruntime \
    --name    "pyenv" \
    --observe _observe_pyenv \
    --evidence _evidence_pyenv \
    --install _install_pyenv \
    --update  _update_pyenv

  # ---- xz (lzma dependency) ----
  _observe_xz() { ucc_asm_package_state "$(brew_observe xz)"; }
  _evidence_xz() {
    local ver; ver=$(xz --version 2>/dev/null | awk 'NR==1 {print $4}')
    [[ -n "$ver" ]] && printf 'version=%s' "$ver"
  }
  _install_xz() { brew_install xz; }
  _update_xz()  { brew_upgrade  xz; }

  ucc_target_nonruntime \
    --name    "xz" \
    --observe _observe_xz \
    --evidence _evidence_xz \
    --install _install_xz \
    --update  _update_xz

  # Load pyenv for subsequent steps
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)" 2>/dev/null || true

  # ---- Python version ----
  _observe_python_version() {
    local raw
    raw=$(pyenv versions 2>/dev/null | grep -q "$python_version" && echo "$python_version" || echo "absent")
    ucc_asm_package_state "$raw"
  }
  _evidence_python_version() {
    local ver path
    ver=$(python3 --version 2>/dev/null | awk '{print $2}')
    path=$(pyenv which python3 2>/dev/null || command -v python3 2>/dev/null || true)
    [[ -n "$ver" ]] && printf 'version=%s' "$ver"
    [[ -n "$path" ]] && printf '%s path=%s' "${ver:+ }" "$path"
  }
  _install_python_version() { pyenv install "$python_version"; pyenv global "$python_version"; }
  _update_python_version()  { pyenv install --skip-existing "$python_version"; pyenv global "$python_version"; }

  ucc_target_nonruntime \
    --name    "python-$python_version" \
    --observe _observe_python_version \
    --evidence _evidence_python_version \
    --install _install_python_version \
    --update  _update_python_version

  # ---- pip up-to-date ----
  _observe_pip() {
    ucc_asm_package_state "$(is_installed pip && pip --version 2>/dev/null | awk '{print $2}' || echo "absent")"
  }
  _evidence_pip() {
    local ver path
    ver=$(pip --version 2>/dev/null | awk '{print $2}')
    path=$(command -v pip 2>/dev/null || true)
    [[ -n "$ver" ]] && printf 'version=%s' "$ver"
    [[ -n "$path" ]] && printf '%s path=%s' "${ver:+ }" "$path"
  }
  _upgrade_pip() { pip install --upgrade "${_pip_bootstrap[@]}"; }

  ucc_target_nonruntime \
    --name    "pip-latest" \
    --observe _observe_pip \
    --evidence _evidence_pip \
    --install _upgrade_pip \
    --update  _upgrade_pip
}
