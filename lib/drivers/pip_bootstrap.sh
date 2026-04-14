#!/usr/bin/env bash
# lib/drivers/pip_bootstrap.sh — driver.kind: pip-bootstrap
# Ensures pip + setuptools + wheel are up-to-date.
# Reads pip_bootstrap list from YAML.
#
# update_class: this target is a `tool` (pip itself is self-contained and
# users expect it current). Outdated detection uses `pip list --outdated`
# (gated on UIC_PREF_UPSTREAM_CHECK like other pip driver checks).
# Update action respects UIC_PREF_TOOL_UPDATE.

_pip_bootstrap_version() {
  pip --version 2>/dev/null | awk '{print $2}'
}

# Check if any of the bootstrap packages (pip/setuptools/wheel) has an
# upstream update available. Reuses _pip_outdated_cache_load from pip.sh
# when available, so the `pip list --outdated` call is shared across drivers.
_pip_bootstrap_outdated() {
  local pkgs="$1"
  [[ -n "$pkgs" ]] || return 1
  [[ "${UIC_PREF_UPSTREAM_CHECK:-0}" == "1" ]] || return 1
  declare -f _pip_outdated_cache_load >/dev/null 2>&1 || return 1
  _pip_outdated_cache_load || return 1
  [[ -n "${_PIP_OUTDATED_CACHE:-}" ]] || return 1
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

_ucc_driver_pip_bootstrap_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ver
  ver="$(_pip_bootstrap_version)"
  [[ -z "$ver" ]] && { printf 'absent'; return; }
  # Outdated detection: only under balanced/aggressive + upstream check on.
  if [[ "${UIC_PREF_TOOL_UPDATE:-always-upgrade}" == "always-upgrade" ]]; then
    local pkgs; pkgs="$(yaml_list "$cfg_dir" "$yaml" pip_bootstrap 2>/dev/null | xargs)"
    if _pip_bootstrap_outdated "$pkgs"; then
      printf 'outdated'
      return
    fi
  fi
  printf '%s' "$ver"
}

_ucc_driver_pip_bootstrap_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local pkgs; pkgs="$(yaml_list "$cfg_dir" "$yaml" pip_bootstrap 2>/dev/null | xargs)"
  [[ -n "$pkgs" ]] || return 0
  case "$action" in
    install)
      # First-time install: always ensure pkgs are present.
      # shellcheck disable=SC2086
      ucc_run pip install --upgrade $pkgs
      ;;
    update)
      # Respect UIC_PREF_TOOL_UPDATE — skip the upgrade under conservative.
      if [[ "${UIC_PREF_TOOL_UPDATE:-always-upgrade}" != "always-upgrade" ]]; then
        return 0
      fi
      # shellcheck disable=SC2086
      ucc_run pip install --upgrade $pkgs
      ;;
  esac
  local rc=$?
  # Invalidate caches after a state-changing action so verify-after-update
  # observes the fresh state instead of the pre-upgrade cached result.
  unset _PIP_OUTDATED_CACHE
  _ucc_cache_invalidate "pip-outdated-global"
  return $rc
}

_ucc_driver_pip_bootstrap_evidence() {
  local ver path
  ver="$(_pip_bootstrap_version)"
  path="$(command -v pip 2>/dev/null || true)"
  [[ -n "$ver" ]] && printf 'version=%s  path=%s' "$ver" "$path"
}
