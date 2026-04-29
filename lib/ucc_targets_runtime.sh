#!/usr/bin/env bash
# lib/ucc_targets_runtime.sh — runtime target factory + observe.
#
# Extracted from lib/ucc_targets.sh on 2026-04-29 (PLAN refactor #2, slice 4).

_ucc_observe_yaml_runtime_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local fn="${target//[^a-zA-Z0-9]/_}"
  local _cached_var="_UCC_OBS_CACHED_${fn}"
  local runtime_driver
  if [[ -n "${!_cached_var:-}" ]]; then
    local _v="_UCC_RT_DRIVER_${fn}"; runtime_driver="${!_v}"
  else
    runtime_driver="$(_ucc_yaml_target_driver_get "$cfg_dir" "$yaml" "$target" "kind")"
  fi
  # Try driver dispatch first — drivers like custom-daemon have their own observe
  local _driver_state
  if _driver_state="$(_ucc_driver_observe "$cfg_dir" "$yaml" "$target" 2>/dev/null)"; then
    # Map driver raw state to ASM
    case "$_driver_state" in
      absent)  ucc_asm_state --installation Absent --runtime NeverStarted --health Unavailable --admin Enabled --dependencies DepsUnknown ;;
      running) ucc_asm_runtime_desired ;;
      outdated)
        # Daemon is running but a newer version exists upstream. Treat as
        # Running+Outdated (analogous to Installed+Outdated for packages).
        # Previously fell through to the default [*] case → Stopped+Degraded
        # which caused scheduler to trigger install action and FAIL when the
        # daemon was actually up (e.g. ollama 0.20.6 when 0.20.7 on GitHub).
        ucc_asm_state --installation Configured --runtime Running --health Outdated --admin Enabled --dependencies DepsReady ;;
      stopped)
        local _sh _sd _v
        _v="_UCC_RT_STOPPED_HEALTH_${fn}"; _sh="${!_v:-Degraded}"
        _v="_UCC_RT_STOPPED_DEPS_${fn}"; _sd="${!_v:-DepsDegraded}"
        ucc_asm_state --installation Configured --runtime Stopped --health "$_sh" --admin Enabled --dependencies "$_sd" ;;
      *)       ucc_asm_state --installation Configured --runtime Stopped --health Degraded --admin Enabled --dependencies DepsReady ;;
    esac
    return
  fi
  _ucc_observe_yaml_runtime_oracle_target "$cfg_dir" "$yaml" "$target"
}

_ucc_observe_yaml_runtime_oracle_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local configured_cmd runtime_cmd stopped_installation stopped_runtime stopped_health stopped_dependencies
  local fn="${target//[^a-zA-Z0-9]/_}"
  local _cached_var="_UCC_OBS_CACHED_${fn}"
  if [[ -n "${!_cached_var:-}" ]]; then
    local _v
    _v="_UCC_RT_CONFIGURED_${fn}";    configured_cmd="${!_v}"
    _v="_UCC_RT_RUNTIME_${fn}";       runtime_cmd="${!_v}"
    _v="_UCC_RT_STOPPED_INST_${fn}";  stopped_installation="${!_v}"
    _v="_UCC_RT_STOPPED_RT_${fn}";    stopped_runtime="${!_v}"
    _v="_UCC_RT_STOPPED_HEALTH_${fn}";stopped_health="${!_v}"
    _v="_UCC_RT_STOPPED_DEPS_${fn}";  stopped_dependencies="${!_v}"
  else
    while IFS=$'\t' read -r -d '' key value; do
      case "$key" in
        oracle.configured)    configured_cmd="$value" ;;
        oracle.runtime)       runtime_cmd="$value" ;;
        stopped_installation) stopped_installation="$value" ;;
        stopped_runtime)      stopped_runtime="$value" ;;
        stopped_health)       stopped_health="$value" ;;
        stopped_dependencies) stopped_dependencies="$value" ;;
      esac
    done < <(_ucc_yaml_target_get_many "$cfg_dir" "$yaml" "$target" \
      oracle.configured oracle.runtime stopped_installation stopped_runtime stopped_health stopped_dependencies)
  fi
  [[ -n "$stopped_installation" ]] || stopped_installation="Configured"
  [[ -n "$stopped_runtime" ]] || stopped_runtime="Stopped"
  [[ -n "$stopped_health" ]] || stopped_health="Degraded"
  [[ -n "$stopped_dependencies" ]] || stopped_dependencies="DepsDegraded"

  if [[ -n "$configured_cmd" ]] && ! _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$configured_cmd"; then
    ucc_asm_state --installation Absent --runtime NeverStarted --health Unavailable --admin Enabled --dependencies DepsUnknown
    return
  fi

  if [[ -n "$runtime_cmd" ]] && _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$runtime_cmd"; then
    ucc_asm_runtime_desired
    return
  fi

  ucc_asm_state \
    --installation "$stopped_installation" \
    --runtime "$stopped_runtime" \
    --health "$stopped_health" \
    --admin Enabled \
    --dependencies "$stopped_dependencies"
}

# Register a runtime target from YAML.
#
# Usage: ucc_yaml_runtime_target <cfg_dir> <yaml> <target> [install_fn] [update_fn]
#
# When install_fn / update_fn are omitted, the framework synthesizes
# wrappers that dispatch to the driver via _ucc_run_yaml_action (→
# _ucc_driver_action → _ucc_driver_<kind>_action). Observe and evidence
# always go through the driver regardless.
#
# When install_fn / update_fn are passed, they REPLACE the synthesized
# driver-dispatch wrappers. The driver's `_action` function is then
# never called for this target — only its `_observe` and `_evidence`.
# Pass explicit wrappers only when the install/update logic is
# genuinely heterogeneous (e.g. Squirrel-swap vs curl|sh vs brew
# services for ollama) or when no existing driver handles the
# mechanism (e.g. custom launchd plist generation). Otherwise prefer
# pure driver dispatch — simpler, keeps driver improvements like
# #57's apply-flow reachable.
ucc_yaml_runtime_target() {
  local cfg_dir="$1" yaml="$2" target="$3" install_fn="${4:-}" update_fn="${5:-}"
  _ucc_target_filtered_out "$target" "$cfg_dir" "$yaml" && return 0
  local fn install_cmd update_cmd self_updating=""
  local obs_configured="" obs_runtime="" obs_driver=""
  local obs_stopped_inst="" obs_stopped_rt="" obs_stopped_health="" obs_stopped_deps=""
  local _ev_b64=""
  fn="${target//[^a-zA-Z0-9]/_}"
  install_cmd=""
  update_cmd=""
  while IFS=$'\t' read -r -d '' key value; do
    if [[ "$key" == "__evidence__" ]]; then _ev_b64="$value"; continue; fi
    case "$key" in
      actions.install)                   install_cmd="$value" ;;
      actions.update)                    update_cmd="$value" ;;
      oracle.configured)                 obs_configured="$value" ;;
      oracle.runtime)                    obs_runtime="$value" ;;
      driver.kind)                       obs_driver="$value" ;;
      driver.self_updating) self_updating="$value" ;;
      stopped_installation)              obs_stopped_inst="$value" ;;
      stopped_runtime)                   obs_stopped_rt="$value" ;;
      stopped_health)                    obs_stopped_health="$value" ;;
      stopped_dependencies)              obs_stopped_deps="$value" ;;
    esac
  done < <(_ucc_ytgt_source "$cfg_dir" "$yaml" "$target" \
      actions.install actions.update oracle.configured oracle.runtime \
      driver.kind driver.self_updating stopped_installation stopped_runtime \
      stopped_health stopped_dependencies)
  [[ -z "$update_cmd" ]] && update_cmd="$install_cmd"
  # A dispatched driver handles install/update even when actions.* are absent from YAML
  local driver_dispatched=0
  [[ -n "$obs_driver" && "$obs_driver" != "custom" ]] && driver_dispatched=1

  export "_UCC_OBS_CACHED_${fn}=1"
  export "_UCC_OBS_EVIDENCE_${fn}=${_ev_b64}"
  export "_UCC_RT_CONFIGURED_${fn}=${obs_configured}"
  export "_UCC_RT_RUNTIME_${fn}=${obs_runtime}"
  export "_UCC_RT_DRIVER_${fn}=${obs_driver}"
  export "_UCC_RT_STOPPED_INST_${fn}=${obs_stopped_inst}"
  export "_UCC_RT_STOPPED_RT_${fn}=${obs_stopped_rt}"
  export "_UCC_RT_STOPPED_HEALTH_${fn}=${obs_stopped_health}"
  export "_UCC_RT_STOPPED_DEPS_${fn}=${obs_stopped_deps}"

  eval "_uyrt_obs_${fn}() { _ucc_observe_yaml_runtime_target '${cfg_dir}' '${yaml}' '${target}'; }"
  eval "_uyrt_evd_${fn}() { ucc_eval_evidence_from_yaml '${cfg_dir}' '${yaml}' '${target}'; }"
  if [[ -z "$install_fn" && ( -n "$install_cmd" || "$driver_dispatched" == "1" ) ]]; then
    eval "_uyrt_ins_${fn}() {
      local rc=0 runtime_cmd=''
      _ucc_run_yaml_action '${cfg_dir}' '${yaml}' '${target}' install || rc=\$?
      if [[ \$rc -eq 0 ]]; then
        runtime_cmd=\"\$(_ucc_yaml_target_get '${cfg_dir}' '${yaml}' '${target}' 'oracle.runtime')\"
        [[ -n \"\$runtime_cmd\" ]] && _ucc_wait_for_yaml_runtime_probe '${cfg_dir}' '${yaml}' '${target}' \"\$runtime_cmd\" || true
      fi
      return \$rc
    }"
    install_fn="_uyrt_ins_${fn}"
  fi
  if [[ -z "$update_fn" && ( -n "$update_cmd" || -n "$install_cmd" || "$driver_dispatched" == "1" ) ]]; then
    eval "_uyrt_upd_${fn}() {
      local rc=0 runtime_cmd=''
      _ucc_run_yaml_action '${cfg_dir}' '${yaml}' '${target}' update || rc=\$?
      if [[ \$rc -eq 0 ]]; then
        runtime_cmd=\"\$(_ucc_yaml_target_get '${cfg_dir}' '${yaml}' '${target}' 'oracle.runtime')\"
        [[ -n \"\$runtime_cmd\" ]] && _ucc_wait_for_yaml_runtime_probe '${cfg_dir}' '${yaml}' '${target}' \"\$runtime_cmd\" || true
      fi
      return \$rc
    }"
    update_fn="_uyrt_upd_${fn}"
  fi

  local args=(
    --name "$target"
    --observe "_uyrt_obs_${fn}"
    --evidence "_uyrt_evd_${fn}"
    --desired "$(ucc_asm_runtime_desired)"
  )
  [[ -n "$install_fn" ]] && args+=(--install "$install_fn")
  [[ -n "$update_fn" ]] && args+=(--update "$update_fn")
  # Externally-managed updates (e.g. Ollama.app auto-updates itself, ollama
  # binary updates come from upstream installer, not a CLI command) → treat
  # post-action still-outdated as [warn], not [fail].
  [[ "$self_updating" == "true" || "$self_updating" == "1" || "$self_updating" == "yes" ]] && \
    args+=(--warn-on-update-failure)
  ucc_target_service "${args[@]}"
}
