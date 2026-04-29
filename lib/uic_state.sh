#!/usr/bin/env bash
# lib/uic_state.sh — global-state display + hard-gate abort helpers.
#
# Extracted from lib/uic.sh on 2026-04-29 (PLAN refactor #6, slice 2).

# ── Global state display helpers ──────────────────────────────────────────────

uic_global_state_label() {
  if [[ ${#_UIC_FAILED_HARD[@]} -gt 0 ]]; then printf 'Blocked'
  elif [[ ${#_UIC_FAILED_SOFT[@]} -gt 0 ]]; then printf 'Degraded'
  else printf 'Ready'
  fi
}

uic_global_state_detail() {
  local detail=""
  if [[ ${#_UIC_FAILED_HARD[@]} -gt 0 ]]; then
    detail="hard_gates=${_UIC_FAILED_HARD[*]}"
  elif [[ ${#_UIC_FAILED_SOFT[@]} -gt 0 ]]; then
    detail="soft_gates=${_UIC_FAILED_SOFT[*]}"
  else
    detail="all_gates_satisfied"
  fi
  printf '%s' "$detail" | tr ' ' ','
}

# ── Hard gate abort helper ────────────────────────────────────────────────────

abort_on_global_hard_gate() {
  local _gi _gkey
  for _gi in "${!_UIC_GATE_NAMES[@]}"; do
    [[ "${_UIC_GATE_BLOCKS[$_gi]}" == "hard" ]]  || continue
    [[ "${_UIC_GATE_SCOPES[$_gi]}" == "global" ]] || continue
    _gkey="$(_uic_gate_key "${_UIC_GATE_NAMES[$_gi]}")"
    if [[ "${!_gkey:-}" == "1" ]]; then
      log_error "UIC global hard gate '${_UIC_GATE_NAMES[$_gi]}' failed — convergence aborted (run --preflight for details)"
    fi
  done
}
