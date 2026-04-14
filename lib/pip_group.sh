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

# List unique venv names used by pip targets in this YAML.
_pip_list_venv_names() {
  local cfg_dir="$1" yaml="$2"
  python3 -c "
import yaml, sys
data = yaml.safe_load(open('$yaml')) or {}
seen = set()
for t in (data.get('targets') or {}).values():
    if not isinstance(t, dict): continue
    iso = (t.get('driver') or {}).get('isolation')
    if isinstance(iso, dict) and iso.get('kind') == 'venv':
        name = iso.get('name', '')
        if name and name not in seen:
            seen.add(name)
            print(name)
" 2>/dev/null || true
}

# ── pip-global-policy enforcement ─────────────────────────────────────────────
# Run after all venv installs. Checks global pip for packages with conflicting
# upper-version constraints. Actions depend on UIC_PREF_PIP_GLOBAL_POLICY:
#   permissive — do nothing
#   strict     — warn on conflicting packages
#   migrate    — auto-remove conflicting packages from global if they exist
#                in a venv or are orphaned transitive deps
_pip_global_policy_enforce() {
  local cfg_dir="$1" yaml="$2"
  local policy="${UIC_PREF_PIP_GLOBAL_POLICY:-permissive}"
  [[ "$policy" == "permissive" ]] && return 0

  _pip_ensure_path || return 0
  local pip_cmd="pip"
  command -v pip >/dev/null 2>&1 || pip_cmd="python3 -m pip"

  # Run pip check and parse conflict sources.
  # pip check output format:
  #   <pkg> <ver> requires <dep><constraint>, which is not installed.
  #   <pkg> <ver> has requirement <dep><constraint>, but you have <dep> <ver>.
  local check_output
  check_output="$($pip_cmd check 2>/dev/null || true)"
  [[ -n "$check_output" ]] || return 0

  # Extract package names that impose conflicting constraints.
  # These are the first word on each line of pip check output.
  local conflict_pkgs
  conflict_pkgs="$(printf '%s\n' "$check_output" \
    | awk '{print tolower($1)}' | sort -u)"
  [[ -n "$conflict_pkgs" ]] || return 0

  # Collect venv package names for "exists in a venv" check.
  local venv_pkgs=""
  local _vn
  for _vn in $(_pip_list_venv_names "$cfg_dir" "$yaml"); do
    _pip_venv_available "$_vn" || continue
    local _vp
    _vp="$("$(_pip_venv_pip_cmd "$_vn")" list --format=json 2>/dev/null \
      | python3 -c "
import sys, json
for p in json.load(sys.stdin):
    print(p['name'].lower().replace('-','_'))
" 2>/dev/null || true)"
    venv_pkgs="${venv_pkgs}${_vp}"$'\n'
  done

  local pkg in_venv
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue
    local norm="${pkg//-/_}"
    # Check if package exists in any venv
    in_venv=0
    printf '%s\n' "$venv_pkgs" | grep -qx "$norm" && in_venv=1

    case "$policy" in
      strict)
        if [[ "$in_venv" == "1" ]]; then
          log_warn "pip-global-policy: '$pkg' conflicts in global pip and exists in a venv — run: pip uninstall -y $pkg"
        else
          log_warn "pip-global-policy: '$pkg' conflicts in global pip — consider: pip uninstall -y $pkg"
        fi
        ;;
      migrate)
        if [[ "$in_venv" == "1" ]]; then
          log_info "pip-global-policy: removing '$pkg' from global pip (exists in venv)"
          $pip_cmd uninstall -y "$pkg" 2>/dev/null || true
        else
          # Orphaned transitive dep: try to uninstall; pip refuses if something
          # in global still depends on it.
          log_info "pip-global-policy: removing orphaned '$pkg' from global pip"
          $pip_cmd uninstall -y "$pkg" 2>/dev/null || \
            log_warn "pip-global-policy: cannot remove '$pkg' — still required by another global package"
        fi
        ;;
    esac
  done <<< "$conflict_pkgs"
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

  # ---- Python lifecycle (pyenv → python → pip) ----
  # Ordering is enforced by YAML depends_on: pyenv→homebrew, python→[xz,pyenv],
  # pip-latest→python. The pkg driver's pyenv backend self-activates pyenv
  # (adds $PYENV_ROOT/bin and shims to PATH, runs `pyenv init -`) on observe;
  # exports persist to subsequent calls in this function.
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "pyenv"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "xz"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "python"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "pip-latest"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "python-venv-available"

  # ---- Pip packages ----
  pip_cache_versions
  # Pre-warm venv caches for targets with isolation.kind=venv
  local _venv_name _warmed="|"
  for _venv_name in $(_pip_list_venv_names "$cfg_dir" "$yaml"); do
    [[ "$_warmed" == *"|${_venv_name}|"* ]] && continue
    _pip_venv_available "$_venv_name" && _pip_venv_cache_versions "$_venv_name"
    _warmed="${_warmed}${_venv_name}|"
  done
  load_pip_groups_from_yaml "$cfg_dir" "$yaml"

  # ---- Unsloth package (all platforms) ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "unsloth"

  # ---- Global pip conflict cleanup ----
  _pip_global_policy_enforce "$cfg_dir" "$yaml"

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
