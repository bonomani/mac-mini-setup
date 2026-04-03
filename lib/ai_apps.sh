#!/usr/bin/env bash
# lib/ai_apps.sh — Docker Compose AI stack targets
# Sourced by components/ai-apps.sh

# Return true when the host platform/version supports Ollama.
# Reads macos_min_version from YAML via $CFG_DIR/$YAML_PATH.
ollama_host_supported() {
  local min_major=""
  while IFS=$'\t' read -r -d '' key value; do
    [[ "$key" == "macos_min_version" ]] && min_major="$value"
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" macos_min_version)
  if [[ "${HOST_PLATFORM:-unknown}" == "macos" ]]; then
    [[ "$(sw_vers -productVersion 2>/dev/null | awk -F. '{print $1}')" -ge "${min_major:-0}" ]]
  else
    [[ "${HOST_PLATFORM:-unknown}" == "linux" || "${HOST_PLATFORM_VARIANT:-unknown}" == "wsl2" ]]
  fi
}

# Emit a log_warn explaining why Ollama is unsupported, then return 1.
# Reads macos_min_version from YAML via $CFG_DIR/$YAML_PATH.
ollama_unsupported_warn() {
  local min_major=""
  while IFS=$'\t' read -r -d '' key value; do
    [[ "$key" == "macos_min_version" ]] && min_major="$value"
  done < <(yaml_get_many "$CFG_DIR" "$YAML_PATH" macos_min_version)
  if [[ "${HOST_PLATFORM:-unknown}" == "macos" ]]; then
    log_warn "Ollama requires macOS ${min_major}+ — current: macOS $(sw_vers -productVersion 2>/dev/null || echo unknown)"
  else
    log_warn "Ollama is not supported on host platform: ${HOST_PLATFORM:-unknown}"
  fi
  return 1
}

# Usage: run_ai_apps_from_yaml <cfg_dir> <yaml_path>
run_ai_apps_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  # ---- Precondition: compose template must exist ----
  ucc_yaml_simple_target "$cfg_dir" "$yaml" "ai-apps-template"

  local compose_dir_rel=".ai-stack" compose_file_name="docker-compose.yml"
  local stack_template_rel="stack/docker-compose.yml" stack_marker=""
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      stack.compose_dir) [[ -n "$value" ]] && compose_dir_rel="$value" ;;
      stack.compose_file) [[ -n "$value" ]] && compose_file_name="$value" ;;
      stack.definition_template) [[ -n "$value" ]] && stack_template_rel="$value" ;;
      stack.marker) [[ -n "$value" ]] && stack_marker="$value" ;;
    esac
  done < <(yaml_get_many "$cfg_dir" "$yaml" \
    stack.compose_dir \
    stack.compose_file \
    stack.definition_template \
    stack.marker)

  COMPOSE_DIR="$HOME/${compose_dir_rel}"
  COMPOSE_FILE="$COMPOSE_DIR/${compose_file_name}"
  COMPOSE_MARKER="$stack_marker"

  AI_SERVICES=()
  while IFS= read -r _svc; do [[ -n "$_svc" ]] && AI_SERVICES+=("$_svc"); done \
    < <(yaml_list "$cfg_dir" "$yaml" stack.services)
  STACK_SERVICES="${#AI_SERVICES[@]}"
  STACK_SIGNATURE="$(printf '%s\n' "${AI_SERVICES[@]}" | LC_ALL=C sort | paste -sd, -)"
  STACK_DEFINITION_VALUE="marker=${COMPOSE_MARKER} services=${STACK_SIGNATURE}"
  IMAGE_POLICY="${UIC_PREF_AI_APPS_IMAGE_POLICY:-reuse-local}"
  _AI_APPS_CFG_DIR="$cfg_dir"
  _AI_APPS_TEMPLATE_FILE="$cfg_dir/${stack_template_rel}"
  _AI_APPS_APPLY_SENTINEL="${COMPOSE_DIR}/runs/${UCC_CORRELATION_ID:-manual}.ai-apps-compose.applied"
  export _AI_SERVICE_IMAGE_CACHE="" _AI_IMAGE_VERSION_CACHE="" _AI_IMAGE_DIGEST_CACHE=""
  local _AI_CACHE_VALUE="" _AI_SERVICE_IMAGE_VALUE="" _AI_IMAGE_VERSION_VALUE="" _AI_IMAGE_DIGEST_VALUE=""

  _ai_cache_get() {
    local var_name="$1" key="$2" cache_key="" value=""
    _AI_CACHE_VALUE=""
    while IFS=$'\t' read -r cache_key value; do
      [[ -n "$cache_key" ]] || continue
      if [[ "$cache_key" == "$key" ]]; then
        _AI_CACHE_VALUE="$value"
        return 0
      fi
    done <<< "${!var_name}"
    return 1
  }

  _ai_cache_put() {
    local var_name="$1" key="$2" value="$3"
    printf -v "$var_name" '%s%s\t%s\n' "${!var_name}" "$key" "$value"
  }

  _ai_target_for_service() {
    printf '%s-runtime' "$1"
  }

  _ai_compose_source() {
    if [[ -f "$COMPOSE_FILE" ]]; then
      printf '%s' "$COMPOSE_FILE"
    else
      printf '%s' "$_AI_APPS_TEMPLATE_FILE"
    fi
  }

  _ai_service_label() {
    local svc="$1" target name
    target="$(_ai_target_for_service "$svc")"
    while IFS=$'\t' read -r name _url _note; do
      [[ -n "$name" ]] && {
        printf '%s' "$name"
        return 0
      }
    done < <(yaml_records "$cfg_dir" "$yaml" "targets.${target}.endpoints" name url note)
    printf '%s' "$svc"
  }

  _ai_probe_service_image() {
    local svc="$1" image=""
    image="$(docker inspect --format '{{.Config.Image}}' "$svc" 2>/dev/null || true)"
    if [[ -z "$image" ]]; then
      image="$(python3 - "$(_ai_compose_source)" "$svc" <<'PY' 2>/dev/null
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
service_name = sys.argv[2]
if not path.exists():
    raise SystemExit(0)

data = yaml.safe_load(path.read_text()) or {}
service = (data.get("services") or {}).get(service_name) or {}
image = service.get("image", "")
if image:
    print(image)
PY
)"
    fi
    printf '%s' "$image"
  }

  _ai_service_image() {
    local svc="$1" image=""
    if _ai_cache_get _AI_SERVICE_IMAGE_CACHE "$svc"; then
      _AI_SERVICE_IMAGE_VALUE="$_AI_CACHE_VALUE"
      return 0
    fi
    image="$(_ai_probe_service_image "$svc")"
    _AI_SERVICE_IMAGE_VALUE="$image"
  }

  _ai_service_image_tag() {
    local image="$1" tail
    [[ -n "$image" ]] || return 0
    tail="${image##*/}"
    tail="${tail%%@*}"
    if [[ "$tail" == *:* ]]; then
      printf '%s' "${tail##*:}"
    else
      printf 'latest'
    fi
  }

  _ai_is_mutable_ref() {
    case "$1" in
      latest|main|master|edge|nightly|dev) return 0 ;;
      *) return 1 ;;
    esac
  }

  _ai_normalize_version() {
    local value="$1"
    [[ "$value" =~ ^v[0-9] ]] && value="${value#v}"
    printf '%s' "$value"
  }

  _ai_probe_image_metadata() {
    local image="$1" version="" label_schema_version="" digest="" short=""
    [[ -n "$image" ]] || return 0
    IFS='|' read -r version label_schema_version digest <<EOF
$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.version" }}|{{ index .Config.Labels "org.label-schema.version" }}|{{index .RepoDigests 0}}' "$image" 2>/dev/null || true)
EOF
    [[ "$version" == "<no value>" ]] && version=""
    if [[ -z "$version" ]]; then
      version="$label_schema_version"
    fi
    [[ "$version" == "<no value>" ]] && version=""
    digest="${digest##*@}"
    if [[ "$digest" == sha256:* ]]; then
      short="${digest#sha256:}"
      short="${short:0:12}"
      digest="sha256:${short}"
    else
      digest=""
    fi
    printf '%s\t%s\n' "$version" "$digest"
  }

  _ai_fill_image_metadata_cache() {
    local image="$1" metadata="" version="" digest=""
    [[ -n "$image" ]] || return 0
    metadata="$(_ai_probe_image_metadata "$image")"
    IFS=$'\t' read -r version digest <<EOF
$metadata
EOF
    _ai_cache_put _AI_IMAGE_VERSION_CACHE "$image" "$version"
    _ai_cache_put _AI_IMAGE_DIGEST_CACHE "$image" "$digest"
  }

  _ai_service_image_label_version() {
    local image="$1"
    [[ -n "$image" ]] || return 0
    if ! _ai_cache_get _AI_IMAGE_VERSION_CACHE "$image"; then
      _ai_fill_image_metadata_cache "$image"
      _ai_cache_get _AI_IMAGE_VERSION_CACHE "$image" || true
    fi
    _AI_IMAGE_VERSION_VALUE="$_AI_CACHE_VALUE"
  }

  _ai_service_image_digest() {
    local image="$1"
    [[ -n "$image" ]] || return 0
    if ! _ai_cache_get _AI_IMAGE_DIGEST_CACHE "$image"; then
      _ai_fill_image_metadata_cache "$image"
      _ai_cache_get _AI_IMAGE_DIGEST_CACHE "$image" || true
    fi
    _AI_IMAGE_DIGEST_VALUE="$_AI_CACHE_VALUE"
  }

  _ai_warm_metadata_cache() {
    local svc="" image=""
    export _AI_SERVICE_IMAGE_CACHE="" _AI_IMAGE_VERSION_CACHE="" _AI_IMAGE_DIGEST_CACHE=""
    for svc in "${AI_SERVICES[@]}"; do
      image="$(_ai_probe_service_image "$svc")"
      _ai_cache_put _AI_SERVICE_IMAGE_CACHE "$svc" "$image"
      [[ -n "$image" ]] || continue
      _ai_cache_get _AI_IMAGE_VERSION_CACHE "$image" || _ai_fill_image_metadata_cache "$image"
    done
  }

  _ai_service_runtime_version() {
    local svc="$1" image tag version
    _ai_service_image "$svc"
    image="$_AI_SERVICE_IMAGE_VALUE"
    tag="$(_ai_service_image_tag "$image")"
    _ai_service_image_label_version "$image"
    version="$_AI_IMAGE_VERSION_VALUE"
    [[ -n "$version" ]] && version="$(_ai_normalize_version "$version")"
    [[ -n "$tag" ]] && tag="$(_ai_normalize_version "$tag")"

    if [[ -n "$version" ]] && ! _ai_is_mutable_ref "$version"; then
      printf '%s' "$version"
      return
    fi

    if [[ -n "$tag" ]] && ! _ai_is_mutable_ref "$tag"; then
      printf '%s' "$tag"
    fi
  }

  _ai_service_runtime_digest() {
    local svc="$1" image tag version digest
    _ai_service_image "$svc"
    image="$_AI_SERVICE_IMAGE_VALUE"
    tag="$(_ai_service_image_tag "$image")"
    _ai_service_image_label_version "$image"
    version="$_AI_IMAGE_VERSION_VALUE"
    _ai_service_image_digest "$image"
    digest="$_AI_IMAGE_DIGEST_VALUE"
    [[ -n "$version" ]] && version="$(_ai_normalize_version "$version")"
    [[ -n "$tag" ]] && tag="$(_ai_normalize_version "$tag")"

    [[ -n "$digest" ]] || return 0
    if [[ -n "$version" ]] && ! _ai_is_mutable_ref "$version" && [[ -n "$tag" ]] && _ai_is_mutable_ref "$tag"; then
      printf '%s' "$digest"
      return
    fi
    if [[ -z "$version" ]]; then
      printf '%s' "$digest"
      return
    fi
    if _ai_is_mutable_ref "$version"; then
      printf '%s' "$digest"
    fi
  }

  _ai_service_runtime_ref() {
    local svc="$1" image tag version
    _ai_service_image "$svc"
    image="$_AI_SERVICE_IMAGE_VALUE"
    tag="$(_ai_service_image_tag "$image")"
    _ai_service_image_label_version "$image"
    version="$_AI_IMAGE_VERSION_VALUE"
    [[ -n "$version" ]] && version="$(_ai_normalize_version "$version")"
    [[ -n "$tag" ]] && tag="$(_ai_normalize_version "$tag")"

    [[ -n "$tag" ]] || return 0
    if [[ -n "$version" ]] && ! _ai_is_mutable_ref "$version"; then
      [[ "$tag" != "$version" ]] && printf '%s' "$tag"
      return
    fi
    printf '%s' "$tag"
  }

  AI_APP_LABELS=()
  for _svc in "${AI_SERVICES[@]}"; do
    AI_APP_LABELS+=("$(_ai_service_label "$_svc")")
  done
  AI_APP_LABEL_LIST=""
  for _svc in "${AI_APP_LABELS[@]}"; do
    [[ -n "$AI_APP_LABEL_LIST" ]] && AI_APP_LABEL_LIST+=", "
    AI_APP_LABEL_LIST+="$_svc"
  done

  _ai_stack_signature() {
    local file="$1"
    python3 - "$file" <<'PY' 2>/dev/null
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
if not path.exists():
    raise SystemExit(1)

data = yaml.safe_load(path.read_text()) or {}
services = data.get("services")
if not isinstance(services, dict):
    raise SystemExit(1)

print(",".join(sorted(services.keys())))
PY
  }

  # ---- Ollama scalars — all values come from YAML ----
  local _OLLAMA_INSTALLER_URL _OLLAMA_BREW_SERVICE_NAME
  local _OLLAMA_API_HOST _OLLAMA_API_PORT _OLLAMA_API_TAGS_PATH _OLLAMA_LOG
  local _OLLAMA_STOP_PATTERN _OLLAMA_START_CMD _OLLAMA_API_URL _OLLAMA_HOST_SUPPORTED_CMD
  while IFS=$'\t' read -r -d '' key value; do
    [[ -n "$value" ]] || continue
    case "$key" in
      ollama_installer_url) _OLLAMA_INSTALLER_URL="$value" ;;
      brew_service_name) _OLLAMA_BREW_SERVICE_NAME="$value" ;;
      api_host) _OLLAMA_API_HOST="$value" ;;
      api_port) _OLLAMA_API_PORT="$value" ;;
      api_tags_path) _OLLAMA_API_TAGS_PATH="$value" ;;
      log_file) _OLLAMA_LOG="$value" ;;
      fallback_stop_pattern) _OLLAMA_STOP_PATTERN="$value" ;;
      fallback_start_cmd) _OLLAMA_START_CMD="$value" ;;
    esac
  done < <(yaml_get_many "$cfg_dir" "$yaml" \
    ollama_installer_url \
    brew_service_name \
    api_host \
    api_port \
    api_tags_path \
    log_file \
    fallback_stop_pattern \
    fallback_start_cmd)
  _OLLAMA_API_URL="http://${_OLLAMA_API_HOST}:${_OLLAMA_API_PORT}${_OLLAMA_API_TAGS_PATH}"
  # Warn if ollama exists outside brew but brew could manage it
  if is_installed brew && is_installed ollama \
     && ! brew list "$_OLLAMA_BREW_SERVICE_NAME" &>/dev/null 2>&1 \
     && [[ "${UIC_PREF_PREFERRED_DRIVER_POLICY:-warn}" != "ignore" ]]; then
    log_warn "Ollama installed outside brew (app/installer). To migrate: brew install ollama"
  fi

  _start_ollama() {
    if ! is_installed ollama; then
      curl -fsSL "$_OLLAMA_INSTALLER_URL" | sh || return 1
    fi

    if is_installed brew && brew list "$_OLLAMA_BREW_SERVICE_NAME" &>/dev/null 2>&1; then
      if brew_service_is_started "$_OLLAMA_BREW_SERVICE_NAME"; then
        brew services restart "$_OLLAMA_BREW_SERVICE_NAME"
      else
        brew services start "$_OLLAMA_BREW_SERVICE_NAME"
      fi
    elif [[ "${HOST_PLATFORM:-}" == "macos" && -d "/Applications/Ollama.app" ]]; then
      # macOS: start daemon via app in background (no GUI window)
      open -gja Ollama
      sleep 3  # give the app time to launch the daemon process
    else
      # Linux/WSL2: start ollama serve directly
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

  # ---- Ollama API health check (guard before model pulls) ----
  # Skip if ollama targets are not in the selection
  if [[ "${UCC_TARGET_SET:-}" == *"ollama|"* && "$UCC_DRY_RUN" != "1" ]]; then
    if ! curl -fsS "$_OLLAMA_API_URL" >/dev/null 2>&1; then
      log_warn "Ollama API not responding at $_OLLAMA_API_URL — models will not be pulled"
      return 0
    fi
  fi

  load_ollama_models_from_yaml "$cfg_dir" "$yaml" "${UIC_PREF_OLLAMA_MODEL_AUTOPULL:-none}"

  # Abort if Docker still not running after the docker component runtime target
  # has had a chance to converge.
  docker info &>/dev/null 2>&1 || {
    log_warn "Docker not running — skipping AI stack"
    return 1
  }
  _ai_warm_metadata_cache

  # ---- Compose file ----
  _observe_compose_file() {
    local actual_sig=""
    [[ -f "$COMPOSE_FILE" ]] || {
      ucc_asm_config_state "absent" "$STACK_DEFINITION_VALUE"
      return
    }

    actual_sig="$(_ai_stack_signature "$COMPOSE_FILE" || true)"
    if [[ -z "$actual_sig" ]]; then
      ucc_asm_config_state "needs-update" "$STACK_DEFINITION_VALUE"
      return
    fi

    if grep -qF "$COMPOSE_MARKER" "$COMPOSE_FILE" 2>/dev/null && [[ "$actual_sig" == "$STACK_SIGNATURE" ]]; then
      ucc_asm_config_state "$STACK_DEFINITION_VALUE" "$STACK_DEFINITION_VALUE"
    else
      ucc_asm_config_state "marker=$(grep -qF "$COMPOSE_MARKER" "$COMPOSE_FILE" 2>/dev/null && echo present || echo missing) services=${actual_sig}" "$STACK_DEFINITION_VALUE"
    fi
  }
  _evidence_compose_file() {
    local actual_sig=""
    actual_sig="$(_ai_stack_signature "$COMPOSE_FILE" || true)"
    printf 'path=%s  apps=%s' "$COMPOSE_FILE" "${AI_APP_LABEL_LIST:-${actual_sig:-unknown}}"
  }
  _write_compose_file() {
    ucc_run mkdir -p "$COMPOSE_DIR"
    ucc_run cp "$_AI_APPS_CFG_DIR/${stack_template_rel}" "$COMPOSE_FILE"
  }

  ucc_target --name "ai-stack-compose-file" \
    --profile parametric \
    --observe _observe_compose_file \
    --evidence _evidence_compose_file \
    --desired "$(ucc_asm_config_desired "$STACK_DEFINITION_VALUE")" \
    --install _write_compose_file --update _write_compose_file

  # ---- App runtimes ----
  _ai_container_is_compose_managed() {
    local name="$1" project=""
    project="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "$name" 2>/dev/null || true)"
    [[ -n "$project" && "$project" != "<no value>" ]]
  }

  _remove_legacy_containers() {
    local name
    for name in "${AI_SERVICES[@]}"; do
      if docker inspect "$name" &>/dev/null 2>&1 && ! _ai_container_is_compose_managed "$name"; then
        log_info "Removing legacy container: $name"
        docker rm -f "$name" >/dev/null 2>&1 || true
      fi
    done
  }
  _ai_apply_compose_runtime() {
    if [[ -f "$_AI_APPS_APPLY_SENTINEL" ]]; then
      return 0
    fi
    _remove_legacy_containers
    if [[ "$IMAGE_POLICY" == "always-pull" ]]; then
      ucc_run docker compose -f "$COMPOSE_FILE" pull
    fi
    ucc_run docker compose -f "$COMPOSE_FILE" up -d
    _ai_warm_metadata_cache
    mkdir -p "$(dirname "$_AI_APPS_APPLY_SENTINEL")"
    : > "$_AI_APPS_APPLY_SENTINEL"
  }

  local svc target
  for svc in "${AI_SERVICES[@]}"; do
    target="$(_ai_target_for_service "$svc")"
    ucc_yaml_runtime_target "$cfg_dir" "$yaml" "$target"
  done
}
