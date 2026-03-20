#!/usr/bin/env bash
# Component: Ollama — local LLMs via Apple Metal
# UCC + Basic

MACOS_MAJOR="$(sw_vers -productVersion | awk -F. '{print $1}')"

# Models recommended for 64 GB machine
MODELS=(
  "qwen3:latest"           # latest Qwen3 — top-tier reasoning
  "llama3.2"               # 3B  — fast, everyday tasks
  "llama3.1:8b"            # 8B  — good balance
  "llama3.1:70b"           # 70B — high quality (~40 GB)
  "mistral:7b"             # 7B  — fast and capable
  "qwen2.5-coder:32b"      # 32B — excellent for coding
  "nomic-embed-text"       # embedding model
)

# --- Step 0: Precondition — macOS 14+ (via ucc_target) ------
_observe_macos_prereq() {
  [[ "$MACOS_MAJOR" -ge 14 ]] && echo "supported" || echo "unsupported"
}
_fail_macos_prereq() {
  log_warn "Ollama requires macOS 14 (Sonoma) or later — current: macOS $MACOS_MAJOR"
  return 1  # permanent failure — cannot install on this OS version
}

ucc_target \
  --name    "macos-14-precondition" \
  --observe _observe_macos_prereq \
  --desired "supported" \
  --install _fail_macos_prereq

# Abort if precondition not met
[[ "$MACOS_MAJOR" -ge 14 ]] || { ucc_summary "05-ollama"; exit 0; }

# --- Ollama binary ------------------------------------------
_observe_ollama() {
  is_installed ollama && echo "installed" || echo "absent"
}

_install_ollama() {
  # Prefer official installer (supports both ARM and Intel)
  curl -fsSL https://ollama.com/install.sh | sh
}

_update_ollama() {
  # Re-run official installer — it handles upgrades
  curl -fsSL https://ollama.com/install.sh | sh
}

ucc_target \
  --name    "ollama" \
  --observe _observe_ollama \
  --desired "installed" \
  --install _install_ollama \
  --update  _update_ollama

# --- Ollama service -----------------------------------------
_observe_ollama_service() {
  curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && echo "running" || echo "stopped"
}

_start_ollama_service() {
  if is_installed brew && brew list ollama &>/dev/null 2>&1; then
    brew services start ollama
  else
    # Fallback: start in background
    nohup ollama serve >/tmp/ollama.log 2>&1 &
  fi
  sleep 5
}

ucc_target \
  --name    "ollama-service" \
  --observe _observe_ollama_service \
  --desired "running" \
  --install _start_ollama_service

# --- API health check ---------------------------------------
if [[ "$UCC_DRY_RUN" != "1" ]]; then
  _observe_ollama_api() {
    curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && echo "ok" || echo "unreachable"
  }
  if [[ "$(_observe_ollama_api)" != "ok" ]]; then
    log_warn "Ollama API not responding at http://127.0.0.1:11434 — models will not be pulled"
    ucc_summary "05-ollama"
    exit 1
  fi
  log_info "Ollama API health check: ok"
fi

# --- Pull models --------------------------------------------
for model in "${MODELS[@]}"; do
  _name="ollama-model-${model//:/-}"

  eval "_observe_model_${_name//[^a-zA-Z0-9_]/_}() {
    ollama_model_present '${model}' && echo 'present' || echo 'absent'
  }"
  eval "_pull_model_${_name//[^a-zA-Z0-9_]/_}() {
    log_info 'Pulling model: ${model}'
    ollama pull '${model}'
  }"

  ucc_target \
    --name    "$_name" \
    --observe "_observe_model_${_name//[^a-zA-Z0-9_]/_}" \
    --desired "present" \
    --install "_pull_model_${_name//[^a-zA-Z0-9_]/_}" \
    --update  "_pull_model_${_name//[^a-zA-Z0-9_]/_}"
done

log_info "Ollama API  → http://127.0.0.1:11434"
log_info "Test with   → ollama run llama3.2"

ucc_summary "05-ollama"
