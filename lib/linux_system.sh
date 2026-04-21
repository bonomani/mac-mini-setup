#!/usr/bin/env bash
# lib/linux_system.sh — Linux/WSL2 host capability probes
#
# BISS: boundary=kernel+init; axis-A=observe; axis-B=capability

# ── Probes ───────────────────────────────────────────────────────────────────

# Return 0 when the kernel exposes the unified cgroup v2 hierarchy at
# /sys/fs/cgroup. Required by rootless podman, systemd --user, and other
# modern Linux container/service stacks.
cgroup2_is_available() {
  [[ "$(stat -fc %T /sys/fs/cgroup 2>/dev/null)" == "cgroup2fs" ]]
}

cgroup2_fstype() {
  stat -fc %T /sys/fs/cgroup 2>/dev/null || printf 'unknown'
}

# Return 0 when systemd is PID 1 (native Linux, or WSL2 with
# [boot] systemd=true in /etc/wsl.conf).
systemd_is_available() {
  [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1
}

systemd_version() {
  command -v systemctl >/dev/null 2>&1 || { printf 'absent'; return; }
  systemctl --version 2>/dev/null | awk 'NR==1{print $2; exit}' || printf 'unknown'
}

# Return 0 when the current user has linger enabled — required for
# systemd --user services to run without an active login session
# (e.g. rootless podman, user timers).
user_linger_is_enabled() {
  command -v loginctl >/dev/null 2>&1 || return 1
  [[ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" == "yes" ]]
}

# ── Runner ───────────────────────────────────────────────────────────────────

# Usage: run_linux_system_from_yaml <cfg_dir> <yaml_path>
run_linux_system_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  ucc_yaml_capability_target "$cfg_dir" "$yaml" "cgroup2-available"
  ucc_yaml_capability_target "$cfg_dir" "$yaml" "systemd-available"
  ucc_yaml_capability_target "$cfg_dir" "$yaml" "user-linger-enabled"
}
