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

# Run all tic_tests declared in a YAML file.
# Usage: run_tic_tests_from_yaml <cfg_dir> <yaml_path>
run_tic_tests_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  local t_name t_component t_requires_status t_intent t_oracle t_trace t_skip skip_reason
  while IFS=$'\t' read -r t_name t_component t_requires_status t_intent t_oracle t_trace t_skip; do
    [[ -n "$t_name" ]] || continue
    skip_reason="$t_skip"
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
  done < <(yaml_records "$cfg_dir" "$yaml" tests name component requires_status_target intent oracle trace skip)
}

# Run docker container-running tests for services listed under a YAML section.
# Usage: run_container_tic_tests_from_yaml <cfg_dir> <yaml_path>
# Run all TIC suites and emit summary.
# Usage: run_verify <cfg_dir>
run_verify() {
  local cfg_dir="$1"

  # Load runtime variables used by oracle strings at eval time
  local _AI_SERVICES=()
  while IFS= read -r _s; do [[ -n "$_s" ]] && _AI_SERVICES+=("$_s"); done \
    < <(yaml_list "$cfg_dir" "$cfg_dir/ucc/software/ai-apps.yaml" services)
  [[ ${#_AI_SERVICES[@]} -gt 0 ]] || _AI_SERVICES=(open-webui flowise openhands n8n qdrant)

  local _NODE_VER _ARIA2_PORT _ARIAFLOW_PORT _ARIAFLOW_WEB_PORT _OLLAMA_API_HOST _OLLAMA_API_PORT
  local _UNSLOTH_PORT _UNSLOTH_LABEL _UNSLOTH_STUDIO_DIR
  _NODE_VER="$(          yaml_get "$cfg_dir" "$cfg_dir/ucc/software/dev-tools.yaml"       node_version          24)"
  _ARIA2_PORT="$(        yaml_get "$cfg_dir" "$cfg_dir/ucc/software/dev-tools.yaml"       aria2_port            6800)"
  _ARIAFLOW_PORT="$(     yaml_get "$cfg_dir" "$cfg_dir/ucc/software/dev-tools.yaml"       ariaflow_port         8000)"
  _ARIAFLOW_WEB_PORT="$( yaml_get "$cfg_dir" "$cfg_dir/ucc/software/dev-tools.yaml"       ariaflow_web_port     8001)"
  _OLLAMA_API_HOST="$(   yaml_get "$cfg_dir" "$cfg_dir/ucc/software/ollama.yaml"          api_host              127.0.0.1)"
  _OLLAMA_API_PORT="$(   yaml_get "$cfg_dir" "$cfg_dir/ucc/software/ollama.yaml"          api_port              11434)"
  _UNSLOTH_PORT="$(      yaml_get "$cfg_dir" "$cfg_dir/ucc/software/ai-python-stack.yaml" unsloth_studio.port   8888)"
  _UNSLOTH_LABEL="$(     yaml_get "$cfg_dir" "$cfg_dir/ucc/software/ai-python-stack.yaml" unsloth_studio.label  ai.unsloth.studio)"
  _UNSLOTH_STUDIO_DIR="$HOME/$(yaml_get "$cfg_dir" "$cfg_dir/ucc/software/ai-python-stack.yaml" unsloth_studio.studio_dir .unsloth/studio)"
  _tic_load_component_policies "$cfg_dir"

  # Ensure pyenv and node are in PATH so oracle commands resolve correctly
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
  if [[ -d "/opt/homebrew/opt/node@${_NODE_VER}/bin" ]]; then
    export PATH="/opt/homebrew/opt/node@${_NODE_VER}/bin:$PATH"
  elif [[ -d "/usr/local/opt/node@${_NODE_VER}/bin" ]]; then
    export PATH="/usr/local/opt/node@${_NODE_VER}/bin:$PATH"
  fi

  run_tic_tests_from_yaml "$cfg_dir" "$cfg_dir/tic/software/verify.yaml"
  run_tic_tests_from_yaml "$cfg_dir" "$cfg_dir/tic/system/verify.yaml"
  run_container_tic_tests_from_yaml "$cfg_dir" "$cfg_dir/ucc/software/ai-apps.yaml"

  tic_summary "verify"
}

run_container_tic_tests_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  local skip_reason="" _svc
  _docker_container_running() {
    docker inspect --format '{{.State.Status}}' "$1" 2>/dev/null | grep -q "^running$"
  }
  skip_reason="$(_tic_component_skip_reason "$cfg_dir" "ai-apps" || true)"
  while IFS= read -r _svc; do
    [[ -n "$_svc" ]] || continue
    if [[ -n "$skip_reason" ]]; then
      tic_test \
        --name   "docker-container-${_svc}" \
        --intent "${_svc} container must be running" \
        --oracle "_docker_container_running '${_svc}'" \
        --trace  "component:ai-apps / ucc-target:ai-stack-running" \
        --skip   "$skip_reason"
    else
      tic_test \
        --name   "docker-container-${_svc}" \
        --intent "${_svc} container must be running" \
        --oracle "_docker_container_running '${_svc}'" \
        --trace  "component:ai-apps / ucc-target:ai-stack-running"
    fi
  done < <(yaml_list "$cfg_dir" "$yaml" services)
}
