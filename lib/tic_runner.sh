#!/usr/bin/env bash
# lib/tic_runner.sh — YAML-driven TIC test runner

_TIC_POLICY_NAMES=()
_TIC_POLICY_MODES=()
_TIC_DISPATCH_COMPS=()
_TIC_DISPATCH_CONFIGS=()

_tic_load_component_policies() {
  local cfg_dir="$1" name mode
  _TIC_POLICY_NAMES=()
  _TIC_POLICY_MODES=()
  _TIC_DISPATCH_COMPS=()
  _TIC_DISPATCH_CONFIGS=()
  [[ -f "$cfg_dir/policy/components.yaml" ]] || return 0
  while IFS=$'\t' read -r name mode; do
    [[ -n "$name" ]] || continue
    _TIC_POLICY_NAMES+=("$name")
    _TIC_POLICY_MODES+=("${mode:-enabled}")
  done < <(yaml_records "$cfg_dir" "$cfg_dir/policy/components.yaml" components name mode)
}

_tic_component_mode() {
  local comp="$1" i
  for i in "${!_TIC_POLICY_NAMES[@]}"; do
    [[ "${_TIC_POLICY_NAMES[$i]}" == "$comp" ]] || continue
    printf '%s' "${_TIC_POLICY_MODES[$i]}"
    return 0
  done
  printf 'enabled'
}

_tic_component_config() {
  local cfg_dir="$1" comp="$2" i dispatch config
  for i in "${!_TIC_DISPATCH_COMPS[@]}"; do
    [[ "${_TIC_DISPATCH_COMPS[$i]}" == "$comp" ]] || continue
    printf '%s' "${_TIC_DISPATCH_CONFIGS[$i]}"
    return 0
  done
  dispatch="$(python3 "$cfg_dir/tools/validate_targets_manifest.py" --dispatch "$comp" "$cfg_dir/ucc" 2>/dev/null || true)"
  config="$(printf '%s\n' "$dispatch" | sed -n '4p')"
  _TIC_DISPATCH_COMPS+=("$comp")
  _TIC_DISPATCH_CONFIGS+=("$config")
  printf '%s' "$config"
}

_tic_component_supported_for_host() {
  local cfg_dir="$1" comp="$2" config="$3" platform
  local supported=()
  [[ -n "$comp" ]] || return 0
  [[ -n "$config" ]] || config="$(_tic_component_config "$cfg_dir" "$comp")"
  [[ -n "$config" ]] || return 0
  while IFS= read -r platform; do
    [[ -n "$platform" ]] && supported+=("$platform")
  done < <(yaml_list "$cfg_dir" "$config" platforms)
  [[ ${#supported[@]} -eq 0 ]] && return 0
  for platform in "${supported[@]}"; do
    [[ "$platform" == "${HOST_PLATFORM_VARIANT:-unknown}" ]] && return 0
    [[ "$platform" == "${HOST_PLATFORM:-unknown}" ]] && return 0
    [[ "${HOST_PLATFORM:-unknown}" == "wsl" && "$platform" == "linux" ]] && return 0
  done
  return 1
}

_tic_component_skip_reason() {
  local cfg_dir="$1" comp="$2" mode config
  [[ -n "$comp" ]] || return 1
  mode="$(_tic_component_mode "$comp")"
  case "$mode" in
    enabled) ;;
    *)
      printf 'component=%s policy=%s' "$comp" "$mode"
      return 0
      ;;
  esac
  config="$(_tic_component_config "$cfg_dir" "$comp")"
  if ! _tic_component_supported_for_host "$cfg_dir" "$comp" "$config"; then
    printf 'component=%s platform unsupported on host=%s' "$comp" "${HOST_PLATFORM:-unknown}"
    return 0
  fi
  return 1
}

_tic_requires_status_skip_reason() {
  local target="$1"
  [[ -n "$target" ]] || return 1
  if [[ -z "${UCC_TARGET_STATUS_FILE:-}" || ! -f "${UCC_TARGET_STATUS_FILE:-}" ]]; then
    printf 'current run did not emit target status for %s' "$target"
    return 0
  fi
  if ! awk -F'|' -v target="$target" '$1==target {found=1} END {exit !found}' "${UCC_TARGET_STATUS_FILE:-/dev/null}"; then
    printf 'current run did not execute target %s' "$target"
    return 0
  fi
  return 1
}

_tic_target_status() {
  local target="$1"
  [[ -n "$target" ]] || return 1
  [[ -n "${UCC_TARGET_STATUS_FILE:-}" && -f "${UCC_TARGET_STATUS_FILE:-}" ]] || return 1
  awk -F'|' -v target="$target" '$1==target {val=$2} END {print val}' "${UCC_TARGET_STATUS_FILE:-/dev/null}" 2>/dev/null || true
}

_tic_target_status_is() {
  local target="$1" expected="$2"
  [[ -n "$target" && -n "$expected" ]] || return 1
  [[ "$(_tic_target_status "$target")" == "$expected" ]]
}

# Return 0 (skip) when a Docker Compose service container is not running.
# Usage: _tic_service_not_running <service_name>
_tic_service_not_running() {
  local svc="$1"
  [[ -n "$svc" ]] || return 0
  ! docker ps --filter "name=${svc}" --filter "status=running" --format '{{.Names}}' 2>/dev/null | grep -q .
}

_tic_skip_when_reason() {
  local condition="$1" reason="${2:-conditional skip}"
  [[ -n "$condition" ]] || return 1
  if eval "$condition"; then
    printf '%s' "$reason"
    return 0
  fi
  return 1
}

# Run all tic_tests declared in a YAML file.
# Usage: run_tic_tests_from_yaml <cfg_dir> <yaml_path>
run_tic_tests_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  local t_name t_component t_requires_status t_intent t_oracle t_trace t_skip t_skip_when skip_reason row
  local _tic_sep=$'\x1f'
  while IFS= read -r row; do
    row="${row//$'\t'/${_tic_sep}}"
    IFS="${_tic_sep}" read -r t_name t_component t_requires_status t_intent t_oracle t_trace t_skip t_skip_when <<< "${row}${_tic_sep}"
    [[ -n "$t_name" ]] || continue
    skip_reason=""
    if [[ -n "$t_skip_when" ]]; then
      skip_reason="$(_tic_skip_when_reason "$t_skip_when" "$t_skip" || true)"
    else
      skip_reason="$t_skip"
    fi
    if [[ -z "$skip_reason" ]]; then
      skip_reason="$(_tic_component_skip_reason "$cfg_dir" "$t_component" || true)"
    fi
    if [[ -z "$skip_reason" ]]; then
      skip_reason="$(_tic_requires_status_skip_reason "$t_requires_status" || true)"
    fi
    if [[ -n "$skip_reason" ]]; then
      tic_test --name "$t_name" --intent "$t_intent" --oracle "$t_oracle" \
               --trace "$t_trace" --skip "$skip_reason"
    else
      tic_test --name "$t_name" --intent "$t_intent" --oracle "$t_oracle" --trace "$t_trace"
    fi
  done < <(yaml_records "$cfg_dir" "$yaml" tests name component requires_status_target intent oracle trace skip skip_when)
}

# Run all TIC suites and emit summary.
# Usage: run_verify <cfg_dir>
run_verify() {
  local cfg_dir="$1"

  local _NODE_VER="24" _PYENV_DIR=".pyenv"
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      node_version) [[ -n "$value" ]] && _NODE_VER="$value" ;;
    esac
  done < <(yaml_get_many "$cfg_dir" "$cfg_dir/ucc/software/dev-tools.yaml" node_version)
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      pyenv_dir) [[ -n "$value" ]] && _PYENV_DIR="$value" ;;
    esac
  done < <(yaml_get_many "$cfg_dir" "$cfg_dir/ucc/software/ai-python-stack.yaml" pyenv_dir)
  _tic_load_component_policies "$cfg_dir"

  # Ensure pyenv and nvm-managed node are in PATH so oracle commands resolve correctly
  export PYENV_ROOT="$HOME/$_PYENV_DIR"
  export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    source "$NVM_DIR/nvm.sh" 2>/dev/null || true
    nvm use "$_NODE_VER" >/dev/null 2>&1 || true
  elif [[ -d "/opt/homebrew/opt/node@${_NODE_VER}/bin" ]]; then
    export PATH="/opt/homebrew/opt/node@${_NODE_VER}/bin:$PATH"
  elif [[ -d "/usr/local/opt/node@${_NODE_VER}/bin" ]]; then
    export PATH="/usr/local/opt/node@${_NODE_VER}/bin:$PATH"
  fi

  run_tic_tests_from_yaml "$cfg_dir" "$cfg_dir/tic/software/verify.yaml"
  run_tic_tests_from_yaml "$cfg_dir" "$cfg_dir/tic/system/verify.yaml"
  run_tic_tests_from_yaml "$cfg_dir" "$cfg_dir/tic/software/integration.yaml"

  tic_summary "verify"
}
