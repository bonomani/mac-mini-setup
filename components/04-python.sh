#!/usr/bin/env bash
# Component: Python via pyenv
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — pyenv + Python version + pip present/absent)
#       Axis B = Basic
# Boundary: local filesystem · brew · network (pyenv install downloads Python source)

_PY4_CFG_DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
_PY4_CFG="$_PY4_CFG_DIR/config/04-python.yaml"

# UIC preference: python-version (safe default = 3.12.3)
PYTHON_VERSION="${UIC_PREF_PYTHON_VERSION:-3.12.3}"

# Load pyenv brew packages from config
_PYENV_PKGS=()
while IFS= read -r p; do [[ -n "$p" ]] && _PYENV_PKGS+=("$p"); done \
  < <(python3 "$_PY4_CFG_DIR/tools/read_config.py" --list "$_PY4_CFG" pyenv_packages 2>/dev/null)
[[ ${#_PYENV_PKGS[@]} -gt 0 ]] || _PYENV_PKGS=(pyenv pyenv-virtualenv)

# Load pip bootstrap packages from config
_PIP_BOOTSTRAP=()
while IFS= read -r p; do [[ -n "$p" ]] && _PIP_BOOTSTRAP+=("$p"); done \
  < <(python3 "$_PY4_CFG_DIR/tools/read_config.py" --list "$_PY4_CFG" pip_bootstrap 2>/dev/null)
[[ ${#_PIP_BOOTSTRAP[@]} -gt 0 ]] || _PIP_BOOTSTRAP=(pip setuptools wheel)

_observe_pyenv() {
  ucc_asm_package_state "$(brew_observe pyenv)"
}
_evidence_pyenv() {
  local ver path
  ver=$(pyenv --version 2>/dev/null | awk '{print $2}')
  path=$(pyenv root 2>/dev/null || true)
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
  [[ -n "$path" ]] && printf '%s root=%s' "${ver:+ }" "$path"
}
_install_pyenv() {
  brew_install "${_PYENV_PKGS[@]}"
  if ! grep -q 'pyenv init' ~/.zshrc 2>/dev/null; then
    cat "$_PY4_CFG_DIR/scripts/pyenv-zshrc-snippet" >> ~/.zshrc
  fi
}
_update_pyenv() { brew_upgrade "${_PYENV_PKGS[@]}"; }

ucc_target_nonruntime \
  --name    "pyenv" \
  --observe _observe_pyenv \
  --evidence _evidence_pyenv \
  --install _install_pyenv \
  --update  _update_pyenv

# --- xz (required to avoid lzma warning when building Python) --
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

# --- Python version -----------------------------------------
_observe_python_version() {
  local raw
  raw=$(pyenv versions 2>/dev/null | grep -q "$PYTHON_VERSION" && echo "$PYTHON_VERSION" || echo "absent")
  ucc_asm_package_state "$raw"
}
_evidence_python_version() {
  local ver path
  ver=$(python3 --version 2>/dev/null | awk '{print $2}')
  path=$(pyenv which python3 2>/dev/null || command -v python3 2>/dev/null || true)
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
  [[ -n "$path" ]] && printf '%s path=%s' "${ver:+ }" "$path"
}
_install_python_version() { pyenv install "$PYTHON_VERSION"; pyenv global "$PYTHON_VERSION"; }
_update_python_version()  { pyenv install --skip-existing "$PYTHON_VERSION"; pyenv global "$PYTHON_VERSION"; }

ucc_target_nonruntime \
  --name    "python-$PYTHON_VERSION" \
  --observe _observe_python_version \
  --evidence _evidence_python_version \
  --install _install_python_version \
  --update  _update_python_version

# --- pip up-to-date -----------------------------------------
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
_upgrade_pip() { pip install --upgrade "${_PIP_BOOTSTRAP[@]}"; }

ucc_target_nonruntime \
  --name    "pip-latest" \
  --observe _observe_pip \
  --evidence _evidence_pip \
  --install _upgrade_pip \
  --update  _upgrade_pip

ucc_summary "04-python"
