#!/usr/bin/env bash
# lib/component_runner.sh — Helpers for per-component execution
# Sourced by install.sh. The main orchestration (_run_comp, _run_layer)
# stays in install.sh because it's tightly coupled to the dispatch arrays
# and $_comp_prelude string — these helpers are the pure-ish utilities.

# Return 0 if the component has at least one target in UCC_TARGET_SET.
# Used by _print_component_header in fast display mode.
# Reads globals: UCC_TARGET_SET, _QUERY_SCRIPT, _MANIFEST_DIR
_component_has_selected_targets() {
  local comp="$1" _t
  while IFS= read -r _t; do
    [[ -z "$_t" ]] && continue
    [[ "${UCC_TARGET_SET:-}" == *"${_t}|"* ]] && return 0
  done < <(python3 "$_QUERY_SCRIPT" --ordered-targets "$comp" "$_MANIFEST_DIR" 2>/dev/null)
  return 1
}

# Print component header. In fast mode, skips header when no selected
# targets are in the component.
# Reads globals: UIC_PREF_SKIP_DISPLAY_MODE, UCC_TARGET_SET
_print_component_header() {
  local comp="$1"
  if [[ "${UIC_PREF_SKIP_DISPLAY_MODE:-full}" == "fast" ]] \
    && [[ -n "${UCC_TARGET_SET:-}" ]] \
    && ! _component_has_selected_targets "$comp"; then
    return 0
  fi
  printf '  [%s]\n' "$(_display_component_name "$comp")"
}

# Record synthetic "platform-skipped" status for every target in a
# component that is being skipped because its platform doesn't apply.
# Consumed by _ucc_check_deps_recursive so cross-component dependents
# cascade to [skip] instead of [dep-fail].
# Reads globals: UCC_TARGETS_QUERY_SCRIPT, UCC_TARGETS_MANIFEST
_record_component_platform_skip() {
  local comp="$1" t
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    _ucc_record_target_status "$t" "platform-skipped"
  done < <(python3 "$UCC_TARGETS_QUERY_SCRIPT" --ordered-targets "$comp" "$UCC_TARGETS_MANIFEST" 2>/dev/null || true)
}
