#!/usr/bin/env bash
# Component: Ollama — local LLMs via Apple Metal
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — ollama binary + service running + models present)
#       Axis B = Basic
# Boundary: local filesystem · network (official installer + model pulls) · HTTP API (port 11434) · macOS launchd

_OLLAMA_CFG_DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$_OLLAMA_CFG_DIR/lib/ollama_models.sh"
source "$_OLLAMA_CFG_DIR/lib/ollama.sh"
run_ollama_from_yaml "$_OLLAMA_CFG_DIR" "$_OLLAMA_CFG_DIR/config/05-ollama.yaml" || true
ucc_summary "05-ollama"
