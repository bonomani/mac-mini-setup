# Driver Migration Plan — Phase 3

## Goal

Eliminate all remaining P1 violations and formalize the 3-class driver model
(install / config / runtime). Audit found 15 targets with embedded shell code
not marked `driver.kind: custom`. The proper fix for runtime targets is to
implement real runtime drivers rather than papering over with `custom`.

---

## Findings

### Category A — Dead evidence code (driver already handles it)

These targets have `evidence.*` fields that are unreachable: the driver's own
`_ucc_driver_<kind>_evidence` runs first and returns 0, so the YAML evidence
block is never executed. Fix: **delete the embedded evidence fields**.

| Target | File | Driver | Embedded fields to remove |
| --- | --- | --- | --- |
| `pmset-ac-sleep=0` | macos-defaults.yaml | pmset | `evidence.sleep` |
| `pmset-disksleep=0` | macos-defaults.yaml | pmset | `evidence.disksleep` |
| `pmset-standby=0` | macos-defaults.yaml | pmset | `evidence.standby` |
| `app-nap=disabled` | macos-defaults.yaml | user-defaults | `evidence.NSAppSleepDisabled` |
| `finder-show-hidden=1` | macos-defaults.yaml | user-defaults | `evidence.AppleShowAllFiles` |
| `show-all-extensions=1` | macos-defaults.yaml | user-defaults | `evidence.AppleShowAllExtensions` |
| `dock-autohide=1` | macos-defaults.yaml | user-defaults | `evidence.autohide` |
| `brew-analytics=off` | homebrew.yaml | brew-analytics | `evidence.analytics` |

### Category B — Non-custom kind with no driver implementation (P1 violation)

These targets have embedded code and a `driver.kind` that has no
`_ucc_driver_<kind>_*` functions. The dispatcher silently falls through to
the embedded code — the exact anti-pattern P4 prohibits.
Fix: **implement real drivers** (preferred) or fall back to `kind: custom`.

| Target | File | Current kind | Fix |
| --- | --- | --- | --- |
| `ariaflow` | dev-tools.yaml | brew-service | implement `brew-service` driver |
| `ariaflow-web` | dev-tools.yaml | brew-service | implement `brew-service` driver |
| `unsloth-studio` | ai-python-stack.yaml | launchd | implement `launchd` driver |
| `ollama` | ollama.yaml | custom-daemon | implement `custom-daemon` driver |
| `ai-stack-compose-file` | ai-apps.yaml | compose-file | implement `compose-file` driver |
| `system-composition` | system.yaml | host-composition | `kind: custom` (one-off, no other users) |

### Category C — Investigate

`docker-resources` has a `desired_cmd` field (printf with variable). This is
a data-value computation for the `docker-settings` driver, not embedded
install logic. Verify whether the driver reads `desired_cmd` or `desired_value`
and remove/convert accordingly.

---

## Steps

### Step 1 — Remove dead evidence fields (Category A)

- [ ] `macos-defaults.yaml`: delete `evidence.*` blocks from all 7 targets
- [ ] `homebrew.yaml`: delete `evidence.analytics` from `brew-analytics=off`
- [ ] Verify: `bash -n`; validator clean; no output change

### Step 2 — Implement config driver dispatch

Separate config drivers from install drivers by introducing a dedicated
`apply` verb. Config drivers currently reuse `install`/`update` which is
semantically wrong — config targets are never "installed", they are "applied".

- [ ] Add `_ucc_driver_<kind>_apply` function to all 6 config drivers:
      `json-merge`, `user-defaults`, `pmset`, `softwareupdate-defaults`,
      `brew-analytics`, `docker-settings`
      (body identical to current `_action` for `install|update` case)
- [ ] Update `ucc_drivers.sh`: add `_ucc_driver_apply` dispatcher that routes
      `type: config` / `type: bool` targets to `_apply` instead of `_action`
- [ ] Keep `_ucc_driver_<kind>_action` as a no-op stub (returns 1) so the
      old path falls through cleanly
- [ ] Update `DRIVER_ARCHITECTURE.md` P3 table with new `apply` column
- [ ] Verify: `bash -n`; validator clean

### Step 3 — Implement runtime drivers (Category B)

Implement real observe/start/stop/status functions for each runtime kind,
then migrate Category B targets off embedded code.

#### 3a — `brew-service` driver (2 targets: ariaflow, ariaflow-web)

Fields: `driver.ref` (service name), `driver.port` (optional, for HTTP probe)

- [ ] Implement `lib/drivers/brew_service.sh`:
      `_ucc_driver_brew_service_observe` — `brew services list | grep $ref`
      `_ucc_driver_brew_service_action` — `brew services start/stop $ref`
      `_ucc_driver_brew_service_evidence` — version + pid + listener
- [ ] Source in `lib/ucc_drivers.sh`
- [ ] Add `driver.port` to `_UCC_YAML_BATCH_KEYS`
- [ ] Migrate `ariaflow` + `ariaflow-web` in `dev-tools.yaml`: remove embedded
      oracle/evidence/action, add `driver.port`
- [ ] Add `brew-service` to validator `KNOWN_RUNTIME_DRIVERS`
- [ ] Verify

#### 3b — `launchd` driver (1 target: unsloth-studio)

Fields: `driver.plist` (plist label), `driver.port` (optional)

- [ ] Implement `lib/drivers/launchd.sh`:
      `_ucc_driver_launchd_observe` — `launchctl list | grep $plist`
      `_ucc_driver_launchd_action` — `launchctl load/unload $plist`
      `_ucc_driver_launchd_evidence` — pid + listener
- [ ] Source in `lib/ucc_drivers.sh`
- [ ] Add `driver.plist` to `_UCC_YAML_BATCH_KEYS`
- [ ] Migrate `unsloth-studio` in `ai-python-stack.yaml`
- [ ] Add `launchd` to validator `KNOWN_RUNTIME_DRIVERS`
- [ ] Verify

#### 3c — `custom-daemon` driver (1 target: ollama)

Fields: `driver.probe_url` (HTTP health endpoint), `driver.process` (process name)

- [ ] Implement `lib/drivers/custom_daemon.sh`:
      `_ucc_driver_custom_daemon_observe` — HTTP probe + pgrep
      `_ucc_driver_custom_daemon_action` — no-op (daemon managed externally)
      `_ucc_driver_custom_daemon_evidence` — version + pid + listener
- [ ] Source in `lib/ucc_drivers.sh`
- [ ] Add `driver.probe_url`, `driver.process` to `_UCC_YAML_BATCH_KEYS`
- [ ] Migrate `ollama` in `ollama.yaml`
- [ ] Add `custom-daemon` to validator `KNOWN_RUNTIME_DRIVERS`
- [ ] Verify

#### 3d — `compose-file` driver (1 target: ai-stack-compose-file)

Fields: `driver.path` (path to compose file)

- [ ] Implement `lib/drivers/compose_file.sh`:
      `_ucc_driver_compose_file_observe` — check file exists
      `_ucc_driver_compose_file_action` — no-op (compose managed by runtime targets)
      `_ucc_driver_compose_file_evidence` — `path=$driver.path`
- [ ] Source in `lib/ucc_drivers.sh`
- [ ] Add `driver.path` to `_UCC_YAML_BATCH_KEYS`
- [ ] Migrate `ai-stack-compose-file` in `ai-apps.yaml`
- [ ] Add `compose-file` to validator `KNOWN_RUNTIME_DRIVERS`
- [ ] Verify

#### 3e — `system-composition` (stay custom)

- [ ] `system.yaml` `system-composition`: `kind: host-composition` → `kind: custom`
      (one-off host introspection; no other targets would use a driver)

### Step 4 — Investigate docker-resources desired_cmd (Category C)

- [ ] Read `docker-config.yaml` and `lib/drivers/docker.sh`
- [ ] Determine if `desired_cmd` is used by the driver or is dead
- [ ] Remove or convert to `desired_value` as appropriate

### Step 5 — Update validator + docs

- [ ] Update `KNOWN_RUNTIME_DRIVERS` in validator: remove placeholder kinds
      (`host-composition`), confirm real ones (`brew-service`, `launchd`,
      `custom-daemon`, `compose-file`)
- [ ] Update `DRIVER_ARCHITECTURE.md`: P3 table (add `apply` column), P7 batch
      keys, compliance audit, justified custom table
- [ ] Update `ANALYSIS.md`: driver counts, runtime driver table

### Step 6 — Commit + push

- [ ] `git add + commit + push`

---

## Verification protocol (each step)

1. `bash -n lib/drivers/*.sh`
2. `python3 tools/validate_targets_manifest.py ucc`
3. Diff runtime output: no behaviour change

---

## Out of scope (stay custom — justified)

These targets legitimately keep embedded code; no migration warranted:

| Target | File | Reason |
| --- | --- | --- |
| `homebrew` | homebrew.yaml | Bootstrap — brew not yet available |
| `xcode-command-line-tools` | homebrew.yaml | Interactive xcode-select prompt |
| `git-global-config` | git-config.yaml | Interactive read -rp prompts |
| `softwareupdate-schedule=on` | macos-software-update.yaml | softwareupdate --schedule CLI |
| `vscode-code-cmd` | dev-tools.yaml | One-off symlink creation |
| `oh-my-zsh` | dev-tools.yaml | curl installer + shell change |
| `omz-theme-agnoster` | dev-tools.yaml | File copy into omz theme dir |
| `home-bin-in-path` | dev-tools.yaml | Shell profile PATH injection |
| `ai-healthcheck` | dev-tools.yaml | Multi-service health aggregation |
| `pyenv` | python.yaml | Shell init injection + PATH setup |
| `pip-latest` | python.yaml | pip self-upgrade with version check |
| `docker-desktop` | docker.yaml | GUI app with license acceptance |
| `ollama-host-supported` | ollama.yaml | CPU/GPU capability check |
| `mps-available` | ai-python-stack.yaml | Metal MPS hardware detection |
| `open-webui-runtime` + 4 | ai-apps.yaml | Shared compose sentinel pattern |
