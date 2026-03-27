#!/usr/bin/env bash
# lib/ai_apps.sh — Docker Compose AI stack targets
# Sourced by components/ai-apps.sh

# Usage: run_ai_apps_from_yaml <cfg_dir> <yaml_path>
run_ai_apps_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  local compose_dir_rel compose_file_name stack_template_rel
  compose_dir_rel="$(yaml_get "$cfg_dir" "$yaml" stack.compose_dir)"
  [[ -n "$compose_dir_rel" ]] || compose_dir_rel="$(yaml_get "$cfg_dir" "$yaml" compose_dir .ai-stack)"
  compose_file_name="$(yaml_get "$cfg_dir" "$yaml" stack.compose_file docker-compose.yml)"
  stack_template_rel="$(yaml_get "$cfg_dir" "$yaml" stack.definition_template stack/docker-compose.yml)"

  COMPOSE_DIR="$HOME/${compose_dir_rel}"
  COMPOSE_FILE="$COMPOSE_DIR/${compose_file_name}"
  COMPOSE_MARKER="$(yaml_get "$cfg_dir" "$yaml" stack.marker)"
  [[ -n "$COMPOSE_MARKER" ]] || COMPOSE_MARKER="$(yaml_get "$cfg_dir" "$yaml" compose_marker "")"

  AI_SERVICES=()
  while IFS= read -r _svc; do [[ -n "$_svc" ]] && AI_SERVICES+=("$_svc"); done \
    < <(yaml_list "$cfg_dir" "$yaml" stack.services)
  if [[ ${#AI_SERVICES[@]} -eq 0 ]]; then
    while IFS= read -r _svc; do [[ -n "$_svc" ]] && AI_SERVICES+=("$_svc"); done \
      < <(yaml_list "$cfg_dir" "$yaml" services)
  fi
  STACK_SERVICES="${#AI_SERVICES[@]}"
  STACK_SIGNATURE="$(printf '%s\n' "${AI_SERVICES[@]}" | LC_ALL=C sort | paste -sd, -)"
  STACK_DEFINITION_VALUE="marker=${COMPOSE_MARKER} services=${STACK_SIGNATURE}"
  IMAGE_POLICY="${UIC_PREF_AI_APPS_IMAGE_POLICY:-reuse-local}"
  _AI_APPS_CFG_DIR="$cfg_dir"
  _AI_APPS_TEMPLATE_FILE="$cfg_dir/${stack_template_rel}"

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

  _ai_service_image() {
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

  _ai_service_image_label_version() {
    local image="$1" version=""
    [[ -n "$image" ]] || return 0
    version="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' "$image" 2>/dev/null || true)"
    [[ "$version" == "<no value>" ]] && version=""
    if [[ -z "$version" ]]; then
      version="$(docker image inspect --format '{{ index .Config.Labels "org.label-schema.version" }}' "$image" 2>/dev/null || true)"
      [[ "$version" == "<no value>" ]] && version=""
    fi
    printf '%s' "$version"
  }

  _ai_service_image_digest() {
    local image="$1" digest="" short=""
    [[ -n "$image" ]] || return 0
    digest="$(docker image inspect --format '{{index .RepoDigests 0}}' "$image" 2>/dev/null || true)"
    digest="${digest##*@}"
    [[ "$digest" == sha256:* ]] || return 0
    short="${digest#sha256:}"
    short="${short:0:12}"
    printf 'sha256:%s' "$short"
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

  # Abort if Docker still not running after the docker component runtime target
  # has had a chance to converge.
  docker info &>/dev/null 2>&1 || {
    log_warn "Docker not running — skipping AI stack"
    return 1
  }

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
  _observe_service_runtime() {
    local svc="$1" target="$2" state runtime_cmd
    [[ -f "$COMPOSE_FILE" ]] || {
      ucc_asm_state --installation Absent --runtime Stopped \
        --health Unavailable --admin Enabled --dependencies DepsFailed
      return
    }

    state="$(docker inspect --format '{{.State.Status}}' "$svc" 2>/dev/null || true)"
    if [[ -z "$state" ]]; then
      ucc_asm_state --installation Configured --runtime Stopped \
        --health Unavailable --admin Enabled --dependencies DepsReady
      return
    fi
    if [[ "$state" != "running" ]]; then
      ucc_asm_state --installation Configured --runtime Stopped \
        --health Degraded --admin Enabled --dependencies DepsReady
      return
    fi

    runtime_cmd="$(_ucc_yaml_get "$cfg_dir" "$yaml" "targets.${target}.oracle.runtime")"
    if [[ -n "$runtime_cmd" ]] && ! eval "$runtime_cmd" >/dev/null 2>&1; then
      ucc_asm_state --installation Configured --runtime Running \
        --health Degraded --admin Enabled --dependencies DepsReady
      return
    fi

    ucc_asm_runtime_desired
  }
  _evidence_service_runtime() {
    local svc="$1" image tag version digest
    image="$(_ai_service_image "$svc")"
    tag="$(_ai_service_image_tag "$image")"
    version="$(_ai_service_image_label_version "$image")"
    digest="$(_ai_service_image_digest "$image")"
    [[ -n "$version" ]] && version="$(_ai_normalize_version "$version")"
    [[ -n "$tag" ]] && tag="$(_ai_normalize_version "$tag")"

    if [[ -n "$version" ]] && ! _ai_is_mutable_ref "$version"; then
      printf 'version=%s' "$version"
      if [[ -n "$digest" && -n "$tag" ]] && _ai_is_mutable_ref "$tag"; then
        printf '  digest=%s' "$digest"
      fi
      if [[ -n "$tag" && "$tag" != "$version" ]]; then
        printf '  ref=%s' "$tag"
      fi
      return
    fi

    if [[ -n "$tag" ]] && ! _ai_is_mutable_ref "$tag"; then
      printf 'version=%s' "$tag"
      return
    fi

    if [[ -n "$digest" ]]; then
      printf 'digest=%s' "$digest"
      [[ -n "$tag" ]] && printf '  ref=%s' "$tag"
      return
    fi

    [[ -n "$tag" ]] && printf 'ref=%s' "$tag"
  }
  _remove_legacy_containers() {
    local name
    for name in "${AI_SERVICES[@]}"; do
      if docker inspect "$name" &>/dev/null 2>&1; then
        log_info "Removing legacy container: $name"
        docker stop "$name" 2>/dev/null || true
        docker rm   "$name" 2>/dev/null || true
      fi
    done
  }
  _start_stack() {
    _remove_legacy_containers
    if [[ "$IMAGE_POLICY" == "always-pull" ]]; then
      ucc_run docker compose -f "$COMPOSE_FILE" pull
    fi
    ucc_run docker compose -f "$COMPOSE_FILE" up -d
  }
  _update_stack() {
    if [[ "$IMAGE_POLICY" == "always-pull" ]]; then
      ucc_run docker compose -f "$COMPOSE_FILE" pull
    fi
    ucc_run docker compose -f "$COMPOSE_FILE" up -d
  }

  local svc target fn
  for svc in "${AI_SERVICES[@]}"; do
    target="$(_ai_target_for_service "$svc")"
    fn="${svc//[^a-zA-Z0-9]/_}"
    eval "_ai_obs_${fn}() { _observe_service_runtime '${svc}' '${target}'; }"
    eval "_ai_evd_${fn}() { _evidence_service_runtime '${svc}'; }"
    eval "_ai_ins_${fn}() { _start_stack; }"
    eval "_ai_upd_${fn}() { _update_stack; }"

    ucc_target_service --name "$target" \
      --observe "_ai_obs_${fn}" \
      --evidence "_ai_evd_${fn}" \
      --desired "$(ucc_asm_runtime_desired)" \
      --install "_ai_ins_${fn}" \
      --update "_ai_upd_${fn}"
  done
}
