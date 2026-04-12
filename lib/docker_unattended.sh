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

# Pre-write the three EULA-acceptance keys into Docker's settings-store.json
# so Docker.app's first launch skips the onboarding + install screens and
# the Subscription Service Agreement acceptance dialog:
#
#   LicenseTermsVersion:  2     (acknowledges the current SSA revision)
#   DisplayedOnboarding:  true  (skips the tour on first launch)
#   ShowInstallScreen:    false (skips the "Install dependencies" screen)
#
# Creates the parent Group Containers directory and the settings file if
# they do not yet exist (fresh install, before Docker.app's first run).
# Uses tools/drivers/json_merge.py to merge the three keys into the file
# without clobbering any other keys that may already be present (e.g. from
# an earlier _docker_settings_store_patch call).
#
# Usage: _docker_assisted_prewrite_eula "$HOME/Library/Group Containers/group.com.docker/settings-store.json"
_docker_assisted_prewrite_eula() {
  local settings_path="$1"
  [[ -n "$settings_path" ]] || { log_warn "docker-assisted: empty settings_path"; return 1; }
  local settings_dir; settings_dir="$(dirname "$settings_path")"
  mkdir -p "$settings_dir" || return 1
  [[ -f "$settings_path" ]] || printf '%s\n' '{}' > "$settings_path"
  local patch_dir="${CFG_DIR:-.}/.build"
  mkdir -p "$patch_dir" || return 1
  local patch="$patch_dir/docker-eula-patch.json"
  cat > "$patch" <<'JSON'
{
  "LicenseTermsVersion": 2,
  "DisplayedOnboarding": true,
  "ShowInstallScreen": false
}
JSON
  python3 "${CFG_DIR:-.}/tools/drivers/json_merge.py" apply "$settings_path" "$patch"
}

# Scan a Mach-O helper binary for its embedded launchd_plist segment and
# print the plist XML on stdout. The vmnetd Mach-O contains two XML
# plists:
#
#   1. The helper's Info.plist — identified by a `CFBundleIdentifier`
#      key. We must NOT match this one.
#   2. The launchd plist — identified by a top-level `Label` key and
#      `MachServices` / `Sockets` keys; crucially has no
#      CFBundleIdentifier. This is what we want.
#
# Walks the binary byte-by-byte looking for `<?xml ... </plist>` chunks
# and returns the first one that has `Label` and does not have
# `CFBundleIdentifier`. Returns rc=1 if no matching chunk is found.
#
# Split out from _docker_assisted_seed_vmnetd so the extraction logic
# can be unit-tested on WSL with a synthetic binary, without needing
# a real vmnetd, codesign, or /Library access.
#
# Usage: plist="$(_docker_assisted_extract_launchd_plist /path/to/binary)" || return 1
_docker_assisted_extract_launchd_plist() {
  local bin_path="$1"
  [[ -f "$bin_path" ]] || { log_warn "docker-assisted: binary not found: $bin_path"; return 1; }
  python3 - "$bin_path" <<'PY' || return 1
import sys
data = open(sys.argv[1], 'rb').read()
i = 0
while True:
    s = data.find(b'<?xml', i)
    if s < 0:
        break
    e = data.find(b'</plist>', s)
    if e < 0:
        break
    e += len(b'</plist>')
    chunk = data[s:e].decode('utf-8', errors='replace')
    if 'Label' in chunk and 'CFBundleIdentifier' not in chunk:
        sys.stdout.write(chunk)
        sys.exit(0)
    i = e
sys.exit(1)
PY
}

# Seed the com.docker.vmnetd privileged helper by copying the embedded
# binary from /Applications/Docker.app into /Library/PrivilegedHelperTools,
# extracting the embedded launchd plist into /Library/LaunchDaemons, and
# bootstrapping the daemon via launchctl. This avoids the macOS
# Authorization Services dialog that Docker.app would otherwise raise
# on first launch.
#
# Preconditions:
#   - Docker.app is present at /Applications/Docker.app (brew cask
#     install must have already run).
#   - SUDO_ASKPASS is exported (via _docker_assisted_setup_askpass),
#     so the `sudo -A` calls succeed non-interactively.
#
# Mac-only: uses codesign, sudo cp to /Library, and launchctl bootstrap.
# The extraction logic is split into _docker_assisted_extract_launchd_plist
# for WSL unit testing.
#
# ⚠️ Unverified end-to-end on Mac mini until Checkpoint C.
_docker_assisted_seed_vmnetd() {
  local bin_src="/Applications/Docker.app/Contents/Library/LaunchServices/com.docker.vmnetd"
  local bin_dst="/Library/PrivilegedHelperTools/com.docker.vmnetd"
  local plist_dst="/Library/LaunchDaemons/com.docker.vmnetd.plist"
  [[ -f "$bin_src" ]] || { log_warn "docker-assisted: vmnetd binary not found at $bin_src"; return 1; }

  # Verify the binary is still signed by Docker Inc. Protects against
  # Docker Inc rotating signing identities in a future release — if
  # codesign -v fails, bail rather than seed an unsigned binary into
  # /Library/PrivilegedHelperTools/ where it would become a local
  # privilege-escalation surface.
  codesign -v --strict "$bin_src" 2>/dev/null \
    || { log_warn "docker-assisted: vmnetd signature invalid — aborting"; return 1; }

  local launchd_plist
  launchd_plist="$(_docker_assisted_extract_launchd_plist "$bin_src")" \
    || { log_warn "docker-assisted: failed to extract vmnetd launchd plist"; return 1; }

  sudo -A install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools /Library/LaunchDaemons || return 1
  sudo -A cp "$bin_src" "$bin_dst" || return 1
  sudo -A chown root:wheel "$bin_dst" || return 1
  sudo -A chmod 755 "$bin_dst" || return 1
  printf '%s' "$launchd_plist" | sudo -A tee "$plist_dst" >/dev/null || return 1
  sudo -A chown root:wheel "$plist_dst" || return 1
  sudo -A chmod 644 "$plist_dst" || return 1
  # launchctl bootstrap returns non-zero if the daemon is already
  # loaded — that's fine, the existing daemon is the one we want.
  sudo -A launchctl bootstrap system "$plist_dst" 2>/dev/null || true
}
