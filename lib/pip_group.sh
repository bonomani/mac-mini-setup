#!/usr/bin/env bash
# lib/pip_group.sh — helper for YAML-driven pip package group targets
# Sourced by components/ai-python-stack.sh

# Populate the pip package version cache (exports _PIP_VERSIONS_CACHE).
pip_cache_versions() {
  _PIP_VERSIONS_CACHE=$(pip list --format=json 2>/dev/null || echo '[]')
}

# Return the installed version of a pip package, or empty string if absent.
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

# Return 0 if a pip package is installed at or above the given minimum version.
# Overrides the standalone version in utils.sh with cached lookup.
# Usage: pip_package_min_version <pkg> <min_version>
pip_package_min_version() {
  local ver; ver="$(_pip_cached_version "$1")"
  [[ -n "$ver" ]] || return 1
  python3 -c "
from packaging.version import Version; import sys
raise SystemExit(0 if Version(sys.argv[1]) <= Version(sys.argv[2]) else 1)
" "$2" "$ver" 2>/dev/null
}

# Runner: load all pip group targets from a YAML config file.
# Usage: load_pip_groups_from_yaml <cfg_dir> <yaml_path>
load_pip_groups_from_yaml() {
  local cfg_dir="$1" yaml="$2" target=""
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    ucc_yaml_simple_target "$cfg_dir" "$yaml" "$target"
  done < <(yaml_list "$cfg_dir" "$yaml" pip_groups)
}

# Combined runner for ai-python-stack: pip groups + unsloth studio + MPS note.
# Usage: run_ai_python_stack_from_yaml <cfg_dir> <yaml_path>
run_ai_python_stack_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  pip_cache_versions
  load_pip_groups_from_yaml "$cfg_dir" "$yaml"

  # ---- Unsloth package (all platforms) ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "unsloth"

  # ---- Unsloth Studio runtime (platform-specific) ----
  case "${HOST_PLATFORM:-}" in
    macos)
      register_unsloth_studio_targets "$cfg_dir" "$yaml"
      ;;
    linux|wsl2)
      register_unsloth_studio_service_targets "$cfg_dir" "$yaml"
      ;;
  esac

  # ---- GPU capability probes ----
  if [[ "$UCC_DRY_RUN" != "1" ]] && is_installed python3; then
    case "${HOST_PLATFORM:-}" in
      macos) ucc_yaml_capability_target "$cfg_dir" "$yaml" "mps-available" ;;
    esac
    ucc_yaml_capability_target "$cfg_dir" "$yaml" "cuda-available"
  fi
}
