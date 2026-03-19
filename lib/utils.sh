#!/usr/bin/env bash
# Shared shell utilities (non-UCC helpers)
# Logging must go through lib/ucc.sh — do not redefine log_* here.

# Check if a command exists
is_installed() { command -v "$1" &>/dev/null; }

# Check if a brew formula is installed
brew_is_installed() { brew list "$1" &>/dev/null 2>&1; }

# Check if a brew cask is installed
brew_cask_is_installed() { brew list --cask "$1" &>/dev/null 2>&1; }

# Check if a Docker container is running
docker_is_running() { docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -q true; }

# Check if a Docker container exists (any state)
docker_exists() { docker inspect "$1" &>/dev/null 2>&1; }

# Check if a pip package is installed
pip_is_installed() { pip show "$1" &>/dev/null 2>&1; }

# Check if an ollama model is present
ollama_model_present() { ollama list 2>/dev/null | grep -q "^$1"; }
