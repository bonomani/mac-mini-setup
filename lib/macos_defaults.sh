#!/usr/bin/env bash
# lib/macos_defaults.sh — helper for YAML-driven macOS defaults targets
# Sourced by components/09-macos-defaults.sh

_macos_defaults_state() {
  local current="$1" desired="$2"
  local dep_state="DepsReady"
  [[ "${UIC_GATE_FAILED_SUDO_AVAILABLE:-0}" == "1" ]] && dep_state="DepsDegraded"
  if [[ "$current" == "$desired" ]]; then
    ucc_asm_state --installation Configured --runtime Stopped --health Healthy \
      --admin Enabled --dependencies "$dep_state" --config-value "$current"
  else
    ucc_asm_state --installation Installed --runtime Stopped --health Degraded \
      --admin Enabled --dependencies "$dep_state" --config-value "$current"
  fi
}

_macos_defaults_desired_state() {
  local desired="$1"
  local dep_state="DepsReady"
  [[ "${UIC_GATE_FAILED_SUDO_AVAILABLE:-0}" == "1" ]] && dep_state="DepsDegraded"
  ucc_asm_state \
    --installation Configured \
    --runtime Stopped \
    --health Healthy \
    --admin Enabled \
    --dependencies "$dep_state" \
    --config-value "$desired"
}

_macos_defaults_observe() {
  local read_cmd="$1" desired="$2" current=""
  current=$(eval "$read_cmd" 2>/dev/null | head -1 | tr -d '[:space:]')
  _macos_defaults_state "$current" "$desired"
}

_macos_defaults_evidence() {
  local read_cmd="$1"
  printf 'value=%s' "$(eval "$read_cmd" | head -1)"
}

_macos_defaults_apply() {
  local apply_cmd="$1"
  eval "$apply_cmd"
}

_macos_defaults_target() {
  local name="$1" read_cmd="$2" desired="$3" apply_cmd="$4"
  local fn; fn="$(printf '%s' "$name" | tr -cs '[:alnum:]' '_')"
  local observe_fn="_obs_${fn}"
  local evidence_fn="_evidence_${fn}"
  local apply_fn="_apply_${fn}"

  # Store commands in globals to avoid single-quote quoting conflicts in eval
  # (read_cmd contains awk patterns with single quotes)
  eval "_MDRD_${fn}=\$read_cmd"
  eval "_MDAP_${fn}=\$apply_cmd"

  eval "${observe_fn}()  { _macos_defaults_observe  \"\${_MDRD_${fn}}\" '${desired}'; }"
  eval "${evidence_fn}() { _macos_defaults_evidence \"\${_MDRD_${fn}}\"; }"
  eval "${apply_fn}()    { _macos_defaults_apply    \"\${_MDAP_${fn}}\"; }"

  ucc_target_nonruntime \
    --name "$name" \
    --observe "$observe_fn" \
    --evidence "$evidence_fn" \
    --desired "$(_macos_defaults_desired_state "$desired")" \
    --install "$apply_fn" \
    --update "$apply_fn"
}
