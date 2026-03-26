#!/usr/bin/env bash
# lib/summary.sh — Final summary rendering for install.sh

# ── Profile counters ──────────────────────────────────────────────────────────

init_summary_counters() {
  _total_ok=0; _total_chg=0; _total_fail=0; _total_skip=0
  _profile_presence_ok=0;   _profile_presence_chg=0;   _profile_presence_fail=0
  _profile_configured_ok=0; _profile_configured_chg=0; _profile_configured_fail=0
  _profile_runtime_ok=0;    _profile_runtime_chg=0;    _profile_runtime_fail=0
  _profile_parametric_ok=0; _profile_parametric_chg=0; _profile_parametric_fail=0
}

_summary_line() {
  local ok="${1:-0}" changed="${2:-0}" failed="${3:-0}" line=""
  line="${ok} ok"
  [[ "$changed" -gt 0 ]] && line="${line}  ${changed} changed"
  [[ "$failed"  -gt 0 ]] && line="${line}  ${failed} FAILED"
  printf '%s' "$line"
}

_profile_var_prefix() {
  case "$1" in
    presence)   printf '_profile_presence'   ;;
    configured) printf '_profile_configured' ;;
    runtime)    printf '_profile_runtime'    ;;
    parametric) printf '_profile_parametric' ;;
    *)          printf ''                    ;;
  esac
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

print_profile_contracts() {
  local profile expected
  for profile in presence configured runtime parametric; do
    expected="$(ucc_profile_expected_text "$profile")"
    [[ -n "$expected" ]] || continue
    printf '  Profile %-10s | baseline: %s\n' "$(ucc_profile_label "$profile")" "$expected"
  done
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
      printf '  %-22s  %s\n' "$_comp" "$_tic_parts"
    else
      _total_ok=$(( _total_ok + _a ))
      _total_chg=$(( _total_chg + _b ))
      _total_fail=$(( _total_fail + _c ))
      _total_skip=$(( _total_skip + ${_d:-0} ))
      local _parts=""
      [[ $_a -gt 0 ]]      && _parts="${_a} ok"
      [[ $_b -gt 0 ]]      && _parts="${_parts:+$_parts  }${_b} changed"
      [[ $_c -gt 0 ]]      && _parts="${_parts:+$_parts  }${_c} FAILED"
      [[ ${_d:-0} -gt 0 ]] && _parts="${_parts:+$_parts  }skip=${_d}"
      printf '  %-22s  %s\n' "$_comp" "${_parts:----}"
    fi
  done < "$UCC_SUMMARY_FILE"
}

print_services_summary() {
  local services_file="$1"
  local name="" url="" note="" line=""
  [[ -f "$services_file" ]] || return 0
  echo "  ──────────────────────────────────────────────────────"
  echo "  Services"
  while IFS= read -r _line; do
    case "$_line" in
      "  - name: "*)
        if [[ -n "$name" ]]; then
          line="    $(printf '%-16s' "$name") → ${url}"
          [[ -n "$note" ]] && line="${line}   (${note})"
          echo "$line"
        fi
        name="${_line#  - name: }"; url=""; note="" ;;
      "    name: "*)  name="${_line#    name: }" ;;
      "    url: "*)   url="${_line#    url: }" ;;
      "    note: "*)  note="${_line#    note: }" ;;
    esac
  done < "$services_file"
  if [[ -n "$name" ]]; then
    line="    $(printf '%-16s' "$name") → ${url}"
    [[ -n "$note" ]] && line="${line}   (${note})"
    echo "$line"
  fi
}

print_final_summary() {
  local dir="$1" mode="$2" dry_run="$3"
  local software_comps=(); local system_comps=(); local tic_comps=()
  # Callers pass arrays by name; read from globals set during run passes
  software_comps=("${_SOFTWARE_COMPS[@]}")
  system_comps=("${_SYSTEM_COMPS[@]}")
  tic_comps=("${_TIC_COMPS[@]}")

  echo ""
  echo "========================================================"
  local _hdr="Summary | mode=${mode}"
  [[ "$dry_run" == "1" ]] && _hdr="${_hdr} | dry_run=1"
  echo "  ${_hdr}"
  echo "  ──────────────────────────────────────────────────────"

  init_summary_counters
  print_summary_section "Convergence / software" "${software_comps[@]}"
  print_summary_section "Convergence / system"   "${system_comps[@]}"
  print_summary_section "Verification"           "${tic_comps[@]}"

  echo "  ──────────────────────────────────────────────────────"
  local _total_line
  _total_line="$(_summary_line "$_total_ok" "$_total_chg" "$_total_fail")"
  [[ $_total_skip -gt 0 ]] && _total_line="${_total_line}  skip=${_total_skip}"
  printf '  %-22s  %s\n' "Total" "$_total_line"

  if [[ -f "$UCC_PROFILE_SUMMARY_FILE" ]]; then
    while IFS='|' read -r _profile _outcome; do
      profile_bump "$_profile" "$_outcome"
    done < "$UCC_PROFILE_SUMMARY_FILE"
    echo "  ──────────────────────────────────────────────────────"
    echo "  By Profile"
    printf '  %-22s  %s\n' "$(ucc_profile_label presence)"   "$(_summary_line "$_profile_presence_ok"   "$_profile_presence_chg"   "$_profile_presence_fail")"
    printf '  %-22s  %s\n' "$(ucc_profile_label configured)" "$(_summary_line "$_profile_configured_ok" "$_profile_configured_chg" "$_profile_configured_fail")"
    printf '  %-22s  %s\n' "$(ucc_profile_label runtime)"    "$(_summary_line "$_profile_runtime_ok"    "$_profile_runtime_chg"    "$_profile_runtime_fail")"
    printf '  %-22s  %s\n' "$(ucc_profile_label parametric)" "$(_summary_line "$_profile_parametric_ok" "$_profile_parametric_chg" "$_profile_parametric_fail")"
  fi

  [[ ${#FAILED_COMPONENTS[@]} -gt 0 ]] && { echo ""; log_warn "Failed components: ${FAILED_COMPONENTS[*]}"; }

  print_services_summary "$dir/services.yaml"
  echo "  ──────────────────────────────────────────────────────"
  echo "  Declarations: $UCC_DECLARATION_FILE"
  echo "  Results:      $UCC_RESULT_FILE"
  echo "========================================================"
  echo ""
}
