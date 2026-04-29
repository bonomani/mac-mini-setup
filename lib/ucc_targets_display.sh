#!/usr/bin/env bash
# lib/ucc_targets_display.sh — display-name + per-target line rendering.
#
# Extracted from lib/ucc_targets.sh on 2026-04-29 (PLAN refactor #2, slice 5).

_UCC_DISPLAY_NAME_CACHE_KEYS=()
_UCC_DISPLAY_NAME_CACHE_VALUES=()
_UCC_DISPLAY_NAME_CACHE_LOADED=0

_ucc_display_name_load_cache() {
  [[ $_UCC_DISPLAY_NAME_CACHE_LOADED -eq 1 ]] && return
  _UCC_DISPLAY_NAME_CACHE_LOADED=1
  [[ -z "${_UCC_ALL_DISPLAY_NAMES_CACHE:-}" ]] && return
  while IFS=$'\t' read -r key value; do
    [[ -n "$key" ]] || continue
    # Append target name when display name differs
    if [[ -n "$value" && "$value" != "$key" ]]; then
      value="${value} (${key})"
    fi
    _UCC_DISPLAY_NAME_CACHE_KEYS+=("$key")
    _UCC_DISPLAY_NAME_CACHE_VALUES+=("$value")
  done <<< "$_UCC_ALL_DISPLAY_NAMES_CACHE"
}

_ucc_display_name() {
  local target="$1" idx display_name="$1"
  _ucc_display_name_load_cache
  for idx in "${!_UCC_DISPLAY_NAME_CACHE_KEYS[@]}"; do
    if [[ "${_UCC_DISPLAY_NAME_CACHE_KEYS[$idx]}" == "$target" ]]; then
      printf '%s' "${_UCC_DISPLAY_NAME_CACHE_VALUES[$idx]}"
      return
    fi
  done

  if [[ -n "${UCC_TARGETS_MANIFEST:-}" && -n "${UCC_TARGETS_QUERY_SCRIPT:-}" ]]; then
    if [[ -e "${UCC_TARGETS_MANIFEST}" && -f "${UCC_TARGETS_QUERY_SCRIPT}" ]]; then
      display_name="$("${UCC_FRAMEWORK_PYTHON:-python3}" "$UCC_TARGETS_QUERY_SCRIPT" --display-name "$target" "$UCC_TARGETS_MANIFEST" 2>/dev/null || true)"
      [[ -n "$display_name" ]] || display_name="$target"
    fi
  fi

  # Show target name in parentheses when display name differs
  if [[ "$display_name" != "$target" ]]; then
    display_name="${display_name} (${target})"
  fi
  _UCC_DISPLAY_NAME_CACHE_KEYS+=("$target")
  _UCC_DISPLAY_NAME_CACHE_VALUES+=("$display_name")
  printf '%s' "$display_name"
}

_ucc_emit_target_line() {
  local profile="$1" status="$2" name="$3" detail="${4:-}" line=""
  if [[ -n "$detail" ]]; then
    line=$(printf '      [%-8s] %-40s %s' "$status" "$name" "$detail")
  else
    line=$(printf '      [%-8s] %s' "$status" "$name")
  fi
  _ucc_emit_profile_line "$profile" "$line"
}

_ucc_policy_detail() {
  local name="$1" observed="$2" desired="$3" axes="$4" evidence_fn="$5" reason="$6"
  local evidence=""
  evidence="$(_ucc_compose_evidence "$name" "$observed" "$axes" "$evidence_fn")"
  if [[ -n "$evidence" ]]; then
    printf '%s (%s)' "$evidence" "$reason"
    return 0
  fi
  printf '"%s" -> "%s" (%s)' \
    "$(_ucc_display_state "$observed" "$axes")" \
    "$(_ucc_display_state "$desired" "$axes")" \
    "$reason"
}

_ucc_policy_warn_detail() {
  local name="$1" observed="$2" axes="$3" evidence_fn="$4" reason="$5"
  local evidence=""
  evidence="$(_ucc_compose_evidence "$name" "$observed" "$axes" "$evidence_fn")"
  if [[ -n "$evidence" ]]; then
    printf '%s  %s' "$reason" "$evidence"
    return 0
  fi
  printf '%s' "$reason"
}
