#!/usr/bin/env bash
# lib/ucc_log.sh — Runtime context variables and structured logging
# Sourced by lib/ucc.sh

UCC_DRY_RUN=${UCC_DRY_RUN:-0}   # 1 = dry-run (inhibitor=dry_run)
UCC_MODE=${UCC_MODE:-install}    # install | update
UCC_DEBUG=${UCC_DEBUG:-0}        # 1 = show DEBUG lines
export UCC_CORRELATION_ID=${UCC_CORRELATION_ID:-$(uuidgen 2>/dev/null || date +%s%N)}

# Per-component counters (reset in each subshell)
_UCC_CONVERGED=0
_UCC_CHANGED=0
_UCC_FAILED=0

_ts() { date '+%H:%M:%S'; }
log_info()   { echo "  $*"; }
log_debug()  { [[ "$UCC_DEBUG" == "1" ]] && echo "$(_ts) [DEBUG]  $*" || true; }
log_warn()   { echo "$(_ts) [WARN]   $*" >&2; }
log_error()  { echo "$(_ts) [ERROR]  $*" >&2; exit 1; }

# ── Exit code conventions (UCC) ───────────────────────────────────────────────
# Driver actions (_ucc_driver_<kind>_action) and runtime helpers MUST return
# one of these codes — anything else triggers a warning + treat-as-fail.
#
#   0    ✓ success — observed state changed to desired
#   1    ✗ failure — retryable, scheduler emits [fail]
#   2    ✗ recover level not supported (recover() only)
#   124  ⚠ warn    — constraint-bound / external daemon / can't apply now,
#                    but not a hard fail. Scheduler emits [warn] and skips
#                    verify-after-update. Examples: pip pkgs already at
#                    constraint-max version, custom-daemon timeout waiting
#                    for externally-managed daemon to appear.
#   125  ⊘ policy  — admin (sudo) required, no ticket cached. Scheduler
#                    emits [policy] and records "admin required" inhibitor.
#
# See _ucc_run_yaml_action in lib/ucc_targets.sh for the dispatch + guard.
