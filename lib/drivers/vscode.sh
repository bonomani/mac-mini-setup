#!/usr/bin/env bash
# lib/drivers/vscode.sh — driver.kind: json-merge
# (vscode-marketplace driver retired; use kind: pkg with vscode backend.)

# ── json-merge ────────────────────────────────────────────────────────────────
# driver.settings_relpath: path relative to $HOME. Two accepted forms:
#   1. flat string                      → used on every platform
#   2. nested map keyed by HOST_PLATFORM → driver picks per-platform value
#      (e.g. settings_relpath.macos / .linux / .wsl2). Falls back to
#      `default:` key if the current platform isn't named.
# driver.patch_relpath:    path relative to $cfg_dir

# Resolve the per-host settings_relpath, supporting either flat or
# platform-keyed map form. Echoes the resolved relpath; empty on failure.
_ucc_driver_json_merge_resolve_relpath() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local platform="${HOST_PLATFORM:-}"
  local rel
  if [[ -n "$platform" ]]; then
    rel="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.settings_relpath.${platform}")"
    [[ -n "$rel" ]] && { printf '%s' "$rel"; return; }
  fi
  rel="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.settings_relpath.default")"
  [[ -n "$rel" ]] && { printf '%s' "$rel"; return; }
  # Flat-string form (backward compat for json-merge users that don't need per-platform paths)
  _ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.settings_relpath"
}

_ucc_driver_json_merge_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local rel_settings rel_patch settings_path patch_path
  rel_settings="$(_ucc_driver_json_merge_resolve_relpath "$cfg_dir" "$yaml" "$target")"
  rel_patch="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.patch_relpath")"
  [[ -n "$rel_settings" && -n "$rel_patch" ]] || return 1
  settings_path="$HOME/$rel_settings"
  if [[ "$rel_patch" == /* ]]; then patch_path="$rel_patch"; else patch_path="$cfg_dir/$rel_patch"; fi
  if python3 "$cfg_dir/tools/drivers/json_merge.py" check "$settings_path" "$patch_path" 2>/dev/null; then
    printf 'configured'
  else
    printf 'absent'
  fi
}

_ucc_driver_json_merge_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  _ucc_driver_json_merge_apply "$cfg_dir" "$yaml" "$target"
}

_ucc_driver_json_merge_apply() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local rel_settings rel_patch settings_path patch_path
  rel_settings="$(_ucc_driver_json_merge_resolve_relpath "$cfg_dir" "$yaml" "$target")"
  rel_patch="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.patch_relpath")"
  [[ -n "$rel_settings" && -n "$rel_patch" ]] || return 1
  settings_path="$HOME/$rel_settings"
  if [[ "$rel_patch" == /* ]]; then patch_path="$rel_patch"; else patch_path="$cfg_dir/$rel_patch"; fi
  ucc_run mkdir -p "$(dirname "$settings_path")"
  _cfg_backup "$settings_path"
  ucc_run python3 "$cfg_dir/tools/drivers/json_merge.py" apply "$settings_path" "$patch_path"
}

_ucc_driver_json_merge_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local rel_settings
  rel_settings="$(_ucc_driver_json_merge_resolve_relpath "$cfg_dir" "$yaml" "$target")"
  [[ -n "$rel_settings" ]] || return 1
  printf 'path=%s' "$HOME/$rel_settings"
}
