#!/usr/bin/env bash
# lib/drivers/pkg_github.sh — github-release backend for the pkg driver.
#
# Extracted from lib/drivers/pkg.sh on 2026-04-28 (PLAN refactor #3, first
# slice). Sourced from lib/drivers/pkg.sh before backend dispatch runs.
# Mechanical move — no behavior change.

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

# Per-process cache of GitHub latest release tag. Shared across pkg
# backends and across drivers (custom_daemon, nvm) via `declare -f` probe.
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
