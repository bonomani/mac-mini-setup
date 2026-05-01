# 05 - Goal Model Synthesis

## Global View

```text
                         Project
                           |
          +----------------+----------------+----------------+
          |                |                |                |
       software          system        verification        run model
          |                |                |                |
      components       components       tests/suites     sessions/plans
          |                |                |                |
    managed resources  managed resources     proof elements   artifacts
```

`software`, `system`, components, resources, gates, and tests are all model
elements. They do not all have the same role: only managed resources are
converged by the engine.

The goal model has two planes:

| Plane | Elements | Purpose |
|---|---|---|
| Static model | project, layer, component, resource-template, managed resource, driver, backend, capability, policy, verification test | Describes what can exist and what converges |
| Run model | host context, run session, selection plan, execution plan, resource operation, observation cache, run artifact | Describes one actual invocation and the evidence it leaves |

## Enriched Managed Resource

```text
managed resource
  identity    : name, component
  lifecycle   : resource_type, convergence_profile_derived, state_model_derived, desired_state
  host        : requires
  graph       : relations
  surface     : provides, consumes
  execution   : driver.driver_type, driver.backends
  policy      : admin_required, update_class, selection, preferred driver
  proof       : evidence, verification verifies
```

## Enriched Run Session

```text
run session
  identity    : correlation_id, timestamp
  operator    : interactive, preference source, override source
  host        : host context and condition facts
  mode        : install, update, check, dry_run
  selection   : selected resources, disabled resources, dependency closure
  plan        : component order, resource order, skipped resources
  execution   : resource operations and outcomes
  artifacts   : declaration, result, resource-status, summary, verification report
```

## Relations

```text
contains
  layer/component -> component/resource
  hierarchy edge

requires
  resource -> host predicate
  outside graph

driver/backend metadata
  resource -> implicit consumes/provides contract
  e.g. pip backend consumes package-manager:pip

provides/consumes
  resource -> capability relation
  can generate or validate graph edges

verification verifies
  verification-test -> resource/capability
  evidence after convergence

depends_on
  resource -> resource
  resolved scheduler edge derived from consumes/provides

selects
  selection-plan -> component/resource
  run-specific inclusion edge

records
  resource-operation/run-session -> run-artifact
  evidence edge

derives
  generated artifact/view -> source element
  source-of-truth edge
```

## Dependency = Consume

The conceptual dependency is a `consumes` relation. Hard and soft dependencies
therefore share the same schema. The difference is `strength`.

```yaml
relations:
  - relation_type: consumes
    to:
      capability_type: binary
      name: python3
    consume_strength: hard
    condition: null
    relation_source: declared
    relation_effect: block

  - relation_type: consumes
    to:
      capability_type: network-probe
      name: networkquality
    consume_strength: soft
    condition: null
    relation_source: declared
    relation_effect: order
```

The executable graph is then resolved:

```text
consumer consumes capability
provider provides capability
=> consumer depends_on provider
```

## Current Dependency Classes

| Class | Example | Blocks the action? | Source |
|---|---|---|---|
| declared hard consume | `python consumes pyenv capability` | yes | current `depends_on` / goal-model `consumes` |
| conditional hard consume | `docker-daemon consumes docker-desktop capability if macos` | yes if condition is true | `depends_on?condition` |
| driver/backend hard consume | `pip-group-* consumes pip` | yes | `driver.kind` / backend |
| semantic/policy hard consume | `pmset-* consumes admin-authority` | yes through policy | driver/policy |
| soft consume | ordering/evidence/warn only | no | current `soft_depends_on` / goal-model `consumes` |

Live manifests :

```text
declared hard deps        : 87
conditional hard deps     : 5
driver/backend hard deps  : 115
semantic/policy hard deps : 12
soft deps                 : 0
```

## Live Cardinalities

| Dimension | Cardinality | Source |
|---|---:|---|
| managed resource | 147 | `ucc/**/*.yaml` |
| managed component | 11 | top-level `component` |
| verification test | 23 | `tic/**/*.yaml` |
| Driver kind | 26 | `driver.kind` |
| Capability family | 17 required | goal model |
| preflight control | 1 | `defaults/gates.yaml` |

## What The Model Enables For Refactoring

| Area | Expected gain |
|---|---|
| `provides` / `consumes` | Detect missing or overly strong dependencies |
| backend-aware deps | Correct dependencies by platform |
| explicit policy | Clean separation between functional dependency and admin blocking |
| verification mapping | Link every test to a resource/capability |
| explicit state-model | Less implicit derivation between profile/type/state |
| enriched validator | Contradictions become schema errors |
| run-session model | Selection, dry-run, status cascade, and artifacts become explicit |
| artifact model | Generated docs and run evidence can be drift-checked |
| cache model | Observation cache validity becomes part of the operation contract |

## Final Invariant

```text
convergence converges resources.
preflight control decides whether the run can start.
verification proves that expected capabilities exist.
The state model provides the state language.
Drivers know how to observe and apply changes.
Policies say whether the action is authorized.
Run sessions say what was selected and what happened.
Artifacts record proof and drift-check generated views.
```
