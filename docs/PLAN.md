# PLAN

## Open

Four items. Three are **waiting-for-consumer** — each has no target
today that would exercise the gap, so the work would be premature
abstraction. They are listed here so a future session picks them up
when (and only when) a real consumer appears. One item (Docker
Desktop fully unattended first install) is **waiting-for-effort**: it
has a real user and a validated recipe, but the implementation is
~150 LOC + a careful test cycle on the Mac mini, and we deferred it
in favor of the capability refactor that closed faster.

### Phase B4 — decouple `docker-compose-service` from `ai_apps`

`_ucc_driver_docker_compose_service_action` calls
`_ai_apply_compose_runtime`, defined in `lib/ai_apps.sh`. Any other
component using `kind: docker-compose-service` would silently fail.
Today **no other component does**, so the decoupling has no current
consumer. Move the compose-apply primitive into a shared
`lib/docker_compose.sh` when (and only when) a second component needs it.

### Phase C1 — uniform drift helper

`_ucc_yaml_parametric_observed_state` already computes drift for every
parametric target. A `_cfg_drift` helper would only matter if drivers
themselves needed to short-circuit on drift before reaching the
framework. None do. Defer until a driver actually wants this.

### Phase X1 — per-driver smoke test fixtures

`tests/test_drivers.py` already covers schema/meta sync, and every
commit runs `bash -n` on touched driver files via the pre-commit hook
chain (commit `b74bb8f`). These catch **syntax errors** in driver
files and **missing entries** in `DRIVER_SCHEMA` / `KNOWN_*_DRIVERS`.

Neither catches the one regression class that has actually bitten:
**a driver file sources without error (bash -n passes, functions are
defined) but one of the hook functions has a runtime error on first
invocation** — a missing `_ucc_yaml_target_get` call, a quoting bug
in a `while read` loop, a typo in a case branch that only fires on a
specific YAML shape.

Today's capability refactor hit exactly this class:
- `ucc_yaml_capability_target` was updated to read `driver.probe`
  — bash -n passed, validator passed, unit tests (that didn't touch
  the actual dispatcher path) passed — but the real Mac mini run
  still returned Stopped because the cache-population path
  (`_UCC_YAML_BATCH_KEYS`) was missing the new key. Only end-to-end
  runs caught it.

A static smoke-test fixture that loads each driver and calls its
hook functions against a known-good fake manifest would have caught
the cache bug by failing in-process, not 5 minutes into an install.sh
run on a different machine.

**Proposed layout**: new file `tests/test_driver_smoke.py`

```python
import os, subprocess, pytest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DRIVERS = sorted((REPO_ROOT / "lib" / "drivers").glob("*.sh"))

@pytest.fixture(scope="module")
def fake_target_yaml(tmp_path_factory):
    """Stage a fake ucc/ tree with one target per driver kind, filled
    with the minimum driver fields from DRIVER_SCHEMA. Targets are
    never executed — they exist only so driver dispatch can run."""
    ...

@pytest.mark.parametrize("driver_path", DRIVERS, ids=lambda p: p.stem)
def test_driver_sources_and_dispatches(driver_path, fake_target_yaml):
    """Source the driver file into a bash subshell, invoke its
    _ucc_driver_<kind>_observe hook against the fake target, and
    assert the command runs (exit code 0 or 1 — both are valid
    'driver dispatched something' outcomes). A bash parse error,
    unbound variable, or missing function declaration all fail here."""
    result = subprocess.run(
        ["bash", "-c", f"""
            set -u
            source lib/ucc.sh
            source lib/utils.sh
            source {driver_path}
            kind=$(basename {driver_path} .sh | tr _ -)
            fn=_ucc_driver_${{kind//-/_}}_observe
            declare -f "$fn" >/dev/null || exit 2
            "$fn" "$PWD" "{fake_target_yaml}" "fake-${{kind}}"
        """],
        cwd=REPO_ROOT, capture_output=True, text=True, timeout=10,
    )
    assert result.returncode in (0, 1), (
        f"driver {driver_path.stem} crashed:\n"
        f"rc={result.returncode}\nstdout={result.stdout}\nstderr={result.stderr}"
    )
```

**What it catches that current checks don't**:

1. **Missing helper function call** — e.g., a driver that references
   `_ucc_yaml_target_get` or `yaml_get_many` without first sourcing
   the file that defines it. `bash -n` doesn't catch this because
   function references are resolved at runtime. The smoke fixture
   catches it because actually running the function errors out.
2. **Quoting bugs in `while read`** — if a driver's NUL-delimited
   parser misses a `-d ''` or uses `$IFS` wrong, the fixture's
   minimal-but-real YAML payload trips it.
3. **Unbound variables under `set -u`** — common regression class
   when a driver grows a new field but forgets to initialize it
   before use.
4. **Typos in case branches** that only match on specific YAML keys,
   like the one that caused the 2026-04-11 capability bug (reading
   `driver.probe` from a cache that never contained it).

**What it explicitly does NOT catch**:
- Correctness of install actions (fixture targets are never executed).
- Interaction between multiple drivers.
- YAML validator errors (already covered by `test_yaml_schema.py`).
- Dispatcher routing through component runners (would need
  integration tests, which is a separate phase).

**Effort estimate**:
- New `tests/test_driver_smoke.py`: ~100 lines.
- Fixture manifest generator: the `fake_target_yaml` fixture walks
  `DRIVER_SCHEMA`, emits one target per kind with the minimum
  required fields, writes a synthetic ucc/software/smoke.yaml.
  ~40 lines.
- Green threshold: each of the ~22 drivers passes (we exclude
  `capability` which has no `_observe` hook — the capability
  dispatch path is tested separately in `test_capability_driver.py`).
- Runtime: <2 seconds for the whole suite.

**When to build this**: when a driver regression slips past `bash -n`
+ the existing suites AND costs >30 minutes of Mac mini debugging.
Today's capability refactor was one such case (the cache bug). If a
second one happens, build the fixture. If not, defer.

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

### 2026-04-11 session

Two items closed in one long session that started with a Docker
Desktop bootstrap recovery and ended with a pre-commit hook install.

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
