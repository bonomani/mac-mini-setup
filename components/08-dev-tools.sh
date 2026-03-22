#!/usr/bin/env bash
# Component: Dev tools (Node, VSCode, CLI tools, Oh My Zsh, healthcheck)
# UCC + Basic

# --- CLI tools (brew) ---------------------------------------
CLI_TOOLS=(jq wget curl htop tmux fzf ripgrep fd tree uv pnpm gcc gh llama.cpp opencode aria2)

for tool in "${CLI_TOOLS[@]}"; do
  eval "_observe_${tool}() { brew_observe '$tool'; }"
  eval "_install_${tool}() { ucc_run brew upgrade '$tool' 2>/dev/null || ucc_run brew install '$tool'; }"

  ucc_target \
    --name    "cli-$tool" \
    --observe "_observe_${tool}" \
    --desired "current" \
    --install "_install_${tool}" \
    --update  "_install_${tool}"
done

# --- VSCode -------------------------------------------------
_observe_vscode() {
  # Manual install (/Applications) counts as current — can't upgrade via brew
  if [[ -d "/Applications/Visual Studio Code.app" ]]; then
    echo "current"; return
  fi
  brew_cask_observe visual-studio-code
}
_install_vscode() { ucc_run brew upgrade --cask visual-studio-code 2>/dev/null || ucc_run brew install --cask visual-studio-code; }

ucc_target \
  --name    "vscode" \
  --observe _observe_vscode \
  --desired "current" \
  --install _install_vscode \
  --update  _install_vscode

# Ensure 'code' CLI is available in PATH
_observe_code_cmd() {
  is_installed code && echo "present" || echo "absent"
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

ucc_target \
  --name    "vscode-code-cmd" \
  --observe _observe_code_cmd \
  --desired "present" \
  --install _fix_code_symlink

# --- VSCode extensions --------------------------------------
VSCODE_EXTENSIONS=(
  "ms-python.python"
  "ms-python.vscode-pylance"
  "ms-toolsai.jupyter"
  "ms-vscode.cpptools"
  "continue.continue"
  "eamodio.gitlens"
  "ms-vscode-remote.remote-containers"
)
# Note: Claude Code is a CLI tool (npm), not a VSCode marketplace extension

if is_installed code; then
  for ext in "${VSCODE_EXTENSIONS[@]}"; do
    _ext_id="${ext//./-}"
    eval "_observe_ext_${_ext_id//-/_}() {
      code --list-extensions 2>/dev/null | grep -qi '^${ext}$' && echo 'installed' || echo 'absent'
    }"
    eval "_install_ext_${_ext_id//-/_}() { ucc_run code --install-extension '${ext}' --force; }"

    ucc_target \
      --name    "vscode-ext-$ext" \
      --observe "_observe_ext_${_ext_id//-/_}" \
      --desired "installed" \
      --install "_install_ext_${_ext_id//-/_}" \
      --update  "_install_ext_${_ext_id//-/_}"
  done
fi

# --- VSCode settings.json (merge, not overwrite) ------------
_observe_vscode_settings() {
  local f="$HOME/Library/Application Support/Code/User/settings.json"
  [[ -f "$f" ]] || { echo "absent"; return; }
  # Check if our key is already present
  jq -e '."terminal.integrated.defaultProfile.osx"' "$f" >/dev/null 2>&1 && echo "configured" || echo "needs-update"
}

_apply_vscode_settings() {
  local f="$HOME/Library/Application Support/Code/User/settings.json"
  mkdir -p "$(dirname "$f")"
  local tmp
  tmp="$(mktemp)"
  local patch='{
    "editor.inlineSuggest.enabled": true,
    "extensions.autoUpdate": true,
    "update.mode": "default",
    "python.createEnvironment.trigger": "off",
    "terminal.integrated.defaultProfile.osx": "zsh"
  }'
  if [[ -f "$f" ]] && jq empty "$f" >/dev/null 2>&1; then
    jq --argjson p "$patch" '. + $p' "$f" > "$tmp"
  else
    echo "$patch" | jq '.' > "$tmp"
  fi
  mv "$tmp" "$f"
}

ucc_target \
  --name    "vscode-settings" \
  --observe _observe_vscode_settings \
  --desired "configured" \
  --install _apply_vscode_settings \
  --update  _apply_vscode_settings

# --- iTerm2 -------------------------------------------------
_observe_iterm2() { brew_cask_observe iterm2; }
_install_iterm2() { ucc_run brew upgrade --cask iterm2 2>/dev/null || ucc_run brew install --cask iterm2; }

ucc_target \
  --name    "iterm2" \
  --observe _observe_iterm2 \
  --desired "current" \
  --install _install_iterm2 \
  --update  _install_iterm2

# --- LM Studio — GUI for GGUF models -----------------------
_observe_lmstudio() { brew_cask_observe lm-studio; }
_install_lmstudio() { ucc_run brew upgrade --cask lm-studio 2>/dev/null || ucc_run brew install --cask lm-studio; }

ucc_target \
  --name    "lm-studio" \
  --observe _observe_lmstudio \
  --desired "current" \
  --install _install_lmstudio \
  --update  _install_lmstudio

# --- Node.js 24 LTS -----------------------------------------
# node@24 required by Unsloth Studio; also compatible with Claude Code, Codex, BMAD
_observe_node24() {
  node --version 2>/dev/null | grep -q '^v24\.' || { echo "absent"; return; }
  if [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" == "always-upgrade" ]]; then
    _brew_is_outdated "node@24" && { echo "outdated"; return; }
  fi
  echo "current"
}
_install_node24() {
  # Unlink any older brew-managed node versions to avoid PATH conflicts
  brew unlink node@20 2>/dev/null || true
  if brew list node@24 &>/dev/null 2>&1; then
    ucc_run brew upgrade node@24 2>/dev/null || true
    ucc_run brew link --overwrite --force node@24
  else
    ucc_run brew install node@24 && ucc_run brew link --overwrite --force node@24
  fi
}

ucc_target \
  --name    "node-24-lts" \
  --observe _observe_node24 \
  --desired "current" \
  --install _install_node24 \
  --update  _install_node24

# Ensure node@24 is in PATH
if [[ -d /opt/homebrew/opt/node@24/bin ]]; then
  export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
elif [[ -d /usr/local/opt/node@24/bin ]]; then
  export PATH="/usr/local/opt/node@24/bin:$PATH"
fi

# --- npm global AI CLI tools --------------------------------
# Each is a ucc_target: observe via npm ls -g, install via npm install -g
NPM_GLOBAL_PKGS=(
  "@openai/codex"             # OpenAI Codex CLI
  "@anthropic-ai/claude-code" # Claude Code CLI
  "bmad-method"               # BMAD — Breakthrough Method for Agile AI-Driven Development
)

for pkg in "${NPM_GLOBAL_PKGS[@]}"; do
  _pkg_id="${pkg//[@\/]/_}"  # safe function name
  eval "_observe_npm_${_pkg_id}() {
    npm ls -g '${pkg}' --depth=0 &>/dev/null 2>&1 && echo 'current' || echo 'absent'
  }"
  eval "_install_npm_${_pkg_id}() { ucc_run npm install -g '${pkg}'; }"
  eval "_update_npm_${_pkg_id}()  { ucc_run npm update  -g '${pkg}'; }"

  ucc_target \
    --name    "npm-global-$pkg" \
    --observe "_observe_npm_${_pkg_id}" \
    --desired "current" \
    --install "_install_npm_${_pkg_id}" \
    --update  "_update_npm_${_pkg_id}"
done

# --- Oh My Zsh ----------------------------------------------
_observe_omz() {
  [[ -d "$HOME/.oh-my-zsh" ]] && echo "installed" || echo "absent"
}
_install_omz() {
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
}
_update_omz() {
  [[ -f "$HOME/.oh-my-zsh/tools/upgrade.sh" ]] && bash "$HOME/.oh-my-zsh/tools/upgrade.sh" || true
}

ucc_target \
  --name    "oh-my-zsh" \
  --observe _observe_omz \
  --desired "installed" \
  --install _install_omz \
  --update  _update_omz

# --- Oh My Zsh theme (agnoster) -----------------------------
_observe_omz_theme() {
  grep -q '^ZSH_THEME="agnoster"' "$HOME/.zshrc" 2>/dev/null && echo "set" || echo "unset"
}
_apply_omz_theme() {
  if grep -q '^ZSH_THEME=' "$HOME/.zshrc" 2>/dev/null; then
    sed -i '' 's/^ZSH_THEME=.*/ZSH_THEME="agnoster"/' "$HOME/.zshrc"
  else
    printf '\nZSH_THEME="agnoster"\n' >> "$HOME/.zshrc"
  fi
}

ucc_target \
  --name    "omz-theme-agnoster" \
  --observe _observe_omz_theme \
  --desired "set" \
  --install _apply_omz_theme \
  --update  _apply_omz_theme

# --- $HOME/bin in PATH --------------------------------------
_observe_home_bin_path() {
  grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.zprofile" 2>/dev/null && echo "present" || echo "absent"
}
_add_home_bin_path() {
  mkdir -p "$HOME/bin"
  printf '\nexport PATH="$HOME/bin:$PATH"\n' >> "$HOME/.zprofile"
  export PATH="$HOME/bin:$PATH"
}

ucc_target \
  --name    "home-bin-in-path" \
  --observe _observe_home_bin_path \
  --desired "present" \
  --install _add_home_bin_path

# --- ai-healthcheck script ----------------------------------
_observe_healthcheck() {
  [[ -x "$HOME/bin/ai-healthcheck" ]] && echo "present" || echo "absent"
}
_install_healthcheck() {
  mkdir -p "$HOME/bin"
  cat > "$HOME/bin/ai-healthcheck" <<'HCEOF'
#!/bin/bash
set -euo pipefail
echo "=== AI Mac Mini Healthcheck ==="
echo "brew:    $(command -v brew   || echo 'missing')"
echo "python:  $(python3 --version 2>/dev/null || echo 'missing')"
echo "node:    $(node   --version 2>/dev/null || echo 'missing')"
echo "uv:      $(uv     --version 2>/dev/null || echo 'missing')"
echo "code:    $(code   --version 2>/dev/null | head -n1 || echo 'missing')"
echo "ollama:  $(ollama --version 2>/dev/null || echo 'missing')"
echo ""
echo "--- VSCode extensions ---"
code --list-extensions 2>/dev/null | sort || echo "code not available"
echo ""
echo "--- Ollama models ---"
curl -fsS http://127.0.0.1:11434/api/tags 2>/dev/null \
  | python3 -c "import sys,json; [print(m['name']) for m in json.load(sys.stdin).get('models',[])]" \
  || echo "Ollama API not reachable"
echo ""
echo "--- Docker containers ---"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || echo "Docker not running"
HCEOF
  chmod +x "$HOME/bin/ai-healthcheck"
}

ucc_target \
  --name    "ai-healthcheck" \
  --observe _observe_healthcheck \
  --desired "present" \
  --install _install_healthcheck \
  --update  _install_healthcheck

# --- ariaflow (brew tap bonomani/ariaflow) ------------------
_observe_ariaflow() {
  brew_is_installed ariaflow || { echo "absent"; return; }
  # Require lifecycle command (alpha.3+); older builds return "outdated" → triggers upgrade
  ariaflow lifecycle &>/dev/null 2>&1 || { echo "outdated"; return; }
  if [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" == "always-upgrade" ]]; then
    _brew_is_outdated ariaflow && { echo "outdated"; return; }
  fi
  echo "current"
}
_install_ariaflow() {
  ucc_run brew tap bonomani/ariaflow
  # Unload running launchd agents before upgrade so they restart with the new binary
  for _plist in ~/Library/LaunchAgents/com.ariaflow.*.plist; do
    [[ -f "$_plist" ]] && ucc_run launchctl unload "$_plist" 2>/dev/null || true
  done
  ucc_run brew upgrade ariaflow 2>/dev/null || ucc_run brew install ariaflow
}

ucc_target \
  --name    "ariaflow" \
  --observe _observe_ariaflow \
  --desired "current" \
  --install _install_ariaflow \
  --update  _install_ariaflow

# --- aria2 daemon — launchd (RPC port 6800, survives reboot) -
_observe_aria2_launchd() {
  ariaflow lifecycle 2>/dev/null \
    | python3 -c "import json,sys; r=json.load(sys.stdin).get('aria2-launchd',{}).get('result',{}); print('loaded' if r.get('outcome')=='converged' else 'absent')" \
    2>/dev/null || true
}
_install_aria2_launchd() { ucc_run ariaflow install --with-aria2; }

ucc_target \
  --name    "aria2-launchd" \
  --observe _observe_aria2_launchd \
  --desired "loaded" \
  --install _install_aria2_launchd \
  --update  _install_aria2_launchd

# --- ariaflow web UI — launchd (port 8000, survives reboot) --
_observe_ariaflow_launchd() {
  ariaflow lifecycle 2>/dev/null \
    | python3 -c "import json,sys; r=json.load(sys.stdin).get('ariaflow-serve-launchd',{}).get('result',{}); print('loaded' if r.get('outcome')=='converged' else 'absent')" \
    2>/dev/null || true
}
_install_ariaflow_launchd() { ucc_run ariaflow install --with-web; }

ucc_target \
  --name    "ariaflow-serve-launchd" \
  --observe _observe_ariaflow_launchd \
  --desired "loaded" \
  --install _install_ariaflow_launchd \
  --update  _install_ariaflow_launchd

log_info "aria2 RPC      → http://127.0.0.1:6800"
log_info "ariaflow web UI → http://127.0.0.1:8000"

log_info "Run 'ai-healthcheck' to verify the full setup"

ucc_summary "08-dev-tools"
