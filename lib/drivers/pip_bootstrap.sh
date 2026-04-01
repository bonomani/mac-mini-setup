#!/usr/bin/env bash
# lib/drivers/pip_bootstrap.sh — driver.kind: pip-bootstrap
# Ensures pip + setuptools + wheel are up-to-date.
# Reads pip_bootstrap list from YAML.

_ucc_driver_pip_bootstrap_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  if command -v pip >/dev/null 2>&1; then
    pip --version 2>/dev/null | awk '{print $2}'
  else
    printf 'absent'
  fi
}

_ucc_driver_pip_bootstrap_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local pkgs; pkgs="$(yaml_list "$cfg_dir" "$yaml" pip_bootstrap 2>/dev/null | xargs)"
  # shellcheck disable=SC2086
  [[ -n "$pkgs" ]] && pip install --upgrade $pkgs
}

_ucc_driver_pip_bootstrap_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ver path
  ver="$(pip --version 2>/dev/null | awk '{print $2}')"
  path="$(command -v pip 2>/dev/null || true)"
  [[ -n "$ver" ]] && printf 'version=%s  path=%s' "$ver" "$path"
}
