#!/usr/bin/env bash
# Component: Dev tools (Node, VSCode, CLI tools, Oh My Zsh, healthcheck)
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — brew formulae + casks + npm globals + launchd agents)
#       Axis B = Basic
# Boundary: local filesystem · brew · npm · macOS launchd · network (package downloads)

# --- CLI tools (brew) — list sourced from config/08-dev-tools.yaml
_DT_CFG_DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
_DT_CFG="$_DT_CFG_DIR/config/08-dev-tools.yaml"
_NODE_VER="$(python3 "$_DT_CFG_DIR/tools/read_config.py" --get "$_DT_CFG" node_version 2>/dev/null)"
_NODE_VER="${_NODE_VER:-24}"
_OMZ_INSTALLER_URL="$(python3 "$_DT_CFG_DIR/tools/read_config.py" --get "$_DT_CFG" omz_installer_url 2>/dev/null)"
_OMZ_INSTALLER_URL="${_OMZ_INSTALLER_URL:-https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh}"
_OMZ_THEME="$(python3 "$_DT_CFG_DIR/tools/read_config.py" --get "$_DT_CFG" omz_theme 2>/dev/null)"
_OMZ_THEME="${_OMZ_THEME:-agnoster}"
_ARIAFLOW_TAP="$(python3 "$_DT_CFG_DIR/tools/read_config.py" --get "$_DT_CFG" ariaflow_tap 2>/dev/null)"
_ARIAFLOW_TAP="${_ARIAFLOW_TAP:-bonomani/ariaflow}"
_ARIA2_PORT="$(python3 "$_DT_CFG_DIR/tools/read_config.py" --get "$_DT_CFG" aria2_port 2>/dev/null)"
_ARIA2_PORT="${_ARIA2_PORT:-6800}"
_ARIAFLOW_WEB_PORT="$(python3 "$_DT_CFG_DIR/tools/read_config.py" --get "$_DT_CFG" ariaflow_web_port 2>/dev/null)"
_ARIAFLOW_WEB_PORT="${_ARIAFLOW_WEB_PORT:-8001}"
CLI_TOOLS=()
while IFS= read -r t; do [[ -n "$t" ]] && CLI_TOOLS+=("$t"); done \
  < <(python3 "$_DT_CFG_DIR/tools/read_config.py" --list "$_DT_CFG" cli_tools 2>/dev/null)

for tool in "${CLI_TOOLS[@]}"; do
  ucc_brew_target "cli-$tool" "$tool"
done

_devtools_brew_cask_target() {
  local target_name="$1" cask_pkg="$2"
  ucc_brew_cask_target "$target_name" "$cask_pkg"
}

_devtools_vscode_extension_target() {
  local ext="$1"
  local ext_id fn
  ext_id="${ext//./-}"
  fn="${ext_id//-/_}"
  eval "_observe_ext_${fn}() {
    local raw; raw=\$(code --list-extensions --show-versions 2>/dev/null | grep -i '^${ext}@' | awk -F@ '{print \$2}' | head -1 || echo 'absent'); ucc_asm_package_state \"\$raw\"
  }"
  eval "_evidence_ext_${fn}() {
    local ver; ver=\$(code --list-extensions --show-versions 2>/dev/null | grep -i '^${ext}@' | awk -F@ '{print \$2}' | head -1 || true); [[ -n \"\$ver\" ]] && printf 'version=%s' \"\$ver\";
  }"
  eval "_install_ext_${fn}() { ucc_run code --install-extension '${ext}' --force; }"

  ucc_target_nonruntime \
    --name "vscode-ext-$ext" \
    --observe "_observe_ext_${fn}" \
    --evidence "_evidence_ext_${fn}" \
    --install "_install_ext_${fn}" \
    --update "_install_ext_${fn}"
}

# --- VSCode -------------------------------------------------
_observe_vscode() {
  local raw
  # Manual install (/Applications) counts as present — can't upgrade via brew
  if [[ -d "/Applications/Visual Studio Code.app" ]] && ! brew_cask_is_installed visual-studio-code; then
    raw=$(defaults read "/Applications/Visual Studio Code.app/Contents/Info" CFBundleShortVersionString 2>/dev/null \
      || echo "present")
    ucc_asm_package_state "$raw"
    return
  fi
  raw=$(brew_cask_observe visual-studio-code)
  ucc_asm_package_state "$raw"
  return
}
_evidence_vscode() {
  local ver
  ver=$(defaults read "/Applications/Visual Studio Code.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
}
_install_vscode() { brew_cask_install visual-studio-code; }
_update_vscode()  { brew_cask_upgrade visual-studio-code; }

ucc_target_nonruntime \
  --name    "vscode" \
  --observe _observe_vscode \
  --evidence _evidence_vscode \
  --install _install_vscode \
  --update  _update_vscode

# Ensure 'code' CLI is available in PATH
_observe_code_cmd() {
  local raw
  raw=$(is_installed code && code --version 2>/dev/null | awk 'NR==1 {print $1}' || echo "absent")
  ucc_asm_package_state "$raw"
}
_evidence_code_cmd() {
  local path
  path=$(command -v code 2>/dev/null || true)
  [[ -n "$path" ]] && printf 'path=%s' "$path"
}
_fix_code_symlink() {
  local vscode_bin="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  if [[ -x "$vscode_bin" ]]; then
    sudo mkdir -p /usr/local/bin
    sudo ln -sf "$vscode_bin" /usr/local/bin/code
    export PATH="/usr/local/bin:$PATH"
    log_warn "Symlink created. If 'code' is still missing in new shells, run: Cmd+Shift+P → 'Shell Command: Install code command in PATH'"
  else
    log_warn "VS Code binary not found. Open VS Code manually first."
    return 1
  fi
}

ucc_target_nonruntime \
  --name    "vscode-code-cmd" \
  --observe _observe_code_cmd \
  --evidence _evidence_code_cmd \
  --install _fix_code_symlink

# --- VSCode extensions — list sourced from config/08-dev-tools.yaml
# Note: Claude Code is a CLI tool (npm), not a VSCode marketplace extension
if is_installed code; then
  while IFS= read -r ext; do
    [[ -n "$ext" ]] && _devtools_vscode_extension_target "$ext"
  done < <(python3 "$_DT_CFG_DIR/tools/read_config.py" --list "$_DT_CFG" vscode_extensions 2>/dev/null)
fi

# --- VSCode settings.json (merge, not overwrite) ------------
_observe_vscode_settings() {
  local f="$HOME/Library/Application Support/Code/User/settings.json"
  [[ -f "$f" ]] || { ucc_asm_config_state "absent"; return; }
  # Check if our key is already present
  if jq -e '."terminal.integrated.defaultProfile.osx"' "$f" >/dev/null 2>&1; then
    ucc_asm_config_state "configured"
  else
    ucc_asm_config_state "needs-update"
  fi
}
_evidence_vscode_settings() {
  printf 'path=%s' "$HOME/Library/Application Support/Code/User/settings.json"
}

_apply_vscode_settings() {
  local f="$HOME/Library/Application Support/Code/User/settings.json"
  local patch_file="$_DT_CFG_DIR/config/vscode-settings.json"
  mkdir -p "$(dirname "$f")"
  local tmp patch
  tmp="$(mktemp)"
  patch=$(cat "$patch_file")
  if [[ -f "$f" ]] && jq empty "$f" >/dev/null 2>&1; then
    jq --argjson p "$patch" '. + $p' "$f" > "$tmp"
  else
    echo "$patch" | jq '.' > "$tmp"
  fi
  mv "$tmp" "$f"
}

ucc_target_nonruntime \
  --name    "vscode-settings" \
  --observe _observe_vscode_settings \
  --evidence _evidence_vscode_settings \
  --install _apply_vscode_settings \
  --update  _apply_vscode_settings

# --- GUI tools (brew cask) — list sourced from config/08-dev-tools.yaml
while IFS=$'\t' read -r cask_name cask_id; do
  [[ -n "$cask_name" ]] && _devtools_brew_cask_target "$cask_name" "$cask_id"
done < <(python3 "$_DT_CFG_DIR/tools/read_config.py" --records "$_DT_CFG" casks name id 2>/dev/null)

# --- Node.js LTS (version from config/08-dev-tools.yaml) ---
# node@${_NODE_VER} required by Unsloth Studio; also compatible with Claude Code, Codex, BMAD
_observe_node24() {
  local ver raw
  ver=$(node --version 2>/dev/null)
  [[ "$ver" == v${_NODE_VER}.* ]] || { ucc_asm_package_state "absent"; return; }
  if [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" == "always-upgrade" ]]; then
    _brew_is_outdated "node@${_NODE_VER}" && { ucc_asm_package_state "outdated"; return; }
  fi
  raw="${ver#v}"
  ucc_asm_package_state "$raw"
}
_evidence_node24() {
  local ver path
  ver=$(node --version 2>/dev/null | sed 's/^v//')
  path=$(command -v node 2>/dev/null || true)
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
  [[ -n "$path" ]] && printf '%s path=%s' "${ver:+ }" "$path"
}
_install_node24() {
  brew unlink "node@$(( _NODE_VER - 4 ))" 2>/dev/null || true
  ucc_run brew install "node@${_NODE_VER}" && ucc_run brew link --overwrite --force "node@${_NODE_VER}"
}
_update_node24() {
  ucc_run brew upgrade "node@${_NODE_VER}" && ucc_run brew link --overwrite --force "node@${_NODE_VER}"
}

ucc_target_nonruntime \
  --name    "node-24-lts" \
  --observe _observe_node24 \
  --evidence _evidence_node24 \
  --install _install_node24 \
  --update  _update_node24

# Ensure node@24 is in PATH
if [[ -d /opt/homebrew/opt/node@24/bin ]]; then
  export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
elif [[ -d /usr/local/opt/node@24/bin ]]; then
  export PATH="/usr/local/opt/node@24/bin:$PATH"
fi

# --- npm global AI CLI tools — list sourced from config/08-dev-tools.yaml
while IFS= read -r pkg; do
  [[ -n "$pkg" ]] && ucc_npm_target "$pkg"
done < <(python3 "$_DT_CFG_DIR/tools/read_config.py" --list "$_DT_CFG" npm_packages 2>/dev/null)

# --- Oh My Zsh ----------------------------------------------
_observe_omz() {
  local raw
  raw=$([[ -d "$HOME/.oh-my-zsh" ]] && echo "installed" || echo "absent")
  ucc_asm_package_state "$raw"
}
_evidence_omz() { printf 'folder=%s' "$HOME/.oh-my-zsh"; }
_install_omz() {
  sh -c "$(curl -fsSL "$_OMZ_INSTALLER_URL")" "" --unattended
}
_update_omz() {
  [[ -f "$HOME/.oh-my-zsh/tools/upgrade.sh" ]] && bash "$HOME/.oh-my-zsh/tools/upgrade.sh" || true
}

ucc_target_nonruntime \
  --name    "oh-my-zsh" \
  --observe _observe_omz \
  --evidence _evidence_omz \
  --install _install_omz \
  --update  _update_omz

# --- Oh My Zsh theme (from config) -----------------------------
_observe_omz_theme() {
  local raw
  raw=$(grep -q "^ZSH_THEME=\"${_OMZ_THEME}\"" "$HOME/.zshrc" 2>/dev/null && echo "set" || echo "unset")
  ucc_asm_config_state "$raw"
}
_evidence_omz_theme() { printf 'theme=%s file=%s' "$_OMZ_THEME" "$HOME/.zshrc"; }
_apply_omz_theme() {
  if grep -q '^ZSH_THEME=' "$HOME/.zshrc" 2>/dev/null; then
    sed -i '' "s/^ZSH_THEME=.*/ZSH_THEME=\"${_OMZ_THEME}\"/" "$HOME/.zshrc"
  else
    printf '\nZSH_THEME="%s"\n' "$_OMZ_THEME" >> "$HOME/.zshrc"
  fi
}

ucc_target_nonruntime \
  --name    "omz-theme-${_OMZ_THEME}" \
  --observe _observe_omz_theme \
  --evidence _evidence_omz_theme \
  --install _apply_omz_theme \
  --update  _apply_omz_theme

# --- $HOME/bin in PATH --------------------------------------
_observe_home_bin_path() {
  local raw
  raw=$(grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.zprofile" 2>/dev/null && echo "present" || echo "absent")
  ucc_asm_config_state "$raw"
}
_evidence_home_bin_path() { printf 'path=%s' "$HOME/bin"; }
_add_home_bin_path() {
  mkdir -p "$HOME/bin"
  printf '\nexport PATH="$HOME/bin:$PATH"\n' >> "$HOME/.zprofile"
  export PATH="$HOME/bin:$PATH"
}

ucc_target_nonruntime \
  --name    "home-bin-in-path" \
  --observe _observe_home_bin_path \
  --evidence _evidence_home_bin_path \
  --install _add_home_bin_path

# --- ai-healthcheck script ----------------------------------
_observe_healthcheck() {
  local raw
  raw=$([[ -x "$HOME/bin/ai-healthcheck" ]] && echo "present" || echo "absent")
  ucc_asm_package_state "$raw"
}
_evidence_healthcheck() { printf 'path=%s' "$HOME/bin/ai-healthcheck"; }
_install_healthcheck() {
  mkdir -p "$HOME/bin"
  install -m 755 "$_DT_CFG_DIR/scripts/ai-healthcheck" "$HOME/bin/ai-healthcheck"
}

ucc_target_nonruntime \
  --name    "ai-healthcheck" \
  --observe _observe_healthcheck \
  --evidence _evidence_healthcheck \
  --install _install_healthcheck \
  --update  _install_healthcheck

# --- ariaflow (brew tap bonomani/ariaflow) ------------------
_observe_ariaflow() {
  brew_is_installed ariaflow || { ucc_asm_package_state "absent"; return; }
  # Require lifecycle command (alpha.3+); older builds return "outdated" → triggers upgrade
  ariaflow lifecycle &>/dev/null 2>&1 || { ucc_asm_package_state "outdated"; return; }
  if [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" == "always-upgrade" ]]; then
    _brew_is_outdated ariaflow && { ucc_asm_package_state "outdated"; return; }
  fi
  local raw
  raw=$(brew list --versions ariaflow 2>/dev/null | awk '{print $NF}')
  ucc_asm_package_state "$raw"
}
_evidence_ariaflow() {
  local ver
  ver=$(brew list --versions ariaflow 2>/dev/null | awk '{print $NF}')
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
}
_install_ariaflow() {
  ucc_run brew tap "$_ARIAFLOW_TAP"
  brew_install ariaflow
}
_update_ariaflow() {
  ucc_run brew tap "$_ARIAFLOW_TAP"
  # Unload running launchd agents before upgrade so they restart with the new binary
  for _plist in ~/Library/LaunchAgents/com.ariaflow.*.plist; do
    [[ -f "$_plist" ]] && ucc_run launchctl unload "$_plist" 2>/dev/null || true
  done
  brew_upgrade ariaflow
}

ucc_target_nonruntime \
  --name    "ariaflow" \
  --observe _observe_ariaflow \
  --evidence _evidence_ariaflow \
  --install _install_ariaflow \
  --update  _update_ariaflow

# --- aria2 daemon — launchd (RPC port 6800, survives reboot) -
_observe_aria2_launchd() {
  ariaflow lifecycle 2>/dev/null \
    | python3 -c "import json,sys; r=json.load(sys.stdin).get('aria2-launchd',{}).get('result',{}); print('loaded' if r.get('outcome')=='converged' else 'absent')" \
    2>/dev/null | while read -r raw; do ucc_asm_service_state \"${raw:-absent}\"; done
}
_evidence_aria2_launchd() {
  local pid
  pid=$(lsof -ti "tcp:${_ARIA2_PORT}" 2>/dev/null | head -1 || true)
  [[ -n "$pid" ]] && printf 'pid=%s port=%s' "$pid" "$_ARIA2_PORT" || printf 'port=%s' "$_ARIA2_PORT"
}
# install and update both use ariaflow install — it is idempotent and handles both cases
_install_aria2_launchd() { ucc_run ariaflow install --with-aria2; }

ucc_target_service \
  --name    "aria2-launchd" \
  --observe _observe_aria2_launchd \
  --evidence _evidence_aria2_launchd \
  --desired "$(ucc_asm_state --installation Configured --runtime Running --health Healthy --admin Enabled --dependencies DepsReady)" \
  --install _install_aria2_launchd \
  --update  _install_aria2_launchd

# --- ariaflow-web — brew formula (port 8001, separate from ariaflow) -
# ariaflow-web is a distinct brew package; managed via brew services (not ariaflow install --with-web)
_observe_ariaflow_web() {
  local raw
  raw=$(brew_observe ariaflow-web)
  ucc_asm_package_state "$raw"
}
_evidence_ariaflow_web() {
  local ver
  ver=$(brew list --versions ariaflow-web 2>/dev/null | awk '{print $NF}')
  [[ -n "$ver" ]] && printf 'version=%s' "$ver"
}
_install_ariaflow_web() {
  ucc_run brew tap "$_ARIAFLOW_TAP"
  brew_install ariaflow-web
}
_update_ariaflow_web() {
  ucc_run brew tap "$_ARIAFLOW_TAP"
  brew_upgrade ariaflow-web
}

ucc_target_nonruntime \
  --name    "ariaflow-web" \
  --observe _observe_ariaflow_web \
  --evidence _evidence_ariaflow_web \
  --install _install_ariaflow_web \
  --update  _update_ariaflow_web

# --- ariaflow-web service — brew services (port 8001, survives reboot) --
_observe_ariaflow_web_service() {
  if brew services list 2>/dev/null | awk '/^ariaflow-web/ {print $2}' | grep -q "^started$"; then
    ucc_asm_service_state "started"
  else
    ucc_asm_service_state "stopped"
  fi
}
_evidence_ariaflow_web_service() {
  local pid
  pid=$(lsof -ti "tcp:${_ARIAFLOW_WEB_PORT}" 2>/dev/null | head -1 || true)
  [[ -n "$pid" ]] && printf 'pid=%s port=%s' "$pid" "$_ARIAFLOW_WEB_PORT" || printf 'port=%s' "$_ARIAFLOW_WEB_PORT"
}
_start_ariaflow_web_service() {
  ucc_run brew services start ${_ARIAFLOW_TAP}/ariaflow-web
}
_restart_ariaflow_web_service() {
  ucc_run brew services restart ${_ARIAFLOW_TAP}/ariaflow-web
}

ucc_target_service \
  --name    "ariaflow-web-service" \
  --observe _observe_ariaflow_web_service \
  --evidence _evidence_ariaflow_web_service \
  --desired "$(ucc_asm_state --installation Configured --runtime Running --health Healthy --admin Enabled --dependencies DepsReady)" \
  --install _start_ariaflow_web_service \
  --update  _restart_ariaflow_web_service

ucc_summary "08-dev-tools"
