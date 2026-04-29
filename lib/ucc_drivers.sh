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
  "$_UCC_DRIVERS_DIR/npm.sh" \
  "$_UCC_DRIVERS_DIR/pip.sh" \
  "$_UCC_DRIVERS_DIR/setting.sh" \
  "$_UCC_DRIVERS_DIR/app_bundle.sh" \
  "$_UCC_DRIVERS_DIR/nvm.sh" \
  "$_UCC_DRIVERS_DIR/service.sh" \
  "$_UCC_DRIVERS_DIR/pkg.sh" \
  "$_UCC_DRIVERS_DIR/custom_daemon.sh" \
  "$_UCC_DRIVERS_DIR/compose_file.sh" \
  "$_UCC_DRIVERS_DIR/compose_apply.sh" \
  "$_UCC_DRIVERS_DIR/docker_compose_service.sh" \
  "$_UCC_DRIVERS_DIR/package.sh" \
  "$_UCC_DRIVERS_DIR/git_repo.sh" \
  "$_UCC_DRIVERS_DIR/build_deps.sh" \
  "$_UCC_DRIVERS_DIR/swupdate_schedule.sh" \
  "$_UCC_DRIVERS_DIR/pyenv_brew.sh" \
  "$_UCC_DRIVERS_DIR/pip_bootstrap.sh" \
  "$_UCC_DRIVERS_DIR/home_artifact.sh" \
  "$_UCC_DRIVERS_DIR/script_installer.sh" \
  "$_UCC_DRIVERS_DIR/zsh_config.sh" \
  "$_UCC_DRIVERS_DIR/path_export.sh" \
  "$_UCC_DRIVERS_DIR/brew_unlink.sh" \
  "$_UCC_DRIVERS_DIR/git_global.sh" \
  ; do
  [[ -f "$_ucc_drv_file" ]] && source "$_ucc_drv_file"
done
unset _ucc_drv_file

# _ucc_driver_dispatch <cfg_dir> <yaml> <target> <operation> [extra_args...]
# Central dispatch: resolves driver.kind, finds _ucc_driver_<kind>_<op>,
# calls it if defined. Returns 0 if handled, 1 to fall through.
_ucc_driver_dispatch() {
  local cfg_dir="$1" yaml="$2" target="$3" op="$4"
  shift 4
  local kind
  kind="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.kind")"
  [[ -n "$kind" && "$kind" != "custom" ]] || return 1
  local fn="_ucc_driver_${kind//-/_}_${op}"
  if ! declare -f "$fn" >/dev/null 2>&1; then
    # Driver kind exists but is missing the requested op. For required ops
    # (observe/action), this is likely a driver bug — log it once per
    # (kind, op) pair so it surfaces in real runs without flooding.
    case "$op" in
      observe|action)
        # Skip the warning for `capability` kind — it intentionally has no
        # `_ucc_driver_capability_observe` because capability targets are
        # dispatched via `_ucc_observe_yaml_capability_target` in ucc_targets.sh,
        # not through the driver registry.
        [[ "$kind" == "capability" ]] && return 1
        # Per-process dedup of missing-op warnings. `declare -g` (not export)
        # keeps the flag in the shell, out of the child-process env.
        local _seen_var="_UCC_DRV_MISSING_${kind//[^a-zA-Z0-9]/_}_${op}"
        if [[ -z "${!_seen_var:-}" ]]; then
          declare -g "$_seen_var=1"
          log_debug "driver '$kind' missing required op '_ucc_driver_${kind//-/_}_${op}' — falling through (target: $target)"
        fi
        ;;
    esac
    return 1
  fi
  "$fn" "$cfg_dir" "$yaml" "$target" "$@"
}

_ucc_driver_observe() { _ucc_driver_dispatch "$1" "$2" "$3" observe; }
_ucc_driver_action()  { _ucc_driver_dispatch "$1" "$2" "$3" action "$4"; }
_ucc_driver_apply()   { _ucc_driver_dispatch "$1" "$2" "$3" apply; }
_ucc_driver_recover() { _ucc_driver_dispatch "$1" "$2" "$3" recover "$4"; }

# _ucc_driver_evidence <cfg_dir> <yaml> <target>
# Returns 0 and emits evidence text if driver handled it; returns 1 to fall through.
_ucc_driver_evidence() {
  _ucc_driver_dispatch "$1" "$2" "$3" evidence || return 1
  # Generic: append latest version from GitHub if driver.github_repo is set
  _ucc_driver_github_latest "$1" "$2" "$3"
}

# Check GitHub releases for latest version (generic, works with any driver).
# Reads driver.github_repo. Appends "  latest=X.Y.Z" to evidence output.
_ucc_driver_github_latest() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local repo; repo="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.github_repo" 2>/dev/null || true)"
  [[ -n "$repo" ]] || return 0
  # Try releases first
  local _t; _t="$(_ucc_curl_timeout probe)"
  local latest; latest="$(curl -fsS --max-time "$_t" "$(_ucc_github_api_url "repos/${repo}/releases/latest")" 2>/dev/null \
    | awk -F'"' '/"tag_name"/{print $4}' | sed 's/^v//')"
  if [[ -n "$latest" ]]; then
    printf '  latest=%s' "$latest"
  else
    # No releases — check latest commit (short hash), label differently
    latest="$(curl -fsS --max-time "$_t" "$(_ucc_github_api_url "repos/${repo}/commits/HEAD")" 2>/dev/null \
      | awk -F'"' '/"sha"/{print substr($4,1,7); exit}')"
    [[ -n "$latest" ]] && printf '  latest-commit=%s' "$latest"
  fi
  return 0
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

# package (platform-aware meta-driver)
_ucc_driver_package_depends_on() {
  case "${HOST_PLATFORM:-macos}" in
    macos) printf 'homebrew' ;;
    *)     printf 'build-deps' ;;
  esac
}
_ucc_driver_package_provided_by() {
  case "${HOST_PLATFORM:-macos}" in
    macos) printf 'brew' ;;
    *)     printf 'native-package-manager' ;;
  esac
}

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

_ucc_driver_pyenv_brew_depends_on() {
  case "${HOST_PLATFORM:-macos}" in
    macos) printf 'homebrew' ;;
    *)     : ;;  # git-clone path has no package-manager prerequisite
  esac
}
_ucc_driver_pyenv_brew_provided_by() {
  case "${HOST_PLATFORM:-macos}" in
    macos) printf 'brew' ;;
    *)     printf 'git' ;;
  esac
}

_ucc_driver_nvm_depends_on()               { printf 'homebrew'; }
_ucc_driver_nvm_provided_by()              { printf 'nvm-installer'; }

_ucc_driver_nvm_version_depends_on()       { printf 'nvm'; }
_ucc_driver_nvm_version_provided_by()      { printf 'nvm'; }


_ucc_driver_service_depends_on() {
  # Inherit dependency from the backend. Only brew has one today.
  case "${_SVC_BACKEND:-}" in brew) printf 'homebrew' ;; esac
}
_ucc_driver_service_provided_by() {
  case "${_SVC_BACKEND:-}" in brew) printf 'brew' ;; launchd) printf 'launchd' ;; esac
}

_ucc_driver_docker_compose_service_depends_on()  { printf 'docker-available'; }
_ucc_driver_docker_compose_service_provided_by() { printf 'docker-compose'; }

# git-repo
_ucc_driver_git_repo_provided_by()     { printf 'git'; }
