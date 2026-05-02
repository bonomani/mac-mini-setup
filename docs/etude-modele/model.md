# Model

> **Status**: candidate canonical model, derived from a deep review of the v3
> spec and the live `mac-mini-setup` YAML. Supersedes the 13 numbered specs
> (`01-elements.md` … `13-field-values-registry.md`) once accepted. The
> numbered docs remain as historical / detailed reference until that point.

## Core principle

Every node in the system — package, daemon, config setting, capability
check, verification test, preflight gate — is a **resource**. Resources
have the same shape. The only edges between resources are typed
**capabilities** that one resource `provides` and another `requires`.

Every action the engine performs on a resource is on one of three state
**axes**: `install`, `config`, `run`. A resource subscribes to a subset
(0–3) of axes. Subscription is implied by the resource's `driver.kind`;
for `kind: custom` it is declared explicitly.

```
Project
  └── Resource (n)                              ← single element class for everything
        ├── requires  → Capability ←──┐
        ├── provides  → Capability ──┘
        ├── driver  { kind, params }              ← kind also encodes the engine's invocation policy (sudo or not, where state lives)
        ├── tags?   [<string>, ...]              ← purely organizational labels (cli-tools, frontend)
        └── policy  { ... }
  Host        (a Resource like any other; provides platform/*, arch/*, os_id/*, ...)
  RunSession  (n)
        └── Operation (n)                       per (resource × axis × session)
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
host-published fact          ←  Host resource's provides (typically external: true)
   ↑↓
unmanaged resource           ←  has provides + observe; no axes
                                (may mark its provides external: true if
                                the engine truly can't influence them)
   ↑↓
managed resource             ←  has axes + driver; engine drives convergence
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
- Platform facts (`platform/macos`) sit at the top of the ladder —
  always host-published, never managed.

The model accepts movement along this ladder without breaking
consumers, because `requires(X)` only cares that `X` is published, not
which level published it.

```yaml
resource:
  id:           <string>                                # required, globally unique
  name:         <string>                                # required, human-readable
  display_name: <string>                                # optional
  tags?:        [<string>, ...]                         # purely organizational; see § Tags

  requires:
    - capability: <Capability>
      strength:   hard | soft | applicable              # required
      when?:      <lifecycle-phase>                     # when this dep must be satisfied (default: kind-derived)
      condition?: <Predicate>                           # only require when predicate holds
      priority?:  <int>                                 # tie-break when multiple match
      args?:      { ... }                               # passed to the provider's operations

  provides:
    - capability: <Capability>
      when?:      <lifecycle-phase>                     # when this capability is delivered (default: kind-derived)
      condition?: <Predicate>                           # only expose when predicate holds

  configures?: <resource-id> | [<resource-id>, ...]     # see § Configuration relation

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

### `requires.strength` values

| Value | Effect when capability is missing |
|---|---|
| `hard` | The resource cannot converge — block. |
| `soft` | The resource is ordered after the capability provider when present, but converges anyway when absent. |
| `applicable` | The resource is **skipped entirely** on hosts where this capability cannot be obtained. Used for platform gating. |

Multiple `applicable` entries on the same resource are OR'd: the resource
is applicable if any one of them is satisfiable.

### `requires.priority`

When multiple `provides` match a `requires` (and conditions all evaluate
true), the highest-priority candidate wins. Ties are broken by
declaration order. Default priority is 0.

### `requires.args`

Free-form parameters passed to the provider's operation handlers. The
schema is governed by the required capability's type (e.g.
`package-manager/*` accepts `{ ref }`).

### Lifecycle phase (`when:`)

Both `requires` and `provides` entries carry an optional `when:` value
that places the edge on the resource's lifecycle. Closed enum, 8 values:

| Value | Meaning |
|---|---|
| `always` | applies regardless of phase (cross-axis; observation-only) |
| `before_install` | dep needed before install can act |
| `after_install` | capability delivered when install converges (persistent) |
| `before_config` | dep needed before config can act |
| `after_config` | capability delivered when config converges (persistent) |
| `before_run` | dep needed before run can start (and remain running) |
| `after_run` | capability delivered when run completes once (persistent) |
| `running` | capability delivered while running (ephemeral — withdrawn when stopped) |

Two distinctions matter:

- **Pre vs post** — `before_X` is a precondition; `after_X` is a postcondition.
- **Persistent vs ephemeral provides** — `after_X` capabilities persist (binary stays installed); `running` capabilities disappear when the resource stops (daemon stops). Resolvers must re-check ephemeral providers and may cache persistent ones.

### Default `when:` per resource shape

To minimize noise on single-axis resources, `when:` has these defaults:

| Resource shape | Default `when:` (requires) | Default `when:` (provides) |
|---|---|---|
| install-only kind (e.g. `pkg`, `pip`) | `before_install` | `after_install` |
| config-only kind (e.g. `setting`, `git-global`) | `before_config` | `after_config` |
| run-only kind (e.g. `service`, `compose-apply`) | `before_run` | `running` |
| custom multi-axis (`kind: custom` with multiple `axes`) | required (no default) | required (no default) |
| observe-only (`kind: observe`) | `always` | `always` |

Most single-axis resources never write `when:` explicitly. Custom multi-axis resources must declare it.

### Phase ordering (resolver rule)

A `requires(X, when: Wr)` is satisfied by `provides(X, when: Wp)` only if `Wp ≤ Wr` in lifecycle order:

`always < before_install < after_install < before_config < after_config < before_run < after_run < running`

A `requires(X, when: before_run)` is satisfied by `provides(X, when: after_install)` (provider materialized first). A `requires(X, when: before_install)` of a provider whose `provides(X, when: running)` would mean "I need X before I install, but X only exists while X's owner is running" — flagged as a planning impossibility.

## Configuration

Configuration is a first-class structural concept, not "just another
axis with a desired value." A config-axis resource carries five
properties beyond what install/run resources have:

| # | Property | Where in the model |
|---|---|---|
| 1 | **Configures relation** — explicit edge: "I am the configuration of `<X>`" | `Resource.configures` |
| 2 | **Source cascade** — defaults → project-default → resource-override → operator-cli | `parameters[<name>].source` (project-level) |
| 3 | **Per-user vs system reach** | encoded by the providing resource's `driver.kind` + params (e.g. `pip` with `--user` writes to `~/.local`); when matching needs to distinguish, use a `qualifiers:` entry or a `condition:` |
| 4 | **Merge semantics** — replace / shallow-merge / deep-merge / append | implied by `driver.kind` (see catalog) |
| 5 | **Typed reload** — explicit signal to the configured target | `driver.hooks.post.notify_resource` |

### Configuration relation (`configures`)

`configures: <resource-id>` makes "this is the configuration of `<X>`"
an explicit edge, not an inference from `requires` + `notify_resource`.

```yaml
vscode-settings:
  configures: vscode                       # ← explicit
  driver:
    kind: json-merge
    path: ~/Library/Application Support/Code/User/settings.json
    format: json
    hooks:
      - { when: after_config, notify_resource: vscode, signal: reload-config }
```

A `configures` relation **implies** a hard `requires` of the target's
primary identity capability — no need to declare it separately.

The validator uses `configures` to detect:
- **Orphaned configs** — `configures` points at a non-existent resource
- **Misclassified configs** — a `kind: setting` resource with no `configures` is suspicious (probably should declare its target)
- **Broken notify chains** — `configures: vscode` but no `notify_resource: vscode` (or vice versa)

`configures` accepts a single `<resource-id>` or a list, and may carry
a `condition?: Predicate` for platform-conditional configuration.

### Configuration target — kind-specific params

Each catalogued config kind takes its own write-location params
directly on the `driver` block (no shared `target:` wrapper). The
fields differ per kind because the underlying tools differ:

```yaml
# kind: setting (macOS defaults / pmset)
driver: { kind: setting, backend: defaults, domain: com.apple.finder, key: AppleShowAllFiles, type: bool, desired: 'true' }

# kind: json-merge
driver: { kind: json-merge, path: ~/Library/.../settings.json, format: json, desired: { ... } }

# kind: git-global
driver: { kind: git-global, key: user.email, desired: 'a@b' }

# kind: path-export
driver: { kind: path-export, rc_file: .zprofile, desired: [~/bin] }
```

See the §Driver kinds catalog for the exact param shape per config
kind. Cross-resource conflict detection (e.g. two resources writing
the same `~/.gitconfig`) is left to validators that understand each
kind's params — there's no shared `target:` block to compare across.

> Earlier drafts of this model had a uniform `driver.target: { ... }`
> wrapper. It was removed because no real YAML used a target block;
> each kind already had its own write-location params, and the
> validator's "target conflict" rule turned out to be speculative.
> Per-kind params are simpler and match observed usage.

### Merge semantics (per kind, not per resource)

Each catalogued config kind has a fixed merge semantic. Per-resource
override is **not** supported — when the semantic differs, use a
different kind (or `kind: custom`).

See § Driver kinds for the per-kind merge column.

### Validator rules summary

The properties above enable cross-cutting checks:

1. **Orphaned `configures`** — points at a missing resource
2. **Configurer/notify mismatch** — `configures: X` requires the resource to have a `hooks` entry with `notify_resource: X` (and vice versa)
3. **Source provenance** — every applied config value records its `config_source` for auditability
4. **Per-kind path conflict** (kind-aware) — when two resources of the same kind write the same location-params (e.g. two `kind: setting` writes to the same `(backend, domain, key)`), reject. Per-kind because there's no longer a shared `target:` shape to compare across kinds.

These rules belong in `lib-quality`; this section names them so the
spec and validator agree on what's enforced.

## Capability

The only currency between resources.

```yaml
capability:
  type:  <namespace>                         # binary, package-manager, daemon, http-endpoint, ...
  name?:            <string>                            # specific identifier within the type
  qualifiers?:      { version?, port?, scheme?, hostname?, path?, ... }
  external?:        bool                                # true = host-published / OS-shipped (not engine-managed)
```

`external: true` marks a capability the engine observes but cannot
control — typically host facts (`platform/macos`) or OS-shipped
binaries the engine doesn't own. See § Provider selection (rule 4)
for how the resolver deprioritizes external candidates when an
engine-managed alternative exists.

> **Removed in v4**: the legacy `scope` field on capabilities. It was
> trying to do three different jobs (aggregator boundary, host vs
> guest, per-user vs system) all welded into one enum, and it was
> redundant with mechanisms that already exist:
>
> - Aggregator/host/guest boundaries → providers across substrate
>   boundaries declare `external: true`; consumers don't filter on
>   scope at all.
> - Per-user vs system → encoded by the providing resource's driver
>   kind (e.g. `pip` with `--user` writes to `~/.local`; `pip` system
>   writes to `/usr/local`). When matching genuinely needs to
>   distinguish, use a qualifier (`qualifiers: { install_path: ... }`)
>   or a `condition:` on the require.
>
> If a real case appears where neither `external` nor qualifiers are
> sufficient, we'll add a narrower mechanism rather than re-introducing
> a multi-purpose enum.

### Capability families and their typical lifecycle phase

Each `type` (within `capability` block) namespace implies the lifecycle phase at which a
provider's capability becomes available. A `provides` whose `when:`
doesn't match its capability family is a modeling error.

| Capability namespace | Required `when:` |
|---|---|
| `binary/*`, `app-bundle/*`, `package-manager/*`, `python-package/*`, `node-package/*`, `app-extension/*`, `ai-model/*` | `after_install` (persistent) |
| `config-file/*`, `os-setting/*` | `after_config` (persistent) |
| `daemon/*`, `socket/*`, `http-endpoint/*`, `compose-stack/*`, `docker-service/*` | `running` (ephemeral — withdrawn when stopped) |
| `capability/*`, `preflight/*`, `verification/*` | `always` (observation-only — declared by the user) |
| `managed-resource-status/*` | `always` — **auto-emitted by the engine for every managed resource; do not declare manually**. Verification tests `require` these to read a resource's most recent Operation outcome. |
| `platform/*`, `arch/*`, `os_id/*`, `os_version/*`, `init-system/*`, `hardware-accel/*` | `always` + `external: true` (immutable host facts — engine cannot ever influence) |
| `package-manager-available/*`, `shell/*`, `network-connectivity/*` | `always` (host-observed state — may flip as a side-effect of other resources converging; do **not** set `external`) |

### Matching rule (requires ↔ provides)

`requires(C_req, when: Wr)` matches `provides(C_off, when: Wp)` if and only if:

1. `type` (within `capability` block) matches exactly.
2. `name` matches exactly (or both omit it).
3. For each qualifier `(k, v_req)` in `C_req.qualifiers`:
   - if `v_req` is scalar: `C_off.qualifiers[k] == v_req`
   - if `v_req` is `{ op, value }`: `C_off.qualifiers[k]` satisfies the
     comparison (semver or numeric)
   - if `v_req` is `{ in: [...] }`: `C_off.qualifiers[k]` is in the list
   - if `k` is absent from `C_off.qualifiers`: **no match**
4. Qualifiers present in `C_off` but not mentioned in `C_req` are ignored.
5. **Phase ordering**: `Wp ≤ Wr` in the lifecycle order (provider's
   `when:` is at or before requirer's `when:`). A `requires(X, when: before_run)`
   matches `provides(X, when: after_install)` (provider materialized first).
   A `requires(X, when: before_install)` of a `provides(X, when: running)`
   would mean "I need X before I install, but X only exists while X's owner
   is running" — flagged as a planning impossibility.

### Provider selection (when multiple providers match)

When a `requires(X)` matches multiple `provides(X)`, the planner picks
exactly one provider per resolution rule, in order:

1. **Filter by condition.** Drop any `requires` entry whose
   `condition` evaluates false against the live `HostContext`. Drop
   any `provides` whose `condition` evaluates false.
2. **Filter by qualifier match** (the matching rule above).
3. **Filter by phase ordering** (rule 6 in matching).
4. **Prefer non-external candidates** when at least one non-external
   candidate is viable after the previous filters. External providers
   (`capability.external: true`) are deprioritized because they can
   disappear without engine-visible cause and the engine can't
   repair them. **If all viable candidates are external**, this step
   is a no-op and the next rule applies — so `requires(platform/macos)`
   matched only by the Host (`external: true`) still resolves
   correctly.
5. **Pick highest `priority`** among surviving candidates. Default
   priority is 0.
6. **Tie-break** by `requires` declaration order (first wins).

**Operator-level preference** ("always prefer brew over native-pm on
this host") is expressed using the existing primitives — no new element
class:

- A typed `parameter` is declared at the project level (e.g. `pm: { type: enum,
  options: [brew, native-pm], default: brew, source: operator-cli }`).
- Each requirer carries a `condition: { fact: pm, eq: brew }` on its
  `requires` entry.
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
project parameters (for input) or capabilities (for the resolved
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
all its declared capabilities (whose `when:` phase has been reached).

## Driver kinds

Each registered kind tells the engine which axes a resource subscribes
to and how to dispatch the per-axis operations. `custom` is the escape
hatch.

> **`kind` vs `type` — naming convention**: the model uses two
> discriminator words that mean different things:
>
> - **`kind`** = behavioral discriminator. What does this thing DO?
>   Used for `driver.kind` (= which driver implementation acts on
>   the resource: `pkg` installs packages, `observe` checks state,
>   `service` manages a daemon). Familiar from Kubernetes
>   (`apiVersion` + `kind`).
> - **`type`** = data-shape discriminator. What NAMESPACE does this
>   value belong to? Used for `capability.type` (= which capability
>   namespace: `binary`, `daemon`, `http-endpoint`), `evidence.type`,
>   `parameter.type`.
>
> Both are deliberate. They answer different questions and avoid
> collision with JSON-Schema's `type:` keyword (which means data
> type, not concept type).

| Kind | Implied axis | Implied merge (config kinds only) | Parameters |
|---|---|---|---|
| `observe` | none | — | `predicate?: <Predicate>` OR `fn?: { name, args? }` |
| `pkg` | install | — | `refs: { brew?, native-pm?, brew-cask?, ... }`, `bin?` |
| `pip` | install | — | `isolation`, `probe_pkg`, `install_packages` |
| `npm` | install | — | `package`, `version?` |
| `git-repo` | install | — | `url`, `dest`, `ref?` |
| `pyenv` | install | — | `version` |
| `nvm` | install | — | `version` |
| `nvm-version` | install | — | `version` (sets active Node version via nvm) |
| `pyenv-brew` | install | — | (installs pyenv via brew; specialty wrapper around `pkg`) |
| `pip-bootstrap` | install | — | (bootstraps pip itself; no params) |
| `vscode` | install | — | `extension_id` |
| `ollama` | install | — | `model` |
| `script-installer` | install | — | `url`, `verify_cmd?` |
| `app-bundle` | install | — | `bundle_path`, `source` |
| `home-artifact` | install | — | `dest`, `source` |
| `brew-unlink` | install | — | `formula` (unlinks a brew formula to free a name) |
| `build-deps` | install | — | `set: brew\|apt\|dnf` (installs platform-specific build essentials) |
| `corepack` | install | — | `enabled` (enables Node corepack) |
| `setting` | config | **replace** | `backend`, `domain?`, `key`, `type?`, `desired` (macOS defaults / pmset) |
| `git-global` | config | **shallow-merge** | `key`, `desired` (single git config key) |
| `path-export` | config | **append** | `rc_file`, `desired: [<dir>, ...]` (PATH additions in shell rc) |
| `zsh-config` | config | **shallow-merge** | `key`, `config_file`, `desired` (single .zshrc variable) |
| `json-merge` | config | **deep-merge** | `path`, `format: json`, `desired: { ...keys-object }` (e.g. VSCode settings) |
| `compose-file` | config | **replace** | `path`, `desired` (whole-file content) |
| `brew-analytics` | config | **replace** | `desired` (single on/off value) |
| `swupdate-schedule` | config | **replace** | `desired: { enabled, frequency }` |
| `softwareupdate-schedule` | config | **replace** | `desired: { enabled, frequency }` (macOS-specific alias of `swupdate-schedule`) |
| `service` | run | — | `unit`, `manager: launchd\|systemd\|brew-services` |
| `compose-apply` | run | — | `compose_file`, `services?` |
| `docker-compose-service` | run | — | `service_name` |
| `custom-daemon` | run | — | `pid_fn`, `start_fn`, `stop_fn` (ad-hoc daemons) |
| `custom` | declared | declared per-resource | `axes: { install?, config?, run? }` |

> **Removed in v4**: `kind: aggregator`. Pure organizational grouping
> (cli-tools, frontend, ai-stack) is handled by the `tags:` field on
> regular resources — no Resource entity needed for the group itself.
> Things that look like containers and have real state (host, container,
> VM) stay as regular Resources with their own driver kinds. See § Tags.

#### Uniform `desired:` slot for all config kinds

Every catalogued config kind uses **`desired:`** for the value to write
(EXT-B polymorphism applies). Accepts:

```yaml
desired: <literal>                                  # static value, the typical case
# OR
desired: { command: <fn-name>, args?: [<arg>, ...] }  # value computed at runtime by calling <fn>
```

Examples:
```yaml
# Literal
finder-show-hidden=1:
  driver: { kind: setting, backend: defaults, domain: com.apple.finder, key: AppleShowAllFiles, type: bool, desired: 'true' }

# Computed (the docker-resources case)
docker-resources:
  driver: { kind: custom, axes: { config: { desired: { command: docker_resources_desired }, ... } } }

# Parameter substitution (resolved before the engine sees the value)
brew-analytics=off:
  driver: { kind: brew-analytics, desired: ${analytics_desired} }
```

The kind-specific params (`target.path`, `target.key`, etc.) describe
**where** to write; `desired` describes **what** to write. Same field
name across all config kinds, polymorphic by definition.

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
      target?:   { ... }                                # see § Configuration target
      recover?:  <fn>
      evidence?: { type, fields }
    run?:
      desired:   running | stopped
      observe:   <fn>
      apply:     { to_running?: <fn>, to_stopped?: <fn>, topology_diff?: <fn> }
      recover?:  <fn>
      evidence?: { type, fields }
```

For `kind: custom` config-axis blocks, the writer's merge semantic is
implicit in the `apply.drifted` function — the engine doesn't enforce a
specific behavior. Use a catalogued kind (e.g. `json-merge`,
`path-export`) when you want the engine to know and enforce the
semantic. See § Configuration for the full structural model.

#### Evidence types

`evidence.type` is an open enum naming the **shape** of the fields the
observe function returns. Known values (extensible):

| `type:` | Typical fields | Used by |
|---|---|---|
| `binary-version` | `version`, `path` | `kind: pkg` install observation |
| `http-response` | `status_code`, `body?`, `headers?` | http endpoint probes |
| `command-output` | `stdout`, `exit_code`, `stderr?` | generic observation via shell command |
| `file-presence` | `path`, `exists`, `size?`, `hash?` | config writes, file-creation checks |
| `pid` | `pid`, `started_at?` | running daemon observation |
| `process-pattern` | `pattern`, `count`, `pids?` | process-list matching |
| `daemon-status` | `status`, `pid?`, `restart_count?` | service-managed daemons |
| `package-installed` | `installed: bool`, `version?`, `source?` | package-manager probes |
| `config-value` | `value`, `source?`, `last_modified?` | config drift detection |

Custom kinds may use additional `type:` values — the engine treats
unknown types as opaque (passes the `fields` object to consumers
verbatim). Catalogued kinds emit one of the known types from the table.

### Hooks (any kind)

```yaml
driver:
  hooks?:
    - when: <lifecycle-phase>          # before_install | after_install | before_config | after_config | before_run | after_run | running
      # one of:
      fn?:    <fn-name>
      args?:  [<arg>, ...]
      # OR
      notify_resource?: <id>
      signal?:          reload-config | restart | daemon-reload | sighup
      # OR
      killall?: [<process>, ...]       # OS process names to kill (auto-restart picks up new state)
```

Hooks use the same `when:` lifecycle phase as `requires` and `provides`,
so the same vocabulary covers all three model concepts. The
**before/after** distinction (formerly `pre`/`post` arrays) is now
implicit in the phase value (`before_X` = pre; `after_X` and `running`
= post).

`always` is **not valid** for hooks — hooks are point-events, not
applies-everywhere conditions.

**Action variants** — closed enum of 3 mutually-exclusive shapes (each
hook entry picks exactly one):

| Variant | Discriminator key | Shape | Effect |
|---|---|---|---|
| `fn` | `fn:` (and optional `args:`) | `{ fn: <fn-name>, args?: [<arg>, ...] }` | invoke a function with optional args |
| `notify` | `notify_resource:` (and required `signal:`) | `{ notify_resource: <id>, signal: reload-config\|restart\|daemon-reload\|sighup }` | queue a reload-style signal to another resource (delivered after this operation's `record` phase) |
| `killall` | `killall:` | `{ killall: [<process-name>, ...] }` | invoke `killall` on named OS processes (they auto-restart via launchd/systemd, picking up new state) |

The variant is identified by which discriminator key is present.
Declaring two discriminator keys in one entry (e.g. both `fn:` and
`killall:`) is a validation error.

#### Firing semantics per `driver.kind`

The kind owns when its hooks fire:

| Kind | Hook firing |
|---|---|
| `pkg`, `pip`, `npm`, `git-repo`, `vscode`, `ollama`, `script-installer`, `app-bundle`, `home-artifact`, `pyenv`, `nvm`, `nvm-version`, `pyenv-brew`, `pip-bootstrap`, `brew-unlink`, `build-deps`, `corepack` | per install-axis apply (when entry's `when:` matches `before_install` or `after_install`) |
| `setting`, `git-global`, `path-export`, `compose-file`, `swupdate-schedule`, `softwareupdate-schedule`, `zsh-config`, `json-merge`, `brew-analytics` | per config-axis apply |
| `service`, `compose-apply`, `docker-compose-service`, `custom-daemon` | per run-axis apply (or `running` for entry into desired state) |
| `custom` | per declared axis-apply (entries scoped by `when:`) |
| `observe` | hooks not meaningful (no apply phase to wrap); declaring them is invalid |

### Snapshot (rare — VM-style resources)

```yaml
driver:
  snapshot?: { capture: <fn>, restore: <fn> }
```

## Predicate

The universal condition language. Used in `requires.condition`,
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

## Tags

Tags are **purely organizational labels** on resources. They have no
semantics for the engine: they don't participate in capability matching,
they don't imply ordering, they don't propagate state. Their only jobs
are CLI selection (`--tag cli-tools`) and status display
(`is everything tagged "frontend" converged?`).

```yaml
resource:
  id: cli-jq
  tags: [cli-tools]
  driver: { kind: pkg, refs: { brew: jq } }

resource:
  id: cli-yq
  tags: [cli-tools, ai-stack]                  # a resource can carry multiple tags
  driver: { kind: pkg, refs: { brew: yq } }
```

`cli-tools` is a **string** — there is no Resource named `cli-tools`,
no manifest entry, no driver. The query "is `cli-tools` converged?" is
computed by the engine from the resources tagged `cli-tools`.

### What replaced the v3 Component concept

| v3 mechanism | v4 replacement |
|---|---|
| `component: cli-tools` field on members | `tags: [cli-tools]` field on members |
| `Component` element class | (removed — not a Resource at all) |
| `kind: aggregator` Resource | (removed — see § Driver kinds) |
| Component `parameters` block (defaults inherited by members) | Project-level parameters file (see § Parameter substitution) |
| Component `resource_templates` (parametric resource generation) | Top-level resource generators in the project file; reference parameters by name |
| Component `restart_processes` hook | Per-resource `hooks:` on the resource that owns the side-effect, OR a regular Resource (`kind: custom`) that performs the killall |
| Component `parent: <component-id>` | Tags compose freely; "nested" is just multiple tags |

### Aggregator-style queries (status of a tag)

The engine answers tag-status queries directly from the resource set
without needing a stand-in Resource:

```
is_converged(tag T, phase P) :=
   ∀ resource R where T ∈ R.tags : R has reached phase P
```

CLI consumers see this as `--show-tag-status cli-tools` or
`--target-tag cli-tools` (selection). No additional declaration is
needed in any manifest.

### Parameter substitution

`${param-name}` references in any string-typed field expand at **load
time**, in a single pre-validation pass. By the time a resource reaches
the planner, no `${...}` tokens remain. There is no late binding.

Parameters are declared at the **project level** (a top-level
`parameters:` file or block), not on individual resources or tags:

```yaml
parameters:
  brew_tap:    { type: string, default: homebrew/core }
  python_ver:  { type: semver, default: 3.12 }
  ai_models:   { type: list,   default: [llama3, mistral] }
```

**Resolution order** (highest precedence wins):

| Source | Where it comes from |
|---|---|
| `operator-cli` | `--set <name>=<value>` flag or `UCC_OVERRIDE__<NAME>` env var |
| `resource-override` | `defaults/resource-overrides.yaml` |
| `project-default` | the project's `parameters[<name>].default`, possibly platform-filtered |
| `built-in default` | `defaults/preferences.yaml` |

**Errors at validation time** (the resource is rejected):

- `${var}` references a name not declared in the project parameters
- the resolved value's type does not match `parameters[<name>].type`
- the resolved value is not in `parameters[<name>].options` (if `options` is set)

**Determinism**: substitution depends only on host facts and operator
input known before validation. Once a `RunSession` starts, every
resource has a frozen, fully-substituted shape.

## The substrate stack: hosts and the substrate they stand on

Every place that runs userland code — a Mac install, a Linux VM, an
Ubuntu container — is modeled as a **host Resource**. There is no
special "host kind"; a host is just a regular Resource whose `provides:`
includes platform/os facts and whose `requires:` carries one
substrate-edge capability. The only thing that distinguishes them is
**what kind of substrate they stand on**.

There are exactly **three substrate flavors**:

| Substrate | Capability the host requires | Provided by | Own kernel? | Own hardware? |
|---|---|---|---|---|
| Bare-metal | `machine-substrate` | a `hardware/<id>` Resource (`kind: observe`) | yes | yes (real) |
| Virtualized | `machine-substrate` | a `hardware/<vm-id>` Resource (`kind: custom`, configurable) which itself requires a `virtualization-platform/<name>` | yes | yes (virtual, configurable) |
| Containerized | `container-runtime/<name>` | a Resource that runs the runtime daemon (e.g. docker-desktop) | **no** (shared with parent) | no |

That's the whole taxonomy. A container is a host with a different
substrate edge — not a separate concept.

### Hardware (only present when the host owns its kernel)

Hardware is a separate Resource ONLY for hosts with their own kernel.
Containers skip the hardware layer entirely.

| Variant | Requires | Provides | Has config axis? |
|---|---|---|---|
| Bare-metal | nothing (bottom of the world) | `machine-substrate` + facts (cpu-cores, ram-bytes, hardware-accel, …) | no |
| Virtual | a `virtualization-platform/<name>` capability (when running) | `machine-substrate` + facts (configurable cpu/ram/disk, `virtualization: <hypervisor>`) | yes |

```yaml
# Bare-metal hardware
id: hardware/mac-mini-m2
driver: { kind: observe, fn: { name: probe_hardware } }
provides:
  - { capability: { type: machine-substrate, external: true } }
  - { capability: { type: cpu-cores,      name: count, qualifiers: { value: 10 },          external: true } }
  - { capability: { type: ram-bytes,      name: total, qualifiers: { value: 68719476736 }, external: true } }
  - { capability: { type: hardware-accel, name: mps,                                       external: true } }

# Virtual hardware (the Linux VM Docker Desktop conjures)
id: hardware/docker-vm
tags: [docker-desktop]                                 # organizational only — see § Tags
driver:
  kind: custom
  axes:
    config:
      desired: { cpu_cores: 4, ram_bytes: 17179869184, disk_bytes: 214748364800 }
      observe: docker_vm_resources_observe
      apply:   { drifted: docker_vm_resources_apply }
requires:
  - { capability: virtualization-platform/docker, strength: hard, when: running }   # the VM only exists when the platform is live
provides:
  - { capability: { type: machine-substrate } }
  - { capability: { type: cpu-cores, name: count, qualifiers: { value: 4 } } }
```

The legacy `docker-resources` resource IS exactly the virtual-hardware
pattern.

### Host (a regular Resource with the substrate-edge requires)

```yaml
id: host                                               # convention: top-level OS
driver: { kind: observe, fn: { name: probe_host_facts } }
requires:
  - { capability: machine-substrate, strength: hard }  # picks bare-metal OR virtual hardware
provides:
  - { capability: { type: platform,    name: macos | linux | wsl2,    external: true } }
  - { capability: { type: os_id,       name: <id>,                     external: true } }
  - { capability: { type: os_version,  name: <semver>,                 external: true } }
  - { capability: { type: init-system, name: launchd | systemd | none, external: true } }
  - { capability: { type: shell,       name: zsh | bash } }
  - { capability: { type: package-manager-available, name: brew | apt | dnf | pacman | winget } }
```

A **container host** swaps the substrate requirement:

```yaml
id: host/ollama-container
tags: [ai-stack]
driver:
  kind: docker-compose-service       # the actual driver that creates and runs the container
  service_name: ollama
requires:
  - { capability: container-runtime/docker, strength: hard, when: running }   # the substrate (no machine-substrate — kernel is shared)
provides:
  - { capability: { type: platform, name: linux } }
  - { capability: { type: ollama-running }, when: running }
```

Same Resource shape. Just a different substrate edge and a different
driver kind.

### Recursion: VM nesting and container nesting

A managed Resource that runs containers or VMs (Docker Desktop, VMware,
Parallels, podman, …) provides one or both of:

- `virtualization-platform/<name>` — lets a `hardware/<vm-id>` Resource
  exist, kicking off a nested (hardware → host) stack
- `container-runtime/<name>` — lets a `host/<container-id>` Resource
  exist directly (no nested hardware, kernel is shared)

```
hardware/mac-mini-m2                              ← bare-metal — provides machine-substrate
   ↑ machine-substrate
host  (the macOS Resource, kernel owner)
   docker-desktop                                 ← when running, provides BOTH
        ├─ virtualization-platform/docker
        └─ container-runtime/docker
              ↑ virtualization-platform                           ↑ container-runtime
   hardware/docker-vm   (VM nesting:                  host/ollama-container  (container nesting:
       requires virt-platform; own kernel)               requires runtime; no hardware, shared kernel)
       ↑ machine-substrate                               (and other container hosts...)
   host/docker-linux  (Linux guest)
```

Tags overlay this structure for organization. The macOS Resources
might all carry `tags: [host]`; the AI containers might carry
`tags: [ai-stack]`. Tags don't change the capability graph above —
they're just labels.

Two nesting shapes from the same building block:

| Nesting | Substrate edge | Adds a `hardware/...`? |
|---|---|---|
| **Virtualization** | `virtualization-platform/<name>` | yes (`hardware/<vm-id>`) |
| **Containerization** | `container-runtime/<name>` | no |

Containers ARE hosts (full userland installs) — they just don't own
their kernel, so they skip the hardware layer.

### Probing — per-resource, with substrate-bound visibility

To populate the runtime fact set, the engine **observes each Resource
independently**:

```
observe(resource):
  facts = run driver's observe fn (if any)
  return facts as the resource's provides
```

There is no recursive aggregation step. Each Resource produces its own
facts; the capability graph composes them via `requires` / `provides`
edges.

But probes are **partially blind** — substrate boundaries (kernel
boundary for VMs, namespace boundary for containers) restrict what
any single Resource can observe:

| Direction | Visibility |
|---|---|
| Parent host → its direct members (services, daemons, containers it lists) | usually yes (list, status) |
| Parent host → guest host across a `virtualization-platform` edge (VM internals) | typically no (opaque; need a probe inside the guest) |
| Parent host → guest host across a `container-runtime` edge (container internals) | partial (the runtime API exposes some state; the guest's filesystem/processes need an exec) |
| Guest host → parent host above it | partial (DMI hints for VMs; cgroup/`/.dockerenv` hints for containers; can't see siblings) |
| Sibling guests (VM↔VM, container↔container) | none (isolation is the point) |

Probes that can't determine a value report it absent rather than
guessing. The engine treats absence as "not provided." A capability
declared in the manifest but not observable is simply not delivered —
consumers of it won't be satisfied.

### `external: true` and the resolver

The two categories of hardware's and host's own provides matter for the
**resolver preference** (see § Provider selection): `external: true`
capabilities trigger "prefer non-external when one exists." Observed
state without `external` doesn't trigger the preference, because the
engine can in principle influence it via another resource.

Each Resource declares `external` on its own provides; there is no
inherited aggregation.

This collapses the legacy `requires:` field: `requires: macos` becomes
`requires: [{ capability: platform/macos, strength: applicable }]`.

## Run plane

Two elements. Everything else is nested.

```yaml
run-session:
  id:           <string>
  mode:         update | verify | observe | snapshot
  dry_run:      <bool>
  host_context: { platform, arch, os_id, package_manager, fingerprint }
  selection:    { include?: [...], exclude?: [...], default?: true | false }

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
*before* the driver runs (no exit code involved):

| Outcome | Set during phase | When |
|---|---|---|
| `disabled` | #2 (selection) | `policy.selection_default` evaluates to `false`, OR the operator explicitly excluded the resource (e.g. `--exclude X`). The Operation record is created with this outcome and the apply phase is skipped. |
| `skip` | #6 (apply) | The Operation entered apply but: (a) a hard `requires` is unsatisfied, OR (b) `branch_taken` is `none` (no diff between observed and desired). Distinguished from `disabled` because the resource WAS in scope but conditions prevented action. |
| `dry-run` | #6 (apply) | `run-session.dry_run: true` and the operation would otherwise have entered apply. The driver isn't invoked; outcome is recorded as if the apply had been a no-op. |

The distinction matters for run reports: a user can act on `disabled`
(re-enable in policy), on `skip` (fix the missing dependency), and on
`dry-run` (re-run without the dry-run flag).

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
| `confirm` | re-run observe; check desired now matches observed | confirmation |
| `recover` | only if apply failed: `driver.axes.<axis>.recover` | recovery outcome |
| `record` | engine writes evidence to `RunArtifact` | persisted `Operation` |

`recover` and `record` always run for an operation that entered
`apply`, whether it succeeded or not.

> **`confirm` vs `verify` — disambiguation**: the operation's per-Operation
> `confirm` phase is the engine's **self-check** after apply (re-runs
> observe to make sure the action committed). The session-level
> **`verify` phase** (#7 below) is different: it runs `verification-test`
> resources — independent post-convergence proof tests that consume
> `managed-resource-status/*` capabilities and provide `verification/*`
> capabilities. They were both called "verify" in earlier drafts; the
> per-operation phase is now `confirm` to keep them distinct.

#### Binding to session phases

The operation phases `observe`, `diff`, `apply`, and `verify` share names
with session phases (#4, #5, #6, #7 below) — **deliberately**. Each
session phase **is** the column-major synchronization barrier where every
in-scope operation executes its corresponding phase:

| Session phase | What it does at the operation level |
|---|---|
| session `observe` (#4) | every operation runs its `observe` |
| session `diff` (#5) | every operation runs its `diff` |
| session `apply` (#6) | every operation runs `apply` (then `confirm`, `recover` if needed, `record`) — in topological order respecting `requires`/`provides` |
| session `verify` (#7) | every verification-test resource runs (a separate concept; see disambiguation note above) |

The session waits for all operations to complete phase X before any
begins phase X+1. Operation phases that have **no session-phase peer**
execute INSIDE their owning session phase:

- `declare` runs during session `plan` (#3) — the planner instantiates an `Operation` record per (resource, axis) pair from the resource shape.
- `confirm` runs at the end of each operation's apply, inside session `apply` (#6).
- `recover` runs only on apply failure, inside session `apply` (#6).
- `record` runs at the end of session `apply` (#6); finalises the `Operation` for the report phase.

The shared names (observe / diff / apply) reflect that each session
phase **is** the column-major barrier for the corresponding operation
phase across all in-scope (resource, axis) pairs. Same concept at two
scopes; not a name collision.

### Phase ordering

A `run-session` proceeds through these phases in order. Each phase has
defined inputs and outputs; the next phase consumes the previous phase's
outputs.

| # | Phase | Input | Output | Stops the run if |
|---|---|---|---|---|
| 1 | **preflight** | declared `Resource`s providing `preflight/*` | for each, evaluate the resource's `driver.observe` | any blocking gate fails |
| 2 | **selection** | full resource set + `policy.selection_default` + `RunSession.selection.{include, exclude, default}` (see Selection cascade below) | the in-scope subset | — |
| 3 | **plan** | in-scope set | resolved capability graph (requires ↔ provides matched, conditions evaluated, providers chosen by `priority`, `applicable`-skipped resources dropped, topological order computed) | a hard `requires` cannot be satisfied |
| 4 | **observe** | planned resources × subscribed axes | one observation per (resource, axis) | — |
| 5 | **diff** | observed × `desired` per axis | `branch_taken` per (resource, axis) | — |
| 6 | **apply** | per (resource, axis) `branch_taken` | one `Operation` per (resource, axis), with `outcome` and optional `inhibitor`; runs `driver.hooks.pre` before and `driver.hooks.post` after each apply | a hard-failed apply blocks all dependents |
| 7 | **verify** | resources providing `verification/*` | verification results (consumed managed-resource-status capabilities are now populated) | — |
| 8 | **report** | all `Operation` outcomes + verification results | a `RunArtifact` (per `ArtifactContract`) | — |

In `mode: observe` the run stops after phase 5 (diff). In `mode: verify`
it skips phases 6 (apply) and runs only phase 7. In `mode: snapshot` it
calls `driver.snapshot.capture` (or `restore`) for resources that have
it, in lieu of the apply branches.

#### Selection cascade (phase #2)

Two fields contribute, in order. They serve different roles:

- `RunSession.selection.{include, exclude, default}` — operator-level filter
  for this run. `default: true` means "include unless excluded;"
  `default: false` means "exclude unless explicitly included." A bool, not
  a Predicate, because it's a global mode switch — not a per-resource
  decision.
- `policy.selection_default` (per-resource) — the resource's intrinsic
  default. `Predicate | true | false`. Predicate is evaluated against
  HostContext to compute a per-resource boolean.

For each resource R, compute scope as:

1. If R is in `RunSession.selection.exclude` → out
2. Else if R is in `RunSession.selection.include` → in
3. Else if `RunSession.selection.default == false` → out
4. Else evaluate R's `policy.selection_default` (defaults to `true` if absent)

The two fields don't share a type because they answer different questions:
the run-session field is "how should I interpret the include/exclude lists
this run?"; the per-resource field is "what's this resource's intrinsic
default scope?"

## Worked examples

### A bare package

```yaml
id: cli-jq
tags: [cli-tools]
requires:
  - capability: { type: package-manager, name: brew }
    strength: hard
    condition: { fact: pm, eq: brew }
    args: { ref: jq }
    # when: defaults to before_install (kind=pkg is install-only)
  - capability: { type: package-manager, name: native-pm }
    strength: hard
    condition: { fact: pm, eq: native-pm }
    args: { ref: jq }
provides:
  - capability: { type: binary, name: jq }
    # when: defaults to after_install
driver: { kind: pkg, refs: { brew: jq, native-pm: jq } }
```

### A custom multi-axis resource

```yaml
id: docker-desktop
tags: [docker]
requires:
  - capability: { type: platform, name: macos, external: true }
    strength: applicable
    when: always
  - capability: { type: package-manager, name: brew-cask }
    strength: hard
    args: { ref: docker-desktop }
    when: before_install
provides:
  - capability: { type: app-bundle, name: docker-desktop }
    when: after_install                          # persistent
  - capability: { type: daemon, name: docker }
    when: running                                # ephemeral — withdrawn when stopped
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
    - { when: after_install, notify_resource: docker-resources, signal: reload-config }
policy:
  admin: { fact: docker-first-install, eq: assisted }
  update: tool-driven
```

### A capability check

```yaml
id: docker-available
tags: [docker]
requires:
  - capability: { type: daemon, name: docker }
    strength: hard
    # when: defaults to always (kind=observe)
provides:
  - capability: { type: capability, name: docker-available }
    # when: defaults to always
driver: { kind: observe, fn: { name: docker_daemon_is_running } }
```

### A preflight gate

```yaml
id: gate-supported-platform
provides:
  - capability: { type: preflight, name: supported-platform }
    # when: defaults to always
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
tags: [system]
requires:
  - capability: { type: managed-resource-status, name: system-composition }
provides:
  - capability: { type: verification, name: system-composition-converged }
driver: { kind: observe, fn: { name: _tic_target_status_is, args: [system-composition, ok] } }
```

## Declaration modes

For every field in the schema, three states are possible:

- **Implicit only** — the engine sets the value; user cannot declare it
- **Explicit only** — user must declare it; nothing to derive
- **Both** — engine derives a default; user can override or supplement

**Principle**: explicit declaration is always allowed except for things only the engine can know (run-plane data, generated IDs). Even when a value is derivable, declaring it explicitly serves as documentation, override capability, and forward compatibility (if a kind's default changes later, existing explicit declarations stay stable).

### Resource fields

| Field | Mode | Derivation source | Explicit recommended? |
|---|---|---|---|
| `id`, `name` | explicit only | — | required |
| `display_name` | explicit only | — | optional |
| `tags` | explicit only | — | optional (organizational) |
| `requires[*].capability` | both | implicit per `driver.kind` contract (see catalog) | **yes** — declares semantic intent |
| `requires[*].strength` | both | defaults to `hard` | yes (`applicable`/`soft` carry distinct meaning) |
| `requires[*].when` | both | per-kind default (`before_install` / `before_config` / `before_run`) | only when non-default |
| `requires[*].condition` | explicit only | — | when needed |
| `requires[*].priority` | both | defaults to 0 | only when tie-breaking |
| `requires[*].args` | explicit only | — | when consumer-specific |
| `provides[*].capability` | both | implicit per `driver.kind` contract | **yes** — documents the resource's exported contract |
| `provides[*].when` | both | per-kind default (`after_install` / `after_config` / `running`) | only when non-default |
| `provides[*].condition` | explicit only | — | when needed |
| `configures` | explicit only | — | yes — explicit is the field's purpose |
| `driver.kind` | explicit only | — | required |
| `driver.<kind-specific-params>` | explicit only | — | required (kind-specific) |
| `driver.axes` (custom only) | explicit only | — | required for `kind: custom` |
| `driver.hooks` | explicit only | — | when used |
| `driver.snapshot` | explicit only | — | rare (VM-style only) |
| `policy.admin` | both | implicit per kind (e.g. `setting+pmset` → `admin: true`) | yes — security-relevant |
| `policy.update` | both | implicit per kind | only when overriding |
| `policy.version_pin` | explicit only | — | when pinning |
| `policy.selection_default` | both | defaults to `true` | only when restricting |
| `policy.destructive` | both | implicit per kind | yes — safety-relevant |

### Capability fields

| Field | Mode | Derivation source | Explicit recommended? |
|---|---|---|---|
| `type` | explicit only | — | required |
| `name` | explicit (often required by family rule) | — | required when family expects |
| `qualifiers` | explicit only | — | when needed (e.g., http-endpoint port) |
| `external` | both | defaults to `false`; Host's facts default to `true` | yes — resolver-relevant |

### Run-plane fields (always implicit unless noted)

| Field | Mode | Source | User can declare? |
|---|---|---|---|
| `RunSession.id` | implicit only | engine-generated | no |
| `RunSession.mode` | explicit only | — | yes (operator picks) |
| `RunSession.dry_run` | explicit only | — | yes |
| `RunSession.host_context` | implicit only | engine reads from Host | no |
| `RunSession.selection.{include, exclude, default}` | explicit only | — | yes |
| `Operation.{session, resource, axis}` | implicit only | engine sets | no |
| `Operation.observed` | implicit only | from observe phase | no |
| `Operation.desired` | implicit only | from resource declaration | no |
| `Operation.branch_taken` | implicit only | from diff phase | no |
| `Operation.outcome` | implicit only | from apply phase | no |
| `Operation.inhibitor` | implicit only | engine reason | no |
| `Operation.evidence` | implicit only | from observe | no |

### Auto-emitted capabilities (always implicit)

| Capability namespace | Emitted by | User declares? |
|---|---|---|
| `managed-resource-status/<id>` | every managed resource | no |
| `tag-status/<tag>/<phase>` | the engine, computed from the resource set tagged `<tag>` | no |
| `platform/*`, `arch/*`, `os_id/*`, `os_version/*`, `init-system/*`, `hardware-accel/*`, `package-manager-available/*`, `shell/*` | the Host built-in resource | no |

### Counts

| Category | Count |
|---|---:|
| Implicit only (engine generates; user can't declare) | 14 |
| Explicit only (user must declare; no derivation) | 21 |
| Both (engine derives; user can override or supplement) | 13 |
| Auto-emitted capability namespaces | ~10 |

### Insight

- **"Both" dominates user-declarable fields** — most are derivable from `driver.kind` + params, but explicit declaration is allowed and often preferred for documentation.
- **Implicit-only fields are mostly run-plane data** — values the engine PRODUCES.
- **Explicit-only fields are mostly identity and intent** — choices only the author can make.

The model intentionally keeps explicit always allowed (except for engine-produced values) so that resources can document their contract beyond what the kind catalog implies.

## What this model eliminates from the v3 spec

| v3 concept | Replaced by |
|---|---|
| 33 `element_type` values | 3 (Project, Resource, RunSession+Operation) — Component dissolved entirely (not even a `kind`) |
| 14 `relation_type` values | 3 declarable (`requires`, `provides`, `configures`) |
| `resource_type`, `convergence_profile_derived`, `state_model_derived` | derived from `driver.kind` and axis subscription |
| `desired_state.{installation, runtime, health, admin, dependencies, value}` | `driver.axes.<axis>.desired` (custom only) |
| `OperationContract.{observe, converge, snapshot, recover, pre/post_converge}` | folded into `driver` |
| `requires:` (v3 top-level predicate string) | `requires: [{ capability: platform/*, strength: applicable }]` (structured list) |
| `depends_on` | derived view of hard `requires` |
| `consumes` (v4 earlier name) | renamed to `requires` — capabilities aren't depleted |
| `provides.when_axes: [<axis>, ...]` (array, AND-set) | `provides.when: <lifecycle-phase>` (single phase value) |
| `verification-test` element class | resource with `provides: verification/*` |
| `preflight-gate` element class | resource with `provides: preflight/*` |
| `governance-claim`, `output-contract`, `external-provider`, `compatibility-*` | dropped or reframed as `provides: <namespace>/*` |
| `verification-suite`, `verification-context` | `tags: [<suite-name>]` on the verification resources |
| `Component` element class | dissolved — no `component:` field, no `kind: aggregator`; pure grouping is `tags: [<group>]`; component parameters become project-level parameters |
| `capability.scope` | dropped (was conflating aggregator boundary, host vs guest, and per-user/system); `external: true` covers cross-substrate visibility, qualifiers/conditions cover the rest |
| `driver.hooks.{pre, post}` (separate arrays) | single `hooks: [...]` list with per-entry `when:` lifecycle phase |
| component-level `restart_processes` (legacy, unmodeled) | per-resource `hooks: [{ when: after_X, killall: [...] }]` on the resource that owns the side-effect |
| `layer` | not modeled (filesystem dirs only) |
| `provider_selection` block | conditional `requires` + `priority` |
| `driver_type`, `driver.kind` (legacy 26 values), `backend_type`, `provider_type`, `provider_name` | one `driver.kind` from a registered catalog |
| `kind: capability`, `kind: predicate`, `kind: oracle` | unified as `kind: observe` |
| Six `desired_state` "axes" | three real state axes (`install`, `config`, `run`); `health`, `admin`, `dependencies` recharacterized |

## Concept count

| | v3 spec | This model |
|---|---:|---:|
| Element classes | 33 | **3** (Project, Resource, RunSession+Operation) — Component dissolved |
| Relation types | 14 | 3 declarable (`requires`, `provides`, `configures`) |
| Top-level resource fields | 15+ | 5 (`requires`, `provides`, `driver`, `policy`, `tags`) |
| State axes | 6 (mixed with predicates) | 3 |
| Consume strengths | 2 | 3 |
| Driver kinds | ~26 + 22 tool_types | ~32 + `custom` (no `aggregator` — pure grouping uses `tags`) |
| Hook arrays | 2 (pre + post) | 1 (`hooks: [...]` with per-entry `when:`) |
| Policy enum/object types | mixed | uniform `Predicate | bool` |

## Open questions

These are intentionally not resolved by this document and are left for a
follow-up:

1. **Capability operation contracts.** Should each `type` (within `capability` block)
   declare an operation signature (the args its consumers can pass via
   `requires.args` and the operations its providers must implement)?
   Yes is cleaner; no is simpler. See "driver-as-capability-op"
   discussion in design notes.

The v3 → canonical-model migration mapping (formerly open question #2)
is now in [compat.md](compat.md), which lists every v3 element_type,
relation_type, and resource field with its disposition (`kept` /
`collapsed` / `removed`) and migration recipe.
