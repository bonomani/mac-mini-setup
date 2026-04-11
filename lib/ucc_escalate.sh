#!/usr/bin/env bash
# lib/ucc_escalate.sh — Generic escalating recovery for UCC targets
#
# When an action fails and verify does not reach desired state, the
# framework calls _ucc_try_escalate() which tries progressively more
# aggressive recovery levels until one succeeds or all fail.
#
# Drivers opt in by implementing:
#   _ucc_driver_<kind>_recover <cfg_dir> <yaml> <target> <level>
#
# Levels:
#   1 = retry      — wait briefly, re-run the same action
#   2 = reinstall  — remove + fresh install
#   3 = clean      — purge caches/state, reinstall from scratch
#
# If a driver does not implement _recover, escalation is skipped.
# Each level re-verifies via observe_fn after recovery.
#
# Driver recover return codes:
#   0   = recovery action succeeded (verify will confirm)
#   1   = recovery action attempted but failed (continue to next level)
#   2   = level not supported by this driver (stop escalating)
#   124 = policy blocked (stop escalating)
#   125 = admin required (stop escalating)

_UCC_ESCALATE_MAX=3
_UCC_ESCALATE_DELAY=(0 2 3 5)

# Result variable — set by _ucc_try_escalate, read by caller.
_UCC_ESCALATE_RESULT=""

# Standalone satisfaction check matching _ucc_satisfied in _ucc_execute_target.
_ucc_escalate_satisfied() {
  local obs="$1" des="$2" axes="$3"
  [[ "$des" == "@present" && "$obs" != "absent" && "$obs" != "outdated" ]] && return 0
  [[ "$(_ucc_diff_obj "$obs" "$des" "$axes")" == "{}" ]]
}

# _ucc_try_escalate <observe_fn> <desired> <axes> <recover_fn> <display_name> <profile>
# Sets _UCC_ESCALATE_RESULT to the observed state on success.
# Returns 0 on success, 1 if all levels exhausted, 124/125 for policy exits.
# All display output goes to stderr to avoid contaminating command substitution.
_ucc_try_escalate() {
  local observe_fn="$1" desired="$2" axes="$3"
  local recover_fn="$4" display_name="$5" profile="$6"

  _UCC_ESCALATE_RESULT=""

  local level verified ver_exit
  for level in $(seq 1 $_UCC_ESCALATE_MAX); do
    log_debug "escalate: level=$level" >&2

    local recover_rc=0
    "$recover_fn" "$level" || recover_rc=$?

    # Return 2 = driver does not support this level — stop escalating
    # Return 1 = recovery attempted but failed — continue to next level
    if [[ $recover_rc -eq 2 ]]; then
      log_debug "escalate: driver returned unsupported for level $level, stopping" >&2
      break
    fi

    # Policy exits stop escalation and propagate
    if [[ $recover_rc -eq 124 || $recover_rc -eq 125 ]]; then
      return $recover_rc
    fi

    # Post-recovery delay — gives async services time to start
    local delay=${_UCC_ESCALATE_DELAY[$level]:-5}
    [[ $delay -gt 0 ]] && sleep "$delay"

    # Verify after recovery
    verified=$($observe_fn 2>/dev/null)
    ver_exit=$?
    if [[ $ver_exit -eq 0 && -n "$verified" ]] && _ucc_escalate_satisfied "$verified" "$desired" "$axes"; then
      log_debug "escalate: level $level succeeded (observed=$verified)" >&2
      _UCC_ESCALATE_RESULT="$verified"
      return 0
    fi
    log_debug "escalate: level $level failed (observed=${verified:-?})" >&2
  done

  return 1
}

# _ucc_attempt_escalation <observe_fn> <desired> <axes> <recover_fn>
#   <display_name> <profile> <action_label> <name> <observed> <msg_id> <started_at>
# Attempts escalating recovery. On success: emits target line, records outcome, returns 0.
# On failure or no recover_fn: returns 1 (caller should handle the fail path).
_ucc_attempt_escalation() {
  local observe_fn="$1" desired="$2" axes="$3" recover_fn="$4"
  local display_name="$5" profile="$6" action_label="$7"
  local name="$8" observed="$9" msg_id="${10}" started_at="${11}"

  [[ -n "$recover_fn" ]] || return 1
  _ucc_try_escalate "$observe_fn" "$desired" "$axes" "$recover_fn" "$display_name" "$profile"
  local esc_rc=$?
  [[ $esc_rc -eq 0 && -n "$_UCC_ESCALATE_RESULT" ]] || return 1

  _ucc_emit_target_line "$profile" "$action_label" "$display_name" \
    "\"$(_ucc_display_state "$observed" "$axes")\" -> \"$(_ucc_display_state "$_UCC_ESCALATE_RESULT" "$axes")\" (recovered)"
  _ucc_record_outcome "$profile" "$name" "CHANGED" "ok" "changed" "$msg_id" "$started_at" \
    "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$_UCC_ESCALATE_RESULT" "$axes"),\"observed_after\":$(_ucc_state_obj "$_UCC_ESCALATE_RESULT")}" \
    "{\"observation\":\"ok\",\"outcome\":\"changed\",\"completion\":\"complete\",\"proof\":{\"change\":\"escalation_recovery\"}}"
  return 0
}
