#!/usr/bin/env bash
# lib/python.sh — pyenv + Python + pip targets
# Sourced by components/python.sh

# Usage: run_python_from_yaml <cfg_dir> <yaml_path>
run_python_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "pyenv"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "xz"

  # Load pyenv for subsequent steps
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)" 2>/dev/null || true

  # ---- Python version ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "python"

  # ---- pip up-to-date ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "pip-latest"
}
