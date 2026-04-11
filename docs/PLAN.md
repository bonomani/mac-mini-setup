# PLAN

## Open

Two items. One is **waiting-for-consumer** (Phase C1) — no driver
today would exercise the gap, so building it would be premature
abstraction. It is listed here so a future session picks it up when
(and only when) a real consumer appears. One item (Docker Desktop
fully unattended first install) is **waiting-for-effort**: it has a
real user and a validated recipe, but the implementation is ~150 LOC
+ a careful test cycle on the Mac mini.

### Phase C1 — uniform drift helper

`_ucc_yaml_parametric_observed_state` already computes drift for every
parametric target. A `_cfg_drift` helper would only matter if drivers
themselves needed to short-circuit on drift before reaching the
framework. None do. Defer until a driver actually wants this.

### Docker Desktop — fully unattended first install on macOS

`_docker_desktop_install_and_start` currently fails fast in
non-interactive mode when Docker Desktop has not been bootstrapped on
the user account, because three independent prompts block first install
and none of them have a clean CLI bypass:

1. **brew cask install** symlinks Docker's CLI plugins into
   `/usr/local/cli-plugins/`, which prompts sudo. Cached sudo would
   normally satisfy this, but Homebrew issue
   [#17915](https://github.com/Homebrew/brew/issues/17915) makes every
   `brew` invocation invalidate the user's sudo ticket as a side effect.
2. **macOS Authorization Services Cocoa dialog** for the privileged
   helper on Docker.app's first launch. Not a sudo prompt — a separate
   subsystem that requires GUI interaction.
3. **EULA / Subscription Service Agreement dialog**. If the user does
   not accept it, Docker Desktop quits the daemon.

**Validated experimental recipe** (works end-to-end on Docker Desktop
4.68 + macOS 26 / Apple Silicon, hand-tested 2026-04-11):

1. `script -q /dev/null brew install --cask --no-binaries docker-desktop` —
   the `script` wrapper isolates brew's sudo activity in a separate pty
   so it does not invalidate the user's outer ticket. `--no-binaries`
   skips the brew `binary` stanzas. The cask's `postflight do` block
   still runs sudo for the `kubectl.docker` symlink — gracefully fails
   on a fresh pty and brew rolls back the install. (Open question: how
   to skip the postflight too. Maybe `HOMEBREW_NO_INSTALL_CLEANUP` or a
   monkey-patched cask formula?)
2. `xattr -dr com.apple.quarantine /Applications/Docker.app`
3. **Seed vmnetd manually** to bypass the Authorization Services dialog.
   The helper binary lives at
   `/Applications/Docker.app/Contents/Library/LaunchServices/com.docker.vmnetd`
   inside the bundle and is signed by Docker Inc (9BNSXJN65R). Its
   embedded `__TEXT,__launchd_plist` segment provides the LaunchDaemon
   plist (extract via Python `find b'<?xml' / b'</plist>'`). Copy
   binary to `/Library/PrivilegedHelperTools/com.docker.vmnetd`
   (`root:wheel 0755`) and write the plist (with `ProgramArguments`
   added — Docker's embedded version omits it because SMJobBless
   injects the path automatically) to
   `/Library/LaunchDaemons/com.docker.vmnetd.plist` (`root:wheel 0644`),
   then `sudo launchctl bootstrap system /Library/LaunchDaemons/com.docker.vmnetd.plist`.
   Docker Desktop's SMJobBless `is helper installed and valid?` check
   then passes and the Cocoa dialog never appears. After Docker is up,
   it discards the seeded helper because Docker 4.x on Apple Silicon
   actually uses `com.docker.helper` at the user launchd domain, not
   vmnetd at the system domain — so the seed is theatre that satisfies
   the legacy SMJobBless check and is then garbage-collected.
4. **Pre-write the EULA acceptance** to
   `~/Library/Group Containers/group.com.docker/settings-store.json`
   before launching Docker.app. The three keys that flip on EULA
   accept (verified by before/after diff):
   ```json
   "DisplayedOnboarding": true,
   "LicenseTermsVersion": 2,
   "ShowInstallScreen": false
   ```
   Use `tools/drivers/json_merge.py` to add them without touching the
   other settings.
5. `open -g -a /Applications/Docker.app` — daemon comes up in seconds,
   no dialogs, no prompts.

Wire this up as an opt-in path behind a preference (default = current
conservative gate). The recipe touches `/Library/PrivilegedHelperTools`
and `/Library/LaunchDaemons` with sudo, depends on Docker.app's
internal layout, and could break with any Docker Desktop release —
opt-in for users who actually need unattended setup (CI, fleet
provisioning) and accept the maintenance cost.

Bootstrap detection lives in `_docker_bootstrap_complete` (checks
`LicenseTermsVersion` in settings-store.json). Use the same probe as
the bypass condition for any future variant.

#### Implementation plan

**Preference (`ucc/software/docker.yaml`)**

Add to the `preferences:` block:
```yaml
- name: docker-first-install
  default: manual
  options: manual|assisted
  rationale: manual fails fast in non-interactive mode and requires the
    user to bootstrap Docker once interactively (sudo + macOS auth dialog
    + EULA accept); assisted runs the experimental recipe that pre-writes
    EULA settings, seeds vmnetd to bypass the auth dialog, and uses a
    SUDO_ASKPASS shim so brew's sudo calls succeed non-interactively
```

Read in code as `UIC_PREF_DOCKER_FIRST_INSTALL` (existing convention).

**Password sourcing**

The recipe needs sudo. Three sources, in order:
1. `UCC_SUDO_PASS` env var (CI / scripted use).
2. Interactive prompt via `read -s` from `/dev/tty` (interactive operator).
3. Fail with a clear message naming both options.

Never log the password. Never write it to a process arg. Store it in a
mode-0600 temp file under `mktemp -d` with mode 0700, deleted on EXIT
trap (with `dd if=/dev/zero` overwrite first).

**SUDO_ASKPASS shim**

brew's internal sudo calls do NOT use `-A`, so plain `SUDO_ASKPASS`
isn't enough. Shadow `sudo` in PATH with a wrapper that always passes
`-A`:
```bash
$WORKDIR/sudo:
  #!/bin/bash
  exec /usr/bin/sudo -A "$@"

$WORKDIR/askpass.sh:
  #!/bin/bash
  cat "$WORKDIR/pass"

export SUDO_ASKPASS="$WORKDIR/askpass.sh"
export PATH="$WORKDIR:$PATH"
```
brew's `sudo …` resolves through PATH → wrapper → `/usr/bin/sudo -A` →
askpass returns the cached password. Open question: validate that brew
calls `sudo` (PATH-resolved) and not `/usr/bin/sudo` (hardcoded). If the
latter, the shim is bypassed and we need a different approach (e.g.
patch sudoers temporarily, or use `expect`).

**File layout**

New file `lib/docker_unattended.sh`. Sourced from `lib/ucc.sh` next to
`lib/docker.sh`. Functions:

- `_docker_assisted_install` — top-level orchestrator. Returns 0 on
  full success or non-zero with a logged warning. Steps:
  1. Read YAML vars (`docker_desktop_cask_id`, `docker_desktop_app_path`,
     `settings_relpath`).
  2. Get password via `_docker_assisted_get_password`.
  3. Set up workdir + askpass + sudo shim, install EXIT trap.
  4. `sudo -A -v` to validate the password before doing real work.
  5. `_docker_assisted_prewrite_eula` — write the three EULA keys to
     `settings-store.json` (creating the parent directory if missing,
     merging into existing file via `tools/drivers/json_merge.py`).
  6. `brew install --cask docker-desktop` — relies on the shim.
  7. `_docker_strip_quarantine` (already exists in `lib/docker.sh`).
  8. `_docker_assisted_seed_vmnetd` — extract embedded launchd plist
     from the helper Mach-O, copy binary + write plist to /Library
     with the correct ownership/perms, `launchctl bootstrap`.
  9. `open -a /Applications/Docker.app` (NOT `-g` — we proved on
     2026-04-11 that `-g` returns 0 without actually starting Docker
     on Apple Silicon; use plain foreground launch).
 10. Poll `~/.docker/run/docker.sock` (max 90s, 2s intervals).
 11. Verify by running `/Applications/Docker.app/Contents/Resources/bin/docker version`.
- `_docker_assisted_get_password` — env var → tty prompt → fail.
- `_docker_assisted_prewrite_eula` — JSON merge.
- `_docker_assisted_seed_vmnetd` — extract+copy+bootstrap.
- `_docker_assisted_cleanup` — wipe workdir on EXIT trap.

**Helper function sketches**

These are not final code — they're starting points sized so the next
session can paste them in and iterate.

```bash
# Three sources, in order: UCC_SUDO_PASS env > interactive read -s > fail.
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
    [[ -n "$_p" ]] || { log_warn "empty password"; return 2; }
    printf '%s' "$_p"
    return 0
  fi
  log_warn "Assisted install needs UCC_SUDO_PASS env var in non-interactive mode"
  return 2
}

# Set up the PATH shim + askpass helper + mode-0600 password file.
# Caller captures the workdir path and installs the EXIT trap.
_docker_assisted_setup_shim() {
  local password="$1"
  local workdir; workdir="$(mktemp -d)" || return 1
  chmod 700 "$workdir"
  printf '%s' "$password" > "$workdir/pass"
  chmod 600 "$workdir/pass"
  cat > "$workdir/askpass.sh" <<ASKPASS
#!/bin/bash
cat "$workdir/pass"
ASKPASS
  chmod 755 "$workdir/askpass.sh"
  cat > "$workdir/sudo" <<SHIM
#!/bin/bash
exec /usr/bin/sudo -A "\$@"
SHIM
  chmod 755 "$workdir/sudo"
  export SUDO_ASKPASS="$workdir/askpass.sh"
  export PATH="$workdir:$PATH"
  printf '%s' "$workdir"
}

# Called from EXIT trap. Overwrite the password file before unlinking
# so the password never sits on disk after the run.
_docker_assisted_cleanup() {
  local workdir="$1"
  [[ -n "$workdir" && -d "$workdir" ]] || return 0
  if [[ -f "$workdir/pass" ]]; then
    dd if=/dev/zero of="$workdir/pass" bs=1 count="$(wc -c < "$workdir/pass")" 2>/dev/null || true
  fi
  rm -rf "$workdir"
}

# Merge the three EULA-acceptance keys into settings-store.json using
# the existing tools/drivers/json_merge.py helper. Creates the file if
# it does not exist yet.
_docker_assisted_prewrite_eula() {
  local settings_path="$1"
  mkdir -p "$(dirname "$settings_path")"
  [[ -f "$settings_path" ]] || printf '%s\n' '{}' > "$settings_path"
  local patch_dir="$CFG_DIR/.build"
  mkdir -p "$patch_dir"
  local patch="$patch_dir/docker-eula-patch.json"
  cat > "$patch" <<'JSON'
{
  "LicenseTermsVersion": 2,
  "DisplayedOnboarding": true,
  "ShowInstallScreen": false
}
JSON
  python3 "$CFG_DIR/tools/drivers/json_merge.py" apply "$settings_path" "$patch"
}

# Extract the launchd plist embedded in the vmnetd binary, copy both
# files into /Library, and launchctl-bootstrap the daemon.
_docker_assisted_seed_vmnetd() {
  local bin_src="/Applications/Docker.app/Contents/Library/LaunchServices/com.docker.vmnetd"
  local bin_dst="/Library/PrivilegedHelperTools/com.docker.vmnetd"
  local plist_dst="/Library/LaunchDaemons/com.docker.vmnetd.plist"
  [[ -f "$bin_src" ]] || { log_warn "vmnetd binary not found at $bin_src"; return 1; }

  # The Info.plist fields embedded in the binary identify Docker Inc as
  # the signer (certificate leaf subject CN = "Developer ID Application:
  # Docker Inc (9BNSXJN65R)"). Verify that the running binary still
  # matches before seeding — protects against Docker Inc rotating
  # signing identities in a future release.
  codesign -v --strict "$bin_src" || { log_warn "vmnetd signature invalid"; return 1; }

  # Scan the helper Mach-O for its embedded launchd_plist segment. The
  # binary contains two XML plists: the helper's Info.plist (identified
  # by CFBundleIdentifier) and the launchd plist (identified by Label
  # and MachServices/Sockets, no CFBundleIdentifier). Use Python to
  # find and extract the second one.
  local launchd_plist
  launchd_plist="$(python3 - "$bin_src" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
i = 0
while True:
    s = data.find(b'<?xml', i)
    if s < 0: break
    e = data.find(b'</plist>', s)
    if e < 0: break
    e += len(b'</plist>')
    chunk = data[s:e].decode('utf-8', errors='replace')
    if 'Label' in chunk and 'CFBundleIdentifier' not in chunk:
        sys.stdout.write(chunk)
        sys.exit(0)
    i = e
sys.exit(1)
PY
  )" || { log_warn "failed to extract vmnetd launchd plist"; return 1; }

  sudo -A install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools /Library/LaunchDaemons
  sudo -A cp "$bin_src" "$bin_dst"
  sudo -A chown root:wheel "$bin_dst"
  sudo -A chmod 755 "$bin_dst"
  printf '%s' "$launchd_plist" | sudo -A tee "$plist_dst" >/dev/null
  sudo -A chown root:wheel "$plist_dst"
  sudo -A chmod 644 "$plist_dst"
  sudo -A launchctl bootstrap system "$plist_dst" 2>&1 || true
  # bootstrap is idempotent-ish but can fail if already loaded; that's
  # fine, the existing daemon is the one we want.
}
```

**Dispatch (`lib/docker.sh`)**

In `_docker_desktop_install_and_start`, before the existing gate:
```bash
if ! _docker_bootstrap_complete; then
  case "${UIC_PREF_DOCKER_FIRST_INSTALL:-manual}" in
    assisted)
      _docker_assisted_install || return $?
      return 0
      ;;
    manual|*)
      # ... existing gate (fail in non-interactive, info-log in interactive)
      ;;
  esac
fi
```
Keeps the default path 100% unchanged.

**Open issues / risks**

1. **kubectl postflight** — `brew install --cask docker-desktop` runs a
   `postflight do` block that tries to symlink `kubectl.docker` into
   `/usr/local/bin/`. With the SUDO_ASKPASS shim, the postflight's sudo
   call should succeed. **Untested.** If brew's Ruby `system` call uses
   the absolute path `/usr/bin/sudo`, the shim is bypassed.
2. **vmnetd code-signing churn** — if Docker Inc changes the signing
   identity, the seeded helper's signature won't match Docker.app's
   `SMPrivilegedExecutables` requirement and SMJobBless will reject it.
   We should `codesign -d -r-` the helper at runtime and compare it
   to the requirement string in `Info.plist`, falling back to the
   manual path if they don't match.
3. **Embedded plist parsing** — relies on finding `<?xml` and
   `</plist>` markers in the Mach-O `__TEXT,__launchd_plist` segment,
   distinguishing the launchd plist from the helper's `Info.plist`
   (filter on presence of `Label` and absence of `CFBundleIdentifier`).
   Brittle if Docker changes the segment layout. Better to use
   `otool -X -s __TEXT __launchd_plist` and parse the hex.
4. **EULA `LicenseTermsVersion` value** — currently `2`. Will Docker
   bump this in a future version, expecting users to re-accept? If
   yes, our pre-write becomes stale and the EULA dialog reappears.
   Mitigation: read the value from a Docker-published source if
   available, or refresh on every assisted run.
5. **`com.docker.helper` user-domain agent** — modern Docker uses
   this instead of system-domain vmnetd. Our seed satisfies the legacy
   SMJobBless check and is then garbage-collected. If Docker drops the
   SMJobBless code path entirely in a future version, our seed becomes
   irrelevant — but the dialog might also disappear, in which case
   the assisted path can drop step (8) entirely.
6. **Settings JSON merge** — `tools/drivers/json_merge.py` is used
   elsewhere; reuse it. If `settings-store.json` does not exist yet
   (fresh install), we create the parent dir and the file with just
   the three keys. Docker writes the rest on first launch, merging.
7. **Password security** — temp file is mode 0600, dir is 0700,
   deleted on EXIT (including SIGINT/SIGTERM). Acceptable for an
   opt-in advanced flow but document the trade-off.

**Test plan**

Validation runs on a clean Mac mini after each cleanup:

1. `UIC_PREF_DOCKER_FIRST_INSTALL=manual` + non-interactive →
   gate fires, no work done. (Regression check.)
2. `UIC_PREF_DOCKER_FIRST_INSTALL=manual` + interactive → manual
   path runs, all three dialogs appear, user clicks through. (Regression
   check.)
3. `UIC_PREF_DOCKER_FIRST_INSTALL=assisted` + interactive →
   ONE password prompt at start, then no further interaction; Docker
   daemon up; `docker version` works.
4. `UIC_PREF_DOCKER_FIRST_INSTALL=assisted` +
   `UCC_SUDO_PASS=...` + non-interactive → ZERO interaction; Docker
   daemon up; `docker version` works.
5. `UIC_PREF_DOCKER_FIRST_INSTALL=assisted` + non-interactive
   without `UCC_SUDO_PASS` → fails clean with a clear "set
   `UCC_SUDO_PASS` or run interactively" message.
6. `UIC_PREF_DOCKER_FIRST_INSTALL=assisted` + WRONG password →
   fails at the `sudo -A -v` validation step before any real work; no
   side effects on disk.
7. After a successful assisted run, re-run `--no-interactive
   docker-desktop` → `_docker_bootstrap_complete` returns true, gate
   skipped, daemon already running, no-op `[ok]`.

**Per-step rollback** (if the assisted install fails mid-way, clean up
only the artifacts produced up to the failure point — avoids a full
wipe when a later step trips):

| Failed at | Cleanup commands |
|---|---|
| Step 4 (`sudo -A -v`) | Nothing to clean. Wrong password rejected before any write. |
| Step 5 (pre-write EULA) | `rm -f ~/Library/Group Containers/group.com.docker/settings-store.json` if we created it; or `git checkout $PATCH_BACKUP` if we backed it up first |
| Step 6 (`brew install`) | `brew uninstall --cask docker-desktop 2>/dev/null \|\| true` |
| Step 7 (strip quarantine) | No cleanup needed (xattr removal is safe) |
| Step 8 (seed vmnetd) | `sudo launchctl bootout system/com.docker.vmnetd 2>/dev/null`; `sudo rm -f /Library/LaunchDaemons/com.docker.vmnetd.plist /Library/PrivilegedHelperTools/com.docker.vmnetd` |
| Step 9 (`open -a`) | `osascript -e 'quit app "Docker"' 2>/dev/null` |
| Step 10 (socket poll timeout) | Step 8 cleanup above; also kill Docker.app: `pkill -f 'com\.docker' 2>/dev/null` |

**Full teardown** (if none of the above work or user wants a clean
slate) — same sequence used by the cleanup script at the top of this
plan entry:

```bash
osascript -e 'quit app "Docker"' 2>/dev/null || true
pkill -f 'com\.docker' 2>/dev/null || true
brew uninstall --cask --zap docker-desktop 2>/dev/null || true
sudo launchctl bootout system/com.docker.vmnetd 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/com.docker.vmnetd.plist
sudo rm -f /Library/PrivilegedHelperTools/com.docker.vmnetd
sudo rm -f /Library/PrivilegedHelperTools/com.docker.socket
rm -rf ~/Library/Group\ Containers/group.com.docker
rm -rf ~/Library/Containers/com.docker.docker
rm -rf ~/Library/Containers/com.docker.helper
rm -rf ~/.docker
rm -rf ~/Library/Application\ Support/Docker\ Desktop
rm -f  ~/Library/Preferences/com.docker.docker.plist
rm -rf ~/Library/Caches/com.docker.docker
rm -rf ~/Library/LaunchAgents/com.docker*
```

**Estimated effort**

- New `lib/docker_unattended.sh`: ~150 lines.
- Dispatch in `lib/docker.sh`: ~10 lines.
- Preference entry in `docker.yaml`: 4 lines.
- Source line in `lib/ucc.sh`: 1 line.
- Test cycles on the Mac mini: 6-8 clean+install runs.

Realistically: implement in one focused session, test in another. Do
not start without a clean Docker uninstall and a way to revert `/Library`
state if seeding goes wrong (`launchctl bootout system/com.docker.vmnetd
&& sudo rm /Library/PrivilegedHelperTools/com.docker.vmnetd
/Library/LaunchDaemons/com.docker.vmnetd.plist`).

## Closed

### 2026-04-12 session

**Phase B4 — hoist compose-up to a first-class target** — The
implementation that landed today matches the "better plan" design
recorded in the Open section yesterday (the one that replaced the
original "move _ai_apply_compose_runtime to lib/docker_compose.sh"
sketch with the cleaner "upstream-gate + observe-only dependents"
model). No second compose-based component exists yet, but the
refactor was justified by two observations:

1. The existing sentinel-based implementation had real coupling
   costs for ai-apps itself — the dep graph was lying (each per-
   service target's `depends_on: ai-stack-compose-file` hid the
   actual sibling side-effect of running `docker compose up -d`).
   Promoting compose-up to a first-class target makes the graph
   honest.
2. The pattern is already used in the framework at 1→1 scale
   (`docker-desktop → docker-available`) and 1→2 scale
   (`pytorch → mps-available + cuda-available`). Extending it to
   1→5 is applying a known primitive, not inventing a new concept —
   so risk is lower than speculative abstraction normally carries.

What actually shipped:

- **New driver `lib/drivers/compose_apply.sh`** (96 LOC) with
  observe/action/evidence hooks. Uses `driver.path_env` (env var
  name indirection, matching the existing `compose-file` driver)
  and optional `driver.pull_policy_env` for "always-pull" gating.
  Observe resolves the compose path, runs `docker compose config
  --services` to enumerate declared services, then checks every
  service has a running container (matching by name with a regex
  that tolerates `--` and `__` compose-project naming). Action
  runs optional `docker compose pull` then `docker compose -f <path>
  up -d`.
- **New target `ai-stack-compose-running`** in ai-apps.yaml,
  profile: runtime, driver.kind: compose-apply. depends_on:
  [docker-desktop, ai-stack-compose-file]. This is the single
  apply gate for the whole ai-apps compose stack.
- **5 runtime targets rewired** (open-webui, flowise, openhands,
  n8n, qdrant) to `depends_on: ai-stack-compose-running` instead of
  `depends_on: ai-stack-compose-file`. Their driver is now pure-
  observe — no _action hook in `docker-compose-service`.
- **`_action` hook deleted** from `lib/drivers/docker_compose_service.sh`.
  The driver is now observe + evidence + recover only. The retry-
  with-backoff HTTP probe from `e36a399` is preserved.
- **Sentinel and apply function deleted** from `lib/ai_apps.sh`:
  `_AI_APPS_APPLY_SENTINEL` variable, its lifecycle (`mkdir -p` +
  `:>` sentinel touch), and the entire `_ai_apply_compose_runtime`
  function. Replaced with: `export COMPOSE_FILE` (so the driver
  reads it via `driver.path_env`), pre-dispatch
  `_remove_legacy_containers` call, `ucc_yaml_runtime_target` for
  `ai-stack-compose-running` before the per-service loop, and a
  second `_ai_warm_metadata_cache` call after that dispatch.
- **Validator updated**: `compose-apply` added to both
  `KNOWN_RUNTIME_DRIVERS` and `DRIVER_SCHEMA` (required: path_env,
  optional: pull_policy_env).
- **Smoke test updated**: `compose-apply` added to
  `FAKE_DRIVER_FIELDS` with a non-existent `path_env` so the
  synthetic observe falls through to "stopped" cleanly. All 55
  tests pass in `tests/test_driver_smoke.py +
  tests/test_drivers.py + tests/test_capability_driver.py +
  tests/test_yaml_schema.py`.
- **Docs regenerated** — driver-feature-matrix.md gains a
  `compose-apply` row and drops `docker-compose-service`'s action
  column from ✅ to —. SPEC.md ai-apps section grows 15 → 16
  targets (the new `ai-stack-compose-running`).

What the refactor buys going forward:

- Adding a second compose stack (monitoring, homelab, media server,
  dev databases) requires **zero lib/ changes**. The new component's
  runner sets its own `COMPOSE_FILE` env var, the YAML declares a
  `*-compose-running` target with `driver.kind: compose-apply` +
  `driver.path_env: COMPOSE_FILE`, plus N `docker-compose-service`
  observe-only targets depending on it.
- The dep graph tells the truth: running
  `./install.sh open-webui-runtime` now visibly resolves as
  `docker-desktop → ai-stack-compose-file → ai-stack-compose-running
  → open-webui-runtime`. The shared sibling side-effect is explicit.
- Failure modes clean up: if `docker compose up -d` fails, the
  gate target reports `[fail]` and the 5 dependents each report
  `[dep-fail]` via the framework's existing propagation. One
  clear root cause.

Mac mini verification still required: the smoke test can exercise
the driver's dispatch path but can't actually run `docker compose`
on WSL without a container stack. The real validation is
`./install.sh --no-interactive` on the Mac mini, with the ai-apps
compose stack torn down first (`docker compose -f
$HOME/.ai-stack/docker-compose.yml down`), confirming the new dep
chain brings everything up cleanly.

Commits: `cd56046` (add compose-apply driver, inert), `34d806a`
(atomic cutover — remove sentinel, rewire YAML, delete _action).

---

### 2026-04-11 session

Three items closed in one long session that started with a Docker
Desktop bootstrap recovery and ended with Phase X1 per-driver smoke
tests.

**Capability driver refactor** — Replaced the legacy verbose shape
(`profile: capability + driver.kind: custom + runtime_manager:
capability + probe_kind: command + oracle.runtime: <fn>`) with a
single `driver.kind: capability + driver.probe: <fn>` declaration.
7 targets migrated across 5 YAML files (`network-available`,
`networkquality-available`, `mdns-available`, `mps-available`,
`cuda-available`, `docker-available`, `sudo-available`). New
`KNOWN_CAPABILITY_DRIVERS` set in the validator; legacy fields
(`runtime_manager`, `probe_kind`, `oracle.runtime` on capability
profile) hard-rejected so authors cannot reintroduce the dead
boilerplate. `ucc_yaml_capability_target` and
`_ucc_observe_yaml_capability_target` now read `driver.probe` instead
of `oracle.runtime`. `install.sh`'s `_UCC_YAML_BATCH_KEYS` pre-fetch
list updated to include `driver.probe`. Two pre-existing miscalls
(`lib/homebrew.sh` and `lib/docker.sh` dispatched `network-available`
/ `docker-available` through `ucc_yaml_runtime_target` instead of the
capability dispatcher) fixed along the way — a latent bug that only
surfaced once the dispatchers diverged. New
`tests/test_capability_driver.py` adds 15 regression tests (validator
positive + 5 negatives + dispatcher round-trip). Verified end-to-end
on the Mac mini: all 7 capability targets report `[ok]` in
`--no-interactive` mode with matching evidence. Runtime-profile
targets (`unsloth-studio`, `docker-desktop`) not migrated — their
`kind: custom` declarations remain; a separate follow-up if desired.

Commits: `e48da96` (atomic cutover), `2863044` (batch-keys fix),
`d17a16c` (runner dispatch fix), `a637074` (tests), `3d5759b`
(regen docs), `3e04358` (PLAN update).

**Phase X1.5 — `--check` drift hook wired into pre-commit** —
`tools/check-bgs.sh` now uses `git rev-parse --show-toplevel` for
REPO_ROOT (was `$(cd "$(dirname "$0")/.." && pwd)` which broke when
the script was invoked via a symlink from `.git/hooks/` or
`~/.git-hooks/`). Added an inert guard so the script exits 0
silently in repos that do not carry `tools/build-driver-matrix.py`
— safe to install as a global pre-commit hook without affecting
unrelated repos. BGS validator step moved from "skip whole script on
missing validator" to "skip only the BGS step, still run drift
checks" so doc drift is caught even when the BGS private repo is
not present. Hook installed as symlink at `~/.git-hooks/pre-commit`
(the user's existing global hooks dir, which already contains a
`commit-msg` hook that strips `Co-Authored-By: *@anthropic.com`
lines — the two hooks coexist). Verified end-to-end: drift detection
blocks commits with `rc=1` and a clear DRIFT message; clean commits
pass. Every commit on this repo now enforces
`python3 tools/build-driver-matrix.py --check` +
`python3 tools/build-spec.py --check`.

Commits: `b74bb8f` (hook + script fix + PLAN update).

**Phase X1 — per-driver smoke test fixtures** — New
`tests/test_driver_smoke.py` (~205 LOC) uses `pytest.parametrize`
over every driver kind that defines a `_ucc_driver_<kind>_observe`
hook in `lib/drivers/`. Each test sources `lib/ucc.sh + lib/utils.sh`
in a bash subshell and invokes the observe function against a
minimal synthetic YAML fixture, asserting exit code is 0 or 1
(both are "driver dispatched cleanly" outcomes). A `FAKE_DRIVER_FIELDS`
dict provides the minimum required fields for each of the 24
currently-covered kinds, with all values designed to resolve to
the driver's "missing" state on the test host. Two meta-sanity
tests enforce that `FAKE_DRIVER_FIELDS` stays in sync with
`DRIVER_SCHEMA[kind]['required']` and that every driver with an
`_observe` hook in `lib/drivers/` is either covered or explicitly
skipped with a documented reason. Runtime: ~1.5 seconds for 26
tests (24 driver smoke + 2 sanity).

Catches: driver files that source clean but crash on first hook
invocation (unbound vars under `set -u`, typos in case branches
matching YAML keys, missing helper function calls). Does NOT catch:
capability targets (dispatched through `ucc_yaml_capability_target`,
not through a driver `_observe` hook — covered by the existing
`tests/test_capability_driver.py`), install-action correctness
(fixture targets are never executed), or meta-drivers like
`npm-global` / `package` that delegate to other kinds. Also
explicitly excluded: `vscode-marketplace` (retired).

Sanity check: injected an unbound-variable crash into
`_ucc_driver_brew_observe`, test failed with `rc=127` and surfaced
bash's stderr in the assert message. Reverted, tests green.

Paired with: a new `InstallShBatchKeysTests` class in
`tests/test_capability_driver.py` adds two static regression tests
for the specific capability-cache bug that today's driver smoke test
CANNOT reach (because it lives in `ucc_yaml_capability_target`'s
dispatch path, not in a driver hook). `test_batch_keys_include_driver_probe`
asserts `driver.probe` appears in install.sh, and
`test_batch_keys_excludes_oracle_runtime` asserts the legacy key
has been removed. Both checks are static file-content greps — they
directly document the invariant "any field the capability dispatcher
reads from the pre-fetched cache MUST be in `_UCC_YAML_BATCH_KEYS`".

Commits: `9762e07` (driver smoke test), `88bbc5e` (install.sh batch
key regression tests).

**Auxiliary fixes from the same session** — not strictly part of
either item above, but landed while recovering the Mac mini's Docker
Desktop install and revealed along the way:

- `ba8f095` — Stop Gatekeeper reinstall loop on Docker Desktop
  (`greedy_auto_updates: true` + unstrtipped quarantine made brew
  reinstall the cask on every run, then tripped a macOS dialog).
- `71c2dee` — Correct the `settings_relpath` YAML key that was
  never being read because the lib code used a non-existent
  `docker_settings_store_relpath` key; also always strip quarantine
  in `_docker_daemon_start` defensively.
- `5a79a42` — Replace `_docker_privileged_helper_installed` (which
  looked for `/Library/PrivilegedHelperTools/com.docker.vmnetd` —
  gone on Apple Silicon Docker 4.x) with `_docker_bootstrap_complete`
  which checks `LicenseTermsVersion` in `settings-store.json`.
- `813aa78` + `f08328e` — `_docker_launch` stops calling the
  nonexistent `docker desktop start` CLI plugin and uses plain
  `open -a /Applications/Docker.app` (`-g` proven broken on Apple
  Silicon — returns 0 without starting Docker).
- `69f47d4` — Escalating recovery feature for failed targets plus
  `winget` backend for `pkg` + `mdns-available` capability target
  (originally wired wrong, fixed in the follow-ups below).
- `ec2d426` + `2261b78` + `5fb5445` — Successive fixes for the new
  network-services targets: missing `state_model`, invalid
  `apt_ref/dnf_ref`, wire `mdns-available` + `avahi` into the
  component runner.
- `6a07393` + `07b63af` — Document the validated recipe for
  fully-unattended Docker first install (vmnetd seeding + EULA
  settings pre-write + SUDO_ASKPASS shim) in PLAN.md as deferred
  future work.

### Earlier closed work

All driver-tier work that had a real consumer: D2, D3, D4, B2, C2,
B3, X2. See git log for details.

Three items honestly skipped:
- **C3** (desired-value comparison in observe) — already handled by
  the parametric framework.
- **C4** (fold compose-file into home-artifact) — would require a
  new one-target subkind; premature abstraction.
- **B1** (state vocab static check) — can't be enforced at static
  analysis without actually running drivers; belongs to runtime tests.

## Out of scope

- New `pkg` backends (mise, nix, aur). Add when a real target needs them.
