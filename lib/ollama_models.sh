#!/usr/bin/env bash
# lib/ollama_models.sh — helpers for YAML-driven Ollama model pull targets
# Sourced by components/ollama.sh

# Populate the Ollama model list cache (exports _OLLAMA_MODELS_CACHE).
ollama_model_cache_list() {
  export _OLLAMA_MODELS_CACHE
  _OLLAMA_MODELS_CACHE="$(ollama list 2>/dev/null | awk 'NR>1 {print $1}' || true)"
}

# Return 0 if the given Ollama model ref is present locally.
ollama_model_present() {
  if [[ -n "${_OLLAMA_MODELS_CACHE+x}" ]]; then
    grep -Fxq "$1" <<< "$_OLLAMA_MODELS_CACHE"
  else
    ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -Fxq "$1"
  fi
}

# Pull an Ollama model and refresh the cache.
# Usage: ollama_model_pull <model_ref>
ollama_model_pull() {
  log_info "Pulling model: $1"
  ucc_run ollama pull "$1" || return $?
  ollama_model_cache_list 2>/dev/null || true
}

# Runner: load model targets from YAML and register them based on autopull preference.
# Usage: load_ollama_models_from_yaml <cfg_dir> <yaml_path> <autopull_pref>
load_ollama_models_from_yaml() {
  local cfg_dir="$1" yaml="$2" autopull="$3"
  local groups=() group="" target=""

  case "$autopull" in
    small)
      log_info "ollama-model-autopull=small — pulling models ≤ 3B"
      groups=(small)
      ;;
    medium)
      log_info "ollama-model-autopull=medium — pulling models ≤ 8B"
      groups=(small medium)
      ;;
    large)
      log_info "ollama-model-autopull=large — pulling all models (may take a long time)"
      groups=(small medium large)
      ;;
    none|*)
      groups=(small medium large)
      ;;
  esac

  ollama_model_cache_list
  for group in "${groups[@]}"; do
    while IFS= read -r target; do
      [[ -n "$target" ]] || continue
      ucc_yaml_simple_target "$cfg_dir" "$yaml" "$target"
    done < <(yaml_list "$cfg_dir" "$yaml" "$group")
  done
}
