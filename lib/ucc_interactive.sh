#!/usr/bin/env bash
# lib/ucc_interactive.sh — Interactive component/target browser
# Sourced by install.sh when UCC_INTERACTIVE=1. Operates on globals:
#   COMPONENTS[], _resolved[], UCC_TARGET_SET, UCC_DISABLED_TARGETS
#   _QUERY_SCRIPT, _MANIFEST_DIR

# Pre-load component target lists (parallel arrays, skip verify)
_BROWSE_COMPS=()
_COMP_TARGETS_DATA=()

_interactive_load_components() {
  for _c in "${COMPONENTS[@]}"; do
    [[ "$_c" == "verify" ]] && continue
    _BROWSE_COMPS+=("$_c")
    _COMP_TARGETS_DATA+=("$(python3 "$_QUERY_SCRIPT" --ordered-targets "$_c" "$_MANIFEST_DIR" 2>/dev/null)")
  done
}

_get_comp_targets() {
  local _idx=0
  for _cc in ${_BROWSE_COMPS[@]+"${_BROWSE_COMPS[@]}"}; do
    [[ "$_cc" == "$1" ]] && { echo "${_COMP_TARGETS_DATA[$_idx]}"; return; }
    _idx=$((_idx + 1))
  done
}

_show_menu() {
  local _idx=1 _tcount _selected _t
  echo ""
  echo "    a) All"
  for _c in ${_BROWSE_COMPS[@]+"${_BROWSE_COMPS[@]}"}; do
    _tcount=0; _disabled_count=0; _selected=0
    while IFS= read -r _t; do
      [[ -z "$_t" ]] && continue
      _tcount=$((_tcount + 1))
      if [[ -n "${UCC_DISABLED_TARGETS}" && "${UCC_DISABLED_TARGETS}" == *"${_t}|"* ]]; then
        _disabled_count=$((_disabled_count + 1))
      elif [[ "${UCC_TARGET_SET}" == *"${_t}|"* ]]; then
        _selected=$((_selected + 1))
      fi
    done <<< "${_COMP_TARGETS_DATA[$((_idx - 1))]}"
    _avail=$((_tcount - _disabled_count))
    if [[ $_selected -gt 0 ]]; then
      printf '    %d) %-20s (%d/%d selected)\n' "$_idx" "$_c" "$_selected" "$_avail"
    elif [[ $_disabled_count -gt 0 && $_avail -eq 0 ]]; then
      printf '    %d) %-20s (all disabled)\n' "$_idx" "$_c"
    elif [[ $_disabled_count -gt 0 ]]; then
      printf '    %d) %-20s (%d targets, %d disabled)\n' "$_idx" "$_c" "$_avail" "$_disabled_count"
    else
      printf '    %d) %-20s (%d targets)\n' "$_idx" "$_c" "$_tcount"
    fi
    _idx=$((_idx + 1))
  done
  echo ""
  echo "  Enter: number to browse, a=all, or target name to select"
}

_interactive_browse() {
  echo ""
  echo "  ── Selection ─────────────────────────────────────────"
  echo "  What would you like to install?"
  echo ""
  _interactive_load_components
  _show_menu
  while true; do
    printf '  → '
    read -r _input < /dev/tty
    [[ -z "$_input" ]] && break

    if [[ "$_input" == "a" || "$_input" == "all" ]]; then
      _resolved=()
      UCC_TARGET_SET=""
      for _c in "${COMPONENTS[@]}"; do _resolve_component "$_c"; done
      echo "  Selected: all components"
      break
    elif [[ "$_input" == "q" || "$_input" == "done" ]]; then
      break
    elif [[ "$_input" =~ ^[0-9]+$ && "$_input" -ge 1 && "$_input" -le "${#_BROWSE_COMPS[@]}" ]]; then
      _sel_comp="${_BROWSE_COMPS[$((_input - 1))]}"
      echo ""
      echo "  ── ${_sel_comp} ──"
      _tidx=1
      while IFS= read -r _t; do
        if [[ -n "$_t" ]]; then
          if [[ -n "${UCC_DISABLED_TARGETS}" && "${UCC_DISABLED_TARGETS}" == *"${_t}|"* ]]; then
            printf '      %d) %-30s [disabled]\n' "$_tidx" "$_t"
          elif [[ "${UCC_TARGET_SET}" == *"${_t}|"* ]]; then
            printf '      %d) %-30s [selected]\n' "$_tidx" "$_t"
          else
            printf '      %d) %s\n' "$_tidx" "$_t"
          fi
        fi
        _tidx=$((_tidx + 1))
      done <<< "$(_get_comp_targets "$_sel_comp")"
      echo ""
      printf '  Select: a=all %s, numbers comma-separated, b=back → ' "$_sel_comp"
      read -r _sub_input < /dev/tty

      if [[ "$_sub_input" == "b" || -z "$_sub_input" ]]; then
        _show_menu
        continue
      elif [[ "$_sub_input" == "a" ]]; then
        _resolve_component "$_sel_comp"
        echo "  Added: all ${_sel_comp}"
      else
        IFS=',' read -ra _sub_picks <<< "$_sub_input"
        _targets_arr=()
        while IFS= read -r _t; do
          [[ -n "$_t" ]] && _targets_arr+=("$_t")
        done <<< "$(_get_comp_targets "$_sel_comp")"
        for _sp in ${_sub_picks[@]+"${_sub_picks[@]}"}; do
          _sp="${_sp// /}"
          if [[ "$_sp" =~ ^[0-9]+$ && "$_sp" -ge 1 && "$_sp" -le "${#_targets_arr[@]}" ]]; then
            _pick="${_targets_arr[$((_sp - 1))]}"
            if [[ -n "${UCC_DISABLED_TARGETS}" && "${UCC_DISABLED_TARGETS}" == *"${_pick}|"* ]]; then
              echo "  Skipped: ${_pick} (disabled by policy)"
            else
              _resolve_target "$_pick"
              echo "  Added: ${_pick}"
            fi
          fi
        done
      fi
      _show_menu
    else
      if python3 "$_QUERY_SCRIPT" --find-target "$_input" "$_MANIFEST_DIR" >/dev/null 2>&1; then
        _resolve_target "$_input"
        echo "  Added: $_input"
      else
        echo "  Unknown: '$_input'"
      fi
    fi
  done
  for _c in "${COMPONENTS[@]}"; do _resolved+=("$_c"); done
  export UCC_TARGET_SET
}
