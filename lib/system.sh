#!/usr/bin/env bash
# lib/system.sh — System-level composition target

# Usage: run_system_from_yaml <cfg_dir> <yaml_path>
run_system_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  local system_kind system_signature expected_count
  local SYSTEM_DEPENDENCIES=()
  local dep

  system_kind="$(yaml_get "$cfg_dir" "$yaml" system.kind host-composition)"
  while IFS= read -r dep; do
    [[ -n "$dep" ]] && SYSTEM_DEPENDENCIES+=("$dep")
  done < <(yaml_list "$cfg_dir" "$yaml" system.depends_on)

  expected_count="${#SYSTEM_DEPENDENCIES[@]}"
  system_signature="$(printf '%s\n' "${SYSTEM_DEPENDENCIES[@]}" | LC_ALL=C sort | paste -sd, -)"

  _system_status_for() {
    local target="$1"
    awk -F'|' -v dep="$target" '$1==dep {val=$2} END {print val}' "${UCC_TARGET_STATUS_FILE:-}" 2>/dev/null || true
  }

  _system_desired_state() {
    ucc_asm_state --installation Configured --runtime Running \
      --health Healthy --admin Enabled --dependencies DepsReady \
      --config-value "kind=${system_kind} targets=${system_signature}"
  }

  _observe_system_composition() {
    local total=0 ok=0 failed=() unknown=() status target

    if [[ -z "${UCC_TARGET_STATUS_FILE:-}" || ! -f "${UCC_TARGET_STATUS_FILE:-}" ]]; then
      ucc_asm_state --installation Installed --runtime Stopped \
        --health Unknown --admin Enabled --dependencies DepsUnknown \
        --config-value "kind=${system_kind} targets=${system_signature}"
      return
    fi

    for target in "${SYSTEM_DEPENDENCIES[@]}"; do
      total=$((total + 1))
      status="$(_system_status_for "$target")"
      case "$status" in
        ok) ok=$((ok + 1)) ;;
        failed) failed+=("$target") ;;
        ""|unknown|unchanged) unknown+=("$target") ;;
        *) unknown+=("$target") ;;
      esac
    done

    if [[ "$ok" -eq "$expected_count" ]]; then
      _system_desired_state
      return
    fi

    if [[ ${#failed[@]} -gt 0 ]]; then
      ucc_asm_state --installation Installed --runtime Stopped \
        --health Unhealthy --admin Enabled --dependencies DepsFailed \
        --config-value "kind=${system_kind} ok=${ok}/${total} failed=$(IFS=,; echo "${failed[*]}")"
      return
    fi

    ucc_asm_state --installation Installed --runtime Stopped \
      --health Degraded --admin Enabled --dependencies DepsDegraded \
      --config-value "kind=${system_kind} ok=${ok}/${total} pending=$(IFS=,; echo "${unknown[*]}")"
  }

  _evidence_system_composition() {
    local target status total=0 ok=0 failed=0 pending=0
    for target in "${SYSTEM_DEPENDENCIES[@]}"; do
      total=$((total + 1))
      status="$(_system_status_for "$target")"
      case "$status" in
        ok) ok=$((ok + 1)) ;;
        failed) failed=$((failed + 1)) ;;
        *) pending=$((pending + 1)) ;;
      esac
    done
    printf 'kind=%s  required=%s  ready=%s/%s' "$system_kind" "$expected_count" "$ok" "$total"
    [[ "$failed" -gt 0 ]] && printf '  failed=%s' "$failed"
    [[ "$pending" -gt 0 ]] && printf '  pending=%s' "$pending"
  }

  _reconcile_system_composition() {
    log_info "system-composition is derived from subsystem convergence; no direct mutation is applied"
    return 0
  }

  ucc_target \
    --name "system-composition" \
    --profile parametric \
    --observe _observe_system_composition \
    --evidence _evidence_system_composition \
    --desired "$(_system_desired_state)" \
    --install _reconcile_system_composition \
    --update _reconcile_system_composition
}
