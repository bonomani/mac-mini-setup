# PLAN

Goal: bring every driver up to the same level *for its tier*. There's no
single feature set that makes sense for every driver — outdated detection
is meaningless for a `zsh-config` line edit, and drift detection is
meaningless for a brew formula install — so the plan is organized by tier,
with a target feature set per tier and a list of per-driver gaps.

## Tiers

| Tier | Drivers | Required features |
|---|---|---|
| **A. Package installers** | `pkg`, `pip` | observe/action/evidence, outdated detection (gated), migration handling, activation guard, dry-run safety |
| **B. Services / daemons** | `service`, `docker-compose-service`, `custom-daemon` | observe/action/evidence, state vocab `running\|stopped\|absent`, log path in evidence, restart-on-update |
| **C. Config writers** | `setting`, `json-merge`, `brew-analytics`, `git-global`, `zsh-config`, `path-export`, `home-artifact`, `compose-file`, `softwareupdate-schedule`, `brew-unlink` | observe/apply, drift detection (current vs desired), backup-before-write, idempotency |
| **D. Specialised installers** | `app-bundle`, `git-repo`, `pyenv-brew`, `pip-bootstrap`, `build-deps`, `script-installer`, `nvm`, `nvm-version` | observe/action/evidence, opportunistic outdated when an upstream signal exists |

`pkg.sh` and `pip.sh` (Tier A) are the reference implementations. Every other
driver is measured against its tier's minimum.

---

## Tier A — already at level

Both `pkg` and `pip` carry: outdated (opt-in), migration handler / conflict
gate, activation guard. Nothing to do at the tier level.

---

## Tier B — services / daemons

### Phase B1 — uniform state vocabulary  (~1 h)

**Gap**: each service driver invents its own observe vocabulary.
- `service`: `absent | running | stopped`
- `docker-compose-service`: `running | stopped`
- `custom-daemon`: `absent | running | stopped`

These are already aligned, but the validator doesn't enforce it. Add a
`KNOWN_RUNTIME_STATES = {"absent", "running", "stopped"}` set in the
validator and a per-tier shape check.

### Phase B2 — log path in evidence  (~30 min each driver)

**Gap**: only `service` (launchd backend) emits a `plist=` evidence line.
Other services don't surface "where do I look when this fails".

**Fix**:
- `service` (brew backend): add `log=$(brew services info <ref> --json | jq .log)`.
- `docker-compose-service`: add `log=docker logs <name>` hint.
- `custom-daemon`: add `log=<configured path>` from `driver.log_path`.

### Phase B3 — `custom-daemon` action upgrade  (~2 h)

**Gap**: `_ucc_driver_custom_daemon_action` returns 1 (no-op). The driver
can observe processes but cannot start them. Today users start the daemon
out-of-band (launchd plist or manual).

**Fix**: optional `driver.start_cmd: <command>` in YAML; the action
runs it on `install`/`update`. Falls back to no-op (current behavior)
when missing — backward compatible.

### Phase B4 — decouple `docker-compose-service` from `ai_apps`  (~3 h)

**Gap**: `_ucc_driver_docker_compose_service_action` calls
`_ai_apply_compose_runtime`, defined in the `ai_apps` runner. Any other
component using `kind: docker-compose-service` would silently fail
(`declare -f` check returns 1).

**Fix**: move the compose-apply primitive into a shared
`lib/docker_compose.sh`, source from both `ai_apps` and the driver.

---

## Tier C — config writers

### Phase C1 — uniform drift detection helper  (~3 h)

**Gap**: each config driver computes "current vs desired" differently.
- `setting`: returns the actual value, framework compares.
- `json-merge`: walks JSON and reports per-key drift.
- `brew-analytics`: returns `on`/`off`.
- `git-global`, `zsh-config`, `path-export`, `home-artifact`, etc.: each
  with its own observe shape.

**Fix**: a shared `_cfg_drift <current> <desired>` helper that returns
0 (in sync) or 1 (drifted) and stashes a structured drift report in env
for the summary printer to format. Each driver normalizes its observe
output to call the helper.

### Phase C2 — backup-before-write  (~1 h)

**Gap**: only `json-merge` backs up the file before editing
(`settings.json.bak`). Others overwrite in place.

**Fix**: a shared `_cfg_backup <file>` helper that copies the target file
to `<file>.bak.<timestamp>` if it exists and doesn't already have a recent
backup. Wire into every config driver's apply path.

**Risk**: low. Backups are dumb file copies.

### Phase C3 — desired-value comparison in observe  (~1 h)

**Gap**: most config drivers report the *current* value as their state.
The framework compares against `desired_value` from YAML. This means a
config-bool target shows `state=on` and `desired_value=off` and the
operator has to read both columns. Surfacing `drifted` directly in
observe would be cleaner.

**Fix**: each config driver reads `desired_value` and emits one of
`configured | drifted | absent`. Validator ensures all `state_model: config`
and `state_model: parametric` targets emit one of these values.

### Phase C4 — `compose-file` becomes a `home-artifact` subkind  (~30 min)

**Gap**: `compose_file.sh` is a single-target driver that does the same
work as `home-artifact subkind: file`. Could fold in.

**Fix**: add `subkind: file` to `home-artifact`, migrate the one
`ai-stack-compose-file` target, retire `compose_file.sh`.

---

## Tier D — specialised installers

### Phase D1 — `git-repo` outdated already done

`git-repo` already detects outdated (local vs remote ref). Nothing to do.

### Phase D2 — `nvm` / `nvm-version` outdated  (~1 h)

**Gap**: no upstream comparison.

**Fix**:
- `nvm`: read `driver.github_repo` (already set to `nvm-sh/nvm`),
  use the existing `_pkg_github_latest_tag` helper to compare.
- `nvm-version`: `nvm ls-remote --lts` shows the latest LTS for
  the requested major version; compare against installed.

Gated on `UIC_PREF_BREW_LIVECHECK=1`.

### Phase D3 — `script-installer` outdated  (~30 min)

**Gap**: no upstream signal.

**Fix**: read `driver.github_repo` (e.g. for oh-my-zsh: `ohmyzsh/ohmyzsh`)
and reuse `_pkg_curl_outdated`'s pattern. Compare installed commit/version
against latest tag.

### Phase D4 — `pyenv-brew` outdated  (~15 min)

**Gap**: no outdated check, even though pyenv is a brew formula.

**Fix**: piggyback on `brew_observe pyenv` in observe. Trivial.

### Phase D5 — `app-bundle` already done

`app-bundle` already detects outdated via upstream API. Nothing to do.

### Phase D6 — `build-deps`, `pip-bootstrap` stay as-is

Both are bootstrap targets; "outdated" would mean re-bootstrapping.
Not actionable. Skip.

---

## Cross-cutting

### Phase X1 — per-tier test fixtures  (~half day)

**Gap**: `tests/test_drivers.py` tests metadata sync but not driver
contracts. Each driver should have a smoke test that loads the file
and asserts its hooks are callable (no syntax/source error).

**Fix**: parametrize a fixture over `lib/drivers/*.sh`, source each in a
subshell, and call `declare -f _ucc_driver_<kind>_observe`. Catches
regressions across the board.

### Phase X2 — feature-table generator  (~1 h)

**Gap**: `docs/driver-feature-matrix.md` was hand-written from a one-shot
audit. It will drift the moment a driver changes.

**Fix**: a `tools/build-driver-matrix.py` that reads `lib/drivers/*.sh`,
counts target uses in `ucc/`, and emits the matrix. Run as part of the
BGS pre-commit hook to keep the doc in sync.

---

## Suggested order

Easiest first to prove the pattern, biggest payoff in the middle, special
cases last.

1. **D4** — `pyenv-brew` outdated (~15 min, trivial brew_observe wrap)
2. **D2** — `nvm` / `nvm-version` outdated (~1 h)
3. **D3** — `script-installer` outdated (~30 min)
4. **B2** — service log paths in evidence (~1 h)
5. **C2** — backup-before-write helper (~1 h)
6. **C3** — desired-value comparison in observe (~1 h)
7. **C4** — fold `compose-file` into `home-artifact` (~30 min)
8. **B3** — `custom-daemon` start_cmd (~2 h)
9. **B4** — decouple `docker-compose-service` from `ai_apps` (~3 h)
10. **C1** — uniform drift detection helper (~3 h)
11. **B1** — uniform state vocabulary check (~1 h, trivial validator)
12. **X1** — per-tier test fixtures (~half day)
13. **X2** — feature-table generator (~1 h)

Total: ~3-5 days of focused work to bring everything to tier-minimum.
Each phase is independent and shippable as its own commit.

## Out of scope

- **D6** (build-deps, pip-bootstrap) — bootstrap targets, no upstream notion.
- New backends for `pkg` (mise, nix, aur) — separate plan, do when needed.
