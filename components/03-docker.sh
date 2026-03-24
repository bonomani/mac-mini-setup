#!/usr/bin/env bash
# Component: Docker Desktop
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — app installed/absent + resources configured)
#       Axis B = Basic
# Boundary: local filesystem · brew cask · Docker daemon API · macOS launchd

DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$DIR/lib/docker.sh"
run_docker_from_yaml "$DIR" "$DIR/config/03-docker.yaml"
ucc_summary "03-docker"
