#!/usr/bin/env bash
# lib/dev_tools.sh — Node, VSCode, CLI tools, Oh My Zsh, ariaflow targets
# Sourced by components/dev-tools.sh

# Usage: run_dev_tools_from_yaml <cfg_dir> <yaml_path>
run_dev_tools_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local _NODE_VER _NODE_PREV_VER _OMZ_INSTALLER_URL _OMZ_THEME
  local _VSCODE_CASK_ID _VSCODE_APP_PATH _VSCODE_CLI_PATH _VSCODE_CLI_LINK_PATH _VSCODE_SETTINGS_PATH _VSCODE_SETTINGS_PATCH
  local _ARIAFLOW_TAP _ARIAFLOW_FORMULA _ARIAFLOW_WEB_FORMULA
  _NODE_VER="$(          yaml_get "$cfg_dir" "$yaml" node_version          24)"
  _NODE_PREV_VER="$(     yaml_get "$cfg_dir" "$yaml" node_previous_version 20)"
  _OMZ_INSTALLER_URL="$( yaml_get "$cfg_dir" "$yaml" omz_installer_url     "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh")"
  _OMZ_THEME="$(         yaml_get "$cfg_dir" "$yaml" omz_theme             agnoster)"
  _VSCODE_CASK_ID="$(    yaml_get "$cfg_dir" "$yaml" vscode_cask_id        visual-studio-code)"
  _VSCODE_APP_PATH="$(   yaml_get "$cfg_dir" "$yaml" vscode_app_path       "/Applications/Visual Studio Code.app")"
  _VSCODE_CLI_PATH="$(   yaml_get "$cfg_dir" "$yaml" vscode_cli_path       "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code")"
  _VSCODE_CLI_LINK_PATH="$(yaml_get "$cfg_dir" "$yaml" vscode_cli_link_path "/usr/local/bin/code")"
  _VSCODE_SETTINGS_PATH="$HOME/$(yaml_get "$cfg_dir" "$yaml" vscode_settings_relpath "Library/Application Support/Code/User/settings.json")"
  _VSCODE_SETTINGS_PATCH="$cfg_dir/$(yaml_get "$cfg_dir" "$yaml" vscode_settings_patch "ucc/software/vscode-settings.json")"
  _ARIAFLOW_TAP="$(      yaml_get "$cfg_dir" "$yaml" ariaflow_tap          bonomani/ariaflow)"
  _ARIAFLOW_FORMULA="${_ARIAFLOW_TAP}/ariaflow"
  _ARIAFLOW_WEB_FORMULA="${_ARIAFLOW_TAP}/ariaflow-web"


  # ---- CLI tools (brew) ----
  local _tool
  while IFS= read -r _tool; do
    [[ -n "$_tool" ]] && ucc_brew_target "cli-$_tool" "$_tool"
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
  _observe_code_cmd()  { ucc_asm_package_state "$(is_installed code && code --version 2>/dev/null | awk 'NR==1 {print $1}' || echo "absent")"; }
  _evidence_code_cmd() { local p; p=$(command -v code 2>/dev/null || true); [[ -n "$p" ]] && printf 'path=%s' "$p"; }
  _fix_code_symlink() {
    if [[ -x "$_VSCODE_CLI_PATH" ]]; then
      sudo mkdir -p "$(dirname "$_VSCODE_CLI_LINK_PATH")"
      sudo ln -sf "$_VSCODE_CLI_PATH" "$_VSCODE_CLI_LINK_PATH"
      export PATH="$(dirname "$_VSCODE_CLI_LINK_PATH"):$PATH"
      log_warn "Symlink created. If 'code' is still missing in new shells, run: Cmd+Shift+P → 'Shell Command: Install code command in PATH'"
    else
      log_warn "VS Code binary not found. Open VS Code manually first."
      return 1
    fi
  }

  ucc_target_nonruntime \
    --name     "vscode-code-cmd" \
    --observe  _observe_code_cmd \
    --evidence _evidence_code_cmd \
    --install  _fix_code_symlink

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
  local _cask_name _cask_id
  while IFS=$'\t' read -r _cask_name _cask_id; do
    [[ -n "$_cask_name" ]] && ucc_brew_cask_target "$_cask_name" "$_cask_id"
  done < <(yaml_records "$cfg_dir" "$yaml" casks name id)

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
  local _pkg
  while IFS= read -r _pkg; do
    [[ -n "$_pkg" ]] && ucc_npm_target "$_pkg"
  done < <(yaml_list "$cfg_dir" "$yaml" npm_packages)

  # ---- Oh My Zsh ----
  _observe_omz()  { ucc_asm_package_state "$([[ -d "$HOME/.oh-my-zsh" ]] && echo "installed" || echo "absent")"; }
  _evidence_omz() { printf 'folder=%s' "$HOME/.oh-my-zsh"; }
  _install_omz()  { sh -c "$(curl -fsSL "$_OMZ_INSTALLER_URL")" "" --unattended; }
  _update_omz()   { [[ -f "$HOME/.oh-my-zsh/tools/upgrade.sh" ]] && bash "$HOME/.oh-my-zsh/tools/upgrade.sh" || true; }

  ucc_target_nonruntime \
    --name     "oh-my-zsh" \
    --observe  _observe_omz \
    --evidence _evidence_omz \
    --install  _install_omz \
    --update   _update_omz

  # ---- Oh My Zsh theme ----
  _observe_omz_theme()  { ucc_asm_config_state "$(grep -q "^ZSH_THEME=\"${_OMZ_THEME}\"" "$HOME/.zshrc" 2>/dev/null && echo "set" || echo "unset")"; }
  _evidence_omz_theme() { printf 'theme=%s  file=%s' "$_OMZ_THEME" "$HOME/.zshrc"; }
  _apply_omz_theme() {
    if grep -q '^ZSH_THEME=' "$HOME/.zshrc" 2>/dev/null; then
      sed -i '' "s/^ZSH_THEME=.*/ZSH_THEME=\"${_OMZ_THEME}\"/" "$HOME/.zshrc"
    else
      printf '\nZSH_THEME="%s"\n' "$_OMZ_THEME" >> "$HOME/.zshrc"
    fi
  }

  ucc_target_nonruntime \
    --name     "omz-theme-${_OMZ_THEME}" \
    --observe  _observe_omz_theme \
    --evidence _evidence_omz_theme \
    --install  _apply_omz_theme \
    --update   _apply_omz_theme

  # ---- $HOME/bin in PATH ----
  _observe_home_bin_path()  { ucc_asm_config_state "$(grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.zprofile" 2>/dev/null && echo "present" || echo "absent")"; }
  _evidence_home_bin_path() { printf 'path=%s' "$HOME/bin"; }
  _add_home_bin_path() {
    mkdir -p "$HOME/bin"
    printf '\nexport PATH="$HOME/bin:$PATH"\n' >> "$HOME/.zprofile"
    export PATH="$HOME/bin:$PATH"
  }

  ucc_target_nonruntime \
    --name     "home-bin-in-path" \
    --observe  _observe_home_bin_path \
    --evidence _evidence_home_bin_path \
    --install  _add_home_bin_path

  # ---- ai-healthcheck script ----
  _observe_healthcheck()  { ucc_asm_package_state "$([[ -x "$HOME/bin/ai-healthcheck" ]] && echo "present" || echo "absent")"; }
  _evidence_healthcheck() { printf 'path=%s' "$HOME/bin/ai-healthcheck"; }
  _install_healthcheck() {
    mkdir -p "$HOME/bin"
    install -m 755 "$cfg_dir/scripts/ai-healthcheck" "$HOME/bin/ai-healthcheck"
  }

  ucc_target_nonruntime \
    --name     "ai-healthcheck" \
    --observe  _observe_healthcheck \
    --evidence _evidence_healthcheck \
    --install  _install_healthcheck \
    --update   _install_healthcheck

  # ---- macOS capability: networkQuality CLI ----
  _observe_networkquality() {
    if command -v networkQuality >/dev/null 2>&1; then
      ucc_asm_state --installation Configured --runtime Stopped --health Healthy --admin Enabled --dependencies DepsReady
    else
      ucc_asm_state --installation Installed --runtime Stopped --health Degraded --admin Enabled --dependencies DepsReady
    fi
  }
  _evidence_networkquality() {
    local path
    path="$(command -v networkQuality 2>/dev/null || true)"
    [[ -n "$path" ]] && printf 'path=%s' "$path"
  }

  ucc_target \
    --name     "networkquality-available" \
    --profile  capability \
    --observe  _observe_networkquality \
    --evidence _evidence_networkquality

  ucc_brew_runtime_formula_target "ariaflow" "ariaflow" "$_ARIAFLOW_FORMULA" "$cfg_dir" "$yaml"
  ucc_brew_runtime_formula_target "ariaflow-web" "ariaflow-web" "$_ARIAFLOW_WEB_FORMULA" "$cfg_dir" "$yaml"
}
