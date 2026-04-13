#!/usr/bin/env bash
# lib/drivers/nvm.sh — driver.kind: nvm, nvm-version
#
# nvm        — installs nvm itself
# nvm-version — installs/activates a specific node version via nvm
#              driver.version: <major>  (e.g. 24)
#              driver.nvm_dir: <relpath relative to $HOME>  (e.g. .nvm)

# ── nvm install ───────────────────────────────────────────────────────────────

_nvm_resolve_dir() {
  local dir; dir="$(_ucc_yaml_target_get "$1" "$2" "$3" "driver.nvm_dir")"
  printf '%s' "${dir:-.nvm}"
}

_nvm_self_version() {
  local nvm_dir="$1"
  [[ -s "$HOME/$nvm_dir/nvm.sh" ]] || return 1
  bash -c "source \"\$HOME/$nvm_dir/nvm.sh\" 2>/dev/null && nvm --version 2>/dev/null" || true
}

_ucc_driver_nvm_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local nvm_dir; nvm_dir="$(_nvm_resolve_dir "$cfg_dir" "$yaml" "$target")"
  local ver
  ver="$(_nvm_self_version "$nvm_dir")" || { printf 'absent'; return; }
  [[ -z "$ver" ]] && { printf 'present'; return; }
  if [[ "${UIC_PREF_BREW_LIVECHECK:-0}" == "1" ]]; then
    local repo; repo="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.github_repo" 2>/dev/null || true)"
    if [[ -n "$repo" ]] && declare -f _pkg_github_latest_tag >/dev/null 2>&1; then
      local latest; latest="$(_pkg_github_latest_tag "$repo" 2>/dev/null)"
      if [[ -n "$latest" ]] && declare -f _pkg_version_lt >/dev/null 2>&1 \
         && _pkg_version_lt "$ver" "$latest"; then
        printf 'outdated'; return
      fi
    fi
  fi
  printf '%s' "$ver"
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
  local nvm_dir; nvm_dir="$(_nvm_resolve_dir "$cfg_dir" "$yaml" "$target")"
  local ver; ver="$(_nvm_self_version "$nvm_dir")" || return 1
  [[ -n "$ver" ]] || return 1
  printf 'version=%s  path=%s' "$ver" "$HOME/$nvm_dir"
}

# ── nvm-version ───────────────────────────────────────────────────────────────

_ucc_driver_nvm_version_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ver driver_ver nvm_dir
  driver_ver="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.version")"
  [[ -n "$driver_ver" ]] || return 1
  nvm_dir="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.nvm_dir")"
  nvm_dir="${nvm_dir:-.nvm}"
  ver="${UIC_PREF_NODE_VERSION:-$driver_ver}"
  if [[ ! -s "$HOME/$nvm_dir/nvm.sh" ]]; then
    printf 'absent'
    return
  fi
  local installed
  installed="$(bash -c "source \"\$HOME/$nvm_dir/nvm.sh\" 2>/dev/null && nvm ls \"$ver\" 2>/dev/null" \
    | grep -oE "v${ver}\.[0-9]+\.[0-9]+" | head -1 | sed 's/^v//')"
  if [[ -z "$installed" ]]; then
    printf 'absent'
    return
  fi
  # Outdated check: compare against `nvm ls-remote --lts` for the major.
  # Opt-in via UIC_PREF_BREW_LIVECHECK=1 (network call).
  if [[ "${UIC_PREF_BREW_LIVECHECK:-0}" == "1" ]]; then
    local latest
    latest="$(bash -c "source \"\$HOME/$nvm_dir/nvm.sh\" 2>/dev/null && nvm ls-remote --lts 2>/dev/null" \
      | grep -oE "v${ver}\.[0-9]+\.[0-9]+" | tail -1 | sed 's/^v//')"
    if [[ -n "$latest" ]] && declare -f _pkg_version_lt >/dev/null 2>&1 \
       && _pkg_version_lt "$installed" "$latest"; then
      printf 'outdated'
      return
    fi
  fi
  printf '%s' "$installed"
}

_ucc_driver_nvm_version_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local driver_ver ver nvm_dir
  driver_ver="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.version")"
  [[ -n "$driver_ver" ]] || return 1
  nvm_dir="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.nvm_dir")"
  nvm_dir="${nvm_dir:-.nvm}"
  ver="${UIC_PREF_NODE_VERSION:-$driver_ver}"
  case "$action" in
    install) ucc_run bash -c "source \"\$HOME/$nvm_dir/nvm.sh\" && nvm install \"$ver\" && nvm alias default \"$ver\"" ;;
    update)  ucc_run bash -c "source \"\$HOME/$nvm_dir/nvm.sh\" && nvm install \"$ver\" && nvm alias default \"$ver\"" ;;
  esac
}

_ucc_driver_nvm_version_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local driver_ver ver nvm_dir
  driver_ver="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.version")"
  [[ -n "$driver_ver" ]] || return 1
  nvm_dir="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.nvm_dir")"
  nvm_dir="${nvm_dir:-.nvm}"
  ver="${UIC_PREF_NODE_VERSION:-$driver_ver}"
  if [[ ! -s "$HOME/$nvm_dir/nvm.sh" ]]; then return 1; fi
  local node_ver node_path
  node_ver="$(bash -c "source \"\$HOME/$nvm_dir/nvm.sh\" && nvm run \"$ver\" --version 2>/dev/null" | grep -v '^Running' || true)"
  node_path="$HOME/$nvm_dir/versions/node/v${ver}"
  [[ -d "$node_path" ]] || node_path=""
  printf 'version=%s  path=%s' "${node_ver:-unknown}" "${node_path:-unknown}"
}
