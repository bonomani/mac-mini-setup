#!/usr/bin/env bash
# lib/vscode_ext.sh — helper for YAML-driven VSCode extension targets
# Sourced by components/dev-tools.sh

# Helper: define one VSCode extension as a ucc_target
# Usage: _vscode_ext_target <extension-id>
_vscode_ext_target() {
  local ext="$1"
  local fn="${ext//./-}"
  fn="${fn//-/_}"

  eval "_observe_ext_${fn}() {
    local raw; raw=\$(code --list-extensions --show-versions 2>/dev/null | grep -i '^${ext}@' | awk -F@ '{print \$2}' | head -1 || echo 'absent'); ucc_asm_package_state \"\$raw\"
  }"
  eval "_evidence_ext_${fn}() {
    local ver; ver=\$(code --list-extensions --show-versions 2>/dev/null | grep -i '^${ext}@' | awk -F@ '{print \$2}' | head -1 || true); [[ -n \"\$ver\" ]] && printf 'version=%s' \"\$ver\";
  }"
  eval "_install_ext_${fn}() { ucc_run code --install-extension '${ext}' --force; }"

  ucc_target_nonruntime \
    --name    "vscode-ext-$ext" \
    --observe "_observe_ext_${fn}" \
    --evidence "_evidence_ext_${fn}" \
    --install "_install_ext_${fn}" \
    --update  "_install_ext_${fn}"
}

# Runner: load all VSCode extension targets from a YAML config file.
# Usage: load_vscode_extensions_from_yaml <cfg_dir> <yaml_path>
load_vscode_extensions_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  if is_installed code; then
    while IFS= read -r ext; do
      [[ -n "$ext" ]] && _vscode_ext_target "$ext"
    done < <(yaml_list "$cfg_dir" "$yaml" vscode_extensions)
  fi
}
