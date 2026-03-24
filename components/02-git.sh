#!/usr/bin/env bash
# Component: Git — version control
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — git present/absent + config configured/absent)
#       Axis B = Basic
# Boundary: local filesystem · brew (git binary)

DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$DIR/lib/git.sh"
run_git_from_yaml "$DIR" "$DIR/config/02-git.yaml"
ucc_summary "02-git"
