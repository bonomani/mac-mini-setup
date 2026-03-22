#!/usr/bin/env bash
# lib/tic.sh — Test Intent Contract (TIC) helper
# BGS suite — bgs/SUITE.md §4.6
#
# BISS: Axis A = GIC (observable verification — no convergence side-effects)
#       Axis B = Basic
#
# Provides tic_test and tic_summary.
# Tests are read-only probes; they MUST NOT mutate system state.
#
# TIC fields implemented per SPEC.md:
#   name        — unique test identifier
#   intent      — what behavior is being verified and why it matters
#   oracle      — shell expression whose exit code decides pass/fail
#   trace       — trace link back to the UCC target or component under test
#   skip        — optional reason; when set the oracle is not evaluated

TIC_PASS=0
TIC_FAIL=0
TIC_SKIP=0

# tic_test: declare and execute one TIC-compliant test
#
# Usage:
#   tic_test \
#     --name   "python-lzma" \
#     --intent "lzma C extension must compile into Python (requires xz at build time)" \
#     --oracle "python3 -c 'import lzma'" \
#     --trace  "component:04-python / ucc-target:xz" \
#     [--skip  "reason"]
tic_test() {
  local name="" intent="" oracle="" trace="" skip_reason=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)   name="$2";        shift 2 ;;
      --intent) intent="$2";      shift 2 ;;
      --oracle) oracle="$2";      shift 2 ;;
      --trace)  trace="$2";       shift 2 ;;
      --skip)   skip_reason="$2"; shift 2 ;;
      *)        shift ;;
    esac
  done

  local trace_field=""
  [[ -n "$trace" ]] && trace_field=" trace=\"$trace\""

  # Phase: skip (oracle not evaluated — reason must be explicit per TIC SPEC)
  if [[ -n "$skip_reason" ]]; then
    printf 'TIC %-45s | status=skip reason="%s"%s\n' \
      "$name" "$skip_reason" "$trace_field"
    TIC_SKIP=$(( TIC_SKIP + 1 ))
    return 0
  fi

  # Phase: arrange + act + observe + assert
  local observed=""
  observed=$(eval "$oracle" 2>&1)
  local exit_code=$?

  # Phase: report
  if [[ $exit_code -eq 0 ]]; then
    printf 'TIC %-45s | status=pass intent="%s"%s\n' \
      "$name" "$intent" "$trace_field"
    TIC_PASS=$(( TIC_PASS + 1 ))
  else
    printf 'TIC %-45s | status=fail intent="%s" observed="%s"%s\n' \
      "$name" "$intent" "$observed" "$trace_field"
    TIC_FAIL=$(( TIC_FAIL + 1 ))
  fi
}

# tic_summary: emit aggregated result and return non-zero if any test failed
tic_summary() {
  local component="${1:-verify}"
  printf '\nTIC summary [%s] | pass=%d fail=%d skip=%d\n' \
    "$component" "$TIC_PASS" "$TIC_FAIL" "$TIC_SKIP"
  [[ "$TIC_FAIL" -eq 0 ]]
}
