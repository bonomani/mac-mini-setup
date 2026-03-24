#!/usr/bin/env bash
# Component: Python via pyenv
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — pyenv + Python version + pip present/absent)
#       Axis B = Basic
# Boundary: local filesystem · brew · network (pyenv install downloads Python source)

DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$DIR/lib/python.sh"
run_python_from_yaml "$DIR" "$DIR/config/04-python.yaml"
ucc_summary "04-python"
