#!/usr/bin/env bash
# lib/ucc_status.sh — single source of truth for target-status semantics.
#
# A "target status" is the value recorded by _ucc_record_target_status that
# downstream consumers (deps line, services list, cascade logic, summary
# counters) read to decide what to do.
#
# Each status carries 4 attributes:
#   - reachable:        Would the target's service endpoint answer? (Services list filter)
#   - hide_from_deps:   Should this status be omitted from a dependent's `deps:` line?
#   - cascade_action:   What should _ucc_check_deps_recursive do when a dep has this status?
#                       Values: dep-fail | skip | continue (default)
#   - counter:          Which _UCC_<NAME> counter to bump in _ucc_record_outcome.
#                       Values: CONVERGED | CHANGED | FAILED | SKIPPED | POLICY | "" (no bump)
#
# Adding a new status is one row per array. Removing requires verifying all
# four arrays. Sites query via the four helpers below — none of them
# hardcode status names.

# ── Reachable: would this target's endpoint be answering on its port? ─────────
# Used by lib/summary.sh:_target_endpoint_reachable to decide which entries
# go into the "Services" list in the run footer. A target whose status is
# unlisted here is treated as unreachable (failed/skipped/disabled etc.).
declare -gA _UCC_STATUS_REACHABLE=(
  [ok]=1
  [unchanged]=1
  [changed]=1
  [updated]=1
  [installed]=1
  [oracle-pass]=1
  [warn]=1
  [satisfied-external]=1
)

# ── Hide from deps line ──────────────────────────────────────────────────────
# Used by lib/ucc_asm.sh:_ucc_dep_status_hidden to decide which dep statuses
# get suppressed from a dependent's `deps:` evidence line.
# Two reasons a parent's status is uninteresting in a dependent's view:
#   - Structural skip (requires-skipped/platform-skipped/disabled/skipped):
#     dep was filtered out for a reason the operator can't act on.
#   - Soft-policy / external (warn/policy/satisfied-external): dep ran or was
#     present externally; propagating these to every dependent's line just
#     suggests degradation that isn't there.
declare -gA _UCC_STATUS_HIDE_FROM_DEPS=(
  [skipped]=1
  [requires-skipped]=1
  [platform-skipped]=1
  [disabled]=1
  [satisfied-external]=1
  [warn]=1
  [policy]=1
)

# ── Cascade action when a dep has this status ────────────────────────────────
# Used by lib/ucc_targets.sh:_ucc_check_deps_recursive to decide what to do
# when checking a dependent's deps:
#   dep-fail  → real failure, dependent should NOT run; emit [dep-fail], rc=1
#   skip      → cascade clean skip; dependent recorded as "skipped", rc=2
#   continue  → dep ran fine OR is irrelevant on this host; dependent proceeds
#               (default for any status not listed here)
#
# Important asymmetries (don't blindly add every "didn't run" status here):
#
#   - `platform-skipped` cascades because the WHOLE COMPONENT containing
#     the dep was group-skipped — the dep genuinely doesn't exist on this
#     host. A dependent in a different component still depending on it
#     can't proceed.
#
#   - `requires-skipped` does NOT cascade because it only means the dep's
#     own `requires:` line didn't match. The dependent may have fallback
#     drivers (e.g. cli-zsh declares depends_on: homebrew, but on Linux
#     it falls back to apt). Cascading would block legitimate fallback
#     installs. The dep simply not appearing in the deps line (via the
#     hide-from-deps filter) is the right outcome here.
#
#   - `disabled` does NOT cascade — operator-disabled deps may still be
#     present from a previous run; the dependent's oracle.configured will
#     verify presence and either proceed or report dep-fail.
declare -gA _UCC_STATUS_CASCADE=(
  [failed]=dep-fail
  [skipped]=skip
  [platform-skipped]=skip
  [policy]=skip
)

# ── Reason text shown on the cascade-skip line ───────────────────────────────
# `_ucc_check_deps_recursive` formats the [skip]/[dep-fail] line as
# "<reason>: <dep>". The reason for `platform-skipped` is host-dependent
# (interpolates HOST_PLATFORM) so it lives in the function override below.
declare -gA _UCC_STATUS_DEP_REASON=(
  [failed]="dependency failed this run"
  [skipped]="dependency was skipped"
  [requires-skipped]="dependency was filtered out"
  [disabled]="dependency was disabled"
  [policy]="dependency requires admin"
)

# ── Counter to bump in _ucc_record_outcome ───────────────────────────────────
# Maps target_status → _UCC_<NAME> counter. Used as fallback when the caller
# of _ucc_record_outcome doesn't pass an explicit counter argument (the
# explicit-arg path still works, e.g. for "changed" → CHANGED even though
# target_status="ok"). Empty mapping = don't bump any counter.
declare -gA _UCC_STATUS_COUNTER=(
  [ok]=CONVERGED
  [unchanged]=CONVERGED
  [oracle-pass]=CONVERGED
  [satisfied-external]=CONVERGED
  [changed]=CHANGED
  [updated]=CHANGED
  [installed]=CHANGED
  [failed]=FAILED
  [dep-fail]=FAILED
  [skipped]=SKIPPED
  [requires-skipped]=SKIPPED
  [platform-skipped]=SKIPPED
  [disabled]=SKIPPED
  [policy]=POLICY
  [warn]=POLICY
)

# ── Query helpers (the only API consumers should use) ────────────────────────

_ucc_status_is_reachable() {
  [[ "${_UCC_STATUS_REACHABLE[$1]:-0}" == "1" ]]
}

_ucc_status_hide_from_deps() {
  [[ "${_UCC_STATUS_HIDE_FROM_DEPS[$1]:-0}" == "1" ]]
}

_ucc_status_cascade_action() {
  printf '%s' "${_UCC_STATUS_CASCADE[$1]:-continue}"
}

_ucc_status_dep_reason() {
  case "$1" in
    # platform-skipped is the one host-dependent reason — interpolate at call time
    platform-skipped) printf 'dependency not applicable on %s' "${HOST_PLATFORM:-host}" ;;
    *)                printf '%s' "${_UCC_STATUS_DEP_REASON[$1]:-dep in unknown state}" ;;
  esac
}

_ucc_status_counter() {
  printf '%s' "${_UCC_STATUS_COUNTER[$1]:-}"
}
