#!/usr/bin/env bash
# lib/drivers/corepack.sh — driver.kind: corepack
# Ensures `corepack enable` has been run so pnpm/yarn shims resolve.
# Corepack itself ships with Node ≥ 16.9; we only manage activation here.

_corepack_shim_path() {
  command -v corepack 2>/dev/null
}

_corepack_pnpm_is_shim() {
  local pnpm_path
  pnpm_path="$(command -v pnpm 2>/dev/null)" || return 1
  # corepack-managed shim resolves to a corepack-tagged path
  [[ -L "$pnpm_path" ]] && readlink "$pnpm_path" 2>/dev/null | grep -q corepack && return 0
  grep -q corepack "$pnpm_path" 2>/dev/null
}

_ucc_driver_corepack_observe() {
  [[ -n "$(_corepack_shim_path)" ]] || { printf 'absent'; return; }
  if _corepack_pnpm_is_shim; then
    printf 'configured'
  else
    printf 'unconfigured'
  fi
}

_ucc_driver_corepack_action() {
  ucc_run corepack enable
}

_ucc_driver_corepack_evidence() {
  local v
  v="$(corepack --version 2>/dev/null || printf 'unknown')"
  printf 'corepack=%s' "$v"
}
