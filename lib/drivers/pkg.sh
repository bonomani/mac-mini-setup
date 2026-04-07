#!/usr/bin/env bash
# lib/drivers/pkg.sh — driver.kind: pkg  (Phase 4 skeleton)
#
# Unified package driver. Replaces (eventually) the per-PM drivers
# (brew, package, npm-global, pip, …). Phase 4 ships as a parallel
# `kind: pkg` so the existing kinds keep working unchanged; migration
# happens YAML-by-YAML in follow-up commits.
#
# YAML shape:
#   driver:
#     kind: pkg
#     backends:                 # ordered preference
#       - npm: opencode-ai
#       - brew: opencode
#       - curl: https://opencode.ai/install
#     bin: opencode             # optional, for foreign-install detection
#     github_repo: sst/opencode # optional, used by the generic outdated check
#
# Backend interface (each backend is a function group):
#   _pkg_<backend>_available           — 0 if backend tool exists on this box
#   _pkg_<backend>_observe   <ref>     — echo "absent"|"outdated"|<version>
#   _pkg_<backend>_install   <ref>     — install <ref>
#   _pkg_<backend>_update    <ref>     — upgrade <ref>
#   _pkg_<backend>_version   <ref>     — echo installed version (or empty)
#   _pkg_<backend>_activate            — optional; ensure runtime on PATH

# ── Backend registry ─────────────────────────────────────────────────────────

# brew (formula). brew_observe already returns absent/outdated/<version>.
_pkg_brew_available() { command -v brew >/dev/null 2>&1; }
_pkg_brew_activate()  { :; }
_pkg_brew_observe()   { brew_observe "$1"; }
_pkg_brew_install()   { brew_install "$1"; }
_pkg_brew_update()    { brew_upgrade "$1"; }
_pkg_brew_version()   { _brew_cached_version "$1"; }
# Outdated detection: piggyback on brew_observe (returns "outdated" when
# brew outdated flags it; UIC_PREF_BREW_LIVECHECK=1 catches formula lag).
_pkg_brew_outdated()  { [[ "$(brew_observe "$1")" == "outdated" ]]; }

# npm-global
_pkg_npm_available()  { _npm_ensure_path; }
_pkg_npm_activate()   { _npm_ensure_path; }
_pkg_npm_observe()    {
  local pkg="$1" v
  v="$(npm_global_version "$pkg")"
  [[ -z "$v" ]] && { printf 'absent'; return; }
  if _pkg_npm_outdated "$pkg"; then
    printf 'outdated'
  else
    printf '%s' "$v"
  fi
}
_pkg_npm_install()    { npm_global_install "$1"; }
_pkg_npm_update()     { npm_global_update  "$1"; }
_pkg_npm_version()    { npm_global_version "$1"; }
# Cache `npm outdated -g --json` once per process; opt-in via the brew
# livecheck flag (same trade-off — slow network call).
_pkg_npm_outdated() {
  [[ "${UIC_PREF_BREW_LIVECHECK:-0}" == "1" ]] || return 1
  local pkg="$1"
  if [[ -z "${_NPM_OUTDATED_CACHE+x}" ]]; then
    export _NPM_OUTDATED_CACHE
    _NPM_OUTDATED_CACHE="$(npm outdated -g --json 2>/dev/null || true)"
  fi
  [[ -n "$_NPM_OUTDATED_CACHE" ]] || return 1
  printf '%s' "$_NPM_OUTDATED_CACHE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(0 if '$pkg' in d else 1)
" 2>/dev/null
}

# curl (script installer fallback). Presence-only: no version source.
_pkg_curl_available() { command -v curl >/dev/null 2>&1; }
_pkg_curl_activate()  { :; }
_pkg_curl_observe()   {
  local bin="${_PKG_BIN:-}"
  [[ -n "$bin" ]] || return 1
  command -v "$bin" >/dev/null 2>&1 && printf 'installed' || printf 'absent'
}
_pkg_curl_install() {
  local url="$1"
  local args="${_PKG_CURL_ARGS:-}"
  if [[ -n "$args" ]]; then
    ucc_run sh -c "curl -fsSL '$url' | sh -s -- $args"
  else
    ucc_run sh -c "curl -fsSL '$url' | sh"
  fi
}
_pkg_curl_update()  { _pkg_curl_install "$1"; }
_pkg_curl_version() { :; }
_pkg_curl_outdated() { return 1; }  # no upstream signal

# brew-cask: macOS GUI apps via Homebrew Cask. Greedy mode (auto-update casks)
# is opt-in via driver.greedy_auto_updates: true at the YAML level.
_pkg_brew_cask_available() { command -v brew >/dev/null 2>&1; }
_pkg_brew_cask_activate()  { :; }
_pkg_brew_cask_observe()   {
  brew_cask_observe "$1" "${_PKG_GREEDY:-false}"
}
_pkg_brew_cask_install()   { brew_cask_install "$1"; }
_pkg_brew_cask_update()    { brew_cask_upgrade "$1" "${_PKG_GREEDY:-false}"; }
_pkg_brew_cask_version()   { _brew_cask_cached_version "$1"; }
_pkg_brew_cask_outdated()  { [[ "$(brew_cask_observe "$1" "${_PKG_GREEDY:-false}")" == "outdated" ]]; }

# native-pm: Linux/WSL2 platform-aware package manager (apt/dnf/pacman/zypper).
# Delegates to the helpers in lib/drivers/package.sh which already implement
# per-PM is_installed/install/upgrade/version. The backend is "available" only
# on non-macOS hosts (and only when a real PM is detected, not 'unknown').
_pkg_native_pm_available() {
  [[ "${HOST_PLATFORM:-macos}" != "macos" ]] || return 1
  declare -f _pkg_native_backend >/dev/null 2>&1 || return 1
  local be; be="$(_pkg_native_backend)"
  [[ "$be" != "unknown" && "$be" != "brew" ]]
}
_pkg_native_pm_activate() { :; }
_pkg_native_pm_observe() {
  local ref="$1" be ver
  be="$(_pkg_native_backend)"
  if _pkg_native_is_installed "$be" "$ref"; then
    ver="$(_pkg_native_version "$be" "$ref")"
    printf '%s' "${ver:-installed}"
  else
    printf 'absent'
  fi
}
_pkg_native_pm_install()  { _pkg_native_install "$(_pkg_native_backend)" "$1"; }
_pkg_native_pm_update()   { _pkg_native_upgrade "$(_pkg_native_backend)" "$1"; }
_pkg_native_pm_version()  { _pkg_native_version "$(_pkg_native_backend)" "$1"; }
_pkg_native_pm_outdated() { return 1; }  # native PM has no uniform outdated check

# pyenv-version
_pkg_pyenv_available() { command -v pyenv >/dev/null 2>&1; }
_pkg_pyenv_activate()  { :; }
_pkg_pyenv_observe()   {
  local v="$1"
  pyenv versions 2>/dev/null | grep -q "$v" && printf '%s' "$v" || printf 'absent'
}
_pkg_pyenv_install()   { ucc_run pyenv install "$1" && ucc_run pyenv global "$1"; }
_pkg_pyenv_update()    { ucc_run pyenv install --skip-existing "$1" && ucc_run pyenv global "$1"; }
_pkg_pyenv_version()   { python3 --version 2>/dev/null | awk '{print $2}'; }
_pkg_pyenv_outdated()  { return 1; }

# ollama-model
_pkg_ollama_available() { command -v ollama >/dev/null 2>&1; }
_pkg_ollama_activate()  { :; }
_pkg_ollama_observe()   {
  local m="$1"
  ollama_model_present "$m" && printf '%s' "$m" || printf 'absent'
}
_pkg_ollama_install()   { ollama_model_pull "$1"; }
_pkg_ollama_update()    { ollama_model_pull "$1"; }
_pkg_ollama_version()   { :; }
_pkg_ollama_outdated()  { return 1; }

# vscode-marketplace
_pkg_vscode_available() { command -v code >/dev/null 2>&1; }
_pkg_vscode_activate()  { :; }
_pkg_vscode_observe()   {
  local id="$1" v
  v="$(_vscode_extension_cached_version "$id" 2>/dev/null || true)"
  [[ -n "$v" ]] && printf '%s' "$v" || printf 'absent'
}
_pkg_vscode_install()   { vscode_extension_install "$1"; }
_pkg_vscode_update()    { vscode_extension_update  "$1"; }
_pkg_vscode_version()   { _vscode_extension_cached_version "$1"; }
_pkg_vscode_outdated()  { return 1; }

# ── Dispatcher ───────────────────────────────────────────────────────────────

# Parse driver.backends list into two arrays: _PKG_BE_NAMES and _PKG_BE_REFS.
# YAML form:
#   backends:
#     - npm: opencode-ai
#     - brew: opencode
# Each item is a single-key mapping; we read both name and ref via the
# helper python tool, since shell can't deeply parse YAML.
_pkg_load_backends() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _PKG_BE_NAMES=()
  _PKG_BE_REFS=()
  local out
  out="$(python3 - "$cfg_dir" "$yaml" "$target" <<'PY' 2>/dev/null || true
import sys, yaml, pathlib, re
cfg_dir, yaml_path, target = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(cfg_dir) / yaml_path if not pathlib.Path(yaml_path).is_absolute() else pathlib.Path(yaml_path)
try:
    data = yaml.safe_load(open(p)) or {}
except Exception:
    sys.exit(0)
# Top-level scalar vars are eligible for ${var} substitution.
top_vars = {k: str(v) for k, v in data.items()
            if k not in ("targets",) and isinstance(v, (str, int, float, bool))}
def subst(s):
    if not isinstance(s, str):
        return s
    return re.sub(r'\$\{([a-zA-Z_][a-zA-Z0-9_]*)\}',
                  lambda m: top_vars.get(m.group(1), m.group(0)),
                  s)
t = (data.get("targets") or {}).get(target) or {}
backends = ((t.get("driver") or {}).get("backends")) or []
for item in backends:
    if isinstance(item, dict) and len(item) == 1:
        for k, v in item.items():
            print(f"{k}\t{subst(v)}")
PY
)"
  while IFS=$'\t' read -r name ref; do
    [[ -n "$name" ]] || continue
    _PKG_BE_NAMES+=("$name")
    _PKG_BE_REFS+=("$ref")
  done <<< "$out"
}

# Pick the first backend whose _pkg_<name>_available returns 0.
# Sets _PKG_PICKED_NAME and _PKG_PICKED_REF.
_pkg_select_backend() {
  _PKG_PICKED_NAME=""
  _PKG_PICKED_REF=""
  local i name ref fn
  for i in "${!_PKG_BE_NAMES[@]}"; do
    name="${_PKG_BE_NAMES[$i]}"
    ref="${_PKG_BE_REFS[$i]}"
    fn="_pkg_${name//-/_}_available"
    declare -f "$fn" >/dev/null 2>&1 || continue
    if "$fn" >/dev/null 2>&1; then
      _PKG_PICKED_NAME="$name"
      _PKG_PICKED_REF="$ref"
      return 0
    fi
  done
  return 1
}

_ucc_driver_pkg_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _pkg_load_backends "$cfg_dir" "$yaml" "$target"
  _pkg_select_backend || { printf 'absent'; return; }
  _PKG_BIN="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin" 2>/dev/null || true)"
  _PKG_GREEDY="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.greedy_auto_updates" 2>/dev/null || true)"
  local fn="_pkg_${_PKG_PICKED_NAME//-/_}_observe"
  declare -f "$fn" >/dev/null 2>&1 || return 1
  "$fn" "$_PKG_PICKED_REF"
}

_ucc_driver_pkg_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  _pkg_load_backends "$cfg_dir" "$yaml" "$target"
  _pkg_select_backend || { log_warn "pkg/${target}: no available backend"; return 1; }
  # Per-backend extras.
  _PKG_CURL_ARGS="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.curl_args" 2>/dev/null || true)"
  _PKG_GREEDY="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.greedy_auto_updates" 2>/dev/null || true)"
  local act_fn="_pkg_${_PKG_PICKED_NAME//-/_}_${action}"
  declare -f "$act_fn" >/dev/null 2>&1 || return 1
  # Optional activation
  local ensure_fn="_pkg_${_PKG_PICKED_NAME//-/_}_activate"
  declare -f "$ensure_fn" >/dev/null 2>&1 && "$ensure_fn" 2>/dev/null || true
  # Foreign-install handling on install: detect a binary owned by a
  # different package manager and consult preferred-driver-policy.
  if [[ "$action" == "install" ]]; then
    local bin display owner safety hint
    bin="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin" 2>/dev/null || true)"
    [[ -z "$bin" ]] && bin="${_PKG_PICKED_REF##*/}"
    display="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "display_name" 2>/dev/null || true)"
    [[ -z "$display" ]] && display="$target"
    if declare -f _npm_global_foreign_owner >/dev/null 2>&1; then
      owner="$(_npm_global_foreign_owner "$bin")"
    fi
    if [[ -n "$owner" ]]; then
      safety="$(_migration_safety_for_target "$cfg_dir" "$yaml" "$target" "$owner" "$bin")"
      hint="brew uninstall ${bin} && retry (or: ./install.sh --pref preferred-driver-policy=migrate ${target})"
      handle_foreign_install "$display" "$owner" "$safety" "$hint" \
        _npm_global_migrate "$owner" "$bin" "$_PKG_PICKED_REF" || return $?
    fi
  fi
  "$act_fn" "$_PKG_PICKED_REF"
}

_ucc_driver_pkg_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _pkg_load_backends "$cfg_dir" "$yaml" "$target"
  _pkg_select_backend || return 1
  local ver_fn="_pkg_${_PKG_PICKED_NAME//-/_}_version"
  local ver=""
  declare -f "$ver_fn" >/dev/null 2>&1 && ver="$("$ver_fn" "$_PKG_PICKED_REF" 2>/dev/null || true)"
  printf 'backend=%s' "$_PKG_PICKED_NAME"
  [[ -n "$ver" ]] && printf '  version=%s' "$ver"
}
