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
commit runs `bash -n` on touched driver files. A parametrized fixture
that loads each driver and asserts its hooks are callable would catch
the marginal "I added a function that fails to source" bug. Worth it
when a regression actually slips through; not before.

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
  9. `open -g -a /Applications/Docker.app`.
 10. Poll `~/.docker/run/docker.sock` (max 90s, 2s intervals).
 11. Verify by running `/Applications/Docker.app/Contents/Resources/bin/docker version`.
- `_docker_assisted_get_password` — env var → tty prompt → fail.
- `_docker_assisted_prewrite_eula` — JSON merge.
- `_docker_assisted_seed_vmnetd` — extract+copy+bootstrap.
- `_docker_assisted_cleanup` — wipe workdir on EXIT trap.

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

Each run cleaned up via the existing teardown sequence in PLAN.md
(`brew uninstall --cask --zap docker-desktop`, `sudo rm -rf
/Applications/Docker.app /Library/PrivilegedHelperTools/com.docker.*
/Library/LaunchDaemons/com.docker.*`, `rm -rf
~/Library/Group Containers/group.com.docker ~/.docker
~/Library/Containers/com.docker.docker`).

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

All driver-tier work that had a real consumer: D2, D3, D4, B2, C2, B3,
X2. See git log for details.

**Capability driver refactor (2026-04-11)** — Replaced the legacy
`profile: capability + driver.kind: custom + runtime_manager: capability
+ probe_kind: command + oracle.runtime: <fn>` verbose shape with a
single `driver.kind: capability + driver.probe: <fn>` declaration.
7 targets migrated across 5 YAML files (network-available,
networkquality-available, mdns-available, mps-available, cuda-available,
docker-available, sudo-available). New `KNOWN_CAPABILITY_DRIVERS` set
in the validator. Legacy fields (`runtime_manager`, `probe_kind`,
`oracle.runtime` on capability profile) hard-rejected so authors
cannot reintroduce the dead boilerplate. `ucc_yaml_capability_target`
and `_ucc_observe_yaml_capability_target` now read `driver.probe`
instead of `oracle.runtime`. `install.sh`'s `_UCC_YAML_BATCH_KEYS`
pre-fetch list updated to include `driver.probe`. Two pre-existing
miscalls (`lib/homebrew.sh` and `lib/docker.sh` dispatched
`network-available` / `docker-available` through
`ucc_yaml_runtime_target` instead of the capability dispatcher) fixed
along the way — a latent bug that only surfaced once the dispatchers
diverged. New `tests/test_capability_driver.py` adds 15 regression
tests (validator positive + 5 negatives + dispatcher round-trip).
Verified end-to-end on the Mac mini: all 7 capability targets report
`[ok]` in `--no-interactive` mode with matching evidence. Runtime-
profile targets (`unsloth-studio`, `docker-desktop`, etc.) not
migrated — their `kind: custom` declarations remain; a separate
follow-up if desired.

Commits: e48da96 (atomic cutover), 2863044 (batch-keys fix), d17a16c
(runner dispatch fix), a637074 (tests), 3d5759b (regen docs).

**Phase X1.5 — `--check` drift hook wired into pre-commit (2026-04-11)** —
`tools/check-bgs.sh` now uses `git rev-parse --show-toplevel` for
REPO_ROOT (was `$(cd "$(dirname "$0")/.." && pwd)` which broke when the
script was invoked via a symlink from `.git/hooks/` or `~/.git-hooks/`).
Added an inert guard so the script exits 0 silently in repos that do not
carry `tools/build-driver-matrix.py` — safe to install as a global
pre-commit hook without affecting unrelated repos. BGS validator step
moved from "skip whole script on missing validator" to "skip only the
BGS step, still run drift checks" so doc drift is caught even when the
BGS private repo is not present. Hook installed as symlink at
`~/.git-hooks/pre-commit` (the user's existing global hooks dir, which
already contains a commit-msg hook that strips Co-Authored-By lines from
Anthropic — the two hooks coexist). Verified end-to-end: drift detection
blocks commits with rc=1 and a clear DRIFT message; clean commits pass.

Three items honestly skipped:
- **C3** (desired-value comparison in observe) — already handled by
  the parametric framework.
- **C4** (fold compose-file into home-artifact) — would require a new
  one-target subkind; premature abstraction.
- **B1** (state vocab static check) — can't be enforced at static
  analysis without actually running drivers; belongs to runtime tests.

## Out of scope

- New `pkg` backends (mise, nix, aur). Add when a real target needs them.
