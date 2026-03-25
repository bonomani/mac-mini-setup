#!/usr/bin/env bash
# lib/tic_runner.sh — YAML-driven TIC test runner

# Run all tic_tests declared in a YAML file.
# Usage: run_tic_tests_from_yaml <cfg_dir> <yaml_path>
run_tic_tests_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  while IFS=$'\t' read -r t_name t_intent t_oracle t_trace t_skip; do
    [[ -n "$t_name" ]] || continue
    if [[ -n "$t_skip" ]]; then
      tic_test --name "$t_name" --intent "$t_intent" --oracle "$t_oracle" \
               --trace "$t_trace" --skip "$t_skip"
    else
      tic_test --name "$t_name" --intent "$t_intent" --oracle "$t_oracle" --trace "$t_trace"
    fi
  done < <(yaml_records "$cfg_dir" "$yaml" tests name intent oracle trace skip)
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

  local _NODE_VER _ARIA2_PORT _ARIAFLOW_WEB_PORT _OLLAMA_API_HOST _OLLAMA_API_PORT
  local _UNSLOTH_PORT _UNSLOTH_LABEL _UNSLOTH_STUDIO_DIR
  _NODE_VER="$(          yaml_get "$cfg_dir" "$cfg_dir/ucc/software/dev-tools.yaml"       node_version          24)"
  _ARIA2_PORT="$(        yaml_get "$cfg_dir" "$cfg_dir/ucc/software/dev-tools.yaml"       aria2_port            6800)"
  _ARIAFLOW_WEB_PORT="$( yaml_get "$cfg_dir" "$cfg_dir/ucc/software/dev-tools.yaml"       ariaflow_web_port     8001)"
  _OLLAMA_API_HOST="$(   yaml_get "$cfg_dir" "$cfg_dir/ucc/software/ollama.yaml"          api_host              127.0.0.1)"
  _OLLAMA_API_PORT="$(   yaml_get "$cfg_dir" "$cfg_dir/ucc/software/ollama.yaml"          api_port              11434)"
  _UNSLOTH_PORT="$(      yaml_get "$cfg_dir" "$cfg_dir/ucc/software/ai-python-stack.yaml" unsloth_studio.port   8888)"
  _UNSLOTH_LABEL="$(     yaml_get "$cfg_dir" "$cfg_dir/ucc/software/ai-python-stack.yaml" unsloth_studio.label  ai.unsloth.studio)"
  _UNSLOTH_STUDIO_DIR="$HOME/$(yaml_get "$cfg_dir" "$cfg_dir/ucc/software/ai-python-stack.yaml" unsloth_studio.studio_dir .unsloth/studio)"

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
  _docker_container_running() {
    docker inspect --format '{{.State.Status}}' "$1" 2>/dev/null | grep -q "^running$"
  }
  local _svc
  while IFS= read -r _svc; do
    [[ -n "$_svc" ]] || continue
    tic_test \
      --name   "docker-container-${_svc}" \
      --intent "${_svc} container must be running" \
      --oracle "_docker_container_running '${_svc}'" \
      --trace  "component:ai-apps / ucc-target:ai-stack-running"
  done < <(yaml_list "$cfg_dir" "$yaml" services)
}
