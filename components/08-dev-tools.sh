#!/usr/bin/env bash
# Component: Dev tools (Node, VSCode, CLI tools, Oh My Zsh)
# UCC + Basic

# --- CLI tools (brew) ---------------------------------------
CLI_TOOLS=(jq wget htop tmux fzf ripgrep tree)

for tool in "${CLI_TOOLS[@]}"; do
  eval "_observe_${tool}() { brew_is_installed '$tool' && echo 'installed' || echo 'absent'; }"
  eval "_install_${tool}() { ucc_run brew install '$tool'; }"
  eval "_update_${tool}()  { ucc_run brew upgrade '$tool' 2>/dev/null || ucc_run brew install '$tool'; }"

  ucc_target \
    --name    "cli-$tool" \
    --observe "_observe_${tool}" \
    --desired "installed" \
    --install "_install_${tool}" \
    --update  "_update_${tool}"
done

# --- VSCode -------------------------------------------------
_observe_vscode() {
  brew_cask_is_installed visual-studio-code && echo "installed" || echo "absent"
}
_install_vscode() { ucc_run brew install --cask visual-studio-code; }
_update_vscode()  { ucc_run brew upgrade --cask visual-studio-code 2>/dev/null || true; }

ucc_target \
  --name    "vscode" \
  --observe _observe_vscode \
  --desired "installed" \
  --install _install_vscode \
  --update  _update_vscode

# --- VSCode extensions --------------------------------------
VSCODE_EXTENSIONS=(
  "ms-python.python"
  "ms-toolsai.jupyter"
  "anthropics.claude-code"
  "continue.continue"
)

if is_installed code; then
  for ext in "${VSCODE_EXTENSIONS[@]}"; do
    _ext_id="${ext//./-}"
    eval "_observe_ext_${_ext_id}() {
      code --list-extensions 2>/dev/null | grep -q '^${ext}$' && echo 'installed' || echo 'absent'
    }"
    eval "_install_ext_${_ext_id}() { ucc_run code --install-extension '$ext'; }"

    ucc_target \
      --name    "vscode-ext-$ext" \
      --observe "_observe_ext_${_ext_id}" \
      --desired "installed" \
      --install "_install_ext_${_ext_id}" \
      --update  "_install_ext_${_ext_id}"
  done
fi

# --- nvm + Node.js ------------------------------------------
_observe_nvm() {
  [[ -d "$HOME/.nvm" ]] && echo "installed" || echo "absent"
}
_install_nvm() {
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
}

ucc_target \
  --name    "nvm" \
  --observe _observe_nvm \
  --desired "installed" \
  --install _install_nvm

export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1090
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" 2>/dev/null || true

_observe_node() {
  is_installed node && echo "installed" || echo "absent"
}
_install_node() {
  nvm install --lts
  nvm use --lts
}
_update_node() {
  nvm install --lts
  nvm use --lts
  nvm alias default 'lts/*'
}

ucc_target \
  --name    "node-lts" \
  --observe _observe_node \
  --desired "installed" \
  --install _install_node \
  --update  _update_node

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

ucc_summary "08-dev-tools"
