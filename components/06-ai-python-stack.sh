#!/usr/bin/env bash
# Component: AI Python Stack (PyTorch MPS + LLM frameworks)
# BGS: UCC + Basic — bash 3.2 compatible (no declare -A)
#
# BISS: Axis A = UCC (state convergence — pip packages installed + launchd service loaded)
#       Axis B = Basic
# Boundary: local filesystem · pip/PyPI (network) · macOS launchd (Unsloth Studio service)
#
# Note: jupyter-ai is intentionally absent — it pins langchain<0.4.0, incompatible with langchain>=1.0.0
# Note: the unsloth Python package cannot be imported on Apple Silicon — it raises
#       NotImplementedError at import time (NVIDIA/AMD/Intel GPUs only).
#       Unsloth Studio runs in its own isolated venv and works on Mac via the CLI.
#       Do NOT install the pip package — it is unused and untestable on this platform.

_PY_CFG_DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
_PY_CFG="$_PY_CFG_DIR/config/06-ai-python-stack.yaml"

source "$_PY_CFG_DIR/lib/pip_group.sh"
source "$_PY_CFG_DIR/lib/unsloth_studio.sh"

load_pip_groups_from_yaml "$_PY_CFG_DIR" "$_PY_CFG"
register_unsloth_studio_targets "$_PY_CFG_DIR" "$_PY_CFG"

# Verify Metal/MPS availability
if [[ "$UCC_DRY_RUN" != "1" ]] && is_installed python3; then
  _mps=$(python3 -c "import torch; print('available' if torch.backends.mps.is_available() else 'not available (CPU only)')" 2>/dev/null || true)
  [[ -n "$_mps" ]] && ucc_profile_note runtime "MPS (Metal) GPU: $_mps"
fi

ucc_summary "06-ai-python-stack"
