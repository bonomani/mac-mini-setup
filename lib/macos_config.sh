#!/usr/bin/env bash
# lib/macos_config.sh — unified runner for macOS defaults + software update targets

# Usage: run_macos_config_from_yaml <cfg_dir> <yaml_path>
run_macos_config_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  local query_script manifest_dir ordered target
  query_script="${UCC_TARGETS_QUERY_SCRIPT:-$cfg_dir/tools/validate_targets_manifest.py}"
  manifest_dir="${UCC_TARGETS_MANIFEST:-$cfg_dir/ucc}"
  ordered="$(python3 "$query_script" --ordered-targets macos-config "$manifest_dir" 2>/dev/null || true)"

  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    ucc_yaml_parametric_target "$cfg_dir" "$yaml" "$target"
  done <<< "$ordered"

  # Restart UI processes if any defaults changed
  if [[ "$UCC_DRY_RUN" != "1" && ${_UCC_CHANGED:-0} -gt 0 ]]; then
    while IFS= read -r _proc; do
      [[ -n "$_proc" ]] && { killall "$_proc" 2>/dev/null || true; }
    done < <(yaml_list "$cfg_dir" "$yaml" restart_processes)
    log_info "UI processes restarted"
  fi
}
