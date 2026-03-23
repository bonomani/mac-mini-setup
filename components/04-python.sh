#!/usr/bin/env bash
# Component: Python via pyenv
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — pyenv + Python version + pip present/absent)
#       Axis B = Basic
# Boundary: local filesystem · brew · network (pyenv install downloads Python source)

# UIC preference: python-version (safe default = 3.12.3)
PYTHON_VERSION="${UIC_PREF_PYTHON_VERSION:-3.12.3}"

_observe_pyenv() {
  local raw
  raw=$(brew_observe pyenv)
  ucc_asm_package_state "$raw"
}
_evidence_pyenv() {
  local ver path
  ver=$(pyenv --version 2>/dev/null | awk '{print $2}')
  path=$(pyenv root 2>/dev/null || true)
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
  [[ -n "$path" ]] && printf '%s root=%s' "${ver:+ }" "$path"
}

_install_pyenv() {
  brew_install pyenv pyenv-virtualenv
  if ! grep -q 'pyenv init' ~/.zshrc 2>/dev/null; then
    cat >> ~/.zshrc <<'EOF'

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
EOF
  fi
}
_update_pyenv() { brew_upgrade pyenv pyenv-virtualenv; }

ucc_target_nonruntime \
  --name    "pyenv" \
  --observe _observe_pyenv \
  --evidence _evidence_pyenv \
  --install _install_pyenv \
  --update  _update_pyenv

# --- xz (required to avoid lzma warning when building Python) --
_observe_xz() {
  local raw
  raw=$(brew_observe xz)
  ucc_asm_package_state "$raw"
}
_evidence_xz() {
  local ver
  ver=$(xz --version 2>/dev/null | awk 'NR==1 {print $4}')
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
}
_install_xz()  { brew_install xz; }
_update_xz()   { brew_upgrade  xz; }

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

_install_python_version() {
  pyenv install "$PYTHON_VERSION"
  pyenv global "$PYTHON_VERSION"
}

_update_python_version() {
  # Reinstall if needed, keep global
  pyenv install --skip-existing "$PYTHON_VERSION"
  pyenv global "$PYTHON_VERSION"
}

ucc_target_nonruntime \
  --name    "python-$PYTHON_VERSION" \
  --observe _observe_python_version \
  --evidence _evidence_python_version \
  --install _install_python_version \
  --update  _update_python_version

# --- pip up-to-date -----------------------------------------
_observe_pip() {
  local raw
  raw=$(is_installed pip && pip --version 2>/dev/null | awk '{print $2}' || echo "absent")
  ucc_asm_package_state "$raw"
}
_evidence_pip() {
  local ver path
  ver=$(pip --version 2>/dev/null | awk '{print $2}')
  path=$(command -v pip 2>/dev/null || true)
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
  [[ -n "$path" ]] && printf '%s path=%s' "${ver:+ }" "$path"
}

_upgrade_pip() {
  pip install --upgrade pip setuptools wheel
}

ucc_target_nonruntime \
  --name    "pip-latest" \
  --observe _observe_pip \
  --evidence _evidence_pip \
  --install _upgrade_pip \
  --update  _upgrade_pip

ucc_summary "04-python"
