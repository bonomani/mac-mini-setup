#!/usr/bin/env bash
# lib/macos_software_update.sh — helpers for YAML-driven macOS software update policy

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
