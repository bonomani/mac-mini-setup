#!/usr/bin/env bash
# lib/ucc_targets_nonruntime.sh — capability + parametric target factories.
#
# Extracted from lib/ucc_targets.sh on 2026-04-29 (PLAN refactor #2, slice 3).
# Dispatch helpers (ucc_target / _ucc_observe_yaml_simple_target /
# _ucc_run_yaml_action) stay in ucc_targets.sh; bash forward-resolves
# them at call time, so the capability/parametric factories live here
# without re-ordering source loads.

_ucc_observe_yaml_capability_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local fn="${target//[^a-zA-Z0-9]/_}"
  local _cached_var="_UCC_OBS_CACHED_${fn}"
  local runtime_cmd
  if [[ -n "${!_cached_var:-}" ]]; then
    local _v="_UCC_CAP_RUNTIME_${fn}"; runtime_cmd="${!_v}"
  else
    runtime_cmd="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.probe")"
  fi
  if [[ -n "$runtime_cmd" ]] && _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$runtime_cmd"; then
    ucc_asm_state --installation Configured --runtime Running --health Healthy --admin Enabled --dependencies DepsReady
  else
    # Capability probe returned false — the capability isn't usable right now.
    # Use `Unavailable` (not Degraded); Degraded is reserved for broken/drift.
    ucc_asm_state --installation Configured --runtime Stopped --health Unavailable --admin Enabled --dependencies DepsReady
  fi
}

ucc_yaml_capability_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _ucc_target_filtered_out "$target" "$cfg_dir" "$yaml" && return 0
  local fn runtime_cmd=""
  local _ev_b64=""
  fn="${target//[^a-zA-Z0-9]/_}"
  while IFS=$'\t' read -r -d '' key value; do
    if [[ "$key" == "__evidence__" ]]; then _ev_b64="$value"; continue; fi
    case "$key" in
      driver.probe) runtime_cmd="$value" ;;
    esac
  done < <(_ucc_ytgt_source "$cfg_dir" "$yaml" "$target" driver.probe)

  export "_UCC_OBS_CACHED_${fn}=1"
  export "_UCC_OBS_EVIDENCE_${fn}=${_ev_b64}"
  export "_UCC_CAP_RUNTIME_${fn}=${runtime_cmd}"

  eval "_uyct_obs_${fn}() { _ucc_observe_yaml_capability_target '${cfg_dir}' '${yaml}' '${target}'; }"
  eval "_uyct_evd_${fn}() { ucc_eval_evidence_from_yaml '${cfg_dir}' '${yaml}' '${target}'; }"

  ucc_target \
    --name "$target" \
    --profile capability \
    --observe "_uyct_obs_${fn}" \
    --evidence "_uyct_evd_${fn}"
}

_ucc_yaml_gate_dependency_state() {
  local gate="$1" dep_state="DepsReady" gate_key=""
  [[ -n "$gate" ]] || { printf '%s' "$dep_state"; return; }
  gate_key="UIC_GATE_FAILED_$(echo "${gate//-/_}" | tr '[:lower:]' '[:upper:]')"
  [[ "${!gate_key:-0}" == "1" ]] && dep_state="DepsDegraded"
  printf '%s' "$dep_state"
}

_ucc_yaml_parametric_observed_state() {
  local current="$1" desired="$2" dep_state="$3"
  if [[ "$current" == "$desired" ]]; then
    ucc_asm_state \
      --installation Configured \
      --runtime Stopped \
      --health Healthy \
      --admin Enabled \
      --dependencies "$dep_state" \
      --config-value "$current"
  else
    ucc_asm_state \
      --installation Configured \
      --runtime Stopped \
      --health Degraded \
      --admin Enabled \
      --dependencies "$dep_state" \
      --config-value "$current"
  fi
}

_ucc_yaml_parametric_desired_state() {
  local desired="$1" dep_state="$2"
  ucc_asm_state \
    --installation Configured \
    --runtime Stopped \
    --health Healthy \
    --admin Enabled \
    --dependencies "$dep_state" \
    --config-value "$desired"
}

_ucc_observe_yaml_parametric_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local observe_cmd desired gate current dep_state
  local fn="${target//[^a-zA-Z0-9]/_}"
  local _cached_var="_UCC_OBS_CACHED_${fn}"
  if [[ -n "${!_cached_var:-}" ]]; then
    local _v
    _v="_UCC_PARAM_OBS_CMD_${fn}"; observe_cmd="${!_v}"
    _v="_UCC_PARAM_GATE_${fn}";    gate="${!_v}"
    _v="_UCC_PARAM_DESIRED_${fn}"; desired="${!_v}"
  else
    while IFS=$'\t' read -r -d '' key value; do
      case "$key" in
        observe_cmd)     observe_cmd="$value" ;;
        dependency_gate) gate="$value" ;;
      esac
    done < <(_ucc_yaml_target_get_many "$cfg_dir" "$yaml" "$target" observe_cmd dependency_gate)
    desired="$(_ucc_yaml_parametric_desired_value "$cfg_dir" "$yaml" "$target")"
  fi
  dep_state="$(_ucc_yaml_gate_dependency_state "$gate")"
  local driver_raw
  if driver_raw="$(_ucc_driver_observe "$cfg_dir" "$yaml" "$target")"; then
    [[ -n "$driver_raw" ]] || driver_raw="absent"
    _ucc_yaml_parametric_observed_state "$driver_raw" "$desired" "$dep_state"
    return
  fi
  current="$(_ucc_eval_yaml_scalar_cmd "$cfg_dir" "$yaml" "$target" "$observe_cmd")"
  _ucc_yaml_parametric_observed_state "$current" "$desired" "$dep_state"
}

_ucc_evidence_yaml_parametric_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local observe_cmd current evidence
  local fn="${target//[^a-zA-Z0-9]/_}"
  local _cached_var="_UCC_OBS_CACHED_${fn}"
  if [[ -n "${!_cached_var:-}" ]]; then
    local _v="_UCC_PARAM_OBS_CMD_${fn}"; observe_cmd="${!_v}"
  else
    while IFS=$'\t' read -r -d '' key value; do
      case "$key" in
        observe_cmd) observe_cmd="$value" ;;
      esac
    done < <(_ucc_yaml_target_get_many "$cfg_dir" "$yaml" "$target" observe_cmd)
  fi
  local CFG_DIR="$cfg_dir" YAML_PATH="$yaml" TARGET_NAME="$target"
  evidence="$(ucc_eval_evidence_from_yaml "$cfg_dir" "$yaml" "$target")"
  if [[ -n "$evidence" ]]; then
    printf '%s' "$evidence"
    return 0
  fi
  current="$(_ucc_eval_yaml_scalar_cmd "$cfg_dir" "$yaml" "$target" "$observe_cmd")"
  printf 'value=%s' "$current"
}

_ucc_yaml_parametric_desired_value() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local desired_cmd desired_value
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      desired_cmd) desired_cmd="$value" ;;
      desired_value) desired_value="$value" ;;
    esac
  done < <(_ucc_yaml_target_get_many "$cfg_dir" "$yaml" "$target" desired_cmd desired_value)

  if [[ -n "$desired_cmd" ]]; then
    _ucc_eval_yaml_scalar_cmd "$cfg_dir" "$yaml" "$target" "$desired_cmd"
    return 0
  fi
  printf '%s' "$desired_value"
}

ucc_yaml_parametric_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _ucc_target_filtered_out "$target" "$cfg_dir" "$yaml" && return 0
  local fn install_cmd update_cmd desired gate dep_state driver_kind
  local obs_cmd="" obs_gate="" desired_cmd="" desired_value_raw=""
  local _ev_b64=""
  fn="${target//[^a-zA-Z0-9]/_}"
  install_cmd=""
  update_cmd=""
  driver_kind=""
  while IFS=$'\t' read -r -d '' key value; do
    if [[ "$key" == "__evidence__" ]]; then _ev_b64="$value"; continue; fi
    case "$key" in
      actions.install)  install_cmd="$value" ;;
      actions.update)   update_cmd="$value" ;;
      desired_cmd)      desired_cmd="$value" ;;
      desired_value)    desired_value_raw="$value" ;;
      dependency_gate)  obs_gate="$value" ;;
      observe_cmd)      obs_cmd="$value" ;;
      driver.kind)      driver_kind="$value" ;;
    esac
  done < <(_ucc_ytgt_source "$cfg_dir" "$yaml" "$target" \
      actions.install actions.update desired_cmd desired_value dependency_gate observe_cmd driver.kind)
  [[ -z "$update_cmd" ]] && update_cmd="$install_cmd"
  local driver_dispatched=0
  [[ -n "$driver_kind" && "$driver_kind" != "custom" ]] && driver_dispatched=1
  if [[ -n "$desired_cmd" ]]; then
    desired="$(_ucc_eval_yaml_scalar_cmd "$cfg_dir" "$yaml" "$target" "$desired_cmd")"
  else
    desired="$desired_value_raw"
  fi
  gate="$obs_gate"
  dep_state="$(_ucc_yaml_gate_dependency_state "$gate")"

  export "_UCC_OBS_CACHED_${fn}=1"
  export "_UCC_OBS_EVIDENCE_${fn}=${_ev_b64}"
  export "_UCC_PARAM_OBS_CMD_${fn}=${obs_cmd}"
  export "_UCC_PARAM_GATE_${fn}=${gate}"
  export "_UCC_PARAM_DESIRED_${fn}=${desired}"

  eval "_uypt_obs_${fn}() { _ucc_observe_yaml_parametric_target '${cfg_dir}' '${yaml}' '${target}'; }"
  eval "_uypt_evd_${fn}() { _ucc_evidence_yaml_parametric_target '${cfg_dir}' '${yaml}' '${target}'; }"
  if [[ ("$driver_dispatched" == "1" || -n "$install_cmd") && "$dep_state" == "DepsReady" ]]; then
    eval "_uypt_ins_${fn}() { _ucc_run_yaml_action '${cfg_dir}' '${yaml}' '${target}' install; }"
    eval "_uypt_upd_${fn}() { _ucc_run_yaml_action '${cfg_dir}' '${yaml}' '${target}' update; }"
  fi

  local args=(
    --name "$target"
    --profile parametric
    --observe "_uypt_obs_${fn}"
    --evidence "_uypt_evd_${fn}"
    --desired "$(_ucc_yaml_parametric_desired_state "$desired" "$dep_state")"
  )
  [[ ("$driver_dispatched" == "1" || -n "$install_cmd") && "$dep_state" == "DepsReady" ]] && args+=(--install "_uypt_ins_${fn}")
  [[ ("$driver_dispatched" == "1" || -n "$install_cmd") && "$dep_state" == "DepsReady" ]] && args+=(--update "_uypt_upd_${fn}")
  ucc_target "${args[@]}"
}
