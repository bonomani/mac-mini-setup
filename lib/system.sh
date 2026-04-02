#!/usr/bin/env bash
# lib/system.sh — System component: OS-level config + composition

# Usage: run_system_from_yaml <cfg_dir> <yaml_path>
run_system_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  local query_script manifest_dir ordered target
  query_script="${UCC_TARGETS_QUERY_SCRIPT:-$cfg_dir/tools/validate_targets_manifest.py}"
  manifest_dir="${UCC_TARGETS_MANIFEST:-$cfg_dir/ucc}"
  ordered="$(python3 "$query_script" --ordered-targets system "$manifest_dir" 2>/dev/null || true)"

  # Probe sudo capability (informational — drivers guard their own actions)

  while IFS= read -r target; do
    [[ -n "$target" ]] || continue

    # system-composition is handled separately at the end
    [[ "$target" == "system-composition" ]] && continue

    # sudo-available capability
    if [[ "$target" == "sudo-available" ]]; then
      ucc_yaml_capability_target "$cfg_dir" "$yaml" "sudo-available"
      continue
    fi

    # All targets run observe (read-only). Admin targets that need changes
    # will fail gracefully at the driver action level if sudo is unavailable.
    ucc_yaml_parametric_target "$cfg_dir" "$yaml" "$target"
  done <<< "$ordered"

  # Restart UI processes if any defaults changed
  if [[ "$UCC_DRY_RUN" != "1" && ${_UCC_CHANGED:-0} -gt 0 ]]; then
    while IFS= read -r _proc; do
      [[ -n "$_proc" ]] && { killall "$_proc" 2>/dev/null || true; }
    done < <(yaml_list "$cfg_dir" "$yaml" restart_processes)
    log_info "UI processes restarted"
  fi

  # System composition — derives state from OS-level targets
  _system_observe() {
    local _total=0 _ok=0 _failed=0 _status
    while IFS= read -r _t; do
      [[ -n "$_t" && "$_t" != "system-composition" ]] || continue
      _total=$((_total + 1))
      _status="$(awk -F'|' -v dep="$_t" '$1==dep {val=$2} END {print val}' "${UCC_TARGET_STATUS_FILE:-}" 2>/dev/null || true)"
      case "$_status" in
        ok) _ok=$((_ok + 1)) ;;
        failed) _failed=$((_failed + 1)) ;;
      esac
    done <<< "$ordered"
    if [[ "$_ok" -eq "$_total" && "$_total" -gt 0 ]]; then
      ucc_asm_state --installation Configured --runtime Running \
        --health Healthy --admin Enabled --dependencies DepsReady \
        --config-value "kind=os-config ok=${_ok}/${_total}"
    elif [[ "$_failed" -gt 0 ]]; then
      ucc_asm_state --installation Installed --runtime Stopped \
        --health Unhealthy --admin Enabled --dependencies DepsFailed \
        --config-value "kind=os-config ok=${_ok}/${_total} failed=${_failed}"
    else
      ucc_asm_state --installation Installed --runtime Stopped \
        --health Degraded --admin Enabled --dependencies DepsDegraded \
        --config-value "kind=os-config ok=${_ok}/${_total}"
    fi
  }

  _system_evidence() {
    local _total=0 _ok=0 _failed=0 _pending=0 _status
    while IFS= read -r _t; do
      [[ -n "$_t" && "$_t" != "system-composition" ]] || continue
      _total=$((_total + 1))
      _status="$(awk -F'|' -v dep="$_t" '$1==dep {val=$2} END {print val}' "${UCC_TARGET_STATUS_FILE:-}" 2>/dev/null || true)"
      case "$_status" in ok) _ok=$((_ok + 1)) ;; failed) _failed=$((_failed + 1)) ;; *) _pending=$((_pending + 1)) ;; esac
    done <<< "$ordered"
    printf 'kind=os-config  ready=%s/%s' "$_ok" "$_total"
    [[ "$_failed" -gt 0 ]] && printf '  failed=%s' "$_failed"
    [[ "$_pending" -gt 0 ]] && printf '  pending=%s' "$_pending"
  }

  _system_desired() {
    local _total=0
    while IFS= read -r _t; do
      [[ -n "$_t" && "$_t" != "system-composition" ]] || continue
      _total=$((_total + 1))
    done <<< "$ordered"
    ucc_asm_state --installation Configured --runtime Running \
      --health Healthy --admin Enabled --dependencies DepsReady \
      --config-value "kind=os-config ok=${_total}/${_total}"
  }

  _system_noop() {
    log_info "system-composition is derived — no direct mutation"
    return 0
  }

  ucc_target \
    --name "system-composition" \
    --profile parametric \
    --observe _system_observe \
    --evidence _system_evidence \
    --desired "$(_system_desired)" \
    --install _system_noop \
    --update _system_noop
}
