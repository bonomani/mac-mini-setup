# Driver Migration Plan — Phase 3

## Goal

Eliminate all remaining P1 violations: YAML targets that have embedded shell
code without `driver.kind: custom`. Audit found 15 such targets in three
categories.

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
the embedded code — this is the exact anti-pattern P4 prohibits.
Fix: **change `driver.kind` to `custom`**.

| Target | File | Current kind | Reason to keep custom |
| --- | --- | --- | --- |
| `system-composition` | system.yaml | host-composition | Host introspection, one-off |
| `ai-stack-compose-file` | ai-apps.yaml | compose-file | Compose file path printf only |
| `unsloth-studio` | ai-python-stack.yaml | launchd | Complex launchd + HTTP probe |
| `ariaflow` | dev-tools.yaml | brew-service | HTTP probe + lsof; brew-service runtime driver not yet implemented |
| `ariaflow-web` | dev-tools.yaml | brew-service | Same as ariaflow |
| `ollama` | ollama.yaml | custom-daemon | Daemon probe; custom-daemon not a real driver |

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

### Step 2 — Fix non-custom kinds (Category B)

- [ ] `system.yaml` `system-composition`: `kind: host-composition` → `kind: custom`
- [ ] `ai-apps.yaml` `ai-stack-compose-file`: `kind: compose-file` → `kind: custom`
- [ ] `ai-python-stack.yaml` `unsloth-studio`: `kind: launchd` → `kind: custom`
- [ ] `dev-tools.yaml` `ariaflow` + `ariaflow-web`: `kind: brew-service` → `kind: custom`
- [ ] `ollama.yaml` `ollama`: `kind: custom-daemon` → `kind: custom`
- [ ] Verify: `bash -n`; validator clean

### Step 3 — Investigate docker-resources desired_cmd (Category C)

- [ ] Read `docker-config.yaml` and `lib/drivers/docker.sh`
- [ ] Determine if `desired_cmd` is used by the driver or is dead
- [ ] Remove or convert to `desired_value` as appropriate

### Step 4 — Update validator + docs

- [ ] Remove `brew-service`, `launchd`, `custom-daemon`, `compose-file`,
      `host-composition` from `KNOWN_RUNTIME_DRIVERS` (they are not real
      drivers — they are `custom` with descriptive names)
  - OR keep them in a separate `KNOWN_CUSTOM_SUBKINDS` set (informational only)
- [ ] Update `DRIVER_ARCHITECTURE.md` justified custom table with new entries
- [ ] Update `ANALYSIS.md`

### Step 5 — Commit

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
| `ariaflow` (action) | dev-tools.yaml | brew-service until runtime driver done |
| `pyenv` | python.yaml | Shell init injection + PATH setup |
| `pip-latest` | python.yaml | pip self-upgrade with version check |
| `docker-desktop` | docker.yaml | GUI app with license acceptance |
| `ollama-host-supported` | ollama.yaml | CPU/GPU capability check |
| `mps-available` | ai-python-stack.yaml | Metal MPS hardware detection |
| `open-webui-runtime` + 4 | ai-apps.yaml | Shared compose sentinel pattern |
