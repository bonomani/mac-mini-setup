#!/usr/bin/env bash
# Component: macOS system defaults (optimized for AI workloads)
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — pmset + defaults write settings)
#       Axis B = Basic
# Boundary: macOS system preferences API · pmset (requires sudo)

_macos_defaults_state() {
  local current="$1" desired="$2"
  local dep_state="DepsReady"
  [[ "${UIC_GATE_FAILED_SUDO_AVAILABLE:-0}" == "1" ]] && dep_state="DepsDegraded"
  # Parametric state (ASM SOFTWARE-MODEL.md §3b): carry config_value so
  # convergence comparison distinguishes distinct values (e.g. "0" vs "1").
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

# Load defaults and restart_processes from config — see config/09-macos-defaults.yaml
# Note: com.apple.universalaccess reduce transparency is write-protected on macOS 14+ from scripts.
# Set manually in System Settings if needed.
_MD_CFG_DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
_MD_CFG="$_MD_CFG_DIR/config/09-macos-defaults.yaml"

while IFS=$'\t' read -r md_name md_desired md_read md_apply; do
  [[ -n "$md_name" ]] || continue
  _macos_defaults_target "$md_name" "$md_read" "$md_desired" "$md_apply"
done < <(python3 "$_MD_CFG_DIR/tools/read_config.py" --records \
    "$_MD_CFG" defaults name desired read apply 2>/dev/null)

if [[ "$UCC_DRY_RUN" != "1" && $_UCC_CHANGED -gt 0 ]]; then
  while IFS= read -r _proc; do
    [[ -n "$_proc" ]] && { killall "$_proc" 2>/dev/null || true; }
  done < <(python3 "$_MD_CFG_DIR/tools/read_config.py" --list "$_MD_CFG" restart_processes 2>/dev/null)
  log_info "Finder/Dock/SystemUIServer restarted"
fi

ucc_summary "09-macos-defaults"
