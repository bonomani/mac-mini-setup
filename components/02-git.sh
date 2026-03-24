#!/usr/bin/env bash
# Component: Git — version control
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — git present/absent + config configured/absent)
#       Axis B = Basic
# Boundary: local filesystem · brew (git binary)

_GIT_CFG_DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$_GIT_CFG_DIR/lib/git.sh"
run_git_from_yaml "$_GIT_CFG_DIR" "$_GIT_CFG_DIR/config/02-git.yaml"
ucc_summary "02-git"
