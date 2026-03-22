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

# Per-component counters (reset in each subshell)
_UCC_CONVERGED=0

# --- Structured logging -------------------------------------
_ts() { date '+%H:%M:%S'; }
log_info()   { echo "  $*"; }
log_notice() { echo "$*"; }
log_debug()  { [[ "$UCC_DEBUG" == "1" ]] && echo "$(_ts) [DEBUG]  $*" || true; }
log_warn()   { echo "$(_ts) [WARN]   $*" >&2; }
log_error()  { echo "$(_ts) [ERROR]  $*" >&2; exit 1; }

# ============================================================
#  Package outdated cache
#  Populated once in install.sh; exported so component subshells
#  can read it without repeating the network call.
# ============================================================
brew_cache_outdated() {
  export _BREW_OUTDATED_CACHE
  export _BREW_CASK_OUTDATED_CACHE
  _BREW_OUTDATED_CACHE=$(brew outdated --quiet 2>/dev/null || true)
  _BREW_CASK_OUTDATED_CACHE=$(brew outdated --cask --quiet 2>/dev/null || true)
}

# Match short name ("ariaflow") or full tap name ("bonomani/ariaflow/ariaflow")
_brew_is_outdated()      { echo "${_BREW_OUTDATED_CACHE:-}"      | grep -qE "(^|/)${1}$"; }
_brew_cask_is_outdated() { echo "${_BREW_CASK_OUTDATED_CACHE:-}" | grep -qE "(^|/)${1}$"; }

# Generic observe helpers — return: absent | outdated | current
# Respect UIC_PREF_PACKAGE_UPDATE_POLICY (install-only | always-upgrade).
# brew_is_installed / brew_cask_is_installed are defined in lib/utils.sh
# which is always sourced before these helpers are called.
_brew_refresh_if_stale() {
  [[ "${_BREW_OUTDATED_STALE:-0}" == "1" ]] || return 0
  brew_cache_outdated 2>/dev/null || true
  _BREW_OUTDATED_STALE=0
}

brew_observe() {
  local pkg="$1"
  brew_is_installed "$pkg" || { echo "absent"; return; }
  if [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" == "always-upgrade" ]]; then
    _brew_refresh_if_stale
    _brew_is_outdated "$pkg" && { echo "outdated"; return; }
  fi
  echo "current"
}

brew_cask_observe() {
  local pkg="$1"
  brew_cask_is_installed "$pkg" || { echo "absent"; return; }
  if [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" == "always-upgrade" ]]; then
    _brew_refresh_if_stale
    _brew_cask_is_outdated "$pkg" && { echo "outdated"; return; }
  fi
  echo "current"
}

# ============================================================
#  Structured result artifact (machine-consumable JSONL)
#  Written to UCC_RESULT_FILE when set (exported by install.sh)
#  Each ucc_target result appends one JSON line.
#  Fields comply with UCC/2.0 canonical result paths.
# ============================================================
_ucc_jstr() { printf '%s' "$*" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

_ucc_meta() {
  local id="${$}-${RANDOM}-${RANDOM}"
  local ts; ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "unknown")
  printf '"meta":{"contract":"ucc","version":"2.0","id":"%s","timestamp":"%s","correlation_id":"%s"}' \
    "$id" "$ts" "$(_ucc_jstr "${UCC_CORRELATION_ID:-}")"
}

_ucc_record() {
  [[ -z "${UCC_RESULT_FILE:-}" ]] && return 0
  printf '%s\n' "$1" >> "$UCC_RESULT_FILE" 2>/dev/null || true
}

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

  # Step 1 – Observe current state
  local observed obs_exit
  observed=$($observe_fn 2>/dev/null)
  obs_exit=$?

  # observation=failed: observe function crashed (non-zero exit)
  if [[ $obs_exit -ne 0 ]]; then
    log_notice "$name | obs-failed"
    _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"failed\"}}"
    return 0
  fi

  # observation=indeterminate: observe ran (exit 0) but produced no usable state
  if [[ -z "$observed" ]]; then
    log_notice "$name | indeterminate"
    _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"indeterminate\"}}"
    return 0
  fi

  log_debug "observed=\"$observed\" desired=\"$desired\" mode=$UCC_MODE"

  # Step 3 – Diff: is observed state == desired?
  if [[ "$observed" == "$desired" ]]; then

    if [[ "$UCC_MODE" == "update" && -n "$update_fn" ]]; then
      # Update mode: run upgrade even when state already matches
      if [[ "$UCC_DRY_RUN" == "1" ]]; then
        log_notice "$name | unchanged inhibitor=dry_run | before=\"$observed\" diff={}"
        _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"dry_run\",\"observed_before\":\"$(_ucc_jstr "$observed")\"}}"
        return 0
      fi
      if $update_fn; then
        log_notice "$name | changed \"$observed\" → \"$desired\" completion=complete proof=update_applied"
        _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"changed\",\"completion\":\"complete\",\"proof\":\"update_applied\",\"observed_before\":\"$(_ucc_jstr "$observed")\",\"observed_after\":\"$(_ucc_jstr "$desired")\"}}"
      else
        log_notice "$name | failed class=retryable | before=\"$observed\" diff={}"
        _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"failed\",\"failure_class\":\"retryable\",\"observed_before\":\"$(_ucc_jstr "$observed")\"}}"
      fi
    else
      # Already at desired state — count silently; ucc_summary prints the total
      _UCC_CONVERGED=$(( _UCC_CONVERGED + 1 ))
      _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"converged\",\"observed_before\":\"$(_ucc_jstr "$observed")\"}}"
    fi
    return 0
  fi

  # Diff non-empty
  local diff_str="{was=\"$observed\",is=\"$desired\"}"

  # Step 4: Apply transition
  if [[ "$UCC_DRY_RUN" == "1" ]]; then
    log_notice "$name | unchanged inhibitor=dry_run | before=\"$observed\" diff=$diff_str"
    _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"dry_run\",\"observed_before\":\"$(_ucc_jstr "$observed")\"}}"
    return 0
  fi

  if [[ -z "$install_fn" ]]; then
    log_notice "$name | unchanged inhibitor=policy | before=\"$observed\" diff=$diff_str"
    _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"observed_before\":\"$(_ucc_jstr "$observed")\"}}"
    return 0
  fi

  if $install_fn; then
    _BREW_OUTDATED_STALE=1  # invalidate cache so verify sees post-upgrade state
    # Step 5 – Verify: re-observe after transition
    local verified ver_exit
    verified=$($observe_fn 2>/dev/null)
    ver_exit=$?
    log_debug "post-install observed=\"$verified\""
    if [[ $ver_exit -eq 0 && "$verified" == "$desired" ]]; then
      log_notice "$name | changed \"$observed\" → \"$desired\" completion=complete proof=verify_pass"
      _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"changed\",\"completion\":\"complete\",\"proof\":\"verify_pass\",\"observed_before\":\"$(_ucc_jstr "$observed")\",\"observed_after\":\"$(_ucc_jstr "$verified")\"}}"
    else
      log_notice "$name | failed class=retryable | before=\"$observed\" diff=$diff_str after=\"${verified:-?}\""
      _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"failed\",\"failure_class\":\"retryable\",\"observed_before\":\"$(_ucc_jstr "$observed")\",\"observed_after\":\"$(_ucc_jstr "${verified:-}")\"}}"
    fi
  else
    log_notice "$name | failed class=retryable | before=\"$observed\" diff=$diff_str"
    _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"failed\",\"failure_class\":\"retryable\",\"observed_before\":\"$(_ucc_jstr "$observed")\"}}"
  fi
}

# ============================================================
#  ucc_summary — final marker for this script
# ============================================================
ucc_summary() {
  [[ $_UCC_CONVERGED -gt 0 ]] && log_notice "  $_UCC_CONVERGED converged"
}
