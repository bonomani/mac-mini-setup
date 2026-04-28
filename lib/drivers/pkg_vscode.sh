#!/usr/bin/env bash
# lib/drivers/pkg_vscode.sh — vscode-marketplace backend.
# Extracted from lib/drivers/pkg.sh on 2026-04-28 (PLAN refactor #3, slice 9).

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
