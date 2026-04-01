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
  "$_UCC_DRIVERS_DIR/docker_compose_service.sh" \
  "$_UCC_DRIVERS_DIR/build_deps.sh" \
  "$_UCC_DRIVERS_DIR/swupdate_schedule.sh" \
  "$_UCC_DRIVERS_DIR/pyenv_brew.sh" \
  "$_UCC_DRIVERS_DIR/pip_bootstrap.sh" \
  "$_UCC_DRIVERS_DIR/cli_symlink.sh" \
  "$_UCC_DRIVERS_DIR/script_installer.sh" \
  "$_UCC_DRIVERS_DIR/zsh_config.sh" \
  "$_UCC_DRIVERS_DIR/path_export.sh" \
  "$_UCC_DRIVERS_DIR/bin_script.sh" \
  "$_UCC_DRIVERS_DIR/brew_unlink.sh" \
  "$_UCC_DRIVERS_DIR/git_global.sh" \
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

# _ucc_driver_depends_on <kind>
# Returns the implicit target dependency for a driver kind, or empty.
_ucc_driver_depends_on() {
  local kind="$1"
  [[ -n "$kind" && "$kind" != "custom" ]] || return 0
  local fn="_ucc_driver_${kind//-/_}_depends_on"
  declare -f "$fn" >/dev/null 2>&1 && "$fn"
}

# _ucc_driver_provided_by <kind>
# Returns the implicit provided_by_tool for a driver kind, or empty.
_ucc_driver_provided_by() {
  local kind="$1"
  [[ -n "$kind" && "$kind" != "custom" ]] || return 0
  local fn="_ucc_driver_${kind//-/_}_provided_by"
  declare -f "$fn" >/dev/null 2>&1 && "$fn"
}

# ── Driver meta declarations ──────────────────────────────────────────────────
# Each driver declares its implicit dependency target and tool name.
# Only drivers with a non-trivial prerequisite need these.

_ucc_driver_brew_depends_on()              { printf 'homebrew'; }
_ucc_driver_brew_provided_by()             { printf 'brew'; }

_ucc_driver_app_bundle_depends_on()        { printf 'homebrew'; }
_ucc_driver_app_bundle_provided_by()       { printf 'brew-cask'; }

_ucc_driver_pip_depends_on()               { printf 'pip-latest'; }
_ucc_driver_pip_provided_by()              { printf 'pip'; }

_ucc_driver_pip_bootstrap_depends_on()     { printf 'python'; }
_ucc_driver_pip_bootstrap_provided_by()    { printf 'pip'; }

_ucc_driver_npm_global_depends_on()        { printf 'node-lts'; }
_ucc_driver_npm_global_provided_by()       { printf 'npm'; }

_ucc_driver_vscode_marketplace_depends_on()  { printf 'vscode-code-cmd'; }
_ucc_driver_vscode_marketplace_provided_by() { printf 'vscode-marketplace'; }

_ucc_driver_pyenv_version_depends_on()     { printf 'pyenv'; }
_ucc_driver_pyenv_version_provided_by()    { printf 'pyenv'; }

_ucc_driver_pyenv_brew_depends_on()        { printf 'homebrew'; }
_ucc_driver_pyenv_brew_provided_by()       { printf 'brew'; }

_ucc_driver_nvm_depends_on()               { printf 'homebrew'; }
_ucc_driver_nvm_provided_by()              { printf 'nvm-installer'; }

_ucc_driver_nvm_version_depends_on()       { printf 'nvm'; }
_ucc_driver_nvm_version_provided_by()      { printf 'nvm'; }

_ucc_driver_ollama_model_depends_on()      { printf 'ollama'; }
_ucc_driver_ollama_model_provided_by()     { printf 'ollama'; }

_ucc_driver_brew_service_depends_on()      { printf 'homebrew'; }
_ucc_driver_brew_service_provided_by()     { printf 'brew'; }

_ucc_driver_docker_compose_service_depends_on()  { printf 'docker-desktop'; }
_ucc_driver_docker_compose_service_provided_by() { printf 'docker-compose'; }
