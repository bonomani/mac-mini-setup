#!/usr/bin/env bash
# Component: Python via pyenv
# BGS: UCC + Basic  (bgs/SUITE.md §4.5 + §4.3)
#
# BISS: Axis A = UCC (state convergence — pyenv + Python version + pip present/absent)
#       Axis B = Basic
# Boundary: local filesystem · brew · network (pyenv install downloads Python source)

# UIC preference: python-version (safe default = 3.12.3)
PYTHON_VERSION="${UIC_PREF_PYTHON_VERSION:-3.12.3}"

_observe_pyenv() {
  is_installed pyenv || { echo "absent"; return; }
  if [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" == "always-upgrade" ]]; then
    _brew_is_outdated pyenv && { echo "outdated"; return; }
  fi
  echo "current"
}

_install_pyenv() {
  brew_install_or_upgrade pyenv pyenv-virtualenv
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

ucc_target \
  --name    "pyenv" \
  --observe _observe_pyenv \
  --desired "current" \
  --install _install_pyenv \
  --update  _install_pyenv

# --- xz (required to avoid lzma warning when building Python) --
_observe_xz() { brew_observe xz; }
_install_xz() { brew_install_or_upgrade xz; }

ucc_target \
  --name    "xz" \
  --observe _observe_xz \
  --desired "current" \
  --install _install_xz \
  --update  _install_xz

# Load pyenv for subsequent steps
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)" 2>/dev/null || true

# --- Python version -----------------------------------------
_observe_python_version() {
  pyenv versions 2>/dev/null | grep -q "$PYTHON_VERSION" && echo "$PYTHON_VERSION" || echo "absent"
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

ucc_target \
  --name    "python-$PYTHON_VERSION" \
  --observe _observe_python_version \
  --desired "$PYTHON_VERSION" \
  --install _install_python_version \
  --update  _update_python_version

# --- pip up-to-date -----------------------------------------
_observe_pip() {
  is_installed pip && echo "present" || echo "absent"
}

_upgrade_pip() {
  pip install --upgrade pip setuptools wheel
}

ucc_target \
  --name    "pip-latest" \
  --observe _observe_pip \
  --desired "present" \
  --install _upgrade_pip \
  --update  _upgrade_pip

ucc_summary "04-python"
