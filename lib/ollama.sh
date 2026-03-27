#!/usr/bin/env bash
# lib/ollama.sh — Ollama software + model pull targets
# Sourced by components/ollama.sh

# Usage: run_ollama_from_yaml <cfg_dir> <yaml_path>
# Returns 1 if host precondition fails or API is unreachable (models not pulled).
run_ollama_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local _OLLAMA_MACOS_MIN _OLLAMA_INSTALLER_URL _OLLAMA_API_HOST _OLLAMA_API_PORT _OLLAMA_LOG
  _OLLAMA_MACOS_MIN="$(    yaml_get "$cfg_dir" "$yaml" macos_min_version    14)"
  _OLLAMA_INSTALLER_URL="$(yaml_get "$cfg_dir" "$yaml" installer_url        "https://ollama.com/install.sh")"
  _OLLAMA_API_HOST="$(     yaml_get "$cfg_dir" "$yaml" api_host             "127.0.0.1")"
  _OLLAMA_API_PORT="$(     yaml_get "$cfg_dir" "$yaml" api_port             "11434")"
  _OLLAMA_LOG="$(          yaml_get "$cfg_dir" "$yaml" log_file             "/tmp/ollama.log")"

  local MACOS_MAJOR=0
  [[ "${HOST_PLATFORM:-macos}" == "macos" ]] && MACOS_MAJOR="$(sw_vers -productVersion | awk -F. '{print $1}')"

  # ---- Step 0: host precondition ----
  _observe_host_prereq() {
    if [[ "${HOST_PLATFORM:-unknown}" == "macos" && "$MACOS_MAJOR" -ge "$_OLLAMA_MACOS_MIN" ]]; then
      ucc_asm_config_state "supported"
    elif [[ "${HOST_PLATFORM:-unknown}" == "linux" || "${HOST_PLATFORM:-unknown}" == "wsl" ]]; then
      ucc_asm_config_state "supported"
    else
      ucc_asm_config_state "absent"
    fi
  }
  _evidence_host_prereq() {
    if [[ "${HOST_PLATFORM:-unknown}" == "macos" ]]; then
      printf 'platform=%s  version=%s' "${HOST_PLATFORM:-unknown}" "$(sw_vers -productVersion 2>/dev/null || echo unknown)"
    else
      printf 'platform=%s  kernel=%s' "${HOST_PLATFORM:-unknown}" "$(uname -r 2>/dev/null || echo unknown)"
    fi
  }
  _fail_host_prereq() {
    if [[ "${HOST_PLATFORM:-unknown}" == "macos" ]]; then
      log_warn "Ollama requires macOS ${_OLLAMA_MACOS_MIN}+ — current: macOS $MACOS_MAJOR"
    else
      log_warn "Ollama is not supported on host platform: ${HOST_PLATFORM:-unknown}"
    fi
    return 1
  }

  ucc_target_nonruntime \
    --name    "ollama-host-supported" \
    --observe _observe_host_prereq \
    --evidence _evidence_host_prereq \
    --install _fail_host_prereq

  if [[ "${HOST_PLATFORM:-unknown}" == "macos" ]]; then
    [[ "$MACOS_MAJOR" -ge "$_OLLAMA_MACOS_MIN" ]] || return 1
  elif [[ "${HOST_PLATFORM:-unknown}" != "linux" && "${HOST_PLATFORM:-unknown}" != "wsl" ]]; then
    return 1
  fi

  _observe_ollama() {
    if ! is_installed ollama; then
      ucc_asm_state --installation Absent --runtime NeverStarted \
        --health Unavailable --admin Enabled --dependencies DepsUnknown
      return
    fi

    if curl -fsS "http://${_OLLAMA_API_HOST}:${_OLLAMA_API_PORT}/api/tags" >/dev/null 2>&1; then
      ucc_asm_runtime_desired
    else
      ucc_asm_state --installation Configured --runtime Stopped \
        --health Unavailable --admin Enabled --dependencies DepsDegraded
    fi
  }
  _evidence_ollama() { ucc_eval_evidence_from_yaml "$cfg_dir" "$yaml" "ollama"; }
  _start_ollama() {
    if ! is_installed ollama; then
      curl -fsSL "$_OLLAMA_INSTALLER_URL" | sh || return 1
    fi

    if is_installed brew && brew list ollama &>/dev/null 2>&1; then
      if brew services list 2>/dev/null | awk '$1=="ollama" {print $2}' | grep -q '^started$'; then
        brew services restart ollama
      else
        brew services start ollama
      fi
    else
      pkill -f 'ollama (serve|app)' 2>/dev/null || true
      nohup ollama serve >"$_OLLAMA_LOG" 2>&1 &
    fi

    _ucc_wait_for_runtime_probe "curl -fsS \"http://${_OLLAMA_API_HOST}:${_OLLAMA_API_PORT}/api/tags\" >/dev/null 2>&1"
  }
  _update_ollama() {
    curl -fsSL "$_OLLAMA_INSTALLER_URL" | sh || return 1
    _start_ollama
  }

  ucc_target_service \
    --name    "ollama" \
    --observe _observe_ollama \
    --evidence _evidence_ollama \
    --desired "$(ucc_asm_runtime_desired)" \
    --install _start_ollama \
    --update  _update_ollama

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
