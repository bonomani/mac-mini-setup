#!/usr/bin/env bash
# lib/pip_group.sh — helper for YAML-driven pip package group targets
# Sourced by components/ai-python-stack.sh

# Runner: load all pip group targets from a YAML config file.
# Usage: load_pip_groups_from_yaml <cfg_dir> <yaml_path>
load_pip_groups_from_yaml() {
  local cfg_dir="$1" yaml="$2" target=""
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    ucc_yaml_simple_target "$cfg_dir" "$yaml" "$target"
  done < <(yaml_list "$cfg_dir" "$yaml" pip_groups)
}

# Combined runner for ai-python-stack: pip groups + unsloth studio + MPS note.
# Usage: run_ai_python_stack_from_yaml <cfg_dir> <yaml_path>
run_ai_python_stack_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  pip_cache_versions
  load_pip_groups_from_yaml "$cfg_dir" "$yaml"

  # ---- Unsloth package (all platforms) ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "unsloth"

  # ---- Unsloth Studio runtime (platform-specific) ----
  case "${HOST_PLATFORM:-}" in
    macos)
      register_unsloth_studio_targets "$cfg_dir" "$yaml"
      ;;
    linux|wsl2)
      register_unsloth_studio_service_targets "$cfg_dir" "$yaml"
      ;;
  esac

  if [[ "$UCC_DRY_RUN" != "1" ]] && is_installed python3; then
    ucc_yaml_capability_target "$cfg_dir" "$yaml" "mps-available"
  fi
}
