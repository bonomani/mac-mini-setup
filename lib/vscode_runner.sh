#!/usr/bin/env bash
# lib/vscode_runner.sh — VS Code install + extensions + settings runner

# Echo the absolute path to the VS Code user settings.json for the
# current host platform. Called from YAML evidence fields.
vscode_settings_path() {
  case "${HOST_PLATFORM:-}" in
    macos) printf '%s' "$HOME/Library/Application Support/Code/User/settings.json" ;;
    wsl)   printf '%s' "$HOME/.vscode-server/data/User/settings.json" ;;
    linux) printf '%s' "$HOME/.config/Code/User/settings.json" ;;
    *)     printf '%s' "$HOME/.config/Code/User/settings.json" ;;
  esac
}

# Usage: run_vscode_from_yaml <cfg_dir> <yaml_path>
run_vscode_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  # ---- VS Code app ----
  if [[ "${HOST_PLATFORM:-macos}" == "macos" ]]; then
    ucc_yaml_simple_target "$cfg_dir" "$yaml" "vscode"
    ucc_yaml_simple_target "$cfg_dir" "$yaml" "vscode-code-cmd"
  else
    if is_installed code; then
      # Dep IS present — pass --satisfied so dependents (vscode-settings,
      # all extensions) proceed normally instead of cascade-skipping.
      ucc_skip_target "vscode" "externally installed" --satisfied
      ucc_skip_target "vscode-code-cmd" "code already in PATH" --satisfied
    else
      # Dep is missing — leave default "skipped" status so dependents
      # cascade-skip cleanly.
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
