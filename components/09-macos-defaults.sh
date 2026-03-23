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
  local install_state="Configured"
  [[ "${UIC_GATE_FAILED_SUDO_AVAILABLE:-0}" == "1" ]] && dep_state="DepsDegraded"
  [[ "$current" == "$desired" ]] \
    && ucc_asm_state --installation "$install_state" --runtime Stopped --health Healthy --admin Enabled --dependencies "$dep_state" \
    || ucc_asm_state --installation Installed --runtime Stopped --health Degraded --admin Enabled --dependencies "$dep_state"
}

_macos_defaults_desired_state() {
  local dep_state="DepsReady"
  [[ "${UIC_GATE_FAILED_SUDO_AVAILABLE:-0}" == "1" ]] && dep_state="DepsDegraded"
  ucc_asm_state \
    --installation Configured \
    --runtime Stopped \
    --health Healthy \
    --admin Enabled \
    --dependencies "$dep_state"
}

_macos_defaults_observe() {
  local read_cmd="$1" desired="$2" current=""
  current=$(eval "$read_cmd")
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
    --desired "$(_macos_defaults_desired_state)" \
    --install "$apply_fn" \
    --update "$apply_fn"
}

# Power management defaults for long AI runs.
_macos_defaults_target \
  "pmset-ac-sleep=0" \
  "pmset -g | awk '/^[[:space:]]+sleep / {print \$2}'" \
  "0" \
  "ucc_run sudo pmset -c sleep 0"

_macos_defaults_target \
  "pmset-disksleep=0" \
  "pmset -g | awk '/disksleep/ {print \$2}'" \
  "0" \
  "ucc_run sudo pmset -c disksleep 0"

_macos_defaults_target \
  "pmset-standby=0" \
  "pmset -g | awk '/^[[:space:]]+standby / {print \$2}'" \
  "0" \
  "ucc_run sudo pmset -c standby 0"

# Note: com.apple.universalaccess reduce transparency is write-protected on macOS 14+ from scripts.
# Set manually in System Settings if needed.
_macos_defaults_target \
  "app-nap=disabled" \
  "defaults read NSGlobalDomain NSAppSleepDisabled 2>/dev/null || echo 0" \
  "1" \
  "ucc_run defaults write NSGlobalDomain NSAppSleepDisabled -bool YES"

_macos_defaults_target \
  "finder-show-hidden=1" \
  "defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || echo 0" \
  "1" \
  "ucc_run defaults write com.apple.finder AppleShowAllFiles -bool true"

_macos_defaults_target \
  "show-all-extensions=1" \
  "defaults read NSGlobalDomain AppleShowAllExtensions 2>/dev/null || echo 0" \
  "1" \
  "ucc_run defaults write NSGlobalDomain AppleShowAllExtensions -bool true"

_macos_defaults_target \
  "dock-autohide=1" \
  "defaults read com.apple.dock autohide 2>/dev/null || echo 0" \
  "1" \
  "ucc_run defaults write com.apple.dock autohide -bool true"

if [[ "$UCC_DRY_RUN" != "1" && $_UCC_CHANGED -gt 0 ]]; then
  killall Finder Dock SystemUIServer 2>/dev/null || true
  log_info "Finder/Dock/SystemUIServer restarted"
fi

ucc_summary "09-macos-defaults"
