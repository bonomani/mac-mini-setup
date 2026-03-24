#!/usr/bin/env bash
# Component: AI Applications via Docker Compose
# BGS: UCC + Basic — bash 3.2 compatible (no declare -A)
#
# BISS: Axis A = UCC (state convergence — compose file present + containers running)
#       Axis B = Basic
# Boundary: local filesystem · Docker daemon API · network (image pulls)

_AI_CFG_DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$_AI_CFG_DIR/lib/ai_apps.sh"
run_ai_apps_from_yaml "$_AI_CFG_DIR" "$_AI_CFG_DIR/config/07-ai-apps.yaml" || true
ucc_summary "07-ai-apps"
