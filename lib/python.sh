#!/usr/bin/env bash
# lib/python.sh — pyenv + Python + pip targets
# Sourced by components/python.sh

# Usage: run_python_from_yaml <cfg_dir> <yaml_path>
run_python_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local _pyenv_pkgs=()
  while IFS= read -r p; do [[ -n "$p" ]] && _pyenv_pkgs+=("$p"); done \
    < <(yaml_list "$cfg_dir" "$yaml" pyenv_packages)
  [[ ${#_pyenv_pkgs[@]} -gt 0 ]] || _pyenv_pkgs=(pyenv pyenv-virtualenv)

  local python_version="${UIC_PREF_PYTHON_VERSION:-$(yaml_get "$cfg_dir" "$yaml" python_version 3.12.3)}"

  # ---- pyenv (custom install: also appends zshrc snippet) ----
  _observe_pyenv()  { ucc_asm_package_state "$(brew_observe pyenv)"; }
  _evidence_pyenv() {
    _ucc_ver_path_evidence \
      "$(pyenv --version 2>/dev/null | awk '{print $2}')" \
      "$(pyenv root 2>/dev/null || true)" \
      "root"
  }
  _install_pyenv() {
    brew_install "${_pyenv_pkgs[@]}"
    grep -q 'pyenv init' ~/.zshrc 2>/dev/null || cat "$cfg_dir/scripts/pyenv-zshrc-snippet" >> ~/.zshrc
  }
  _update_pyenv() { brew_upgrade "${_pyenv_pkgs[@]}"; }

  ucc_target_nonruntime \
    --name     "pyenv" \
    --observe  _observe_pyenv \
    --evidence _evidence_pyenv \
    --install  _install_pyenv \
    --update   _update_pyenv

  # ---- xz (lzma dependency) ----
  ucc_brew_target "xz" "xz"

  # Load pyenv for subsequent steps
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)" 2>/dev/null || true

  # ---- Python version ----
  ucc_pyenv_version_target "python" "$python_version"

  # ---- pip up-to-date ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "pip-latest"
}
