# Update Detection Gaps

Which drivers report an `outdated` state vs. only `ok`/`absent`.

## Detects updates

| Driver | File | Mechanism |
|---|---|---|
| `app_bundle` | `lib/drivers/app_bundle.sh:55` | Installed version vs. latest from upstream API |
| `git_repo` | `lib/drivers/git_repo.sh:36` | Local ref vs. remote ref |

## No update detection (stays `ok` once installed)

| Driver | File | Notes |
|---|---|---|
| `package` | `lib/drivers/package.sh` | Meta-driver; on macOS delegates to `brew_observe`, never calls `brew outdated` |
| `brew` | `lib/drivers/brew.sh` | Reports installed version only |
| `pip` | `lib/drivers/pip.sh` | No `pip list --outdated` check |
| `pip_bootstrap` | `lib/drivers/pip_bootstrap.sh` | — |
| `pyenv_brew` | `lib/drivers/pyenv_brew.sh` | — |
| `curl_installer` | `lib/drivers/curl_installer.sh:19` | Explicitly noted: no native outdated check |
| `script_installer` | `lib/drivers/script_installer.sh` | — |
| `custom_daemon` | `lib/drivers/custom_daemon.sh` | — |

## Impact

Targets using gap-listed drivers (e.g. `cli-opencode` via `kind: package`) remain
`ok` even when a newer upstream release exists. To surface upgrades, the relevant
driver must compare installed version against an upstream source (`brew outdated`,
`pip list --outdated`, GitHub releases via existing `_ucc_driver_github_latest`,
etc.) and emit `outdated`.
