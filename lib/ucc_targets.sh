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

# ── Convenience target helpers ────────────────────────────────────────────────

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

# ucc_brew_cask_target <target-name> <cask-pkg>
# Standard brew cask: install=brew install --cask, update=brew upgrade --cask
ucc_brew_cask_target() {
  local tname="$1" pkg="$2"
  local fn; fn="${pkg//[^a-zA-Z0-9]/_}"
  eval "_ubct_obs_${fn}() { local raw; raw=\$(brew_cask_observe '${pkg}'); ucc_asm_package_state \"\$raw\"; }"
  eval "_ubct_evd_${fn}() { local ver; ver=\$(brew list --cask --versions '${pkg}' 2>/dev/null | awk '{print \$NF}'); [[ -n \"\$ver\" ]] && printf 'version=%s' \"\$ver\"; }"
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
  eval "_upvt_evd_${fn}() { local v p; v=\$(python3 --version 2>/dev/null | awk '{print \$2}'); p=\$(pyenv which python3 2>/dev/null || command -v python3 2>/dev/null || true); [[ -n \"\$v\" ]] && printf 'version=%s' \"\$v\"; [[ -n \"\$p\" ]] && printf ' path=%s' \"\$p\"; }"
  eval "_upvt_ins_${fn}() { pyenv install '${ver}'; pyenv global '${ver}'; }"
  eval "_upvt_upd_${fn}() { pyenv install --skip-existing '${ver}'; pyenv global '${ver}'; }"
  ucc_target_nonruntime --name "$tname" \
    --observe  "_upvt_obs_${fn}" \
    --evidence "_upvt_evd_${fn}" \
    --install  "_upvt_ins_${fn}" \
    --update   "_upvt_upd_${fn}"
}

# ── ucc_target — full UCC Steps 0-6 lifecycle per target ─────────────────────

ucc_target() {
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
    _ucc_emit_profile_line "$profile" "$(printf '  %-46s  obs-failed  (observe fn exited non-zero)' "$name")"
    _UCC_FAILED=$(( _UCC_FAILED + 1 ))
    _ucc_record_profile_summary "$profile" "failed"
    _ucc_record_target_status "$name" "failed"
    duration_ms=$(_ucc_duration_ms "$started_at")
    _ucc_record_result "$msg_id" "$duration_ms" "{}" \
      "{\"observation\":\"failed\",\"message\":\"observe function exited non-zero\"}"
    return 0
  fi

  # observation=indeterminate: observe ran (exit 0) but produced no usable state
  if [[ -z "$observed" ]]; then
    _ucc_emit_profile_line "$profile" "$(printf '  %-46s  indeterminate  (observe returned no state)' "$name")"
    _UCC_FAILED=$(( _UCC_FAILED + 1 ))
    _ucc_record_profile_summary "$profile" "failed"
    _ucc_record_target_status "$name" "failed"
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
        _ucc_emit_profile_line "$profile" "$(printf '  %-46s  dry-run  state=\"%s\"  (update skipped)' "$name" "$(_ucc_display_state "$observed" "$axes")")"
        _ucc_record_profile_summary "$profile" "unchanged"
        _ucc_record_target_status "$name" "unchanged"
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
          _ucc_emit_profile_line "$profile" "$(printf '  %-46s  updated  \"%s\" → \"%s\"' "$name" "$(_ucc_display_state "$observed" "$axes")" "$(_ucc_display_state "$verified" "$axes")")"
          _UCC_CHANGED=$(( _UCC_CHANGED + 1 ))
          _ucc_record_profile_summary "$profile" "changed"
          _ucc_record_target_status "$name" "ok"
          duration_ms=$(_ucc_duration_ms "$started_at")
          _ucc_record_result "$msg_id" "$duration_ms" \
            "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$verified" "$axes"),\"observed_after\":$(_ucc_state_obj "$verified")}" \
            "{\"observation\":\"ok\",\"outcome\":\"changed\",\"completion\":\"complete\",\"proof\":{\"change\":\"update_applied\"}}"
        else
          _ucc_emit_profile_line "$profile" "$(printf '  %-46s  FAILED — verify after update: \"%s\"' "$name" "$(_ucc_display_state "${verified:-?}" "$axes")")"
          _UCC_FAILED=$(( _UCC_FAILED + 1 ))
          _ucc_record_profile_summary "$profile" "failed"
          _ucc_record_target_status "$name" "failed"
          duration_ms=$(_ucc_duration_ms "$started_at")
          _ucc_record_result "$msg_id" "$duration_ms" \
            "{}" \
            "{\"observation\":\"failed\",\"message\":\"post-update verify did not reach desired state\"}"
        fi
      else
        _ucc_emit_profile_line "$profile" "$(printf '  %-46s  FAILED — update error  state=\"%s\"' "$name" "$(_ucc_display_state "$observed" "$axes")")"
        _UCC_FAILED=$(( _UCC_FAILED + 1 ))
        _ucc_record_profile_summary "$profile" "failed"
        _ucc_record_target_status "$name" "failed"
        duration_ms=$(_ucc_duration_ms "$started_at")
        _ucc_record_result "$msg_id" "$duration_ms" \
          "{}" \
          "{\"observation\":\"failed\",\"message\":\"update function failed\"}"
      fi
    else
      # Already at desired state
      _ucc_emit_profile_line "$profile" "$(printf '  %-46s  ok  %s' "$name" "$(_ucc_compose_evidence "$name" "$observed" "$axes" "$evidence_fn")")"
      _UCC_CONVERGED=$(( _UCC_CONVERGED + 1 ))
      _ucc_record_profile_summary "$profile" "ok"
      _ucc_record_target_status "$name" "ok"
      duration_ms=$(_ucc_duration_ms "$started_at")
      _ucc_record_result "$msg_id" "$duration_ms" \
        "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":{}}" \
        "{\"observation\":\"ok\",\"outcome\":\"converged\"}"
    fi
    return 0
  fi

  # Step 4: Apply transition
  if [[ "$UCC_DRY_RUN" == "1" ]]; then
    _ucc_emit_profile_line "$profile" "$(printf '  %-46s  dry-run  \"%s\" → \"%s\"' "$name" "$(_ucc_display_state "$observed" "$axes")" "$(_ucc_display_state "$desired" "$axes")")"
    _ucc_record_profile_summary "$profile" "unchanged"
    _ucc_record_target_status "$name" "unchanged"
    duration_ms=$(_ucc_duration_ms "$started_at")
    _ucc_record_result "$msg_id" "$duration_ms" \
      "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$desired" "$axes")}" \
      "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"dry_run\",\"message\":\"transition not applied due to dry-run mode\"}"
    return 0
  fi

  if [[ -z "$install_fn" ]]; then
    _ucc_emit_profile_line "$profile" "$(printf '  %-46s  no-install (policy)  \"%s\" → \"%s\"' "$name" "$(_ucc_display_state "$observed" "$axes")" "$(_ucc_display_state "$desired" "$axes")")"
    _ucc_record_profile_summary "$profile" "unchanged"
    _ucc_record_target_status "$name" "unchanged"
    duration_ms=$(_ucc_duration_ms "$started_at")
    _ucc_record_result "$msg_id" "$duration_ms" \
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
    _BREW_OUTDATED_STALE=1  # invalidate cache so verify sees post-upgrade state
    # Step 5 – Verify: re-observe after transition
    local verified ver_exit
    verified=$($observe_fn 2>/dev/null)
    ver_exit=$?
    log_debug "post-install observed=\"$verified\""
    if [[ $ver_exit -eq 0 ]] && _ucc_satisfied "$verified" "$desired"; then
      _ucc_emit_profile_line "$profile" "$(printf '  %-46s  %s  \"%s\" → \"%s\"' "$name" "$action_label" "$(_ucc_display_state "$observed" "$axes")" "$(_ucc_display_state "$verified" "$axes")")"
      _UCC_CHANGED=$(( _UCC_CHANGED + 1 ))
      _ucc_record_profile_summary "$profile" "changed"
      _ucc_record_target_status "$name" "ok"
      duration_ms=$(_ucc_duration_ms "$started_at")
      _ucc_record_result "$msg_id" "$duration_ms" \
        "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$verified" "$axes"),\"observed_after\":$(_ucc_state_obj "$verified")}" \
        "{\"observation\":\"ok\",\"outcome\":\"changed\",\"completion\":\"complete\",\"proof\":{\"change\":\"verify_pass\"}}"
    else
      _ucc_emit_profile_line "$profile" "$(printf '  %-46s  FAILED — verify after install: \"%s\"' "$name" "$(_ucc_display_state "${verified:-?}" "$axes")")"
      _UCC_FAILED=$(( _UCC_FAILED + 1 ))
      _ucc_record_profile_summary "$profile" "failed"
      _ucc_record_target_status "$name" "failed"
      duration_ms=$(_ucc_duration_ms "$started_at")
      _ucc_record_result "$msg_id" "$duration_ms" \
        "{}" \
        "{\"observation\":\"failed\",\"message\":\"post-install verify did not reach desired state\"}"
    fi
  else
    _ucc_emit_profile_line "$profile" "$(printf '  %-46s  FAILED — install error  was=\"%s\"' "$name" "$(_ucc_display_state "$observed" "$axes")")"
    _UCC_FAILED=$(( _UCC_FAILED + 1 ))
    _ucc_record_profile_summary "$profile" "failed"
    _ucc_record_target_status "$name" "failed"
    duration_ms=$(_ucc_duration_ms "$started_at")
    _ucc_record_result "$msg_id" "$duration_ms" \
      "{}" \
      "{\"observation\":\"failed\",\"message\":\"install function failed\"}"
  fi
}

ucc_target_nonruntime() {
  local desired="" has_profile=0 args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --desired)
        desired="$2"
        args+=("$1" "$2")
        shift 2
        ;;
      --kind|--profile)
        has_profile=1
        args+=("$1" "$2")
        shift 2
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done
  [[ "$has_profile" -eq 0 ]] && args+=(--profile configured)
  ucc_target "${args[@]}"
}

ucc_target_service() {
  local desired="" has_profile=0 args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --desired)
        desired="$2"
        args+=("$1" "$2")
        shift 2
        ;;
      --kind|--profile)
        has_profile=1
        args+=("$1" "$2")
        shift 2
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done
  [[ "$has_profile" -eq 0 ]] && args+=(--profile runtime)
  ucc_target "${args[@]}"
}

# ── ucc_summary — write per-component counts to summary file ──────────────────

ucc_summary() {
  local comp="${1:-}"
  if [[ -n "${UCC_SUMMARY_FILE:-}" && -n "$comp" ]]; then
    printf '%s|%d|%d|%d\n' "$comp" "$_UCC_CONVERGED" "$_UCC_CHANGED" "$_UCC_FAILED" \
      >> "$UCC_SUMMARY_FILE" 2>/dev/null || true
  fi
}
