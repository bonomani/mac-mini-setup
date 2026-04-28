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
# Backend families are extracted into focused files as the registry grows.
# shellcheck source=lib/drivers/pkg_github.sh
source "${BASH_SOURCE[0]%/*}/pkg_github.sh"
# shellcheck source=lib/drivers/pkg_npm.sh
source "${BASH_SOURCE[0]%/*}/pkg_npm.sh"
# shellcheck source=lib/drivers/pkg_curl.sh
source "${BASH_SOURCE[0]%/*}/pkg_curl.sh"
# shellcheck source=lib/drivers/pkg_brew.sh
source "${BASH_SOURCE[0]%/*}/pkg_brew.sh"
# shellcheck source=lib/drivers/pkg_native_pm.sh
source "${BASH_SOURCE[0]%/*}/pkg_native_pm.sh"
# shellcheck source=lib/drivers/pkg_winget.sh
source "${BASH_SOURCE[0]%/*}/pkg_winget.sh"
# shellcheck source=lib/drivers/pkg_pyenv.sh
source "${BASH_SOURCE[0]%/*}/pkg_pyenv.sh"
# shellcheck source=lib/drivers/pkg_ollama.sh
source "${BASH_SOURCE[0]%/*}/pkg_ollama.sh"
# shellcheck source=lib/drivers/pkg_vscode.sh
source "${BASH_SOURCE[0]%/*}/pkg_vscode.sh"




# Return 0 if $1 (installed) is strictly older than $2 (latest). Tolerates `v`
# prefix and trailing metadata. Empty inputs → not older.
_pkg_version_lt() {
  local installed="${1#v}" latest="${2#v}"
  [[ -n "$installed" && -n "$latest" ]] || return 1
  [[ "$installed" == "$latest" ]] && return 1
  local first
  first=$(printf '%s\n%s\n' "$installed" "$latest" | sort -V | head -n1)
  [[ "$first" == "$installed" ]]
}







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
  local out name ref
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
import json, base64
def _subst_deep(o):
    if isinstance(o, str):  return subst(o)
    if isinstance(o, dict): return {kk: _subst_deep(vv) for kk, vv in o.items()}
    if isinstance(o, list): return [_subst_deep(x) for x in o]
    return o
for item in backends:
    if isinstance(item, dict) and len(item) == 1:
        for k, v in item.items():
            if isinstance(v, dict):
                payload = json.dumps(_subst_deep(v))
                ref = "json:" + base64.b64encode(payload.encode()).decode()
            else:
                ref = subst(v)
            print(f"{k}\t{ref}")
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
  _PKG_GITHUB_REPO="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.github_repo" 2>/dev/null || true)"
  _PKG_UPDATE_CLASS="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "update_class" 2>/dev/null || true)"
  local fn="_pkg_${_PKG_PICKED_NAME//-/_}_observe"
  declare -f "$fn" >/dev/null 2>&1 || return 1
  "$fn" "$_PKG_PICKED_REF"
}

_ucc_driver_pkg_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  _pkg_load_backends "$cfg_dir" "$yaml" "$target"
  _pkg_select_backend || { log_warn "pkg/${target}: no available backend"; return 1; }
  # Per-backend extras.
  _PKG_BIN="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin" 2>/dev/null || true)"
  _PKG_CURL_ARGS="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.curl_args" 2>/dev/null || true)"
  _PKG_GREEDY="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.greedy_auto_updates" 2>/dev/null || true)"
  _PKG_UPDATE_CLASS="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "update_class" 2>/dev/null || true)"
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

_ucc_driver_pkg_recover() {
  local cfg_dir="$1" yaml="$2" target="$3" level="$4"
  _pkg_load_backends "$cfg_dir" "$yaml" "$target"
  _pkg_select_backend || return 1
  local ref="$_PKG_PICKED_REF" backend="$_PKG_PICKED_NAME"
  case "$level" in
    1) # Retry install via selected backend
      local act_fn="_pkg_${backend//-/_}_install"
      declare -f "$act_fn" >/dev/null 2>&1 || return 1
      "$act_fn" "$ref"
      ;;
    2) # Uninstall + reinstall via selected backend
      local ins_fn="_pkg_${backend//-/_}_install"
      declare -f "$ins_fn" >/dev/null 2>&1 || return 1
      # Backend-specific removal before reinstall
      case "$backend" in
        brew)      ucc_run brew uninstall "$ref" 2>/dev/null || true ;;
        brew-cask) ucc_run brew uninstall --cask "$ref" 2>/dev/null || true ;;
        npm)       ucc_run npm uninstall -g "$ref" 2>/dev/null || true ;;
        winget)    local wcmd; wcmd="$(_pkg_winget_cmd)"; ucc_run $wcmd uninstall --id "$ref" --exact --silent 2>/dev/null || true ;;
        *)         ;; # curl/native — no clean uninstall, just re-install over
      esac
      "$ins_fn" "$ref"
      ;;
    *) return 2 ;;  # level not supported
  esac
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
