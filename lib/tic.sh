#!/usr/bin/env bash
# lib/tic.sh — Test Intent Contract (TIC) helper
# BGS suite — TIC verification layer
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
#
# Runner-only metadata such as component scoping and current-run status
# dependencies are resolved in lib/tic_runner.sh before tic_test is called.

TIC_PASS=0
TIC_FAIL=0
TIC_SKIP=0

_tic_emit_line() {
  local status="$1" name="$2" detail="${3:-}"
  if [[ -n "$detail" ]]; then
    printf '      [%-8s] %-30s %s\n' "$status" "$name" "$detail"
  else
    printf '      [%-8s] %s\n' "$status" "$name"
  fi
}

# tic_test: declare and execute one TIC-compliant test
#
# Usage:
#   tic_test \
#     --name   "python-lzma" \
#     --intent "lzma C extension must compile into Python (requires xz at build time)" \
#     --oracle "python3 -c 'import lzma'" \
#     --trace  "component:python / ucc-target:xz" \
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
    _tic_emit_line "skip" "$name" "$skip_reason"
    TIC_SKIP=$(( TIC_SKIP + 1 ))
    return 0
  fi

  # Phase: arrange + act + observe + assert
  local observed="" exit_code=0
  if observed=$(eval "$oracle" 2>&1); then
    exit_code=0
  else
    exit_code=$?
  fi

  # Phase: report
  if [[ $exit_code -eq 0 ]]; then
    _tic_emit_line "pass" "$name"
    TIC_PASS=$(( TIC_PASS + 1 ))
  else
    _tic_emit_line "fail" "$name"
    [[ -n "$intent" ]] && printf '                 intent: %s\n' "$intent"
    printf '                 observed: %s\n' "$observed"
    [[ -n "$trace" ]] && printf '                 trace: %s\n' "$trace"
    TIC_FAIL=$(( TIC_FAIL + 1 ))
  fi
}

# tic_summary: emit aggregated result and return non-zero if any test failed
tic_summary() {
  if [[ -n "${UCC_SUMMARY_FILE:-}" ]]; then
    printf 'verify|tic|%d|%d|%d\n' "$TIC_PASS" "$TIC_FAIL" "$TIC_SKIP" \
      >> "$UCC_SUMMARY_FILE" 2>/dev/null || true
  fi
  [[ "$TIC_FAIL" -eq 0 ]]
}
