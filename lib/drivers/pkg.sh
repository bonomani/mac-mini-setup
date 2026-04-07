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

# brew (formula)
_pkg_brew_available() { command -v brew >/dev/null 2>&1; }
_pkg_brew_activate()  { :; }
_pkg_brew_observe()   { brew_observe "$1"; }
_pkg_brew_install()   { brew_install "$1"; }
_pkg_brew_update()    { brew_upgrade "$1"; }
_pkg_brew_version()   { _brew_cached_version "$1"; }

# npm-global
_pkg_npm_available()  { _npm_ensure_path; }
_pkg_npm_activate()   { _npm_ensure_path; }
_pkg_npm_observe()    { npm_global_observe "$1"; }
_pkg_npm_install()    { npm_global_install "$1"; }
_pkg_npm_update()     { npm_global_update  "$1"; }
_pkg_npm_version()    { npm_global_version "$1"; }

# curl (script installer fallback)
_pkg_curl_available() { command -v curl >/dev/null 2>&1; }
_pkg_curl_activate()  { :; }
_pkg_curl_observe()   {
  # Presence-only: curl-installed packages have no version source.
  local bin="${_PKG_BIN:-}"
  [[ -n "$bin" ]] || return 1
  command -v "$bin" >/dev/null 2>&1 && printf 'installed' || printf 'absent'
}
_pkg_curl_install() {
  local url="$1"
  ucc_run sh -c "curl -fsSL '$url' | sh"
}
_pkg_curl_update()  { _pkg_curl_install "$1"; }
_pkg_curl_version() { :; }

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
import sys, yaml, pathlib
cfg_dir, yaml_path, target = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(cfg_dir) / yaml_path if not pathlib.Path(yaml_path).is_absolute() else pathlib.Path(yaml_path)
try:
    data = yaml.safe_load(open(p)) or {}
except Exception:
    sys.exit(0)
t = (data.get("targets") or {}).get(target) or {}
backends = ((t.get("driver") or {}).get("backends")) or []
for item in backends:
    if isinstance(item, dict) and len(item) == 1:
        for k, v in item.items():
            print(f"{k}\t{v}")
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
  local fn="_pkg_${_PKG_PICKED_NAME//-/_}_observe"
  declare -f "$fn" >/dev/null 2>&1 || return 1
  "$fn" "$_PKG_PICKED_REF"
}

_ucc_driver_pkg_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  _pkg_load_backends "$cfg_dir" "$yaml" "$target"
  _pkg_select_backend || { log_warn "pkg/${target}: no available backend"; return 1; }
  local act_fn="_pkg_${_PKG_PICKED_NAME//-/_}_${action}"
  declare -f "$act_fn" >/dev/null 2>&1 || return 1
  # Optional activation
  local ensure_fn="_pkg_${_PKG_PICKED_NAME//-/_}_activate"
  declare -f "$ensure_fn" >/dev/null 2>&1 && "$ensure_fn" 2>/dev/null || true
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
