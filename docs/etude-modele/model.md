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
  capability_scope: host | user | component | container | service | external
  qualifiers?:      { version?, port?, scheme?, host?, path?, ... }
```

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
| `brew-analytics` | config | `desired` |
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
      desired:   <value> | { command: <fn> }
      observe:   <fn>
      apply:     { drifted?: <fn> }
      recover?:  <fn>
      evidence?: { type, fields }
    run?:
      desired:   running | stopped
      observe:   <fn>
      apply:     { to_running?: <fn>, to_stopped?: <fn>, topology_diff?: <fn> }
      recover?:  <fn>
      evidence?: { type, fields }
```

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

## Host (built-in)

The engine emits a virtual `host` resource that exposes machine facts as
capabilities. Other resources consume them like any other capability.

```yaml
id: host
component: <root>
provides:
  - { capability: { capability_type: platform,     name: macos | linux | wsl2,         capability_scope: host } }
  - { capability: { capability_type: arch,         name: arm64 | x86_64,               capability_scope: host } }
  - { capability: { capability_type: os_id,        name: <id>,                         capability_scope: host } }
  - { capability: { capability_type: os_version,   name: <semver>,                     capability_scope: host } }
  - { capability: { capability_type: package-manager-available, name: brew | apt | dnf | pacman | winget, capability_scope: host } }
  - { capability: { capability_type: init-system,  name: launchd | systemd | none,     capability_scope: host } }
  - { capability: { capability_type: shell,        name: zsh | bash,                   capability_scope: user } }
  - { capability: { capability_type: hardware-accel, name: mps | cuda,                 capability_scope: host } }
driver: { kind: observe, fn: { name: collect_host_facts } }
```

This collapses the legacy `requires:` field: `requires: macos` becomes
`consumes: [{ capability: platform/macos, strength: applicable }]`.

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
  outcome:        ok | changed | failed | skip | dry-run
  inhibitor?:     dry-run | policy | admin | user | no-install-fn | preflight-gate | drift | already-converged
  evidence:       { ... }
```

Every managed resource implicitly publishes a `managed-resource-status/<id>`
capability whose latest value is the most recent operation outcome.
Verification tests consume these.

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
2. **Where component-parameter substitution (`${var}`) is performed.**
   Pre-validation pass; details unspecified here.
3. **Operator-level provider preference** beyond per-consumer `priority`.
   May warrant a top-level `Preference` resource.
4. **Phase ordering inside a run-session** (preflight → plan → observe →
   apply → verify → report). Implicit in `mode` but not modeled.
5. **Migration / compatibility view** of v3 element_types and relation_types
   over this model — needed to keep existing tooling working.
