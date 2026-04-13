#!/usr/bin/env bash
# lib/drivers/swupdate_schedule.sh — driver.kind: softwareupdate-schedule
# Manages the macOS automatic software update schedule (on/off).

_swupdate_schedule_state() {
  if softwareupdate --schedule 2>/dev/null | grep -qiE 'is (on|turned on)\.?$'; then
    printf 'on'
  else
    printf 'off'
  fi
}

_ucc_driver_softwareupdate_schedule_observe() {
  _swupdate_schedule_state
}

_ucc_driver_softwareupdate_schedule_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  sudo_is_available || { log_warn "softwareupdate-schedule requires sudo"; return 1; }
  ucc_run run_elevated softwareupdate --schedule on
}

_ucc_driver_softwareupdate_schedule_evidence() {
  printf 'schedule=%s' "$(_swupdate_schedule_state)"
}
