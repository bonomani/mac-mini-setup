#!/usr/bin/env bash
# ============================================================
#  UCC + Basic — Universal Convergence Contract engine
#  Implements Steps 0-6 of UCC/2.0 in bash
#
#  Three-field result model (normative):
#    observation : ok | indeterminate | failed
#    outcome     : converged | changed | unchanged | failed
#    completion  : complete | pending  (when outcome=changed)
#
#  Qualifiers (conditional):
#    failure_class : retryable | permanent  (when outcome=failed)
#    inhibitor     : dry_run | policy       (when outcome=unchanged)
#    reason        : match | updated | verify_failed | no_install_fn
#
#  Mandatory state fields:
#    before  : observed state before action  (when observation=ok)
#    diff    : {was,is} or empty             (when observation=ok)
#    after   : observed state after action   (when outcome=changed, completion=complete)
#    proof   : verify_pass | update_applied  (when outcome=changed)
#
#  Five-field counters (per-target in NOTICE, totals in summary):
#    Observed Applied Changed Failed Skipped
# ============================================================

# --- Runtime context ----------------------------------------
UCC_DRY_RUN=${UCC_DRY_RUN:-0}   # 1 = dry-run (inhibitor=dry_run)
UCC_MODE=${UCC_MODE:-install}    # install | update
UCC_DEBUG=${UCC_DEBUG:-0}        # 1 = show DEBUG lines
UCC_CORRELATION_ID=${UCC_CORRELATION_ID:-$(uuidgen 2>/dev/null || date +%s%N)}

# --- Per-script running totals ------------------------------
_UCC_OBSERVED=0
_UCC_APPLIED=0
_UCC_CHANGED=0
_UCC_FAILED=0
_UCC_SKIPPED=0

# --- Structured logging -------------------------------------
_ts() { date '+%H:%M:%S'; }
log_info()   { echo "$(_ts) [INFO]   $*"; }
log_notice() { echo "$(_ts) [NOTICE] $*"; }
log_debug()  { [[ "$UCC_DEBUG" == "1" ]] && echo "$(_ts) [DEBUG]  $*" || true; }
log_warn()   { echo "$(_ts) [WARN]   $*" >&2; }
log_error()  { echo "$(_ts) [ERROR]  $*" >&2; exit 1; }

# --- Dry-run gate -------------------------------------------
ucc_run() {
  if [[ "$UCC_DRY_RUN" == "1" ]]; then
    log_debug "DRY-RUN would execute: $*"
    return 0
  fi
  "$@"
}

# ============================================================
#  ucc_target — full UCC Steps 0-6 lifecycle per target
# ============================================================
ucc_target() {
  local name="" observe_fn="" desired="" install_fn="" update_fn=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)    name="$2";       shift 2 ;;
      --observe) observe_fn="$2"; shift 2 ;;
      --desired) desired="$2";    shift 2 ;;
      --install) install_fn="$2"; shift 2 ;;
      --update)  update_fn="$2";  shift 2 ;;
      *) shift ;;
    esac
  done

  log_info "Target: $name"

  # Step 1 – Observe current state
  local observed obs_exit
  observed=$($observe_fn 2>/dev/null)
  obs_exit=$?
  _UCC_OBSERVED=$(( _UCC_OBSERVED + 1 ))

  # Step 1 result: observation=indeterminate when observe infrastructure fails
  # (non-zero exit OR empty output = state cannot be determined)
  if [[ $obs_exit -ne 0 || -z "$observed" ]]; then
    _UCC_SKIPPED=$(( _UCC_SKIPPED + 1 ))
    log_notice "$name | observation=indeterminate | Observed=1 Applied=0 Changed=0 Failed=0 Skipped=1"
    return 0
  fi

  log_debug "observed=\"$observed\" desired=\"$desired\" mode=$UCC_MODE"

  # Step 3 – Diff: is observed state == desired?
  if [[ "$observed" == "$desired" ]]; then

    if [[ "$UCC_MODE" == "update" && -n "$update_fn" ]]; then
      # Update mode: run upgrade even when state already matches
      if [[ "$UCC_DRY_RUN" == "1" ]]; then
        _UCC_SKIPPED=$(( _UCC_SKIPPED + 1 ))
        log_notice "$name | observation=ok outcome=unchanged inhibitor=dry_run | before=\"$observed\" diff=empty | Observed=1 Applied=0 Changed=0 Failed=0 Skipped=1"
        return 0
      fi
      _UCC_APPLIED=$(( _UCC_APPLIED + 1 ))
      if $update_fn; then
        _UCC_CHANGED=$(( _UCC_CHANGED + 1 ))
        log_notice "$name | observation=ok outcome=changed completion=complete | before=\"$observed\" diff=empty proof=update_applied reason=updated | Observed=1 Applied=1 Changed=1 Failed=0 Skipped=0"
      else
        _UCC_FAILED=$(( _UCC_FAILED + 1 ))
        log_notice "$name | observation=ok outcome=failed failure_class=retryable | before=\"$observed\" diff=empty | Observed=1 Applied=1 Changed=0 Failed=1 Skipped=0"
      fi
    else
      # Already at desired state — converged
      log_notice "$name | observation=ok outcome=converged | before=\"$observed\" diff=empty reason=match | Observed=1 Applied=0 Changed=0 Failed=0 Skipped=0"
    fi
    return 0
  fi

  # Diff non-empty
  local diff_str="{was=\"$observed\",is=\"$desired\"}"

  # Step 4: Apply transition
  if [[ "$UCC_DRY_RUN" == "1" ]]; then
    _UCC_SKIPPED=$(( _UCC_SKIPPED + 1 ))
    log_notice "$name | observation=ok outcome=unchanged inhibitor=dry_run | before=\"$observed\" diff=$diff_str | Observed=1 Applied=0 Changed=0 Failed=0 Skipped=1"
    return 0
  fi

  if [[ -z "$install_fn" ]]; then
    _UCC_SKIPPED=$(( _UCC_SKIPPED + 1 ))
    log_notice "$name | observation=ok outcome=unchanged inhibitor=policy | before=\"$observed\" diff=$diff_str reason=no_install_fn | Observed=1 Applied=0 Changed=0 Failed=0 Skipped=1"
    return 0
  fi

  _UCC_APPLIED=$(( _UCC_APPLIED + 1 ))
  if $install_fn; then
    # Step 5 – Verify: re-observe after transition
    local verified ver_exit
    verified=$($observe_fn 2>/dev/null)
    ver_exit=$?
    log_debug "post-install observed=\"$verified\""
    if [[ $ver_exit -eq 0 && "$verified" == "$desired" ]]; then
      _UCC_CHANGED=$(( _UCC_CHANGED + 1 ))
      log_notice "$name | observation=ok outcome=changed completion=complete | before=\"$observed\" diff=$diff_str after=\"$verified\" proof=verify_pass | Observed=1 Applied=1 Changed=1 Failed=0 Skipped=0"
    else
      _UCC_FAILED=$(( _UCC_FAILED + 1 ))
      log_notice "$name | observation=ok outcome=failed failure_class=retryable | before=\"$observed\" diff=$diff_str after=\"$verified\" reason=verify_failed | Observed=1 Applied=1 Changed=0 Failed=1 Skipped=0"
    fi
  else
    _UCC_FAILED=$(( _UCC_FAILED + 1 ))
    log_notice "$name | observation=ok outcome=failed failure_class=retryable | before=\"$observed\" diff=$diff_str | Observed=1 Applied=1 Changed=0 Failed=1 Skipped=0"
  fi
}

# ============================================================
#  ucc_summary — final counters for this script
#  Returns 1 if any target failed.
# ============================================================
ucc_summary() {
  local script_name="${1:-$(basename "${BASH_SOURCE[1]:-$0}")}"
  echo ""
  log_notice "=== $script_name | Observed=$_UCC_OBSERVED Applied=$_UCC_APPLIED Changed=$_UCC_CHANGED Failed=$_UCC_FAILED Skipped=$_UCC_SKIPPED ==="
  [[ $_UCC_FAILED -gt 0 ]] && return 1 || return 0
}
