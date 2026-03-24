#!/usr/bin/env bash
# lib/tic_runner.sh — YAML-driven TIC test runner
# Sourced by components/10-verify.sh

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
  done < <(python3 "$cfg_dir/tools/read_config.py" --records \
      "$yaml" tests name intent oracle trace skip 2>/dev/null)
}

# Run docker container-running tests for services listed under a YAML section.
# Usage: run_container_tic_tests_from_yaml <cfg_dir> <yaml_path>
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
      --trace  "component:07-ai-apps / ucc-target:ai-stack-running"
  done < <(python3 "$cfg_dir/tools/read_config.py" --list "$yaml" services 2>/dev/null)
}
