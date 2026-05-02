#!/usr/bin/env bash
# lib/ucc_status.sh — single source of truth for target-status semantics.
#
# A "target status" is the value recorded by _ucc_record_target_status that
# downstream consumers (deps line, services list, cascade logic, summary
# counters) read to decide what to do.
#
# Each status carries up to 5 attributes. They live in 5 sibling case
# statements below — one per attribute, all in this one file. Adding a new
# status means adding one row to each relevant case (anywhere from 1 to 5
# entries depending on which decisions it participates in). Sites query
# via the helpers — none of them hardcode status names.
#
# bash 3.2 compatibility: this file deliberately avoids `declare -A`
# (assoc arrays are bash 4+). The case-statement form is uglier than
# associative-array literals but works on macOS's stock /bin/bash.

# ── Reachable: would this target's endpoint be answering on its port? ─────────
# Used by lib/summary.sh:_target_endpoint_reachable to decide which entries
# go into the "Services" list in the run footer. A status not listed here
# is treated as unreachable (failed/skipped/disabled etc.).
_ucc_status_is_reachable() {
  case "$1" in
    ok|unchanged|changed|updated|installed|oracle-pass|warn|satisfied-external) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Hide from deps line ──────────────────────────────────────────────────────
# Used by lib/ucc_asm.sh:_ucc_dep_status_hidden to decide which dep statuses
# get suppressed from a dependent's `deps:` evidence line.
# Two reasons a parent's status is uninteresting in a dependent's view:
#   - Structural skip (requires-skipped/platform-skipped/disabled/skipped):
#     dep was filtered out for a reason the operator can't act on.
#   - Soft-policy / external (warn/policy/satisfied-external): dep ran or
#     was present externally; propagating these to every dependent's line
#     just suggests degradation that isn't there.
_ucc_status_hide_from_deps() {
  case "$1" in
    skipped|requires-skipped|platform-skipped|disabled|satisfied-external|warn|policy) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Cascade action when a dep has this status ────────────────────────────────
# Used by lib/ucc_targets.sh:_ucc_check_deps_recursive to decide what to do
# when checking a dependent's deps:
#   dep-fail  → real failure, dependent should NOT run; emit [dep-fail], rc=1
#   skip      → cascade clean skip; dependent recorded as "skipped", rc=2
#   continue  → dep ran fine OR is irrelevant on this host; dependent proceeds
#               (default for any status not listed here)
#
# Important asymmetries:
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
_ucc_status_cascade_action() {
  case "$1" in
    failed)                                  printf 'dep-fail' ;;
    skipped|platform-skipped|policy)         printf 'skip' ;;
    *)                                       printf 'continue' ;;
  esac
}

# ── Reason text shown on the cascade-skip / dep-fail line ────────────────────
# `_ucc_check_deps_recursive` formats the [skip]/[dep-fail] line as
# "<reason>: <dep>". The reason for `platform-skipped` interpolates
# HOST_PLATFORM at call time, which is why this is a function (not a
# table) — call-time eval of $HOST_PLATFORM matters.
_ucc_status_dep_reason() {
  case "$1" in
    failed)           printf 'dependency failed this run' ;;
    skipped)          printf 'dependency was skipped' ;;
    platform-skipped) printf 'dependency not applicable on %s' "${HOST_PLATFORM:-host}" ;;
    policy)           printf 'dependency requires admin' ;;
    requires-skipped) printf 'dependency was filtered out' ;;
    disabled)         printf 'dependency was disabled' ;;
    *)                printf 'dep in unknown state (%s)' "$1" ;;
  esac
}

# ── Counter to bump in _ucc_record_outcome ───────────────────────────────────
# Maps target_status → _UCC_<NAME> counter name. Used as fallback when
# the caller of _ucc_record_outcome doesn't pass an explicit counter
# argument (the explicit-arg path still works, e.g. for "changed" →
# CHANGED even though target_status="ok"). Empty output = don't bump
# any counter.
_ucc_status_counter() {
  case "$1" in
    ok|unchanged|oracle-pass|satisfied-external)                       printf 'CONVERGED' ;;
    changed|updated|installed)                                          printf 'CHANGED' ;;
    failed|dep-fail)                                                    printf 'FAILED' ;;
    skipped|requires-skipped|platform-skipped|disabled)                 printf 'SKIPPED' ;;
    policy|warn)                                                        printf 'POLICY' ;;
    *)                                                                  printf '' ;;
  esac
}
