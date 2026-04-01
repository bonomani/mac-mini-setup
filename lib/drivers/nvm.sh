#!/usr/bin/env bash
# lib/drivers/nvm.sh — driver.kind: nvm, nvm-version
#
# nvm        — installs nvm itself
# nvm-version — installs/activates a specific node version via nvm
#              driver.version: <major>  (e.g. 24)

# ── nvm install ───────────────────────────────────────────────────────────────

_ucc_driver_nvm_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    local ver
    ver="$(bash -c 'source "$HOME/.nvm/nvm.sh" 2>/dev/null && nvm --version 2>/dev/null' || true)"
    printf '%s' "${ver:-present}"
  else
    printf 'absent'
  fi
}

_ucc_driver_nvm_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local installer_url
  installer_url="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.installer_url")"
  [[ -n "$installer_url" ]] || installer_url="https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh"
  ucc_run bash -c "curl -fsSL '$installer_url' | bash"
}

_ucc_driver_nvm_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ver
  ver="$(bash -c 'source "$HOME/.nvm/nvm.sh" 2>/dev/null && nvm --version 2>/dev/null' || true)"
  [[ -n "$ver" ]] || return 1
  printf 'version=%s  path=%s' "$ver" "$HOME/.nvm"
}

# ── nvm-version ───────────────────────────────────────────────────────────────

_ucc_driver_nvm_version_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ver driver_ver
  driver_ver="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.version")"
  [[ -n "$driver_ver" ]] || return 1
  ver="${UIC_PREF_NODE_VERSION:-$driver_ver}"
  if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
    printf 'absent'
    return
  fi
  if bash -c "source \"\$HOME/.nvm/nvm.sh\" 2>/dev/null && nvm ls \"$ver\" 2>/dev/null" | grep -q "v${ver}"; then
    printf '%s' "$ver"
  else
    printf 'absent'
  fi
}

_ucc_driver_nvm_version_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local driver_ver ver
  driver_ver="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.version")"
  [[ -n "$driver_ver" ]] || return 1
  ver="${UIC_PREF_NODE_VERSION:-$driver_ver}"
  case "$action" in
    install) ucc_run bash -c "source \"\$HOME/.nvm/nvm.sh\" && nvm install \"$ver\" && nvm alias default \"$ver\"" ;;
    update)  ucc_run bash -c "source \"\$HOME/.nvm/nvm.sh\" && nvm install \"$ver\" && nvm alias default \"$ver\"" ;;
  esac
}

_ucc_driver_nvm_version_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local driver_ver ver path
  driver_ver="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.version")"
  [[ -n "$driver_ver" ]] || return 1
  ver="${UIC_PREF_NODE_VERSION:-$driver_ver}"
  if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then return 1; fi
  local node_ver node_path
  node_ver="$(bash -c "source \"\$HOME/.nvm/nvm.sh\" && nvm run \"$ver\" --version 2>/dev/null" | grep -v '^Running' || true)"
  node_path="$HOME/.nvm/versions/node/v${ver}"
  [[ -d "$node_path" ]] || node_path=""
  printf 'version=%s  path=%s' "${node_ver:-unknown}" "${node_path:-unknown}"
}
