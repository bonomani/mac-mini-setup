#!/usr/bin/env bash
# lib/run_components.sh — component / layer dispatch (extracted from install.sh).
#
# Extracted 2026-04-29 (PLAN refactor #5, slice 1). These functions consume
# install.sh-scoped variables (DIR, _QUERY_SCRIPT, _MANIFEST_DIR,
# FAILED_COMPONENTS[], _DISP_* arrays, _comp_prelude) via bash dynamic
# scoping — install.sh sources this file just before calling _run_layer.

_run_comp() {
  local comp="$1" _libs="$2" _runner="$3" _on_fail="$4" _config="$5"
  if uic_component_blocked "$comp"; then
    log_warn "Component $comp blocked by UIC hard gate — outcome=failed, failure_class=permanent, reason=gate_failed"
    # Count targets in the blocked component and record them as skipped
    local _skip_count
    _skip_count=$("${UCC_FRAMEWORK_PYTHON:-python3}" "$_QUERY_SCRIPT" --ordered-targets "$comp" "$_MANIFEST_DIR" 2>/dev/null | wc -l)
    _skip_count=$(( _skip_count + 0 ))  # ensure numeric
    [[ -n "${UCC_SUMMARY_FILE:-}" && $_skip_count -gt 0 ]] && \
      printf '%s|%d|%d|%d|%d\n' "$comp" 0 0 0 "$_skip_count" >> "$UCC_SUMMARY_FILE" 2>/dev/null || true
    FAILED_COMPONENTS+=("$comp"); return
  fi
  local _src=""
  for _lib in $_libs; do _src="${_src}source \"${DIR}/lib/${_lib}.sh\"; "; done
  local _run
  case "$_on_fail" in
    exit)   _run="ucc_reset_registered_targets; export UCC_TARGET_DEFER=1; ${_runner} \"${DIR}\" \"${_config}\" && ucc_flush_registered_targets \"${comp}\" || { ucc_summary \"${comp}\"; exit 1; }" ;;
    ignore) _run="ucc_reset_registered_targets; export UCC_TARGET_DEFER=1; ${_runner} \"${DIR}\" \"${_config}\" && ucc_flush_registered_targets \"${comp}\" || true" ;;
    *)      _run="ucc_reset_registered_targets; export UCC_TARGET_DEFER=1; ${_runner} \"${DIR}\" \"${_config}\" && ucc_flush_registered_targets \"${comp}\"" ;;
  esac
  # Refresh sudo ticket before component execution. bash -c loses tty
  # context, so sudo -n inside the child can't see the parent's ticket.
  # sudo -v here (in the main shell with tty) renews it just in time.
  _ucc_sudo_refresh
  if ! bash -c "${_comp_prelude}; ${_src}${_run}; ucc_summary \"${comp}\""; then
    log_warn "Component failed: $comp"
    FAILED_COMPONENTS+=("$comp")
  fi
  _refresh_brew_path
}

# _run_layer <label> <filter> <comps_array_ref>
# filter: "software" | "system" | "tic"
_run_layer() {
  local label="$1" filter="$2" comps_ref="$3"
  echo ""; printf '── %s\n' "$label"
  for _i in "${!_DISP_COMPS[@]}"; do
    local _cfg="${_DISP_CONFIGS[$_i]}"
    case "$filter" in
      software) [[ "$_cfg" == */system/* || "$_cfg" == "tic" ]] && continue ;;
      system)   [[ "$_cfg" != */system/* ]] && continue ;;
      tic)      [[ "$_cfg" != "tic" ]] && continue ;;
    esac
    local comp="${_DISP_COMPS[$_i]}"
    eval "${comps_ref}+=(\"\$comp\")"
    _print_component_header "$comp"
    if [[ "$filter" == "tic" ]]; then
      # Skip verification when nothing was selected
      if [[ -z "${UCC_TARGET_SET:-}" ]]; then
        log_info "Skipping $(_display_component_name "$comp") (no targets selected)"
        continue
      fi
      if uic_component_blocked "$comp"; then
        log_warn "Component $comp blocked by UIC hard gate"
        FAILED_COMPONENTS+=("$comp"); continue
      fi
      if ! bash -c "${_comp_prelude}; source \"${DIR}/lib/tic.sh\"; source \"${DIR}/lib/tic_runner.sh\"; run_verify \"${DIR}\"" \
           > "$UCC_VERIFICATION_REPORT_FILE"; then
        log_warn "Component failed: $comp"; FAILED_COMPONENTS+=("$comp")
      fi
      [[ -s "$UCC_VERIFICATION_REPORT_FILE" ]] && cat "$UCC_VERIFICATION_REPORT_FILE"
    else
      _run_comp "$comp" "${_DISP_LIBS[$_i]}" "${_DISP_RUNNERS[$_i]}" "${_DISP_ON_FAILS[$_i]}" "$_cfg"
    fi
  done
}
