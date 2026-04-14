#!/usr/bin/env bash
# lib/summary.sh — Final summary rendering for install.sh

# ── Profile counters ──────────────────────────────────────────────────────────

init_summary_counters() {
  _total_ok=0; _total_chg=0; _total_fail=0; _total_skip=0
  _summary_profiles=()
  local profile prefix
  for profile in "${_UCC_PROFILE_IDS[@]}"; do
    [[ -n "$profile" && "$profile" != "verification" ]] || continue
    _summary_profiles+=("$profile")
    prefix="$(_profile_var_prefix "$profile")"
    eval "${prefix}_ok=0"
    eval "${prefix}_chg=0"
    eval "${prefix}_fail=0"
  done
}

_summary_line() {
  local ok="${1:-0}" changed="${2:-0}" failed="${3:-0}" line=""
  line="${ok} ok"
  [[ "$changed" -gt 0 ]] && line="${line}  ${changed} changed"
  [[ "$failed"  -gt 0 ]] && line="${line}  ${failed} FAILED"
  printf '%s' "$line"
}

_profile_var_prefix() {
  local normalized="${1//[^a-zA-Z0-9_]/_}"
  [[ -n "$normalized" ]] && printf '_profile_%s' "$normalized" || printf ''
}

profile_bump() {
  local prefix
  prefix="$(_profile_var_prefix "$1")"
  [[ -z "$prefix" ]] && return 0
  case "$2" in
    ok|unchanged) eval "${prefix}_ok=\$(( ${prefix}_ok + 1 ))" ;;
    changed)      eval "${prefix}_chg=\$(( ${prefix}_chg + 1 ))" ;;
    failed)       eval "${prefix}_fail=\$(( ${prefix}_fail + 1 ))" ;;
  esac
}

# ── Section printers ──────────────────────────────────────────────────────────

print_layer_contracts() {
  printf '  %-19s | %s\n' "UIC Gates" "readiness/integrity/authorization pre-convergence"
  printf '  %-19s | %s\n' "TIC Verification" "post-convergence verification evidence"
}

print_profile_contracts() {
  local profile expected
  for profile in "${_UCC_PROFILE_IDS[@]}"; do
    [[ -n "$profile" && "$profile" != "verification" ]] || continue
    expected="$(ucc_profile_expected_text "$profile")"
    [[ -n "$expected" ]] || continue
    printf '  Profile %-10s | baseline: %s\n' "$(ucc_profile_label "$profile")" "$expected"
  done
}

_summary_component_label() {
  case "$1" in
    system) printf 'System' ;;
    verify) printf 'Verification' ;;
    *)      printf '%s' "$1" ;;
  esac
}

print_summary_section() {
  local section_label="$1"; shift
  local _comps=("$@")
  local _printed=0
  [[ ${#_comps[@]} -eq 0 ]] && return
  [[ -f "$UCC_SUMMARY_FILE" ]] || return
  while IFS='|' read -r _comp _a _b _c _d; do
    _comp_in_list "$_comp" "${_comps[@]}" || continue
    if [[ $_printed -eq 0 ]]; then
      echo "  ── $section_label"
      _printed=1
    fi
    if [[ "$_a" == "tic" ]]; then
      local _tic_parts="${_b} pass"
      [[ "$_c" -gt 0 ]] && _tic_parts="${_tic_parts}  ${_c} FAIL"
      [[ "$_d" -gt 0 ]] && _tic_parts="${_tic_parts}  skip=${_d}"
      printf '  %-22s  %s\n' "$(_summary_component_label "$_comp")" "$_tic_parts"
    else
      _total_ok=$(( _total_ok + _a ))
      _total_chg=$(( _total_chg + _b ))
      _total_fail=$(( _total_fail + _c ))
      _total_skip=$(( _total_skip + ${_d:-0} ))
      local _parts="" _all_zero=1
      [[ $_a -gt 0 ]]      && { _parts="${_a} ok"; _all_zero=0; }
      [[ $_b -gt 0 ]]      && { _parts="${_parts:+$_parts  }${_b} changed"; _all_zero=0; }
      [[ $_c -gt 0 ]]      && { _parts="${_parts:+$_parts  }${_c} FAILED"; _all_zero=0; }
      [[ ${_d:-0} -gt 0 ]] && { _parts="${_parts:+$_parts  }skip=${_d}"; _all_zero=0; }
      # If all counters are zero, count targets as skipped
      if [[ $_all_zero -eq 1 ]]; then
        local _comp_target_count
        _comp_target_count=$(python3 "${UCC_TARGETS_QUERY_SCRIPT:-$DIR/tools/validate_targets_manifest.py}" \
          --ordered-targets "$_comp" "${UCC_TARGETS_MANIFEST:-$DIR/ucc}" 2>/dev/null | wc -l)
        _comp_target_count=$(( _comp_target_count + 0 ))
        if [[ $_comp_target_count -gt 0 ]]; then
          _parts="skip=${_comp_target_count}"
          _total_skip=$(( _total_skip + _comp_target_count ))
        fi
      fi
      printf '  %-22s  %s\n' "$(_summary_component_label "$_comp")" "${_parts:----}"
    fi
  done < "$UCC_SUMMARY_FILE"
}

# Return 0 if the target reached a successful (or planned-dry-run) state
# during this run — i.e. its service endpoint will be (or already is)
# reachable. Returns 1 for failed, platform-skipped, or no-status (which
# covers disabled, requires-skipped, never-registered).
_target_endpoint_reachable() {
  local target="$1" status
  [[ -n "${UCC_TARGET_STATUS_FILE:-}" && -f "${UCC_TARGET_STATUS_FILE:-}" ]] || return 0
  status="$(awk -F'|' -v t="$target" '$1==t{val=$2} END{print val}' "$UCC_TARGET_STATUS_FILE")"
  case "$status" in
    failed|platform-skipped) return 1 ;;
    "")                      return 1 ;;
    *)                       return 0 ;;
  esac
}

print_services_summary() {
  local root_dir="$1"
  local query_script="$root_dir/tools/validate_targets_manifest.py"
  local manifest_dir="$root_dir/ucc"
  local rows="" name="" url="" note="" line=""
  [[ -f "$query_script" && -d "$manifest_dir" ]] || return 0
  rows="$(python3 "$query_script" --runtime-endpoints "$manifest_dir" 2>/dev/null || true)"
  [[ -n "$rows" ]] || return 0
  local _printed=0
  while IFS=$'\t' read -r _target name url note; do
    # Filter to current target set (empty set = nothing selected)
    if [[ "${UCC_TARGET_SET:-}" != *"${_target}|"* ]]; then
      continue
    fi
    # Filter to targets that actually reached a reachable state this run
    # (skip endpoints whose parent was disabled, platform-skipped, failed,
    # or requires:-filtered — they won't be answering on this host).
    if ! _target_endpoint_reachable "$_target"; then
      continue
    fi
    if [[ $_printed -eq 0 ]]; then
      echo "  ──────────────────────────────────────────────────────"
      echo "  Services"
      _printed=1
    fi
    line="    $(printf '%-16s' "$name") → ${url}"
    [[ -n "$note" ]] && line="${line}   (${note})"
    echo "$line"
  done <<< "$rows"
}

print_final_summary() {
  local dir="$1" mode="$2" dry_run="$3"
  local software_comps=(); local system_comps=(); local tic_comps=()
  # Callers pass arrays by name; read from globals set during run passes
  software_comps=(${_SOFTWARE_COMPS[@]+"${_SOFTWARE_COMPS[@]}"})
  system_comps=(${_SYSTEM_COMPS[@]+"${_SYSTEM_COMPS[@]}"})
  tic_comps=(${_TIC_COMPS[@]+"${_TIC_COMPS[@]}"})

  echo ""
  echo "========================================================"
  local _hdr="Summary | mode=${mode}"
  [[ "$dry_run" == "1" ]] && _hdr="${_hdr} | dry_run=1"
  echo "  ${_hdr}"
  echo "  ──────────────────────────────────────────────────────"

  init_summary_counters
  print_summary_section "Convergence / software" ${software_comps[@]+"${software_comps[@]}"}
  print_summary_section "Convergence / system"   ${system_comps[@]+"${system_comps[@]}"}
  print_summary_section "Verification"           ${tic_comps[@]+"${tic_comps[@]}"}

  echo "  ──────────────────────────────────────────────────────"
  local _total_line
  _total_line="$(_summary_line "$_total_ok" "$_total_chg" "$_total_fail")"
  [[ $_total_skip -gt 0 ]] && _total_line="${_total_line}  skip=${_total_skip}"
  printf '  %-22s  %s\n' "Total" "$_total_line"

  if [[ -f "$UCC_PROFILE_SUMMARY_FILE" ]]; then
    local profile prefix
    while IFS='|' read -r _profile _outcome; do
      profile_bump "$_profile" "$_outcome"
    done < "$UCC_PROFILE_SUMMARY_FILE"
    echo "  ──────────────────────────────────────────────────────"
    # "Total" above counts only targets already at desired state ([ok] lines).
    # "By Profile" counts every observation including dry-run plans, [ok], and
    # changed transitions — answers a different question, hence different sums.
    echo "  By Profile — observations (incl. dry-run plans)"
    for profile in "${_summary_profiles[@]}"; do
      prefix="$(_profile_var_prefix "$profile")"
      printf '  %-22s  %s\n' \
        "$(ucc_profile_label "$profile")" \
        "$(_summary_line "$(eval "printf '%s' \"\${${prefix}_ok}\"")" "$(eval "printf '%s' \"\${${prefix}_chg}\"")" "$(eval "printf '%s' \"\${${prefix}_fail}\"")")"
    done
  fi

  [[ ${#FAILED_COMPONENTS[@]} -gt 0 ]] && { echo ""; log_warn "Failed components: ${FAILED_COMPONENTS[*]}"; }

  print_services_summary "$dir"
  echo "  ──────────────────────────────────────────────────────"
  echo "  Declarations: $UCC_DECLARATION_FILE"
  echo "  Results:      $UCC_RESULT_FILE"
  echo "========================================================"
  echo ""
}
