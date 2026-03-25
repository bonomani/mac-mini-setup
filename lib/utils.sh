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

# Pip version cache — call pip_cache_versions once before pip group targets
pip_cache_versions() {
  _PIP_VERSIONS_CACHE=$(pip list --format=json 2>/dev/null || echo '[]')
}

# Return installed version of a pip package, or empty string if absent
_pip_cached_version() {
  [[ -z "${_PIP_VERSIONS_CACHE+x}" ]] && { pip show "$1" 2>/dev/null | awk '/^Version:/{print $2}'; return; }
  python3 -c "
import sys, json
pkgs = json.load(sys.stdin)
name = sys.argv[1].lower().replace('-','_')
for p in pkgs:
    if p['name'].lower().replace('-','_') == name:
        print(p['version']); sys.exit(0)
" "$1" 2>/dev/null <<< "$_PIP_VERSIONS_CACHE"
}

# Check if a pip package is installed (uses version cache when available)
pip_is_installed() { [[ -n "$(_pip_cached_version "$1")" ]]; }

# Check if a brew formula is installed (uses version cache when available)
brew_is_installed() {
  if [[ -n "${_BREW_VERSIONS_CACHE+x}" ]]; then
    echo "${_BREW_VERSIONS_CACHE}" | awk -v p="$1" '$1==p{found=1} END{exit !found}'
  else
    brew list "$1" &>/dev/null 2>&1
  fi
}

# Check if a brew cask is installed (uses version cache when available)
brew_cask_is_installed() {
  if [[ -n "${_BREW_CASK_VERSIONS_CACHE+x}" ]]; then
    echo "${_BREW_CASK_VERSIONS_CACHE}" | awk -v p="$1" '$1==p{found=1} END{exit !found}'
  else
    brew list --cask "$1" &>/dev/null 2>&1
  fi
}

# yaml_get <cfg_dir> <yaml_path> <key> [<default>]
# Read a scalar value from a YAML config file, with optional default.
yaml_get() {
  local val
  val="$(python3 "$1/tools/read_config.py" --get "$2" "$3" 2>/dev/null)"
  echo "${val:-${4:-}}"
}

# yaml_list <cfg_dir> <yaml_path> <section>
# Output each item in a YAML list section, one per line.
yaml_list() { python3 "$1/tools/read_config.py" --list "$2" "$3" 2>/dev/null; }

# yaml_records <cfg_dir> <yaml_path> <section> <field1> [field2 ...]
# Output tab-delimited records from a YAML list-of-dicts section.
yaml_records() { local d="$1" y="$2" s="$3"; shift 3; python3 "$d/tools/read_config.py" --records "$y" "$s" "$@" 2>/dev/null; }

# Check if a Docker container is running
docker_is_running() { docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -q true; }

# Check if a Docker container exists (any state)
docker_exists() { docker inspect "$1" &>/dev/null 2>&1; }

# Check if a pip package is installed
pip_is_installed() { pip show "$1" &>/dev/null 2>&1; }

# Check if an ollama model is present
ollama_model_present() { ollama list 2>/dev/null | grep -q "^$1"; }

# Install a brew formula (package is absent)
brew_install()      { ucc_run brew install      "$@"; }

# Upgrade a brew formula (package is present but outdated)
brew_upgrade()      { ucc_run brew upgrade      "$@"; }

# Install a brew cask (cask is absent)
brew_cask_install() { ucc_run brew install --cask "$@"; }

# Upgrade a brew cask (cask is present but outdated)
brew_cask_upgrade() { ucc_run brew upgrade --cask "$@"; }
