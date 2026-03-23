#!/usr/bin/env bash
# Component: macOS system defaults (optimized for AI workloads)
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — pmset + defaults write settings)
#       Axis B = Basic
# Boundary: macOS system preferences API · pmset (requires sudo)

# Each setting is a UCC target: observe current value → apply if different

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

# --- Power management (no sleep for long AI runs) -----------

_observe_ac_sleep() {
  local current
  current=$(pmset -g | awk '/^[[:space:]]+sleep / {print $2}')
  _macos_defaults_state "$current" "0"
}
_set_ac_sleep_0() { ucc_run sudo pmset -c sleep 0; }

ucc_target \
  --name    "pmset-ac-sleep=0" \
  --observe _observe_ac_sleep \
  --desired "$(_macos_defaults_desired_state)" \
  --install _set_ac_sleep_0 \
  --update  _set_ac_sleep_0

_observe_disksleep() {
  local current
  current=$(pmset -g | awk '/disksleep/ {print $2}')
  _macos_defaults_state "$current" "0"
}
_set_disksleep_0() { ucc_run sudo pmset -c disksleep 0; }

ucc_target \
  --name    "pmset-disksleep=0" \
  --observe _observe_disksleep \
  --desired "$(_macos_defaults_desired_state)" \
  --install _set_disksleep_0 \
  --update  _set_disksleep_0

_observe_standby() {
  local current
  current=$(pmset -g | awk '/^[[:space:]]+standby / {print $2}')
  _macos_defaults_state "$current" "0"
}
_set_standby_0() { ucc_run sudo pmset -c standby 0; }

ucc_target \
  --name    "pmset-standby=0" \
  --observe _observe_standby \
  --desired "$(_macos_defaults_desired_state)" \
  --install _set_standby_0 \
  --update  _set_standby_0

# --- Disable App Nap ----------------------------------------
_observe_app_nap() {
  local current
  current=$(defaults read NSGlobalDomain NSAppSleepDisabled 2>/dev/null || echo "0")
  _macos_defaults_state "$current" "1"
}
_disable_app_nap() { ucc_run defaults write NSGlobalDomain NSAppSleepDisabled -bool YES; }

ucc_target \
  --name    "app-nap=disabled" \
  --observe _observe_app_nap \
  --desired "$(_macos_defaults_desired_state)" \
  --install _disable_app_nap \
  --update  _disable_app_nap

# --- Reduce transparency (performance) ----------------------
# Note: com.apple.universalaccess is write-protected on macOS 14+ from scripts.
# Set manually: System Settings → Accessibility → Display → Reduce Transparency

# --- Show hidden files in Finder ----------------------------
_observe_hidden_files() {
  local current
  current=$(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || echo "0")
  _macos_defaults_state "$current" "1"
}
_show_hidden_files() { ucc_run defaults write com.apple.finder AppleShowAllFiles -bool true; }

ucc_target \
  --name    "finder-show-hidden=1" \
  --observe _observe_hidden_files \
  --desired "$(_macos_defaults_desired_state)" \
  --install _show_hidden_files \
  --update  _show_hidden_files

# --- Show all file extensions -------------------------------
_observe_extensions() {
  local current
  current=$(defaults read NSGlobalDomain AppleShowAllExtensions 2>/dev/null || echo "0")
  _macos_defaults_state "$current" "1"
}
_show_extensions() { ucc_run defaults write NSGlobalDomain AppleShowAllExtensions -bool true; }

ucc_target \
  --name    "show-all-extensions=1" \
  --observe _observe_extensions \
  --desired "$(_macos_defaults_desired_state)" \
  --install _show_extensions \
  --update  _show_extensions

# --- Dock auto-hide -----------------------------------------
_observe_dock_autohide() {
  local current
  current=$(defaults read com.apple.dock autohide 2>/dev/null || echo "0")
  _macos_defaults_state "$current" "1"
}
_dock_autohide() { ucc_run defaults write com.apple.dock autohide -bool true; }

ucc_target \
  --name    "dock-autohide=1" \
  --observe _observe_dock_autohide \
  --desired "$(_macos_defaults_desired_state)" \
  --install _dock_autohide \
  --update  _dock_autohide

# Restart affected services (only if something changed and not dry-run)
if [[ "$UCC_DRY_RUN" != "1" && $_UCC_CHANGED -gt 0 ]]; then
  killall Finder Dock SystemUIServer 2>/dev/null || true
  log_info "Finder/Dock/SystemUIServer restarted"
fi

ucc_summary "09-macos-defaults"
