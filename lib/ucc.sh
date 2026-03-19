#!/usr/bin/env bash
# ============================================================
#  UCC + Basic — Universal Convergence Contract engine
#  Implements Steps 0-6 of UCC/2.0 in bash
# ============================================================

# --- Runtime context (set by install.sh or per-script) ------
UCC_DRY_RUN=${UCC_DRY_RUN:-0}   # 1 = dry-run  (inhibitor=dry_run)
UCC_MODE=${UCC_MODE:-install}    # install | update
UCC_DEBUG=${UCC_DEBUG:-0}        # 1 = show DEBUG lines
UCC_CORRELATION_ID=${UCC_CORRELATION_ID:-$(uuidgen 2>/dev/null || date +%s%N)}

# --- Per-script counters ------------------------------------
_UCC_OBSERVED=0
_UCC_APPLIED=0
_UCC_CHANGED=0
_UCC_FAILED=0
_UCC_SKIPPED=0

# --- Structured logging (UCC-aligned levels) ----------------
#   INFO   – what is being processed
#   NOTICE – final observable state + counters
#   DEBUG  – diagnostics (shown only when UCC_DEBUG=1)
#   WARN   – degraded but non-fatal
#   ERROR  – blocking failure (exits)

_ts() { date '+%H:%M:%S'; }
log_info()   { echo "$(_ts) [INFO]   $*"; }
log_notice() { echo "$(_ts) [NOTICE] $*"; }
log_debug()  { [[ "$UCC_DEBUG" == "1" ]] && echo "$(_ts) [DEBUG]  $*" || true; }
log_warn()   { echo "$(_ts) [WARN]   $*" >&2; }
log_error()  { echo "$(_ts) [ERROR]  $*" >&2; exit 1; }

# --- Run or print command (dry-run gate) --------------------
ucc_run() {
  if [[ "$UCC_DRY_RUN" == "1" ]]; then
    log_debug "DRY-RUN would execute: $*"
    return 0
  fi
  "$@"
}

# ============================================================
#  ucc_target — core UCC lifecycle per target
#
#  Usage:
#    ucc_target \
#      --name     "homebrew"         \
#      --observe  _observe_homebrew  \   # fn that echoes current state
#      --desired  "installed"        \   # desired state string
#      --install  _install_homebrew  \   # fn called when state != desired (install mode)
#      --update   _update_homebrew       # fn called in update mode (optional)
#
#  observe fn must echo exactly the current state string.
#  install/update fns return 0 on success, non-zero on failure.
#  After install, observe is re-run to verify (Step 5).
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
  local observed
  observed=$($observe_fn 2>/dev/null) || observed="unknown"
  log_debug "observed=$observed desired=$desired mode=$UCC_MODE"
  _UCC_OBSERVED=$(( _UCC_OBSERVED + 1 ))

  # Step 3 – Diff
  if [[ "$observed" == "$desired" ]]; then
    # State already matches desired
    if [[ "$UCC_MODE" == "update" && -n "$update_fn" ]]; then
      # Update mode: run upgrade even if already installed
      if [[ "$UCC_DRY_RUN" == "1" ]]; then
        log_notice "$name | Observed=1 Applied=0 Changed=0 Failed=0 Skipped=1 | outcome=unchanged inhibitor=dry_run"
        _UCC_SKIPPED=$(( _UCC_SKIPPED + 1 ))
        return 0
      fi
      _UCC_APPLIED=$(( _UCC_APPLIED + 1 ))
      if $update_fn; then
        _UCC_CHANGED=$(( _UCC_CHANGED + 1 ))
        log_notice "$name | Observed=1 Applied=1 Changed=1 Failed=0 Skipped=0 | outcome=changed reason=updated"
      else
        _UCC_FAILED=$(( _UCC_FAILED + 1 ))
        log_notice "$name | Observed=1 Applied=1 Changed=0 Failed=1 Skipped=0 | outcome=failed failure_class=retryable"
      fi
    else
      # Already converged, nothing to do
      log_notice "$name | Observed=1 Applied=0 Changed=0 Failed=0 Skipped=0 | outcome=converged reason=match"
    fi
    return 0
  fi

  # Diff non-empty — Step 4: Apply transition
  if [[ "$UCC_DRY_RUN" == "1" ]]; then
    log_notice "$name | Observed=1 Applied=0 Changed=0 Failed=0 Skipped=1 | outcome=unchanged inhibitor=dry_run | was=\"$observed\" desired=\"$desired\""
    _UCC_SKIPPED=$(( _UCC_SKIPPED + 1 ))
    return 0
  fi

  if [[ -z "$install_fn" ]]; then
    log_warn "$name — no install function defined, skipping"
    _UCC_SKIPPED=$(( _UCC_SKIPPED + 1 ))
    log_notice "$name | Observed=1 Applied=0 Changed=0 Failed=0 Skipped=1 | outcome=unchanged inhibitor=policy reason=no_install_fn"
    return 0
  fi

  _UCC_APPLIED=$(( _UCC_APPLIED + 1 ))
  if $install_fn; then
    # Step 5 – Verify
    local verified
    verified=$($observe_fn 2>/dev/null) || verified="unknown"
    log_debug "post-install observed=$verified"
    if [[ "$verified" == "$desired" ]]; then
      _UCC_CHANGED=$(( _UCC_CHANGED + 1 ))
      log_notice "$name | Observed=1 Applied=1 Changed=1 Failed=0 Skipped=0 | outcome=changed completion=complete"
    else
      _UCC_FAILED=$(( _UCC_FAILED + 1 ))
      log_notice "$name | Observed=1 Applied=1 Changed=0 Failed=1 Skipped=0 | outcome=failed reason=verify_failed | verified=\"$verified\""
    fi
  else
    _UCC_FAILED=$(( _UCC_FAILED + 1 ))
    log_notice "$name | Observed=1 Applied=1 Changed=0 Failed=1 Skipped=0 | outcome=failed failure_class=retryable"
  fi
}

# ============================================================
#  ucc_summary — emit final counters for this script
#  Returns 1 if any target failed.
# ============================================================
ucc_summary() {
  local script_name="${1:-$(basename "${BASH_SOURCE[1]:-$0}")}"
  echo ""
  log_notice "=== $script_name | Observed=$_UCC_OBSERVED Applied=$_UCC_APPLIED Changed=$_UCC_CHANGED Failed=$_UCC_FAILED Skipped=$_UCC_SKIPPED ==="
  [[ $_UCC_FAILED -gt 0 ]] && return 1 || return 0
}
