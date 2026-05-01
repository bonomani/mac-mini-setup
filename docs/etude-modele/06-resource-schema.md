# 06 - Goal Resource Schema

This file defines the goal schema. It is not the current YAML schema yet; it is
the resource model that the current implementation migrates toward.

## Complete Convergence Resource

```yaml
cli-jq:
  element_type: managed-resource
  component: cli-tools

  resource_type: package
  convergence_profile_derived: configured
  state_model_derived: package

  requires:
    any:
      - platform: macos
      - platform: linux
      - platform: wsl2

  relations:
    - relation_type: consumes
      to:
        capability_type: package-manager
        name: brew
      consume_strength: hard
      condition: backend=brew
      relation_source: backend
      relation_effect: block

    - relation_type: consumes
      to:
        capability_type: package-manager
        name: native-package-manager
      consume_strength: hard
      condition: backend=native-pm
      relation_source: backend
      relation_effect: block

    - relation_type: consumes
      to:
        capability_type: package-manager
        any:
          - brew
          - native-package-manager
      consume_strength: hard
      relation_source: declared
      relation_effect: block

  provides:
    - capability_type: binary
      name: jq
      capability_scope: host

  resolved_dependencies:
    - resource: homebrew
      from: consumes package-manager:brew
      consume_strength: hard
    - resource: build-deps
      from: consumes package-manager:native-package-manager
      consume_strength: hard

  driver:
    driver_type: pkg
    backends:
      - brew: jq
      - native-pm: jq

  policy:
    update_class: tool
    selection_default: enabled

  desired_state:
    installation: Configured
    runtime: Stopped
    health: Healthy
    admin: Enabled
    dependencies: DepsReady

  operation_contract:
    observe:
      predicate: brew_pkg_is_installed
      state_command: brew_pkg_observe
      evidence:
        evidence_type: binary-version
        fields: { command: "jq --version" }
    converge:
      on_absent: brew_pkg_install      # legacy `action_type=install`
      on_outdated: brew_pkg_update     # legacy `action_type=update`
      on_drifted: brew_pkg_repair      # legacy `action_type=configure`
    pre_converge: []
    post_converge: []
```

The `action_type` of the resource's driver is **`converge`** (one of the
three primary actions). The actual sub-action is decided by the diff
between observed and desired state and dispatched through the
`operation_contract.converge.*` branches. See `13-field-values-registry.md`
§ `action_type` and `07-current-mapping.md` §8.

`admin_required` is not written: the `consumes admin-authority/sudo`
relation produces it (see L6). `endpoints[]`, `desired_value`,
`desired_cmd`, `oracle`, `observe_cmd`, top-level `evidence`, and
`actions:` are not present in the goal schema; their information is held
by `provides[].http-endpoint` (EXT-A), `desired_state.value` (EXT-B), or
`operation_contract` (L12, L15).

## Required Optimized Resource Semantics

In the goal model, every managed resource must expose the semantics that the
current implementation often keeps implicit.

```yaml
managed-resource:
  identity:
    name: cli-jq
    component: cli-tools

  lifecycle:
    resource_type: package
    convergence_profile_derived: configured
    state_model_derived: package

  applicability:
    requires:
      any:
        - platform: macos
        - platform: linux
        - platform: wsl2
    derived_from_hard_providers: []

  outputs:
    provides:
      - capability:binary/jq

  needs:
    consumes:
      - capability:package-manager/brew
      - capability:package-manager/native-pm

  provider_selection:
    strategy: first-compatible
    candidates:
      - provider: managed-resource:homebrew
        condition:
          equals:
            fact: backend
            value: brew
      - provider: managed-resource:build-deps
        condition:
          equals:
            fact: backend
            value: native-pm

  execution:
    driver_contract: driver-contract:pkg
    backend_contracts:
      - backend-contract:brew
      - backend-contract:native-pm

  operation_contract:
    operation_phases:
      observe: required
      converge: required
      verify: required
      evidence: required
      recover: optional
    pre_converge: optional
    post_converge: optional
    snapshot: optional

  compatibility_views:
    depends_on: generated
    requires_string: generated
```

Required resource rules:

| Resource class | Required semantic output |
|---|---|
| capability resource | stable provided capability ID |
| runtime resource with endpoints | derived `http-endpoint` capabilities |
| package resource | typed output capability: binary, app, model, extension, library, toolchain, or package |
| custom resource | explicit `operation_contract` |
| resource with conditional dependencies | condition intersection proof |
| resource with hard providers | derived applicability proof |
| package resource | package desired state, not `desired_value` |

## Complete Preflight Control

```yaml
supported-platform:
  element_type: preflight-gate
  gate_scope: global
  class: readiness
  condition: _gate_supported_platform
  relation_effect: block-run
```

## Layer And Component As Elements

```yaml
software:
  element_type: layer
  relations:
    - relation_type: contains
      to: cli-tools
      declared_in: model
      contains:
        cardinality: one-to-many
        order: declared

cli-tools:
  element_type: component
  parent: software
  relations:
    - relation_type: contains
      to: cli-jq
      declared_in: manifest
      contains:
        cardinality: one-to-many
        order: declared
```

## Complete Verification Test

```yaml
ollama-api-reachable:
  element_type: verification-test
  component: system
  verifies:
    - resource: ollama
      capability:
        capability_type: http-endpoint
        port: 11434
  oracle: http_probe_localhost 11434
  relation_effect: report-only
```

## Complete Run Session

```yaml
run-2026-05-01T120000Z:
  element_type: run-session
  correlation_id: "20260501T120000Z-host"
  mode: update
  dry_run: false
  interactive: false

  host_context:
    platform: macos
    platform_variant: macos
    arch: arm64
    os_id: macos-15.4
    package_manager: brew
    fingerprint_segments:
      - macos
      - arm64
      - brew

  selection_plan:
    source:
      - defaults/selection.yaml
      - preferences.env
      - selection.yaml
      - resource-overrides.yaml
      - cli_args
    default: all
    selected_resources:
      - cli-jq
    disabled_resources:
      - ollama-model-llama3.1-70b
    dependency_closure:
      - homebrew

  execution_plan:
    component_order:
      - software-bootstrap
      - cli-tools
    resource_order:
      - network-available
      - xcode-command-line-tools
      - homebrew
      - cli-jq

  artifact_contract:
    declaration: "$HOME/.ai-stack/runs/<id>.declaration.jsonl"
    result: "$HOME/.ai-stack/runs/<id>.result.jsonl"
    resource_status: "$HOME/.ai-stack/runs/<id>.resource-status"
    summary: "$HOME/.ai-stack/runs/<id>.summary"
    verification_report: "$HOME/.ai-stack/runs/<id>.verification.report"
```

## Complete Resource Operation

```yaml
cli-jq-operation:
  element_type: resource-operation
  resource: cli-jq
  session: run-2026-05-01T120000Z

  operation_phases:
    - declare
    - observe
    - diff
    - pre_converge
    - converge
    - post_converge
    - verify
    - recover
    - record

  consumes:
    - element_type: managed-resource-status
      name: homebrew
      consume_strength: hard
      relation_effect: block
    - element_type: observation-cache
      name: brew-versions
      consume_strength: soft
      relation_effect: observe

  produces:
    - element_type: run-artifact
      name: result-jsonl
    - element_type: run-artifact
      name: resource-status

  possible_outcomes:
    - ok
    - changed
    - failed
    - warn
    - policy
    - skipped
    - disabled
    - dry-run
```

## Schema Extensions Absorbing Legacy Duplicates

Five extensions, none of which adds a new top-level concept. EXT-A/B/C
absorb existing legacy duplicates; EXT-D/E enable version-aware and
parametric resolution. See `07-current-mapping.md` §8 for the legacy
field mapping.

### EXT-A — `provides[]` qualifiers for `http-endpoint`

```yaml
provides:
  - capability_type: http-endpoint
    name: ollama.tags
    capability_scope: host
    qualifiers:
      scheme: http
      host: 127.0.0.1
      port: 11434
      path: /api/tags
```

`endpoints[]` is removed. Verification tests target the capability directly.

### EXT-B — `desired_state.value` polymorphic axis

```yaml
desired_state:
  value: { literal: "0" }
# or
  value: { command: get_pmset_value }
```

`desired_value` and `desired_cmd` are removed.

### EXT-C — `inhibitor` block on `operation-outcome`

```text
when outcome_type ∈ { policy, skip, disabled, dry-run }:
  inhibitor block is required
otherwise:
  inhibitor block is forbidden
```

`inhibitor.inhibitor_type` reuses the existing enum.

### EXT-D — version qualifiers on `provides[]` and `consumes[]`

Capabilities can carry a `version` qualifier. Providers expose the exact
version they install; consumers express a constraint. The validator
matches with semver-style grammar.

```yaml
# A provider exposes its exact version
provides:
  - capability_type: language-runtime
    name: node
    qualifiers:
      version: "20.15.0"

# A consumer expresses a constraint
consumes:
  - capability_type: language-runtime
    name: node
    qualifiers:
      version: "<=20"           # supported: =, >=, <=, >, <, ~, ^, ranges, OR via ||
    consume_strength: hard
```

| Operator | Example | Match |
|---|---|---|
| `=` (default) | `version: "20.15.0"` | exact |
| `>=` / `<=` / `>` / `<` | `version: "<=20"` | comparison |
| `~` | `version: "~20.15"` | tilde range |
| `^` | `version: "^20"` | caret range |
| range | `version: ">=18 <22"` | intersection |
| OR | `version: "18.x \|\| 20.x"` | union |

Provider-selection rejects providers whose `version` qualifier does not
satisfy the consumer's constraint.

### EXT-E — parametric resources

A resource can declare itself parametric in one or more inputs. The
validator instantiates a concrete copy of the resource for each distinct
input value demanded by a consumer.

```yaml
node-versioned:
  resource_type: package
  parametric_in: [version]
  driver:
    action_type: install
    tool_type: nvm
    parameters:
      version: "${requested.version}"
  consumes:
    - capability_type: tool
      name: nvm
  provides:
    - capability_type: language-runtime
      name: node
      qualifiers:
        version: "${this.version}"
```

When a consumer asks for `language-runtime:node@<=20`, the validator
picks a concrete version (e.g. the latest LTS satisfying the constraint),
instantiates `node-versioned[version=20.15.0]`, and resolves the closure
through it.

Rules:

- `parametric_in:` lists the parameters the validator may bind.
- `${requested.X}` reads the consumer's qualifier `X`.
- `${this.X}` reads the resolved bound value (used to compute `provides`).
- Two consumers asking for the same value reuse the same instance; two
  consumers asking for different values produce two instances side by side.
- The instance id includes the parameter values: `node-versioned@20.15.0`.

This formalizes the pattern already present in legacy form via
`nvm-version` (single static version) and via the `pip-group-*` family
(parameter list passed at component level). EXT-E lifts the parameter
from a static manifest variable to a dynamic value derived from the
consumer's request.

## Configuration as a First-Class Dimension

30 of the 147 live resources (~20%) are `resource_type: config`.
Configuration shares the action vocabulary of install/update (one verb,
`converge`, with branches dispatched by diff) but exposes **five extra
structural properties** that pure installs never have. The model handles
them with one new relation type, two new enums, and the reuse of two
existing concepts. No new top-level element class.

### 1. `configures` — explicit coupling to the consumer

A config resource is the configuration **of** something. The relation is
explicit, not implicit through `depends_on`.

```yaml
git-global-config:
  resource_type: config
  relations:
    - relation_type: configures        # new value (relation_type goes from 13 to 14)
      to: managed-resource:git
      condition:
        equals: { fact: package_state, value: configured }
```

Effect: the validator can detect orphaned configs (configure a missing
resource) and flag packages that should have a config but do not. Replaces
the implicit `depends_on: [git]` for config resources whose semantic role
is configuration. `depends_on` is still allowed for non-configuration
preconditions.

### 2. `config_source` — explicit cascade of value origins

A configured value can originate from several sources with a precedence:

```text
defaults                   (defaults/preferences.yaml)
   ↓ overridable by
component-preference       (component.preferences:)
   ↓ overridable by
resource-override          (UCC_OVERRIDE__*, resource-overrides.yaml)
   ↓ overridable by
operator-cli               (--set arg, env var)
```

Recorded on the resolved `desired_state.value`:

```yaml
desired_state:
  value:
    literal: "0"
    config_source: defaults
```

Closed enum: `defaults`, `component-preference`, `resource-override`,
`operator-cli`. Parallel to the existing `selection_source` for selection
inputs. Validator emits the source in run reports and verification
artifacts so a user can answer *« why is this value 0? »* without reading
the bash.

### 3. `capability_scope` — reuse for config scope

The `capability_scope` enum (`host`, `user`, `app`, `component`,
`container`, `external`) is reused on config resources to express the
reach of the change:

```yaml
pmset-ac-sleep=0:
  capability_scope: host         # affects whole machine

git-global-config:
  capability_scope: user         # affects ~/.gitconfig

vscode-settings:
  capability_scope: app          # affects only VS Code profile
```

No new field. The existing enum is sufficient. Validator uses it for
rollback safety (host-scope changes are riskier than app-scope) and for
admin policy (host-scope changes typically require `admin-authority`).

### 4. `merge_semantics` — replace vs merge

Configuration writes are not all the same. The `setting` driver replaces;
`json-merge` deep-merges; PATH manipulation appends without duplicates.
The semantic must be explicit in the desired_state:

```yaml
desired_state:
  value:
    command: read_settings_template
    merge_semantics: deep-merge
```

Closed enum (4 values):

| Value | Behavior | Driver examples |
|---|---|---|
| `replace` | observed value entirely overwritten (default) | `setting`, `defaults`, `pmset` |
| `shallow-merge` | top-level key-by-key merge | shell rc files (per key) |
| `deep-merge` | recursive merge | `json-merge` for VS Code settings |
| `append` | additive without duplicates | PATH, `sources.list`, completion files |

Validator rejects mismatched pairs (e.g. a `replace` semantics on a
multi-section file is almost certainly a regression).

### 5. `post_converge` typed reload — `notify_resource` hook

The hook system already accepts arbitrary post-converge functions. For
configuration that requires a reload of a consumer (Finder reads its
prefs only at start; systemd needs `daemon-reload`; brew services need
restart), a typed pattern formalizes the intent:

```yaml
finder-show-hidden=1:
  operation_contract:
    converge:
      on_drifted: defaults_write_finder_hidden
    post_converge:
      - notify_resource:
          resource: managed-resource:Finder.app
          notify_signal: reload-config
```

`notify_signal` values: `reload-config`, `restart`, `daemon-reload`, `sighup`.

Replaces the legacy component-level `restart_processes: Finder, Dock`
which was a hidden cross-resource side effect. The new form makes the
notification visible at the resource level and reusable across drivers.

### Worked example

```yaml
vscode-settings:
  resource_type: config
  capability_scope: app

  relations:
    - relation_type: configures
      to: managed-resource:vscode

  desired_state:
    value:
      command: render_vscode_settings_template
      config_source: defaults              # overridable by user override
      merge_semantics: deep-merge

  driver:
    action_type: converge
    tool_type: none

  operation_contract:
    observe:
      state_command: read_vscode_settings
    converge:
      on_drifted: json_merge_settings_patch
    post_converge:
      - notify_resource:
          resource: managed-resource:vscode
          notify_signal: reload-config
```

A single resource declaration captures: what it configures, where the
value comes from, what scope it touches, how it merges, and what to
reload when it changes. The validator can answer all five structural
questions automatically.

### What does **not** belong here

- The verb (install / update / configure / start / stop) — already a
  branch of `converge`, not a configuration concept.
- Pre-action setup (PATH activation, shim load) — already covered by
  `pre_converge` hooks, applies to all resources, not only configs.
- Selection (which configs to apply this run) — already covered by
  `selection-plan`, parallel to `selection_source`.

## Component Parameter Space (typed)

The 11 components carry **69 scalar variables** (`python_version`,
`unsloth_port`, `aria2_port`, `omz_theme`, …) consumed by drivers via
`${var}` interpolation. Today these are untyped strings substituted at
runtime. The goal model promotes them to **typed parameters** with a
declared origin.

### Typed parameter declaration

```yaml
component: ai-python-stack
parameters:
  python_version:
    parameter_type: semver
    default: "3.12.3"
    config_source: defaults
    description: Python version installed via pyenv
  unsloth_port:
    parameter_type: port
    default: 7860
    range: [1024, 65535]
    config_source: defaults
  pyenv_dir:
    parameter_type: path
    default: ".pyenv"
    capability_scope: user
  pip_groups:
    parameter_type: list
    item_schema:
      name: string
      packages: string
      min_version: { parameter_type: semver-constraint, optional: true }
```

### `parameter_type` (closed enum)

| Value | Examples |
|---|---|
| `string` | `omz_theme: agnoster` |
| `int` | `cpu_count: 10` |
| `path` | `pyenv_dir: .pyenv` |
| `url` | `installer_url: https://…` |
| `port` | `unsloth_port: 7860` |
| `semver` | `python_version: 3.12.3` |
| `semver-constraint` | `min_version: ">=2.0"` |
| `bool` | `analytics_desired: false` |
| `enum` | `gpu_backend: { values: [mps, cuda, cpu] }` |
| `list` | `npm_packages: [...]` |
| `cask-id` | `docker_desktop_cask_id: docker` |
| `process-pattern` | `docker_desktop_process: "Docker Desktop"` |

The validator typecheck each parameter against its declared type and
rejects bad values before the run starts.

### Resource-templates absorb generator lists

Five legacy generator lists (`cli_tools`, `casks`, `pip_groups`,
`npm_packages`, `vscode_extensions`) become first-class
`resource-template` elements (already declared in 09 § Improved Concept
Set, made concrete here):

```yaml
component: cli-tools
resource_templates:
  - id: cli_tool_template
    parametric_in: [name, brew_ref, native_ref, bin]
    expansion_rule: one-resource-per-instance
    output_template:
      resource_type: package
      driver:
        action_type: converge
        tool_type: brew | native-pm
        backends:
          - brew: ${brew_ref}
          - native-pm: ${native_ref}
        bin: ${bin}
      provides:
        - capability_type: binary
          name: ${bin}
    instances:
      - { name: cli-jq, brew_ref: jq, native_ref: jq, bin: jq }
      - { name: cli-ripgrep, brew_ref: ripgrep, native_ref: ripgrep, bin: rg }
      - { name: cli-fd, brew_ref: fd, native_ref: fd, bin: fd }
      # … 50+ more
```

The current ~50 `cli-*` resources, ~16 `pip-group-*` resources, ~10
`vscode-ext-*` resources, ~7 `npm-global-*` resources, and the cask
list disappear from the YAML. They are **generated by the validator**
from one template + an instance list. Only the template + the list are
source of truth.

### Cascade of values

Like configuration values (see § Configuration as a First-Class
Dimension), a parameter can be overridden:

```text
defaults                        defaults/preferences.yaml
   ↓
component-preference            component.preferences:
   ↓
resource-override               UCC_OVERRIDE__*, resource-overrides.yaml
   ↓
operator-cli                    --set parameter, env var
```

The resolved value's `config_source` is recorded in the run report so
the operator sees *« python_version=3.12.3 vient de defaults, override
possible via UCC_OVERRIDE__PYTHON_VERSION »*.

### Migration impact

- All current `${var}` interpolations continue to work during migration
  (the validator types and validates the existing values, no rewrite needed).
- Generator lists migrate component-by-component to `resource-template`.
- 69 component-level scalars become typed parameters; type errors show
  up at validation time instead of at apply time.

This closes the gap between the goal model's parameter-space concept
(documented in 13 § Component Parameter Space) and the actual YAML.

## Virtualization Pattern (hypervisor + VMs)

Hypervisors and VMs follow the same multi-level containment pattern as
Docker (host → daemon → stack → container). Three levels of
`managed-resource`, each consuming the capability of the level below.

```yaml
# Level 1 — installer (existing pattern)
vmware-fusion:
  resource_type: package
  driver:
    driver_type: pkg
    backends:
      - brew-cask: vmware-fusion
  requires:
    platform: macos
  provides:
    - capability_type: app-bundle
      name: vmware-fusion

# Level 2 — running hypervisor service
vmware-fusion-running:
  resource_type: runtime
  driver:
    action_type: start
    tool_type: vmware
  consumes:
    - capability_type: app-bundle
      name: vmware-fusion
      consume_strength: hard
  provides:
    - capability_type: hypervisor-runtime
      name: vmware-fusion

# Level 3 — declared VM
my-test-vm:
  resource_type: runtime
  driver:
    action_type: start            # observe/start/stop/snapshot
    tool_type: vmware
    parameters:
      vmx_path: ~/VMs/test/test.vmx
      memory_mb: 4096
      cpu_count: 4
      snapshot: clean
  consumes:
    - capability_type: hypervisor-runtime
      name: vmware-fusion
      consume_strength: hard
  provides:
    - capability_type: vm-runtime
      name: my-test-vm
      qualifiers:
        guest_os: ubuntu-24.04
        guest_arch: arm64
```

The same shape with `tool_type: hyperv` or `tool_type: qemu` covers
Hyper-V and QEMU. Adding a hypervisor brand is one new `tool_type`
value plus one driver implementation; no model change.

## Host predicate structure

Progressively replace free-form strings:

```yaml
requires: macos>=14,linux,wsl2
```

with a validatable structure:

```yaml
requires:
  any:
    - os:
        name: macos
        version: ">=14"
    - platform: linux
    - platform: wsl2
```

The supported host atoms are:

| Atom | Example |
|---|---|
| platform | `macos`, `linux`, `wsl2` |
| init | `launchd`, `systemd`, `no-init-system` |
| package_manager | `brew`, `apt`, `dnf`, `pacman` |
| arch | `arm64`, `x86_64` |
| os_version | `macos>=14`, `ubuntu>=22.04` |
| fingerprint_segment | explicit segment of `HOST_FINGERPRINT` |

## Validation Rules To Add

1. Every hard `relation_type=consumes` relation must be satisfied by a compatible
   `provides` entry or by a declared external capability.
2. Every conditional relation must have a valid host condition.
3. Every driver/backend dependency must be exposed through validatable metadata.
4. Every `consumes` relation must be satisfied by at least one compatible
   `provides` entry, unless the capability is marked external.
5. Every verification test must verify a declared resource or capability.
6. Every `requires` value must use known atoms.
7. Every impossible condition between a resource and its dependency must be a
   warning or an error.
8. Every admin action must be represented by policy or by a dependency on
   `sudo-available`.
9. Generated docs must take their cardinalities from the manifests.
10. Hard and soft dependencies must be `consumes` relations with the same
    relation schema; only the `strength` value changes.
11. The executable `depends_on` field must be derivable or verifiable from
    `consumes` + `provides`.
12. A run session must record the host context used to resolve `requires` and
    conditional dependencies.
13. A selection plan must be derivable from defaults, preferences, CLI args,
    user selection files, disabled resources, and dependency closure.
14. A resource operation must declare the phases it supports: observe, apply,
    verify, recover, evidence.
15. Run artifacts must be tied back to a session, resource, phase, and outcome.
16. Generated docs must declare their source elements and drift-check command.
17. Cache entries must declare scope, TTL, and invalidating actions when they
    can influence an observation.
18. Relation fields must be relation_type-specific. For example, `strength` belongs to
    `consumes`; it is not required for `contains`, `records`, or
    `derives`.
19. Every compatibility field must have a declared projection rule from the
    goal model, or a declared importer rule into the goal model.
20. Every goal-model concept must pass the orthogonality check: it owns one axis and
    does not duplicate lifecycle, policy, execution, or evidence semantics from
    another concept.
21. Every conditional dependency must have an applicability
    intersection:
    resource condition + relation condition + provider condition.
22. Every capability resource must declare or derive the capability it provides.
23. Every runtime endpoint must declare or derive an `http-endpoint`
    capability.
24. Every package resource must declare or derive its output capability:
    binary, app bundle, extension, model, library, toolchain, or package.
25. Every `driver.driver_type: custom` resource must have an explicit
    `operation-contract` or must be migrated to a named driver contract.
26. Applicability inherited through hard dependencies must be visible to the
    validator, so dependents do not silently apply where their providers cannot.
27. Package presence must live in package desired state, not in
    `desired_value`; `desired_value` is reserved for parametric config values.

## Compatibility Migration

| Step | Change | Risk |
|---|---|---|
| 1 | Add `provides` compatibility imports to critical resources | low |
| 2 | Add `consumes` compatibility imports for packages, services, verification | low |
| 3 | Expose driver/backend deps in one metadata table | medium |
| 4 | Run capability-aware validation as a migration warning before enforcing it | medium |
| 5 | Convert selected warnings into errors | medium |
| 6 | Structure `requires` without breaking the existing string syntax | medium |
| 7 | Link verification tests to `verifies` | low |
| 8 | Add `run-session`, `selection-plan`, and `artifact-contract` docs schema | low |
| 9 | Add validator output for host context and resolved execution plan | medium |
| 10 | Add cache metadata for observation caches that affect update decisions | medium |
| 11 | Add compatibility projections so legacy fields can be generated or verified | medium |
| 12 | Enforce orthogonality rules in schema review before making fields required | low |
| 13 | Add goal-model resource-spec checks as migration warnings before enforcing them | low |
| 14 | Promote endpoint, package-output, and capability-resource derivations to schema | medium |
| 15 | Replace impossible conditional dependency edges with provider-selection rules | medium |

## Expected Result

The project moves from:

```text
resource-name graph + driver conventions
```

to:

```text
capability-aware convergence model
```

with a more explicit graph, separated policies, and verification tests linked
to the capabilities they prove.
