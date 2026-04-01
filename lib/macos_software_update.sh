#!/usr/bin/env bash
# lib/macos_software_update.sh — helpers for YAML-driven macOS software update policy

# Observe softwareupdate schedule state: on | off
softwareupdate_schedule_observe() {
  if softwareupdate --schedule 2>/dev/null | grep -qiE 'Automatic check is on\.?$'; then
    echo on
  else
    echo off
  fi
}

# Return 0 if the softwareupdate schedule is set to 'on'.
softwareupdate_schedule_is_on() {
  softwareupdate_schedule_observe | grep -q '^on$'
}

# Read a softwareupdate defaults key, printing 0 if absent.
# Usage: softwareupdate_pref_read <domain> <key>
softwareupdate_pref_read() {
  defaults read "$1" "$2" 2>/dev/null || echo 0
}

# Enable the automatic softwareupdate schedule (requires sudo).
softwareupdate_schedule_enable() {
  ucc_run sudo softwareupdate --schedule on
}

# Usage: run_macos_software_update_from_yaml <cfg_dir> <yaml_path>
run_macos_software_update_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  local query_script manifest_dir ordered target
  query_script="${UCC_TARGETS_QUERY_SCRIPT:-$cfg_dir/tools/validate_targets_manifest.py}"
  manifest_dir="${UCC_TARGETS_MANIFEST:-$cfg_dir/ucc}"
  ordered="$(python3 "$query_script" --ordered-targets macos-software-update "$manifest_dir" 2>/dev/null || true)"

  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    ucc_yaml_parametric_target "$cfg_dir" "$yaml" "$target"
  done <<< "$ordered"
}
