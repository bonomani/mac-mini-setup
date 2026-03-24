#!/usr/bin/env bash
# lib/ollama_models.sh — helpers for YAML-driven Ollama model pull targets
# Sourced by components/05-ollama.sh

# Helper: register ucc_targets for a list of models.
# Usage: _ollama_pull_set <model> [<model> ...]
_ollama_pull_set() {
  local models=("$@")
  local model _name _fn
  for model in "${models[@]}"; do
    _name="ollama-model-${model//:/-}"
    _fn="${_name//[^a-zA-Z0-9_]/_}"
    eval "_observe_${_fn}() { local raw; raw=\$(ollama_model_present '${model}' && echo 'present' || echo 'absent'); ucc_asm_package_state \"\$raw\"; }"
    eval "_evidence_${_fn}() { printf 'model=${model}'; }"
    eval "_pull_${_fn}()    { log_info 'Pulling model: ${model}'; ucc_run ollama pull '${model}'; }"
    ucc_target_nonruntime \
      --name    "$_name" \
      --observe "_observe_${_fn}" \
      --evidence "_evidence_${_fn}" \
      --install "_pull_${_fn}" \
      --update  "_pull_${_fn}"
  done
}

# Runner: load model sets from YAML and register targets based on autopull preference.
# Usage: load_ollama_models_from_yaml <cfg_dir> <yaml_path> <autopull_pref>
load_ollama_models_from_yaml() {
  local cfg_dir="$1" yaml="$2" autopull="$3"
  local models_small=() models_medium=() models_large=()

  while IFS= read -r m; do [[ -n "$m" ]] && models_small+=("$m"); done \
    < <(python3 "$cfg_dir/tools/read_config.py" --list "$yaml" small 2>/dev/null)
  while IFS= read -r m; do [[ -n "$m" ]] && models_medium+=("$m"); done \
    < <(python3 "$cfg_dir/tools/read_config.py" --list "$yaml" medium 2>/dev/null)
  while IFS= read -r m; do [[ -n "$m" ]] && models_large+=("$m"); done \
    < <(python3 "$cfg_dir/tools/read_config.py" --list "$yaml" large 2>/dev/null)

  case "$autopull" in
    small)
      log_info "ollama-model-autopull=small — pulling models ≤ 3B"
      _ollama_pull_set "${models_small[@]}"
      ;;
    medium)
      log_info "ollama-model-autopull=medium — pulling models ≤ 8B"
      _ollama_pull_set "${models_small[@]}" "${models_medium[@]}"
      ;;
    large)
      log_info "ollama-model-autopull=large — pulling all models (may take a long time)"
      _ollama_pull_set "${models_small[@]}" "${models_medium[@]}" "${models_large[@]}"
      ;;
    none|*) ;;
  esac
}
