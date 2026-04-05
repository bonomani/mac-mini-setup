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

# ── Driver interface ───────────────────────────────────────────────────────────

_ucc_driver_package_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local backend ref
  backend="$(_pkg_effective_backend "$cfg_dir" "$yaml" "$target")"

  if [[ "$backend" == "curl" ]]; then
    # curl-installed: check if binary exists
    local bin; bin="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin" 2>/dev/null || true)"
    bin="${bin:-$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")}"
    if command -v "$bin" >/dev/null 2>&1; then
      printf 'installed'
    else
      printf 'absent'
    fi
    return
  fi

  ref="$(_pkg_ref_for_backend "$cfg_dir" "$yaml" "$target" "$backend")"
  [[ -n "$ref" ]] || return 1

  if [[ "$backend" == "brew" ]]; then
    # Delegate to existing brew driver logic
    local cask; cask="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.cask")"
    if [[ "$cask" == "true" ]]; then
      local greedy; greedy="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.greedy_auto_updates")"
      brew_cask_observe "$ref" "$greedy"
    else
      brew_observe "$ref"
    fi
  else
    if _pkg_native_is_installed "$backend" "$ref"; then
      local ver; ver="$(_pkg_native_version "$backend" "$ref")"
      printf '%s' "${ver:-installed}"
    else
      printf 'absent'
    fi
  fi
}

_ucc_driver_package_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local backend ref
  backend="$(_pkg_effective_backend "$cfg_dir" "$yaml" "$target")"

  if [[ "$backend" == "curl" ]]; then
    local url args
    url="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.fallback_install_url")"
    args="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.fallback_install_args" 2>/dev/null || true)"
    [[ -n "$url" ]] || return 1
    case "$action" in
      install) curl -fsSL "$url" | sh ${args:+$args} ;;
      update)
        local update_cmd; update_cmd="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.update_cmd" 2>/dev/null || true)"
        if [[ -n "$update_cmd" ]]; then
          $update_cmd
        else
          curl -fsSL "$url" | sh ${args:+$args}
        fi
        ;;
    esac
    return
  fi

  ref="$(_pkg_ref_for_backend "$cfg_dir" "$yaml" "$target" "$backend")"
  [[ -n "$ref" ]] || return 1

  if [[ "$backend" == "brew" ]]; then
    local cask; cask="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.cask")"
    if [[ "$cask" == "true" ]]; then
      local greedy; greedy="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.greedy_auto_updates")"
      case "$action" in
        install) brew_cask_install "$ref" ;;
        update)  brew_cask_upgrade "$ref" "$greedy" ;;
      esac
    else
      local previous_ref; previous_ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.previous_ref")"
      case "$action" in
        install)
          [[ -n "$previous_ref" ]] && { brew unlink "$previous_ref" 2>/dev/null || true; }
          brew_install "$ref"
          [[ -n "$previous_ref" ]] && ucc_run brew link --overwrite --force "$ref"
          ;;
        update)
          brew_upgrade "$ref"
          [[ -n "$previous_ref" ]] && ucc_run brew link --overwrite --force "$ref"
          ;;
      esac
    fi
  else
    case "$action" in
      install) _pkg_native_install "$backend" "$ref" ;;
      update)  _pkg_native_upgrade "$backend" "$ref" ;;
    esac
  fi
}

_ucc_driver_package_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local backend ref ver
  backend="$(_pkg_effective_backend "$cfg_dir" "$yaml" "$target")"

  if [[ "$backend" == "curl" ]]; then
    local bin; bin="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin" 2>/dev/null || true)"
    bin="${bin:-$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")}"
    ver="$("$bin" --version 2>/dev/null | head -1 | awk '{print $NF}')"
    [[ -n "$ver" ]] && printf 'version=%s  backend=curl' "$ver"
    return
  fi

  ref="$(_pkg_ref_for_backend "$cfg_dir" "$yaml" "$target" "$backend")"
  [[ -n "$ref" ]] || return 1

  if [[ "$backend" == "brew" ]]; then
    local cask; cask="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.cask")"
    if [[ "$cask" == "true" ]]; then
      ver="$(_brew_cask_cached_version "$ref")"
    else
      ver="$(_brew_cached_version "$ref")"
    fi
  else
    ver="$(_pkg_native_version "$backend" "$ref")"
  fi
  [[ -n "$ver" ]] && printf 'version=%s  backend=%s' "$ver" "$backend"
}
