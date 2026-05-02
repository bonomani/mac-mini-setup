#!/usr/bin/env bash
# lib/ucc_targets.sh — Target lifecycle (ucc_target), convenience helpers, and summary
# Sourced by lib/ucc.sh

# ── YAML evidence executor ─────────────────────────────────────────────────────

# ucc_eval_evidence_from_yaml <cfg_dir> <yaml> <target>
# Execute evidence snippets declared in the target's YAML evidence: block.
# Outputs: key=value  key=value  (two-space separated, omits empty values)
# Top-level YAML scalar ${vars} are pre-substituted by read_config.py.
ucc_eval_evidence_from_yaml() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local _first=1 _key _cmd _val
  local fn="${target//[^a-zA-Z0-9]/_}"
  local _cached_var="_UCC_OBS_CACHED_${fn}"
  local _ev_var="_UCC_OBS_EVIDENCE_${fn}"

  if _ucc_driver_evidence "$cfg_dir" "$yaml" "$target"; then
    return
  fi

  while IFS=$'\t' read -r -d '' _key _cmd; do
    [[ -z "$_key" || -z "$_cmd" ]] && continue
    _val=$(_ucc_eval_yaml_expr "$cfg_dir" "$yaml" "$target" "$_cmd" 2>/dev/null || true)
    [[ -z "$_val" ]] && continue
    [[ $_first -eq 0 ]] && printf '  '
    printf '%s=%s' "$_key" "$_val"
    _first=0
  done < <(
    if [[ -n "${!_cached_var:-}" ]]; then
      [[ -n "${!_ev_var:-}" ]] && printf '%s' "${!_ev_var}" | base64 -d
    else
      "${UCC_FRAMEWORK_PYTHON:-python3}" "$cfg_dir/tools/read_config.py" --evidence "$yaml" "$target" 2>/dev/null
    fi
  )
}

# YAML target-field reader + user-override layer (extracted 2026-04-28).
# shellcheck source=lib/ucc_targets_yaml.sh
source "${BASH_SOURCE[0]%/*}/ucc_targets_yaml.sh"
# Brew runtime formula target subsystem (extracted 2026-04-28).
# shellcheck source=lib/ucc_targets_brew_runtime.sh
source "${BASH_SOURCE[0]%/*}/ucc_targets_brew_runtime.sh"
# Capability + parametric target factories (extracted 2026-04-29).
# shellcheck source=lib/ucc_targets_nonruntime.sh
source "${BASH_SOURCE[0]%/*}/ucc_targets_nonruntime.sh"
# Runtime target factory (extracted 2026-04-29).
# shellcheck source=lib/ucc_targets_runtime.sh
source "${BASH_SOURCE[0]%/*}/ucc_targets_runtime.sh"
# Display-name + per-target line rendering (extracted 2026-04-29).
# shellcheck source=lib/ucc_targets_display.sh
source "${BASH_SOURCE[0]%/*}/ucc_targets_display.sh"

_ucc_observed_prefers_update_action() {
  local observed="$1"
  [[ "$observed" == "outdated" || "$observed" == "needs-update" ]] && return 0
  _ucc_is_json_obj "$observed" || return 1
  # Runtime targets can be Running+Outdated (externally-managed daemon needs
  # upgrade, e.g. ollama 0.20.6 vs github 0.20.7). Update action is the right
  # choice — the daemon is up, we just want the newer binary.
  if [[ "$observed" == *'"runtime_state":"Running"'* && "$observed" == *'"health_state":"Outdated"'* ]]; then
    return 0
  fi
  [[ "$observed" == *'"runtime_state":"Stopped"'* ]] || return 1
  # Both Degraded (drift/broken) and Outdated (new version available) trigger
  # the update action when the target is already installed/configured.
  [[ "$observed" == *'"health_state":"Degraded"'* || "$observed" == *'"health_state":"Outdated"'* ]] || return 1
  if [[ "$observed" == *'"installation_state":"Installed"'* ]]; then
    return 0
  fi
  if [[ "$observed" == *'"installation_state":"Configured"'* && "$observed" == *'"config_value":'* ]]; then
    return 0
  fi
  return 1
}

# ── Convenience target helpers ────────────────────────────────────────────────


_ucc_observe_yaml_simple_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local target_type profile configured_cmd observe_cmd state_model success_raw failure_raw raw_state
  local fn="${target//[^a-zA-Z0-9]/_}"
  local _cached_var="_UCC_OBS_CACHED_${fn}"

  if [[ -n "${!_cached_var:-}" ]]; then
    local _v
    _v="_UCC_OBS_TYPE_${fn}";    target_type="${!_v}"
    _v="_UCC_OBS_ORACLE_${fn}";  configured_cmd="${!_v}"
    _v="_UCC_OBS_CMD_${fn}";     observe_cmd="${!_v}"
    _v="_UCC_OBS_MODEL_${fn}";   state_model="${!_v}"
    _v="_UCC_OBS_SUCCESS_${fn}"; success_raw="${!_v}"
    _v="_UCC_OBS_FAILURE_${fn}"; failure_raw="${!_v}"
  else
    while IFS=$'\t' read -r -d '' key value; do
      case "$key" in
        profile)           profile="$value" ;;
        type)              target_type="$value" ;;
        oracle.configured) configured_cmd="$value" ;;
        observe_cmd)       observe_cmd="$value" ;;
        state_model)       state_model="$value" ;;
        observe_success)   success_raw="$value" ;;
        observe_failure)   failure_raw="$value" ;;
      esac
    done < <(_ucc_yaml_target_get_many "$cfg_dir" "$yaml" "$target" profile type oracle.configured observe_cmd state_model observe_success observe_failure)
  fi
  [[ -n "$target_type" ]] || target_type="config"
  # Derive state_model from (profile, type) when omitted:
  #   type=package                         → state_model=package
  #   type=config, profile=parametric      → state_model=parametric
  #   type=config, profile≠parametric      → state_model=config
  # For runtime/capability/precondition, fall back to target_type (legacy behavior).
  if [[ -z "$state_model" ]]; then
    case "$target_type" in
      package) state_model="package" ;;
      config)
        if [[ "$profile" == "parametric" ]]; then
          state_model="parametric"
        else
          state_model="config"
        fi ;;
      *) state_model="$target_type" ;;
    esac
  fi

  local driver_raw
  if driver_raw="$(_ucc_driver_observe "$cfg_dir" "$yaml" "$target")"; then
    [[ -n "$driver_raw" ]] || driver_raw="absent"
    case "$state_model" in
      package) ucc_asm_package_state "$driver_raw" ;;
      *)       ucc_asm_config_state  "$driver_raw" ;;
    esac
    return
  fi

  if [[ -n "$observe_cmd" ]]; then
    raw_state="$(_ucc_eval_yaml_scalar_cmd "$cfg_dir" "$yaml" "$target" "$observe_cmd")"
    [[ -n "$raw_state" ]] || raw_state="absent"
    case "$state_model" in
      package)
        ucc_asm_package_state "$raw_state"
        ;;
      *)
        ucc_asm_config_state "$raw_state"
        ;;
    esac
    return
  fi

  case "$state_model" in
    package)
      [[ -n "$success_raw" ]] || success_raw="present"
      [[ -n "$failure_raw" ]] || failure_raw="absent"
      ;;
    *)
      [[ -n "$success_raw" ]] || success_raw="configured"
      [[ -n "$failure_raw" ]] || failure_raw="absent"
      ;;
  esac

  if [[ -n "$configured_cmd" ]] && _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$configured_cmd"; then
    raw_state="$success_raw"
  else
    raw_state="$failure_raw"
  fi

  case "$state_model" in
    package)
      ucc_asm_package_state "$raw_state"
      ;;
    *)
      ucc_asm_config_state "$raw_state"
      ;;
  esac
}

_ucc_run_yaml_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action_key="$4"
  local cmd

  # Check admin_required BEFORE any driver or YAML action dispatch.
  # Return 125 (policy) so ucc_target shows [policy] instead of [fail].
  if _ucc_yaml_target_admin_required "$cfg_dir" "$yaml" "$target" "$action_key"; then
    if sudo_not_available; then
      log_warn "Target '$target' requires admin privileges — skipped (no sudo ticket)"
      return 125
    fi
  fi

  if [[ "$action_key" == "install" || "$action_key" == "update" ]]; then
    local _driver_kind
    _driver_kind="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.kind")"
    if [[ -n "$_driver_kind" && "$_driver_kind" != "custom" ]]; then
      # Always propagate the driver's exit code — including 124 (warn) and
      # 125 (admin required) which the scheduler maps to [warn]/[policy]
      # instead of [fail]. Previously `&& return` swallowed non-zero codes
      # and fell through to the YAML actions block, which then returned 1
      # for drivers without explicit actions.* entries.
      local _drv_rc=0
      _ucc_driver_action "$cfg_dir" "$yaml" "$target" "$action_key" || _drv_rc=$?
      # UCC exit-code convention: 0/1/2/124/125 only (see lib/ucc_log.sh).
      # Any other code is a driver bug — log + treat as fail.
      case $_drv_rc in
        0|1|2|124|125) ;;
        *)
          log_warn "driver '$_driver_kind' returned non-conventional rc=$_drv_rc for $target/$action_key — treating as fail (rc=1). See lib/ucc_log.sh for the rc convention."
          _drv_rc=1
          ;;
      esac
      return $_drv_rc
    fi
  fi

  case "$action_key" in
    install)
      cmd="$(_ucc_yaml_target_action_get "$cfg_dir" "$yaml" "$target" "install")"
      ;;
    update)
      cmd="$(_ucc_yaml_target_action_get "$cfg_dir" "$yaml" "$target" "update")"
      ;;
    *)
      cmd="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "$action_key")"
      ;;
  esac
  [[ -n "$cmd" ]] || return 1
  _ucc_eval_yaml_expr "$cfg_dir" "$yaml" "$target" "$cmd"
}

# Return 0 if target should be skipped due to UCC_TARGET_SET filter.
# Emits a visible [skip] line so all targets are accounted for.
# UCC_TARGET_SET is always set:
#   - empty = nothing selected (skip all)
#   - populated = only targets in the set run
_UCC_EMITTED_TARGETS=""

# Evaluate a requires: condition string (comma = OR).
# Each atom: value (match), !value (negate), name>=ver (version compare).
# Returns 0 if any atom is true.
_ucc_eval_requires() {
  local requires="$1" cond
  local _host_vals="|${HOST_PLATFORM:-}|${HOST_PLATFORM_VARIANT:-}|${HOST_ARCH:-}|${HOST_OS_ID:-}|${HOST_PACKAGE_MANAGER:-}|"
  # Add fingerprint segments
  local _fp="${HOST_FINGERPRINT:-}"
  local _seg; for _seg in ${_fp//\// }; do _host_vals="${_host_vals}${_seg}|"; done

  IFS=',' read -ra _conds <<< "$requires"
  for cond in "${_conds[@]}"; do
    cond="${cond// /}"  # trim
    [[ -z "$cond" ]] && continue

    # Version comparison: name>=version, name<version, etc.
    if [[ "$cond" =~ ^(!?)([a-zA-Z][a-zA-Z0-9_-]*)(>=|<=|>|<|==|!=)(.+)$ ]]; then
      local _neg="${BASH_REMATCH[1]}" _name="${BASH_REMATCH[2]}" _op="${BASH_REMATCH[3]}" _ver="${BASH_REMATCH[4]}"
      # Extract version from HOST_OS_ID: "macos-15.4" → macos=15.4
      local _actual=""
      if [[ "${HOST_OS_ID:-}" == "${_name}-"* ]]; then
        _actual="${HOST_OS_ID#${_name}-}"
      fi
      if [[ -n "$_actual" ]]; then
        local _result=1
        # Compare as dotted version tuples (avoid pipe-to-read subshell issue)
        local _smaller; _smaller="$(printf '%s\n%s' "$_actual" "$_ver" | sort -V 2>/dev/null | head -1 || echo "$_ver")"
        case "$_op" in
          ">=") [[ "$_smaller" == "$_ver" || "$_actual" == "$_ver" ]] && _result=0 ;;
          "<=") [[ "$_smaller" == "$_actual" || "$_actual" == "$_ver" ]] && _result=0 ;;
          ">")  [[ "$_smaller" == "$_ver" && "$_actual" != "$_ver" ]] && _result=0 ;;
          "<")  [[ "$_smaller" == "$_actual" && "$_actual" != "$_ver" ]] && _result=0 ;;
          "==") [[ "$_actual" == "$_ver" ]] && _result=0 ;;
          "!=") [[ "$_actual" != "$_ver" ]] && _result=0 ;;
        esac
        [[ -n "$_neg" ]] && { [[ $_result -eq 0 ]] && _result=1 || _result=0; }
        [[ $_result -eq 0 ]] && return 0
      else
        # Name not found — atom fails (unless negated)
        [[ -n "$_neg" ]] && return 0
      fi
      continue
    fi

    # Negation: !value
    if [[ "$cond" == !* ]]; then
      [[ "$_host_vals" != *"|${cond#!}|"* ]] && return 0
      continue
    fi

    # Simple match: value
    [[ "$_host_vals" == *"|${cond}|"* ]] && return 0
  done
  return 1  # no condition matched
}

_ucc_target_filtered_out() {
  local target="$1" cfg_dir="${2:-}" yaml="${3:-}"
  # In deferred mode, emission is handled by ucc_flush_registered_targets in
  # topological order. Filter without printing here to keep output ordered.
  local _defer="${UCC_TARGET_DEFER:-0}"
  # Check if globally disabled by policy
  if [[ -n "${UCC_DISABLED_TARGETS:-}" && "${UCC_DISABLED_TARGETS}" == *"${target}|"* ]]; then
    if [[ "$_defer" != "1" ]]; then
      _UCC_EMITTED_TARGETS="${_UCC_EMITTED_TARGETS}|${target}|"
      local display_name; display_name="$(_ucc_display_name "$target")"
      printf '      [%-8s] %-40s %s\n' "disabled" "$display_name" "disabled by policy"
      _UCC_SKIPPED=$(( ${_UCC_SKIPPED:-0} + 1 ))
    fi
    return 0
  fi
  # Check requires: condition (platform/version/PM support)
  if [[ -n "$cfg_dir" && -n "$yaml" ]]; then
    local _requires; _requires="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "requires" 2>/dev/null || true)"
    if [[ -n "$_requires" ]] && ! _ucc_eval_requires "$_requires"; then
      if [[ "$_defer" != "1" ]]; then
        _UCC_EMITTED_TARGETS="${_UCC_EMITTED_TARGETS}|${target}|"
        local display_name; display_name="$(_ucc_display_name "$target")"
        printf '      [%-8s] %-40s %s\n' "skip" "$display_name" "requires: ${_requires}"
        _UCC_SKIPPED=$(( ${_UCC_SKIPPED:-0} + 1 ))
      else
        # Stash the requires: condition so flush can render the same message.
        eval "_UCC_DEFERRED_REQUIRES_$(echo "${target//[^a-zA-Z0-9]/_}")=\"\$_requires\""
      fi
      return 0
    fi
  fi
  # When UCC_TARGET_SET is unset, no filter is active — all targets run.
  # When set (even empty), only targets in the set are processed.
  if [[ -n "${UCC_TARGET_SET+x}" && "${UCC_TARGET_SET:-}" != *"${target}|"* ]]; then
    _UCC_EMITTED_TARGETS="${_UCC_EMITTED_TARGETS}|${target}|"
    # Fast mode: hide non-selected targets entirely (no observe, no output)
    if [[ "${UIC_PREF_SKIP_DISPLAY_MODE:-full}" == "fast" ]]; then
      return 0
    fi
    local display_name state=""
    display_name="$(_ucc_display_name "$target")"
    # Try to observe current state (read-only, best-effort)
    if [[ -n "$cfg_dir" && -n "$yaml" ]]; then
      # Try driver first, then fall back to YAML oracle/observe_cmd
      state="$(_ucc_driver_observe "$cfg_dir" "$yaml" "$target" 2>/dev/null || true)"
      if [[ -z "$state" ]]; then
        # Custom driver — try observe_cmd
        local _obs_cmd; _obs_cmd="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "observe_cmd" 2>/dev/null || true)"
        if [[ -n "$_obs_cmd" ]]; then
          state="$(_ucc_eval_yaml_expr "$cfg_dir" "$yaml" "$target" "$_obs_cmd" 2>/dev/null || true)"
        fi
      fi
      if [[ -z "$state" ]]; then
        # Try oracle.configured
        local _oracle; _oracle="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "oracle.configured" 2>/dev/null || true)"
        if [[ -n "$_oracle" ]]; then
          if _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$_oracle"; then
            state="configured"
          fi
        fi
      fi
      if [[ -z "$state" ]]; then
        # Try oracle.runtime
        local _rt_oracle; _rt_oracle="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "oracle.runtime" 2>/dev/null || true)"
        if [[ -n "$_rt_oracle" ]]; then
          if _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$_rt_oracle"; then
            state="running"
          else
            state="stopped"
          fi
        fi
      fi
    fi
    if [[ -n "$state" && "$state" != "absent" ]]; then
      printf '      [%-8s] %-40s %s (current: %s)\n' "skip" "$display_name" "not selected" "$state"
    else
      printf '      [%-8s] %-40s %s\n' "skip" "$display_name" "not selected"
    fi
    _UCC_SKIPPED=$(( ${_UCC_SKIPPED:-0} + 1 ))
    return 0
  fi
  return 1
}

ucc_yaml_simple_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _ucc_target_filtered_out "$target" "$cfg_dir" "$yaml" && return 0
  local fn profile install_cmd update_cmd self_updating driver_kind
  local obs_type="" obs_oracle="" obs_cmd="" obs_model="" obs_success="" obs_failure=""
  local _ev_b64=""
  fn="${target//[^a-zA-Z0-9]/_}"
  profile="configured"
  install_cmd=""
  update_cmd=""
  self_updating=""
  driver_kind=""
  while IFS=$'\t' read -r -d '' key value; do
    if [[ "$key" == "__evidence__" ]]; then _ev_b64="$value"; continue; fi
    case "$key" in
      profile)                           [[ -n "$value" ]] && profile="$value" ;;
      actions.install)                   install_cmd="$value" ;;
      actions.update)                    update_cmd="$value" ;;
      driver.self_updating) self_updating="$value" ;;
      driver.kind)                       driver_kind="$value" ;;
      type)                              obs_type="$value" ;;
      oracle.configured)                 obs_oracle="$value" ;;
      observe_cmd)                       obs_cmd="$value" ;;
      state_model)                       obs_model="$value" ;;
      observe_success)                   obs_success="$value" ;;
      observe_failure)                   obs_failure="$value" ;;
    esac
  done < <(_ucc_ytgt_source "$cfg_dir" "$yaml" "$target" \
      profile actions.install actions.update driver.self_updating driver.kind \
      type oracle.configured observe_cmd state_model observe_success observe_failure)
  [[ -z "$update_cmd" ]] && update_cmd="$install_cmd"
  # Derive state_model from (profile, type) when omitted — matches the
  # derivation in _ucc_observe_yaml_simple_target. Keeps YAML tidy by
  # letting targets skip `state_model: foo` when it's the default for
  # their (profile, type) combination.
  if [[ -z "$obs_model" ]]; then
    case "$obs_type" in
      package) obs_model="package" ;;
      config)
        if [[ "$profile" == "parametric" ]]; then obs_model="parametric"
        else obs_model="config"; fi ;;
      *) obs_model="$obs_type" ;;
    esac
  fi
  # A dispatched driver handles install/update even when actions.* are absent from YAML
  local driver_dispatched=0
  [[ -n "$driver_kind" && "$driver_kind" != "custom" ]] && driver_dispatched=1

  export "_UCC_OBS_CACHED_${fn}=1"
  export "_UCC_OBS_TYPE_${fn}=${obs_type}"
  export "_UCC_OBS_ORACLE_${fn}=${obs_oracle}"
  export "_UCC_OBS_CMD_${fn}=${obs_cmd}"
  export "_UCC_OBS_MODEL_${fn}=${obs_model}"
  export "_UCC_OBS_SUCCESS_${fn}=${obs_success}"
  export "_UCC_OBS_FAILURE_${fn}=${obs_failure}"
  export "_UCC_OBS_EVIDENCE_${fn}=${_ev_b64}"

  eval "_uyst_obs_${fn}() { _ucc_observe_yaml_simple_target '${cfg_dir}' '${yaml}' '${target}'; }"
  eval "_uyst_evd_${fn}() { ucc_eval_evidence_from_yaml '${cfg_dir}' '${yaml}' '${target}'; }"
  if [[ -n "$install_cmd" || "$driver_dispatched" == "1" ]]; then
    eval "_uyst_ins_${fn}() { _ucc_run_yaml_action '${cfg_dir}' '${yaml}' '${target}' install; }"
    eval "_uyst_upd_${fn}() { _ucc_run_yaml_action '${cfg_dir}' '${yaml}' '${target}' update; }"
  fi
  # Escalating recovery: wire _ucc_driver_recover if driver supports it
  if [[ "$driver_dispatched" == "1" ]]; then
    eval "_uyst_rec_${fn}() { _ucc_driver_recover '${cfg_dir}' '${yaml}' '${target}' \"\$1\"; }"
  fi

  local args=(--name "$target" --profile "$profile" --observe "_uyst_obs_${fn}" --evidence "_uyst_evd_${fn}")
  [[ -n "$install_cmd" || "$driver_dispatched" == "1" ]] && args+=(--install "_uyst_ins_${fn}")
  [[ -n "$install_cmd" || "$driver_dispatched" == "1" ]] && args+=(--update "_uyst_upd_${fn}")
  [[ "$driver_dispatched" == "1" ]] && args+=(--recover "_uyst_rec_${fn}")
  [[ "$self_updating" == "true" || "$self_updating" == "1" || "$self_updating" == "yes" ]] && \
    args+=(--warn-on-update-failure)
  ucc_target "${args[@]}"
}




# ── _ucc_record_outcome — shared emit+count+record for all outcome paths ───────
# Usage: _ucc_record_outcome <profile> <name> <COUNTER|""> <target_status> \
#                             <summary_status> <msg_id> <started_at> <diff_json> <result_json>
# COUNTER: CONVERGED | CHANGED | FAILED | "" (unchanged / dry-run paths)
#
# When COUNTER is "" we still bump a category counter based on
# target_status so the summary's totals match the visible status lines:
#   policy / warn → _UCC_POLICY (operator-actionable: admin required, blocked-by-policy)
#   anything else with empty COUNTER → no bump (e.g. unchanged, dry-run paths)
_ucc_record_outcome() {
  local _p="$1" _n="$2" _ctr="$3" _tst="$4" _sst="$5" _mid="$6" _sat="$7" _dif="$8" _res="$9"
  if [[ -n "$_ctr" ]]; then
    eval "_UCC_${_ctr}=\$(( _UCC_${_ctr} + 1 ))"
  else
    case "$_tst" in
      policy|warn) _UCC_POLICY=$(( ${_UCC_POLICY:-0} + 1 )) ;;
    esac
  fi
  _ucc_record_profile_summary "$_p" "$_sst"
  _ucc_record_target_status "$_n" "$_tst"
  local _dur; _dur=$(_ucc_duration_ms "$_sat")
  _ucc_record_result "$_mid" "$_dur" "$_dif" "$_res"
}

_UCC_REGISTERED_NAMES=()
_UCC_REGISTERED_ARGS=()
_UCC_REGISTERED_ENV=()

ucc_reset_registered_targets() {
  _UCC_REGISTERED_NAMES=()
  _UCC_REGISTERED_ARGS=()
  _UCC_REGISTERED_ENV=()
  # Purge _UCC_* exports from the previous component to prevent env
  # bloat. These vars are intra-component cache only — they're set by
  # ucc_yaml_*_target and read via ${!_v} indirection within the same
  # bash -c session. Without this cleanup, a full run accumulates 500+
  # vars / 145+ KB which causes Docker Desktop to silently fail to start.
  local _var
  while IFS= read -r _var; do
    unset "$_var"
  done < <(compgen -A variable _UCC_OBS_ _UCC_RT_ _UCC_CAP_ _UCC_PARAM_)
}

_ucc_should_snapshot_var() {
  local name="$1" decl="${2:-}"
  [[ -n "$name" ]] || return 1
  [[ "$name" =~ ^(_UCC_|BASH_|EUID$|PPID$|SHELLOPTS$|BASHPID$|FUNCNAME$|BASH_SOURCE$|BASH_LINENO$|LINENO$|RANDOM$|SECONDS$|SRANDOM$|PIPESTATUS$|GROUPS$|DIRSTACK$|COMP_|COPROC$|MAPFILE$) ]] && return 1
  [[ "$decl" == declare\ -r* || "$decl" == "declare -ir"* || "$decl" == "declare -ar"* || "$decl" == "declare -A -r"* || "$decl" == "declare -n -r"* ]] && return 1
  return 0
}

_ucc_capture_visible_vars() {
  local name decl snapshot=""
  while IFS= read -r name; do
    decl="$(declare -p "$name" 2>/dev/null || true)"
    [[ -n "$decl" ]] || continue
    _ucc_should_snapshot_var "$name" "$decl" || continue
    snapshot+="${decl}"$'\n'
  done < <(compgen -A variable | LC_ALL=C sort)
  printf '%s' "$snapshot"
}

_ucc_register_target() {
  local args=("$@") name="" argv="" arg snapshot=""
  while [[ ${#args[@]} -gt 0 ]]; do
    case "${args[0]}" in
      --name) name="${args[1]:-}"; args=("${args[@]:2}") ;;
      *) args=("${args[@]:1}") ;;
    esac
  done
  [[ -n "$name" ]] || { log_error "Attempted to register unnamed target"; return 1; }
  for arg in "$@"; do
    argv+="$(printf '%q ' "$arg")"
  done
  snapshot="$(_ucc_capture_visible_vars)"
  _UCC_REGISTERED_NAMES+=("$name")
  _UCC_REGISTERED_ARGS+=("${argv% }")
  _UCC_REGISTERED_ENV+=("$snapshot")
}

_ucc_registered_index() {
  local needle="$1" i
  for i in "${!_UCC_REGISTERED_NAMES[@]}"; do
    [[ "${_UCC_REGISTERED_NAMES[$i]}" == "$needle" ]] && { printf '%s' "$i"; return 0; }
  done
  return 1
}

_ucc_target_status_value() {
  local target="$1"
  [[ -n "${UCC_TARGET_STATUS_FILE:-}" && -f "${UCC_TARGET_STATUS_FILE:-}" ]] || return 0
  awk -F'|' -v dep="$target" '$1==dep {val=$2} END {print val}' "$UCC_TARGET_STATUS_FILE" 2>/dev/null || true
}

# Return direct depends_on list for a target (newline-separated).
_ucc_target_direct_deps() {
  local t="$1"
  if [[ -n "${_UCC_ALL_DEPS_CACHE:-}" ]]; then
    printf '%s\n' "$_UCC_ALL_DEPS_CACHE" | awk -F'\t' -v tgt="$t" '$1==tgt{print $2; exit}' | tr ',' '\n'
  else
    "${UCC_FRAMEWORK_PYTHON:-python3}" "$UCC_TARGETS_QUERY_SCRIPT" --deps "$t" "$UCC_TARGETS_MANIFEST" 2>/dev/null || true
  fi
}

# Return the oracle.configured command for a target, or empty if none.
_ucc_target_oracle_configured() {
  local t="$1"
  if [[ -n "${_UCC_ALL_ORACLES_CACHE:-}" ]]; then
    printf '%s\n' "$_UCC_ALL_ORACLES_CACHE" | awk -F'\t' -v tgt="$t" '$1==tgt{print $2; exit}'
  fi
}

# Recursively walk the transitive dep closure of $root_target.
# Arguments:
#   $1 root_target  — the target whose deps we are checking now
#   $2 origin       — the top-level target that started the chain (for error messages)
#   $3 visited      — colon-separated cycle guard (e.g. "A:B:C")
#
# Per dep:
#   status "failed"   → hard block (dep ran this session and failed)
#   status non-empty, non-failed → dep ran and passed; its own transitive deps were
#                                   already validated when it ran — skip recursion
#   status empty      → dep not run this session; probe oracle.configured:
#                         oracle fail → hard block
#                         oracle pass or no oracle → recurse into dep's own deps
_ucc_check_deps_recursive() {
  local root_target="$1" origin="${2:-$1}" visited="${3:-}" dep deps status oracle_cmd
  deps="$(_ucc_target_direct_deps "$root_target")"
  [[ -n "$deps" ]] || return 0
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    # Cycle guard — colons added at check time, not storage time
    [[ ":${visited}:" == *":${dep}:"* ]] && continue
    status="$(_ucc_target_status_value "$dep")"
    if [[ "$status" == "failed" ]]; then
      printf '      [%-8s] %-40s dependency failed this run: %s\n' \
        "dep-fail" "$(_ucc_display_name "$origin")" "$dep"
      return 1
    fi
    if [[ "$status" == "platform-skipped" ]]; then
      # Dep's component was group-skipped for platform reasons — cascade to
      # a clean [skip] on the dependent instead of [dep-fail]. The dep was
      # never a real failure; it simply doesn't apply on this host.
      printf '      [%-8s] %-40s dependency not applicable on %s: %s\n' \
        "skip" "$(_ucc_display_name "$origin")" "${HOST_PLATFORM:-host}" "$dep"
      _UCC_SKIPPED=$(( ${_UCC_SKIPPED:-0} + 1 ))
      return 1
    fi
    if [[ "$status" == "policy" ]]; then
      # Dep skipped this run because admin privileges weren't available
      # (rc=125). Don't run the dependent — its install would fail anyway
      # without the dep present. Cascade as a clean [skip], not [fail].
      printf '      [%-8s] %-40s dependency requires admin: %s\n' \
        "skip" "$(_ucc_display_name "$origin")" "$dep"
      _UCC_SKIPPED=$(( ${_UCC_SKIPPED:-0} + 1 ))
      return 1
    fi
    if [[ -n "$status" ]]; then
      # Dep ran this session and did not fail; its transitive deps were already
      # validated before it executed — no need to recurse further.
      continue
    fi
    # Dep not run this session — probe its oracle.configured to verify it's installed
    oracle_cmd="$(_ucc_target_oracle_configured "$dep")"
    if [[ -n "$oracle_cmd" ]]; then
      if ! eval "$oracle_cmd" 2>/dev/null; then
        printf '      [%-8s] %-40s dependency not satisfied (oracle fail): %s\n' \
          "dep-fail" "$(_ucc_display_name "$origin")" "$dep"
        _UCC_SKIPPED=$(( ${_UCC_SKIPPED:-0} + 1 ))
        return 1
      fi
      # Oracle passed — record a synthetic status so evidence shows "oracle-pass" not "unknown"
      _ucc_record_target_status "$dep" "oracle-pass"
    fi
    # Oracle passed (or no oracle) — recurse into this dep's own deps
    _ucc_check_deps_recursive "$dep" "$origin" "${visited}:${dep}" || return 1
  done <<< "$deps"
  return 0
}

_ucc_require_declared_dependencies_resolved() {
  local target="$1"
  [[ -n "${UCC_TARGETS_MANIFEST:-}" && -n "${UCC_TARGETS_QUERY_SCRIPT:-}" ]] || return 0
  _ucc_check_deps_recursive "$target" "$target" "$target"
}

# ── ucc_target — full UCC Steps 0-6 lifecycle per target ─────────────────────

_ucc_execute_target() {
  # DEBUG: skip snapshot eval to test if it kills Docker
  #local _ucc_snapshot="${UCC_EXEC_SNAPSHOT:-}"
  #if [[ -n "$_ucc_snapshot" ]]; then
  #  eval "$_ucc_snapshot"
  #fi

  local name="" observe_fn="" desired="" install_fn="" update_fn="" axes="" profile="" evidence_fn="" recover_fn=""
  local warn_on_update_failure=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)    name="$2";       shift 2 ;;
      --observe) observe_fn="$2"; shift 2 ;;
      --desired) desired="$2";    shift 2 ;;
      --install) install_fn="$2"; shift 2 ;;
      --update)  update_fn="$2";  shift 2 ;;
      --axes)    axes="$2";       shift 2 ;;
      --evidence) evidence_fn="$2"; shift 2 ;;
      --profile) profile="$2";    shift 2 ;;
      --recover) recover_fn="$2"; shift 2 ;;
      --warn-on-update-failure) warn_on_update_failure=1; shift ;;
      *) shift ;;
    esac
  done

  [[ -z "$axes" && -n "$profile" ]] && axes="$(_ucc_profile_axes "$profile")"
  if [[ -z "$desired" && "$profile" == "parametric" ]]; then
    log_warn "parametric target '$name' requires explicit --desired with --config-value — profile default has no config_value, will cause perpetual re-convergence"
  fi
  [[ -z "$desired" && -n "$profile" ]] && desired="$(_ucc_profile_desired "$profile")"

  local started_at declaration_ts mode target_id msg_id duration_ms display_name
  started_at=$(date +%s 2>/dev/null || echo 0)
  declaration_ts=$(_ucc_now_utc)
  mode="apply"
  [[ "$UCC_DRY_RUN" == "1" ]] && mode="dry_run"
  target_id=$(_ucc_target_id "$name")
  msg_id="${UCC_CORRELATION_ID:-run}-${target_id}"
  display_name="$(_ucc_display_name "$name")"
  _ucc_record_declaration "$msg_id" "$name" "$desired" "$mode" "$declaration_ts"

  # Step 1 – Observe current state
  local observed obs_exit
  observed=$($observe_fn 2>/dev/null)
  obs_exit=$?

  # observation=failed: observe function crashed (non-zero exit)
  if [[ $obs_exit -ne 0 ]]; then
    _ucc_emit_target_line "$profile" "obs-fail" "$display_name" "observe fn exited non-zero"
    _ucc_record_outcome "$profile" "$name" "FAILED" "failed" "failed" "$msg_id" "$started_at" \
      "{}" "{\"observation\":\"failed\",\"message\":\"observe function exited non-zero\"}"
    return 0
  fi

  # observation=indeterminate: observe ran (exit 0) but produced no usable state
  if [[ -z "$observed" ]]; then
    _ucc_emit_target_line "$profile" "unknown" "$display_name" "observe returned no state"
    _ucc_record_outcome "$profile" "$name" "FAILED" "failed" "failed" "$msg_id" "$started_at" \
      "{}" "{\"observation\":\"indeterminate\",\"message\":\"observe returned empty state\"}"
    return 0
  fi

  log_debug "observed=\"$observed\" desired=\"$desired\" mode=$UCC_MODE"

  # Helper: is observed state satisfying desired?
  # @present wildcard: any value other than "absent" or "outdated" counts as present
  _ucc_satisfied() {
    local obs="$1" des="$2"
    [[ "$des" == "@present" && "$obs" != "absent" && "$obs" != "outdated" ]] && return 0
    [[ "$(_ucc_diff_obj "$obs" "$des" "$axes")" == "{}" ]]
  }

  # Step 3 – Diff: is observed state == desired?
  if _ucc_satisfied "$observed" "$desired"; then

    if [[ "$UCC_MODE" == "update" && -n "$update_fn" ]]; then
      # Update mode: run upgrade even when state already matches
    if [[ "$UCC_DRY_RUN" == "1" ]]; then
        _ucc_emit_target_line "$profile" "dry-run" "$display_name" "state=\"$(_ucc_display_state "$observed" "$axes")\" (update skipped)"
        _ucc_record_outcome "$profile" "$name" "" "unchanged" "unchanged" "$msg_id" "$started_at" \
          "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":{}}" \
          "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"dry_run\",\"message\":\"update transition not applied due to dry-run mode\"}"
        return 0
    fi
      local update_rc=0
      $update_fn || update_rc=$?
      if [[ $update_rc -eq 0 ]]; then
        local verified ver_exit
        verified=$($observe_fn 2>/dev/null)
        ver_exit=$?
        if [[ $ver_exit -eq 0 ]] && _ucc_satisfied "$verified" "$desired"; then
          _ucc_emit_target_line "$profile" "updated" "$display_name" "\"$(_ucc_display_state "$observed" "$axes")\" -> \"$(_ucc_display_state "$verified" "$axes")\""
          _ucc_record_outcome "$profile" "$name" "CHANGED" "ok" "changed" "$msg_id" "$started_at" \
            "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$verified" "$axes"),\"observed_after\":$(_ucc_state_obj "$verified")}" \
            "{\"observation\":\"ok\",\"outcome\":\"changed\",\"completion\":\"complete\",\"proof\":{\"change\":\"update_applied\"}}"
        elif [[ "$warn_on_update_failure" == "1" ]]; then
          _ucc_emit_target_line "$profile" "warn" "$display_name" "self-updating target — update deferred to built-in updater  $(_ucc_compose_evidence "$name" "${verified:-$observed}" "$axes" "$evidence_fn")"
          _ucc_record_outcome "$profile" "$name" "" "warn" "unchanged" "$msg_id" "$started_at" \
            "{}" "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"update must be applied externally\"}"
        else
          _ucc_attempt_escalation "$observe_fn" "$desired" "$axes" "$recover_fn" \
            "$display_name" "$profile" "updated" "$name" "$observed" "$msg_id" "$started_at" \
            && return 0
          _ucc_emit_target_line "$profile" "fail" "$display_name" "verify after update: \"$(_ucc_display_state "${verified:-?}" "$axes")\"  $(_ucc_compose_evidence "$name" "${verified:-$observed}" "$axes" "$evidence_fn")"
          _ucc_record_outcome "$profile" "$name" "FAILED" "failed" "failed" "$msg_id" "$started_at" \
            "{}" "{\"observation\":\"failed\",\"message\":\"post-update verify did not reach desired state\"}"
        fi
      elif [[ $update_rc -eq 124 ]]; then
        _ucc_emit_target_line "$profile" "warn" "$display_name" \
          "$(_ucc_policy_warn_detail "$name" "$observed" "$axes" "$evidence_fn" "transition blocked by policy")"
        _ucc_record_outcome "$profile" "$name" "" "warn" "unchanged" "$msg_id" "$started_at" \
          "{}" "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"transition blocked by policy\"}"
      elif [[ $update_rc -eq 125 ]]; then
        _ucc_emit_target_line "$profile" "policy" "$display_name" \
          "$(_ucc_policy_detail "$name" "$observed" "$desired" "$axes" "$evidence_fn" "admin required")"
        _ucc_record_outcome "$profile" "$name" "" "policy" "unchanged" "$msg_id" "$started_at" \
          "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$desired" "$axes")}" \
          "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"transition requires admin privileges\"}"
      elif [[ "$warn_on_update_failure" == "1" ]]; then
        _ucc_emit_target_line "$profile" "warn" "$display_name" "self-updating target — update deferred to built-in updater  $(_ucc_compose_evidence "$name" "$observed" "$axes" "$evidence_fn")"
        _ucc_record_outcome "$profile" "$name" "" "warn" "unchanged" "$msg_id" "$started_at" \
          "{}" "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"update must be applied externally\"}"
      else
        _ucc_attempt_escalation "$observe_fn" "$desired" "$axes" "$recover_fn" \
          "$display_name" "$profile" "updated" "$name" "$observed" "$msg_id" "$started_at" \
          && return 0
        _ucc_emit_target_line "$profile" "fail" "$display_name" "update error state=\"$(_ucc_display_state "$observed" "$axes")\""
        _ucc_record_outcome "$profile" "$name" "FAILED" "failed" "failed" "$msg_id" "$started_at" \
          "{}" "{\"observation\":\"failed\",\"message\":\"update function failed\"}"
      fi
    else
      # Already at desired state
      _ucc_emit_target_line "$profile" "ok" "$display_name" "$(_ucc_compose_evidence "$name" "$observed" "$axes" "$evidence_fn")"
      _ucc_record_outcome "$profile" "$name" "CONVERGED" "ok" "ok" "$msg_id" "$started_at" \
        "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":{}}" \
        "{\"observation\":\"ok\",\"outcome\":\"converged\"}"
    fi
    return 0
  fi

  # Step 4: Apply transition
  if [[ "$UCC_DRY_RUN" == "1" ]]; then
    if [[ -z "$install_fn" && "$profile" == "capability" ]]; then
      # Capability target with no install_fn: observe-only, no transition.
      _ucc_emit_target_line "$profile" "observe" "$display_name" "state=\"$(_ucc_display_state "$observed" "$axes")\" (observe-only)"
      _ucc_record_outcome "$profile" "$name" "" "unchanged" "unchanged" "$msg_id" "$started_at" \
        "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":{}}" \
        "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"no_install_fn\",\"message\":\"observe-only target, no transition possible\"}"
      return 0
    fi
    _ucc_emit_target_line "$profile" "dry-run" "$display_name" "\"$(_ucc_display_state "$observed" "$axes")\" -> \"$(_ucc_display_state "$desired" "$axes")\""
    _ucc_record_outcome "$profile" "$name" "" "unchanged" "unchanged" "$msg_id" "$started_at" \
      "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$desired" "$axes")}" \
      "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"dry_run\",\"message\":\"transition not applied due to dry-run mode\"}"
    return 0
  fi

  if [[ -z "$install_fn" ]]; then
    # Capability targets have no install_fn by design — they're observe-only.
    # Other profiles without install_fn (e.g. parametric with failed dep-gate)
    # get the legacy "policy blocked" treatment.
    if [[ "$profile" == "capability" ]]; then
      _ucc_emit_target_line "$profile" "observe" "$display_name" "state=\"$(_ucc_display_state "$observed" "$axes")\" (observe-only)"
      _ucc_record_outcome "$profile" "$name" "" "unchanged" "unchanged" "$msg_id" "$started_at" \
        "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":{}}" \
        "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"no_install_fn\",\"message\":\"observe-only target, no transition possible\"}"
      return 0
    fi
    _ucc_emit_target_line "$profile" "policy" "$display_name" \
      "$(_ucc_policy_detail "$name" "$observed" "$desired" "$axes" "$evidence_fn" "policy blocked")"
    _ucc_record_outcome "$profile" "$name" "" "policy" "unchanged" "$msg_id" "$started_at" \
      "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$desired" "$axes")}" \
      "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"transition not applied - no install function declared\"}"
    return 0
  fi

  # Route outdated → update_fn (upgrade), absent → install_fn (fresh install)
  local action_fn="$install_fn"
  local action_label="installed"
  local action_context="install"
  if _ucc_observed_prefers_update_action "$observed" && [[ -n "$update_fn" ]]; then
    action_fn="$update_fn"
    action_label="updated"
    action_context="update"
  fi

  # Interactive mode: confirm before applying changes
  if [[ "${UCC_INTERACTIVE:-0}" == "1" && -t 0 ]]; then
    printf '      [?] %s %s? [Y/n] ' "$action_context" "$display_name"
    local _confirm
    read -r _confirm
    if [[ "$_confirm" =~ ^[Nn] ]]; then
      _ucc_emit_target_line "$profile" "skip" "$display_name" "user declined"
      _ucc_record_outcome "$profile" "$name" "" "unchanged" "unchanged" "$msg_id" "$started_at" \
        "{}" "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"user\",\"message\":\"user declined interactive confirmation\"}"
      return 0
    fi
  fi

  local action_rc=0
  $action_fn || action_rc=$?
    # Step 5 – Verify: re-observe after transition.
  # Always attempt verify when action ran (not a policy exit).  The action may
  # have succeeded even on non-zero exit (e.g. brew exits 1 when a dependency
  # unlinks a conflicting keg, yet the package itself was installed correctly).
  # If verify confirms desired state, declare success regardless of action_rc.
  if [[ $action_rc -ne 124 && $action_rc -ne 125 ]]; then
    local verified ver_exit
    verified=$($observe_fn 2>/dev/null)
    ver_exit=$?
    log_debug "post-${action_context} observed=\"$verified\""
    if [[ $ver_exit -eq 0 ]] && _ucc_satisfied "$verified" "$desired"; then
      _ucc_emit_target_line "$profile" "$action_label" "$display_name" "\"$(_ucc_display_state "$observed" "$axes")\" -> \"$(_ucc_display_state "$verified" "$axes")\""
      _ucc_record_outcome "$profile" "$name" "CHANGED" "ok" "changed" "$msg_id" "$started_at" \
        "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$verified" "$axes"),\"observed_after\":$(_ucc_state_obj "$verified")}" \
        "{\"observation\":\"ok\",\"outcome\":\"changed\",\"completion\":\"complete\",\"proof\":{\"change\":\"verify_pass\"}}"
    elif [[ "$warn_on_update_failure" == "1" && "$action_context" == "update" ]]; then
      _ucc_emit_target_line "$profile" "warn" "$display_name" "self-updating target — update deferred to built-in updater  $(_ucc_compose_evidence "$name" "${verified:-$observed}" "$axes" "$evidence_fn")"
      _ucc_record_outcome "$profile" "$name" "" "warn" "unchanged" "$msg_id" "$started_at" \
        "{}" "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"update must be applied externally\"}"
    elif [[ $action_rc -eq 0 ]]; then
      _ucc_attempt_escalation "$observe_fn" "$desired" "$axes" "$recover_fn" \
        "$display_name" "$profile" "$action_label" "$name" "$observed" "$msg_id" "$started_at" \
        && return 0
      _ucc_emit_target_line "$profile" "fail" "$display_name" "verify after ${action_context}: \"$(_ucc_display_state "${verified:-?}" "$axes")\"  $(_ucc_compose_evidence "$name" "${verified:-$observed}" "$axes" "$evidence_fn")"
      _ucc_record_outcome "$profile" "$name" "FAILED" "failed" "failed" "$msg_id" "$started_at" \
        "{}" "{\"observation\":\"failed\",\"message\":\"post-${action_context} verify did not reach desired state\"}"
    else
      _ucc_attempt_escalation "$observe_fn" "$desired" "$axes" "$recover_fn" \
        "$display_name" "$profile" "$action_label" "$name" "$observed" "$msg_id" "$started_at" \
        && return 0
      _ucc_emit_target_line "$profile" "fail" "$display_name" "${action_context} error was=\"$(_ucc_display_state "$observed" "$axes")\"  $(_ucc_compose_evidence "$name" "$observed" "$axes" "$evidence_fn")"
      _ucc_record_outcome "$profile" "$name" "FAILED" "failed" "failed" "$msg_id" "$started_at" \
        "{}" "{\"observation\":\"failed\",\"message\":\"${action_context} function failed; verify also did not reach desired state\"}"
    fi
    return 0
  fi
  if [[ $action_rc -eq 124 ]]; then
    _ucc_emit_target_line "$profile" "warn" "$display_name" \
      "$(_ucc_policy_warn_detail "$name" "$observed" "$axes" "$evidence_fn" "transition blocked by policy")"
    _ucc_record_outcome "$profile" "$name" "" "warn" "unchanged" "$msg_id" "$started_at" \
      "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$desired" "$axes")}" \
      "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"transition blocked by policy\"}"
  elif [[ $action_rc -eq 125 ]]; then
    _ucc_emit_target_line "$profile" "policy" "$display_name" \
      "$(_ucc_policy_detail "$name" "$observed" "$desired" "$axes" "$evidence_fn" "admin required")"
    _ucc_record_outcome "$profile" "$name" "" "policy" "unchanged" "$msg_id" "$started_at" \
      "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$desired" "$axes")}" \
      "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"transition requires admin privileges\"}"
  fi
}

ucc_flush_registered_targets() {
  local component="$1" ordered="" target idx
  local declared=() undeclared=()
  # Note: do NOT early-return when _UCC_REGISTERED_NAMES is empty.
  # In deferred mode, fully-filtered components (all targets disabled or
  # requires-skipped) register nothing — but the flush still needs to emit
  # those targets in topo order with their proper [disabled]/[skip] reasons.

  if [[ -n "${_UCC_ALL_ORDERED_CACHE:-}" ]]; then
    ordered="$(printf '%s\n' "$_UCC_ALL_ORDERED_CACHE" | awk -F'\t' -v c="$component" '$1==c{print $2; exit}' | tr ',' '\n')"
  elif [[ -n "${UCC_TARGETS_MANIFEST:-}" && -n "${UCC_TARGETS_QUERY_SCRIPT:-}" ]]; then
    ordered="$("${UCC_FRAMEWORK_PYTHON:-python3}" "$UCC_TARGETS_QUERY_SCRIPT" --ordered-targets "$component" "$UCC_TARGETS_MANIFEST" 2>/dev/null || true)"
  fi

  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    declared+=("$target")
  done <<< "$ordered"

  for target in "${declared[@]+"${declared[@]}"}"; do
    idx="$(_ucc_registered_index "$target" || true)"
    [[ -n "$idx" ]] || continue
    # Target set filter applied at entry points (ucc_yaml_*_target functions)
    # On dep-fail: print [dep-fail], record status, continue to next target.
    # Previously aborted the whole component — hid 11+ targets on first fail.
    if ! _ucc_require_declared_dependencies_resolved "$target"; then
      _ucc_record_target_status "$target" "failed"
      continue
    fi
    # On target execute failure: continue; _ucc_execute_target already
    # recorded outcome internally, we should not abort independent targets.
    UCC_EXEC_SNAPSHOT="${_UCC_REGISTERED_ENV[$idx]}" eval "_ucc_execute_target ${_UCC_REGISTERED_ARGS[$idx]}" || true
  done

  local name seen
  for idx in "${!_UCC_REGISTERED_NAMES[@]}"; do
    name="${_UCC_REGISTERED_NAMES[$idx]}"
    seen=0
    for target in "${declared[@]+"${declared[@]}"}"; do
      [[ "$target" == "$name" ]] && { seen=1; break; }
    done
    [[ "$seen" -eq 1 ]] && continue
    log_warn "Target '$name' is not declared in the manifest; executing after topo-sorted targets with no dependencies"
    undeclared+=("$idx")
  done

  for idx in "${undeclared[@]+"${undeclared[@]}"}"; do
    UCC_EXEC_SNAPSHOT="${_UCC_REGISTERED_ENV[$idx]}" eval "_ucc_execute_target ${_UCC_REGISTERED_ARGS[$idx]}" || true
  done

  # Emit [skip] for targets in the component that the runner never processed
  for target in "${declared[@]+"${declared[@]}"}"; do
    # Check if target was registered (runner called ucc_yaml_*_target for it)
    _was_processed=0
    for _rn in "${_UCC_REGISTERED_NAMES[@]+"${_UCC_REGISTERED_NAMES[@]}"}"; do
      [[ "$_rn" == "$target" ]] && { _was_processed=1; break; }
    done
    # Check if target was already handled by _ucc_target_filtered_out
    [[ "${_UCC_EMITTED_TARGETS:-}" == *"|${target}|"* ]] && _was_processed=1
    if [[ $_was_processed -eq 0 ]]; then
      local _dn; _dn="$(_ucc_display_name "$target")"
      if [[ -n "${UCC_DISABLED_TARGETS:-}" && "${UCC_DISABLED_TARGETS}" == *"${target}|"* ]]; then
        printf '      [%-8s] %-40s %s\n' "disabled" "$_dn" "disabled by policy"
      else
        # Was the target filtered by `requires:` during the deferred
        # registration phase? If so, surface the same message we would
        # have shown immediately in non-defer mode.
        local _req_var="_UCC_DEFERRED_REQUIRES_$(echo "${target//[^a-zA-Z0-9]/_}")"
        local _req="${!_req_var:-}"
        if [[ -n "$_req" ]]; then
          printf '      [%-8s] %-40s %s\n' "skip" "$_dn" "requires: ${_req}"
        else
          printf '      [%-8s] %-40s %s\n' "skip" "$_dn" "not processed"
        fi
      fi
      _UCC_SKIPPED=$(( ${_UCC_SKIPPED:-0} + 1 ))
    fi
  done
}

ucc_target() {
  # Extract --name for filter check
  local _tgt_name="" _a _prev=0
  for _a in "$@"; do
    if [[ $_prev -eq 1 ]]; then _tgt_name="$_a"; break; fi
    [[ "$_a" == "--name" ]] && _prev=1
  done
  [[ -n "$_tgt_name" ]] && _ucc_target_filtered_out "$_tgt_name" && return 0

  if [[ "${UCC_TARGET_DEFER:-0}" == "1" ]]; then
    _ucc_register_target "$@"
  else
    _ucc_execute_target "$@"
  fi
}

_ucc_target_with_default_profile() {
  local _default="$1"; shift
  local has_profile=0 args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile) has_profile=1; args+=("$1" "$2"); shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  [[ "$has_profile" -eq 0 ]] && args+=(--profile "$_default")
  ucc_target "${args[@]}"
}

ucc_target_nonruntime() { _ucc_target_with_default_profile configured "$@"; }
ucc_target_service()    { _ucc_target_with_default_profile runtime    "$@"; }

ucc_skip_target() {
  _ucc_target_filtered_out "$1" && return 0
  local name="$1" reason="$2"
  local display_name
  display_name="$(_ucc_display_name "$name")"
  printf '      [%-8s] %-40s %s\n' "skip" "$display_name" "$reason"
  _UCC_SKIPPED=$(( ${_UCC_SKIPPED:-0} + 1 ))
  _UCC_EMITTED_TARGETS="${_UCC_EMITTED_TARGETS}|${name}|"
}

# ── ucc_summary — write per-component counts to summary file ──────────────────

ucc_summary() {
  local comp="${1:-}"
  if [[ -n "${UCC_SUMMARY_FILE:-}" && -n "$comp" ]]; then
    printf '%s|%d|%d|%d|%d|%d\n' "$comp" "$_UCC_CONVERGED" "$_UCC_CHANGED" "$_UCC_FAILED" "${_UCC_SKIPPED:-0}" "${_UCC_POLICY:-0}" \
      >> "$UCC_SUMMARY_FILE" 2>/dev/null || true
  fi
}
