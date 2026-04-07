#!/usr/bin/env bash
# lib/drivers/pip.sh — driver.kind: pip
# driver.probe_pkg:       primary package to probe for presence/version
# driver.install_packages: space-separated list of packages to install/upgrade
# driver.min_version:     minimum required version (empty = no constraint)

# Ensure pip + python are on PATH for non-interactive subshells.
# Falls back to the pyenv-managed interpreter when pyenv is set up.
_pip_ensure_path() {
  if command -v pip >/dev/null 2>&1; then
    return 0
  fi
  declare -f _pyenv_ensure_path >/dev/null 2>&1 && _pyenv_ensure_path 2>/dev/null || true
  command -v pip >/dev/null 2>&1 && return 0
  command -v python3 >/dev/null 2>&1 || return 1
  return 0  # python3 -m pip is the fallback path
}

# Cache `pip list --outdated --format=json` once per process; opt-in via
# UIC_PREF_BREW_LIVECHECK=1 (network call, can be slow on big environments).
_pip_outdated_cache_load() {
  [[ "${UIC_PREF_BREW_LIVECHECK:-0}" == "1" ]] || return 1
  [[ -n "${_PIP_OUTDATED_CACHE+x}" ]] && return 0
  export _PIP_OUTDATED_CACHE=""
  local cmd="pip"
  command -v pip >/dev/null 2>&1 || cmd="python3 -m pip"
  _PIP_OUTDATED_CACHE="$($cmd list --outdated --format=json 2>/dev/null || true)"
  return 0
}

# True (0) if any of the space-separated packages is in pip's outdated list.
_pip_pkgs_outdated() {
  local pkgs="$1"
  [[ -n "$pkgs" ]] || return 1
  _pip_outdated_cache_load || return 1
  [[ -n "$_PIP_OUTDATED_CACHE" ]] || return 1
  printf '%s' "$_PIP_OUTDATED_CACHE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
outdated = {(p.get('name') or '').lower() for p in data}
wanted = set('$pkgs'.lower().split())
sys.exit(0 if wanted & outdated else 1)
" 2>/dev/null
}

_ucc_driver_pip_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _pip_ensure_path || { printf 'absent'; return; }
  local probe min_ver pkgs ver
  probe="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.probe_pkg")"
  [[ -n "$probe" ]] || return 1
  min_ver="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.min_version")"
  pkgs="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.install_packages")"
  ver="$(_pip_cached_version "$probe")"
  if [[ -z "$ver" ]]; then
    printf 'absent'
    return
  fi
  if [[ -n "$min_ver" ]]; then
    if ! python3 -c \
      "from packaging.version import Version; import sys; raise SystemExit(0 if Version('$min_ver') <= Version(sys.argv[1]) else 1)" \
      "$ver" 2>/dev/null; then
      printf 'absent'
      return
    fi
  fi
  if _pip_pkgs_outdated "$pkgs"; then
    printf 'outdated'
  else
    printf '%s' "$ver"
  fi
}

_ucc_driver_pip_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  _pip_ensure_path || { log_warn "pip not available (no pyenv/python on PATH)"; return 1; }
  local pkgs pip_cmd
  pkgs="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.install_packages")"
  [[ -n "$pkgs" ]] || return 1
  if command -v pip >/dev/null 2>&1; then
    pip_cmd="pip"
  else
    pip_cmd="python3 -m pip"
  fi
  case "$action" in
    install)
      # Plain install: don't touch existing deps unless required by <pkgs>.
      ucc_run $pip_cmd install -q --upgrade-strategy only-if-needed $pkgs \
        && pip_cache_versions
      ;;
    update)
      # Non-destructive update: dry-run first; if the resolver would
      # leave any other already-installed package with an unsatisfied
      # constraint ("X requires Y<Z, but you have Y>=Z"), skip the
      # upgrade entirely and leave the current install untouched.
      # Outdated detection still flags the target so the operator
      # knows there's a pending update; only the *write* is gated.
      if _pip_update_would_conflict "$pip_cmd" "$pkgs"; then
        return 0
      fi
      ucc_run $pip_cmd install -q --upgrade --upgrade-strategy only-if-needed $pkgs \
        && pip_cache_versions
      ;;
  esac
}

# Return 0 (= would conflict) if a dry-run upgrade reports incompatibility
# warnings against any other installed package. Logs the offending lines.
_pip_update_would_conflict() {
  local pip_cmd="$1" pkgs="$2"
  local out conflicts
  out="$($pip_cmd install --dry-run --upgrade --upgrade-strategy only-if-needed -q $pkgs 2>&1 || true)"
  # pip prints lines like:
  #   unsloth 2026.4.4 requires torch<2.11.0,>=2.4.0, but you have torch 2.11.0 which is incompatible.
  conflicts="$(printf '%s\n' "$out" | grep -E '^[A-Za-z0-9._-]+ [^ ]+ requires .*which is incompatible\.$' || true)"
  [[ -z "$conflicts" ]] && return 1
  log_warn "pip update for [${pkgs}] would break existing packages; skipping (non-destructive)."
  printf '%s\n' "$conflicts" | head -5 | while IFS= read -r line; do
    log_warn "  ${line}"
  done
  log_warn "  Resolve manually with a coordinated upgrade, or relax the conflicting pins, then re-run."
  return 0
}

_ucc_driver_pip_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local probe ver
  probe="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.probe_pkg")"
  [[ -n "$probe" ]] || return 1
  ver="$(_pip_cached_version "$probe")"
  printf 'version=%s  pkg=%s' "${ver:-absent}" "$probe"
}
