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
#  Canonical message structure used here:
#    declaration: meta + declaration
#    result     : meta + observe + result
#    observe.observed_before / observe.diff / observe.observed_after
#    result.proof is emitted as an object when outcome=changed
# ============================================================

_UCC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/ucc_log.sh
source "${_UCC_LIB_DIR}/ucc_log.sh"
# shellcheck source=lib/ucc_brew.sh
source "${_UCC_LIB_DIR}/ucc_brew.sh"
# shellcheck source=lib/ucc_asm.sh
source "${_UCC_LIB_DIR}/ucc_asm.sh"
# shellcheck source=lib/ucc_artifacts.sh
source "${_UCC_LIB_DIR}/ucc_artifacts.sh"
# shellcheck source=lib/ucc_targets.sh
source "${_UCC_LIB_DIR}/ucc_targets.sh"
# shellcheck source=lib/ucc_drivers.sh
source "${_UCC_LIB_DIR}/ucc_drivers.sh"
