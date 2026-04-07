# PLAN

## Driver consolidation: 5 groups → 5 generic drivers

Goal: collapse the 28 current driver files into 5 generic drivers, one per
similarity group from `docs/driver-feature-matrix.md`. Ship in dependency
order so each phase de-risks the next.

### Phase 0b — Cross-cutting: user override layer  (~2-3 days)

**Problem**: targets are configured in tracked YAML, but every box has
exceptions (offline, corporate mirror, missing runtime, deliberate
divergence). Today the only escape is to edit tracked files. Documented in
`docs/install-method-gaps.md` under "User override".

**Approach**:
1. New env-var convention: `UCC_DRIVER__<TARGET>=<kind>:<ref>` (target name
   normalized, `-` → `_`). Resolved before driver dispatch in
   `_ucc_driver_observe`/`_action`.
2. New overlay file: `~/.config/ucc/overrides.yaml`, deep-merged on top of
   tracked YAML by `_ucc_yaml_target_get`.
3. Precedence (highest wins): env var > overlay file > tracked YAML.
4. New CLI: `install.sh --show-overrides` lists each target's effective
   driver and the source (env / overlay / yaml), so users can audit drift.
5. Tests: env override takes precedence; overlay merges field-by-field;
   missing overlay file is silent; malformed overlay is a hard error.

**Why before Phase 4**: the package driver's multi-backend selection logic
needs an override surface to consume on day one. Building the override layer
first means Phase 4 plugs into it instead of inventing its own.

**Why cross-cutting (not Phase-4-only)**: every driver benefits, not just
package. A user might want to override `git_global` user.email per-machine,
or pin a `service` driver to a specific backend. Keeping it general avoids
re-doing it later.

### Phase 0c — BGS Grade-2 compliance refresh against `BGSPrivate/bgs`  (~1 day)

**Problem**: BGS canonical home moved to `~/repos/github/bonomani/BGSPrivate/bgs/`
and advanced to Grade 2 (Extension Model: profiles + policies, mechanical
validators, stricter schema). This repo's BGS artifacts predate that and
would fail `tools/check-bgs-compliance.py`.

**Concrete gaps**:
1. `docs/bgs-decision.md` is missing schema-required fields:
   `decision_id`, `bgs_version_ref` (immutable, no branch),
   `members_used`, `overlays_used`, `member_version_refs` (sha/tag per
   member), `external_controls` (5 required keys),
   `evidence_refs[]`.
2. CR-7 violations: any `master`/`HEAD`/`main` refs in BGS docs are
   rejected. Replace with sha or tag.
3. `BGS.md` lacks `bgs_version_ref` and a pointer at the new canonical
   home.
4. `docs/bgs-compliance-report.md` references the old `bgs/` paths in
   places.
5. README.md / cross-doc links may still point at the old location.
6. Validator never wired into CI.

**Approach**:
1. Re-shape `docs/bgs-decision.md` to satisfy
   `BGSPrivate/bgs/schemas/decision-record.schema.json`:
   - Add all required fields with concrete values.
   - `members_used: [BISS, ASM, UIC, UCC]`.
   - `overlays_used: []` unless adopting `Basic`/`RIG`.
   - `member_version_refs`: pin each member to a sha or tag from its
     repo (UIC, UCC, ASM, BISS — TIC if listed).
   - `external_controls`: declare each of the 5 keys as
     `external` / `out_of_scope` / `in_scope_with_link`.
   - `evidence_refs[]`: list paths to UIC preflight artifacts, UCC
     convergence reports, ASM model doc, BISS classification doc.
2. Update `BGS.md`: add `bgs_version_ref: bgs@<sha-or-tag>` and
   `bgs_canonical: ../BGSPrivate/bgs`.
3. Refresh `docs/bgs-compliance-report.md`:
   - Re-point to `BGSPrivate/bgs` for slice/schema/example refs.
   - Verify CR-1a (smallest sufficient slice), CR-1b (ASM-based for
     stateful), CR-7 (no branch refs) all still hold.
4. Optional Grade-2 declaration: if/when the schema gains
   `profiles_used`, declare ASM's `SOFTWARE-MODEL.md` profile (we use
   its `state_model: package|config|...` vocabulary throughout YAML).
5. Wire the validator:
   ```sh
   python3 ../BGSPrivate/bgs/tools/check-bgs-compliance.py docs/bgs-decision.md
   ```
   Add as a pre-commit hook or CI step. Fail the run on validation
   error.
6. `git grep` for `../bgs/` and `bgs/` references; rewrite to
   `BGSPrivate/bgs/` where they refer to the suite (not this repo's
   own state).

**Risk**: low. Pure docs and metadata. No code paths affected.
**Payoff**: passes the new validator, audit-ready, sets up mechanical
drift detection so the next BGS bump is a one-command refresh instead
of a forensic exercise.

**Out of scope**:
- Adopting new overlays (`Basic`, `RIG`) — declare absence honestly.
- Claiming SMGV (would require formalizing TIC as a slice member) —
  separate decision.
- Profile/policy declarations — additive in Grade 2; do later if
  needed.

### Phase 1 — Group E: filesystem plumbing  (~1-2 days)

**New driver**: `lib/drivers/fs_artifact.sh` with `driver.kind: fs-artifact`
and `driver.subkind: symlink|file|repo|unlink`.

**Absorbs**: `bin_script.sh`, `cli_symlink.sh`, `brew_unlink.sh`, `git_repo.sh`.

**Approach**:
1. Define a uniform interface: `_fs_<subkind>_observe/_action/_evidence`.
2. Move existing logic verbatim under the subkind dispatch.
3. Add a YAML compat shim: old `kind: bin-script` etc. dispatches to the new
   driver until all YAML is migrated.
4. Migrate YAML targets one component at a time.
5. Delete the old driver files when no YAML references them.

**Risk**: very low. No semantic change.
**Payoff**: 4 → 1 file; proves the consolidation pattern.

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
