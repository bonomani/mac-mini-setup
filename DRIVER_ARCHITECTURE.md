# Driver Architecture — Principles & Compliance Audit

## Principles

### P1 — YAML is pure data

YAML files contain no executable shell code. Fields `observe_cmd`, `actions.*`, and
`evidence.*` (with embedded shell/Python) must not appear except in targets explicitly
marked `driver.kind: custom`.

### P2 — Single dispatch point

`driver.kind` is the sole routing key. No per-target conditional logic exists in the
dispatcher. `ucc_drivers.sh` derives the function name mechanically:
`_ucc_driver_${kind//-/_}_{observe,action,evidence}`.

### P3 — Uniform driver interface

Every driver implements exactly three functions:

- `_ucc_driver_<kind>_observe  <cfg_dir> <yaml> <target>`        → prints raw state string
- `_ucc_driver_<kind>_action   <cfg_dir> <yaml> <target> <verb>` → executes install/update
- `_ucc_driver_<kind>_evidence <cfg_dir> <yaml> <target>`        → prints `key=val` lines

No partial implementations without an explicit documented reason.

### P4 — Escape hatch is explicit, not implicit

`driver.kind: custom` is the only valid way to keep embedded code in YAML.
A target without `driver.kind` falls through silently (dispatcher returns 1).
This distinguishes "intentionally keeping embedded code" from "forgot to migrate".

### P5 — State model wrapping

Driver observe functions return raw strings (e.g. `"1.8.1"`, `"absent"`, `"on"`).
The dispatch layer in `ucc_targets.sh` wraps them through the correct state-model
function before returning — never raw:

- Simple targets:     `ucc_asm_package_state` or `ucc_asm_config_state`
- Parametric targets: `_ucc_yaml_parametric_observed_state`

Drivers must **never** emit JSON directly.

### P6 — Empty-field guards

A driver must return 1 when a required field (e.g. `driver.ref`) is absent.
This allows targets that share the same `driver.kind` but lack that field to fall
through cleanly to their own embedded logic, without crashing.

### P7 — Cache pre-loading

All `driver.*` fields read at runtime must be listed in `_UCC_YAML_BATCH_KEYS`
(install.sh) so the per-file batch cache covers them. Missing entries cause
live `python3` spawns on the hot path.

### P8 — Evidence parity

Every driver that implements observe/action must also implement evidence.
Evidence is the audit trail shown to the user; omitting it creates invisible installs.

---

## Compliance Audit

**P1 — YAML is pure data** — FULLY APPLIED.
All targets with embedded shell code are marked `driver.kind: custom` (20 targets).
No violations.

**P2 — Single dispatch point** — FULLY APPLIED.
`lib/ucc_drivers.sh` contains zero per-target conditions:

```bash
local fn="_ucc_driver_${kind//-/_}_observe"
declare -f "$fn" >/dev/null 2>&1 || return 1
"$fn" "$cfg_dir" "$yaml" "$target"
```

**P3 — Uniform driver interface** — FULLY APPLIED. All 17 drivers implement observe/action/evidence.
Config drivers additionally implement `apply` (called by `_ucc_driver_apply`).

**Install drivers** (`type: package`)

| Driver                  | observe | action | evidence | Notes                                             |
| ----------------------- | :-----: | :----: | :------: | ------------------------------------------------- |
| brew                    |    ✅   |   ✅   |    ✅    | cask=true for casks; previous_ref → force-link    |
| app-bundle              |    ✅   |   ✅   |    ✅    | delegates to brew-cask when cask installed        |
| pyenv-version           |    ✅   |   ✅   |    ✅    | respects UIC_PREF_PYTHON_VERSION override         |
| vscode-marketplace      |    ✅   |   ✅   |    ✅    |                                                   |
| ollama-model            |    ✅   |   ✅   |    ✅    |                                                   |
| npm-global              |    ✅   |   ✅   |    ✅    |                                                   |
| pip                     |    ✅   |   ✅   |    ✅    |                                                   |

**Config drivers** (`type: config`, `type: bool`) — also implement `_apply`

| Driver                  | observe | action | apply | evidence | Notes                                        |
| ----------------------- | :-----: | :----: | :---: | :------: | -------------------------------------------- |
| brew-analytics          |    ✅   |   ✅   |  ✅   |    ✅    |                                              |
| json-merge              |    ✅   |   ✅   |  ✅   |    ✅    |                                              |
| user-defaults           |    ✅   |   ✅   |  ✅   |    ✅    |                                              |
| pmset                   |    ✅   |   ✅   |  ✅   |    ✅    |                                              |
| softwareupdate-defaults |    ✅   |   ✅   |  ✅   |    ✅    |                                              |
| docker-settings         |    ✅   |   ✅   |  ✅   |    ✅    | evidence uses inline heredoc Python          |

**Runtime drivers** (`type: runtime`)

| Driver                  | observe | action | evidence | Notes                                             |
| ----------------------- | :-----: | :----: | :------: | ------------------------------------------------- |
| brew-service            |    ✅   |   ✅   |    ✅    | start/stop via brew services                      |
| launchd                 |    ✅   |   ✅   |    ✅    | load/unload via launchctl                         |
| custom-daemon           |    ✅   |   —    |    ✅    | observe only; daemon started externally           |
| compose-file            |    ✅   |   —    |    ✅    | observe file exists; managed by compose           |

**P4 — Explicit escape hatch** — FULLY APPLIED.
Every target retaining embedded code carries `driver.kind: custom`. No silent fall-throughs.

**P5 — State model wrapping** — FULLY APPLIED.
Both dispatch sites wrap driver output before returning:
`_ucc_observe_yaml_simple_target` via `ucc_asm_package_state` / `ucc_asm_config_state`;
`_ucc_observe_yaml_parametric_target` via `_ucc_yaml_parametric_observed_state`.
No driver emits JSON directly.

**P6 — Empty-field guards** — FULLY APPLIED for all implemented drivers:
`brew/ollama-model/brew-service`: `[[ -n "$ref" ]] || return 1`;
`npm-global`: `[[ -n "$pkg" ]] || return 1`;
`json-merge`: `[[ -n "$rel_settings" && -n "$rel_patch" ]] || return 1`;
`user-defaults/softwareupdate-defaults`: `[[ -n "$domain" && -n "$key" ]] || return 1`;
`pmset`: `[[ -n "$setting" ]] || return 1`;
`docker-settings`: `[[ -n "$DOCKER_SETTINGS_PATH" ]] || return 1`;
`app-bundle`: `[[ -n "$app_path" ]] || return 1`;
`launchd/custom-daemon`: `[[ -n "$plist" ]] || return 1` / `[[ -n "$bin" ]] || return 1`.

**P7 — Cache pre-loading** — FULLY APPLIED.
All `driver.*` fields appear in `_UCC_YAML_BATCH_KEYS` (install.sh):
`driver.ref`, `driver.probe_pkg`, `driver.install_packages`, `driver.min_version`,
`driver.extension_id`, `driver.package`, `driver.domain`, `driver.key`, `driver.value`,
`driver.type`, `driver.setting`, `driver.settings_relpath`, `driver.patch_relpath`,
`driver.kind`, `driver.cask`, `driver.greedy_auto_updates`, `driver.app_path`, `driver.brew_cask`,
`driver.update_api`, `driver.download_url_tpl`, `driver.package_ext`,
`driver.version`, `driver.previous_ref`, `driver.cask`,
`driver.plist`, `driver.bin`, `driver.process`, `driver.path_env`.

**P8 — Evidence parity** — FULLY APPLIED for all 17 implemented drivers.
Note: `docker-settings` evidence uses an inline heredoc Python script rather than
delegating to `docker_settings.py` — correct behaviour, style inconsistency only.
Note: `custom-daemon` and `compose-file` action returns 1 (no-op) by design —
these are externally managed; no install/update action is appropriate.

---

## Summary

| Principle               | Status            |
| ----------------------- | ----------------- |
| P1 — YAML is pure data  | ✅ Fully applied  |
| P2 — Single dispatch    | ✅ Fully applied  |
| P3 — Uniform interface  | ✅ Fully applied  |
| P4 — Explicit escape    | ✅ Fully applied  |
| P5 — State model wrap   | ✅ Fully applied  |
| P6 — Empty-field guards | ✅ Fully applied  |
| P7 — Cache pre-loading  | ✅ Fully applied  |
| P8 — Evidence parity    | ✅ Fully applied  |

---

## Justified `driver.kind: custom` targets

These targets legitimately retain embedded code, grouped by reason.

### Category A — Component-coupled shared action

`type: runtime` targets managed by `runtime_manager: docker-compose`. Their install
action (`_ai_apply_compose_runtime`) is intentionally **shared across all 5 services**
via a sentinel file — one `docker compose up -d` for the whole stack, not one per
target. A per-target driver dispatch would break this by running compose 5 times.
The evidence functions (`_ai_service_runtime_*`) depend on Docker image metadata
built inside `ai_apps.sh`'s component context and cannot be extracted to a generic
driver without re-implementing that pipeline.

| Target              | File          |
| ------------------- | ------------- |
| open-webui-runtime  | ai-apps.yaml  |
| flowise-runtime     | ai-apps.yaml  |
| openhands-runtime   | ai-apps.yaml  |
| n8n-runtime         | ai-apps.yaml  |
| qdrant-runtime      | ai-apps.yaml  |

### Category B — Capability probe (observe-only, no install/update)

`type: capability` / `type: runtime` targets that only detect hardware or OS capabilities.
No install action exists; the target is read-only. A driver would implement only observe
and evidence — partial interface, not worth the abstraction.

| Target                | File                    | Reason                             |
| --------------------- | ----------------------- | ---------------------------------- |
| mps-available         | ai-python-stack.yaml    | Metal MPS hardware detection       |
| ollama-host-supported | ollama.yaml             | CPU/GPU capability check           |

### Category C — Complex or interactive logic

Targets with non-trivial install logic (interactive prompts, multi-step loops,
external tool bootstrapping) that cannot be expressed as a parameterised driver.

| Target                  | File                         | Reason                                      |
| ----------------------- | ---------------------------- | ------------------------------------------- |
| homebrew                | homebrew.yaml                | Bootstrap installer — no brew available yet |
| xcode-command-line-tools| homebrew.yaml                | `xcode-select --install` interactive prompt |
| vscode-code-cmd         | dev-tools.yaml               | Symlink creation with path check            |
| oh-my-zsh               | dev-tools.yaml               | curl installer + shell change               |
| omz-theme-agnoster      | dev-tools.yaml               | File copy into omz theme dir                |
| home-bin-in-path        | dev-tools.yaml               | Shell profile PATH injection                |
| ai-healthcheck          | dev-tools.yaml               | Multi-service health aggregation            |
| ariaflow                | dev-tools.yaml               | Tap + multi-package brew install            |
| docker-desktop          | docker.yaml                  | GUI app with license acceptance             |
| pyenv                   | python.yaml                  | Shell init injection + PATH setup           |
| pip-latest              | python.yaml                  | pip self-upgrade with version check         |
| git-global-config       | git-config.yaml              | Interactive `read -rp` prompts              |
| softwareupdate-schedule | macos-software-update.yaml   | `softwareupdate --schedule` CLI             |

---

## Open improvements

1. **`docker-settings` evidence**: move inline heredoc Python to `docker_settings.py read`
   to match the extracted-tool pattern used by observe/action.
2. **Version on `updated` line**: framework-level change needed in `ucc_targets.sh`
   to append evidence to the `updated` emit (currently only shows ASM state diff;
   evidence is shown on `ok`/`warn`/`fail` only).
