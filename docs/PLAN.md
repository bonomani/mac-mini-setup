# PLAN

Open work derived from the three live gap docs
(`update-detection-gaps.md`, `install-method-gaps.md`,
`runtime-activation-gaps.md`). Phases are independent and shippable
in any order.

## Phase R1 — `pkg` pyenv backend activation  (~30 min)

**Gap**: `runtime-activation-gaps.md` — `_pkg_pyenv_activate` is a no-op.
`pyenv install` / `pyenv global` only work if `pyenv init` shims are on
PATH. Today this works on the user's box because their interactive shell
already initialised pyenv, but a fresh `install.sh` subprocess on a clean
box would fail.

**Fix**:
1. Add `_pyenv_ensure_path` helper to `lib/drivers/pkg.sh`:
   ```sh
   _pyenv_ensure_path() {
     command -v pyenv >/dev/null 2>&1 || return 1
     export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
     case ":$PATH:" in *":$PYENV_ROOT/bin:"*) ;; *) PATH="$PYENV_ROOT/bin:$PATH" ;; esac
     case ":$PATH:" in *":$PYENV_ROOT/shims:"*) ;; *) PATH="$PYENV_ROOT/shims:$PATH" ;; esac
     export PATH
     eval "$(pyenv init - bash 2>/dev/null)" 2>/dev/null || true
     command -v pyenv >/dev/null 2>&1
   }
   ```
2. Wire it: change `_pkg_pyenv_activate() { :; }` → `_pkg_pyenv_activate() { _pyenv_ensure_path; }`.
3. Test on a fresh shell: `bash -c './install.sh python --no-interactive'`
   should still install / report ok.

**Risk**: low. Activation is a no-op when pyenv is already on PATH.

---

## Phase R2 — `kind: pip` python activation  (~1 h)

**Gap**: `runtime-activation-gaps.md` — `kind: pip` calls `pip` / `python -m pip`
bare. If a target depends on the pyenv-managed python but lives in a
component that doesn't run `pyenv init`, the wrong interpreter is used
silently.

**Fix**:
1. Add `_pip_ensure_path` to `lib/drivers/pip.sh`:
   - Try `_pyenv_ensure_path` first (sourced from `pkg.sh`).
   - Fall back to verifying `command -v python3` and `command -v pip`.
2. Gate `_ucc_driver_pip_observe` and `_ucc_driver_pip_action` on the
   helper before calling `pip`.
3. Test: `./install.sh unsloth --no-interactive` should report `ok`.

**Risk**: low; touches one driver, no YAML changes.

---

## Phase O1 — `vscode` backend outdated detection  (~1 h)

**Gap**: `update-detection-gaps.md` — vscode marketplace backend has no
outdated check. `code --list-extensions --show-versions` knows the local
version but doesn't compare to marketplace.

**Fix**:
1. New per-process cache `_VSCODE_OUTDATED_CACHE`, opt-in via
   `UIC_PREF_BREW_LIVECHECK=1` (same flag — it's already the "do
   slow upstream lookups" master switch).
2. Populate via `code --list-extensions --show-versions` + a single
   `curl https://marketplace.visualstudio.com/_apis/...` call per
   extension (or one bulk call if the API supports it).
3. `_pkg_vscode_outdated()` returns 0 if the cache says newer.

**Risk**: low. Network-bound and opt-in — falls back to current
behavior when the flag is off.

---

## Phase O2 — `curl` backend outdated via `github_repo`  (~30 min)

**Gap**: `update-detection-gaps.md` — curl-installed packages have no
upstream signal. But `_ucc_driver_github_latest` (`lib/ucc_drivers.sh`)
already knows how to fetch the latest GitHub release and is set up to
read `driver.github_repo`.

**Fix**:
1. `_pkg_curl_outdated()` reads `driver.github_repo` from the cached YAML
   context (already loaded by `_pkg_load_backends`).
2. Compares the latest GitHub release tag against the binary's reported
   version (`$_PKG_BIN --version`), with a per-binary version regex
   from `driver.version_cmd` if present.
3. Returns 0 (outdated) when the GitHub release is strictly newer.

**Risk**: low. Needs a version-extraction regex per binary; defaults to
matching `\d+(\.\d+){1,3}` in the first line of `--version`.

---

## Phase O3 — `pip` outdated detection  (~2 h)

**Gap**: `update-detection-gaps.md` — `kind: pip` has no `pip list --outdated`
integration.

**Fix**:
1. Cache `pip list --outdated --format=json` once per process when
   `UIC_PREF_BREW_LIVECHECK=1`.
2. `_ucc_driver_pip_observe` checks each `install_packages` entry against
   the cache; if any is outdated, return `outdated`.
3. Test with a target that has a known-old pin.

**Risk**: medium. Pip's outdated set can be slow on large environments.
Cache mitigates.

---

## Phase O4 — `native-pm` outdated detection  (~2 h)

**Gap**: `update-detection-gaps.md` — apt/dnf/pacman have outdated
mechanisms but the `native-pm` backend doesn't use them.

**Fix**:
1. Per-PM cache function in `lib/drivers/package.sh` (where the native
   helpers live):
   - apt: `apt list --upgradable 2>/dev/null`
   - dnf: `dnf check-update --quiet`
   - pacman: `pacman -Qu`
   - zypper: `zypper list-updates`
2. `_pkg_native_pm_outdated()` greps the cache for the target ref.
3. Opt-in via `UIC_PREF_BREW_LIVECHECK=1` (consistent with other
   network-bound checks).

**Risk**: medium. Per-PM output formats need testing on each platform.

---

## Phase B1 — Retire dead per-driver kinds  (~1 h)

**Gap**: orphan driver files. After Phase 4, several per-driver kinds have
no YAML using them, but the files are still sourced from `lib/ucc_drivers.sh`
and the validator still lists them in `KNOWN_*_DRIVERS` and `DRIVER_META`.

**Audit**:
1. `git grep -l "kind: <name>" ucc/` for each driver file in `lib/drivers/`.
2. For each kind with zero hits, mark the file dead.
3. Cross-check with the test suite to ensure no test references it.

**Fix**:
1. Delete the dead `.sh` files.
2. Remove their entries from `lib/ucc_drivers.sh`, `DRIVER_META`,
   `DRIVER_SCHEMA`, `KNOWN_*_DRIVERS`, `_PACKAGE_DRIVER_META`.
3. Run the full pytest suite.

**Risk**: low if the audit is honest. Orphan deletion is mechanical.
**Payoff**: cleaner driver count and dispatch table.

---

## Phase B2 — BGS validator pre-commit hook  (~30 min)

**Gap**: `docs/PLAN.md` Phase 0c (closed) wired the validator manually but
never installed a hook. Future BGS bumps could break compliance silently.

**Fix**:
1. Add `.git/hooks/pre-commit` (or document a `make check` target) that
   runs:
   ```sh
   python3 ../BGSPrivate/bgs/tools/check-bgs-compliance.py BGS.md
   ```
2. Fail the commit on any error; warnings allowed.
3. Document in `README.md` how to set it up locally.

**Risk**: low. Local-only; no CI changes required.

---

## Phase X1 — New backends: `mise`, `nix`, `aur`  (open-ended)

**Gap**: `install-method-gaps.md` — three install methods have no backend.

**Approach**:
- `mise`: `mise install <pkg>@<ver>`, `mise outdated`. Single-ref. Easy
  fit for the `pkg` backend pattern.
- `nix`: nixpkgs flake refs. Single-ref but needs `nix profile install`
  and `nix profile diff-closures` for outdated. Medium effort.
- `aur`: `paru -S <pkg>`. Linux-only. Single-ref. Easy fit.

**Risk**: each new backend is its own commit; do them as need arises.
Not blocking any current use case.

---

## Out of scope (still won't fit `pkg`)

- `kind: pip` — multi-package shape. Outdated detection (Phase O3) and
  activation (Phase R2) are valuable, but the driver itself stays separate.
- `kind: pyenv-brew` — installs plugins + writes shell-init snippet.
- `kind: nvm` / `kind: nvm-version` — context fields and self-sourcing.
- `kind: app-bundle` — direct dmg/pkg/zip downloads, action wholly different.

---

## Suggested order

1. **R1** (pyenv activation) — fixes a latent bug; trivial.
2. **B1** (retire dead drivers) — cleanup after Phase 4; reduces surface.
3. **O2** (curl github_repo outdated) — closes the worst observability gap.
4. **R2** (pip activation) — needed before O3 to avoid false negatives.
5. **O3** (pip outdated) — biggest python-side win.
6. **O1** (vscode outdated) — nice-to-have.
7. **O4** (native-pm outdated) — needs per-PM testing.
8. **B2** (BGS hook) — ops nicety.
9. **X1** (new backends) — only when an actual target needs one.
