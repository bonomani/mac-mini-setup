# Driver Feature Matrix

Snapshot of every driver under `lib/drivers/` after Phase 4 + the
post-Phase-4 gap closures (R1, R2, B1, O1–O4, B2).

## Drivers

| File | Kind(s) exported | Role | Outdated | Migration | Activation | Notes |
|---|---|---|---|---|---|---|
| `pkg.sh` | `pkg` | Unified package dispatcher with 8 backends. The dominant driver — 41 YAML targets. | brew/brew-cask/npm/vscode/native-pm/curl(github) — opt-in `UIC_PREF_BREW_LIVECHECK=1`; pyenv/ollama no | yes (`handle_foreign_install` + safety probe) | npm via `_npm_ensure_path`, pyenv via `_pyenv_ensure_path` | Replaces brew/package/npm-global/vscode-marketplace/pyenv-version/ollama-model/curl-installer |
| `brew.sh` | `brew-analytics` | Bool toggle (only the analytics flag remains; the formula driver was retired) | n/a | n/a | implicit | 1 YAML target |
| `vscode.sh` | `json-merge` | Idempotent jq edit on `~/Library/Application Support/Code/User/settings.json` | n/a | n/a | implicit | 1 YAML target |
| `setting.sh` | `setting` | Unified config writer (defaults / pmset). Replaces user-defaults + pmset + softwareupdate-defaults. | n/a (config) | n/a | implicit | 12 YAML targets |
| `service.sh` | `service` | Unified daemon wrapper (brew + launchd). Replaces brew-service + launchd. | n/a | n/a | implicit | 2 YAML targets |
| `home_artifact.sh` | `home-artifact` | Filesystem artifact under `$HOME` (script | symlink). Replaces bin-script + cli-symlink. | n/a | n/a | n/a | 2 YAML targets |
| `app_bundle.sh` | `app-bundle` | Direct dmg/pkg/zip download + install | yes (upstream API) | no | n/a | 1 YAML target |
| `git_repo.sh` | `git-repo` | Clone + ref tracking | yes (local vs remote ref) | no | n/a | 1 YAML target |
| `pip.sh` | `pip` | Multi-package pip install | yes (R2/O3 closed: `pip list --outdated`) | no | yes (R2: `_pip_ensure_path`) | 13 YAML targets — stays separate (multi-package shape) |
| `pip_bootstrap.sh` | `pip-bootstrap` | Ensure pip itself | n/a | n/a | implicit | 1 YAML target |
| `pyenv_brew.sh` | `pyenv-brew` | Brew install + plugins + shell init | n/a | no | implicit | 1 YAML target |
| `nvm.sh` | `nvm`, `nvm-version` | Install nvm itself + per-version node | no | no | yes (subshell wrapper) | 2 YAML targets |
| `package.sh` | (helpers only) | `_pkg_native_*` + `_pkg_native_outdated_*` helpers used by `pkg`'s `native-pm` backend. Dispatcher functions retired. | — | — | — | not a driver any more |
| `npm.sh` | (helpers only) | `_npm_ensure_path`, `npm_global_*`, `_npm_global_foreign_owner`, `_npm_global_migrate` helpers used by `pkg` and the foreign-install path. | — | — | — | not a driver any more |
| `compose_file.sh` | `compose-file` | Static compose file ensure | n/a | n/a | n/a | 1 YAML target |
| `docker_compose_service.sh` | `docker-compose-service` | Compose-managed service. Tightly coupled to `ai_apps` runner. | no | no | implicit | 1 YAML target |
| `custom_daemon.sh` | `custom-daemon` | Process probe (observe-only — action returns 1) | no | no | n/a | 1 YAML target |
| `build_deps.sh` | `build-deps` | Linux native PM bootstrap | no | no | n/a | 1 YAML target |
| `git_global.sh` | `git-global` | Interactive git config user.name + user.email | n/a | n/a | n/a | 1 YAML target |
| `git_repo.sh` | (above) | | | | | |
| `path_export.sh` | `path-export` | Append PATH= line to shell rc | n/a | n/a | n/a | 1 YAML target |
| `zsh_config.sh` | `zsh-config` | Idempotent line edit in `.zshrc` | n/a | n/a | n/a | 1 YAML target |
| `brew_unlink.sh` | `brew-unlink` | Unlink a brew formula | n/a | n/a | implicit | 1 YAML target |
| `script_installer.sh` | `script-installer` | Generic shell installer (oh-my-zsh, etc.) | no | no | n/a | 1 YAML target |
| `swupdate_schedule.sh` | `softwareupdate-schedule` | macOS automatic update scheduler | n/a | n/a | n/a | 1 YAML target |

24 driver files total. Two of them (`package.sh`, `npm.sh`) host helper
functions only — their dispatcher entry points were retired in Phase B1.

## Active YAML kinds

`pkg` (41), `pip` (13), `setting` (12), `home-artifact` (2), `service` (2),
`nvm-version` (1), `nvm` (1), `pyenv-brew` (1), `pip-bootstrap` (1),
`brew-analytics` (1), `json-merge` (1), `app-bundle` (1), `git-repo` (1),
`docker-compose-service` (1), `custom-daemon` (1), `build-deps` (1),
`git-global` (1), `path-export` (1), `zsh-config` (1), `brew-unlink` (1),
`script-installer` (1), `softwareupdate-schedule` (1), `compose-file` (1).

23 distinct kinds, dominated by `pkg`.

## Outdated detection (post-O1–O4)

Behind `UIC_PREF_BREW_LIVECHECK=1`:

| Source | Mechanism |
|---|---|
| `pkg` brew | `brew outdated` always; `brew livecheck` opt-in |
| `pkg` brew-cask | `brew outdated --cask` (+ `--greedy` if YAML asks) |
| `pkg` npm | `npm outdated -g --json`, cached |
| `pkg` vscode | marketplace `extensionquery` POST API, bulk + cached |
| `pkg` curl | `_pkg_curl_version` + `driver.github_repo` release tag |
| `pkg` native-pm | per-PM cache: apt list --upgradable / dnf check-update / pacman -Qu / zypper -n list-updates |
| `pip` | `pip list --outdated --format=json`, cached |
| `app_bundle` | upstream API |
| `git_repo` | local vs remote ref |

No outdated detection (by design): pkg pyenv, pkg ollama, custom-daemon,
script-installer, build-deps, all config-writer kinds.

## Foreign-install migration

Implemented in `lib/utils.sh:handle_foreign_install` + per-driver-pair safety
probe (`_assess_migration_safety`). Used by:

- `pkg` install action (any backend, before reinstalling).
- `desktop_app_handle_unmanaged_cask` (legacy cask handler, refactored to use
  the same helper).

## Runtime activation

| Backend / driver | Helper |
|---|---|
| `pkg` npm | `_npm_ensure_path` (in-process gate) |
| `pkg` pyenv | `_pyenv_ensure_path` (R1) |
| `kind: pip` | `_pip_ensure_path` → `_pyenv_ensure_path` fallback (R2) |
| `kind: nvm` / `nvm-version` | `bash -c 'source nvm.sh && …'` (subshell wrapper) |

## What was retired

- `bin_script.sh` → folded into `home_artifact.sh`
- `cli_symlink.sh` → folded into `home_artifact.sh`
- `macos_defaults.sh` → folded into `setting.sh` (user-defaults + pmset)
- `macos_swupdate.sh` → folded into `setting.sh`
- `brew_service.sh` → folded into `service.sh`
- `launchd.sh` → folded into `service.sh`
- `curl_installer.sh` → folded into `pkg.sh` (curl backend)
- `ollama_model.sh` → folded into `pkg.sh` (ollama backend)
- `pyenv.sh` → folded into `pkg.sh` (pyenv backend)
- `npm.sh` (driver portion) → folded into `pkg.sh` (npm backend)
- `package.sh` (driver portion) → folded into `pkg.sh` (brew + brew-cask + native-pm backends)
- `vscode.sh` (vscode-marketplace portion) → folded into `pkg.sh` (vscode backend)

12 driver kinds retired into 4 unified drivers (`pkg`, `setting`, `service`,
`home_artifact`).

## Linked living docs

- `docs/install-method-gaps.md` — backend coverage and user-override layer.
- `docs/update-detection-gaps.md` — outdated detection per backend/driver.
- `docs/runtime-activation-gaps.md` — what activates what.
