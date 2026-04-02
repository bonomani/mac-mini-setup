#!/usr/bin/env bash
# lib/vscode_runner.sh — VS Code install + extensions + settings runner

# Usage: run_vscode_from_yaml <cfg_dir> <yaml_path>
run_vscode_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  # ---- VS Code app ----
  if [[ "${HOST_PLATFORM:-macos}" == "macos" ]]; then
    ucc_yaml_simple_target "$cfg_dir" "$yaml" "vscode"
    ucc_yaml_simple_target "$cfg_dir" "$yaml" "vscode-code-cmd"
  else
    if is_installed code; then
      ucc_skip_target "vscode" "externally installed"
      ucc_skip_target "vscode-code-cmd" "code already in PATH"
    else
      ucc_skip_target "vscode" "install VS Code manually on Linux"
      ucc_skip_target "vscode-code-cmd" "code not available"
    fi
  fi

  # ---- Extensions (cross-platform if code is available) ----
  if is_installed code; then
    load_vscode_extensions_from_yaml "$cfg_dir" "$yaml"
    ucc_yaml_simple_target "$cfg_dir" "$yaml" "vscode-settings"
  else
    ucc_skip_target "vscode-settings" "code not available"
  fi
}
