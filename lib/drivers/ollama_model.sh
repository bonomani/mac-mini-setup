#!/usr/bin/env bash
# lib/drivers/ollama_model.sh — driver.kind: ollama-model
# driver.ref: <model-name>  (e.g. llama3.2, mistral:7b)

_ucc_driver_ollama_model_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ref
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  [[ -n "$ref" ]] || return 1
  if ollama_model_present "$ref"; then
    printf '%s' "$ref"
  else
    printf 'absent'
  fi
}

_ucc_driver_ollama_model_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local ref
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  [[ -n "$ref" ]] || return 1
  ollama_model_pull "$ref"
}

_ucc_driver_ollama_model_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local ref
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  [[ -n "$ref" ]] || return 1
  printf 'model=%s' "$ref"
}
