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
#
#  Mandatory state fields:
#    before  : observed state before action  (when observation=ok)
#    diff    : {was,is} or empty             (when observation=ok)
#    after   : observed state after action   (when outcome=changed, completion=complete)
#    proof   : verify_pass | update_applied  (when outcome=changed)
# ============================================================

# --- Runtime context ----------------------------------------
UCC_DRY_RUN=${UCC_DRY_RUN:-0}   # 1 = dry-run (inhibitor=dry_run)
UCC_MODE=${UCC_MODE:-install}    # install | update
UCC_DEBUG=${UCC_DEBUG:-0}        # 1 = show DEBUG lines
UCC_CORRELATION_ID=${UCC_CORRELATION_ID:-$(uuidgen 2>/dev/null || date +%s%N)}

# --- Structured logging -------------------------------------
_ts() { date '+%H:%M:%S'; }
log_info()   { echo "$(_ts) [INFO]   $*"; }
log_notice() { echo "$*"; }
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

  # observation=failed: observe function crashed (non-zero exit)
  if [[ $obs_exit -ne 0 ]]; then
    log_notice "$name | observation=failed failure_class=retryable"
    return 0
  fi

  # observation=indeterminate: observe ran (exit 0) but produced no usable state
  if [[ -z "$observed" ]]; then
    log_notice "$name | observation=indeterminate"
    return 0
  fi

  log_debug "observed=\"$observed\" desired=\"$desired\" mode=$UCC_MODE"

  # Step 3 – Diff: is observed state == desired?
  if [[ "$observed" == "$desired" ]]; then

    if [[ "$UCC_MODE" == "update" && -n "$update_fn" ]]; then
      # Update mode: run upgrade even when state already matches
      if [[ "$UCC_DRY_RUN" == "1" ]]; then
        log_notice "$name | observation=ok outcome=unchanged inhibitor=dry_run | before=\"$observed\" diff={}"
        return 0
      fi
      if $update_fn; then
        log_notice "$name | observation=ok outcome=changed completion=complete | before=\"$observed\" diff={} after=\"$desired\" proof=update_applied"
      else
        log_notice "$name | observation=ok outcome=failed failure_class=retryable | before=\"$observed\" diff={}"
      fi
    else
      # Already at desired state — converged
      log_notice "$name | observation=ok outcome=converged | before=\"$observed\" diff={}"
    fi
    return 0
  fi

  # Diff non-empty
  local diff_str="{was=\"$observed\",is=\"$desired\"}"

  # Step 4: Apply transition
  if [[ "$UCC_DRY_RUN" == "1" ]]; then
    log_notice "$name | observation=ok outcome=unchanged inhibitor=dry_run | before=\"$observed\" diff=$diff_str"
    return 0
  fi

  if [[ -z "$install_fn" ]]; then
    log_notice "$name | observation=ok outcome=unchanged inhibitor=policy | before=\"$observed\" diff=$diff_str"
    return 0
  fi

  if $install_fn; then
    # Step 5 – Verify: re-observe after transition
    local verified ver_exit
    verified=$($observe_fn 2>/dev/null)
    ver_exit=$?
    log_debug "post-install observed=\"$verified\""
    if [[ $ver_exit -eq 0 && "$verified" == "$desired" ]]; then
      log_notice "$name | observation=ok outcome=changed completion=complete | before=\"$observed\" diff=$diff_str after=\"$verified\" proof=verify_pass"
    else
      log_notice "$name | observation=ok outcome=failed failure_class=retryable | before=\"$observed\" diff=$diff_str after=\"$verified\""
    fi
  else
    log_notice "$name | observation=ok outcome=failed failure_class=retryable | before=\"$observed\" diff=$diff_str"
  fi
}

# ============================================================
#  ucc_summary — final marker for this script
# ============================================================
ucc_summary() {
  local script_name="${1:-$(basename "${BASH_SOURCE[1]:-$0}")}"
  echo ""
  log_notice "=== $script_name ==="
}
