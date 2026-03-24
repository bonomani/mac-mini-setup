#!/usr/bin/env bash
# Component: Dev tools (Node, VSCode, CLI tools, Oh My Zsh, healthcheck)
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — brew formulae + casks + npm globals + launchd agents)
#       Axis B = Basic
# Boundary: local filesystem · brew · npm · macOS launchd · network (package downloads)

_DT_CFG_DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$_DT_CFG_DIR/lib/vscode_ext.sh"
source "$_DT_CFG_DIR/lib/dev_tools.sh"
run_dev_tools_from_yaml "$_DT_CFG_DIR" "$_DT_CFG_DIR/config/08-dev-tools.yaml"
ucc_summary "08-dev-tools"
