#!/usr/bin/env bash
# lib/ucc_selection.sh — Target/component selection and resolution
# Sourced by install.sh. Operates on globals:
#   _resolved[]       — ordered list of components to run
#   UCC_TARGET_SET    — pipe-delimited set of selected target names
#   COMPONENTS[]      — all available components
#   _QUERY_SCRIPT     — path to validate_targets_manifest.py
#   _MANIFEST_DIR     — path to ucc/ manifest directory

# Resolve a single target name: add it and its dep components to _resolved.
_resolve_target() {
  local name="$1"
  log_info "Resolved target '$name' → component '$("${UCC_FRAMEWORK_PYTHON:-python3}" "$_QUERY_SCRIPT" --find-target "$name" "$_MANIFEST_DIR" 2>/dev/null)'"
  UCC_TARGET_SET="${UCC_TARGET_SET}$("${UCC_FRAMEWORK_PYTHON:-python3}" "$_QUERY_SCRIPT" --dep-targets "$name" "$_MANIFEST_DIR" 2>/dev/null | tr '\n' '|')"
  while IFS= read -r _dep_comp; do
    [[ -n "$_dep_comp" ]] && _resolved+=("$_dep_comp")
  done < <("${UCC_FRAMEWORK_PYTHON:-python3}" "$_QUERY_SCRIPT" --dep-components "$name" "$_MANIFEST_DIR" 2>/dev/null || true)
}

# Resolve a component: collect targets, auto-include dep components, add to _resolved.
_resolve_component() {
  local name="$1" _t _dep_comp _seen=""
  local _targets=()
  while IFS= read -r _t; do
    [[ -n "$_t" ]] && _targets+=("$_t")
  done < <("${UCC_FRAMEWORK_PYTHON:-python3}" "$_QUERY_SCRIPT" --ordered-targets "$name" "$_MANIFEST_DIR" 2>/dev/null || true)
  for _t in ${_targets[@]+"${_targets[@]}"}; do
    while IFS= read -r _dep_comp; do
      if [[ -n "$_dep_comp" && "$_dep_comp" != "$name" \
        && "$_seen" != *"|${_dep_comp}|"* ]] \
        && ! printf '%s\n' "${_resolved[@]+"${_resolved[@]}"}" | grep -qx "$_dep_comp"; then
        _seen="${_seen}|${_dep_comp}|"
        _resolved+=("$_dep_comp")
        local _dt
        while IFS= read -r _dt; do
          [[ -n "$_dt" ]] && UCC_TARGET_SET="${UCC_TARGET_SET}${_dt}|"
        done < <("${UCC_FRAMEWORK_PYTHON:-python3}" "$_QUERY_SCRIPT" --ordered-targets "$_dep_comp" "$_MANIFEST_DIR" 2>/dev/null || true)
      fi
    done < <("${UCC_FRAMEWORK_PYTHON:-python3}" "$_QUERY_SCRIPT" --dep-components "$_t" "$_MANIFEST_DIR" 2>/dev/null || true)
  done
  _resolved+=("$name")
  for _t in ${_targets[@]+"${_targets[@]}"}; do
    UCC_TARGET_SET="${UCC_TARGET_SET}${_t}|"
  done
}

# Resolve a list of component/target names into _resolved + UCC_TARGET_SET.
_resolve_selection() {
  for _arg in "$@"; do
    case "$_arg" in
      component:*) _arg="${_arg#component:}" ;;
      target:*)    _resolve_target "${_arg#target:}"; continue ;;
    esac
    if printf '%s\n' "${COMPONENTS[@]}" | grep -qx "$_arg"; then
      _resolve_component "$_arg"
    else
      "${UCC_FRAMEWORK_PYTHON:-python3}" "$_QUERY_SCRIPT" --find-target "$_arg" "$_MANIFEST_DIR" >/dev/null 2>&1 \
        || log_error "Unknown component or target: '$_arg'"
      _resolve_target "$_arg"
    fi
  done
}
