# Model

> **Status**: candidate canonical model, derived from a deep review of the v3
> spec and the live `mac-mini-setup` YAML. Supersedes the 13 numbered specs
> (`01-elements.md` … `13-field-values-registry.md`) once accepted. The
> numbered docs remain as historical / detailed reference until that point.

## Core principle

Every node in the system — package, daemon, config setting, capability
check, verification test, preflight gate — is a **resource**. Resources
have the same shape. The only edges between resources are typed
**capabilities** that one resource `provides` and another `consumes`.

Every action the engine performs on a resource is on one of three state
**axes**: `install`, `config`, `run`. A resource subscribes to a subset
(0–3) of axes. Subscription is implied by the resource's `driver.kind`;
for `kind: custom` it is declared explicitly.

```
Project
  ├── Component (n)
  │     └── Resource (n)
  │           ├── consumes  → Capability ←──┐
  │           ├── provides  → Capability ──┘
  │           ├── driver { kind, params }
  │           └── policy { ... }
  ├── Host  (built-in; provides platform/*, arch/*, os_id/*, ...)
  └── RunSession (n)
        └── Operation (n)   per (resource × axis × session)
```

## Resource

Every resource has exactly this shape. There is no `element_type`
discrimination — what a resource does is determined by its `driver.kind`
and the capabilities it provides.

### Promotion / demotion lifecycle

"Managed" and "unmanaged" are not static categories. Every resource
sits on a continuum of engine responsibility, and its position can
change over time:

```
fact (host-published)            ←  capability comes from `Host` resource
   ↑↓
external-provider                 ←  capability `external: true`,
                                     observed via `kind: observe`
   ↑↓
unmanaged resource                ←  has provides + observe; no axes
   ↑↓
managed resource                  ←  has axes + driver; engine drives convergence
```

A resource is **promoted** by adding an `axes` block (the engine starts
managing what was only observed). It is **demoted** by removing axes
(the engine stops managing; the capability still publishes if the
observation passes).

Examples:
- `python-venv-available` is currently unmanaged (observe-only). It
  could be promoted to managed if we wanted the engine to install
  Python venv.
- A future host where Homebrew is operator-installed could see
  `homebrew` demoted to a capability check.
- Platform facts (`platform/macos`) are never managed — they live at
  the top of the ladder as host-published.

The model accepts movement along this ladder without breaking
consumers, because `consumes(X)` only cares that `X` is published, not
which level of the ladder published it.

```yaml
resource:
  id:           <string>                                # required, globally unique
  name:         <string>                                # required, human-readable
  display_name: <string>                                # optional
  component:    <component-id>                          # required

  consumes:
    - capability: <Capability>
      strength:   hard | soft | applicable              # required
      condition?: <Predicate>                           # only consume when predicate holds
      priority?:  <int>                                 # tie-break when multiple match
      args?:      { ... }                               # passed to the provider's operations

  provides:
    - capability: <Capability>
      when_axes?: [<axis>, ...]                         # ALL listed axes must converge for delivery
      condition?: <Predicate>                           # only expose when predicate holds

  driver:
    kind:        <kind>                                 # one of the registered kinds (see catalog)
    # kind-specific parameters
    # plus the following common slots:
    hooks?:
      pre?:  [{ fn: <fn-name> }]
      post?: [{ fn: <fn-name> } | { notify_resource: <id>, signal: <signal> }]
    snapshot?: { capture: <fn>, restore: <fn> }

  policy?:
    admin?:             <Predicate> | true | false      # default absent = never required
    selection_default?: <Predicate> | true | false      # default absent = enabled
    update?:            never | on-demand | tool-driven # default tool-driven
    version_pin?:       <semver-string>                 # if set, pin to this version
    destructive?:       <bool>
```

### `consumes.strength` values

| Value | Effect when capability is missing |
|---|---|
| `hard` | The resource cannot converge — block. |
| `soft` | The resource is ordered after the capability provider when present, but converges anyway when absent. |
| `applicable` | The resource is **skipped entirely** on hosts where this capability cannot be obtained. Used for platform gating. |

Multiple `applicable` entries on the same resource are OR'd: the resource
is applicable if any one of them is satisfiable.

### `consumes.priority`

When multiple `provides` match a `consumes` (and conditions all evaluate
true), the highest-priority candidate wins. Ties are broken by
declaration order. Default priority is 0.

### `consumes.args`

Free-form parameters passed to the provider's operation handlers. The
schema is governed by the consumed capability's type (e.g.
`package-manager/*` accepts `{ ref }`).

### `provides.when_axes`

Lists the axes that must all be in their desired state for the
capability to be delivered to consumers. Examples:

- `[install]` — capability is delivered as soon as install converges
- `[install, run]` — capability is only delivered when both install
  and run converge (e.g. a daemon's HTTP endpoint)

If `when_axes` is omitted, the capability is delivered whenever the
resource's `driver.observe` (kind=observe) returns true.

## Capability

The only currency between resources.

```yaml
capability:
  capability_type:  <namespace>                         # binary, package-manager, daemon, http-endpoint, ...
  name?:            <string>                            # specific identifier within the type
  capability_scope: host | user | component | container | service
  qualifiers?:      { version?, port?, scheme?, host?, path?, ... }
  external?:        bool                                # true = host-published / OS-shipped (not engine-managed)
```

`external: true` marks a capability the engine observes but cannot
control — typically host facts (`platform/macos`) or OS-shipped
binaries the engine doesn't own. The resolver prefers
non-`external` providers when both can satisfy a `consumes`, since
external capabilities can disappear without engine-visible cause.

> **Note**: v3 had `capability_scope: external` as a 6th scope value.
> It was removed because controllability is a separate concern from
> scope. Use `capability_scope: host` (or whichever scope applies)
> plus `external: true`.

### Capability families and their typical axis subscription

Each `capability_type` namespace implies which axes a provider must
have. A `provides` whose `when_axes` doesn't match its capability
family is a modeling error.

| Capability namespace | Required `when_axes` |
|---|---|
| `binary/*`, `app-bundle/*`, `package-manager/*`, `python-package/*`, `node-package/*`, `app-extension/*`, `ai-model/*` | `[install]` |
| `config-file/*`, `os-setting/*` | `[config]` |
| `daemon/*`, `socket/*`, `http-endpoint/*`, `compose-stack/*` | `[install, run]` (or `[run]` if install is delegated to a sibling resource) |
| `capability/*`, `preflight/*`, `verification/*`, `managed-resource-status/*` | `[]` (omit `when_axes`; observation-only) |
| `platform/*`, `arch/*`, `os_id/*`, `os_version/*`, `init-system/*`, `hardware-accel/*` | `[]` + `external: true` (immutable host facts — engine cannot ever influence) |
| `package-manager-available/*`, `shell/*`, `network-connectivity/*` | `[]` (host-observed state — may flip as a side-effect of other resources converging; do **not** set `external`) |

### Matching rule (consumes ↔ provides)

`consumes(C_req)` matches `provides(C_off)` if and only if:

1. `capability_type` matches exactly.
2. `name` matches exactly (or both omit it).
3. `capability_scope` matches exactly. **No wildcards.**
4. For each qualifier `(k, v_req)` in `C_req.qualifiers`:
   - if `v_req` is scalar: `C_off.qualifiers[k] == v_req`
   - if `v_req` is `{ op, value }`: `C_off.qualifiers[k]` satisfies the
     comparison (semver or numeric)
   - if `v_req` is `{ in: [...] }`: `C_off.qualifiers[k]` is in the list
   - if `k` is absent from `C_off.qualifiers`: **no match**
5. Qualifiers present in `C_off` but not mentioned in `C_req` are ignored.

A consumer that wants to accept multiple scopes must declare multiple
`consumes` entries (one per scope). Determinism over expressiveness.

### Provider selection (when multiple providers match)

When a `consumes(X)` matches multiple `provides(X)`, the planner picks
exactly one provider per resolution rule, in order:

1. **Filter by condition.** Drop any `consumes` entry whose
   `condition` evaluates false against the live `HostContext`. Drop
   any `provides` whose `condition` evaluates false.
2. **Filter by qualifier match** (the matching rule above).
3. **Pick highest `priority`** among surviving candidates. Default
   priority is 0.
4. **Tie-break** by `consumes` declaration order (first wins).

**Operator-level preference** ("always prefer brew over native-pm on
this host") is expressed using the existing primitives — no new element
class:

- The component declares a typed `parameter` (e.g. `pm: { type: enum,
  options: [brew, native-pm], default: brew, source: operator-cli }`).
- Each consumer's `consumes` carries a `condition: { fact: pm, eq: brew }`.
- Operator overrides via `--set pm=native-pm` (resolved at substitution
  time, see § Parameter substitution).

For preferences that **must** apply uniformly without each consumer
declaring the condition, expose the chosen provider as a
`Host`-published capability (e.g. `package-manager-selected/brew`) and
have all consumers consume that abstract capability. The mapping from
operator input to the published capability lives in one place (the host
preference resolver), not in every consumer.

Two mechanisms — per-consumer condition + abstract host-published
capability — are deliberately the only ones. A separate `Preference`
element class was considered and rejected: it would duplicate either
component parameters (for input) or capabilities (for the resolved
choice).

## Axes

Every action the engine performs is on one of three state axes:

| Axis | Question | Apply branches |
|---|---|---|
| **install** | Is the artifact present at the right version? | `absent`, `outdated` |
| **config** | Are declared settings the same as live settings? | `drifted` |
| **run** | Is the runtime in the desired execution state? | `to_running`, `to_stopped`, `topology_diff` |

A resource subscribes to a subset of these. Subscription is implied by
`driver.kind`; for `kind: custom` it is declared in `driver.axes`.

The `health` of a resource is **not a separate axis**. It is the live
state of `provides`: a resource is healthy iff it is currently delivering
all its declared capabilities (whose `when_axes` are converged).

## Driver kinds

Each registered kind tells the engine which axes a resource subscribes
to and how to dispatch the per-axis operations. `custom` is the escape
hatch.

| Kind | Implied axis | Parameters |
|---|---|---|
| `observe` | none | `predicate?: <Predicate>` OR `fn?: { name, args? }` |
| `pkg` | install | `refs: { brew?, native-pm?, brew-cask?, ... }`, `bin?` |
| `pip` | install | `isolation`, `probe_pkg`, `install_packages` |
| `npm` | install | `package`, `version?` |
| `git-repo` | install | `url`, `dest`, `ref?` |
| `pyenv` | install | `version` |
| `nvm` | install | `version` |
| `vscode` | install | `extension_id` |
| `ollama` | install | `model` |
| `script-installer` | install | `url`, `verify_cmd?` |
| `app-bundle` | install | `bundle_path`, `source` |
| `home-artifact` | install | `dest`, `source` |
| `setting` | config | `path`, `key`, `value` |
| `git-global` | config | `key`, `value` |
| `path-export` | config | `dirs`, `rc_file` |
| `compose-file` | config | `path`, `content` |
| `swupdate-schedule` | config | `enabled`, `frequency` |
| `service` | run | `unit`, `manager: launchd|systemd|brew-services` |
| `compose-apply` | run | `compose_file`, `services?` |
| `docker-compose-service` | run | `service_name` |
| `custom-daemon` | run | `pid_fn`, `start_fn`, `stop_fn` (ad-hoc daemons not under a service manager) |
| `brew-analytics` | config | `desired` |
| `json-merge` | config | `target_file`, `keys` (deep-merge JSON config files, e.g. VSCode settings) |
| `softwareupdate-schedule` | config | `enabled`, `frequency` (macOS softwareupdate config; alias of `swupdate-schedule`) |
| `zsh-config` | config | `theme`, `installer_url`, `omz_dir` (oh-my-zsh setup) |
| `path-export` | config | `dirs`, `rc_file` |
| `compose-file` | config | `path`, `content` |
| `swupdate-schedule` | config | `enabled`, `frequency` |
| `setting` | config | `path`, `key`, `value` |
| `git-global` | config | `key`, `value` |
| `brew-unlink` | install | `formula` (unlinks a brew formula to free a name) |
| `build-deps` | install | `set: brew|apt|dnf` (installs platform-specific build essentials) |
| `corepack` | install | `enabled` (enables Node corepack) |
| `nvm-version` | install | `version` (sets active Node version via nvm; depends on `nvm`) |
| `pip-bootstrap` | install | (bootstraps pip itself; no params) |
| `pyenv-brew` | install | (installs pyenv via brew; specialty wrapper around `pkg`) |
| `custom` | declared | `axes: { install?, config?, run? }` |

### `kind: observe` — the universal observation driver

Replaces the former `capability`, `predicate`, and `oracle` kinds.

```yaml
driver:
  kind: observe
  predicate?: <Predicate>                          # pure data, no fn ref
  fn?:        { name: <fn-name>, args?: [...] }    # arbitrary callable
  # exactly one of `predicate` or `fn`
```

### `kind: custom` — bespoke per-axis logic

```yaml
driver:
  kind: custom
  axes:
    install?:
      desired:   <value> | { command: <fn> }
      observe:   <fn>
      apply:     { absent?: <fn>, outdated?: <fn> }
      recover?:  <fn>
      evidence?: { type: <evidence_type>, fields: { ... } }
    config?:
      desired:          <value> | { command: <fn> }
      observe:          <fn>
      apply:            { drifted?: <fn> }
      merge_semantics?: replace | shallow-merge | deep-merge | append    # default: replace
      recover?:         <fn>
      evidence?:        { type, fields }
    run?:
      desired:   running | stopped
      observe:   <fn>
      apply:     { to_running?: <fn>, to_stopped?: <fn>, topology_diff?: <fn> }
      recover?:  <fn>
      evidence?: { type, fields }
```

`merge_semantics` (config axis only) tells the engine how a write
combines with the live value. Without it, two resources writing the
same file silently overwrite each other.

| Value | Behavior | Used by |
|---|---|---|
| `replace` | overwrite entirely (default) | `setting`, `defaults`, `pmset` |
| `shallow-merge` | top-level key-by-key | shell rc files |
| `deep-merge` | recursive | `json-merge` (VS Code settings) |
| `append` | add to existing list | `path-export` |

### Hooks (any kind)

```yaml
driver:
  hooks:
    pre?:  [{ fn: <fn-name> }]
    post?: [{ fn: <fn-name> } | { notify_resource: <id>, signal: reload-config | restart | daemon-reload | sighup }]
```

### Snapshot (rare — VM-style resources)

```yaml
driver:
  snapshot?: { capture: <fn>, restore: <fn> }
```

## Predicate

The universal condition language. Used in `consumes.condition`,
`provides.condition`, `policy.admin`, `policy.selection_default`,
`driver.observe.predicate`.

```
Predicate :=
  | { fact: <name>, eq:  <value> }
  | { fact: <name>, neq: <value> }
  | { fact: <name>, in:  [<value>, ...] }
  | { fact: <name>, op:  lt | le | gt | ge, value: <value> }
  | { all: [<Predicate>, ...] }
  | { any: [<Predicate>, ...] }
  | { not: <Predicate> }
```

Facts come from the `Host` resource's `provides` (platform, arch, os_id,
…) and from configured component preferences.

Predicates are evaluated at **plan time** against the live `HostContext`.
Re-evaluation during a single run is not guaranteed.

## Component

Components group resources for selection, display, and parameter
scoping. Components form a tree under the project root.

```yaml
component:
  id, name, display_name
  parent?: <component-id>

  parameters?:
    <param-name>:
      type:        string | int | semver | port | path | url | bool | enum | list
      default:     <value>
      source:      defaults | component-preference | resource-override | operator-cli
      options?:    [<value>, ...]
      rationale?:  <string>

  resource_templates?:
    - id:              <template-id>
      parametric_in:   [<param-name>, ...]
      output_template: { ... resource shape with ${param} substitutions ... }
      instances:       [{ <param>: <value>, ... }, ...]
```

### Parameter substitution

`${param-name}` references in any string-typed field expand at **load
time**, in a single pre-validation pass. By the time a resource reaches
the planner, no `${...}` tokens remain. There is no late binding.

**Resolution order** (highest precedence wins):

| Source | Where it comes from |
|---|---|
| `operator-cli` | `--set <name>=<value>` flag or `UCC_OVERRIDE__<NAME>` env var |
| `resource-override` | `defaults/resource-overrides.yaml` |
| `component-preference` | the component's `parameters[<name>].default`, possibly platform-filtered |
| `defaults` | `defaults/preferences.yaml` |

**Errors at validation time** (the resource is rejected):

- `${var}` references a name not declared in `component.parameters`
- the resolved value's type does not match `parameters[<name>].type`
- the resolved value is not in `parameters[<name>].options` (if `options` is set)

**Scope**: substitution sees only the parameters of the resource's own
component (and its ancestors via `parent`). Cross-component refs are not
allowed; for those, expose the value as a capability instead.

**Determinism**: substitution depends only on host facts and operator
input known before validation. Once a `RunSession` starts, every
resource has a frozen, fully-substituted shape.

## Host (built-in)

The engine emits a virtual `host` resource that exposes machine facts as
capabilities. Other resources consume them like any other capability.

```yaml
id: host
component: <root>
provides:
  # Immutable host facts — engine cannot ever influence these.
  - { capability: { capability_type: platform,       name: macos | linux | wsl2,    capability_scope: host, external: true } }
  - { capability: { capability_type: arch,           name: arm64 | x86_64,           capability_scope: host, external: true } }
  - { capability: { capability_type: os_id,          name: <id>,                     capability_scope: host, external: true } }
  - { capability: { capability_type: os_version,     name: <semver>,                 capability_scope: host, external: true } }
  - { capability: { capability_type: hardware-accel, name: mps | cuda,               capability_scope: host, external: true } }
  - { capability: { capability_type: init-system,    name: launchd | systemd | none, capability_scope: host, external: true } }
  # Host-observed state — may flip as a side-effect of other resources
  # converging (e.g. installing brew makes package-manager-available/brew
  # become true). The engine influences these indirectly, so no `external`.
  - { capability: { capability_type: package-manager-available, name: brew | apt | dnf | pacman | winget, capability_scope: host } }
  - { capability: { capability_type: shell,          name: zsh | bash,               capability_scope: user } }
driver: { kind: observe, fn: { name: collect_host_facts } }
```

This collapses the legacy `requires:` field: `requires: macos` becomes
`consumes: [{ capability: platform/macos, strength: applicable }]`.

The two categories matter for the **resolver preference** (see § Provider
selection): `external: true` capabilities trigger "prefer non-external
when one exists." Host-observed state without `external` doesn't trigger
the preference, because the engine can in principle influence it via
another resource.

## Run plane

Two elements. Everything else is nested.

```yaml
run-session:
  id:           <string>
  mode:         update | verify | observe | snapshot
  dry_run:      <bool>
  host_context: { platform, arch, os_id, package_manager, fingerprint }
  selection:    { include?: [...], exclude?: [...], default?: enabled | disabled }

operation:                                      # one per (resource × axis × session)
  session:        <run-session-id>
  resource:       <resource-id>
  axis:           install | config | run | observe
  observed:       <evidence>
  desired:        <value>
  branch_taken:   absent | outdated | drifted | to_running | to_stopped | topology_diff | none
  outcome:        ok | changed | failed | warn | policy | skip | disabled | dry-run
  inhibitor?:     dry-run | policy | admin | user | no-install-fn | preflight-gate | drift | already-converged
  evidence:       { ... }
```

Every managed resource implicitly publishes a `managed-resource-status/<id>`
capability whose latest value is the most recent operation outcome.
Verification tests consume these.

### Outcome ↔ driver exit-code contract

Drivers communicate their outcome to the engine via process exit code:

| Exit code | Outcome | Meaning |
|---|---|---|
| 0 | `ok` or `changed` | converged successfully (changed flag separately reported) |
| 1 | `failed` | driver crashed or aborted before convergence |
| 2 | `warn` | converged but a diagnostic was emitted |
| 124 | `warn` | converged with policy warning (operator-suppressible) |
| 125 | `policy` | inhibited by operator policy (admin denied, gated, …) |

`skip`, `disabled`, and `dry-run` outcomes are set by the engine
*before* the driver runs (no exit code involved).

### Operation phases (per-operation lifecycle)

Each `operation` proceeds through these phases internally — distinct
from the session phases above. The session's `apply` phase (#6) fans
out into many operations, each going through their own micro-phases:

| Phase | What runs | Produces |
|---|---|---|
| `declare` | the resource shape is loaded and validated | `Operation` record with `desired` populated |
| `observe` | `driver.axes.<axis>.observe` (or `driver.observe`) | `observed` evidence |
| `diff` | engine compares `observed` vs `desired` | `branch_taken` |
| `apply` | `driver.axes.<axis>.apply.<branch>` | exit code → `outcome` |
| `verify` | re-run observe; confirm desired now matches observed | confirmation |
| `recover` | only if apply failed: `driver.axes.<axis>.recover` | recovery outcome |
| `record` | engine writes evidence to `RunArtifact` | persisted `Operation` |

`recover` and `record` always run for an operation that entered
`apply`, whether it succeeded or not.

### Phase ordering

A `run-session` proceeds through these phases in order. Each phase has
defined inputs and outputs; the next phase consumes the previous phase's
outputs.

| # | Phase | Input | Output | Stops the run if |
|---|---|---|---|---|
| 1 | **preflight** | declared `Resource`s providing `preflight/*` | for each, evaluate the resource's `driver.observe` | any blocking gate fails |
| 2 | **selection** | full resource set + `policy.selection_default` + operator overrides | the in-scope subset | — |
| 3 | **plan** | in-scope set | resolved capability graph (consumes ↔ provides matched, conditions evaluated, providers chosen by `priority`, `applicable`-skipped resources dropped, topological order computed) | a hard `consumes` cannot be satisfied |
| 4 | **observe** | planned resources × subscribed axes | one observation per (resource, axis) | — |
| 5 | **diff** | observed × `desired` per axis | `branch_taken` per (resource, axis) | — |
| 6 | **apply** | per (resource, axis) `branch_taken` | one `Operation` per (resource, axis), with `outcome` and optional `inhibitor`; runs `driver.hooks.pre` before and `driver.hooks.post` after each apply | a hard-failed apply blocks all dependents |
| 7 | **verify** | resources providing `verification/*` | verification results (consumed managed-resource-status capabilities are now populated) | — |
| 8 | **report** | all `Operation` outcomes + verification results | a `RunArtifact` (per `ArtifactContract`) | — |

In `mode: observe` the run stops after phase 5 (diff). In `mode: verify`
it skips phases 6 (apply) and runs only phase 7. In `mode: snapshot` it
calls `driver.snapshot.capture` (or `restore`) for resources that have
it, in lieu of the apply branches.

## Worked examples

### A bare package

```yaml
id: cli-jq
component: cli-tools
consumes:
  - capability: { capability_type: package-manager, name: brew,      capability_scope: host }
    strength: hard
    condition: { fact: pm, eq: brew }
    args: { ref: jq }
  - capability: { capability_type: package-manager, name: native-pm, capability_scope: host }
    strength: hard
    condition: { fact: pm, eq: native-pm }
    args: { ref: jq }
provides:
  - capability: { capability_type: binary, name: jq, capability_scope: host }
    when_axes: [install]
driver: { kind: pkg, refs: { brew: jq, native-pm: jq } }
```

### A custom multi-axis resource

```yaml
id: docker-desktop
component: docker
consumes:
  - capability: { capability_type: platform, name: macos, capability_scope: host }
    strength: applicable
  - capability: { capability_type: package-manager, name: brew-cask, capability_scope: host }
    strength: hard
    args: { ref: docker-desktop }
provides:
  - capability: { capability_type: app-bundle, name: docker-desktop, capability_scope: host }
    when_axes: [install]
  - capability: { capability_type: daemon, name: docker, capability_scope: host }
    when_axes: [install, run]
driver:
  kind: custom
  axes:
    install:
      desired: present
      observe: docker_desktop_observe
      apply:   { absent: _docker_desktop_install }
      evidence: { type: command-output, fields: { version: docker_version, install_source: docker_install_source_observe } }
    run:
      desired: running
      observe: docker_desktop_is_running
      apply:   { to_running: docker_start, to_stopped: docker_stop }
      evidence: { type: pid, fields: { pid: docker_desktop_pid } }
  hooks:
    post:
      - { notify_resource: docker-resources, signal: reload-config }
policy:
  admin: { fact: docker-first-install, eq: assisted }
  update: tool-driven
```

### A capability check

```yaml
id: docker-available
component: docker
consumes:
  - capability: { capability_type: daemon, name: docker, capability_scope: host }
    strength: hard
provides:
  - capability: { capability_type: capability, name: docker-available, capability_scope: host }
driver: { kind: observe, fn: { name: docker_daemon_is_running } }
```

### A preflight gate

```yaml
id: gate-supported-platform
component: <root>
provides:
  - capability: { capability_type: preflight, name: supported-platform, capability_scope: host }
driver:
  kind: observe
  predicate:
    any:
      - { fact: platform, eq: macos }
      - { fact: platform, eq: linux }
      - { fact: platform, eq: wsl2 }
```

### A verification test

```yaml
id: tic-system-composition-converged
component: system
consumes:
  - capability: { capability_type: managed-resource-status, name: system-composition, capability_scope: host }
provides:
  - capability: { capability_type: verification, name: system-composition-converged, capability_scope: host }
driver: { kind: observe, fn: { name: _tic_target_status_is, args: [system-composition, ok] } }
```

## What this model eliminates from the v3 spec

| v3 concept | Replaced by |
|---|---|
| 33 `element_type` values | 4 (Project, Component, Resource, RunSession+Operation) |
| 14 `relation_type` values | 2 (`consumes`, `provides`) |
| `resource_type`, `convergence_profile_derived`, `state_model_derived` | derived from `driver.kind` and axis subscription |
| `desired_state.{installation, runtime, health, admin, dependencies, value}` | `driver.axes.<axis>.desired` (custom only) |
| `OperationContract.{observe, converge, snapshot, recover, pre/post_converge}` | folded into `driver` |
| `requires:` (top-level) | `consumes(platform/*, applicable)` via `Host` |
| `depends_on` | derived view of hard `consumes` |
| `verification-test` element class | resource with `provides: verification/*` |
| `preflight-gate` element class | resource with `provides: preflight/*` |
| `governance-claim`, `output-contract`, `external-provider`, `compatibility-*` | dropped or reframed as `provides: <namespace>/*` |
| `verification-suite`, `verification-context` | use `component` for grouping |
| `layer` | not modeled (filesystem dirs only) |
| `provider_selection` block | conditional `consumes` + `priority` |
| `driver_type`, `driver.kind` (legacy 26 values), `backend_type`, `provider_type`, `provider_name` | one `driver.kind` from a registered catalog |
| `kind: capability`, `kind: predicate`, `kind: oracle` | unified as `kind: observe` |
| Six `desired_state` "axes" | three real state axes (`install`, `config`, `run`); `health`, `admin`, `dependencies` recharacterized |

## Concept count

| | v3 spec | This model |
|---|---:|---:|
| Element classes | 33 | 4 |
| Relation types | 14 | 2 |
| Top-level resource fields | 15+ | 4 (`consumes`, `provides`, `driver`, `policy`) |
| State axes | 6 (mixed with predicates) | 3 |
| Consume strengths | 2 | 3 |
| Driver kinds | ~26 + 22 tool_types | ~22 + `custom` |
| Policy enum/object types | mixed | uniform `Predicate | bool` |

## Open questions

These are intentionally not resolved by this document and are left for a
follow-up:

1. **Capability operation contracts.** Should each `capability_type`
   declare an operation signature (the args its consumers can pass via
   `consumes.args` and the operations its providers must implement)?
   Yes is cleaner; no is simpler. See "driver-as-capability-op"
   discussion in design notes.

The v3 → canonical-model migration mapping (formerly open question #2)
is now in [compat.md](compat.md), which lists every v3 element_type,
relation_type, and resource field with its disposition (`kept` /
`collapsed` / `removed`) and migration recipe.
