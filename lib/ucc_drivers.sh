#!/usr/bin/env bash
# lib/ucc_drivers.sh — Driver dispatch hub
# Sourced by lib/ucc.sh after ucc_targets.sh.
#
# Each driver implements three operations:
#   _ucc_driver_<kind>_observe  <cfg_dir> <yaml> <target>  → prints ASM state
#   _ucc_driver_<kind>_action   <cfg_dir> <yaml> <target> <install|update>
#   _ucc_driver_<kind>_evidence <cfg_dir> <yaml> <target>  → prints evidence text
#
# driver.kind: custom  is the explicit escape hatch — targets that keep
# observe_cmd/actions.*/evidence.* embedded in YAML are not dispatched here.

_UCC_DRIVERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/drivers" && pwd)"

for _ucc_drv_file in \
  "$_UCC_DRIVERS_DIR/brew.sh" \
  "$_UCC_DRIVERS_DIR/vscode.sh" \
  "$_UCC_DRIVERS_DIR/ollama_model.sh" \
  "$_UCC_DRIVERS_DIR/npm.sh" \
  "$_UCC_DRIVERS_DIR/pip.sh" \
  "$_UCC_DRIVERS_DIR/macos_defaults.sh" \
  "$_UCC_DRIVERS_DIR/macos_swupdate.sh" \
  "$_UCC_DRIVERS_DIR/docker.sh" \
  "$_UCC_DRIVERS_DIR/app_bundle.sh" \
  "$_UCC_DRIVERS_DIR/pyenv.sh" \
  "$_UCC_DRIVERS_DIR/nvm.sh" \
  "$_UCC_DRIVERS_DIR/brew_service.sh" \
  "$_UCC_DRIVERS_DIR/launchd.sh" \
  "$_UCC_DRIVERS_DIR/custom_daemon.sh" \
  "$_UCC_DRIVERS_DIR/compose_file.sh" \
  ; do
  [[ -f "$_ucc_drv_file" ]] && source "$_ucc_drv_file"
done
unset _ucc_drv_file

# _ucc_driver_observe <cfg_dir> <yaml> <target>
# Returns 0 and emits ASM state if driver handled it; returns 1 to fall through.
_ucc_driver_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local kind
  kind="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.kind")"
  [[ -n "$kind" && "$kind" != "custom" ]] || return 1
  local fn="_ucc_driver_${kind//-/_}_observe"
  declare -f "$fn" >/dev/null 2>&1 || return 1
  "$fn" "$cfg_dir" "$yaml" "$target"
}

# _ucc_driver_action <cfg_dir> <yaml> <target> <install|update>
# Returns 0 and executes action if driver handled it; returns 1 to fall through.
_ucc_driver_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local kind
  kind="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.kind")"
  [[ -n "$kind" && "$kind" != "custom" ]] || return 1
  local fn="_ucc_driver_${kind//-/_}_action"
  declare -f "$fn" >/dev/null 2>&1 || return 1
  "$fn" "$cfg_dir" "$yaml" "$target" "$action"
}

# _ucc_driver_apply <cfg_dir> <yaml> <target>
# For config/bool targets: routes to _ucc_driver_<kind>_apply instead of _action.
# Returns 0 if driver handled it; returns 1 to fall through.
_ucc_driver_apply() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local kind
  kind="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.kind")"
  [[ -n "$kind" && "$kind" != "custom" ]] || return 1
  local fn="_ucc_driver_${kind//-/_}_apply"
  declare -f "$fn" >/dev/null 2>&1 || return 1
  "$fn" "$cfg_dir" "$yaml" "$target"
}

# _ucc_driver_evidence <cfg_dir> <yaml> <target>
# Returns 0 and emits evidence text if driver handled it; returns 1 to fall through.
_ucc_driver_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local kind
  kind="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.kind")"
  [[ -n "$kind" && "$kind" != "custom" ]] || return 1
  local fn="_ucc_driver_${kind//-/_}_evidence"
  declare -f "$fn" >/dev/null 2>&1 || return 1
  "$fn" "$cfg_dir" "$yaml" "$target"
}
