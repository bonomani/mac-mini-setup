# Driver Feature Matrix

Snapshot of every driver under `lib/drivers/`. Columns:

- **observe** — has `_ucc_driver_<kind>_observe` (state read).
- **action** — has `install`/`update` action handler.
- **apply** — has `_ucc_driver_<kind>_apply` (config/bool model).
- **evidence** — emits human-readable evidence string.
- **outdated** — distinguishes "installed but newer available" from "current".
- **migration** — supports foreign-install conflict resolution
  (`handle_foreign_install` + safety probe).
- **runtime activation** — sources its required runtime (nvm/pyenv/etc.)
  before calling its tools.
- **always-loaded helpers** — non-driver helper functions live in the same
  file (so callers don't need a component lib).
- **notes** — gaps and quirks worth knowing.

| Driver | obs | act | app | ev | outd | mig | rt act | helpers | notes |
|---|---|---|---|---|---|---|---|---|---|
| `app_bundle` | ✅ | ✅ | — | ✅ | ✅ | — | — | — | Compares installed vs upstream API; one of only three drivers that detect updates. |
| `bin_script` | ✅ | ✅ | — | ✅ | — | — | — | — | Installs a script into `~/bin`; presence-only. |
| `brew` (formula) | ✅ | ✅ | — | ✅ | ⚠️ | — | implicit | — | Detects outdated via `brew outdated` (and `brew livecheck` opt-in via `UIC_PREF_BREW_LIVECHECK=1`); can lag upstream. |
| `brew-analytics` | ✅ | ✅ | ✅ | ✅ | — | — | implicit | — | Bool config (on/off). |
| `brew-service` | ✅ | ✅ | — | ✅ | — | — | implicit | — | Wraps `brew services`. |
| `brew-unlink` | ✅ | ✅ | — | ✅ | — | — | implicit | — | Idempotent unlink. |
| `build-deps` | ✅ | ✅ | — | ✅ | — | — | — | — | Linux native PM bootstrap. |
| `cli-symlink` | ✅ | ✅ | — | ✅ | — | — | — | — | Symlink management. |
| `compose-file` | ✅ | ✅ | — | ✅ | — | — | — | — | Static file ensure. |
| `curl_installer` | ✅ | ✅ | — | ✅ | ⚠️ | — | — | — | Notes "no native outdated check" in source; presence-only effectively. |
| `custom-daemon` | ✅ | ✅ | — | ✅ | — | — | — | — | Generic daemon scaffolding. |
| `docker-compose-service` | ✅ | ✅ | — | ✅ | — | — | implicit | — | Requires Docker Desktop on PATH. |
| `git-global` | ✅ | ✅ | — | ✅ | — | — | — | — | git config user/email. |
| `git-repo` | ✅ | ✅ | — | ✅ | ✅ | — | — | — | Compares local vs remote ref → outdated. |
| `launchd` | ✅ | ✅ | — | ✅ | — | — | — | — | Plist install + load. |
| `macos-defaults` (`pmset`, `user-defaults`) | ✅ | ✅ | ✅ | ✅ | — | — | — | — | Bool/scalar config via `defaults`/`pmset`. |
| `macos-swupdate` (`softwareupdate-defaults`) | ✅ | ✅ | ✅ | ✅ | — | — | — | — | macOS auto-update toggles. |
| `npm-global` | ✅ | ✅ | — | ✅ | — | ✅ | ✅ (`_npm_ensure_path`) | ✅ (`npm_global_*`) | Migration probe + nvm activation; no `npm outdated` integration yet. |
| `nvm` / `nvm-version` | ✅ | ✅ | — | ✅ | — | — | ✅ (subshell wrapper) | — | Self-sources `nvm.sh` in `bash -c`; reference pattern for activation. |
| `ollama-model` | ✅ | ✅ | — | ✅ | — | — | implicit | — | Wraps `ollama pull`/`list`. |
| `package` (meta) | ✅ | ✅ | — | ✅ | ⚠️ | — | implicit | — | Dispatches brew/native-PM/curl. Inherits brew's outdated quirks. |
| `path-export` | ✅ | ✅ | — | ✅ | — | — | — | — | Shell rc-file edits. |
| `pip` | ✅ | ✅ | — | ✅ | — | — | ❌ gap | — | Calls `pip` bare; misses pyenv-managed python activation. |
| `pip-bootstrap` | ✅ | ✅ | — | ✅ | — | — | — | — | Ensures pip itself. |
| `pyenv-version` | ✅ | ✅ | — | ✅ | — | — | ❌ gap | — | Calls `pyenv` bare; needs `pyenv init` shims. |
| `pyenv-brew` | ✅ | ✅ | — | ✅ | — | — | implicit | — | Brew-installed pyenv binary; no shim init needed for the calls used. |
| `script-installer` | ✅ | ✅ | — | ✅ | — | — | — | — | Generic shell installer. |
| `swupdate-schedule` (`softwareupdate-schedule`) | ✅ | ✅ | — | ✅ | — | — | — | — | macOS scheduling. |
| `vscode` (`vscode-marketplace`, `json-merge`) | ✅ | ✅ | ✅ (json-merge) | ✅ | — | — | implicit | — | Extension install + settings.json merge. |
| `zsh-config` | ✅ | ✅ | — | ✅ | — | — | — | — | rc snippet ensure. |

Legend: ✅ has it · ⚠️ partial / known limitation · — not applicable / not implemented · `implicit` runtime is on PATH because its installer (brew etc.) places it there with no shell init needed.

## Cross-cutting capabilities

| Capability | Drivers that have it | Drivers that should have it |
|---|---|---|
| Outdated detection | `app_bundle`, `git_repo`, `brew` (partial via livecheck) | `npm-global` (via `npm outdated`), `pip` (via `pip list --outdated`), `curl_installer` (via versioned URL or release feed) |
| Migration / foreign-install handling | `npm-global`, `brew-cask` (via `desktop_app_handle_unmanaged_cask`) | `brew`, `pip`, every package-installing driver in principle |
| Runtime activation guard | `npm-global`, `nvm` | `pyenv-version`, `pip` (when pyenv-managed) |
| Per-driver `evidence` evidence + GitHub-latest hint | All drivers via `_ucc_driver_evidence` post-hook | — |
| Driver-implicit dependencies (`_<kind>_depends_on`) | Most | New drivers: `mise`, `nix`, `aur` (don't exist yet) |

## Known gaps (linked docs)

- Update detection: `docs/update-detection-gaps.md`.
- Install method coverage + multi-backend & user override: `docs/install-method-gaps.md`.
- Runtime activation: `docs/runtime-activation-gaps.md`.

## Grouping by similarity

### A. Package installers (binary on $PATH)

Install a binary/library through some upstream package manager. Same shape:
ref → install → version → outdated.

- `brew` (formula)
- `package` (meta: brew → native PM → curl fallback)
- `build-deps` (Linux native PM bootstrap)
- `npm-global`
- `pip`
- `pip-bootstrap`
- `pyenv-version`
- `pyenv-brew`
- `nvm`, `nvm-version`
- `ollama-model`
- `vscode-marketplace`
- `curl_installer`
- `script_installer`

Common needs: outdated detection, runtime activation, foreign-install
migration, version cache.

### B. GUI / app-bundle installers

Install a `.app` or system-wide GUI artifact, possibly under `/Applications`.

- `app_bundle`
- `brew` (cask branch — handled inside `brew.sh`)

Common needs: sudo/admin, system-wide cleanup, kext/helper handling, almost
always destructive on migration.

### C. Service / daemon managers

Manage a long-running process via an init system.

- `brew-service`
- `launchd`
- `custom-daemon`
- `docker-compose-service`

Common needs: start/stop/status, autostart toggle, log location, restart
semantics.

### D. Configuration writers (idempotent file edits)

Mutate a config file or registry to converge on a desired value. Use the
`apply` model rather than `action`.

- `macos-defaults` (`pmset`, `user-defaults`)
- `macos-swupdate`
- `swupdate-schedule`
- `vscode` (`json-merge`)
- `git-global`
- `zsh-config`
- `path-export`
- `brew-analytics`
- `compose-file`

Common needs: backup-before-write, drift detection, idempotency, no service
restart unless required.

### E. Filesystem / link plumbing

Create/maintain artifacts on the filesystem with no external PM involved.

- `bin_script`
- `cli_symlink`
- `brew_unlink`
- `git_repo` (clone + ref tracking)

Common needs: ownership, replace-if-different, dry-run safety.

### Cross-group observations

- **Group A** is where the unfinished work lives: outdated detection,
  multi-backend, migration safety, runtime activation.
- **Group B** is where the strictest safety gates belong (system-wide,
  potentially destructive, often needs sudo).
- **Group C** would benefit from a shared service-state model (started,
  stopped, failed, autostart) instead of each driver inventing its own.
- **Group D** is the only group that uses the `apply` hook; this is the
  natural home for an "intended-state" reconciler.
- **Group E** is the simplest and most stable — nothing missing.

## Maturity ranking

1. **Most mature**: `brew`, `package`, `npm-global`, `nvm` — complete
   observe/action/evidence, clear migration story, good cache use.
2. **Solid but narrow**: `app_bundle`, `git_repo`, all `*-defaults`,
   `brew-service`, `launchd`.
3. **Functional with gaps**: `pip`, `pyenv-version` (runtime activation),
   `curl_installer` (no outdated detection), `script_installer`.
4. **Single-purpose helpers**: `bin_script`, `cli_symlink`, `compose_file`,
   `path_export`, `zsh_config`, `git_global`, `brew_unlink` — narrow scope,
   nothing missing.
