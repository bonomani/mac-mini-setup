#!/usr/bin/env bash
# lib/drivers/build_deps.sh — driver.kind: build-deps
# Installs native build dependencies for compiling Python, etc.
# Detects the Linux distro and uses the appropriate package manager.

_build_deps_distro_family() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}${ID_LIKE:-}" in
      *debian*|*ubuntu*) printf 'debian' ;;
      *fedora*|*rhel*)   printf 'fedora' ;;
      *arch*)            printf 'arch' ;;
      *suse*)            printf 'suse' ;;
      *)                 printf 'unknown' ;;
    esac
  else
    printf 'unknown'
  fi
}

_build_deps_install_cmd() {
  local family="$1"
  case "$family" in
    debian) printf 'sudo apt-get install -y' ;;
    fedora) printf 'sudo dnf install -y' ;;
    arch)   printf 'sudo pacman -S --noconfirm' ;;
    suse)   printf 'sudo zypper install -y' ;;
    *)      return 1 ;;
  esac
}

_build_deps_packages() {
  local family="$1"
  case "$family" in
    debian)
      printf 'build-essential curl file git libssl-dev libffi-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev liblzma-dev libncurses-dev tk-dev'
      ;;
    fedora)
      printf 'gcc make curl file git openssl-devel libffi-devel zlib-devel bzip2-devel readline-devel sqlite-devel xz-devel ncurses-devel tk-devel'
      ;;
    arch)
      printf 'base-devel curl file git openssl libffi zlib bzip2 readline sqlite xz ncurses tk'
      ;;
    suse)
      printf 'gcc make curl file git libopenssl-devel libffi-devel zlib-devel libbz2-devel readline-devel sqlite3-devel xz-devel ncurses-devel tk-devel'
      ;;
    *)
      return 1
      ;;
  esac
}

_ucc_driver_build_deps_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  # On macOS, Xcode CLT provides build tools — not needed
  [[ "${HOST_PLATFORM:-macos}" != "macos" ]] || { printf 'not-applicable'; return; }
  # Check if gcc/make are available as a proxy for build deps
  if command -v gcc >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
    printf 'installed'
  else
    printf 'absent'
  fi
}

_ucc_driver_build_deps_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  [[ "${HOST_PLATFORM:-macos}" != "macos" ]] || return 0
  local family install_cmd packages
  family="$(_build_deps_distro_family)"
  install_cmd="$(_build_deps_install_cmd "$family")" || {
    log_warn "build-deps: unsupported distro family '$family' — install build tools manually"
    return 1
  }
  packages="$(_build_deps_packages "$family")" || return 1
  # Native package managers require sudo
  if sudo_not_available; then
    log_warn "build-deps: sudo required for $family package manager — run: sudo -v"
    return 1
  fi
  log_info "Installing build dependencies via $family package manager..."
  # shellcheck disable=SC2086
  ucc_run $install_cmd $packages
}

_ucc_driver_build_deps_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  [[ "${HOST_PLATFORM:-macos}" != "macos" ]] || { printf 'platform=macOS (xcode-clt)'; return; }
  local family
  family="$(_build_deps_distro_family)"
  local gcc_ver; gcc_ver="$(gcc --version 2>/dev/null | head -1 || echo 'absent')"
  printf 'distro=%s  gcc=%s' "$family" "$gcc_ver"
}
