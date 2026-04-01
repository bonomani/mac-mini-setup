#!/usr/bin/env bash
# lib/drivers/docker.sh — driver.kind: docker-settings

# ── docker-settings ───────────────────────────────────────────────────────────
# Uses env vars set by the docker runner:
#   DOCKER_SETTINGS_PATH  full path to Docker settings.json
#   DOCKER_MEM_MIB        memory in MiB
#   DOCKER_CPU_COUNT      CPU count
#   DOCKER_SWAP_MIB       swap in MiB
#   DOCKER_DISK_MIB       disk size in MiB
#   DOCKER_MEM_GB         memory in GB (for log message)

_ucc_driver_docker_settings_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  [[ -n "$DOCKER_SETTINGS_PATH" ]] || return 1
  python3 "$cfg_dir/tools/drivers/docker_settings.py" read "$DOCKER_SETTINGS_PATH" 2>/dev/null
}

_ucc_driver_docker_settings_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  _ucc_driver_docker_settings_apply "$cfg_dir" "$yaml" "$target"
}

_ucc_driver_docker_settings_apply() {
  local cfg_dir="$1" yaml="$2" target="$3"
  [[ -n "$DOCKER_SETTINGS_PATH" ]] || return 1
  if [[ ! -f "$DOCKER_SETTINGS_PATH" ]]; then
    log_warn "Docker settings file not found yet — launch Docker first"
    return 1
  fi
  python3 "$cfg_dir/tools/drivers/docker_settings.py" apply \
    "$DOCKER_SETTINGS_PATH" \
    "${DOCKER_MEM_MIB}" "${DOCKER_CPU_COUNT}" "${DOCKER_SWAP_MIB}" "${DOCKER_DISK_MIB}"
  log_warn "Restart Docker Desktop to apply new resource settings"
  log_info "Docker resources set: memory=${DOCKER_MEM_GB}GB cpus=${DOCKER_CPU_COUNT} swap=${DOCKER_SWAP_MIB}MiB disk=${DOCKER_DISK_MIB}MiB"
}

_ucc_driver_docker_settings_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  [[ -n "$DOCKER_SETTINGS_PATH" && -f "$DOCKER_SETTINGS_PATH" ]] || return 1
  python3 - "$DOCKER_SETTINGS_PATH" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
mem_gb = int(data.get("memoryMiB", 0)) // 1024
cpus = int(data.get("cpus", 0))
print(f"memory={mem_gb}GB  cpus={cpus}")
PY
}
