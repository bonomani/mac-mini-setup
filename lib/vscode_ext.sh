#!/usr/bin/env bash
# lib/vscode_ext.sh — helper for YAML-driven VSCode extension targets
# Sourced by components/dev-tools.sh

# Populate the VSCode extensions cache (exports _VSCODE_EXTENSIONS_CACHE).
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

# Install a VSCode extension by ID and refresh the cache.
vscode_extension_install() {
  ucc_run code --install-extension "$1" --force || return $?
  vscode_extensions_cache_versions 2>/dev/null || true
}

# Update a VSCode extension (same as install for VSCode marketplace).
vscode_extension_update() {
  vscode_extension_install "$1"
}

# Return the installed version of a VSCode extension (uses cache when available).
_vscode_extension_cached_version() {
  if [[ -z "${_VSCODE_EXTENSIONS_CACHE+x}" ]]; then
    code --list-extensions --show-versions 2>/dev/null | awk -F@ 'tolower($1)==tolower("'"$1"'") {print $2; exit}'
    return
  fi
  awk -F'\t' -v q="$1" 'tolower($1)==tolower(q) {print $2; exit}' <<< "$_VSCODE_EXTENSIONS_CACHE"
}

# Runner: load all VSCode extension targets from a YAML config file.
# Usage: load_vscode_extensions_from_yaml <cfg_dir> <yaml_path>
load_vscode_extensions_from_yaml() {
  local cfg_dir="$1" yaml="$2" target=""
  vscode_extensions_cache_versions
  while IFS= read -r -u 3 target; do
    [[ -n "$target" ]] || continue
    ucc_yaml_simple_target "$cfg_dir" "$yaml" "$target"
  done 3< <(yaml_list "$cfg_dir" "$yaml" vscode_extensions)
}
