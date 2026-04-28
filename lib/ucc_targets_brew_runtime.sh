#!/usr/bin/env bash
# lib/ucc_targets_brew_runtime.sh — brew runtime formula target subsystem.
#
# Extracted from lib/ucc_targets.sh on 2026-04-28 (PLAN refactor #2, slice 2).
# Used only by brew formulae that ship a launchd/systemd service alongside
# the binary (e.g. ariaflow-server, ariaflow-dashboard).

_ucc_observe_brew_runtime_formula() {
  local pkg="$1" service_name="$2" runtime_cmd="${3:-}" configured_cmd="${4:-}" cfg_dir="${5:-}" yaml="${6:-}" target="${7:-}"
  local pkg_state update_class
  update_class="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "update_class" 2>/dev/null || true)"
  pkg_state="$(brew_observe "$pkg" "${update_class:-tool}")"

  if [[ "$pkg_state" == "absent" ]]; then
    ucc_asm_state --installation Absent --runtime NeverStarted --health Unavailable --admin Enabled --dependencies DepsUnknown
    return
  fi

  if [[ "$pkg_state" == "outdated" ]]; then
    if brew_service_is_started "$service_name"; then
      ucc_asm_state --installation Installed --runtime Running --health Degraded --admin Enabled --dependencies DepsDegraded
    else
      ucc_asm_state --installation Installed --runtime Stopped --health Degraded --admin Enabled --dependencies DepsDegraded
    fi
    return
  fi

  if [[ -n "$configured_cmd" ]] && ! _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$configured_cmd"; then
    ucc_asm_state --installation Installed --runtime Stopped --health Degraded --admin Enabled --dependencies DepsDegraded
    return
  fi

  if ! brew_service_is_started "$service_name"; then
    ucc_asm_state --installation Configured --runtime Stopped --health Degraded --admin Enabled --dependencies DepsDegraded
    return
  fi

  if [[ -n "$runtime_cmd" ]] && ! _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$runtime_cmd"; then
    ucc_asm_state --installation Configured --runtime Running --health Degraded --admin Enabled --dependencies DepsDegraded
    return
  fi

  ucc_asm_runtime_desired
}

_ucc_apply_brew_runtime_formula() {
  local pkg="$1" brew_ref="$2" service_name="$3" runtime_cmd="${4:-}" mode="${5:-install}" cfg_dir="${6:-}" yaml="${7:-}" target="${8:-}"
  local pkg_state update_class
  update_class="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "update_class" 2>/dev/null || true)"
  pkg_state="$(brew_observe "$pkg" "${update_class:-tool}")"
  if [[ "$pkg_state" == "absent" ]]; then
    brew_install "$brew_ref" || return 1
  elif [[ "$pkg_state" == "outdated" || "$mode" == "update" ]]; then
    brew_upgrade "$brew_ref" || return 1
  fi

  if brew_service_is_started "$service_name"; then
    ucc_run brew services restart "$brew_ref" || return 1
  else
    ucc_run brew services start "$brew_ref" || return 1
  fi

  [[ -n "$runtime_cmd" ]] && _ucc_wait_for_yaml_runtime_probe "$cfg_dir" "$yaml" "$target" "$runtime_cmd"
}

_ucc_wait_for_runtime_probe() {
  local runtime_cmd="$1"
  local attempts="${UCC_RUNTIME_WAIT_ATTEMPTS:-20}"
  local interval="${UCC_RUNTIME_WAIT_INTERVAL:-1}"
  local i

  [[ -n "$runtime_cmd" ]] || return 0

  for ((i = 1; i <= attempts; i++)); do
    if eval "$runtime_cmd" >/dev/null 2>&1; then
      return 0
    fi
    [[ "$i" -lt "$attempts" ]] && sleep "$interval"
  done

  return 1
}

_ucc_wait_for_yaml_runtime_probe() {
  local cfg_dir="$1" yaml="$2" target="$3" runtime_cmd="$4"
  local attempts="${UCC_RUNTIME_WAIT_ATTEMPTS:-20}"
  local interval="${UCC_RUNTIME_WAIT_INTERVAL:-1}"
  local i

  [[ -n "$runtime_cmd" ]] || return 0

  for ((i = 1; i <= attempts; i++)); do
    if _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$runtime_cmd"; then
      return 0
    fi
    [[ "$i" -lt "$attempts" ]] && sleep "$interval"
  done

  return 1
}

# ucc_brew_runtime_formula_target <target-name> <brew-pkg> [brew-ref] [cfg_dir] [yaml] [service-name]
# Software-centric brew formula target: package presence, service lifecycle, and
# runtime probe are governed as one runtime-profile target.
ucc_brew_runtime_formula_target() {
  local tname="$1" pkg="$2" brew_ref="${3:-$2}" cfg_dir="${4:-}" yaml="${5:-}" service_name="${6:-$2}"
  _ucc_target_filtered_out "$tname" "$cfg_dir" "$yaml" && return 0
  local fn; fn="${tname//[^a-zA-Z0-9]/_}"
  eval "_ubrt_obs_${fn}() {
    local runtime_cmd configured_cmd
    if [[ -n '${cfg_dir}' && -n '${yaml}' ]]; then
      runtime_cmd=\"\$(_ucc_yaml_target_get '${cfg_dir}' '${yaml}' '${tname}' 'oracle.runtime')\"
      configured_cmd=\"\$(_ucc_yaml_target_get '${cfg_dir}' '${yaml}' '${tname}' 'oracle.configured')\"
    fi
    _ucc_observe_brew_runtime_formula '${pkg}' '${service_name}' \"\$runtime_cmd\" \"\$configured_cmd\" '${cfg_dir}' '${yaml}' '${tname}'
  }"
  eval "_ubrt_evd_${fn}() {
    if [[ -n '${cfg_dir}' && -n '${yaml}' ]]; then
      ucc_eval_evidence_from_yaml '${cfg_dir}' '${yaml}' '${tname}'
      return
    fi
    local ver
    ver=\$(_brew_cached_version '${pkg}')
    [[ -n \"\$ver\" ]] && printf 'version=%s' \"\$ver\"
  }"
  eval "_ubrt_ins_${fn}() {
    local runtime_cmd=''
    if [[ -n '${cfg_dir}' && -n '${yaml}' ]]; then
      runtime_cmd=\"\$(_ucc_yaml_target_get '${cfg_dir}' '${yaml}' '${tname}' 'oracle.runtime')\"
    fi
    _ucc_apply_brew_runtime_formula '${pkg}' '${brew_ref}' '${service_name}' \"\$runtime_cmd\" install '${cfg_dir}' '${yaml}' '${tname}'
  }"
  eval "_ubrt_upd_${fn}() {
    local runtime_cmd=''
    if [[ -n '${cfg_dir}' && -n '${yaml}' ]]; then
      runtime_cmd=\"\$(_ucc_yaml_target_get '${cfg_dir}' '${yaml}' '${tname}' 'oracle.runtime')\"
    fi
    _ucc_apply_brew_runtime_formula '${pkg}' '${brew_ref}' '${service_name}' \"\$runtime_cmd\" update '${cfg_dir}' '${yaml}' '${tname}'
  }"
  ucc_target_service --name "$tname" \
    --observe "_ubrt_obs_${fn}" \
    --evidence "_ubrt_evd_${fn}" \
    --desired "$(ucc_asm_runtime_desired)" \
    --install "_ubrt_ins_${fn}" \
    --update "_ubrt_upd_${fn}"
}
