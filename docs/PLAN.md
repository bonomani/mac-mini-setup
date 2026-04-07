# PLAN

## Driver consolidation: 5 groups → 5 generic drivers

Goal: collapse the 28 current driver files into 5 generic drivers, one per
similarity group from `docs/driver-feature-matrix.md`. Ship in dependency
order so each phase de-risks the next.

### Phase 2 — Group D: configuration writers  (~1-2 weeks)

**New driver**: `lib/drivers/config_writer.sh` with `driver.kind: config` and
`driver.format: defaults|pmset|gitconfig|json-merge|line-append|plist|brew-toggle`.

**Absorbs**: `macos_defaults.sh` (`pmset`, `user-defaults`),
`macos_swupdate.sh`, `swupdate_schedule.sh`, `vscode.sh` (`json-merge`),
`git_global.sh`, `zsh_config.sh`, `path_export.sh`, `brew.sh` (`brew-analytics`),
`compose_file.sh`.

**Approach**:
1. Define a `(read, diff, write)` triple per format. Each format implements
   `_cfg_<format>_get key`, `_cfg_<format>_set key value`, optional
   `_cfg_<format>_delete key`.
2. Generic driver dispatches to the triple via `driver.format`.
3. Drop the `apply` vs `action` distinction — config writes are always
   apply-style.
4. Add backup-before-write at the framework level (single place).
5. Add drift detection: a YAML field `desired` is compared to current; only
   writes if different. Already the de-facto pattern; now enforced.
6. Migrate YAML, delete old drivers.

**Risk**: medium. Drift semantics must match per-driver quirks (e.g.
`defaults` types). Requires careful per-format tests.
**Payoff**: 9 → 1 file; eliminates the `apply` hook entirely; uniform drift
detection; one place for backup/rollback.

### Phase 3 — Group C: services / daemons  (~3-5 days)

**New driver**: `lib/drivers/service.sh` with `driver.kind: service` and
`driver.backend: launchd|brew-services|systemd|docker-compose|custom`.

**Absorbs**: `brew_service.sh`, `launchd.sh`, `custom_daemon.sh`,
`docker_compose_service.sh`.

**Approach**:
1. Standardize state vocabulary: `stopped | started | failed | autostart_on
   | autostart_off`.
2. Per-backend interface: `_svc_<backend>_status`, `_svc_<backend>_start`,
   `_svc_<backend>_stop`, `_svc_<backend>_enable`, `_svc_<backend>_disable`.
3. Generic driver maps `desired_state` (from YAML) to the right backend call.
4. Keep `provided_by` / `depends_on` declarations for each backend.
5. Migrate YAML, delete old drivers.

**Risk**: medium. Backends differ wildly in YAML shape — the generic schema
must accommodate launchd plists *and* brew-service refs *and* compose files
without becoming a kitchen sink. Mitigation: backend-specific sub-objects
under `driver.<backend>`.
**Payoff**: 4 → 1 file; uniform service status reporting; one place to add
new init systems.

### Phase 4 — Group A: package installers  (~2-3 weeks)

**New driver**: `lib/drivers/package_v2.sh` (eventually replacing
`package.sh`) with `driver.kind: package` and
`driver.backend: brew|brew-cask|brew-tap|apt|dnf|pacman|zypper|npm|pip|pyenv|nvm|ollama|vscode-marketplace|curl|script`.

**Absorbs**: `brew.sh` (formula branch), `package.sh` (existing meta),
`build_deps.sh`, `npm.sh`, `pip.sh`, `pip_bootstrap.sh`, `pyenv.sh`,
`pyenv_brew.sh`, `nvm.sh`, `ollama_model.sh`, `vscode.sh`
(`vscode-marketplace`), `curl_installer.sh`, `script_installer.sh`.

**Approach**:
1. Backend registry: each backend implements
   `_pkg_<backend>_observe/_install/_update/_outdated/_version/_activate`.
2. Per-target backend list (from `docs/install-method-gaps.md` design):
   ```yaml
   driver:
     kind: package
     ref: opencode
     backends:
       - npm: opencode-ai
       - brew-tap: anomalyco/tap/opencode
       - brew: opencode
       - curl: https://opencode.ai/install
   ```
3. Selection policy: first available backend wins;
   `UCC_DRIVER__<TARGET>` env override and `~/.config/ucc/overrides.yaml`
   overlay take precedence.
4. Runtime activation: `_pkg_<backend>_activate` is called before any
   action, replacing the per-driver `_*_ensure_path` helpers
   (`docs/runtime-activation-gaps.md`).
5. Migration safety: foreign-install handler stays as today, but the
   probe is registered per backend pair instead of per driver.
6. Outdated detection: each backend implements `_pkg_<backend>_outdated`
   uniformly. Drivers without a native source plug into a shared
   `_pkg_github_release_check` helper using `driver.github_repo`.
7. Migrate YAML in waves: first the easy 1-backend targets, then the
   multi-backend ones.

**Risk**: high. Touches ~50 targets and the most-used code paths. Mitigation:
keep `package.sh` and the old kinds sourced in parallel during migration;
flip targets one at a time; full pytest run between waves.
**Payoff**: 13 → 1 file; multi-backend per target; uniform outdated/migration/
activation; eliminates the gaps documented in `update-detection-gaps.md`,
`install-method-gaps.md`, and `runtime-activation-gaps.md` in one stroke.

### Phase 5 — Group B: GUI / app bundles  (~1 day)

**New driver**: `lib/drivers/app_bundle_v2.sh` with `driver.kind: app-bundle`
and `driver.backend: brew-cask|dmg|pkg|zip`.

**Absorbs**: `app_bundle.sh`, brew-cask branch of `brew.sh`.

**Approach**:
1. Trivial wrapper now that group A's backend pattern exists — reuse the
   registry conventions.
2. Always destructive on migration; always require sudo gate.
3. Migrate YAML, delete dead branches.

**Risk**: low. Few targets, narrow surface.
**Payoff**: 2 → 1 file; consistent with the rest.

## Cross-cutting work (do once during phase 1)

- **Compat shim**: `_ucc_driver_<old_kind>_*` functions delegate to the new
  generic driver until YAML migration is complete. Delete after each phase.
- **Test harness**: per-driver pytest fixture that loads only that driver
  file and asserts its observe/action contract. Runs in CI for both old and
  new drivers during the migration window.
- **Doc updates**: `DRIVER_ARCHITECTURE.md` rewritten at the end of each
  phase; gap docs deleted as their gaps close.

## Sequencing rationale

1. **Phase 1 first** — proves the migration mechanics on the safest group.
2. **Phase 2 next** — biggest conceptual win, no runtime dependencies on
   group A.
3. **Phase 3** — standalone, low coupling.
4. **Phase 4** — biggest, riskiest; benefits from helpers and patterns
   refined in earlier phases.
5. **Phase 5** — trivial cleanup using group A's machinery.

## Total estimate

~5-7 weeks of focused work. Each phase is independently shippable and
reversible (compat shim).
