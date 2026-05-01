# 01 - Objects And Elements

## Model Element

A **model element** is any named node that participates in the system
description:

```text
project
  -> layer
     -> component
        -> resource
```

So `software` and `system` are elements. They are not managed resources; they
are **container elements**.

## Element Classes

The goal model does not collapse everything into one bucket:

| Class | Source | Role | Example |
|---|---|---|---|
| `project` | repo | Root of the modeled system | `mac-mini-setup` |
| `layer` | convention / governance scope | Major domain | `software`, `system`, `verification` |
| `component` | `component:` YAML | Functional and display grouping | `cli-tools`, `docker` |
| `resource-template` | component YAML generator lists | Template input that expands into many managed resources | `pip_groups`, `cli_tools`, `vscode_extensions` |
| `preflight-gate` | `defaults/gates.yaml` | Block or allow the run before convergence | `supported-platform` |
| `preference` | `defaults/preferences.yaml` | Operator policy with safe default and override sources | `update-policy` |
| `managed-resource` | `ucc/**/*.yaml` | Element observed, converged, and proven by the engine | `homebrew`, `docker-available` |
| `driver` | `driver.kind` + `lib/drivers/*.sh` | Observation/action/evidence adapter | `pkg`, `pip`, `setting` |
| `backend` | `driver.backends` | Provider choice inside a driver | `brew`, `native-pm`, `npm` |
| `run-session` | `install.sh` invocation | One run, including mode, host, selection, and artifacts | `mode=update dry_run=0` |
| `execution-plan` | validator + scheduler | Ordered operations to execute for a run | topological resource order |
| `run-artifact` | `$HOME/.ai-stack/runs/*` | Declaration, result, status, and summary evidence | `*.result.jsonl` |
| `derived-artifact` | generators / validators | File generated from source of truth | `docs/SPEC.md` |
| `governance-claim` | governance docs (e.g. `BGS.md`) | External compliance or boundary claim | `BGS-State-Modeled-Governed` |
| `verification-test` | `tic/**/*.yaml` | Post-convergence verification, without mutation | `ollama-api-reachable` |

In this study:

```text
element              = any model node
convergence element  = managed resource (`managed-resource`)
container element    = project, layer, or component
verification element = verification test
gate element         = preflight control
runtime element      = run-session, execution-plan, resource operation
artifact element     = generated docs, run evidence, status files
```

## Managed Resource

A managed resource is the atom of convergence: an executable leaf of the model.

```text
managed-resource := {
  name,
  component,
  resource_type,
  convergence_profile_derived,
  state_model_derived,
  requires,
  relations,
  provides,
  consumes,
  driver,
  policy,
  desired_state,
  evidence
}
```

## Convergence Graph Closure

```text
resource A --relation(relation_type=depends_on,consume_strength=hard)--> resource B
resource B --relation(relation_type=depends_on,consume_strength=soft)--> resource C

All vertices are managed resources declared under `ucc/`.
```

`depends_on` is only the resolved resource -> resource view. The functional
need is better expressed by `consumes`.

Example:

```text
cli-opencode consumes package-manager:npm
node-lts provides package-manager:npm
=> cli-opencode depends_on node-lts
```

## Outside The Graph

| Mechanism | Why it is outside the graph |
|---|---|
| `requires` | Predicate on the current host: platform, init system, package manager, OS version, arch |
| preflight control | Global run condition, not resource convergence |
| verification test | Result verification, not a convergence precondition |
| Policy | May block an action without representing a functional dependency |

## Element / Fact Continuum

The boundary between "element of the graph" and "fact of the host context" is
not absolute. It is a continuum driven by **engine responsibility**.

```text
        ┌──────────────────────────────────────┐
        │   ÉLÉMENT GÉRÉ                       │
        │   managed-resource                   │
        │   start/stop/install/configure/      │
        │   observe                            │
        └──────────────────────────────────────┘
              ▲                  │
              │ promotion        │  demotion
              │ (sonde)          │  (out of scope)
              │                  ▼
        ┌──────────────────────────────────────┐
        │   ÉLÉMENT NON-GÉRÉ                   │
        │   external-provider                  │
        │   present, referenced, not managed   │
        └──────────────────────────────────────┘
              ▲                  │
              │                  │  demotion
              │                  │  (banalisation)
              │                  ▼
        ┌──────────────────────────────────────┐
        │   FACT PUR                           │
        │   host-context                       │
        │   HOST_PLATFORM, HOST_ARCH, …        │
        │   evaluated by Predicate             │
        └──────────────────────────────────────┘
```

### Promotion: fact → element (sonde)

A fact is **promoted** to an element via a *sonde* (a `managed-resource` of
`resource_type: capability`, by convention named with the suffix
`-available`). Use this when:

- the fact is dynamic (changes between runs);
- several resources need to consume it explicitly;
- the observation should appear in the convergence report;
- the evaluation is non-trivial and benefits from caching.

```yaml
mps-available:
  resource_type: capability
  driver:
    action_type: observe
    tool_type: none
    parameters: { probe: torch_mps_available }
  provides:
    - capability_type: hardware-accel
      name: mps
```

Live sondes (11): `mps-available`, `cuda-available`, `mdns-available`,
`networkquality-available`, `network-available`, `docker-available`,
`python-venv-available`, `cgroup2-available`, `systemd-available`,
`user-linger-enabled`, `sudo-available`.

### Demotion: element → fact

An element drops to fact status when the engine **stops being responsible**
for it. Three intermediate stops:

| From | To | When |
|---|---|---|
| `managed-resource` | `external-provider` | engine still acknowledges the thing but no longer manages it (e.g. Bonjour on macOS) |
| `external-provider` | host-context fact | the thing becomes universal enough to live as a plain `HOST_*` fact |
| `managed-resource` | host-context fact | direct demotion when the resource is removed from the YAML |

### Cross-engine demotion

Crossing an engine boundary always demotes elements:

```text
Engine A (provisioner) elements
   └── installs OS                          # element of A
            │
            ▼
            Engine B (this project) sees:
            └── OS as fact                  # demoted across the boundary
                  └── installs Docker       # element of B
                        │
                        ▼
                        Engine C (in-container) sees:
                        └── Docker daemon as fact   # demoted again
```

### Rule

> The status (element / external-provider / fact) is determined by
> **whose responsibility the thing is**. Movement is bidirectional and
> requires only a declaration change, never a model change.

| Action on declaration | Effect |
|---|---|
| Add a `*-available` resource with `driver_type=capability` | promote a fact to element |
| Change `element_type` from `managed-resource` to `external-provider` | demote element to non-managed |
| Remove a resource from YAML and consume the matching `HOST_*` fact instead | demote element to fact |

## Dependencies As Consumes

Hard and soft are not two different objects. They are two strengths of the
same `consumes` relation:

```text
relation := {
  from: resource,
  to: resource | capability | host-predicate,
  relation_type: consumes | provides | verifies | contains | requires,
  consume_strength: hard | soft,
  condition: optional host predicate,
  relation_source: declared | driver | backend | policy | inferred,
  relation_effect: block | order | warn | prove | contain
}
```

| Strength | Effect |
|---|---|
| `hard` | Blocks convergence if unsatisfied |
| `soft` | Influences ordering, evidence, or warnings without blocking |

This gives a clean equivalence:

```text
hard dependency = relation(relation_type=consumes, consume_strength=hard)
soft dependency = relation(relation_type=consumes, consume_strength=soft)
```

`depends_on` is then a derived artifact:

```text
consumes(capability X) + provides(capability X) => depends_on(provider resource)
```

## Element Identity

| Field | Role | Example |
|---|---|---|
| `name` | Unique identifier | `cli-jq` |
| `component` | Logical and display group | `cli-tools` |
| `resource_type` | Manifest nature | `package`, `config`, `runtime` |
| `convergence_profile_derived` | Convergence profile | `configured`, `runtime`, `parametric` |
| `state_model_derived` | State model | `package`, `config`, `parametric` |
| `driver.driver_type` | Observation/action mechanism | `pkg`, `pip`, `service` |
| `requires` | Host predicate | `macos`, `linux,wsl2`, `launchd,systemd` |
| `relations` | Normalized provides/consumes/verifies/contains links | `consumes hard binary:python` |
| `provides` | Provided capabilities | `binary:jq`, `endpoint:http://127.0.0.1:11434` |
| `consumes` | Consumed capabilities | `package-manager:brew` |

## Type Nomenclature Convention

Every "what kind am I within my category?" field uses the suffix `_type`:

| Category | Field | Values |
|---|---|---|
| Resource | `resource_type` | `package`, `config`, `runtime`, `capability`, `precondition` |
| Capability | `capability_type` | `binary`, `http-endpoint`, `package-manager`, … (17 families) |
| Driver | `driver_type` | `pkg`, `pip`, `service`, `setting`, `tic`, `capability`, `custom` |
| Backend | `backend_type` | `brew`, `native-pm`, `npm`, `pip`, … |
| Relation | `relation_type` | `consumes`, `provides`, `contains`, `requires`, `verifies`, … |
| Element | `element_type` | `managed-resource`, `verification-test`, `preflight-gate`, … |
| Outcome | `outcome_type` | `ok`, `changed`, `failed`, `warn`, `policy`, `skip` |

Rule: never use a bare `kind:` or `type:` — always specify *of what*. This eliminates the `kind`/`type` ambiguity at the cost of one extra word per field.

## Derived Field Convention

Fields that are **never written as source of truth** but always computed from other fields use the suffix `_derived`. The validator may emit them as a read-only projection. Writing such a field by hand is an error unless it equals the derivation.

| Field | Computed from | Comment |
|---|---|---|
| `convergence_profile_derived` | `resource_type` + presence of `desired_value` / `desired_cmd` | replaces legacy `profile` |
| `state_model_derived` | `convergence_profile_derived` (so indirectly `resource_type`) | replaces legacy `state_model` |
| `dependencies_derived` | `consumes` relations + `provides` relations + `provider_selection` | replaces legacy `depends_on` |
| `platform_dependencies_derived` | conditional `consumes` relations | replaces legacy `depends_on_by_platform` |
| `provider_provenance_derived` | resolved provider for a satisfied `consumes` | replaces legacy `provided_by_tool` |
| `admin_required_derived` | `policy` + `consumes admin-authority` | replaces legacy `admin_required` boolean |
| `requires_string_derived` | `condition` AST | legacy `requires` string projection |
| `derived_applicability` | hard `consumes` providers' `requires` | already explicit |
| `resolved_dependencies` | `consumes` + `provides` resolved per host | already explicit |

Rule: a `_derived` field that does not match its derivation is a validation error.

## Other Composed Field Names

The same rule applies to fields that previously appeared under several parents with different meanings:

| Generic before | Composed after | Parent context |
|---|---|---|
| `source:` | `relation_source:` | relation provenance (`declared`, `driver`, `backend`, `policy`, `inferred`) |
| `source:` | `selection_source:` | selection-plan input (`cli_args`, `selection.yaml`) |
| `source:` | `declared_in:` | contains relation source-of-truth (`model`, `manifest`) |
| `scope:` | `capability_scope:` | capability scope (`host`, `user`, `component`, `container`, `external`) |
| `scope:` | `gate_scope:` | preflight gate scope (`global`) |
| `scope:` | `provider_scope:` | provider scope inside a `provides:` relation |
| `phase:` | `relation_phase:` | relation phase (`model`, `plan`, `apply`, `verify`, `report`) |
| `phases:` | `operation_phases:` | operation contract phase list |
| `effect:` | `relation_effect:` | relation effect (`block`, `order`, `warn`, `prove`, `contain`, `observe`, `record`) |
| `strength:` | `consume_strength:` | hard/soft on `consumes` relation |

## Shared Super-Forms

Several concepts repeat the same shape under different names. Documenting the
super-form once removes parallel redefinition. Full schema in
`09-executable-contract-and-orthogonality.md` § Shared Super-Forms.

| Super-form | Used by |
|---|---|
| `Identifiable` | every element class (`id`, `name`, `display_name?`) |
| `Predicate` | `requires`, `condition` (relation, provider-selection, gate, verification) |
| `Contract` | `driver-contract`, `backend-contract`, `operation-contract`, `verification-contract` |
| `CapabilityEdge` | `provides`, `consumes`, `verifies` (resource-level edges) |
| `Generator` | `resource-template`, `provider-selection`, `compatibility-projection` |
| `GeneratedFile` | `run-artifact`, `derived-artifact` |

## Important Correction

Gates are not convergence elements. The model says:

```text
preflight control controls the run.
managed resource converges state.
verification test verifies the result.
```
