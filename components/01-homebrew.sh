#!/usr/bin/env bash
# Component: Homebrew — package manager
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — brew present/absent)
#       Axis B = Basic
# Boundary: local filesystem · network (brew installer + package index)
#           · macOS system (xcode-select)
# Note: "brew update" is GIC (observable side-effect, not a convergence target)

_HB_CFG_DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$_HB_CFG_DIR/lib/homebrew.sh"
run_homebrew_from_yaml "$_HB_CFG_DIR" "$_HB_CFG_DIR/config/01-homebrew.yaml" || { ucc_summary "01-homebrew"; exit 1; }
ucc_summary "01-homebrew"
