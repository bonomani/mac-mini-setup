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

# github-release: download a CLI binary or tarball asset from a GitHub release.
# YAML shape (the value is a dict, encoded by the parser as "json:<base64>"):
#   backends:
#   - github:
#       repo: sigstore/cosign                  # required
#       asset: cosign-{os}-{arch_alt}          # optional; default: <bin>-<os>-<arch>
#       extract: binary|tar|tar.gz|tar.xz|tar.bz2|zip   # default: binary
#       bin_path_in_archive: <relpath>         # optional; for tar/zip extracts
#     bin: cosign                              # required (driver.bin)
# Templating placeholders: {version} (tag without leading v), {tag} (raw),
#   {os} (linux|darwin), {arch} (x86_64|aarch64), {arch_alt} (amd64|arm64).
# Install dir: $UCC_GITHUB_BIN_DIR (default $HOME/bin).
# Version sidecar: $UCC_GITHUB_STATE_DIR/<bin>.version (default $HOME/.local/state/ucc/github-releases).
_pkg_github_decode() {
  local ref="$1"
  if [[ "$ref" == json:* ]]; then
    printf '%s' "${ref#json:}" | base64 -d 2>/dev/null
  else
    printf '{"repo":"%s"}' "$ref"
  fi
}
_pkg_github_field() {
  printf '%s' "$1" | python3 -c "
import sys, json
try: d = json.load(sys.stdin)
except Exception: d = {}
print(d.get('$2', ''))
" 2>/dev/null
}
_pkg_github_os()       { case "$(uname -s)" in Linux) printf 'linux' ;; Darwin) printf 'darwin' ;; *) uname -s | tr '[:upper:]' '[:lower:]' ;; esac; }
_pkg_github_arch()     { case "$(uname -m)" in x86_64|amd64) printf 'x86_64' ;; aarch64|arm64) printf 'aarch64' ;; *) uname -m ;; esac; }
_pkg_github_arch_alt() { case "$(uname -m)" in x86_64|amd64) printf 'amd64' ;; aarch64|arm64) printf 'arm64' ;; *) uname -m ;; esac; }
_pkg_github_bin_dir()  { local d="${UCC_GITHUB_BIN_DIR:-$HOME/bin}"; mkdir -p "$d"; printf '%s' "$d"; }
_pkg_github_state_dir(){ local d="${UCC_GITHUB_STATE_DIR:-$HOME/.local/state/ucc/github-releases}"; mkdir -p "$d"; printf '%s' "$d"; }
_pkg_github_template() {
  local s="$1" version="$2" tag="$3" os="$4" arch="$5" arch_alt="$6"
  s="${s//\{version\}/$version}"
  s="${s//\{tag\}/$tag}"
  s="${s//\{os\}/$os}"
  s="${s//\{arch\}/$arch}"
  s="${s//\{arch_alt\}/$arch_alt}"
  printf '%s' "$s"
}
_pkg_github_available() { command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; }
_pkg_github_activate()  { :; }
_pkg_github_observe() {
  local ref="$1" bin="${_PKG_BIN:-}" v
  [[ -n "$bin" ]] || { printf 'absent'; return; }
  v="$(cat "$(_pkg_github_state_dir)/${bin}.version" 2>/dev/null || true)"
  [[ -z "$v" ]] && { printf 'absent'; return; }
  if [[ "${UIC_PREF_UPSTREAM_CHECK:-0}" == "1" ]]; then
    local repo latest
    repo="$(_pkg_github_field "$(_pkg_github_decode "$ref")" repo)"
    if [[ -n "$repo" ]]; then
      latest="$(_pkg_github_latest_tag "$repo" 2>/dev/null || true)"
      if [[ -n "$latest" ]] && _pkg_version_lt "$v" "$latest"; then
        printf 'outdated'; return
      fi
    fi
  fi
  printf '%s' "$v"
}
_pkg_github_install() {
  local ref="$1" bin="${_PKG_BIN:-}"
  [[ -n "$bin" ]] || { log_warn "github: driver.bin required"; return 1; }
  local cfg; cfg="$(_pkg_github_decode "$ref")"
  local repo asset_tpl extract bin_path
  repo="$(_pkg_github_field "$cfg" repo)"
  asset_tpl="$(_pkg_github_field "$cfg" asset)"
  extract="$(_pkg_github_field "$cfg" extract)"
  bin_path="$(_pkg_github_field "$cfg" bin_path_in_archive)"
  [[ -n "$repo" ]] || { log_warn "github: repo required"; return 1; }
  [[ -n "$extract" ]] || extract="binary"

  local tag version os arch arch_alt
  tag="$(curl -fsS --max-time "$(_ucc_curl_timeout probe)" \
    "$(_ucc_github_api_url "repos/${repo}/releases/latest")" 2>/dev/null \
    | awk -F'"' '/"tag_name"/{print $4; exit}')"
  [[ -n "$tag" ]] || { log_warn "github ${repo}: failed to fetch latest tag"; return 1; }
  version="${tag#v}"
  os="$(_pkg_github_os)"
  arch="$(_pkg_github_arch)"
  arch_alt="$(_pkg_github_arch_alt)"
  [[ -n "$asset_tpl" ]] || asset_tpl="${bin}-${os}-${arch}"

  local asset url tmp
  asset="$(_pkg_github_template "$asset_tpl" "$version" "$tag" "$os" "$arch" "$arch_alt")"
  url="$(_ucc_github_web_url "${repo}/releases/download/${tag}/${asset}")"
  tmp="$(mktemp -d)"
  log_info "github ${repo}: downloading ${asset} (tag=${tag})"
  if ! ucc_run curl -fsSL --max-time "$(_ucc_curl_timeout download)" -o "$tmp/$asset" "$url"; then
    rm -rf "$tmp"; return 1
  fi

  local final_bin src
  final_bin="$(_pkg_github_bin_dir)/$bin"
  case "$extract" in
    binary)
      ucc_run mv -f "$tmp/$asset" "$final_bin" || { rm -rf "$tmp"; return 1; }
      ucc_run chmod +x "$final_bin"
      ;;
    tar|tar.gz|tar.xz|tar.bz2)
      (cd "$tmp" && ucc_run tar -xf "$asset") || { rm -rf "$tmp"; return 1; }
      if [[ -n "$bin_path" ]]; then
        src="$tmp/$(_pkg_github_template "$bin_path" "$version" "$tag" "$os" "$arch" "$arch_alt")"
      else
        src="$(find "$tmp" -type f -name "$bin" -perm -u+x 2>/dev/null | head -1)"
      fi
      [[ -f "$src" ]] || { log_warn "github ${repo}: ${bin} not found in archive"; rm -rf "$tmp"; return 1; }
      ucc_run mv -f "$src" "$final_bin" || { rm -rf "$tmp"; return 1; }
      ucc_run chmod +x "$final_bin"
      ;;
    zip)
      command -v unzip >/dev/null 2>&1 || { log_warn "github ${repo}: unzip not available"; rm -rf "$tmp"; return 1; }
      (cd "$tmp" && ucc_run unzip -q "$asset") || { rm -rf "$tmp"; return 1; }
      if [[ -n "$bin_path" ]]; then
        src="$tmp/$(_pkg_github_template "$bin_path" "$version" "$tag" "$os" "$arch" "$arch_alt")"
      else
        src="$(find "$tmp" -type f -name "$bin" 2>/dev/null | head -1)"
      fi
      [[ -f "$src" ]] || { log_warn "github ${repo}: ${bin} not found in zip"; rm -rf "$tmp"; return 1; }
      ucc_run mv -f "$src" "$final_bin" || { rm -rf "$tmp"; return 1; }
      ucc_run chmod +x "$final_bin"
      ;;
    *)
      log_warn "github ${repo}: unknown extract mode '${extract}'"
      rm -rf "$tmp"; return 1
      ;;
  esac
  printf '%s\n' "$version" > "$(_pkg_github_state_dir)/${bin}.version"
  rm -rf "$tmp"
}
_pkg_github_update()   { _pkg_github_install "$@"; }
_pkg_github_version()  { cat "$(_pkg_github_state_dir)/${_PKG_BIN:-_}.version" 2>/dev/null || true; }
_pkg_github_outdated() { return 1; }

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
  local tag; tag="$(curl -fsS --max-time "$(_ucc_curl_timeout probe)" "$(_ucc_github_api_url "repos/${repo}/releases/latest")" 2>/dev/null \
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
  # `winget list` writes "no match" diagnostics to stdout (not stderr), so we
  # must filter both streams to avoid leaking localized status into the run log.
  ver="$($wcmd list --id "$ref" --exact --accept-source-agreements 2>/dev/null \
    | grep -vE 'No package|Aucun package|Kein Paket|Nessun pacchetto|Ningún paquete|没有' \
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
  local out rc
  out="$(ucc_run $wcmd install --id "$1" --exact --accept-source-agreements --accept-package-agreements --silent 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    printf '%s\n' "$out" >&2
    # winget rc=20 (and locale-translated "no package matches" output) ⇒ not
    # available on this host's configured sources. Treat as policy/availability
    # rather than fail so the run summary reflects "skip" not FAILED.
    if [[ $rc -eq 20 ]] || printf '%s' "$out" | grep -qiE 'no package|aucun package|kein paket|nessun pacchetto|ningún paquete|没有'; then
      log_warn "winget: package '$1' not found in configured sources — treating as unavailable (admin required to add source)"
      return 125
    fi
    return 1
  fi
  printf '%s\n' "$out"
}
_pkg_winget_update() {
  local wcmd; wcmd="$(_pkg_winget_cmd)"
  local out rc
  out="$(ucc_run $wcmd upgrade --id "$1" --exact --accept-source-agreements --accept-package-agreements --silent 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    printf '%s\n' "$out" >&2
    if [[ $rc -eq 20 ]] || printf '%s' "$out" | grep -qiE 'no package|aucun package|kein paket|nessun pacchetto|ningún paquete|没有'; then
      log_warn "winget: package '$1' not found in configured sources — treating as unavailable"
      return 125
    fi
    return 1
  fi
  printf '%s\n' "$out"
}
_pkg_winget_version() {
  local ref="$1" wcmd
  wcmd="$(_pkg_winget_cmd)"
  $wcmd list --id "$ref" --exact --accept-source-agreements 2>/dev/null \
    | grep -vE 'No package|Aucun package|Kein Paket|Nessun pacchetto|Ningún paquete|没有' \
    | tail -n +2 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\./) {print $i; exit}}'
}
_pkg_winget_outdated() {
  [[ "${UIC_PREF_UPSTREAM_CHECK:-0}" == "1" ]] || return 1
  local ref="$1" wcmd
  wcmd="$(_pkg_winget_cmd)"
  $wcmd upgrade --id "$ref" --exact --accept-source-agreements 2>/dev/null \
    | grep -vE 'No package|Aucun package|Kein Paket|Nessun pacchetto|Ningún paquete|没有' \
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
