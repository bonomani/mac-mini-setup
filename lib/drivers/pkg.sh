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
_pkg_brew_observe()   { brew_observe "$1" "${_PKG_UPDATE_CLASS:-tool}"; }
_pkg_brew_install()   { brew_install "$1"; }
_pkg_brew_update()    { brew_upgrade "$1"; }
_pkg_brew_version()   { _brew_cached_version "$1"; }
# Outdated detection: piggyback on brew_observe (returns "outdated" when
# brew outdated flags it; UIC_PREF_UPSTREAM_CHECK=1 catches formula lag).
_pkg_brew_outdated()  { [[ "$(brew_observe "$1" "${_PKG_UPDATE_CLASS:-tool}")" == "outdated" ]]; }

# npm-global
# Split "<name>[@<version>]" honoring scoped names (@scope/name[@version]).
_pkg_npm_split_ref() {
  local ref="$1" name version=""
  if [[ "$ref" == @*/*@* ]]; then
    name="${ref%@*}"; version="${ref##*@}"
  elif [[ "$ref" != @* && "$ref" == *@* ]]; then
    name="${ref%@*}"; version="${ref##*@}"
  else
    name="$ref"
  fi
  printf '%s\t%s' "$name" "$version"
}
_pkg_npm_name()    { local s; s="$(_pkg_npm_split_ref "$1")"; printf '%s' "${s%$'\t'*}"; }
_pkg_npm_pinned()  { local s; s="$(_pkg_npm_split_ref "$1")"; printf '%s' "${s#*$'\t'}"; }
_pkg_npm_available()  { _npm_ensure_path; }
_pkg_npm_activate()   { _npm_ensure_path; }
_pkg_npm_observe()    {
  local ref="$1" name pin v
  name="$(_pkg_npm_name "$ref")"
  pin="$(_pkg_npm_pinned "$ref")"
  v="$(npm_global_version "$name")"
  [[ -z "$v" ]] && { printf 'absent'; return; }
  if [[ -n "$pin" ]]; then
    [[ "$v" == "$pin" ]] && { printf '%s' "$v"; return; }
    printf 'outdated'; return
  fi
  local policy="${UIC_PREF_TOOL_UPDATE:-always-upgrade}"
  [[ "${_PKG_UPDATE_CLASS:-tool}" == "lib" ]] && policy="${UIC_PREF_LIB_UPDATE:-install-only}"
  if [[ "$policy" == "always-upgrade" ]] && _pkg_npm_outdated "$name"; then
    printf 'outdated'
  else
    printf '%s' "$v"
  fi
}
_pkg_npm_install()    { npm_global_install "$1"; }
# Version-pinned updates are sensitive (may downgrade): require interactive
# mode. Unpinned refs follow the usual `npm update -g` path.
_pkg_npm_update()     {
  local ref="$1" name pin cur
  name="$(_pkg_npm_name "$ref")"
  pin="$(_pkg_npm_pinned "$ref")"
  if [[ -n "$pin" ]]; then
    cur="$(npm_global_version "$name")"
    if [[ "${UCC_INTERACTIVE:-0}" != "1" ]]; then
      log_warn "npm-global ${name}: pinned to ${pin} but currently ${cur:-absent}; skipping (re-run with --interactive to apply pin)"
      return 0
    fi
    npm_global_install "$ref"
    return $?
  fi
  npm_global_update "$name"
}
_pkg_npm_version()    { npm_global_version "$(_pkg_npm_name "$1")"; }
# Cache `npm outdated -g --json` once per process; opt-in via the brew
# livecheck flag (same trade-off — slow network call).
_pkg_npm_outdated() {
  [[ "${UIC_PREF_UPSTREAM_CHECK:-0}" == "1" ]] || return 1
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

# curl (script installer fallback). Presence by default; outdated detection
# is opt-in via driver.github_repo + UIC_PREF_UPSTREAM_CHECK=1.
_pkg_curl_available() { command -v curl >/dev/null 2>&1; }
_pkg_curl_activate()  { :; }
_pkg_curl_observe()   {
  local bin="${_PKG_BIN:-}"
  [[ -n "$bin" ]] || return 1
  command -v "$bin" >/dev/null 2>&1 || { printf 'absent'; return; }
  if _pkg_curl_outdated; then
    printf 'outdated'
  else
    printf 'installed'
  fi
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
_pkg_curl_version() {
  local bin="${_PKG_BIN:-}"
  [[ -n "$bin" ]] || return 0
  "$bin" --version 2>/dev/null | head -1 | _ucc_parse_version
}
# True (0) if upstream GitHub release is strictly newer than installed binary.
# Gated on UIC_PREF_UPSTREAM_CHECK=1 (network call). Reads driver.github_repo
# from _PKG_GITHUB_REPO stashed by the dispatcher.
_pkg_curl_outdated() {
  [[ "${UIC_PREF_UPSTREAM_CHECK:-0}" == "1" ]] || return 1
  [[ -n "${_PKG_GITHUB_REPO:-}" ]] || return 1
  local installed latest
  installed="$(_pkg_curl_version)"
  [[ -n "$installed" ]] || return 1
  latest="$(_pkg_github_latest_tag "$_PKG_GITHUB_REPO")"
  [[ -n "$latest" ]] || return 1
  _pkg_version_lt "$installed" "$latest"
}

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

# Per-process cache of GitHub latest release tag, shared across pkg backends.
# Cache format: lines of "<repo>\t<tag>"; "-" tag means "lookup failed".
_pkg_github_latest_tag() {
  local repo="$1"
  [[ -n "$repo" ]] || return 1
  local cached
  cached="$(printf '%s\n' "${_PKG_GH_TAG_CACHE:-}" \
    | awk -F'\t' -v r="$repo" '$1==r{print $2; exit}')"
  if [[ -n "$cached" ]]; then
    [[ "$cached" == "-" ]] && return 1
    printf '%s' "$cached"
    return 0
  fi
  local tag; tag="$(curl -fsS --max-time "$(_ucc_curl_timeout probe)" "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
    | awk -F'"' '/"tag_name"/{print $4}' | sed 's/^v//')"
  if [[ -z "$tag" ]]; then
    export _PKG_GH_TAG_CACHE="${_PKG_GH_TAG_CACHE:+${_PKG_GH_TAG_CACHE}
}${repo}	-"
    return 1
  fi
  export _PKG_GH_TAG_CACHE="${_PKG_GH_TAG_CACHE:+${_PKG_GH_TAG_CACHE}
}${repo}	${tag}"
  printf '%s' "$tag"
}

# brew-cask: macOS GUI apps via Homebrew Cask. Greedy mode (auto-update casks)
# is opt-in via driver.greedy_auto_updates: true at the YAML level.
_pkg_brew_cask_available() { command -v brew >/dev/null 2>&1; }
_pkg_brew_cask_activate()  { :; }
_pkg_brew_cask_observe()   {
  brew_cask_observe "$1" "${_PKG_GREEDY:-false}" "${_PKG_UPDATE_CLASS:-tool}"
}
_pkg_brew_cask_install()   { brew_cask_install "$1"; }
_pkg_brew_cask_update()    { brew_cask_upgrade "$1" "${_PKG_GREEDY:-false}"; }
_pkg_brew_cask_version()   { _brew_cask_cached_version "$1"; }
_pkg_brew_cask_outdated()  { [[ "$(brew_cask_observe "$1" "${_PKG_GREEDY:-false}" "${_PKG_UPDATE_CLASS:-tool}")" == "outdated" ]]; }

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
  if ! _pkg_native_is_installed "$be" "$ref"; then
    printf 'absent'
    return
  fi
  if _pkg_native_is_outdated "$be" "$ref"; then
    printf 'outdated'
    return
  fi
  ver="$(_pkg_native_version "$be" "$ref")"
  printf '%s' "${ver:-installed}"
}
_pkg_native_pm_install()  { _pkg_native_install "$(_pkg_native_backend)" "$1"; }
_pkg_native_pm_update()   { _pkg_native_upgrade "$(_pkg_native_backend)" "$1"; }
_pkg_native_pm_version()  { _pkg_native_version "$(_pkg_native_backend)" "$1"; }
_pkg_native_pm_outdated() { _pkg_native_is_outdated "$(_pkg_native_backend)" "$1"; }

# winget: Windows Package Manager. Available on Windows 10/11 and WSL2 via
# interop (winget.exe). Ref is the winget package ID (e.g. aria2.aria2).
_pkg_winget_available() {
  command -v winget >/dev/null 2>&1 || command -v winget.exe >/dev/null 2>&1
}
_pkg_winget_activate() { :; }
_pkg_winget_cmd() {
  if command -v winget >/dev/null 2>&1; then
    echo "winget"
  else
    echo "winget.exe"
  fi
}
_pkg_winget_observe() {
  local ref="$1" wcmd ver
  wcmd="$(_pkg_winget_cmd)"
  ver="$($wcmd list --id "$ref" --exact --accept-source-agreements 2>/dev/null \
    | tail -n +2 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\./) {print $i; exit}}')"
  if [[ -z "$ver" ]]; then
    printf 'absent'
    return
  fi
  if _pkg_winget_outdated "$ref"; then
    printf 'outdated'
  else
    printf '%s' "$ver"
  fi
}
_pkg_winget_install() {
  local wcmd; wcmd="$(_pkg_winget_cmd)"
  ucc_run $wcmd install --id "$1" --exact --accept-source-agreements --accept-package-agreements --silent
}
_pkg_winget_update() {
  local wcmd; wcmd="$(_pkg_winget_cmd)"
  ucc_run $wcmd upgrade --id "$1" --exact --accept-source-agreements --accept-package-agreements --silent
}
_pkg_winget_version() {
  local ref="$1" wcmd
  wcmd="$(_pkg_winget_cmd)"
  $wcmd list --id "$ref" --exact --accept-source-agreements 2>/dev/null \
    | tail -n +2 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\./) {print $i; exit}}'
}
_pkg_winget_outdated() {
  [[ "${UIC_PREF_UPSTREAM_CHECK:-0}" == "1" ]] || return 1
  local ref="$1" wcmd
  wcmd="$(_pkg_winget_cmd)"
  $wcmd upgrade --id "$ref" --exact --accept-source-agreements 2>/dev/null \
    | grep -qi "$ref"
}

# pyenv-version
_pyenv_ensure_path() {
  command -v pyenv >/dev/null 2>&1 || {
    [[ -x "$HOME/.pyenv/bin/pyenv" ]] || return 1
    export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
    PATH="$PYENV_ROOT/bin:$PATH"
  }
  export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
  case ":$PATH:" in *":$PYENV_ROOT/shims:"*) ;; *) PATH="$PYENV_ROOT/shims:$PATH" ;; esac
  export PATH
  eval "$(pyenv init - bash 2>/dev/null)" 2>/dev/null || true
  command -v pyenv >/dev/null 2>&1
}
_pkg_pyenv_available() { _pyenv_ensure_path; }
_pkg_pyenv_activate()  { _pyenv_ensure_path; }
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
  [[ -z "$v" ]] && { printf 'absent'; return; }
  if _pkg_vscode_outdated "$id"; then
    printf 'outdated'
  else
    printf '%s' "$v"
  fi
}
_pkg_vscode_install()   { vscode_extension_install "$1"; }
_pkg_vscode_update()    { vscode_extension_update  "$1"; }
_pkg_vscode_version()   { _vscode_extension_cached_version "$1"; }

# Per-process cache: lines of "<extension_id>\t<latest_version>".
# Built lazily by querying the VS Code marketplace once for all installed
# extensions. Gated on UIC_PREF_UPSTREAM_CHECK=1 (network call).
_pkg_vscode_outdated_cache_load() {
  [[ "${UIC_PREF_UPSTREAM_CHECK:-0}" == "1" ]] || return 1
  [[ -n "${_PKG_VSCODE_LATEST_CACHE+x}" ]] && return 0
  export _PKG_VSCODE_LATEST_CACHE=""
  command -v code >/dev/null 2>&1 || return 1
  local installed
  installed="$(code --list-extensions 2>/dev/null)"
  [[ -n "$installed" ]] || return 1
  local body
  body="$(python3 - <<PY
import json, sys
ids = """${installed}""".strip().splitlines()
filters = [{"criteria": [{"filterType": 7, "value": i} for i in ids],
            "pageNumber": 1, "pageSize": len(ids), "sortBy": 0, "sortOrder": 0}]
print(json.dumps({"filters": filters, "flags": 0x192}))
PY
)"
  local resp
  resp="$(curl -fsS --max-time "$(_ucc_curl_timeout endpoint)" \
    -H 'Accept: application/json;api-version=3.0-preview.1' \
    -H 'Content-Type: application/json' \
    -X POST "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery" \
    -d "$body" 2>/dev/null)"
  [[ -n "$resp" ]] || return 1
  _PKG_VSCODE_LATEST_CACHE="$(printf '%s' "$resp" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
results = (d.get('results') or [{}])[0].get('extensions') or []
for ext in results:
    pub = (ext.get('publisher') or {}).get('publisherName', '')
    name = ext.get('extensionName', '')
    versions = ext.get('versions') or []
    if not versions: continue
    latest = versions[0].get('version', '')
    if pub and name and latest:
        print(f'{pub}.{name}\t{latest}')
" 2>/dev/null || true)"
  export _PKG_VSCODE_LATEST_CACHE
  return 0
}

_pkg_vscode_outdated() {
  [[ "${UIC_PREF_UPSTREAM_CHECK:-0}" == "1" ]] || return 1
  local id="$1"
  [[ -n "$id" ]] || return 1
  _pkg_vscode_outdated_cache_load || return 1
  [[ -n "$_PKG_VSCODE_LATEST_CACHE" ]] || return 1
  local latest installed
  latest="$(printf '%s\n' "$_PKG_VSCODE_LATEST_CACHE" \
    | awk -F'\t' -v i="$id" 'tolower($1)==tolower(i){print $2; exit}')"
  [[ -n "$latest" ]] || return 1
  installed="$(_vscode_extension_cached_version "$id" 2>/dev/null || true)"
  [[ -n "$installed" ]] || return 1
  _pkg_version_lt "$installed" "$latest"
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
