#!/usr/bin/env bash
# lib/drivers/cli_symlink.sh — driver.kind: cli-symlink
# driver.src_path:      absolute path to the source binary
# driver.link_relpath:  relative path from $HOME for the symlink
# driver.cmd:           command name to check (for oracle/evidence)
# driver.hint:          optional warning message after install

_ucc_driver_cli_symlink_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local cmd
  cmd="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.cmd")"
  [[ -n "$cmd" ]] || return 1
  if command -v "$cmd" >/dev/null 2>&1; then
    printf 'installed'
  else
    printf 'absent'
  fi
}

_ucc_driver_cli_symlink_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local src_path link_relpath hint
  src_path="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.src_path")"
  link_relpath="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.link_relpath")"
  hint="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.hint")"
  [[ -n "$src_path" && -n "$link_relpath" ]] || return 1
  if [[ -x "$src_path" ]]; then
    mkdir -p "$(dirname "$HOME/${link_relpath}")"
    ln -sf "$src_path" "$HOME/${link_relpath}"
    export PATH="$(dirname "$HOME/${link_relpath}"):$PATH"
    [[ -n "$hint" ]] && log_warn "$hint"
  else
    log_warn "Source binary not found at '${src_path}'. Install the app first."
    return 1
  fi
}

_ucc_driver_cli_symlink_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local cmd ver path
  cmd="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.cmd")"
  [[ -n "$cmd" ]] || return 1
  ver="$("$cmd" --version 2>/dev/null | head -1)"
  path="$(command -v "$cmd" 2>/dev/null || true)"
  [[ -n "$path" ]] && printf 'version=%s  path=%s' "${ver:-?}" "$path"
}
