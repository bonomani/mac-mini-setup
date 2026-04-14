#!/usr/bin/env bash
# lib/pip_common.sh — shared helpers for pip / pip-bootstrap drivers
# Sourced by lib/ucc.sh

# Constraint-bound check: if an `update` action completed successfully but the
# packages are still flagged as outdated (typically because pip's
# `--upgrade-strategy only-if-needed` won't pull newer versions that would
# break peer constraints), signal warn (rc=124) instead of letting the
# framework's verify-after-update see "still outdated" and emit [fail].
#
# Usage:
#   _pip_constraint_bound_check <action> <rc> <outdated_check_fn> [args...]
#
# Returns 124 if the constraint-bound condition matches; the original $rc
# otherwise. Intended to be the LAST statement of the action function:
#   _pip_constraint_bound_check "$action" "$rc" _pip_pkgs_outdated "$pkgs"
#   return $?
_pip_constraint_bound_check() {
  local action="$1" rc="$2" check_fn="$3"
  shift 3
  if [[ "$action" == "update" && $rc -eq 0 ]]; then
    if "$check_fn" "$@"; then
      log_debug "pip/$action: pkgs still outdated post-upgrade (constraint-bound) — signalling warn"
      return 124
    fi
  fi
  return $rc
}
