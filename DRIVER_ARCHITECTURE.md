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
- `_ucc_driver_<kind>_observe  <cfg_dir> <yaml> <target>`       → prints raw state string
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

### P1 — YAML is pure data

| Status | Count | Detail |
|--------|-------|--------|
| ✅ Correct `custom` | 16 | All remaining embedded-code targets have `driver.kind: custom` |
| ⚠️ Grey area | 5 | `ai-apps.yaml`: `open-webui-runtime`, `flowise-runtime`, `openhands-runtime`, `n8n-runtime`, `qdrant-runtime` — use `driver.kind: docker-compose` but that driver is not implemented; embedded `actions:` still present |
| ⚠️ Grey area | 1 | `ai-python-stack.yaml: mps-available` — uses `driver.kind: capability` (unimplemented); shell code in `evidence.status` |
| ⚠️ Dead code | 1 | `docker-config.yaml: docker-resources` — `driver.kind: docker-settings` is implemented and driver evidence runs first, but the YAML still contains the old inline Python in `evidence.memory` / `evidence.cpus` (never executed, but not cleaned up) |

**Assessment: PARTIALLY APPLIED.**
All legacy targets are correctly gated by `custom`. However, 6 targets use future-driver
kinds (`docker-compose`, `capability`) that aren't implemented yet, causing silent fall-through
to embedded code without using the `custom` marker. The intent is different — these are
*planned* drivers — but the current observable behaviour is indistinguishable from a
forgotten migration. These should either be implemented or temporarily marked `custom`.

### P2 — Single dispatch point

**FULLY APPLIED.**
`lib/ucc_drivers.sh` contains zero per-target conditions. The dispatch is purely:
```bash
local fn="_ucc_driver_${kind//-/_}_observe"
declare -f "$fn" >/dev/null 2>&1 || return 1
"$fn" "$cfg_dir" "$yaml" "$target"
```
No special-casing for any target or kind.

### P3 — Uniform driver interface

All implemented drivers:

| Driver | observe | action | evidence | Notes |
|--------|---------|--------|----------|-------|
| brew-formula | ✅ | ✅ | ✅ | |
| brew-cask | ✅ | ✅ | ✅ | |
| brew-analytics | ✅ | ✅ | ✅ | |
| vscode-marketplace | ✅ | ✅ | ✅ | |
| json-merge | ✅ | ✅ | ✅ | |
| ollama-model | ✅ | ✅ | ✅ | |
| npm-global | ✅ | ✅ | ✅ | |
| pip | ✅ | ✅ | ✅ | |
| user-defaults | ✅ | ✅ | ✅ | |
| pmset | ✅ | ✅ | ✅ | |
| softwareupdate-defaults | ✅ | ✅ | ✅ | |
| docker-settings | ✅ | ✅ | ✅ | evidence uses inline heredoc Python |
| docker-compose | ❌ | ❌ | ❌ | declared in YAML, not yet implemented |
| capability | ❌ | ❌ | ❌ | declared in YAML, not yet implemented |

**Assessment: PARTIALLY APPLIED** for implemented drivers (all 12 are complete).
Two declared driver kinds have no implementation.

### P4 — Escape hatch is explicit, not implicit

**PARTIALLY APPLIED.**
All 16 targets retaining embedded code for legitimate reasons are correctly marked
`driver.kind: custom`. However, the 6 targets with unimplemented driver kinds
(`docker-compose`, `capability`) also fall through silently to embedded code —
identical observable behaviour to `custom` but without the explicit marker.
The distinction matters for tooling (validator, future audits).

### P5 — State model wrapping

**FULLY APPLIED.**
Both dispatch sites in `ucc_targets.sh` wrap driver output before returning:

- `_ucc_observe_yaml_simple_target` (line ~248): wraps via `ucc_asm_package_state` /
  `ucc_asm_config_state` based on `state_model`
- `_ucc_observe_yaml_parametric_target` (line ~491): wraps via
  `_ucc_yaml_parametric_observed_state`

No driver emits JSON directly; all emit plain strings (`"absent"`, version strings,
`"on"/"off"`, `"configured"`).

### P6 — Empty-field guards

**FULLY APPLIED** for all implemented drivers that have required fields:
- `brew-formula`, `brew-cask`: `[[ -n "$ref" ]] || return 1`
- `json-merge`, `vscode.sh`: `[[ -n "$rel_settings" && -n "$rel_patch" ]] || return 1`
- `user-defaults`, `softwareupdate-defaults`: `[[ -n "$domain" && -n "$key" ]] || return 1`
- `pmset`: `[[ -n "$setting" ]] || return 1`
- `docker-settings`: `[[ -n "$DOCKER_SETTINGS_PATH" ]] || return 1`

Minor gap: `ollama-model` and `npm-global` do not guard against empty `driver.ref` /
`driver.package`. An empty ref would silently pass an empty string to
`ollama_model_present` / `npm_global_observe`. Not a practical issue (all targets
have these fields set) but inconsistent with the pattern.

### P7 — Cache pre-loading

**FULLY APPLIED.**
All driver fields used at runtime appear in `_UCC_YAML_BATCH_KEYS` (install.sh lines 537–547):
```
driver.ref  driver.probe_pkg  driver.install_packages
driver.min_version  driver.extension_id  driver.package
driver.domain  driver.key  driver.value  driver.type  driver.setting
driver.settings_relpath  driver.patch_relpath
driver.kind  driver.greedy_auto_updates
```

### P8 — Evidence parity

**FULLY APPLIED** for all 12 implemented drivers.
One consistency note: `docker-settings` evidence is implemented as an inline heredoc
Python script rather than delegating to `docker_settings.py` (unlike the observe/action
functions). The behaviour is correct but breaks the pattern of using the extracted tool.

---

## Summary

| Principle | Status |
|-----------|--------|
| P1 — YAML is pure data | ⚠️ Partially applied (6 targets with unimplemented driver kinds fall through implicitly) |
| P2 — Single dispatch point | ✅ Fully applied |
| P3 — Uniform driver interface | ⚠️ Partially applied (docker-compose, capability not implemented) |
| P4 — Explicit escape hatch | ⚠️ Partially applied (same 6 targets as P1) |
| P5 — State model wrapping | ✅ Fully applied |
| P6 — Empty-field guards | ⚠️ Minor gap: ollama-model, npm-global missing empty-ref guard |
| P7 — Cache pre-loading | ✅ Fully applied |
| P8 — Evidence parity | ✅ Fully applied |

## Recommended follow-up actions

1. **Implement `docker-compose` driver** (5 targets in ai-apps.yaml) or mark them
   `driver.kind: custom` until implemented.
2. **Implement `capability` driver** (mps-available) or mark it `driver.kind: custom`.
3. **Remove dead evidence code** from `docker-config.yaml: docker-resources`
   (the inline Python in `evidence.memory`/`evidence.cpus` is never reached).
4. **Add empty-field guards** to `ollama-model` and `npm-global` drivers for consistency.
5. **Consider moving docker-settings evidence** to `docker_settings.py read` to maintain
   the pattern of evidence via the extracted tool.
