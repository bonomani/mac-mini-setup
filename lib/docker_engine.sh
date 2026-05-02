#!/usr/bin/env bash
# lib/docker_engine.sh — Linux/WSL Docker Engine support.
#
# Observes / starts an *existing* Docker daemon on Linux or WSL2. Does not
# install Docker packages and does not automate Docker Desktop for Linux.
# macOS Docker Desktop logic lives in `lib/docker_desktop_macos.sh`.

# Start the Docker daemon on Linux / WSL. Returns:
#   0   — daemon is reachable (already-running or successfully started).
#   1   — start attempted but daemon never became reachable.
#   125 — no supported start backend (skip).
_docker_engine_start() {
  if _docker_ready; then
    log_info "Docker daemon already reachable"
    return 0
  fi
  if [[ "${HOST_FINGERPRINT:-}" == *"/systemd" ]] && command -v systemctl >/dev/null 2>&1; then
    if sudo_not_available; then
      sudo_warn "Starting Docker daemon via systemd requires sudo — run: sudo -v (or pass --interactive)"
      return 125
    fi
    ucc_run run_elevated systemctl start docker || return 1
    _ucc_wait_until 30 2 _docker_ready || {
      log_warn "Docker daemon not reachable after systemctl start docker"
      return 1
    }
    return 0
  fi
  log_warn "Docker daemon is not reachable and this host has no supported Docker start backend"
  return 125
}
