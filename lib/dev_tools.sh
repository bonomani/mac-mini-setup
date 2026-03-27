#!/usr/bin/env bash
# lib/dev_tools.sh — Node, VSCode, CLI tools, Oh My Zsh, ariaflow targets
# Sourced by components/dev-tools.sh

# Usage: run_dev_tools_from_yaml <cfg_dir> <yaml_path>
run_dev_tools_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local _NODE_VER
  local _VSCODE_SETTINGS_PATH _VSCODE_SETTINGS_PATCH
  local _ARIAFLOW_TAP _ARIAFLOW_FORMULA _ARIAFLOW_WEB_FORMULA
  _NODE_VER="$(          yaml_get "$cfg_dir" "$yaml" node_version          24)"
  _VSCODE_SETTINGS_PATH="$HOME/$(yaml_get "$cfg_dir" "$yaml" vscode_settings_relpath "Library/Application Support/Code/User/settings.json")"
  _VSCODE_SETTINGS_PATCH="$cfg_dir/$(yaml_get "$cfg_dir" "$yaml" vscode_settings_patch "ucc/software/vscode-settings.json")"
  _ARIAFLOW_TAP="$(      yaml_get "$cfg_dir" "$yaml" ariaflow_tap          bonomani/ariaflow)"
  _ARIAFLOW_FORMULA="${_ARIAFLOW_TAP}/ariaflow"
  _ARIAFLOW_WEB_FORMULA="${_ARIAFLOW_TAP}/ariaflow-web"
  # ---- CLI tools (brew) ----
  local _target
  while IFS= read -r _target; do
    [[ -n "$_target" ]] && ucc_yaml_simple_target "$cfg_dir" "$yaml" "$_target"
  done < <(yaml_list "$cfg_dir" "$yaml" cli_tools)

  # ---- VSCode ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "vscode"

  # ---- code CLI symlink ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "vscode-code-cmd"

  # ---- VSCode extensions ----
  load_vscode_extensions_from_yaml "$cfg_dir" "$yaml"

  # ---- VSCode settings.json (merge, not overwrite) ----
  _vscode_settings_match_patch() {
    local settings_file="$1" patch_file="$2"
    python3 - "$settings_file" "$patch_file" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
patch_path = Path(sys.argv[2])

try:
    settings = json.loads(settings_path.read_text())
    patch = json.loads(patch_path.read_text())
except Exception:
    raise SystemExit(1)

if not isinstance(settings, dict) or not isinstance(patch, dict):
    raise SystemExit(1)

for key, value in patch.items():
    if settings.get(key) != value:
        raise SystemExit(1)

raise SystemExit(0)
PY
  }
  _observe_vscode_settings() {
    [[ -f "$_VSCODE_SETTINGS_PATH" ]] || { ucc_asm_config_state "absent"; return; }
    if _vscode_settings_match_patch "$_VSCODE_SETTINGS_PATH" "$_VSCODE_SETTINGS_PATCH"; then
      ucc_asm_config_state "configured"
    else
      ucc_asm_config_state "needs-update"
    fi
  }
  _evidence_vscode_settings() { printf 'path=%s' "$_VSCODE_SETTINGS_PATH"; }
  _apply_vscode_settings() {
    mkdir -p "$(dirname "$_VSCODE_SETTINGS_PATH")"
    local tmp
    tmp="$(mktemp)"
    python3 - "$_VSCODE_SETTINGS_PATH" "$_VSCODE_SETTINGS_PATCH" "$tmp" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
patch_path = Path(sys.argv[2])
tmp_path = Path(sys.argv[3])

patch = json.loads(patch_path.read_text())
if not isinstance(patch, dict):
    raise SystemExit(1)

if settings_path.exists():
    try:
      settings = json.loads(settings_path.read_text())
    except Exception:
      settings = {}
else:
    settings = {}

if not isinstance(settings, dict):
    settings = {}

settings.update(patch)
tmp_path.write_text(json.dumps(settings, indent=2, sort_keys=True) + "\n")
PY
    mv "$tmp" "$_VSCODE_SETTINGS_PATH"
  }

  ucc_target_nonruntime \
    --name     "vscode-settings" \
    --observe  _observe_vscode_settings \
    --evidence _evidence_vscode_settings \
    --install  _apply_vscode_settings \
    --update   _apply_vscode_settings

  # ---- GUI tools (brew cask) ----
  while IFS= read -r _target; do
    [[ -n "$_target" ]] && ucc_yaml_simple_target "$cfg_dir" "$yaml" "$_target"
  done < <(yaml_list "$cfg_dir" "$yaml" casks)

  # ---- Node.js LTS ----
  # Ensure node@N is first in PATH before observe so version check sees the right binary
  if [[ -d "/opt/homebrew/opt/node@${_NODE_VER}/bin" ]]; then
    export PATH="/opt/homebrew/opt/node@${_NODE_VER}/bin:$PATH"
  elif [[ -d "/usr/local/opt/node@${_NODE_VER}/bin" ]]; then
    export PATH="/usr/local/opt/node@${_NODE_VER}/bin:$PATH"
  fi
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "node-lts"

  # ---- npm global packages ----
  while IFS= read -r _target; do
    [[ -n "$_target" ]] && ucc_yaml_simple_target "$cfg_dir" "$yaml" "$_target"
  done < <(yaml_list "$cfg_dir" "$yaml" npm_packages)

  # ---- YAML-first simple configured targets ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "oh-my-zsh"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "omz-theme-agnoster"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "home-bin-in-path"
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "ai-healthcheck"

  # ---- macOS capability: networkQuality CLI ----
  ucc_yaml_capability_target "$cfg_dir" "$yaml" "networkquality-available"

  ucc_brew_runtime_formula_target "ariaflow" "ariaflow" "$_ARIAFLOW_FORMULA" "$cfg_dir" "$yaml"
  ucc_brew_runtime_formula_target "ariaflow-web" "ariaflow-web" "$_ARIAFLOW_WEB_FORMULA" "$cfg_dir" "$yaml"
}
