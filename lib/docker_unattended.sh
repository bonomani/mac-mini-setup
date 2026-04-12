#!/usr/bin/env bash
# lib/docker_unattended.sh — assisted (unattended) Docker Desktop first-install helpers
#
# This file holds the experimental recipe selected by
# `UIC_PREF_DOCKER_FIRST_INSTALL=assisted`. It does NOT wire itself in
# anywhere — `lib/docker.sh` dispatches into these helpers from a later
# commit. Sourcing this file alone must have no side effects.
#
# Design notes (see docs/PLAN.md → "Docker Desktop first install —
# unattended recipe" for the full story):
#
# - Homebrew invokes `/usr/bin/sudo` directly (hardcoded, not via PATH)
#   and auto-adds `-A` to its argv whenever `SUDO_ASKPASS` is set. We
#   exploit this: set `SUDO_ASKPASS` to a tiny script that cats a
#   mode-0600 password file, and every `sudo` call brew makes succeeds
#   non-interactively. No PATH shadowing, no sudo wrapper.
# - The password file and askpass helper live in a mktemp workdir
#   (chmod 700) and are wiped + unlinked on the caller's EXIT trap via
#   `_docker_assisted_cleanup`. The caller owns the trap so cleanup
#   fires on normal exit, errors, and SIGINT alike.
# - `_docker_assisted_get_password` is the only source-of-truth for
#   the password. In order: `UCC_SUDO_PASS` env var, then interactive
#   `read -s` from /dev/tty if `UCC_INTERACTIVE=1`, else fail. No
#   fallbacks.
#
# This file has three helpers only. The EULA pre-write, vmnetd seeding,
# and the top-level orchestrator land in subsequent commits.

# Three sources, in order of preference:
#   1. UCC_SUDO_PASS env var (CI/automation mode).
#   2. Interactive `read -s` from /dev/tty (operator mode).
#   3. Fail with a clear message.
# Prints the resolved password on stdout. Returns 2 on failure.
_docker_assisted_get_password() {
  if [[ -n "${UCC_SUDO_PASS:-}" ]]; then
    printf '%s' "$UCC_SUDO_PASS"
    return 0
  fi
  if [[ "${UCC_INTERACTIVE:-1}" == "1" && -r /dev/tty ]]; then
    local _p
    printf 'sudo password for assisted Docker install: ' >/dev/tty
    IFS= read -r -s _p </dev/tty
    printf '\n' >/dev/tty
    [[ -n "$_p" ]] || { log_warn "docker-assisted: empty password rejected"; return 2; }
    printf '%s' "$_p"
    return 0
  fi
  log_warn "docker-assisted: non-interactive mode requires UCC_SUDO_PASS env var"
  return 2
}

# Create a workdir containing a mode-0600 password file and a mode-0755
# askpass helper that cats the password file. Exports SUDO_ASKPASS to
# point at the helper. Sets the global `_DOCKER_ASSISTED_WORKDIR` to
# the workdir path so the caller can capture it and feed it back to
# `_docker_assisted_cleanup` on exit.
#
# We cannot print the workdir on stdout and have the caller capture it
# via `workdir="$(... )"` — command substitution runs in a subshell,
# so the `export SUDO_ASKPASS` would not reach the caller's shell.
# The global-out-variable pattern keeps the export in-shell.
#
# Usage:
#   _docker_assisted_setup_askpass "$password" || return 1
#   workdir="$_DOCKER_ASSISTED_WORKDIR"
#   trap '_docker_assisted_cleanup "$workdir"' EXIT
_docker_assisted_setup_askpass() {
  local password="$1"
  _DOCKER_ASSISTED_WORKDIR=""
  [[ -n "$password" ]] || { log_warn "docker-assisted: empty password"; return 1; }
  local workdir
  workdir="$(mktemp -d 2>/dev/null)" || return 1
  chmod 700 "$workdir"
  printf '%s' "$password" > "$workdir/pass"
  chmod 600 "$workdir/pass"
  cat > "$workdir/askpass.sh" <<ASKPASS
#!/usr/bin/env bash
cat "$workdir/pass"
ASKPASS
  chmod 755 "$workdir/askpass.sh"
  export SUDO_ASKPASS="$workdir/askpass.sh"
  _DOCKER_ASSISTED_WORKDIR="$workdir"
}

# Shred + unlink the askpass workdir. Called from the caller's EXIT trap
# so cleanup runs on normal exit, error paths, and SIGINT alike. Safe
# to call with an empty or nonexistent workdir — returns 0 without
# doing anything (idempotent).
#
# The shred uses `dd if=/dev/zero` because `shred(1)` is not on macOS
# and posix-only `dd` is portable. We overwrite before unlinking so
# the password never sits in unlinked-but-not-yet-reclaimed disk
# blocks after the run.
_docker_assisted_cleanup() {
  local workdir="$1"
  [[ -n "$workdir" && -d "$workdir" ]] || return 0
  if [[ -f "$workdir/pass" ]]; then
    local _sz
    _sz="$(wc -c < "$workdir/pass" 2>/dev/null | tr -d ' ')"
    if [[ -n "$_sz" && "$_sz" -gt 0 ]]; then
      dd if=/dev/zero of="$workdir/pass" bs=1 count="$_sz" 2>/dev/null || true
    fi
  fi
  rm -rf "$workdir"
  unset SUDO_ASKPASS
}
