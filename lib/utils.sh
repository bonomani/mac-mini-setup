#!/usr/bin/env bash
# Shared shell utilities (non-UCC helpers)
# Logging must go through lib/ucc.sh — do not redefine log_* here.

# Ensure brew is in PATH for every component subshell (Apple Silicon / Intel)
for _bp in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [[ -x "$_bp" ]] && ! command -v brew &>/dev/null; then
    eval "$("$_bp" shellenv)"
    break
  fi
done
unset _bp

# Ensure pyenv shims are in PATH for every component subshell
if [[ -d "$HOME/.pyenv" ]]; then
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init --path 2>/dev/null)" || true
  eval "$(pyenv init - 2>/dev/null)" || true
fi

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

# Install or upgrade a brew formula (idempotent: upgrade first, install if absent)
# Accepts multiple packages: brew_install_or_upgrade pkg1 pkg2 ...
brew_install_or_upgrade()      { ucc_run brew upgrade      "$@" 2>/dev/null || ucc_run brew install      "$@"; }

# Install or upgrade a brew cask
brew_cask_install_or_upgrade() { ucc_run brew upgrade --cask "$@" 2>/dev/null || ucc_run brew install --cask "$@"; }
