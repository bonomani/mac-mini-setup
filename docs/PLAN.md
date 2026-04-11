# PLAN

## Open

Three items remain — all deferred until there's a real consumer that
exercises the gap, not because the plan listed them.

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

### Phase X1.5 — `--check` mode for `build-driver-matrix.py` in pre-commit

Trivial follow-up: install the BGS pre-commit hook and add
`python3 tools/build-driver-matrix.py --check` alongside it so a
silently-stale matrix fails the commit. ~10 minutes when the next
hook install happens.

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

Wire this up as an opt-in path behind a preference (e.g.
`docker-first-install: assisted | manual`, default `manual`) so the
default behaviour stays the conservative gate that is in
`_docker_desktop_install_and_start` today. The recipe touches
`/Library/PrivilegedHelperTools` and `/Library/LaunchDaemons` with
sudo, depends on Docker.app's internal layout, and could break with
any Docker Desktop release — opt-in for users who actually need
unattended setup (CI, fleet provisioning) and accept the maintenance
cost.

Bootstrap detection lives in `_docker_bootstrap_complete` (checks
`LicenseTermsVersion` in settings-store.json). Use the same probe as
the bypass condition for any future variant.

## Closed

All driver-tier work that had a real consumer: D2, D3, D4, B2, C2, B3,
X2. See git log for details.

Three items honestly skipped:
- **C3** (desired-value comparison in observe) — already handled by
  the parametric framework.
- **C4** (fold compose-file into home-artifact) — would require a new
  one-target subkind; premature abstraction.
- **B1** (state vocab static check) — can't be enforced at static
  analysis without actually running drivers; belongs to runtime tests.

## Out of scope

- New `pkg` backends (mise, nix, aur). Add when a real target needs them.
