#!/usr/bin/env bash
# Shared shell utilities (non-UCC helpers)
# Logging must go through lib/ucc.sh — do not redefine log_* here.

# Ensure brew is in PATH for every component subshell (Apple Silicon / Intel)
for _bp in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
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

vscode_extensions_cache_versions() {
  export _VSCODE_EXTENSIONS_CACHE
  _VSCODE_EXTENSIONS_CACHE="$(
    code --list-extensions --show-versions 2>/dev/null | awk -F@ '
      NF {
        ext = tolower($1)
        ver = (NF > 1 ? $2 : "")
        printf "%s\t%s\n", ext, ver
      }
    ' || true
  )"
}

vscode_extension_install() {
  ucc_run code --install-extension "$1" --force || return $?
  vscode_extensions_cache_versions 2>/dev/null || true
}

vscode_extension_update() {
  vscode_extension_install "$1"
}

_vscode_extension_cached_version() {
  if [[ -z "${_VSCODE_EXTENSIONS_CACHE+x}" ]]; then
    code --list-extensions --show-versions 2>/dev/null | awk -F@ 'tolower($1)==tolower("'"$1"'") {print $2; exit}'
    return
  fi
  awk -F'\t' -v q="$1" 'tolower($1)==tolower(q) {print $2; exit}' <<< "$_VSCODE_EXTENSIONS_CACHE"
}

ollama_model_cache_list() {
  export _OLLAMA_MODELS_CACHE
  _OLLAMA_MODELS_CACHE="$(ollama list 2>/dev/null | awk 'NR>1 {print $1}' || true)"
}

npm_global_cache_versions() {
  export _NPM_GLOBAL_VERSIONS_CACHE
  _NPM_GLOBAL_VERSIONS_CACHE="$(
    npm ls -g --depth=0 --json 2>/dev/null | python3 -c "
import json, sys
deps = (json.load(sys.stdin) or {}).get('dependencies', {})
for name in sorted(deps):
    print(f'{name}\t{deps[name].get(\"version\", \"\")}')
" 2>/dev/null || true
  )"
}

npm_global_install() {
  ucc_run npm install -g "$1" || return $?
  npm_global_cache_versions 2>/dev/null || true
}

npm_global_update() {
  ucc_run npm update -g "$1" || return $?
  npm_global_cache_versions 2>/dev/null || true
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

# yaml_get_many <cfg_dir> <yaml_path> <key1> [key2 ...]
# Output NUL-delimited tab-separated key/value rows for multiple scalar lookups.
yaml_get_many() {
  local d="$1" y="$2"
  shift 2
  python3 "$d/tools/read_config.py" --get-many "$y" "$@" 2>/dev/null
}

# yaml_target_get_many <cfg_dir> <yaml_path> <target> <key1> [key2 ...]
# Output NUL-delimited tab-separated key/value rows for multiple target scalar lookups.
yaml_target_get_many() {
  local d="$1" y="$2" t="$3"
  shift 3
  python3 "$d/tools/read_config.py" --target-get-many "$y" "$t" "$@" 2>/dev/null
}

# yaml_list <cfg_dir> <yaml_path> <section>
# Output each item in a YAML list section, one per line.
yaml_list() { python3 "$1/tools/read_config.py" --list "$2" "$3" 2>/dev/null; }

# yaml_records <cfg_dir> <yaml_path> <section> <field1> [field2 ...]
# Output tab-delimited records from a YAML list-of-dicts section.
yaml_records() { local d="$1" y="$2" s="$3"; shift 3; python3 "$d/tools/read_config.py" --records "$y" "$s" "$@" 2>/dev/null; }

# _ucc_ver_path_evidence <ver> <path> [label=path]
# Emit "version=V  label=P" evidence string (omits missing parts).
_ucc_ver_path_evidence() {
  [[ -n "$1" ]] && printf 'version=%s' "$1"
  [[ -n "$2" ]] && printf '%s%s=%s' "${1:+  }" "${3:-path}" "$2"
}

# Check if an ollama model is present
ollama_model_present() {
  if [[ -n "${_OLLAMA_MODELS_CACHE+x}" ]]; then
    grep -Fxq "$1" <<< "$_OLLAMA_MODELS_CACHE"
  else
    ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -Fxq "$1"
  fi
}

softwareupdate_first_label_matching() {
  local pattern="$1"
  softwareupdate --list 2>/dev/null | awk -v pat="$pattern" '
    /^\* Label: / {
      label = $0
      sub(/^\* Label: /, "", label)
      if (label ~ pat) {
        print label
        exit
      }
    }
  ' || true
}

xcode_clt_update_label() {
  softwareupdate_first_label_matching 'Command Line Tools for Xcode'
}

xcode_clt_update() {
  local label
  label="$(xcode_clt_update_label)"
  if [[ -z "$label" ]]; then
    log_warn "No Command Line Tools for Xcode update label found in softwareupdate --list."
    return 1
  fi
  ucc_run sudo softwareupdate --install "$label"
}

ollama_model_pull() {
  log_info "Pulling model: $1"
  ucc_run ollama pull "$1" || return $?
  ollama_model_cache_list 2>/dev/null || true
}

# Return installed version of a global npm package, or empty string if absent.
npm_global_version() {
  if [[ -z "${_NPM_GLOBAL_VERSIONS_CACHE+x}" ]]; then
    npm ls -g "$1" --depth=0 --json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
deps = d.get('dependencies', {})
k = next(iter(deps), '')
if k:
    print(deps[k].get('version', ''))
" 2>/dev/null || true
    return
  fi
  awk -F'\t' -v q="$1" '$1==q {print $2; exit}' <<< "$_NPM_GLOBAL_VERSIONS_CACHE"
}

# Observe a global npm package as an ASM package raw state.
npm_global_observe() {
  local version
  version="$(npm_global_version "$1")"
  printf '%s' "${version:-absent}"
}

# Install a brew formula (package is absent)
brew_install() {
  ucc_run brew install "$@" || return $?
  brew_refresh_caches 2>/dev/null || true
}

# Upgrade a brew formula (package is present but outdated)
brew_upgrade() {
  ucc_run brew upgrade "$@" || return $?
  brew_refresh_caches 2>/dev/null || true
}

# Install a brew cask (cask is absent)
brew_cask_install() {
  ucc_run brew install --cask "$@" || return $?
  brew_refresh_caches 2>/dev/null || true
}

# Upgrade a brew cask (cask is present but outdated)
brew_cask_upgrade() {
  local pkg="$1" greedy_auto_updates="${2:-false}"
  if _brew_flag_true "$greedy_auto_updates"; then
    ucc_run brew upgrade --cask --greedy-auto-updates "$pkg" || return $?
  else
    ucc_run brew upgrade --cask "$pkg" || return $?
  fi
  brew_refresh_caches 2>/dev/null || true
}
