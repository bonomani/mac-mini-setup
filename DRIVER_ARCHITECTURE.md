# Driver Architecture

## Principles

### P1 — YAML is pure data

YAML fields (`oracle`, `observe_cmd`, `evidence`, `actions`, `desired_cmd`, `skip_when`)
contain only plain function calls with `${var}` args. No shell operators, redirections,
subshells, bash tests, or inline tools. See CLAUDE.md Rule 1.

### P2 — Single dispatch point

`driver.kind` is the sole routing key. `lib/ucc_drivers.sh` derives function names
mechanically: `_ucc_driver_${kind//-/_}_{observe,action,evidence}`.

### P3 — Uniform driver interface

Every driver implements three functions:

- `_ucc_driver_<kind>_observe  <cfg_dir> <yaml> <target>` → prints raw state
- `_ucc_driver_<kind>_action   <cfg_dir> <yaml> <target> <verb>` → executes install/update
- `_ucc_driver_<kind>_evidence <cfg_dir> <yaml> <target>` → prints `key=val` lines

### P4 — Driver-implied dependencies

Drivers declare implicit `depends_on` and `provided_by_tool` via meta functions.
YAML targets don't need to repeat them. Platform-aware: `package` driver resolves
to `homebrew` on macOS, `build-deps` on Linux.

### P5 — Driver schema validation

`DRIVER_SCHEMA` in the validator defines required/optional keys per driver kind.
Missing required keys or unexpected keys are flagged at validation time.

### P6 — Escape hatch is explicit

`driver.kind: custom` is the only valid way to keep inline oracle/evidence/actions
in YAML. A target without `driver.kind` falls through silently (dispatcher returns 1).

---

## Drivers

### Package drivers (`type: package`)

| Driver | File | Purpose | Required keys |
|--------|------|---------|---------------|
| `package` | package.sh | Platform-aware: brew (macOS) or apt/dnf/pacman (Linux) | `ref` |
| `brew` | brew.sh | Homebrew formula/cask | `ref` |
| `app-bundle` | app_bundle.sh | macOS app with brew-cask backend | `app_path`, `brew_cask` |
| `pyenv-version` | pyenv.sh | Python version via pyenv | `version` |
| `pyenv-brew` | pyenv_brew.sh | pyenv + plugins via brew | — |
| `nvm` | nvm.sh | nvm installer | `nvm_dir` |
| `nvm-version` | nvm.sh | Node.js version via nvm | `version`, `nvm_dir` |
| `npm-global` | npm.sh | Global npm package | `package` |
| `pip` | pip.sh | Pip package group | `probe_pkg`, `install_packages` |
| `pip-bootstrap` | pip_bootstrap.sh | pip/setuptools/wheel upgrade | — |
| `vscode-marketplace` | vscode.sh | VS Code extension | `extension_id` |
| `ollama-model` | ollama_model.sh | Ollama model pull | `ref` |
| `build-deps` | build_deps.sh | Native build tools (apt/dnf/pacman) | — |

### Config drivers (`type: config`)

| Driver | File | Purpose | Required keys |
|--------|------|---------|---------------|
| `brew-analytics` | brew.sh | Homebrew analytics on/off | — |
| `brew-unlink` | brew_unlink.sh | Ensure formula unlinked | `formula` |
| `json-merge` | vscode.sh | JSON settings merge | `settings_relpath`, `patch_relpath` |
| `user-defaults` | macos_defaults.sh | macOS defaults write | `domain`, `key`, `value`, `type` |
| `pmset` | macos_defaults.sh | macOS pmset power | `setting`, `value` |
| `softwareupdate-defaults` | macos_swupdate.sh | macOS SU defaults | `domain`, `key`, `value` |
| `softwareupdate-schedule` | swupdate_schedule.sh | macOS SU schedule | — |
| `docker-settings` | docker.sh | Docker Desktop resources | — |
| `cli-symlink` | cli_symlink.sh | Binary symlink | `src_path`, `link_relpath`, `cmd` |
| `script-installer` | script_installer.sh | curl installer + upgrade | `install_url`, `install_dir` |
| `zsh-config` | zsh_config.sh | Set key=value in zsh config | `key`, `value`, `config_file` |
| `path-export` | path_export.sh | Add dir to PATH in profile | `bin_dir`, `shell_profile` |
| `bin-script` | bin_script.sh | Install script from CFG_DIR | `script_name`, `bin_dir` |
| `git-global` | git_global.sh | Interactive git global config | — |

### Runtime drivers (`type: runtime`)

| Driver | File | Purpose | Required keys |
|--------|------|---------|---------------|
| `brew-service` | brew_service.sh | Homebrew service start/stop | `ref` |
| `docker-compose-service` | docker_compose_service.sh | Docker Compose service | `service_name` |
| `launchd` | launchd.sh | macOS launchd plist | `plist` |
| `custom-daemon` | custom_daemon.sh | Observe-only daemon | `bin`, `process` |
| `compose-file` | compose_file.sh | Observe compose file | `path_env` |

---

## Gates

Only 1 gate remains:

| Gate | Type | Purpose |
|------|------|---------|
| `supported-platform` | hard/global | Block all components on unsupported platforms |

All other gates have been converted to targets:
- `ai-apps-template` → precondition target in ai-apps.yaml
- `docker-settings-file` → precondition target in docker.yaml
- `networkquality-available` → capability target in dev-tools.yaml
- `sudo-available` → capability target in macos-config.yaml
- `network-available` → capability target in homebrew.yaml
- `docker-available` → capability target in docker.yaml
- `mps-available` → capability target in ai-python-stack.yaml
- `cuda-available` → capability target in ai-python-stack.yaml

---

## Justified `driver.kind: custom` targets

| Target | File | Reason |
|--------|------|--------|
| `xcode-command-line-tools` | homebrew.yaml | macOS-specific bootstrap |
| `homebrew` | homebrew.yaml | Bootstrap — no brew available yet |
| `docker-desktop` | docker.yaml | GUI app + daemon lifecycle |
| `ollama` | ai-apps.yaml | Custom daemon with installer |
| `ollama-host-supported` | ai-apps.yaml | Platform precondition |
| `unsloth-studio` | ai-python-stack.yaml | Dynamic plist generation |
| `unsloth-studio-service` | ai-python-stack.yaml | Dynamic systemd unit generation |
| `mps-available` | ai-python-stack.yaml | Hardware capability probe |
| `cuda-available` | ai-python-stack.yaml | Hardware capability probe |
| `network-available` | homebrew.yaml | Connectivity probe |
| `docker-available` | docker.yaml | Daemon reachability probe |
| `docker-settings-file` | docker.yaml | Settings file precondition |
| `ai-apps-template` | ai-apps.yaml | Template file precondition |
| `sudo-available` | macos-config.yaml | Authorization probe |
| `networkquality-available` | dev-tools.yaml | Command availability probe |
| `system-composition` | system.yaml | Meta-target (composition) |
