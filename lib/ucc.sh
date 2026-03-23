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
#  Structured artifacts (machine-consumable JSONL)
#  Written to UCC_DECLARATION_FILE and UCC_RESULT_FILE when set.
#  Each ucc_target appends one declaration line and one result line.
#  Fields comply with UCC/2.0 canonical message shapes.
# ============================================================
_ucc_jstr() { printf '%s' "$*" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

_ucc_now_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "1970-01-01T00:00:00Z"
}

_ucc_target_id() {
  printf '%s' "$1" | tr -cs '[:alnum:]' '-' | sed 's/^-*//; s/-*$//' | tr '[:upper:]' '[:lower:]'
}

_ucc_is_json_obj() {
  python3 - "$1" <<'PY' 2>/dev/null
import json, sys
try:
    value = json.loads(sys.argv[1])
    sys.exit(0 if isinstance(value, dict) else 1)
except Exception:
    sys.exit(1)
PY
}

_ucc_state_obj() {
  if _ucc_is_json_obj "$1"; then
    printf '%s' "$1"
  else
    printf '{"state":"%s"}' "$(_ucc_jstr "$1")"
  fi
}

_ucc_diff_obj() {
  local before="$1" after="$2"
  if _ucc_is_json_obj "$before" || _ucc_is_json_obj "$after"; then
    if _ucc_json_equal "$before" "$after"; then
      printf '{}'
    else
      printf '{"before":%s,"after":%s}' "$(_ucc_state_obj "$before")" "$(_ucc_state_obj "$after")"
    fi
  else
    if [[ "$before" == "$after" ]]; then
      printf '{}'
    else
      printf '{"state":{"before":"%s","after":"%s"}}' \
        "$(_ucc_jstr "$before")" "$(_ucc_jstr "$after")"
    fi
  fi
}

_ucc_json_equal() {
  python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, sys
try:
    left = json.loads(sys.argv[1])
    right = json.loads(sys.argv[2])
    sys.exit(0 if left == right else 1)
except Exception:
    sys.exit(1)
PY
}

_ucc_display_state() {
  if _ucc_is_json_obj "$1"; then
    python3 - "$1" <<'PY' 2>/dev/null
import json, sys
state = json.loads(sys.argv[1])
fields = []
for key in ("installation_state", "runtime_state", "health_state", "admin_state", "dependency_state"):
    value = state.get(key)
    if value:
        fields.append(f"{key}={value}")
print(" ".join(fields) if fields else json.dumps(state, separators=(",", ":")))
PY
  else
    printf '%s' "$1"
  fi
}

ucc_asm_state() {
  local installation="" runtime="" health="" admin="" dependency=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --installation) installation="$2"; shift 2 ;;
      --runtime) runtime="$2"; shift 2 ;;
      --health) health="$2"; shift 2 ;;
      --admin) admin="$2"; shift 2 ;;
      --dependencies) dependency="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  printf '{"installation_state":"%s","runtime_state":"%s","health_state":"%s","admin_state":"%s","dependency_state":"%s"}' \
    "$(_ucc_jstr "$installation")" \
    "$(_ucc_jstr "$runtime")" \
    "$(_ucc_jstr "$health")" \
    "$(_ucc_jstr "$admin")" \
    "$(_ucc_jstr "$dependency")"
}

_ucc_meta_in() {
  local id="$1" ts="$2"
  printf '"meta":{"contract":"ucc","version":"2.0","id":"%s","timestamp":"%s","scope":"operation"}' \
    "$(_ucc_jstr "$id")" "$(_ucc_jstr "$ts")"
}

_ucc_meta_out() {
  local id="$1" duration_ms="$2" ts
  ts=$(_ucc_now_utc)
  printf '"meta":{"contract":"ucc","version":"2.0","id":"%s","timestamp":"%s","duration_ms":%s,"scope":"operation"}' \
    "$(_ucc_jstr "$id")" "$(_ucc_jstr "$ts")" "${duration_ms:-0}"
}

_ucc_record_file() {
  local path="$1" payload="$2"
  [[ -z "$path" ]] && return 0
  printf '%s\n' "$payload" >> "$path" 2>/dev/null || true
}

_ucc_record_declaration() {
  local id="$1" name="$2" desired="$3" mode="$4" ts="$5"
  local payload
  payload="{$(_ucc_meta_in "$id" "$ts"),\"declaration\":{\"mode\":\"$(_ucc_jstr "$mode")\",\"target\":\"$(_ucc_jstr "$name")\",\"desired_state\":$(_ucc_state_obj "$desired")}}"
  _ucc_record_file "${UCC_DECLARATION_FILE:-}" "$payload"
}

_ucc_record_result() {
  local id="$1" duration_ms="$2" observe_json="$3" result_json="$4"
  local payload
  payload="{$(_ucc_meta_out "$id" "$duration_ms"),\"observe\":${observe_json},\"result\":${result_json}}"
  _ucc_record_file "${UCC_RESULT_FILE:-}" "$payload"
}

_ucc_duration_ms() {
  local started_at="$1" now
  now=$(date +%s 2>/dev/null || echo 0)
  echo $(( (now - started_at) * 1000 ))
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

  local started_at declaration_ts mode target_id msg_id duration_ms
  started_at=$(date +%s 2>/dev/null || echo 0)
  declaration_ts=$(_ucc_now_utc)
  mode="apply"
  [[ "$UCC_DRY_RUN" == "1" ]] && mode="dry_run"
  target_id=$(_ucc_target_id "$name")
  msg_id="${UCC_CORRELATION_ID:-run}-${target_id}"
  _ucc_record_declaration "$msg_id" "$name" "$desired" "$mode" "$declaration_ts"

  # Step 1 – Observe current state
  local observed obs_exit
  observed=$($observe_fn 2>/dev/null)
  obs_exit=$?

  # observation=failed: observe function crashed (non-zero exit)
  if [[ $obs_exit -ne 0 ]]; then
    printf '  %-46s  obs-failed  (observe fn exited non-zero)\n' "$name"
    _UCC_FAILED=$(( _UCC_FAILED + 1 ))
    duration_ms=$(_ucc_duration_ms "$started_at")
    _ucc_record_result "$msg_id" "$duration_ms" "{}" \
      "{\"observation\":\"failed\",\"message\":\"observe function exited non-zero\"}"
    return 0
  fi

  # observation=indeterminate: observe ran (exit 0) but produced no usable state
  if [[ -z "$observed" ]]; then
    printf '  %-46s  indeterminate  (observe returned no state)\n' "$name"
    _UCC_FAILED=$(( _UCC_FAILED + 1 ))
    duration_ms=$(_ucc_duration_ms "$started_at")
    _ucc_record_result "$msg_id" "$duration_ms" "{}" \
      "{\"observation\":\"indeterminate\",\"message\":\"observe returned empty state\"}"
    return 0
  fi

  log_debug "observed=\"$observed\" desired=\"$desired\" mode=$UCC_MODE"

  # Helper: is observed state satisfying desired?
  # @present wildcard: any value other than "absent" or "outdated" counts as present
  _ucc_satisfied() {
    local obs="$1" des="$2"
    if _ucc_is_json_obj "$obs" || _ucc_is_json_obj "$des"; then
      _ucc_json_equal "$obs" "$des" && return 0
      return 1
    fi
    [[ "$obs" == "$des" ]] && return 0
    [[ "$des" == "@present" && "$obs" != "absent" && "$obs" != "outdated" ]] && return 0
    return 1
  }

  # Step 3 – Diff: is observed state == desired?
  if _ucc_satisfied "$observed" "$desired"; then

    if [[ "$UCC_MODE" == "update" && -n "$update_fn" ]]; then
      # Update mode: run upgrade even when state already matches
      if [[ "$UCC_DRY_RUN" == "1" ]]; then
        printf '  %-46s  dry-run  state="%s"  (update skipped)\n' "$name" "$(_ucc_display_state "$observed")"
        duration_ms=$(_ucc_duration_ms "$started_at")
        _ucc_record_result "$msg_id" "$duration_ms" \
          "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":{}}" \
          "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"dry_run\",\"message\":\"update transition not applied due to dry-run mode\"}"
        return 0
      fi
      if $update_fn; then
        local verified ver_exit
        verified=$($observe_fn 2>/dev/null)
        ver_exit=$?
        if [[ $ver_exit -eq 0 ]] && _ucc_satisfied "$verified" "$desired"; then
          printf '  %-46s  updated  "%s" → "%s"\n' "$name" "$(_ucc_display_state "$observed")" "$(_ucc_display_state "$verified")"
          _UCC_CHANGED=$(( _UCC_CHANGED + 1 ))
          duration_ms=$(_ucc_duration_ms "$started_at")
          _ucc_record_result "$msg_id" "$duration_ms" \
            "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$verified"),\"observed_after\":$(_ucc_state_obj "$verified")}" \
            "{\"observation\":\"ok\",\"outcome\":\"changed\",\"completion\":\"complete\",\"proof\":{\"change\":\"update_applied\"}}"
        else
          printf '  %-46s  FAILED — verify after update: "%s"\n' "$name" "$(_ucc_display_state "${verified:-?}")"
          _UCC_FAILED=$(( _UCC_FAILED + 1 ))
          duration_ms=$(_ucc_duration_ms "$started_at")
          if [[ $ver_exit -eq 0 && -n "$verified" ]]; then
            _ucc_record_result "$msg_id" "$duration_ms" \
              "{}" \
              "{\"observation\":\"failed\",\"message\":\"post-update verify did not reach desired state\"}"
          else
            _ucc_record_result "$msg_id" "$duration_ms" \
              "{}" \
              "{\"observation\":\"failed\",\"message\":\"post-update verify did not reach desired state\"}"
          fi
        fi
      else
        printf '  %-46s  FAILED — update error  state="%s"\n' "$name" "$(_ucc_display_state "$observed")"
        _UCC_FAILED=$(( _UCC_FAILED + 1 ))
        duration_ms=$(_ucc_duration_ms "$started_at")
        _ucc_record_result "$msg_id" "$duration_ms" \
          "{}" \
          "{\"observation\":\"failed\",\"message\":\"update function failed\"}"
      fi
    else
      # Already at desired state
      printf '  %-46s  ok  state="%s"\n' "$name" "$(_ucc_display_state "$observed")"
      _UCC_CONVERGED=$(( _UCC_CONVERGED + 1 ))
      duration_ms=$(_ucc_duration_ms "$started_at")
      _ucc_record_result "$msg_id" "$duration_ms" \
        "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":{}}" \
        "{\"observation\":\"ok\",\"outcome\":\"converged\"}"
    fi
    return 0
  fi

  # Step 4: Apply transition
  if [[ "$UCC_DRY_RUN" == "1" ]]; then
    printf '  %-46s  dry-run  "%s" → "%s"\n' "$name" "$(_ucc_display_state "$observed")" "$(_ucc_display_state "$desired")"
    duration_ms=$(_ucc_duration_ms "$started_at")
    _ucc_record_result "$msg_id" "$duration_ms" \
      "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$desired")}" \
      "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"dry_run\",\"message\":\"transition not applied due to dry-run mode\"}"
    return 0
  fi

  if [[ -z "$install_fn" ]]; then
    printf '  %-46s  no-install (policy)  "%s" → "%s"\n' "$name" "$(_ucc_display_state "$observed")" "$(_ucc_display_state "$desired")"
    duration_ms=$(_ucc_duration_ms "$started_at")
    _ucc_record_result "$msg_id" "$duration_ms" \
      "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$desired")}" \
      "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"transition not applied - no install function declared\"}"
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
      printf '  %-46s  %s  "%s" → "%s"\n' "$name" "$action_label" "$(_ucc_display_state "$observed")" "$(_ucc_display_state "$verified")"
      _UCC_CHANGED=$(( _UCC_CHANGED + 1 ))
      duration_ms=$(_ucc_duration_ms "$started_at")
      _ucc_record_result "$msg_id" "$duration_ms" \
        "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$verified"),\"observed_after\":$(_ucc_state_obj "$verified")}" \
        "{\"observation\":\"ok\",\"outcome\":\"changed\",\"completion\":\"complete\",\"proof\":{\"change\":\"verify_pass\"}}"
    else
      printf '  %-46s  FAILED — verify after install: "%s"\n' "$name" "$(_ucc_display_state "${verified:-?}")"
      _UCC_FAILED=$(( _UCC_FAILED + 1 ))
      duration_ms=$(_ucc_duration_ms "$started_at")
      if [[ $ver_exit -eq 0 && -n "$verified" ]]; then
        _ucc_record_result "$msg_id" "$duration_ms" \
          "{}" \
          "{\"observation\":\"failed\",\"message\":\"post-install verify did not reach desired state\"}"
      else
        _ucc_record_result "$msg_id" "$duration_ms" \
          "{}" \
          "{\"observation\":\"failed\",\"message\":\"post-install verify did not reach desired state\"}"
      fi
    fi
  else
    printf '  %-46s  FAILED — install error  was="%s"\n' "$name" "$(_ucc_display_state "$observed")"
    _UCC_FAILED=$(( _UCC_FAILED + 1 ))
    duration_ms=$(_ucc_duration_ms "$started_at")
    _ucc_record_result "$msg_id" "$duration_ms" \
      "{}" \
      "{\"observation\":\"failed\",\"message\":\"install function failed\"}"
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
