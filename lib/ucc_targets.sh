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
  while IFS=$'\t' read -r _key _cmd; do
    [[ -z "$_key" || -z "$_cmd" ]] && continue
    _val=$(eval "$_cmd" 2>/dev/null || true)
    [[ -z "$_val" ]] && continue
    [[ $_first -eq 0 ]] && printf '  '
    printf '%s=%s' "$_key" "$_val"
    _first=0
  done < <(python3 "$cfg_dir/tools/read_config.py" --evidence "$yaml" "$target" 2>/dev/null)
}

_ucc_yaml_get() {
  local cfg_dir="$1" yaml="$2" key="$3" default="${4:-}" val=""
  val="$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" "$key" 2>/dev/null || true)"
  printf '%s' "${val:-$default}"
}

# ── Convenience target helpers ────────────────────────────────────────────────

_ucc_display_name() {
  case "$1" in
    ai-stack-compose-file) printf 'compose file' ;;
    open-webui-runtime)    printf 'Open WebUI' ;;
    flowise-runtime)       printf 'Flowise' ;;
    openhands-runtime)     printf 'OpenHands' ;;
    n8n-runtime)           printf 'n8n' ;;
    qdrant-runtime)        printf 'Qdrant' ;;
    docker-desktop)        printf 'Docker Desktop' ;;
    unsloth-studio)        printf 'Unsloth Studio' ;;
    system-composition)    printf 'composition' ;;
    *)                     printf '%s' "$1" ;;
  esac
}

_ucc_emit_target_line() {
  local profile="$1" status="$2" name="$3" detail="${4:-}" line=""
  if [[ -n "$detail" ]]; then
    line=$(printf '      [%-8s] %-30s %s' "$status" "$name" "$detail")
  else
    line=$(printf '      [%-8s] %s' "$status" "$name")
  fi
  _ucc_emit_profile_line "$profile" "$line"
}

# ucc_brew_target <target-name> <brew-pkg>
# Standard brew formula: install=brew install, update=brew upgrade
ucc_brew_target() {
  local tname="$1" pkg="$2"
  local fn; fn="${pkg//[^a-zA-Z0-9]/_}"
  eval "_ubt_obs_${fn}() { local raw; raw=\$(brew_observe '${pkg}'); ucc_asm_package_state \"\$raw\"; }"
  eval "_ubt_evd_${fn}() { local ver; ver=\$(_brew_cached_version '${pkg}'); [[ -n \"\$ver\" ]] && printf 'version=%s' \"\$ver\"; }"
  eval "_ubt_ins_${fn}() { brew_install  '${pkg}'; }"
  eval "_ubt_upd_${fn}() { brew_upgrade  '${pkg}'; }"
  ucc_target --profile presence --name "$tname" --observe "_ubt_obs_${fn}" \
             --evidence "_ubt_evd_${fn}" \
             --install "_ubt_ins_${fn}" --update "_ubt_upd_${fn}"
}

_ucc_brew_service_status() {
  local service_name="$1"
  brew services list 2>/dev/null | awk -v svc="$service_name" '$1==svc {print $2; found=1} END {if (!found) print ""}'
}

_ucc_observe_brew_runtime_formula() {
  local pkg="$1" service_name="$2" runtime_cmd="${3:-}" configured_cmd="${4:-}"
  local pkg_state svc_status

  pkg_state="$(brew_observe "$pkg")"
  svc_status="$(_ucc_brew_service_status "$service_name")"

  if [[ "$pkg_state" == "absent" ]]; then
    ucc_asm_state --installation Absent --runtime NeverStarted --health Unavailable --admin Enabled --dependencies DepsUnknown
    return
  fi

  if [[ "$pkg_state" == "outdated" ]]; then
    if [[ "$svc_status" == "started" ]]; then
      ucc_asm_state --installation Installed --runtime Running --health Degraded --admin Enabled --dependencies DepsDegraded
    else
      ucc_asm_state --installation Installed --runtime Stopped --health Degraded --admin Enabled --dependencies DepsDegraded
    fi
    return
  fi

  if [[ -n "$configured_cmd" ]] && ! eval "$configured_cmd" >/dev/null 2>&1; then
    ucc_asm_state --installation Installed --runtime Stopped --health Degraded --admin Enabled --dependencies DepsDegraded
    return
  fi

  if [[ "$svc_status" != "started" ]]; then
    ucc_asm_state --installation Configured --runtime Stopped --health Degraded --admin Enabled --dependencies DepsDegraded
    return
  fi

  if [[ -n "$runtime_cmd" ]] && ! eval "$runtime_cmd" >/dev/null 2>&1; then
    ucc_asm_state --installation Configured --runtime Running --health Degraded --admin Enabled --dependencies DepsDegraded
    return
  fi

  ucc_asm_runtime_desired
}

_ucc_apply_brew_runtime_formula() {
  local pkg="$1" brew_ref="$2" service_name="$3" runtime_cmd="${4:-}" mode="${5:-install}"
  local pkg_state

  pkg_state="$(brew_observe "$pkg")"
  if [[ "$pkg_state" == "absent" ]]; then
    brew_install "$brew_ref" || return 1
  elif [[ "$pkg_state" == "outdated" || "$mode" == "update" ]]; then
    brew_upgrade "$brew_ref" || return 1
  fi

  if [[ "$(_ucc_brew_service_status "$service_name")" == "started" ]]; then
    ucc_run brew services restart "$brew_ref" || return 1
  else
    ucc_run brew services start "$brew_ref" || return 1
  fi

  [[ -n "$runtime_cmd" ]] && _ucc_wait_for_runtime_probe "$runtime_cmd"
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

# ucc_brew_runtime_formula_target <target-name> <brew-pkg> [brew-ref] [cfg_dir] [yaml] [service-name]
# Software-centric brew formula target: package presence, service lifecycle, and
# runtime probe are governed as one runtime-profile target.
ucc_brew_runtime_formula_target() {
  local tname="$1" pkg="$2" brew_ref="${3:-$2}" cfg_dir="${4:-}" yaml="${5:-}" service_name="${6:-$2}"
  local fn; fn="${tname//[^a-zA-Z0-9]/_}"
  eval "_ubrt_obs_${fn}() {
    local runtime_cmd configured_cmd
    if [[ -n '${cfg_dir}' && -n '${yaml}' ]]; then
      runtime_cmd=\"\$(_ucc_yaml_get '${cfg_dir}' '${yaml}' 'targets.${tname}.oracle.runtime')\"
      configured_cmd=\"\$(_ucc_yaml_get '${cfg_dir}' '${yaml}' 'targets.${tname}.oracle.configured')\"
    fi
    _ucc_observe_brew_runtime_formula '${pkg}' '${service_name}' \"\$runtime_cmd\" \"\$configured_cmd\"
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
      runtime_cmd=\"\$(_ucc_yaml_get '${cfg_dir}' '${yaml}' 'targets.${tname}.oracle.runtime')\"
    fi
    _ucc_apply_brew_runtime_formula '${pkg}' '${brew_ref}' '${service_name}' \"\$runtime_cmd\" install
  }"
  eval "_ubrt_upd_${fn}() {
    local runtime_cmd=''
    if [[ -n '${cfg_dir}' && -n '${yaml}' ]]; then
      runtime_cmd=\"\$(_ucc_yaml_get '${cfg_dir}' '${yaml}' 'targets.${tname}.oracle.runtime')\"
    fi
    _ucc_apply_brew_runtime_formula '${pkg}' '${brew_ref}' '${service_name}' \"\$runtime_cmd\" update
  }"
  ucc_target_service --name "$tname" \
    --observe "_ubrt_obs_${fn}" \
    --evidence "_ubrt_evd_${fn}" \
    --desired "$(ucc_asm_runtime_desired)" \
    --install "_ubrt_ins_${fn}" \
    --update "_ubrt_upd_${fn}"
}

# ucc_brew_cask_target <target-name> <cask-pkg>
# Standard brew cask: install=brew install --cask, update=brew upgrade --cask
ucc_brew_cask_target() {
  local tname="$1" pkg="$2"
  local fn; fn="${pkg//[^a-zA-Z0-9]/_}"
  eval "_ubct_obs_${fn}() { local raw; raw=\$(brew_cask_observe '${pkg}'); ucc_asm_package_state \"\$raw\"; }"
  eval "_ubct_evd_${fn}() { local ver; ver=\$(_brew_cask_cached_version '${pkg}'); [[ -n \"\$ver\" ]] && printf 'version=%s' \"\$ver\"; }"
  eval "_ubct_ins_${fn}() { brew_cask_install '${pkg}'; }"
  eval "_ubct_upd_${fn}() { brew_cask_upgrade '${pkg}'; }"
  ucc_target --profile presence --name "$tname" --observe "_ubct_obs_${fn}" \
             --evidence "_ubct_evd_${fn}" \
             --install "_ubct_ins_${fn}" --update "_ubct_upd_${fn}"
}

# ucc_npm_target <npm-pkg>
# Global npm package: observe=npm ls -g desired=current install=npm install -g update=npm update -g
ucc_npm_target() {
  local pkg="$1"
  local fn; fn="${pkg//[@\/]/_}"
  eval "_unt_obs_${fn}() { local raw; raw=\$(npm ls -g '${pkg}' --depth=0 --json 2>/dev/null | python3 -c \"import sys,json; d=json.load(sys.stdin); deps=d.get('dependencies',{}); k=next(iter(deps),''); print(deps[k].get('version','present') if k else 'absent')\" 2>/dev/null || echo 'absent'); ucc_asm_package_state \"\$raw\"; }"
  eval "_unt_evd_${fn}() { local ver; ver=\$(npm ls -g '${pkg}' --depth=0 --json 2>/dev/null | python3 -c \"import sys,json; d=json.load(sys.stdin); deps=d.get('dependencies',{}); k=next(iter(deps),''); print(deps[k].get('version','')) if k else None\" 2>/dev/null); [[ -n \"\$ver\" ]] && printf 'version=%s' \"\$ver\"; }"
  eval "_unt_ins_${fn}() { ucc_run npm install -g '${pkg}'; }"
  eval "_unt_upd_${fn}() { ucc_run npm update  -g '${pkg}'; }"
  ucc_target --profile presence --name "npm-global-${pkg}" --observe "_unt_obs_${fn}" \
             --evidence "_unt_evd_${fn}" \
             --install "_unt_ins_${fn}" --update "_unt_upd_${fn}"
}

# ucc_pyenv_version_target <target-name> <version>
# pyenv-managed language version: observe=pyenv versions, install=pyenv install+global
ucc_pyenv_version_target() {
  local tname="$1" ver="$2"
  local fn; fn="${tname//[^a-zA-Z0-9]/_}"
  eval "_upvt_obs_${fn}() { ucc_asm_package_state \"\$(pyenv versions 2>/dev/null | grep -q '${ver}' && echo '${ver}' || echo 'absent')\"; }"
  eval "_upvt_evd_${fn}() { local v p; v=\$(python3 --version 2>/dev/null | awk '{print \$2}'); p=\$(pyenv which python3 2>/dev/null || command -v python3 2>/dev/null || true); [[ -n \"\$v\" ]] && printf 'version=%s' \"\$v\"; [[ -n \"\$p\" ]] && printf '  path=%s' \"\$p\"; }"
  eval "_upvt_ins_${fn}() { pyenv install '${ver}'; pyenv global '${ver}'; }"
  eval "_upvt_upd_${fn}() { pyenv install --skip-existing '${ver}'; pyenv global '${ver}'; }"
  ucc_target_nonruntime --name "$tname" \
    --observe  "_upvt_obs_${fn}" \
    --evidence "_upvt_evd_${fn}" \
    --install  "_upvt_ins_${fn}" \
    --update   "_upvt_upd_${fn}"
}

# ── _ucc_record_outcome — shared emit+count+record for all outcome paths ───────
# Usage: _ucc_record_outcome <profile> <name> <COUNTER|""> <target_status> \
#                             <summary_status> <msg_id> <started_at> <diff_json> <result_json>
# COUNTER: CONVERGED | CHANGED | FAILED | "" (unchanged / dry-run paths)
_ucc_record_outcome() {
  local _p="$1" _n="$2" _ctr="$3" _tst="$4" _sst="$5" _mid="$6" _sat="$7" _dif="$8" _res="$9"
  [[ -n "$_ctr" ]] && eval "_UCC_${_ctr}=\$(( _UCC_${_ctr} + 1 ))"
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

_ucc_require_declared_dependencies_resolved() {
  local target="$1" deps="" dep status
  [[ -n "${UCC_TARGETS_MANIFEST:-}" && -n "${UCC_TARGETS_QUERY_SCRIPT:-}" ]] || return 0
  deps=$(python3 "$UCC_TARGETS_QUERY_SCRIPT" --deps "$target" "$UCC_TARGETS_MANIFEST" 2>/dev/null || true)
  [[ -n "$deps" ]] || return 0
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    status="$(_ucc_target_status_value "$dep")"
    [[ -n "$status" ]] || {
      printf '      [%-8s] %-30s declared dependency unresolved: %s\n' "dep-fail" "$(_ucc_display_name "$target")" "$dep"
      return 1
    }
  done <<< "$deps"
  return 0
}

# ── ucc_target — full UCC Steps 0-6 lifecycle per target ─────────────────────

_ucc_execute_target() {
  local _ucc_snapshot="${UCC_EXEC_SNAPSHOT:-}"
  if [[ -n "$_ucc_snapshot" ]]; then
    eval "$_ucc_snapshot"
  fi

  local name="" observe_fn="" desired="" install_fn="" update_fn="" axes="" profile="" evidence_fn=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)    name="$2";       shift 2 ;;
      --observe) observe_fn="$2"; shift 2 ;;
      --desired) desired="$2";    shift 2 ;;
      --install) install_fn="$2"; shift 2 ;;
      --update)  update_fn="$2";  shift 2 ;;
      --axes)    axes="$2";       shift 2 ;;
      --evidence) evidence_fn="$2"; shift 2 ;;
      --kind)    profile="$2";    shift 2 ;;
      --profile) profile="$2";    shift 2 ;;
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
    if _ucc_is_json_obj "$obs" || _ucc_is_json_obj "$des"; then
      _ucc_json_equal "$obs" "$des" "$axes" && return 0
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
        _ucc_emit_target_line "$profile" "dry-run" "$display_name" "state=\"$(_ucc_display_state "$observed" "$axes")\" (update skipped)"
        _ucc_record_outcome "$profile" "$name" "" "unchanged" "unchanged" "$msg_id" "$started_at" \
          "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":{}}" \
          "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"dry_run\",\"message\":\"update transition not applied due to dry-run mode\"}"
        return 0
      fi
      if $update_fn; then
        local verified ver_exit
        verified=$($observe_fn 2>/dev/null)
        ver_exit=$?
        if [[ $ver_exit -eq 0 ]] && _ucc_satisfied "$verified" "$desired"; then
          _ucc_emit_target_line "$profile" "updated" "$display_name" "\"$(_ucc_display_state "$observed" "$axes")\" -> \"$(_ucc_display_state "$verified" "$axes")\""
          _ucc_record_outcome "$profile" "$name" "CHANGED" "ok" "changed" "$msg_id" "$started_at" \
            "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$verified" "$axes"),\"observed_after\":$(_ucc_state_obj "$verified")}" \
            "{\"observation\":\"ok\",\"outcome\":\"changed\",\"completion\":\"complete\",\"proof\":{\"change\":\"update_applied\"}}"
        else
          _ucc_emit_target_line "$profile" "fail" "$display_name" "verify after update: \"$(_ucc_display_state "${verified:-?}" "$axes")\"  $(_ucc_compose_evidence "$name" "${verified:-$observed}" "$axes" "$evidence_fn")"
          _ucc_record_outcome "$profile" "$name" "FAILED" "failed" "failed" "$msg_id" "$started_at" \
            "{}" "{\"observation\":\"failed\",\"message\":\"post-update verify did not reach desired state\"}"
        fi
      else
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
    _ucc_emit_target_line "$profile" "dry-run" "$display_name" "\"$(_ucc_display_state "$observed" "$axes")\" -> \"$(_ucc_display_state "$desired" "$axes")\""
    _ucc_record_outcome "$profile" "$name" "" "unchanged" "unchanged" "$msg_id" "$started_at" \
      "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$desired" "$axes")}" \
      "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"dry_run\",\"message\":\"transition not applied due to dry-run mode\"}"
    return 0
  fi

  if [[ -z "$install_fn" ]]; then
    _ucc_emit_target_line "$profile" "policy" "$display_name" "\"$(_ucc_display_state "$observed" "$axes")\" -> \"$(_ucc_display_state "$desired" "$axes")\""
    _ucc_record_outcome "$profile" "$name" "" "unchanged" "unchanged" "$msg_id" "$started_at" \
      "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$desired" "$axes")}" \
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
    # Step 5 – Verify: re-observe after transition
    local verified ver_exit
    verified=$($observe_fn 2>/dev/null)
    ver_exit=$?
    log_debug "post-install observed=\"$verified\""
    if [[ $ver_exit -eq 0 ]] && _ucc_satisfied "$verified" "$desired"; then
      _ucc_emit_target_line "$profile" "$action_label" "$display_name" "\"$(_ucc_display_state "$observed" "$axes")\" -> \"$(_ucc_display_state "$verified" "$axes")\""
      _ucc_record_outcome "$profile" "$name" "CHANGED" "ok" "changed" "$msg_id" "$started_at" \
        "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$verified" "$axes"),\"observed_after\":$(_ucc_state_obj "$verified")}" \
        "{\"observation\":\"ok\",\"outcome\":\"changed\",\"completion\":\"complete\",\"proof\":{\"change\":\"verify_pass\"}}"
    else
      _ucc_emit_target_line "$profile" "fail" "$display_name" "verify after install: \"$(_ucc_display_state "${verified:-?}" "$axes")\"  $(_ucc_compose_evidence "$name" "${verified:-$observed}" "$axes" "$evidence_fn")"
      _ucc_record_outcome "$profile" "$name" "FAILED" "failed" "failed" "$msg_id" "$started_at" \
        "{}" "{\"observation\":\"failed\",\"message\":\"post-install verify did not reach desired state\"}"
    fi
  else
    _ucc_emit_target_line "$profile" "fail" "$display_name" "install error was=\"$(_ucc_display_state "$observed" "$axes")\"  $(_ucc_compose_evidence "$name" "$observed" "$axes" "$evidence_fn")"
    _ucc_record_outcome "$profile" "$name" "FAILED" "failed" "failed" "$msg_id" "$started_at" \
      "{}" "{\"observation\":\"failed\",\"message\":\"install function failed\"}"
  fi
}

ucc_flush_registered_targets() {
  local component="$1" ordered="" target idx
  local declared=() undeclared=()
  [[ ${#_UCC_REGISTERED_NAMES[@]} -gt 0 ]] || return 0

  if [[ -n "${UCC_TARGETS_MANIFEST:-}" && -n "${UCC_TARGETS_QUERY_SCRIPT:-}" ]]; then
    ordered="$(python3 "$UCC_TARGETS_QUERY_SCRIPT" --ordered-targets "$component" "$UCC_TARGETS_MANIFEST" 2>/dev/null || true)"
  fi

  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    declared+=("$target")
  done <<< "$ordered"

  for target in "${declared[@]}"; do
    idx="$(_ucc_registered_index "$target" || true)"
    [[ -n "$idx" ]] || continue
    _ucc_require_declared_dependencies_resolved "$target" || return 1
    UCC_EXEC_SNAPSHOT="${_UCC_REGISTERED_ENV[$idx]}" eval "_ucc_execute_target ${_UCC_REGISTERED_ARGS[$idx]}" || return 1
  done

  local name seen
  for idx in "${!_UCC_REGISTERED_NAMES[@]}"; do
    name="${_UCC_REGISTERED_NAMES[$idx]}"
    seen=0
    for target in "${declared[@]}"; do
      [[ "$target" == "$name" ]] && { seen=1; break; }
    done
    [[ "$seen" -eq 1 ]] && continue
    log_warn "Target '$name' is not declared in the manifest; executing after topo-sorted targets with no dependencies"
    undeclared+=("$idx")
  done

  for idx in "${undeclared[@]}"; do
    UCC_EXEC_SNAPSHOT="${_UCC_REGISTERED_ENV[$idx]}" eval "_ucc_execute_target ${_UCC_REGISTERED_ARGS[$idx]}" || return 1
  done
}

ucc_target() {
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
      --kind|--profile) has_profile=1; args+=("$1" "$2"); shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  [[ "$has_profile" -eq 0 ]] && args+=(--profile "$_default")
  ucc_target "${args[@]}"
}

ucc_target_nonruntime() { _ucc_target_with_default_profile configured "$@"; }
ucc_target_service()    { _ucc_target_with_default_profile runtime    "$@"; }

ucc_skip_target() {
  local name="$1" reason="$2"
  local display_name
  display_name="$(_ucc_display_name "$name")"
  printf '      [%-8s] %-30s %s\n' "skip" "$display_name" "$reason"
  _UCC_SKIPPED=$(( ${_UCC_SKIPPED:-0} + 1 ))
}

# ── ucc_summary — write per-component counts to summary file ──────────────────

ucc_summary() {
  local comp="${1:-}"
  if [[ -n "${UCC_SUMMARY_FILE:-}" && -n "$comp" ]]; then
    printf '%s|%d|%d|%d|%d\n' "$comp" "$_UCC_CONVERGED" "$_UCC_CHANGED" "$_UCC_FAILED" "${_UCC_SKIPPED:-0}" \
      >> "$UCC_SUMMARY_FILE" 2>/dev/null || true
  fi
}
