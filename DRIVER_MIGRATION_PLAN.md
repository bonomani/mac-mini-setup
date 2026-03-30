# Driver Migration Plan
# Move embedded shell code from YAML into named shell driver functions

## Goal
Replace eval'd shell strings in YAML (`observe_cmd`, `actions.*`, `evidence.*`)
with named shell functions dispatched by `driver.kind`. YAML becomes pure data.
The existing `observe_cmd`/`actions.*` path becomes a `driver.kind: custom`
escape hatch for targets with truly unique logic.

## Architecture

### Dispatch hook (3 insertion points in ucc_targets.sh)
1. `_ucc_observe_yaml_simple_target` — before reading observe_cmd
2. `_ucc_run_yaml_action` — before reading actions.*
3. `ucc_eval_evidence_from_yaml` — before reading evidence.*

Each hook: read `driver.kind` from cache → call `_ucc_driver_<hook>` →
return if handled, fall through to existing eval path if unknown kind.

### New files
- `lib/ucc_drivers.sh`        — dispatch hub (sourced by ucc.sh)
- `lib/drivers/brew.sh`       — brew-formula, brew-cask
- `lib/drivers/vscode.sh`     — vscode-marketplace
- `lib/drivers/ollama_model.sh` — ollama-model
- `lib/drivers/npm.sh`        — npm-global
- `lib/drivers/pip.sh`        — pip

### Cache prerequisite
Add to `_UCC_YAML_BATCH_KEYS` in install.sh:
  driver.ref  driver.probe_pkg  driver.install_packages
  driver.min_version  driver.extension_id  driver.package

---

## Phase 1 — Group A: mechanical drivers (no YAML schema change)
All embedded code is a single function call with an existing driver.* field.
~57 targets. No behavioral change — just moves code from YAML to shell.

### Step 0 — Prerequisites
- [x] Add driver.* keys to _UCC_YAML_BATCH_KEYS in install.sh
- [x] Source lib/ucc_drivers.sh from lib/ucc.sh
- [x] Create lib/drivers/ directory

### Step 1 — Dispatch infrastructure
- [x] Create lib/ucc_drivers.sh with:
      _ucc_driver_observe  <cfg_dir> <yaml> <target> <kind>  → dispatches or returns 1
      _ucc_driver_action   <cfg_dir> <yaml> <target> <action> <kind>  → dispatches or returns 1
      _ucc_driver_evidence <cfg_dir> <yaml> <target> <kind>  → dispatches or returns 1
- [x] Add dispatch hook to _ucc_observe_yaml_simple_target (ucc_targets.sh)
- [x] Add dispatch hook to _ucc_run_yaml_action (ucc_targets.sh)
- [x] Add dispatch hook to ucc_eval_evidence_from_yaml (ucc_targets.sh)

### Step 2 — ollama-model driver  (7 targets, simplest)
Driver fields: driver.ref
observe:  ollama_model_present '$ref' && printf '%s' '$ref' || printf absent
install:  ollama_model_pull '$ref'
update:   ollama_model_pull '$ref'
evidence: model → printf '%s' '$ref'

- [x] Implement lib/drivers/ollama_model.sh
- [x] Remove observe_cmd/actions/evidence from ollama.yaml (ollama-model-* targets)
- [ ] Verify: bash -n; run Profile Configured diff

### Step 3 — npm-global driver  (3 targets)
Driver fields: driver.package
observe:  npm_global_observe '$pkg'
install:  npm_global_install '$pkg'
update:   npm_global_update '$pkg'
evidence: version → npm_global_version '$pkg'

- [x] Implement lib/drivers/npm.sh
- [x] Remove observe_cmd/actions/evidence from dev-tools.yaml (npm-global-* targets)
- [ ] Verify

### Step 4 — vscode-marketplace driver  (7 targets)
Driver fields: driver.extension_id
observe:  ver=$(_vscode_extension_cached_version '$id'); printf '%s' "${ver:-absent}"
install:  vscode_extension_install '$id'
update:   vscode_extension_update '$id'
evidence: version → _vscode_extension_cached_version '$id'

- [x] Implement lib/drivers/vscode.sh
- [x] Remove observe_cmd/actions/evidence from dev-tools.yaml (vscode-ext-* targets)
- [ ] Verify

### Step 5 — brew-formula driver  (simple ref targets: ~23 targets)
Targets with driver.ref set AND using only brew_observe/install/upgrade.
Excludes: node-lts (custom logic), python/pyenv (custom logic).
Driver fields: driver.ref
observe:  brew_observe '$ref'
install:  brew_install '$ref'
update:   brew_upgrade '$ref'
evidence: version → _brew_cached_version '$ref'

- [x] Implement lib/drivers/brew.sh (brew_formula section)
- [ ] Remove observe_cmd/actions/evidence from:
      dev-tools.yaml  (all cli-* targets)
      git.yaml        (git target)
      python.yaml     (xz target)
- [ ] Verify

### Step 6 — brew-cask driver  (simple ref targets: iterm2, lm-studio)
Targets with driver.ref set. Excludes vscode (uses top-level vars, no driver.ref).
Driver fields: driver.ref, driver.greedy_auto_updates
observe:  brew_cask_observe '$ref' '$greedy'
install:  brew_cask_install '$ref'
update:   brew_cask_upgrade '$ref' '$greedy'
evidence: version → _brew_cask_cached_version '$ref'

- [ ] Implement brew-cask section in lib/drivers/brew.sh
- [ ] Remove observe_cmd/actions/evidence from dev-tools.yaml (iterm2, lm-studio)
- [ ] Verify

### Step 7 — pip driver  (12 targets)
Driver fields: driver.probe_pkg, driver.install_packages, driver.min_version
observe:  ver=$(_pip_cached_version '$probe'); if empty → absent;
          if min_version set → python3 version compare; else → ver
install:  ucc_run pip install -q $install_packages && pip_cache_versions
update:   ucc_run pip install -q --upgrade $install_packages && pip_cache_versions
evidence: version → _pip_cached_version '$probe'
          pkg    → printf '%s' '$probe'

- [x] Implement lib/drivers/pip.sh
- [x] Remove observe_cmd/actions/evidence from ai-python-stack.yaml (pip-group-* targets)
- [ ] Verify

### Step 8 — Commit Phase 1
- [ ] git add + commit all Phase 1 changes
- [ ] git push

---

## Phase 2 — Group B: data drivers (YAML schema extension required)
Embedded code is mechanical but parameters are hardcoded in shell strings.
Requires adding driver.* fields to YAML and implementing shell handlers.
~14 targets.

### Step 9 — user-defaults driver  (4 targets: app-nap, finder, extensions, dock)
New driver fields: driver.domain, driver.key, driver.value, driver.type (bool|int|string)
observe:  defaults read '$domain' '$key' 2>/dev/null || echo 0
oracle:   defaults read '$domain' '$key' 2>/dev/null | grep -q '^$value$'
install:  ucc_run defaults write '$domain' '$key' -$type $value
evidence: $key → defaults read '$domain' '$key' 2>/dev/null

- [ ] Implement lib/drivers/macos_defaults.sh (user-defaults section)
- [ ] Update macos-defaults.yaml: add driver.domain/key/value/type, remove embedded code
- [ ] Verify

### Step 10 — pmset driver  (3 targets)
New driver fields: driver.setting, driver.value
observe:  pmset -g | awk -v s='$setting' '$1==s{print $2}'
oracle:   pmset -g | awk -v s='$setting' -v v='$value' '$1==s && $2==v{exit 0} END{exit 1}'
install:  ucc_run pmset -a '$setting' '$value'
evidence: $setting → pmset -g | awk -v s='$setting' '$1==s{print $2}'

- [ ] Implement pmset section in lib/drivers/macos_defaults.sh
- [ ] Update macos-defaults.yaml: add driver.setting/value, remove embedded code
- [ ] Verify

### Step 11 — softwareupdate-defaults driver  (5 targets)
New driver fields: driver.domain, driver.key, driver.value
(same pattern as user-defaults but different domain/key names)

- [ ] Implement lib/drivers/macos_swupdate.sh
- [ ] Update macos-software-update.yaml
- [ ] Verify

### Step 12 — git-global-config driver  (1 target)
New driver fields: driver.key, driver.value (already has driver.kind: git-global-config)
observe:  git config --global '$key' 2>/dev/null || echo absent
oracle:   git config --global '$key' | grep -qF '$value'
install:  ucc_run git config --global '$key' '$value'
evidence: $key → git config --global '$key' 2>/dev/null

- [ ] Implement lib/drivers/git_config.sh
- [ ] Update git-config.yaml: add driver.key/value, remove embedded code
- [ ] Verify

### Step 13 — brew-analytics driver  (1 target)
New driver fields: driver.setting (analytics), driver.value (off)

- [ ] Implement brew-analytics section in lib/drivers/brew.sh
- [ ] Update homebrew.yaml: add driver fields, remove embedded code
- [ ] Verify

### Step 14 — Commit Phase 2
- [ ] git add + commit all Phase 2 changes
- [ ] git push

---

## Phase 3 — Group C: complex drivers
Non-trivial logic; extract to dedicated scripts or named functions.

### Step 15 — json-merge driver  (vscode-settings)
Extract embedded Python to tools/drivers/json_merge.py <check|apply> <settings> <patch>
oracle:   python3 tools/drivers/json_merge.py check  $settings_path $patch_path
install:  python3 tools/drivers/json_merge.py apply  $settings_path $patch_path

- [ ] Create tools/drivers/json_merge.py
- [ ] Implement json-merge section in lib/drivers/vscode.sh
- [ ] Update dev-tools.yaml: remove embedded Python, use driver fields
- [ ] Verify

### Step 16 — docker-settings driver  (docker-resources)
Extract embedded Python to tools/drivers/docker_settings.py <check|apply> <settings_file> <patch_file>

- [ ] Create tools/drivers/docker_settings.py
- [ ] Implement docker-settings section in lib/drivers/docker.sh
- [ ] Update docker-config.yaml: remove embedded Python
- [ ] Verify

### Step 17 — Mark remaining targets as driver.kind: custom
Targets keeping observe_cmd/actions.*: node-lts, vscode (cask), homebrew,
xcode-clt, ollama, unsloth-studio, ollama-host-supported, mps-available,
pip-latest, docker-desktop, system-composition, pyenv, python, ariaflow.
Document: driver.kind: custom is the explicit escape hatch.

- [ ] Add driver.kind: custom to each remaining target in YAML
- [ ] Add comment in ucc_drivers.sh explaining custom escape hatch

### Step 18 — Commit Phase 3
- [ ] git add + commit all Phase 3 changes
- [ ] git push

---

## Verification protocol (each step)
1. bash -n lib/ucc_drivers.sh lib/drivers/*.sh  →  syntax ok
2. bash -n lib/ucc_targets.sh                   →  syntax ok
3. Run: Profile Configured  →  diff against baseline (no output change)
4. Run: Profile Runtime     →  diff against baseline (no output change)
