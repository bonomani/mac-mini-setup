#!/usr/bin/env bash
# Component: Ollama — local LLMs via Apple Metal
# BGS: UCC + Basic  (bgs/SUITE.md §4.5 + §4.3)
#
# BISS: Axis A = UCC (state convergence — ollama binary + service running + models present)
#       Axis B = Basic
# Boundary: local filesystem · network (official installer + model pulls) · HTTP API (port 11434) · macOS launchd

MACOS_MAJOR="$(sw_vers -productVersion | awk -F. '{print $1}')"

# UIC preference: ollama-model-autopull (safe default=none)
# small  = models ≤ 3B   (fast, low memory)
# medium = models ≤ 8B   (balanced)
# large  = all models    (requires ~60 GB free disk)
_OLLAMA_AUTOPULL="${UIC_PREF_OLLAMA_MODEL_AUTOPULL:-none}"

MODELS_SMALL=(
  "llama3.2"               # 3B  — fast, everyday tasks
  "nomic-embed-text"       # embedding (small)
)
MODELS_MEDIUM=(
  "qwen3:latest"           # reasoning, varies
  "llama3.1:8b"            # 8B  — good balance
  "mistral:7b"             # 7B  — fast and capable
)
MODELS_LARGE=(
  "qwen2.5-coder:32b"      # 32B — excellent for coding
  "llama3.1:70b"           # 70B — high quality (~40 GB)
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

# --- Pull models (gated by UIC preference ollama-model-autopull) ----
# Default = none (safe: no automatic downloads)
# Override in ~/.ai-stack/preferences.env:  OLLAMA_MODEL_AUTOPULL=small|medium|large
_ollama_pull_set() {
  local models=("$@")
  local model _name _fn
  for model in "${models[@]}"; do
    _name="ollama-model-${model//:/-}"
    _fn="${_name//[^a-zA-Z0-9_]/_}"
    eval "_observe_${_fn}() { ollama_model_present '${model}' && echo 'present' || echo 'absent'; }"
    eval "_pull_${_fn}()    { log_info 'Pulling model: ${model}'; ucc_run ollama pull '${model}'; }"
    ucc_target \
      --name    "$_name" \
      --observe "_observe_${_fn}" \
      --desired "present" \
      --install "_pull_${_fn}" \
      --update  "_pull_${_fn}"
  done
}

case "$_OLLAMA_AUTOPULL" in
  small)
    log_info "ollama-model-autopull=small — pulling models ≤ 3B"
    _ollama_pull_set "${MODELS_SMALL[@]}"
    ;;
  medium)
    log_info "ollama-model-autopull=medium — pulling models ≤ 8B"
    _ollama_pull_set "${MODELS_SMALL[@]}" "${MODELS_MEDIUM[@]}"
    ;;
  large)
    log_info "ollama-model-autopull=large — pulling all models (may take a long time)"
    _ollama_pull_set "${MODELS_SMALL[@]}" "${MODELS_MEDIUM[@]}" "${MODELS_LARGE[@]}"
    ;;
  none|*)
    ;;
esac

log_info "Ollama API → http://127.0.0.1:11434  (pull models: ollama pull <model>)"

ucc_summary "05-ollama"
