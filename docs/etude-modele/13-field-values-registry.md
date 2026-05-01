# 13 - Field Values Registry

Central registry of every enum-like value for every composed field defined in
this study. Source for validator-side schema checks.

Two columns of metadata:

- **Closed** — the validator rejects unknown values.
- **Open** — the validator emits a warning for unknown values; new values may
  appear without a schema bump (but should still be registered here on first use).

## Source-Of-Truth Fields

### `resource_type` (closed, 5 values)

Source: `04-types.md`. Live counts from the manifests.

| Value | Role | Live |
|---|---|---:|
| `package` | Install or update a software artifact | 95 |
| `config` | Converge a file, link, preference, or value | 27 |
| `runtime` | Bring a service/process into the desired execution state | 13 |
| `capability` | Observe a currently available capability | 11 |
| `precondition` | Local prerequisite for a config/runtime resource | 1 |

### `capability_type` (open, ~25 known)

Source: `03-capabilities.md` (17 declared families) plus extensions found in
`11-avahi-bonjour-declination.md` and `12-resource-spec-requirements.md`.

| Value | Definition |
|---|---|
| `binary` | Invocable command on PATH |
| `package-manager` | Usable package manager |
| `language-runtime` | Activatable runtime/toolchain |
| `python-import` | Importable Python module |
| `python-package-set` | Group of pip packages |
| `python-feature` | Python feature (e.g. `venv`) |
| `app-extension` | Extension installed in a host app |
| `app-bundle` | macOS app bundle / cask |
| `daemon` | Running daemon/service |
| `socket` | Local socket |
| `http-endpoint` | Healthy local URL |
| `compose-stack` | Active Docker Compose topology |
| `ai-model` | Local AI model present/loadable |
| `config-file` | Declared config file present/conformant |
| `os-setting` | OS setting at desired value |
| `network-probe` | Network diagnostic tool |
| `network-connectivity` | Internet connectivity |
| `hardware-accel` | Usable hardware acceleration (MPS, CUDA) |
| `admin-authority` | Elevation capability (sudo) |
| `update-policy` | Configured update policy |
| `service-discovery` | Local service discovery (mDNS) |
| `kernel-feature` | Kernel feature (cgroup2) |
| `init-system` | systemd / launchd availability |
| `user-service` | Per-user service capability (linger) |
| `node-package` | Globally-installed npm package |
| `hypervisor-runtime` | Usable hypervisor (VMware, QEMU, Hyper-V, …) |
| `vm-runtime` | Running virtual machine (started, snapshot reachable) |
| `vm-snapshot` | Captured snapshot of a VM |

### `driver_type` — decomposed into `action_type` × `tool_type`

The 26 live `driver_type` values in `ucc/**/*.yaml` mix three orthogonal
axes (action, tool, object class). The goal model splits them into two
new fields plus the existing `resource_type`. The 26 legacy values become
deprecated aliases mapped onto triples; the mapping table lives in
`07-current-mapping.md` §8 (Driver decomposition).

### `action_type` (closed, 3 values)

The model has only three primary actions. Sub-cases (install / update /
configure / start / stop / link / toggle / apply-stack) are **branches of
`converge`** dispatched by the diff between observed and desired state.
The dispatcher lives in `operation_contract.converge` (see 06).

| Value | Mutation? | Meaning |
|---|:---:|---|
| `converge` | yes | Bring observed state to desired state. Branches: `on_absent`, `on_outdated`, `on_drifted`, `on_runtime_diff.{to_running, to_stopped}`, `on_topology_diff` |
| `observe` | no | Read state, no mutation |
| `snapshot` | yes | Capture or restore a snapshot (independent of desired-state diff) |

Pre- and post-converge effects (PATH activation, `restart_processes`,
`daemon-reload`, …) are **hooks** of the `operation_contract`, not
separate `action_type` values.

Mapping from legacy 10-verb form lives in `07-current-mapping.md` §8.

### `tool_type` (open, 21 values)

Which tool the action is mediated through.

| Value | Notes |
|---|---|
| `brew` | Homebrew formulae and casks |
| `native-pm` | apt / dnf / pacman |
| `pip` | Python package manager (resolves into a venv) |
| `npm` | Node package manager (global) |
| `pyenv` | Python version manager |
| `nvm` | Node version manager |
| `git` | Repository clone or global config |
| `docker` | Compose CLI |
| `vscode` | `code --install-extension` |
| `ollama` | Model registry pull |
| `shell-rc` | Direct edit of a shell rc file |
| `defaults` / `pmset` / `softwareupdate` | macOS settings tools |
| `curl` | Plain HTTPS fetch |
| `github` | GitHub release tarball |
| `winget` | Windows winget |
| `vmware` | VMware Fusion / Workstation CLI (`vmrun`) |
| `qemu` | QEMU/libvirt CLI |
| `hyperv` | Hyper-V PowerShell |
| `none` | Action runs without a delegated tool |

### `backend_type` — decomposed into `provider_type` × `provider_name`

`backend_type` mixed three categories (real package manager, fetch method,
app registry). It is split into two orthogonal fields.

### `provider_type` (closed, 3 values)

| Value | Examples |
|---|---|
| `package-manager` | `brew`, `native-pm`, `npm`, `pip`, `pyenv` |
| `fetch-method` | `github`, `curl` |
| `app-registry` | `ollama`, `vscode`, `winget` |

### `provider_name` (open, 10 live values)

Concrete provider name, observed under `driver.backends:` in live YAML.

| Value | Live | provider_type |
|---|---:|---|
| `brew` | 43 | `package-manager` |
| `native-pm` | 41 | `package-manager` |
| `ollama` | 7 | `app-registry` |
| `vscode` | 7 | `app-registry` |
| `github` | 6 | `fetch-method` |
| `npm` | 5 | `package-manager` |
| `brew-cask` | 4 | `package-manager` (sub-flavor of `brew`, `subtype: cask`) |
| `pyenv` | 1 | `package-manager` |
| `curl` | 1 | `fetch-method` |
| `winget` | 1 | `app-registry` |

### `relation_type` (closed, 14 values)

Source: `08-implementation-gaps-and-model-v3.md` line 163, plus `configures`
introduced by the configuration section in `06-resource-schema.md`.

| Value | Semantic |
|---|---|
| `contains` | Hierarchy edge (layer→component→resource) |
| `declares` | Declaration source |
| `generates` | Template → instances |
| `derives` | Derived view |
| `selects` | Run inclusion |
| `overrides` | Overlay |
| `consumes` | Functional dependency |
| `provides` | Capability exposure |
| `configures` | Config resource is the configuration of a managed resource |
| `requires` | Host predicate |
| `verifies` | Post-convergence proof |
| `schedules` | Topological ordering |
| `records` | Run trace |
| `invalidates` | Cache invalidation |

Compatibility legacy: `depends_on` (resolved view of hard `consumes`).

### `config_source` (closed, 4 values)

Origin of a configured value, recorded on resolved `desired_state.value`.
Parallel to `selection_source` but for arbitrary config values rather than
selection.

| Value | Origin | Precedence |
|---|---|---|
| `defaults` | `defaults/preferences.yaml` | lowest |
| `component-preference` | `<component>.preferences:` block | overrides defaults |
| `resource-override` | `UCC_OVERRIDE__*` env var or `resource-overrides.yaml` | overrides preference |
| `operator-cli` | `--set` argument or run-time env var | highest |

### `merge_semantics` (closed, 4 values)

How a written config value combines with the observed value.

| Value | Behavior | Used by |
|---|---|---|
| `replace` | overwrite entirely (default) | `setting`, `defaults`, `pmset` |
| `shallow-merge` | top-level key-by-key | shell rc files |
| `deep-merge` | recursive | `json-merge` (VS Code settings) |
| `append` | additive without duplicates | PATH, `sources.list`, completion files |

### `notify_signal` (closed, 4 values)

Signal sent to a target resource by `post_converge.notify_resource`.

| Value | Effect |
|---|---|
| `reload-config` | resource re-reads its config (Finder, Dock) |
| `restart` | resource fully restarted |
| `daemon-reload` | systemd or launchd reload (no service restart) |
| `sighup` | POSIX SIGHUP (loggers, web servers) |

### `consume_strength` (closed, 2 values)

| Value | Effect |
|---|---|
| `hard` | Blocks convergence if unsatisfied |
| `soft` | Influences ordering/evidence/warning, does not block |

### `relation_effect` (closed, 16 values)

Source: `08-implementation-gaps-and-model-v3.md` line 170.

| Value | Where |
|---|---|
| `contain` | `contains` |
| `declare` | `declares` |
| `derive` | `derives` |
| `select` | `selects` |
| `override` | `overrides` |
| `block` | hard consume unsatisfied |
| `order` | soft consume → order only |
| `warn` | soft consume → warning |
| `skip` | requires not met |
| `observe` | hard consume in observe phase |
| `apply` | action execution |
| `verify` | post-action verification |
| `prove` | verification-test |
| `record` | artifact write |
| `invalidate` | cache invalidation |
| `report` | report only |

### `relation_phase` (closed, 7 values)

Source: `08-implementation-gaps-and-model-v3.md` line 175.

| Value | Phase |
|---|---|
| `model` | Static model time |
| `preflight` | Pre-run gates |
| `plan` | Plan construction |
| `observe` | Observation phase |
| `apply` | Apply phase |
| `verify` | Post-convergence verification |
| `report` | Artifact generation |

### `relation_source` (closed, 9 values)

Sources: `01-elements.md` line 115, `09-executable-contract-and-orthogonality.md` line 32.

| Value | Origin |
|---|---|
| `declared` | Declared in YAML |
| `driver` | Implicit via driver |
| `backend` | Implicit via backend |
| `backend-contract` | From a backend contract |
| `policy` | Generated by a policy |
| `inferred` | Inferred by validator |
| `resolved-dependencies` | From provider/consumer resolution |
| `model` | Static project hierarchy |
| `manifest` | Component-level declaration |

### `selection_source` (open)

| Value | Origin |
|---|---|
| `cli_args` | Command-line argument |
| `defaults/selection.yaml` | Project default |
| `selection.env` | Environment variable |
| `selection.yaml` | User file |
| `resource-overrides.yaml` | User overlay |
| `dependency_closure` | Transitive closure |

### `declared_in` (closed, 2 values)

| Value | Case |
|---|---|
| `model` | Internal hierarchy (project/layer/component) |
| `manifest` | Component YAML |

### `capability_scope` (closed, 6 values)

| Value | Meaning |
|---|---|
| `host` | Whole machine |
| `user` | Current user |
| `component` | Component-scoped |
| `container` | Inside a container |
| `service` | Service-scoped |
| `external` | Outside the managed graph |

### `gate_scope` (closed, 1 value)

| Value | Meaning |
|---|---|
| `global` | Run-wide preflight predicate |

### `provider_scope` (closed)

Inherits `capability_scope` values. Always describes how widely a `provides`
relation applies.

### `element_type` (closed, ~30 values)

Sources: `01-elements.md`, `08-implementation-gaps-and-model-v3.md` static and
run plane lists, `09-executable-contract-and-orthogonality.md`.

#### Static plane

| Value |
|---|
| `project` |
| `layer` |
| `component` |
| `resource-template` |
| `managed-resource` |
| `capability` |
| `provider-selection` |
| `condition` |
| `policy` |
| `driver-contract` |
| `backend-contract` |
| `preflight-gate` |
| `preference` |
| `verification-suite` |
| `verification-test` |
| `derived-artifact` |
| `governance-claim` |
| `output-contract` |
| `external-provider` |
| `compatibility-view` |
| `compatibility-import` |
| `compatibility-warning` |

#### Run plane

| Value |
|---|
| `host-context` |
| `run-session` |
| `selection-plan` |
| `execution-plan` |
| `resource-operation` |
| `operation-outcome` |
| `transition-inhibitor` |
| `observation-cache` |
| `run-artifact` |
| `verification-context` |
| `managed-resource-status` |

### `outcome_type` (closed, 8 values)

Source: `06-resource-schema.md` line 304.

| Value | Meaning |
|---|---|
| `ok` | Nothing to change |
| `changed` | Change applied |
| `failed` | Failure |
| `warn` | Warning |
| `policy` | Blocked by policy |
| `skip` | Skipped (requires unmet) |
| `disabled` | Disabled by selection |
| `dry-run` | Simulation |

### `inhibitor_type` (closed, 8 values)

Source: `08-implementation-gaps-and-model-v3.md` line 140; extended with
engine-emitted inhibitors observed in the run-plane.

| Value | Case |
|---|---|
| `dry-run` | Simulation mode |
| `policy` | Policy violation |
| `admin` | Required admin unavailable |
| `user` | User refusal |
| `no-install-fn` | Driver has no install function |
| `preflight-gate` | A preflight-gate condition failed; the run is blocked |
| `drift` | Observed state diverges from the previously converged state |
| `already-converged` | Observed state matches desired; converge is a no-op |

### `phase_type` for operations (closed, 7 values)

Source: `06-resource-schema.md` line 271. This is the operation lifecycle.
Distinct from `relation_phase`.

| Value | Action |
|---|---|
| `declare` | Register in the run |
| `observe` | Probe current state |
| `diff` | Compute desired vs observed |
| `apply` | Make the change |
| `verify` | Post-action verification |
| `recover` | Recover after failure |
| `record` | Write evidence |

## Derived Fields

Derived fields are not source of truth. The validator computes them and
rejects YAML that writes them differently.

### `convergence_profile_derived` (4 live + 2 reserved)

Source: `04-types.md`. Computed from `resource_type` plus presence of
`desired_value` / `desired_cmd`.

| Value | Live | Reserved |
|---|:---:|:---:|
| `configured` | yes (105) | — |
| `parametric` | yes (18) | — |
| `runtime` | yes (13) | — |
| `capability` | yes (11) | — |
| `presence` | — | reserved |
| `verification` | — | reserved |

### `state_model_derived` (4 values)

Computed from `convergence_profile_derived` (chain documented in
`04-types.md`).

| Value | Comparison |
|---|---|
| `package` | Installed version |
| `config` | File content / link |
| `parametric` | Current value vs desired value |
| `runtime` | Installation/runtime/health/dependencies axes |

### `dependencies_derived`

Resolved list of provider resources for hard `consumes` relations.

| Shape | Source |
|---|---|
| `[resource-name]` | `consumes` (hard) + `provides` + `provider-selection` |

### `platform_dependencies_derived`

Conditional resolved list keyed by host predicate.

### `provider_provenance_derived`

Resolved provider for one satisfied `consumes`. Compatibility projection of
legacy `provided_by_tool`.

### `admin_required_derived` (2 values)

| Value | Source |
|---|---|
| `true` | `policy` consumes `admin-authority/sudo` |
| `false` | otherwise |

### `requires_string_derived`

Legacy string projection of the `condition` AST. Example: `macos>=14,linux,wsl2`.

### `derived_applicability`

Applicability inherited through hard providers. Already explicit in name.

### `resolved_dependencies`

Per-host concrete provider list. Already explicit in name.

## Driver Field Contracts

Per `driver_type`, the fields actually used in the live YAML. Backends are
listed under each driver as `backends.<key>`.

### `pkg` (71 resources)

| Field | Frequency | Sample |
|---|---:|---|
| `bin` | 54 | `zsh`, `cosign`, `cvc5` |
| `backends.brew` | 43 | `graphviz`, `zsh` |
| `backends.native-pm` | 41 | `graphviz`, `uv` |
| `github_repo` | 10 | `sigstore/cosign` |
| `backends.ollama` | 7 | `mistral:7b`, `qwen2.5-coder:32b` |
| `backends.vscode` | 7 | `ms-python.vscode-pylance` |
| `backends.github` | 6 | `bazelbuild/bazelisk` |
| `backends.npm` | 5 | `bmad-method`, `@anthropic-ai/claude-code` |
| `backends.brew-cask` | 4 | `vmware-fusion`, `lm-studio` |
| `greedy_auto_updates` | 3 | `true` |
| `backends.pyenv` | 1 | `${python_version}` |
| `backends.winget` | 1 | `VMware.WorkstationPro` |
| `backends.curl` | 1 | `https://sh.rustup.rs` |
| `curl_args` | 1 | `-y` |

### `pip` (16 resources)

| Field | Frequency |
|---|---:|
| `install_packages` | 16 |
| `isolation` | 16 | nested object: `isolation_type: venv`, `name: <venv>` |
| `min_version` | 16 |
| `probe_pkg` | 16 |

### `setting` (12 resources)

| Field | Frequency | Values |
|---|---:|---|
| `backend` | 12 | `pmset`, `defaults`, `softwareupdate-config` |
| `key` | 12 | setting key |
| `value` | 12 | desired value |
| `domain` | 9 | `NSGlobalDomain`, `com.apple.finder`, `${softwareupdate_domain}` |
| `requires_sudo` | 8 | `true` |
| `type` | 4 | `bool` |

### `capability` (11 resources)

| Field | Frequency | Values |
|---|---:|---|
| `probe` | 11 | `mdns_is_available`, `torch_mps_available`, `cgroup2_is_available`, … |

### `custom` (10 resources)

Heterogeneous; each `custom` driver carries its own parameter set:

| Field | Used by |
|---|---|
| `app_name`, `app_path`, `package_ref` | docker-desktop |
| `cpu_count`, `disk_mib`, `memory_gb`, `swap_mib` | docker-resources |
| `settings_relpath` | vscode-settings |
| `greedy_auto_updates`, `self_updating` | various |

### `docker-compose-service` (5 resources)

| Field | Frequency | Sample |
|---|---:|---|
| `service_name` | 5 | `open-webui`, `openhands`, `n8n`, `flowise`, `qdrant` |

### `home-artifact` (2 resources)

| Field | Sub-type |
|---|---|
| `subtype` (legacy `subkind`) | `symlink` or `script` |
| `bin_dir`, `link_relpath`, `src_path` | `symlink` |
| `script_name`, `cmd`, `hint` | `script` |

### `service` (2 resources)

| Field | Frequency | Sample |
|---|---:|---|
| `backend` | 2 | `brew` |
| `ref` | 2 | `bonomani/ariaflow/ariaflow-server` |

### `compose-file` (1 resource)

| Field | Sample |
|---|---|
| `path_env` | `COMPOSE_FILE` |

### `compose-apply` (1 resource)

| Field | Sample |
|---|---|
| `path_env` | `COMPOSE_FILE` |
| `pull_policy_env` | `UIC_PREF_AI_APPS_IMAGE_POLICY` |

### `custom-daemon` (1 resource — ollama)

| Field | Sample |
|---|---|
| `bin` | `ollama` |
| `github_repo` | `ollama/ollama` |
| `install_app_path` | `/Applications/Ollama.app` |
| `pending_update_glob` | cache update glob |
| `process` | `ollama (serve|app)` |
| `self_updating` | `true` |
| `start_cmd` | `open -a Ollama` |
| `version_probe_path` | `/api/version` |

### `pyenv-brew` (1 resource)

No driver-level fields; bootstraps pyenv via Homebrew.

### `pip-bootstrap` (1 resource)

No driver-level fields; ensures pip in the active venv.

### `git-repo` (1 resource — rdpilot)

| Field | Sample |
|---|---|
| `dest` | `repos/github/bonomani/rdpilot` |
| `github_repo` / `repo` | `bonomani/rdpilot` |

### `git-global` (1 resource)

No driver-level fields; reads `global_config` from component vars.

### `script-installer` (1 resource — Oh My Zsh)

| Field | Sample |
|---|---|
| `github_repo` | `ohmyzsh/ohmyzsh` |
| `install_url` | `${omz_installer_url}` |
| `install_dir` | `${omz_dir}` |
| `upgrade_script` | `tools/upgrade.sh` |

### `zsh-config` (1 resource — agnoster theme)

| Field | Sample |
|---|---|
| `config_file` | `.zshrc` |
| `key` | `ZSH_THEME` |
| `value` | `${omz_theme}` |

### `path-export` (1 resource — `~/bin in PATH`)

| Field | Sample |
|---|---|
| `bin_dir` | `${home_bin_dir}` |
| `shell_profile` | `${shell_profile}` |

### `build-deps` (1 resource)

No driver-level fields; installs platform build toolchain.

### `brew-analytics` (1 resource)

No driver-level fields; toggles Homebrew analytics.

### `nvm` (1 resource)

| Field | Sample |
|---|---|
| `github_repo` | `nvm-sh/nvm` |
| `nvm_dir` | `${nvm_dir}` |

### `nvm-version` (1 resource — node-lts)

| Field | Sample |
|---|---|
| `nvm_dir` | `${nvm_dir}` |
| `version` | `${node_version}` |

### `brew-unlink` (1 resource)

| Field | Sample |
|---|---|
| `formula` | `${node_formula}` |

### `app-bundle` (1 resource — vscode)

| Field | Sample |
|---|---|
| `app_path` | `/Applications/Visual Studio Code.app` |
| `brew_cask` | `visual-studio-code` |
| `download_url_tpl` | upstream download template |
| `package_ext` | `zip` |
| `update_api` | upstream version API |

### `json-merge` (1 resource — vscode-settings)

| Field | Sample |
|---|---|
| `patch_relpath` | `${vscode_settings_patch}` |
| `settings_relpath` | `${vscode_settings_relpath}` |

### `softwareupdate-schedule` (1 resource)

No driver-level fields; toggles macOS Software Update schedule.

## Endpoint Sub-Schema (10 resources, 11 endpoints)

| Field | Live | Required | Meaning |
|---|---:|:---:|---|
| `name` | 11 | yes | Endpoint identifier (`Ollama API`, `Qdrant`) |
| `scheme` | 11 | yes | `http`, `https` |
| `host` | 11 | yes | usually `127.0.0.1` or `localhost` |
| `port` | 11 | yes | TCP port |
| `path` | 3 | no | health/probe path (`/api/tags`, `/health`) |
| `note` | 2 | no | free-form annotation |

## Evidence Sub-Schema

The `evidence:` field appears 22 times. The `evidence_type` discriminator is sparsely populated; observed nesting fields below.

| Field | Frequency | Meaning |
|---|---:|---|
| `status` | 7 | observed status string |
| `path` | 5 | filesystem path checked |
| `version` | 4 | version string captured |
| `value` | 2 | scalar value captured |
| `template` | 1 | template id |
| `plist` | 1 | macOS plist label |
| `service` | 1 | service name |
| `gpu` | 1 | GPU device type |
| `device` | 1 | hardware device |
| `install_source` | 1 | install method recorder |
| `pid` | 1 | process id |
| `fstype` | 1 | filesystem type |
| `user` | 1 | user identity |
| `evidence_type` | 1 | only one resource declares it explicitly |

Goal-model rule: every resource should declare a typed `evidence_type` and a
fixed sub-schema per type. Today this is loose.

## Action Sub-Schema (legacy form, absorbed)

The legacy `actions:` field appears 6 times in live YAML with two
subkeys: `install` (6) and `update` (4). The goal model absorbs both into
`operation_contract.converge` branches:

| Legacy `actions.<key>` | Goal-model home |
|---|---|
| `actions.install` | `operation_contract.converge.on_absent` |
| `actions.update` | `operation_contract.converge.on_outdated` |

After migration, `actions:` is removed from the schema. Pre/post effects
that the legacy code performed implicitly (PATH activation, restart of
Finder/Dock, daemon reload) become `operation_contract.pre_converge` /
`post_converge` hooks.

## Component Parameter Space

Each component declares scalar variables consumed by its drivers. Total: 69
component-level fields across the 11 components, beyond the 5 mandatory ones
(`component`, `primary_profile`, `libs`, `runner`, `platforms`).

In the live YAML these are **untyped strings** substituted at runtime. The
goal model promotes them to **typed parameters** with declared
`parameter_type` and `config_source` (cascade). See
`06-resource-schema.md` § Component Parameter Space (typed) for the full
schema and `09-executable-contract-and-orthogonality.md` § Rollout Order
phase M16 for the migration. Generator lists (`cli_tools`, `casks`,
`pip_groups`, `npm_packages`, `vscode_extensions`) migrate to
`resource-template` instances in phase M17.

### `ai-apps` (15 vars)

`api_host`, `api_port`, `api_tags_path`, `brew_service_name`,
`fallback_start_cmd`, `fallback_stop_pattern`, `large`, `log_file`,
`macos_min_version`, `medium`, `ollama_installer_url`, `on_fail`,
`preferences`, `small`, `stack`

### `ai-python-stack` (18 vars)

`gpu_backend`, `pip_bootstrap`, `pip_groups`, `preferences`, `pyenv_dir`,
`pyenv_git_sources`, `pyenv_packages`, `python_version`, `systemd_user_dir`,
`unsloth_host`, `unsloth_label`, `unsloth_log_file`, `unsloth_plist_marker`,
`unsloth_plist_relpath`, `unsloth_port`, `unsloth_service_name`,
`unsloth_studio_dir`, `zsh_config`

### `cli-tools` (8 vars)

`casks`, `cli_tools`, `global_config`, `home_bin_dir`, `omz_dir`,
`omz_installer_url`, `omz_theme`, `shell_profile`

### `docker` (6 vars)

`docker_desktop_app_name`, `docker_desktop_app_path`, `docker_desktop_cask_id`,
`docker_desktop_process`, `preferences`, `settings_relpath`

### `network-services` (3 vars)

`aria2_port`, `ariaflow_dashboard_port`, `ariaflow_port`

### `node-stack` (4 vars)

`node_formula`, `node_version`, `npm_packages`, `nvm_dir`

### `software-bootstrap` (5 vars)

`analytics_desired`, `installer_url`, `on_fail`, `platform_tool_preferences`,
`shell_config_file`

### `vscode-stack` (6 vars)

`vscode_cli_link_relpath`, `vscode_cli_path`, `vscode_code_cmd_hint`,
`vscode_extensions`, `vscode_settings_patch`, `vscode_settings_relpath`

### `system` (3 vars)

`on_fail`, `restart_processes`, `softwareupdate_domain`

### `linux-system` / `build-tools`

Only `on_fail` (or none).

These component vars are referenced inside drivers via `${var}` interpolation.

## State Model Exception

One resource writes `state_model:` explicitly:

| Resource | resource_type | profile | state_model |
|---|---|---|---|
| `ai-apps-template` | `precondition` | `configured` | `config` |

Goal-model derivation says:
`resource_type=precondition` → `convergence_profile_derived=configured` →
`state_model_derived=config`. The written value matches the derivation, so
this resource is consistent. Once `state_model` becomes a `_derived` field
in the schema, this written line should be removed.

## Suffix Conventions Summary

| Suffix | Source of truth? | Examples |
|---|---|---|
| `_type` | written | `resource_type`, `capability_type`, `driver_type` |
| `_source` / `_in` | written | `relation_source`, `selection_source`, `declared_in` |
| `_scope` | written | `capability_scope`, `gate_scope`, `provider_scope` |
| `_phase` | written | `relation_phase` |
| `_effect` | written | `relation_effect` |
| `_strength` | written | `consume_strength` |
| `_state` | written | `desired_state`, `observed_state` |
| `_required` | written | `admin_required` (legacy) |
| **`_derived`** | **never written as source** | `convergence_profile_derived`, `state_model_derived`, `dependencies_derived` |

## Validator Hooks

A future validator can use this registry as input:

```text
load registry
for each YAML resource:
  validate every field's value belongs to its registry
  for each `_derived` field:
    recompute and assert match
  for each open registry:
    record any new value as warning
```

Closed registries are blockers; open registries are advisories.
