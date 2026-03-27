#!/usr/bin/env bash
# lib/dev_tools.sh — Node, VSCode, CLI tools, Oh My Zsh, ariaflow targets
# Sourced by components/dev-tools.sh

# Usage: run_dev_tools_from_yaml <cfg_dir> <yaml_path>
run_dev_tools_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local _NODE_VER _NODE_PREV_VER
  local _VSCODE_CASK_ID _VSCODE_APP_PATH _VSCODE_SETTINGS_PATH _VSCODE_SETTINGS_PATCH
  local _ARIAFLOW_TAP _ARIAFLOW_FORMULA _ARIAFLOW_WEB_FORMULA
  _NODE_VER="$(          yaml_get "$cfg_dir" "$yaml" node_version          24)"
  _NODE_PREV_VER="$(     yaml_get "$cfg_dir" "$yaml" node_previous_version 20)"
  _VSCODE_CASK_ID="$(    yaml_get "$cfg_dir" "$yaml" vscode_cask_id        visual-studio-code)"
  _VSCODE_APP_PATH="$(   yaml_get "$cfg_dir" "$yaml" vscode_app_path       "/Applications/Visual Studio Code.app")"
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
  _observe_vscode() {
    local raw
    if [[ -d "$_VSCODE_APP_PATH" ]] && ! brew_cask_is_installed "$_VSCODE_CASK_ID"; then
      raw=$(defaults read "${_VSCODE_APP_PATH}/Contents/Info" CFBundleShortVersionString 2>/dev/null \
        || echo "present")
      ucc_asm_package_state "$raw"; return
    fi
    ucc_asm_package_state "$(brew_cask_observe "$_VSCODE_CASK_ID")"
  }
  _evidence_vscode() {
    local ver
    ver=$(defaults read "${_VSCODE_APP_PATH}/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
    [[ -n "$ver" ]] && printf 'version=%s' "$ver"
  }

  _install_vscode() { brew_cask_install "$_VSCODE_CASK_ID"; }
  _update_vscode()  { brew_cask_upgrade "$_VSCODE_CASK_ID"; }

  ucc_target_nonruntime \
    --name     "vscode" \
    --observe  _observe_vscode \
    --evidence _evidence_vscode \
    --install  _install_vscode \
    --update   _update_vscode

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
  _observe_node_lts() {
    local ver
    ver=$(node --version 2>/dev/null)
    [[ "$ver" == v${_NODE_VER}.* ]] || { ucc_asm_package_state "absent"; return; }
    if [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" == "always-upgrade" ]]; then
      _brew_is_outdated "node@${_NODE_VER}" && { ucc_asm_package_state "outdated"; return; }
    fi
    ucc_asm_package_state "${ver#v}"
  }
  _evidence_node_lts() {
    _ucc_ver_path_evidence \
      "$(node --version 2>/dev/null | sed 's/^v//')" \
      "$(command -v node 2>/dev/null || true)"
  }
  _install_node_lts() {
    brew unlink "node@${_NODE_PREV_VER}" 2>/dev/null || true
    ucc_run brew install "node@${_NODE_VER}" && ucc_run brew link --overwrite --force "node@${_NODE_VER}"
  }
  _update_node_lts() {
    ucc_run brew upgrade "node@${_NODE_VER}" && ucc_run brew link --overwrite --force "node@${_NODE_VER}"
  }

  ucc_target_nonruntime \
    --name     "node-lts" \
    --observe  _observe_node_lts \
    --evidence _evidence_node_lts \
    --install  _install_node_lts \
    --update   _update_node_lts

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
