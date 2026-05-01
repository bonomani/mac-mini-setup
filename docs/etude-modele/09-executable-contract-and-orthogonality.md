# 09 - Executable Contract And Orthogonality

The missing pieces are part of the goal model, but not as more ad hoc fields on
managed resources. They are added as an executable contract layer with
orthogonal concepts.

## Goal

The current implementation model can be fully replaced only when the goal model can do three
things:

1. Import every legacy field into a goal-model concept.
2. Generate or verify every legacy executable view from the goal-model concepts.
3. Prove that each goal-model concept owns one meaning and does not duplicate another
   concept.

That means model v3 is:

```text
static declaration model
+ executable contract model
+ compatibility projection model
```

## Required Goal Contract

| Missing contract | Add as | Improvement before adding |
|---|---|---|
| Formal schema | `schema-registry` | Define common element fields and relation_type-specific required fields |
| Relation rules | `typed-relation` | Use common relation fields plus relation_type-specific attributes |
| Capability catalog | `capability-registry` | Use stable scoped capability IDs, not only names |
| Provider choice | `provider-selection` | Choose providers for a capability without leaking implementation details to dependents |
| Condition language | `condition-ast` | Parse legacy strings into structured predicates |
| Driver/backend metadata | `driver-contract` and `backend-contract` | Declare phases, params, implicit consumes/provides, exits, caches |
| Resource output | `output-contract` | Derive or declare what each package/runtime/capability resource provides |
| State transition model | `operation-contract` | Make observe/diff/apply/verify/recover explicit phases |
| Policy model | `policy-contract` | Separate operator intent from functional dependency |
| Run-session model | `run-contract` | Include host context, mode, selection, plan, and artifact paths |
| Verification mapping | `verification-contract` | Replace free-form trace with structured `verifies` |
| Compatibility layer | `compatibility-projection` | Keep legacy fields as generated or imported views |

## Shared Super-Forms

Several concepts share a common shape. Defining the super-form once avoids
parallel definitions and keeps validators uniform.

### `Predicate` (used by 5 concepts)

A single AST type used wherever the model evaluates a host or run fact:

```yaml
Predicate :=
    equals  { fact, value }
  | compare { fact, op, value }
  | not     { Predicate }
  | any     [ Predicate ]
  | all     [ Predicate ]
```

Used by: `requires` (resource), `condition` (relation), `condition`
(provider-selection), `preflight-gate.condition`,
`verification-test.skip_when`. One implementation, five call sites.

### `Contract` (used by 4 concepts)

Driver, backend, operation, and verification contracts share:

```yaml
Contract :=
  phases:           map<phase_name, { required: bool, command?: string }>
  parameters:       { required: [...], optional: [...] }
  implicit_relations: [ relation ]
  exit_codes?:      map<int, outcome_type>
```

Specializations: `driver-contract` (full), `backend-contract` (subset of
phases for one provider), `operation-contract` (per-resource override),
`verification-contract` (proof-only phases).

### `CapabilityEdge` (used by `provides`, `consumes`, `verifies`)

Every resource-level edge to a capability has the shape:

```yaml
CapabilityEdge :=
  to:                 Capability      # capability_type + name + scope + qualifiers
  condition?:         Predicate
  relation_source:    enum
  modifiers:                          # depends on which list:
    consumes: { consume_strength, relation_effect }
    provides: { provider_scope, satisfaction_rule }
    verifies: { oracle, evidence_level }
```

### `GeneratedFile` (used by `run-artifact`, `derived-artifact`)

```yaml
GeneratedFile :=
  path:               string
  format:             enum
  source_elements:    [ element_id ]
  generation_phase:   relation_phase
  drift_check?:       command           # only on derived-artifact
  outcome_link?:      operation-outcome  # only on run-artifact
```

### `Generator` (used by `resource-template`, `provider-selection`,
`compatibility-projection`)

```yaml
Generator :=
  input_shape:        schema
  condition?:         Predicate
  output_shape:       schema
  expansion:          function
```

### `Identifiable` (every model element)

```yaml
Identifiable :=
  id:           string         # `<element_type>:<name>`, fully qualified
  name:         string         # short identifier
  display_name?: string         # defaults to Title-Case of name
```

## Improved Concept Set

Model v3 uses these groups.

### Static Declaration Concepts

| Concept | Owns |
|---|---|
| `project` | Repository-level identity |
| `layer` | Top-level domain grouping |
| `component` | Functional grouping and execution scope |
| `resource-template` | Generator input for repeated resources |
| `managed-resource` | Converged leaf declaration |
| `capability` | Functional surface provided or consumed |
| `provider-selection` | Strategy for satisfying a capability through one of several providers |
| `condition` | Predicate over host or run facts |
| `policy` | Operator intent and permission/update/selection rules |
| `driver-contract` | Adapter behavior for observe/apply/evidence/recover |
| `backend-contract` | Provider-specific behavior inside a driver |
| `verification-test` | Independent post-convergence proof check |
| `derived-artifact` | Generated source-derived output |
| `governance-claim` | Compliance/boundary assertion |
| `output-contract` | Declared or derived outputs for packages, runtimes, and capabilities |

### Run Concepts

| Concept | Owns |
|---|---|
| `host-context` | Concrete facts for one run |
| `run-session` | One invocation and its identity |
| `selection-plan` | Resolved resource/component inclusion |
| `execution-plan` | Ordered operation graph for the run |
| `resource-operation` | One resource lifecycle during the run |
| `operation-outcome` | Result of a resource operation |
| `transition-inhibitor` | Why an operation did not apply |
| `observation-cache` | Cached observation source and invalidation |
| `run-artifact` | Declaration, result, status, summary, and verification output |
| `verification-context` | Runtime inputs needed by verification tests |

### Compatibility Concepts

| Concept | Owns |
|---|---|
| `compatibility-import` | How a legacy field is read into model v3 |
| `compatibility-view` | How a v3 model emits a legacy field |
| `compatibility-warning` | Where old and new meanings diverge |

## Typed Relation Contract

The relation shape is typed before it becomes executable. A single object with
all possible fields creates overlap.

Use common fields plus relation_type-specific attributes:

```yaml
relation:
  relation_type: consumes
  from: managed-resource:cli-jq
  to: capability:package-manager/brew
  condition:
    equals:
      fact: backend
      value: brew
  relation_source: backend-contract
  relation_phase: plan
  consumes:
    consume_strength: hard
    relation_effect: block
```

Common relation fields:

| Field | Meaning |
|---|---|
| `relation_type` | Relation verb |
| `from` | Source element |
| `to` | Resource element |
| `condition` | Optional predicate |
| `relation_source` | Where the relation came from |
| `phase` | Model/run phase where it matters |

relation_type-specific attributes:

| Relation type | Specific attributes |
|---|---|
| `contains` | `cardinality`, `order` |
| `declares` | `schema`, `source_file` |
| `generates` | `template`, `instances` |
| `derives` | `projection_rule`, `drift_check` |
| `selects` | `selection_source`, `closure_reason` |
| `overrides` | `precedence`, `operator_source` |
| `consumes` | `strength`, `effect`, `satisfaction` |
| `provides` | `provider_scope`, `satisfaction_rule` |
| `requires` | `condition_ref`, `skip_effect` |
| `verifies` | `claim`, `oracle`, `evidence_level` |
| `schedules` | `order_reason`, `cycle_policy` |
| `records` | `artifact_kind`, `format` |
| `invalidates` | `cache_key`, `when` |

Important improvement:

```text
strength belongs to consumes only.
requires is a host predicate relation, not a dependency.
depends_on is a compatibility view, not a source relation.
```

## Condition Contract

Legacy strings remain importable, but the model stores conditions as an AST.

```yaml
condition:
  any:
    - equals:
        fact: platform
        value: macos
    - equals:
        fact: platform
        value: linux
    - equals:
        fact: platform_variant
        value: wsl2
```

Version and negation examples:

```yaml
condition:
  all:
    - compare:
        fact: os_version.macos
        op: ">="
        value: "14"
    - not:
        equals:
          fact: package_manager
          value: brew
```

Compatibility import:

| Legacy string | Goal AST |
|---|---|
| `macos` | `equals(fact=platform,value=macos)` |
| `linux,wsl2` | `any(equals(platform,linux), equals(platform_variant,wsl2))` |
| `!brew` | `not(equals(package_manager,brew))` |
| `macos>=14` | `compare(fact=os_version.macos,op=>=,value=14)` |

## Driver Contract

Drivers are declared contracts, not only shell implementations.

```yaml
driver-contract:
  name: pkg
  operation_phases:
    observe: required
    apply: required
    evidence: optional
    recover: optional
  parameters:
    required:
      - backends
    optional:
      - bin
      - github_repo
      - migration_safety
  implicit_relations:
    - when:
        backend: brew
      consumes:
        capability: package-manager/brew
        consume_strength: hard
    - when:
        backend: npm
      consumes:
        capability: package-manager/npm
        consume_strength: hard
  exit_codes:
    0: complete
    1: failed
    2: changed_with_warning
    124: policy_warn
    125: admin_policy
```

This improves the current model because backend dependencies, cache behavior,
and policy exits become validatable instead of being inferred from shell code.

## Policy Contract

Policy must stay separate from dependency.

```yaml
policy:
  name: admin-required
  applies_to:
    resource: pmset-ac-sleep=0
    operation_phases:
      - apply
  requires:
    capability: admin-authority/sudo
  inhibitor:
    when_unsatisfied: policy
    exit_code: 125
```

Rule:

```text
policy decides whether an action is allowed.
consumes describes what the action needs.
policy may create a consumes relation, but it is not itself a dependency.
```

## Compatibility Projection

The legacy fields are compatibility projections. Model v3 owns the source of
truth.

| Legacy field | Goal-model source of truth | Projection |
|---|---|---|
| `depends_on` | hard `consumes` resolved through providers | generated resource list |
| `soft_depends_on` | soft `consumes` | generated resource or gate list |
| `depends_on_by_platform` | hard `consumes` with condition | generated legacy mapping |
| `requires` | `requires` relation to condition AST | generated legacy string while compatible |
| `provided_by_tool` | provider capability metadata | generated display/provenance field |
| `admin_required` | policy plus `admin-authority` consume | generated boolean/string hint |
| `trace` | structured `verifies` relation | generated legacy trace text |
| `driver.backends` implicit deps | `backend-contract` | generated consumes relations |

Replacement is complete only when the validator can prove:

```text
legacy field == projection(goal model)
```

or:

```text
goal model == import(legacy field)
```

during migration.

## Orthogonality Rules

Use these rules before adding a goal-model concept.

1. A concept must own one axis.
2. A relation must connect concepts; it must not duplicate concept identity.
3. A policy may block an operation, but must not pretend to be a functional
   dependency.
4. A condition is a predicate, not a relation by itself.
5. A capability is a functional surface, not a resource and not a state.
6. A state is observed or desired; it is not a capability.
7. A driver is implementation, not lifecycle type.
8. A backend is provider choice, not platform policy.
9. A run-session is a runtime instance, not static configuration.
10. An artifact is a record or generated view, not the source declaration.

## Orthogonality Matrix

| Concept | Owns | Must not own |
|---|---|---|
| `project` | root identity | resource lifecycle, execution behavior |
| `layer` | top-level grouping | policy, state, driver behavior |
| `component` | functional grouping | dependency semantics, operation outcomes |
| `resource-template` | repeated resource generation | runtime selection or resource status |
| `managed-resource` | desired convergence declaration | run outcome or cache state |
| `type` | what kind of thing is converged | state axes or driver implementation |
| `profile` | default state axes/desired shape | package manager or backend choice |
| `state_model_derived` | comparison algorithm | install method or policy |
| `capability` | usable functional surface | provider resource identity or observed state |
| `condition` | predicate over facts | relation effect or resource identity |
| `provider-selection` | provider choice for a capability | dependency identity or platform policy |
| `relation` | typed edge between elements | element definition |
| `policy` | operator/admin/update/selection intent | technical dependency mechanics |
| `driver-contract` | implementation adapter behavior | resource lifecycle meaning |
| `backend-contract` | provider-specific adapter behavior | global platform policy |
| `preflight-control` | before-run gate | managed convergence |
| `verification-test` | independent proof check | resource action or mutation |
| `run-session` | one invocation | static source-of-truth |
| `selection-plan` | concrete inclusion set | declared component structure |
| `execution-plan` | concrete execution order | dependency source semantics |
| `resource-operation` | one resource's run lifecycle | resource declaration |
| `operation-outcome` | result classification | desired state |
| `transition-inhibitor` | why apply did not happen | dependency identity |
| `observation-cache` | cached observation data | source declaration |
| `run-artifact` | evidence from a run | static model definition |
| `derived-artifact` | generated view | live run evidence |
| `compatibility-view` | legacy field projection | goal-model source of truth |

## Non-Orthogonal Risks To Fix

| Risk | Why it overlaps | Fix |
|---|---|---|
| `depends_on` and `consumes` both treated as source truth | Both describe dependency | Make `consumes` source truth and `depends_on` resolved view |
| `requires` looks like dependency | It can skip resources like a dependency failure | Model it as relation to `condition`, not `consumes` |
| preflight controls and capability resources both check readiness | Both can say "ready/not ready" | Preflight controls gate a run; capability resources are managed observations |
| `admin_required` and `sudo-available` both represent admin | Policy and capability overlap | Policy consumes `admin-authority`; capability observes sudo availability |
| `driver_type` and `resource_type` both imply behavior | Package resources often map to package drivers | `type` is domain; driver is implementation |
| backend preferences and backend contracts both mention providers | Policy selects, backend executes | Preference chooses provider; backend contract declares behavior |
| provider names repeated in dependent resources | Dependents start depending on implementation details | Add provider-selection and make dependents consume the abstract capability |
| runtime endpoints and verification URLs diverge | Endpoint metadata and tests can describe different surfaces | Derive `http-endpoint` capabilities from endpoints and make tests verify those capabilities |
| package names and output capabilities are conflated | Package install names differ from binaries, apps, extensions, or models | Add output-contract for each package class |
| evidence and verification both prove things | Both produce proof | Evidence is resource-local; verification test is independent post-convergence proof |
| generated docs and source manifests both describe system | One copies the other | Generated docs are `derived-artifact` with drift checks |
| cache and observed state both affect decisions | Cached data can masquerade as state | Cache is an observation input with TTL and invalidation |
| compatibility fields and new fields coexist | Double source of truth risk | Add import/projection rules and validator equivalence checks |

## Minimal Model V3 Shape

```yaml
model_version: 3

elements:
  - id: managed-resource:cli-jq
    element_type: managed-resource
    component: cli-tools
    lifecycle:
      resource_type: package
      convergence_profile_derived: configured
      state_model_derived: package
    desired_state:
      installation: Configured
      runtime: Stopped
      health: Healthy
      admin: Enabled
      dependencies: DepsReady
    uses_driver: driver-contract:pkg

capabilities:
  - id: capability:binary/jq
    capability_type: binary
    name: jq
    capability_scope: host

relations:
  - relation_type: provides
    from: managed-resource:cli-jq
    to: capability:binary/jq
    provides:
      provider_scope: host

  - relation_type: consumes
    from: managed-resource:cli-jq
    to: capability:package-manager/brew
    condition:
      equals:
        fact: backend
        value: brew
    consumes:
      consume_strength: hard
      relation_effect: block

compatibility:
  views:
    depends_on:
      derives_from:
        - relations[relation_type=consumes, consumes.strength=hard]
        - provider_resolution
```

## Rollout Order

Migration is staged so legacy and goal forms coexist via projections; no
flag day. Each phase ships independently. The runner behavior is unchanged
for existing YAML throughout.

| # | Phase | Output | Risk |
|---|---|---|---|
| M1 | **Capability registry** + `provides`/`consumes` reader (warning mode) | new `lib/ucc_capability.sh`; validator parses optional `provides:` / `consumes:`, emits unresolved warnings | low |
| M2 | **Condition AST** | parser of legacy strings (`linux,wsl2`, `!brew`, `macos>=14`) into `{any, all, not, equals, compare}`; existing `requires` evaluator rebuilt on top | low |
| M3 | **Provider-selection** | `provider_selection:` block honored when a `consumes` matches multiple `provides`; first-compatible chooses by host condition | medium |
| M4 | **`consumes` ↔ `depends_on` equivalence** | validator computes `dependencies_derived` from `consumes`+`provides`; compares with hand-written `depends_on`; emits warning on mismatch | low |
| M5 | **Driver decomposition writer** | accept `action_type` (3 values: `converge`/`observe`/`snapshot`) + `tool_type` alongside legacy `driver.kind`; legacy verbs (install/update/configure/start/stop/…) become branches of `operation_contract.converge.*` dispatched by diff; validator computes the legacy projection | medium |
| M6 | **Backend decomposition writer** | accept `provider_type`/`provider_name`; cask becomes `provider_name=brew, subtype=cask` | low |
| M7 | **Operation contract** | accept `operation_contract:` block with `observe`, `converge.{on_absent, on_outdated, on_drifted, on_runtime_diff, on_topology_diff}`, `pre_converge` / `post_converge` hooks (replaces ad-hoc `restart_processes`), `snapshot.{capture, restore}`, and `recover`; absorbs `oracle` / `observe_cmd` / `evidence` / `actions.install` / `actions.update` | medium |
| M8 | **Endpoint absorption (EXT-A)** | `provides[].http-endpoint` with fixed qualifiers replaces `endpoints[]` | low |
| M9 | **Desired-value absorption (EXT-B)** | `desired_state.value: { literal | command }` replaces `desired_value`/`desired_cmd` | low |
| M10 | **Outcome/inhibitor coupling (EXT-C)** | runner attaches `inhibitor` block to `operation-outcome` when discriminator inhibits | low |
| M10b | **Version qualifiers (EXT-D)** | semver-style `version:` accepted in `provides`/`consumes` qualifiers; provider-selection rejects mismatched providers | medium |
| M10c | **Parametric resources (EXT-E)** | `parametric_in:` declared resources instantiated per-consumer-request; `nvm-version` and `pip-group-*` migrate onto this | high |
| M11 | **`_derived` fields read-only** | validator computes and exposes the 9 `_derived` fields; rejects manual writes that disagree | medium |
| M12 | **Verification re-targeting** | `verifies` points at capability IDs (`capability:http-endpoint/ollama.tags`) rather than free strings | medium |
| M13 | **Cutover: legacy fields become read-only views** | `depends_on`, `requires` (string), `state_model`, `profile`, `actions`, `oracle`, `observe_cmd`, `evidence` (top-level), `endpoints[]`, `desired_value`, `desired_cmd`, `runtime_manager`, `probe_kind`, `provided_by_tool`, `admin_required` — all generated, never written | high |
| M14 | **Compatibility-view emitter retired** | once equivalence proven across all 147 resources for a legacy field, drop the projection from the validator | low |
| M15 | **Driver implementations split (one per `tool_type`)** | refactor `lib/drivers/*.sh`: each driver becomes one file per tool with action dispatchers; legacy 26 driver kinds resolve to (action, tool) pairs at load time | high |
| M16 | **Component parameter typing** | accept `parameters:` block in component YAML with `parameter_type` (semver, port, path, url, …); validator typechecks every `${var}` substitution; bad values rejected at validation time instead of apply time | medium |
| M17 | **Resource-template instantiation** | accept `resource_templates:` blocks; the 5 generator lists (`cli_tools`, `casks`, `pip_groups`, `npm_packages`, `vscode_extensions`) become one template + one instance list each; the validator generates the ~80+ derived resources at load time; legacy expansion bash code retired | high |

### Phasing rules

- M1–M6 add features; legacy forms keep working unchanged.
- M7–M12 are dual-form: validator accepts legacy or goal, emits warnings on mismatch.
- M13–M15 are cutover: legacy forms become projections only.

### What unlocks the user-facing promise

The "I declare `consumes daemon:docker`, the engine figures out winget on
WSL2" scenario needs **M1 + M2 + M3 + M5** (capability, condition AST,
provider-selection, action/tool decomposition). The remaining phases are
about cleaning up duplicates and absorbing legacy fields.

In the goal model, these checks are required. During migration they run in
warning mode before they become blocking validation errors:

1. Condition intersection check for every conditional dependency.
2. Capability resource must provide a stable capability ID.
3. Runtime endpoint must derive an `http-endpoint` capability.
4. Package resource must derive a typed output capability.
5. `custom` resource must declare an operation contract.
6. Package `desired_value` is replaced by package desired state.
7. Direct provider edges become provider-selection rules where an
   abstract capability exists.

## Replacement Criteria

The current compatibility model can be removed when all of these are true:

```text
every legacy live field has an import rule
every legacy executable field has a projection rule
validator proves old and new views equivalent
all driver/backend implicit dependencies are declared as contracts
all verification trace strings have structured verifies relations
run artifacts reference model version, run-session, resource, phase, and outcome
generated docs declare their source elements and drift checks
compatibility fields are read-only generated views or deleted
```

Until then, the correct strategy is dual-read with one source of truth per
concept and validator-enforced equivalence.
