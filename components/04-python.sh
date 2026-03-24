#!/usr/bin/env bash
# Component: Python via pyenv
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — pyenv + Python version + pip present/absent)
#       Axis B = Basic
# Boundary: local filesystem · brew · network (pyenv install downloads Python source)

_PY4_CFG_DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$_PY4_CFG_DIR/lib/python.sh"
run_python_from_yaml "$_PY4_CFG_DIR" "$_PY4_CFG_DIR/config/04-python.yaml"
ucc_summary "04-python"
