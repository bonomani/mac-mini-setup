# Plan: Skip-Display Mode + Preference Scoping

## Context

When running `./install.sh <target>` with explicit args, the output shows
~100 `[skip]` lines for unrelated targets and 4 preference summaries that
don't apply to the selected work. This makes targeted runs noisy and hides
the actual results.

Users need:
1. Choice between **full** display (current — shows every target's state)
   and **fast** display (hides unrelated targets entirely)
2. Preferences shown only when relevant to the selected components

## Changes

### 1. New preference `skip-display-mode`

`defaults/preferences.yaml`:
```yaml
- name: skip-display-mode
  default: full
  options: full|fast
  rationale: 'full: show every target with current state and version (slower observe); fast: hide non-selected targets entirely (faster runs)'
```

### 2. `_ucc_target_filtered_out` respects mode

`lib/ucc_targets.sh` — when target is not in `UCC_TARGET_SET`:
- **full mode** (default): current behavior — observe + print `[skip] ... current state`
- **fast mode**: `return 0` silently, no observe, no output, but still mark in `_UCC_EMITTED_TARGETS`

### 3. Component header hidden in fast mode

`lib/ucc_targets.sh` (or runner side) — track if any target was emitted for
the component; if zero, suppress the `[component]` header line.

### 4. Execution Plan filtering in fast mode

`install.sh` `print_execution_plan()` — when `UIC_PREF_SKIP_DISPLAY_MODE=fast`:
- Show only components that have at least one target in `UCC_TARGET_SET`
- (Or that are auto-pulled as transitive deps via `_resolved`)

### 5. Preference scoping (Option C — derived)

`lib/uic.sh` `load_uic_preferences()`:
- For each preference, scan selected component YAML files (and lib files
  loaded by those components) for references to its env var name
  (`UIC_PREF_<NAME_UPPERCASE>`)
- Only register preferences that are actually referenced by selected work
- Always-relevant preferences (`destructive-updates`, `skip-display-mode`)
  stay global

## Files to modify

| File | Change |
|------|--------|
| `defaults/preferences.yaml` | Add `skip-display-mode` |
| `lib/ucc_targets.sh` | Mode check in `_ucc_target_filtered_out` + component header tracking |
| `install.sh` | Filter execution plan when mode=fast |
| `lib/uic.sh` | Scope preferences to selected components via env var grep |

## Verification

```bash
# Fast mode — minimal output
./install.sh ariaflow --pref skip-display-mode=fast --no-interactive
# Expected: software-bootstrap + node-stack only
# No preference prompts for unrelated prefs

# Full mode (default) — current behavior
./install.sh ariaflow --no-interactive
# Expected: every target with [skip] + current state

# Pin fast mode for future runs
./install.sh --interactive
# Choose fast at the skip-display-mode prompt → saved to ~/.ai-stack/preferences.env
```

## Out of scope

- Display name `(target)` suffix tuning (#2 — do nothing)
- "Resolved target" lines reformatting (#6 — do nothing)
- Setup banner condensing (#7 — do nothing)
