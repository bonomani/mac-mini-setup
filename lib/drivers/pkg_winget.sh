#!/usr/bin/env bash
# lib/drivers/pkg_winget.sh — Windows Package Manager backend (Win10/11 + WSL2 interop).
# Extracted from lib/drivers/pkg.sh on 2026-04-28 (PLAN refactor #3, slice 6).

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
    # winget rc=20 (and locale-translated "no package matches" output) ⇒ not
    # available on this host's configured sources. Treat as policy/availability
    # rather than fail so the run summary reflects "skip" not FAILED.
    # Skip the raw-output dump in this case — emitting localized strings
    # like "Aucun package ne correspond..." plus winget's TTY progress
    # indicator (which doesn't render in captured form) is just noise.
    # The clean log_warn below carries all the useful info.
    if [[ $rc -eq 20 ]] || printf '%s' "$out" | grep -qiE 'no package|aucun package|kein paket|nessun pacchetto|ningún paquete|没有'; then
      log_warn "winget: package '$1' not found in configured sources — treating as unavailable (admin required to add source)"
      return 125
    fi
    # Genuine failure — dump captured output for diagnostics
    printf '%s\n' "$out" >&2
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
    if [[ $rc -eq 20 ]] || printf '%s' "$out" | grep -qiE 'no package|aucun package|kein paket|nessun pacchetto|ningún paquete|没有'; then
      log_warn "winget: package '$1' not found in configured sources — treating as unavailable"
      return 125
    fi
    printf '%s\n' "$out" >&2
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
