#!/usr/bin/env bash
# lib/ollama.sh — Ollama software + model pull targets
# Sourced by components/ollama.sh

# Usage: run_ollama_from_yaml <cfg_dir> <yaml_path>
# Returns 1 if host precondition fails or API is unreachable (models not pulled).
run_ollama_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local _OLLAMA_INSTALLER_URL _OLLAMA_BREW_SERVICE_NAME
  local _OLLAMA_API_HOST _OLLAMA_API_PORT _OLLAMA_API_TAGS_PATH _OLLAMA_LOG
  local _OLLAMA_STOP_PATTERN _OLLAMA_START_CMD _OLLAMA_API_URL _OLLAMA_HOST_SUPPORTED_CMD
  _OLLAMA_INSTALLER_URL="https://ollama.com/install.sh"
  _OLLAMA_BREW_SERVICE_NAME="ollama"
  _OLLAMA_API_HOST="127.0.0.1"
  _OLLAMA_API_PORT="11434"
  _OLLAMA_API_TAGS_PATH="/api/tags"
  _OLLAMA_LOG="/tmp/ollama.log"
  _OLLAMA_STOP_PATTERN="ollama (serve|app)"
  _OLLAMA_START_CMD="ollama serve"
  while IFS=$'\t' read -r -d '' key value; do
    [[ -n "$value" ]] || continue
    case "$key" in
      installer_url) _OLLAMA_INSTALLER_URL="$value" ;;
      brew_service_name) _OLLAMA_BREW_SERVICE_NAME="$value" ;;
      api_host) _OLLAMA_API_HOST="$value" ;;
      api_port) _OLLAMA_API_PORT="$value" ;;
      api_tags_path) _OLLAMA_API_TAGS_PATH="$value" ;;
      log_file) _OLLAMA_LOG="$value" ;;
      fallback_stop_pattern) _OLLAMA_STOP_PATTERN="$value" ;;
      fallback_start_cmd) _OLLAMA_START_CMD="$value" ;;
    esac
  done < <(yaml_get_many "$cfg_dir" "$yaml" \
    installer_url \
    brew_service_name \
    api_host \
    api_port \
    api_tags_path \
    log_file \
    fallback_stop_pattern \
    fallback_start_cmd)
  _OLLAMA_API_URL="http://${_OLLAMA_API_HOST}:${_OLLAMA_API_PORT}${_OLLAMA_API_TAGS_PATH}"
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      oracle.configured) _OLLAMA_HOST_SUPPORTED_CMD="$value" ;;
    esac
  done < <(yaml_target_get_many "$cfg_dir" "$yaml" "ollama-host-supported" "oracle.configured")

  ucc_yaml_simple_target "$cfg_dir" "$yaml" "ollama-host-supported"

  local CFG_DIR="$cfg_dir" YAML_PATH="$yaml" TARGET_NAME="ollama-host-supported"
  if [[ -n "$_OLLAMA_HOST_SUPPORTED_CMD" ]] && ! eval "$_OLLAMA_HOST_SUPPORTED_CMD" >/dev/null 2>&1; then
    return 1
  fi

  _start_ollama() {
    if ! is_installed ollama; then
      curl -fsSL "$_OLLAMA_INSTALLER_URL" | sh || return 1
    fi

    if is_installed brew && brew list "$_OLLAMA_BREW_SERVICE_NAME" &>/dev/null 2>&1; then
      if brew services list 2>/dev/null | awk -v svc="$_OLLAMA_BREW_SERVICE_NAME" '$1==svc {print $2}' | grep -q '^started$'; then
        brew services restart "$_OLLAMA_BREW_SERVICE_NAME"
      else
        brew services start "$_OLLAMA_BREW_SERVICE_NAME"
      fi
    else
      pkill -f "$_OLLAMA_STOP_PATTERN" 2>/dev/null || true
      nohup bash -lc "$_OLLAMA_START_CMD" >"$_OLLAMA_LOG" 2>&1 &
    fi

    _ucc_wait_for_runtime_probe "curl -fsS \"$_OLLAMA_API_URL\" >/dev/null 2>&1"
  }
  _update_ollama() {
    curl -fsSL "$_OLLAMA_INSTALLER_URL" | sh || return 1
    _start_ollama
  }

  ucc_yaml_runtime_target "$cfg_dir" "$yaml" "ollama" _start_ollama _update_ollama

  # ---- API health check (guard before model pulls) ----
  if [[ "$UCC_DRY_RUN" != "1" ]]; then
    if ! curl -fsS "$_OLLAMA_API_URL" >/dev/null 2>&1; then
      log_warn "Ollama API not responding at $_OLLAMA_API_URL — models will not be pulled"
      return 1
    fi
  fi

  # ---- Pull models (gated by UIC preference ollama-model-autopull) ----
  # Default = none (safe: no automatic downloads)
  # Override in ~/.ai-stack/preferences.env:  OLLAMA_MODEL_AUTOPULL=small|medium|large
  load_ollama_models_from_yaml "$cfg_dir" "$yaml" "${UIC_PREF_OLLAMA_MODEL_AUTOPULL:-none}"
}
