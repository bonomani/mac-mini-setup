#!/usr/bin/env bash
# lib/ucc_display.sh — Execution plan display and component name formatting
# Sourced by install.sh. Operates on globals:
#   _DISP_COMPS[], _DISP_CONFIGS[] — dispatch arrays
#   UCC_TARGET_SET, UIC_PREF_SKIP_DISPLAY_MODE

_display_component_name() {
  case "$1" in
    system) printf 'macOS system' ;;
    linux-system) printf 'Linux system' ;;
    verify) printf 'Verification' ;;
    *)      printf '%s' "$1" ;;
  esac
}

_comp_in_list() {
  local needle="$1"; shift
  local item
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

_collect_layer_components() {
  local filter="$1"
  local comps=() _cfg _comp
  for _i in "${!_DISP_COMPS[@]}"; do
    _cfg="${_DISP_CONFIGS[$_i]}"
    case "$filter" in
      software) [[ "$_cfg" == */system/* || "$_cfg" == "tic" ]] && continue ;;
      system)   [[ "$_cfg" != */system/* ]] && continue ;;
      tic)      [[ "$_cfg" != "tic" ]] && continue ;;
    esac
    _comp="${_DISP_COMPS[$_i]}"
    if [[ "${UIC_PREF_SKIP_DISPLAY_MODE:-full}" == "fast" ]] \
      && [[ -n "${UCC_TARGET_SET:-}" ]] \
      && [[ "$_cfg" != "tic" ]] \
      && ! _component_has_selected_targets "$_comp"; then
      continue
    fi
    comps+=("$_comp")
  done
  [[ ${#comps[@]} -gt 0 ]] && printf '%s\n' "${comps[@]}"
}

print_execution_plan() {
  local software=() system=() tic=() item
  while IFS= read -r item; do [[ -n "$item" ]] && software+=("$(_display_component_name "$item")"); done < <(_collect_layer_components software)
  while IFS= read -r item; do [[ -n "$item" ]] && system+=("$(_display_component_name "$item")"); done < <(_collect_layer_components system)
  while IFS= read -r item; do [[ -n "$item" ]] && tic+=("$(_display_component_name "$item")"); done < <(_collect_layer_components tic)

  echo ""
  echo "  Execution Plan"
  echo "  ──────────────────────────────────────────────────────"
  [[ ${#software[@]} -gt 0 ]] && printf '  %-14s %s\n' "Software" "$(IFS=', '; echo "${software[*]}")"
  [[ ${#system[@]} -gt 0 ]]   && printf '  %-14s %s\n' "System"   "$(IFS=', '; echo "${system[*]}")"
  [[ ${#tic[@]} -gt 0 ]]      && printf '  %-14s %s\n' "Verify"   "$(IFS=', '; echo "${tic[*]}")"
  return 0
}
