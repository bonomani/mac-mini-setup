#!/usr/bin/env bash
# Component: macOS system defaults (optimized for AI workloads)
# UCC + Basic

# Each setting is a UCC target: observe current value → apply if different

# --- Power management (no sleep for long AI runs) -----------

_observe_ac_sleep() {
  pmset -g | awk '/^[[:space:]]+sleep / {print $2}'
}
_set_ac_sleep_0() { ucc_run sudo pmset -c sleep 0; }

ucc_target \
  --name    "pmset-ac-sleep=0" \
  --observe _observe_ac_sleep \
  --desired "0" \
  --install _set_ac_sleep_0 \
  --update  _set_ac_sleep_0

_observe_disksleep() {
  pmset -g | awk '/disksleep/ {print $2}'
}
_set_disksleep_0() { ucc_run sudo pmset -c disksleep 0; }

ucc_target \
  --name    "pmset-disksleep=0" \
  --observe _observe_disksleep \
  --desired "0" \
  --install _set_disksleep_0 \
  --update  _set_disksleep_0

_observe_standby() {
  pmset -g | awk '/^[[:space:]]+standby / {print $2}'
}
_set_standby_0() { ucc_run sudo pmset -c standby 0; }

ucc_target \
  --name    "pmset-standby=0" \
  --observe _observe_standby \
  --desired "0" \
  --install _set_standby_0 \
  --update  _set_standby_0

# --- Disable App Nap ----------------------------------------
_observe_app_nap() {
  defaults read NSGlobalDomain NSAppSleepDisabled 2>/dev/null || echo "0"
}
_disable_app_nap() { ucc_run defaults write NSGlobalDomain NSAppSleepDisabled -bool YES; }

ucc_target \
  --name    "app-nap=disabled" \
  --observe _observe_app_nap \
  --desired "1" \
  --install _disable_app_nap \
  --update  _disable_app_nap

# --- Reduce transparency (performance) ----------------------
_observe_transparency() {
  defaults read com.apple.universalaccess reduceTransparency 2>/dev/null || echo "0"
}
_reduce_transparency() { ucc_run defaults write com.apple.universalaccess reduceTransparency -bool true; }

ucc_target \
  --name    "reduce-transparency=1" \
  --observe _observe_transparency \
  --desired "1" \
  --install _reduce_transparency \
  --update  _reduce_transparency

# --- Show hidden files in Finder ----------------------------
_observe_hidden_files() {
  defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || echo "0"
}
_show_hidden_files() { ucc_run defaults write com.apple.finder AppleShowAllFiles -bool true; }

ucc_target \
  --name    "finder-show-hidden=1" \
  --observe _observe_hidden_files \
  --desired "1" \
  --install _show_hidden_files \
  --update  _show_hidden_files

# --- Show all file extensions -------------------------------
_observe_extensions() {
  defaults read NSGlobalDomain AppleShowAllExtensions 2>/dev/null || echo "0"
}
_show_extensions() { ucc_run defaults write NSGlobalDomain AppleShowAllExtensions -bool true; }

ucc_target \
  --name    "show-all-extensions=1" \
  --observe _observe_extensions \
  --desired "1" \
  --install _show_extensions \
  --update  _show_extensions

# --- Dock auto-hide -----------------------------------------
_observe_dock_autohide() {
  defaults read com.apple.dock autohide 2>/dev/null || echo "0"
}
_dock_autohide() { ucc_run defaults write com.apple.dock autohide -bool true; }

ucc_target \
  --name    "dock-autohide=1" \
  --observe _observe_dock_autohide \
  --desired "1" \
  --install _dock_autohide \
  --update  _dock_autohide

# Restart affected services (only if something changed and not dry-run)
if [[ "$UCC_DRY_RUN" != "1" && $_UCC_CHANGED -gt 0 ]]; then
  killall Finder Dock SystemUIServer 2>/dev/null || true
  log_info "Finder/Dock/SystemUIServer restarted"
fi

ucc_summary "09-macos-defaults"
