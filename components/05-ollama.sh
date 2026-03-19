#!/usr/bin/env bash
# Component: Ollama — local LLMs via Apple Metal
# UCC + Basic

# Models recommended for 64 GB machine
MODELS=(
  "llama3.2"           # 3B  — fast, everyday tasks
  "llama3.1:8b"        # 8B  — good balance
  "llama3.1:70b"       # 70B — high quality (~40 GB)
  "mistral:7b"         # 7B  — fast and capable
  "qwen2.5-coder:32b"  # 32B — excellent for coding
  "nomic-embed-text"   # embedding model
)

_observe_ollama() {
  is_installed ollama && echo "installed" || echo "absent"
}

_install_ollama() {
  brew install ollama
  brew services start ollama
  sleep 3
}

_update_ollama() {
  brew upgrade ollama 2>/dev/null || brew install ollama
  brew services restart ollama
  sleep 3
}

ucc_target \
  --name    "ollama" \
  --observe _observe_ollama \
  --desired "installed" \
  --install _install_ollama \
  --update  _update_ollama

# Ensure service is running
_observe_ollama_service() {
  ollama list &>/dev/null 2>&1 && echo "running" || echo "stopped"
}

_start_ollama_service() {
  brew services start ollama
  sleep 3
}

ucc_target \
  --name    "ollama-service" \
  --observe _observe_ollama_service \
  --desired "running" \
  --install _start_ollama_service

# --- Pull models --------------------------------------------
for model in "${MODELS[@]}"; do
  _name="ollama-model-${model//:/-}"

  _observe_fn() { ollama_model_present "$model" && echo "present" || echo "absent"; }

  _pull_fn() {
    log_info "Pulling model: $model"
    ollama pull "$model"
  }

  _update_fn() {
    log_info "Re-pulling model: $model (update)"
    ollama pull "$model"
  }

  ucc_target \
    --name    "$_name" \
    --observe _observe_fn \
    --desired "present" \
    --install _pull_fn \
    --update  _update_fn
done

echo ""
log_info "Ollama API  → http://localhost:11434"
log_info "Test with   → ollama run llama3.2"

ucc_summary "05-ollama"
