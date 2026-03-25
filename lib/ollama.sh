#!/usr/bin/env bash
# lib/ollama.sh — Ollama install + service + model pull targets
# Sourced by components/ollama.sh

# Usage: run_ollama_from_yaml <cfg_dir> <yaml_path>
# Returns 1 if macOS precondition fails or API is unreachable (models not pulled).
run_ollama_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local _OLLAMA_MACOS_MIN _OLLAMA_INSTALLER_URL _OLLAMA_API_HOST _OLLAMA_API_PORT _OLLAMA_LOG
  _OLLAMA_MACOS_MIN="$(    yaml_get "$cfg_dir" "$yaml" macos_min_version    14)"
  _OLLAMA_INSTALLER_URL="$(yaml_get "$cfg_dir" "$yaml" installer_url        "https://ollama.com/install.sh")"
  _OLLAMA_API_HOST="$(     yaml_get "$cfg_dir" "$yaml" api_host             "127.0.0.1")"
  _OLLAMA_API_PORT="$(     yaml_get "$cfg_dir" "$yaml" api_port             "11434")"
  _OLLAMA_LOG="$(          yaml_get "$cfg_dir" "$yaml" log_file             "/tmp/ollama.log")"

  local MACOS_MAJOR
  MACOS_MAJOR="$(sw_vers -productVersion | awk -F. '{print $1}')"

  # ---- Step 0: macOS version precondition ----
  _observe_macos_prereq() {
    if [[ "$MACOS_MAJOR" -ge "$_OLLAMA_MACOS_MIN" ]]; then
      ucc_asm_config_state "supported"
    else
      ucc_asm_config_state "absent"
    fi
  }
  _evidence_macos_prereq() { printf 'macos=%s' "$(sw_vers -productVersion 2>/dev/null || echo unknown)"; }
  _fail_macos_prereq() {
    log_warn "Ollama requires macOS ${_OLLAMA_MACOS_MIN}+ — current: macOS $MACOS_MAJOR"
    return 1
  }

  ucc_target_nonruntime \
    --name    "macos-precondition" \
    --observe _observe_macos_prereq \
    --evidence _evidence_macos_prereq \
    --install _fail_macos_prereq

  [[ "$MACOS_MAJOR" -ge "$_OLLAMA_MACOS_MIN" ]] || return 1

  # ---- Ollama binary ----
  _observe_ollama() { ucc_asm_package_state "$(is_installed ollama && ollama --version 2>/dev/null | awk '{print $NF}' || echo "absent")"; }
  _evidence_ollama() { ucc_eval_evidence_from_yaml "$cfg_dir" "$yaml" "ollama"; }
  _install_ollama() { curl -fsSL "$_OLLAMA_INSTALLER_URL" | sh; }
  _update_ollama()  { curl -fsSL "$_OLLAMA_INSTALLER_URL" | sh; }

  ucc_target_nonruntime \
    --name    "ollama" \
    --observe _observe_ollama \
    --evidence _evidence_ollama \
    --install _install_ollama \
    --update  _update_ollama

  # ---- Ollama service ----
  _observe_ollama_service() {
    if ! is_installed ollama; then
      ucc_asm_state --installation Absent --runtime NeverStarted \
        --health Unavailable --admin Enabled --dependencies DepsUnknown
      return
    fi
    if curl -fsS "http://${_OLLAMA_API_HOST}:${_OLLAMA_API_PORT}/api/tags" >/dev/null 2>&1; then
      ucc_asm_runtime_desired
    else
      ucc_asm_state --installation Installed --runtime Stopped \
        --health Unavailable --admin Enabled --dependencies DepsDegraded
    fi
  }
  _evidence_ollama_service() { ucc_eval_evidence_from_yaml "$cfg_dir" "$yaml" "ollama-service"; }
  _start_ollama_service() {
    if is_installed brew && brew list ollama &>/dev/null 2>&1; then
      brew services start ollama
    else
      nohup ollama serve >"$_OLLAMA_LOG" 2>&1 &
    fi
    sleep 5
  }

  ucc_target_service \
    --name    "ollama-service" \
    --observe _observe_ollama_service \
    --evidence _evidence_ollama_service \
    --desired "$(ucc_asm_runtime_desired)" \
    --install _start_ollama_service

  # ---- API health check (guard before model pulls) ----
  if [[ "$UCC_DRY_RUN" != "1" ]]; then
    if ! curl -fsS "http://${_OLLAMA_API_HOST}:${_OLLAMA_API_PORT}/api/tags" >/dev/null 2>&1; then
      log_warn "Ollama API not responding at http://${_OLLAMA_API_HOST}:${_OLLAMA_API_PORT} — models will not be pulled"
      return 1
    fi
  fi

  # ---- Pull models (gated by UIC preference ollama-model-autopull) ----
  # Default = none (safe: no automatic downloads)
  # Override in ~/.ai-stack/preferences.env:  OLLAMA_MODEL_AUTOPULL=small|medium|large
  load_ollama_models_from_yaml "$cfg_dir" "$yaml" "${UIC_PREF_OLLAMA_MODEL_AUTOPULL:-none}"
}
