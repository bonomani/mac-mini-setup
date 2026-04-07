#!/usr/bin/env bash
# lib/drivers/package.sh — driver.kind: package
# Platform-aware package meta-driver.
# On macOS: delegates to brew.
# On Linux/WSL2: delegates to the native package manager (apt/dnf/pacman/zypper).
#
# driver.ref:      universal package name (works on brew and most native PMs)
# driver.apt_ref:  override name for Debian/Ubuntu (optional)
# driver.dnf_ref:  override name for Fedora/RHEL (optional)
# driver.pacman_ref: override name for Arch (optional)
# driver.cask:     true for macOS GUI apps (brew --cask)
# driver.greedy_auto_updates: true for cask auto-updates (optional)
# driver.previous_ref: formula to unlink before install (optional, brew only)

# ── Platform detection helpers ─────────────────────────────────────────────────

_pkg_backend() {
  if [[ "${HOST_PLATFORM:-macos}" == "macos" ]]; then
    printf 'brew'
  else
    _pkg_native_backend
  fi
}

# Determine the effective backend for a specific package.
# Priority: native PM → brew fallback → curl fallback
_pkg_effective_backend() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local backend ref
  backend="$(_pkg_backend)"
  if [[ "$backend" != "brew" ]]; then
    ref="$(_pkg_ref_for_backend "$cfg_dir" "$yaml" "$target" "$backend")"
    if ! _pkg_native_can_install "$backend" "$ref" 2>/dev/null; then
      # Try brew
      if command -v brew >/dev/null 2>&1; then
        ref="$(_pkg_ref_for_backend "$cfg_dir" "$yaml" "$target" "brew")"
        if brew list "$ref" >/dev/null 2>&1 || brew info "$ref" >/dev/null 2>&1; then
          printf 'brew'
          return
        fi
      fi
      # Try curl fallback
      local _fallback; _fallback="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.fallback_install_url" 2>/dev/null || true)"
      if [[ -n "$_fallback" ]]; then
        printf 'curl'
        return
      fi
    fi
  else
    # On brew — check if formula exists, fall back to curl if not
    ref="$(_pkg_ref_for_backend "$cfg_dir" "$yaml" "$target" "brew")"
    if ! brew list "$ref" >/dev/null 2>&1 && ! brew info "$ref" >/dev/null 2>&1; then
      local _fallback; _fallback="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.fallback_install_url" 2>/dev/null || true)"
      if [[ -n "$_fallback" ]]; then
        printf 'curl'
        return
      fi
    fi
  fi
  printf '%s' "$backend"
}

_pkg_native_backend() {
  if command -v apt-get >/dev/null 2>&1; then
    printf 'apt'
  elif command -v dnf >/dev/null 2>&1; then
    printf 'dnf'
  elif command -v pacman >/dev/null 2>&1; then
    printf 'pacman'
  elif command -v zypper >/dev/null 2>&1; then
    printf 'zypper'
  elif command -v brew >/dev/null 2>&1; then
    printf 'brew'
  else
    printf 'unknown'
  fi
}

_pkg_ref_for_backend() {
  local cfg_dir="$1" yaml="$2" target="$3" backend="$4"
  local ref override_key override
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  case "$backend" in
    apt)    override_key="driver.apt_ref" ;;
    dnf)    override_key="driver.dnf_ref" ;;
    pacman) override_key="driver.pacman_ref" ;;
    *)      printf '%s' "$ref"; return ;;
  esac
  override="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "$override_key" 2>/dev/null)"
  printf '%s' "${override:-$ref}"
}

# ── Native package manager operations ──────────────────────────────────────────

_pkg_native_can_install() {
  local backend="$1" pkg="$2"
  case "$backend" in
    apt)    apt-cache show "$pkg" >/dev/null 2>&1 ;;
    dnf)    dnf info "$pkg" >/dev/null 2>&1 ;;
    pacman) pacman -Si "$pkg" >/dev/null 2>&1 ;;
    zypper) zypper info "$pkg" >/dev/null 2>&1 ;;
    *)      return 1 ;;
  esac
}

_pkg_native_is_installed() {
  local backend="$1" pkg="$2"
  case "$backend" in
    apt)    dpkg -s "$pkg" >/dev/null 2>&1 ;;
    dnf)    rpm -q "$pkg" >/dev/null 2>&1 ;;
    pacman) pacman -Qi "$pkg" >/dev/null 2>&1 ;;
    zypper) rpm -q "$pkg" >/dev/null 2>&1 ;;
    *)      return 1 ;;
  esac
}

_pkg_native_version() {
  local backend="$1" pkg="$2"
  case "$backend" in
    apt)    dpkg -s "$pkg" 2>/dev/null | awk '/^Version:/{print $2}' ;;
    dnf)    rpm -q --qf '%{VERSION}' "$pkg" 2>/dev/null ;;
    pacman) pacman -Qi "$pkg" 2>/dev/null | awk '/^Version/{print $3}' ;;
    zypper) rpm -q --qf '%{VERSION}' "$pkg" 2>/dev/null ;;
  esac
}

_pkg_native_install() {
  local backend="$1" pkg="$2"
  if sudo_not_available; then
    log_warn "Installing '$pkg' via $backend requires sudo — run: sudo -v"
    return 1
  fi
  case "$backend" in
    apt)    ucc_run run_elevated apt-get install -y "$pkg" ;;
    dnf)    ucc_run run_elevated dnf install -y "$pkg" ;;
    pacman) ucc_run run_elevated pacman -S --noconfirm "$pkg" ;;
    zypper) ucc_run run_elevated zypper install -y "$pkg" ;;
    *)      log_warn "Unknown package backend '$backend'"; return 1 ;;
  esac
}

_pkg_native_upgrade() {
  local backend="$1" pkg="$2"
  if sudo_not_available; then
    log_warn "Upgrading '$pkg' via $backend requires sudo — run: sudo -v"
    return 1
  fi
  case "$backend" in
    apt)    ucc_run run_elevated apt-get install --only-upgrade -y "$pkg" ;;
    dnf)    ucc_run run_elevated dnf upgrade -y "$pkg" ;;
    pacman) ucc_run run_elevated pacman -S --noconfirm "$pkg" ;;
    zypper) ucc_run run_elevated zypper update -y "$pkg" ;;
    *)      log_warn "Unknown package backend '$backend'"; return 1 ;;
  esac
}

# ── Per-PM outdated detection (used by pkg native-pm backend) ────────────────
# Cache populated lazily on first call. Each backend has its own cache var.
# Gated on UIC_PREF_BREW_LIVECHECK=1 (network call, can be slow).
_pkg_native_outdated_cache_load() {
  local backend="$1"
  [[ "${UIC_PREF_BREW_LIVECHECK:-0}" == "1" ]] || return 1
  case "$backend" in
    apt)
      [[ -n "${_PKG_APT_OUTDATED_CACHE+x}" ]] && return 0
      export _PKG_APT_OUTDATED_CACHE
      _PKG_APT_OUTDATED_CACHE="$(apt list --upgradable 2>/dev/null \
        | awk -F'/' 'NR>1 && $1!=""{print $1}' || true)"
      ;;
    dnf)
      [[ -n "${_PKG_DNF_OUTDATED_CACHE+x}" ]] && return 0
      export _PKG_DNF_OUTDATED_CACHE
      _PKG_DNF_OUTDATED_CACHE="$(dnf check-update --quiet 2>/dev/null \
        | awk 'NF>=3 && $1 !~ /^(Last|Obsoleting)/{print $1}' || true)"
      ;;
    pacman)
      [[ -n "${_PKG_PACMAN_OUTDATED_CACHE+x}" ]] && return 0
      export _PKG_PACMAN_OUTDATED_CACHE
      _PKG_PACMAN_OUTDATED_CACHE="$(pacman -Qu 2>/dev/null \
        | awk '{print $1}' || true)"
      ;;
    zypper)
      [[ -n "${_PKG_ZYPPER_OUTDATED_CACHE+x}" ]] && return 0
      export _PKG_ZYPPER_OUTDATED_CACHE
      _PKG_ZYPPER_OUTDATED_CACHE="$(zypper -n list-updates 2>/dev/null \
        | awk -F'|' 'NR>4 && $3!=""{gsub(/ /,"",$3); print $3}' || true)"
      ;;
    *) return 1 ;;
  esac
}

# Return 0 if <pkg> is in <backend>'s outdated cache.
_pkg_native_is_outdated() {
  local backend="$1" pkg="$2"
  _pkg_native_outdated_cache_load "$backend" || return 1
  local cache_var
  case "$backend" in
    apt)    cache_var=_PKG_APT_OUTDATED_CACHE ;;
    dnf)    cache_var=_PKG_DNF_OUTDATED_CACHE ;;
    pacman) cache_var=_PKG_PACMAN_OUTDATED_CACHE ;;
    zypper) cache_var=_PKG_ZYPPER_OUTDATED_CACHE ;;
    *)      return 1 ;;
  esac
  printf '%s\n' "${!cache_var}" | grep -qxF "$pkg"
}

