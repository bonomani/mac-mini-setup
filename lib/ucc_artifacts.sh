#!/usr/bin/env bash
# lib/ucc_artifacts.sh — JSONL artifact recording and dry-run gate
# Sourced by lib/ucc.sh

_ucc_meta_in() {
  local id="$1" ts="$2"
  printf '"meta":{"contract":"ucc","version":"2.0","id":"%s","timestamp":"%s","scope":"operation"}' \
    "$(_ucc_jstr "$id")" "$(_ucc_jstr "$ts")"
}

_ucc_meta_out() {
  local id="$1" duration_ms="$2" ts
  ts=$(_ucc_now_utc)
  printf '"meta":{"contract":"ucc","version":"2.0","id":"%s","timestamp":"%s","duration_ms":%s,"scope":"operation"}' \
    "$(_ucc_jstr "$id")" "$(_ucc_jstr "$ts")" "${duration_ms:-0}"
}

_ucc_record_file() {
  local path="$1" payload="$2"
  [[ -z "$path" ]] && return 0
  printf '%s\n' "$payload" >> "$path" 2>/dev/null || true
}

_ucc_record_declaration() {
  local id="$1" name="$2" desired="$3" mode="$4" ts="$5"
  local payload
  payload="{$(_ucc_meta_in "$id" "$ts"),\"declaration\":{\"mode\":\"$(_ucc_jstr "$mode")\",\"target\":\"$(_ucc_jstr "$name")\",\"desired_state\":$(_ucc_state_obj "$desired")}}"
  _ucc_record_file "${UCC_DECLARATION_FILE:-}" "$payload"
}

_ucc_record_result() {
  local id="$1" duration_ms="$2" observe_json="$3" result_json="$4"
  local payload
  payload="{$(_ucc_meta_out "$id" "$duration_ms"),\"observe\":${observe_json},\"result\":${result_json}}"
  _ucc_record_file "${UCC_RESULT_FILE:-}" "$payload"
}

_ucc_record_profile_summary() {
  local profile="$1" outcome="$2"
  [[ -z "${UCC_PROFILE_SUMMARY_FILE:-}" ]] && return 0
  printf '%s|%s\n' "${profile:-configured}" "$outcome" >> "$UCC_PROFILE_SUMMARY_FILE" 2>/dev/null || true
}

_ucc_record_target_status() {
  local target="$1" status="$2"
  [[ -z "${UCC_TARGET_STATUS_FILE:-}" ]] && return 0
  printf '%s|%s\n' "$target" "$status" >> "$UCC_TARGET_STATUS_FILE" 2>/dev/null || true
}

_ucc_duration_ms() {
  local started_at="$1" now
  now=$(date +%s 2>/dev/null || echo 0)
  echo $(( (now - started_at) * 1000 ))
}

# Dry-run gate: skip any side-effecting command when UCC_DRY_RUN=1
ucc_run() {
  if [[ "$UCC_DRY_RUN" == "1" ]]; then
    log_debug "DRY-RUN would execute: $*"
    return 0
  fi
  "$@"
}
