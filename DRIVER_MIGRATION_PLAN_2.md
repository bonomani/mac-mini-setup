# Driver Migration Plan — Phase 2

## Goal
Continue migrating `driver.kind: custom` targets where a generic driver
is a clean fit. Phase 1 covered all mechanical single-function patterns.
Phase 2 targets require either a new driver kind or a new driver field.

## Candidates assessed

| Target | File | Verdict |
| ------ | ---- | ------- |
| `python` | python.yaml | ✅ **Migrate** — `pyenv-version` driver (kind already in validator) |
| `node-lts` | dev-tools.yaml | ✅ **Migrate** — new `brew-formula-pinned` driver |
| `docker-desktop` | docker.yaml | ❌ **Keep custom** — `type: runtime`, needs `open -a` + daemon wait on install; not a package-install pattern |
| `vscode-code-cmd` | dev-tools.yaml | ❌ **Keep custom** — single-use symlink; abstraction cost > benefit |
| `pyenv` | python.yaml | ❌ **Keep custom** — `brew_observe` but install injects shell init; not separable |

---

## Step 1 — `pyenv-version` driver  (1 target: python)

Driver fields: `driver.version` (optional, falls back to `UIC_PREF_PYTHON_VERSION`)
```
observe:  ver="${UIC_PREF_PYTHON_VERSION:-$driver_version}"
          pyenv versions | grep -q "$ver" && printf '%s' "$ver" || printf 'absent'
install:  pyenv install "$ver" && pyenv global "$ver"
update:   pyenv install --skip-existing "$ver" && pyenv global "$ver"
evidence: version → python3 --version | awk '{print $2}'
          path    → pyenv which python3
```

- [x] Implement `lib/drivers/pyenv.sh`
- [x] Add `driver.version` to `_UCC_YAML_BATCH_KEYS` in `install.sh`
- [x] Update `python.yaml`: add `driver.version`, remove `observe_cmd`/`actions`/`evidence`
- [x] Verify: bash -n; validator clean

## Step 2 — `brew-formula-pinned` driver  (1 target: node-lts)

Driver fields: `driver.ref` (formula name with version, e.g. `node@24`),
               `driver.previous_ref` (formula to unlink first, e.g. `node@20`)
```
observe:  ver="$(node --version 2>/dev/null)"
          if [[ "$ver" != v*... ]]; use brew_observe '$ref'
          (reuses existing brew_observe + _brew_is_outdated logic)
install:  brew unlink '$previous_ref' 2>/dev/null || true
          brew_install '$ref' && brew link --overwrite --force '$ref'
update:   brew_upgrade '$ref' && brew link --overwrite --force '$ref'
evidence: version → node --version | sed 's/^v//'
          path    → command -v node
```

- [x] Implement `brew-formula-pinned` section in `lib/drivers/brew.sh`
- [x] Add `driver.previous_ref` to `_UCC_YAML_BATCH_KEYS` in `install.sh`
- [x] Update `dev-tools.yaml`: add `driver.ref`/`driver.previous_ref`, remove embedded code
- [x] Verify: bash -n; validator clean; add `brew-formula-pinned` to `KNOWN_PACKAGE_DRIVERS`

## Step 3 — Commit Phase 2
- [x] git add + commit all Phase 2 changes
- [x] git push
- [x] Update `DRIVER_ARCHITECTURE.md` justified custom table

---

## Verification protocol (each step)
1. `bash -n lib/drivers/*.sh`            → syntax ok
2. `python3 tools/validate_targets_manifest.py ucc`  → validator clean
3. Run: Profile Configured → diff against baseline (no output change)
