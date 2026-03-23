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
export UCC_CORRELATION_ID=${UCC_CORRELATION_ID:-$(uuidgen 2>/dev/null || date +%s%N)}

# Per-component counters (reset in each subshell)
_UCC_CONVERGED=0
_UCC_CHANGED=0
_UCC_FAILED=0

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
  local pkg="$1" ver
  brew_is_installed "$pkg" || { echo "absent"; return; }
  if [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" == "always-upgrade" ]]; then
    _brew_refresh_if_stale
    _brew_is_outdated "$pkg" && { echo "outdated"; return; }
  fi
  ver=$(brew list --versions "$pkg" 2>/dev/null | awk '{print $NF}')
  echo "${ver:-present}"
}

brew_cask_observe() {
  local pkg="$1" ver
  brew_cask_is_installed "$pkg" || { echo "absent"; return; }
  if [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" == "always-upgrade" ]]; then
    _brew_refresh_if_stale
    _brew_cask_is_outdated "$pkg" && { echo "outdated"; return; }
  fi
  ver=$(brew list --cask --versions "$pkg" 2>/dev/null | awk '{print $NF}')
  echo "${ver:-present}"
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
#  Convenience target helpers — eliminate boilerplate for common patterns
# ============================================================

# ucc_brew_target <target-name> <brew-pkg>
# Standard brew formula: install=brew install, update=brew upgrade
ucc_brew_target() {
  local tname="$1" pkg="$2"
  local fn; fn="${pkg//[^a-zA-Z0-9]/_}"
  eval "_ubt_obs_${fn}() { brew_observe '${pkg}'; }"
  eval "_ubt_ins_${fn}() { brew_install  '${pkg}'; }"
  eval "_ubt_upd_${fn}() { brew_upgrade  '${pkg}'; }"
  ucc_target --name "$tname" --observe "_ubt_obs_${fn}" --desired "@present" \
             --install "_ubt_ins_${fn}" --update "_ubt_upd_${fn}"
}

# ucc_brew_cask_target <target-name> <cask-pkg>
# Standard brew cask: install=brew install --cask, update=brew upgrade --cask
ucc_brew_cask_target() {
  local tname="$1" pkg="$2"
  local fn; fn="${pkg//[^a-zA-Z0-9]/_}"
  eval "_ubct_obs_${fn}() { brew_cask_observe '${pkg}'; }"
  eval "_ubct_ins_${fn}() { brew_cask_install '${pkg}'; }"
  eval "_ubct_upd_${fn}() { brew_cask_upgrade '${pkg}'; }"
  ucc_target --name "$tname" --observe "_ubct_obs_${fn}" --desired "@present" \
             --install "_ubct_ins_${fn}" --update "_ubct_upd_${fn}"
}

# ucc_npm_target <npm-pkg>
# Global npm package: observe=npm ls -g desired=current install=npm install -g update=npm update -g
ucc_npm_target() {
  local pkg="$1"
  local fn; fn="${pkg//[@\/]/_}"
  eval "_unt_obs_${fn}() { npm ls -g '${pkg}' --depth=0 --json 2>/dev/null | python3 -c \"import sys,json; d=json.load(sys.stdin); deps=d.get('dependencies',{}); k=next(iter(deps),''); print(deps[k].get('version','present') if k else 'absent')\" 2>/dev/null || echo 'absent'; }"
  eval "_unt_ins_${fn}() { ucc_run npm install -g '${pkg}'; }"
  eval "_unt_upd_${fn}() { ucc_run npm update  -g '${pkg}'; }"
  ucc_target --name "npm-global-${pkg}" --observe "_unt_obs_${fn}" --desired "@present" \
             --install "_unt_ins_${fn}" --update "_unt_upd_${fn}"
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
    printf '  %-46s  obs-failed  (observe fn exited non-zero)\n' "$name"
    _UCC_FAILED=$(( _UCC_FAILED + 1 ))
    _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"failed\",\"message\":\"observe function exited non-zero\"}}"
    return 0
  fi

  # observation=indeterminate: observe ran (exit 0) but produced no usable state
  if [[ -z "$observed" ]]; then
    printf '  %-46s  indeterminate  (observe returned no state)\n' "$name"
    _UCC_FAILED=$(( _UCC_FAILED + 1 ))
    _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"indeterminate\",\"message\":\"observe returned empty state\"}}"
    return 0
  fi

  log_debug "observed=\"$observed\" desired=\"$desired\" mode=$UCC_MODE"

  # Helper: is observed state satisfying desired?
  # @present wildcard: any value other than "absent" or "outdated" counts as present
  _ucc_satisfied() {
    local obs="$1" des="$2"
    [[ "$obs" == "$des" ]] && return 0
    [[ "$des" == "@present" && "$obs" != "absent" && "$obs" != "outdated" ]] && return 0
    return 1
  }

  # Step 3 – Diff: is observed state == desired?
  if _ucc_satisfied "$observed" "$desired"; then

    if [[ "$UCC_MODE" == "update" && -n "$update_fn" ]]; then
      # Update mode: run upgrade even when state already matches
      if [[ "$UCC_DRY_RUN" == "1" ]]; then
        printf '  %-46s  dry-run  state="%s"  (update skipped)\n' "$name" "$observed"
        _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"dry_run\",\"message\":\"transition not applied due to dry-run mode\",\"observed_before\":\"$(_ucc_jstr "$observed")\"}}"
        return 0
      fi
      if $update_fn; then
        printf '  %-46s  updated  state="%s"\n' "$name" "$observed"
        _UCC_CHANGED=$(( _UCC_CHANGED + 1 ))
        _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"changed\",\"completion\":\"complete\",\"proof\":\"update_applied\",\"observed_before\":\"$(_ucc_jstr "$observed")\",\"observed_after\":\"$(_ucc_jstr "$desired")\"}}"
      else
        printf '  %-46s  FAILED — update error  state="%s"\n' "$name" "$observed"
        _UCC_FAILED=$(( _UCC_FAILED + 1 ))
        _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"failed\",\"failure_class\":\"retryable\",\"message\":\"update function failed\",\"observed_before\":\"$(_ucc_jstr "$observed")\"}}"
      fi
    else
      # Already at desired state
      printf '  %-46s  ok  state="%s"\n' "$name" "$observed"
      _UCC_CONVERGED=$(( _UCC_CONVERGED + 1 ))
      _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"converged\",\"observed_before\":\"$(_ucc_jstr "$observed")\"}}"
    fi
    return 0
  fi

  # Step 4: Apply transition
  if [[ "$UCC_DRY_RUN" == "1" ]]; then
    printf '  %-46s  dry-run  "%s" → "%s"\n' "$name" "$observed" "$desired"
    _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"dry_run\",\"message\":\"transition not applied due to dry-run mode\",\"observed_before\":\"$(_ucc_jstr "$observed")\"}}"
    return 0
  fi

  if [[ -z "$install_fn" ]]; then
    printf '  %-46s  no-install (policy)  "%s" → "%s"\n' "$name" "$observed" "$desired"
    _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"transition not applied — no install function declared\",\"observed_before\":\"$(_ucc_jstr "$observed")\"}}"
    return 0
  fi

  # Route outdated → update_fn (upgrade), absent → install_fn (fresh install)
  local action_fn="$install_fn"
  local action_label="installed"
  if [[ "$observed" == "outdated" && -n "$update_fn" ]]; then
    action_fn="$update_fn"
    action_label="upgraded"
  fi

  if $action_fn; then
    _BREW_OUTDATED_STALE=1  # invalidate cache so verify sees post-upgrade state
    # Step 5 – Verify: re-observe after transition
    local verified ver_exit
    verified=$($observe_fn 2>/dev/null)
    ver_exit=$?
    log_debug "post-install observed=\"$verified\""
    if [[ $ver_exit -eq 0 ]] && _ucc_satisfied "$verified" "$desired"; then
      printf '  %-46s  %s  "%s" → "%s"\n' "$name" "$action_label" "$observed" "$verified"
      _UCC_CHANGED=$(( _UCC_CHANGED + 1 ))
      _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"changed\",\"completion\":\"complete\",\"proof\":\"verify_pass\",\"observed_before\":\"$(_ucc_jstr "$observed")\",\"observed_after\":\"$(_ucc_jstr "$verified")\"}}"
    else
      printf '  %-46s  FAILED — verify after install: "%s"\n' "$name" "${verified:-?}"
      _UCC_FAILED=$(( _UCC_FAILED + 1 ))
      _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"failed\",\"failure_class\":\"retryable\",\"message\":\"post-install verify did not reach desired state\",\"observed_before\":\"$(_ucc_jstr "$observed")\",\"observed_after\":\"$(_ucc_jstr "${verified:-}")\"}}"
    fi
  else
    printf '  %-46s  FAILED — install error  was="%s"\n' "$name" "$observed"
    _UCC_FAILED=$(( _UCC_FAILED + 1 ))
    _ucc_record "{$(_ucc_meta),\"target\":\"$(_ucc_jstr "$name")\",\"result\":{\"observation\":\"ok\",\"outcome\":\"failed\",\"failure_class\":\"retryable\",\"message\":\"install function failed\",\"observed_before\":\"$(_ucc_jstr "$observed")\"}}"
  fi
}

# ============================================================
#  ucc_summary — write per-component counts to summary file
# ============================================================
ucc_summary() {
  local comp="${1:-}"
  if [[ -n "${UCC_SUMMARY_FILE:-}" && -n "$comp" ]]; then
    printf '%s|%d|%d|%d\n' "$comp" "$_UCC_CONVERGED" "$_UCC_CHANGED" "$_UCC_FAILED" \
      >> "$UCC_SUMMARY_FILE" 2>/dev/null || true
  fi
}
