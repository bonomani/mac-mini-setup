# Update Detection Gaps

Which drivers report an `outdated` state vs. only `installed`/`absent`.

## Detects updates

| Driver / backend | File | Mechanism |
|---|---|---|
| `pkg` backend `brew` | `lib/drivers/pkg.sh` → `brew_observe` | `brew outdated` always; `brew livecheck` opt-in via `UIC_PREF_BREW_LIVECHECK=1` (catches formula lag — upstream newer than the homebrew formula) |
| `pkg` backend `brew-cask` | `lib/drivers/pkg.sh` → `brew_cask_observe` | `brew outdated --cask` (+ `--greedy` when `driver.greedy_auto_updates: true`) |
| `pkg` backend `npm` | `lib/drivers/pkg.sh` → `_pkg_npm_outdated` | `npm outdated -g --json`, opt-in via `UIC_PREF_BREW_LIVECHECK=1` |
| `app_bundle` | `lib/drivers/app_bundle.sh` | Installed version vs. upstream API |
| `git_repo` | `lib/drivers/git_repo.sh` | Local ref vs. remote ref |

## No update detection

| Driver / backend | Reason |
|---|---|
| `pkg` backend `pyenv` | pyenv has no native "newer interpreter" notion at this granularity |
| `pkg` backend `ollama` | Ollama models don't expose a simple "newer tag" check; tags are pinned refs |
| `pkg` backend `vscode` | VS Code's `code --list-extensions --show-versions` doesn't compare against marketplace |
| `pkg` backend `native-pm` | Each PM has its own outdated mechanism; not yet wired |
| `pkg` backend `curl` | No upstream signal — installer URL is fire-and-forget |
| `pip` | `kind: pip` stays separate (multi-package shape); no `pip list --outdated` integration |
| `pip-bootstrap` | Bootstrap step, version-agnostic |
| `pyenv-brew` | Manages plugins; not version-bumpy |
| `nvm` / `nvm-version` | Could compare against `nvm ls-remote --lts`; not implemented |
| `custom_daemon` | Observe-only |
| `script_installer`, `curl_installer` | No upstream signal |

## How to enable per-target outdated checks

For `pkg` targets that already have an outdated-capable backend (brew, brew-cask,
npm), set the env opt-in once:

```sh
export UIC_PREF_BREW_LIVECHECK=1
./install.sh
```

Without it, the network-bound checks are skipped and behavior is install-only
fast path.

## Impact

The gap is now backend-shaped, not driver-shaped: a target migrated to `kind: pkg`
inherits whatever outdated detection its first available backend offers. The
remaining work is per-backend, not per-driver.
