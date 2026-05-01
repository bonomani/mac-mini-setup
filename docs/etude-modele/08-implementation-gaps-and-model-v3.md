# 08 - Implementation Gaps And Model V3

This pass rechecked the goal model against the current implementation, not
only against the resource manifests.

Sources inspected:

- `ucc/**/*.yaml` for live managed resources and manifest parameters.
- `defaults/*.yaml` for preferences, gates, profiles, and selection.
- `tic/**/*.yaml` for verification tests.
- `tools/validate_targets_manifest.py` and validator helpers for schema,
  condition parsing, graph ordering, driver metadata, and compatibility fields.
- `install.sh`, `lib/ucc*.sh`, `lib/uic*.sh`, `lib/tic*.sh`, and
  `lib/drivers/*.sh` for run behavior.
- `tools/build-spec.py`, `docs/SPEC.md`, and governance docs for generated and
  compliance artifacts.

## Reverification Result

The previous model was correct for the live managed-resource surface, but too
resource-centric for the whole project.

```text
live resource fields are mapped
run mechanics are under-modeled
generated artifacts are under-modeled
governance metadata is under-modeled
cache and override mechanics are under-modeled
some validator-supported fields are compatibility or reserved schema
```

Live implementation facts:

| Surface | Live count / state |
|---|---:|
| managed resources | 147 |
| managed components | 11 |
| verification tests | 23 |
| driver_type values in use | 26 |
| live resource fields | 22 |
| live driver fields | 48 |
| live soft dependency edges | 0 |
| validator-supported profiles not live | `presence`, `verification` |
| validator-supported resource type not live | `service` |
| resource schema fields supported but not live | `depends_on_by_platform`, `soft_depends_on`, `stopped_installation`, `stopped_runtime` |
| live field outside canonical resource order | `requires` |

## What Did Not Map Cleanly

| Current implementation surface | Evidence | Previous mapping quality | Goal model element |
|---|---|---|---|
| One invocation of the installer | `install.sh`, `UCC_MODE`, `UCC_DRY_RUN`, `UCC_CORRELATION_ID`, interactive flags | weak | `run-session` |
| Host facts used by conditions | `HOST_PLATFORM`, `HOST_PLATFORM_VARIANT`, `HOST_ARCH`, `HOST_OS_ID`, `HOST_PACKAGE_MANAGER`, `HOST_FINGERPRINT` | partial | `host-context` |
| Condition grammar | `requires`, `depends_on?condition`, `_resolve_conditional_dep`, `_ucc_eval_requires` | partial string mapping | `condition` element with parser semantics |
| Selection and disabled-resource closure | `defaults/selection.yaml`, `selection.env`, `selection.yaml`, CLI args, dependency closure | weak policy mapping | `selection-plan` |
| Per-resource user overrides | `UCC_OVERRIDE__*`, `resource-overrides.yaml`, preferred-driver ignore list | weak policy mapping | `overlay` / `operator-override` |
| Topological execution | validator ordering, `UCC_TARGET_DEFER`, registered resources, platform skip cascade | weak graph mapping | `execution-plan` |
| One resource lifecycle execution | declare, observe, diff, apply, verify, recover, record in `ucc_target` | under-modeled | `resource-operation` |
| Operation outcomes | `ok`, `changed`, `failed`, `warn`, `policy`, `skip`, `disabled`, `dry-run` | under-modeled | `operation-outcome` |
| Exit-code policy | driver rc `124` warn, rc `125` admin/policy | missing | `transition-inhibitor` |
| Observation and update caches | `_BREW_*_CACHE`, `_PIP_*_CACHE`, `_ucc_cache_*`, TTL/invalidation | missing | `observation-cache` |
| Run evidence files | declaration/result JSONL, resource-status, summary, verification report | partial evidence mapping | `run-artifact` |
| Generated specification | `tools/build-spec.py`, `docs/SPEC.md`, `--check` | missing | `derived-artifact` |
| Governance/compliance claims | `BGS.md` and other governance docs, compliance report | missing | `governance-claim` |
| Verification execution context | `requires_status_target`, `skip_when`, component platform skip, PATH setup for pyenv/nvm | partial | `verification-context` |
| Resource generator lists | `cli_tools`, `pip_groups`, `npm_packages`, `vscode_extensions`, Ollama size groups | partial | `resource-template` |
| Manifest scalar substitution | ports, paths, versions, URLs, stack metadata consumed by resources/drivers | partial | `parameter-space` |
| Compatibility fields | zero-live fields and legacy views | partial | `compatibility-view` |

## Goal Model: Static Plane + Run Plane

The goal model is a two-plane model rather than a resource-centered model.

### Static Plane

The static plane describes what the repository declares.

```text
project
  contains layer
  contains component
  declares resource-template
  declares managed-resource
  declares capability
  declares driver/backend contract
  declares preflight control
  declares preference/policy
  declares verification suite/test
  declares governance claim
  generates derived artifact
```

Static element classes:

| Element | Purpose |
|---|---|
| `project` | Root of the modeled system |
| `layer` | Major domain: software, system, verification |
| `component` | Functional group and execution scope |
| `resource-template` | Generator input that expands into many resources |
| `managed-resource` | Leaf that can be observed and converged |
| `capability` | Functional surface provided or consumed |
| `driver` | Adapter contract for observe/apply/evidence/recover |
| `backend` | Provider choice inside a driver |
| `host-context` | Facts used by conditions |
| `condition` | Parsed predicate over host/run facts |
| `preflight-control` | Run gate before convergence |
| `preference` | Operator policy with defaults and overrides |
| `verification-suite` | Group of verification tests |
| `verification-test` | Read-only proof check |
| `derived-artifact` | Generated view such as `docs/SPEC.md` |
| `governance-claim` | External boundary/compliance assertion |
| `compatibility-view` | Legacy alias or schema field kept during migration |

### Run Plane

The run plane describes what happens during one invocation.

```text
run-session
  uses host-context
  resolves preferences and overlays
  builds selection-plan
  builds execution-plan
  executes resource-operation
  reads/writes observation-cache
  records run-artifact
  runs verification-context
```

Run element classes:

| Element | Purpose |
|---|---|
| `run-session` | One invocation, including mode, dry-run, interaction, and correlation id |
| `selection-plan` | Concrete selected/disabled resource set plus dependency closure |
| `execution-plan` | Ordered components and resources for this run |
| `resource-operation` | One resource's observe/diff/apply/verify/recover/record lifecycle |
| `operation-outcome` | Result of a resource operation |
| `transition-inhibitor` | Reason an action did not apply: dry-run, policy, admin, user, no install function |
| `observation-cache` | Cached observation data with scope, TTL, and invalidation rules |
| `run-artifact` | Declaration, result, status, summary, and report files |
| `verification-context` | Verification runtime inputs, skips, status dependencies, and environment setup |

## Goal Relation Schema

The relation model keeps hard and soft dependencies equivalent as
`consumes`, while also modeling relations that are not dependencies.

```text
relation := {
  from,
  to,
  relation_type,
  consume_strength,
  condition,
  relation_source,
  relation_effect,
  relation_phase
}

relation_type :=
  contains | declares | generates | derives | selects | overrides |
  consumes | provides | requires | verifies | schedules | records |
  invalidates

consume_strength :=
  hard | soft

relation_effect :=
  contain | declare | derive | select | override | block | order |
  warn | skip | observe | apply | verify | prove | record |
  invalidate

relation_phase :=
  model | preflight | plan | observe | apply | verify | report
```

Examples:

```yaml
- relation_type: selects
  from: selection-plan:run-2026-05-01
  to: managed-resource:cli-jq
  selection_source: cli_args
  relation_effect: select
  relation_phase: plan

- relation_type: consumes
  from: resource-operation:cli-jq
  to: managed-resource-status:homebrew
  consume_strength: hard
  relation_source: resolved-dependencies
  relation_effect: block
  relation_phase: apply

- relation_type: records
  from: resource-operation:cli-jq
  to: run-artifact:result-jsonl
  relation_effect: record
  relation_phase: report

- relation_type: invalidates
  from: resource-operation:pip-group-langchain
  to: observation-cache:pip-outdated
  relation_effect: invalidate
  relation_phase: apply
```

## Concrete Refactoring Model Additions

Add these objects to the model before changing the live YAML:

1. `host-context`
   - Owns `HOST_*` facts and fingerprint segments.
   - Conditions consume it instead of parsing free strings everywhere.

2. `condition`
   - Represents `macos`, `linux,wsl2`, `!brew`, and `macos>=14`.
   - Used by `requires`, conditional consumes, skips, and backend selection.

3. `run-session`
   - Owns mode, dry-run, interactive state, correlation id, and artifact paths.
   - Makes `install`, `update`, and `check` explicit model inputs.

4. `selection-plan`
   - Resolves defaults, preferences, CLI args, user selection files, disabled
     resources, and dependency closure into one concrete resource set.

5. `execution-plan`
   - Captures component order, resource order, platform skips, dependency skips,
     and deferred execution.

6. `resource-operation`
   - Captures phases: declare, observe, diff, apply, verify, recover, record.
   - Owns outcomes and transition inhibitors.

7. `observation-cache`
   - Captures in-memory and disk caches, TTL, source command, and invalidating
     action.

8. `run-artifact`
   - Captures declaration, result, resource-status, summary, profile-summary, and
     verification report files.

9. `derived-artifact`
   - Captures generated docs and their source-of-truth inputs.
   - Example: `docs/SPEC.md` generated by `tools/build-spec.py`.

10. `governance-claim`
    - Captures governance compliance assertions (e.g. BGS) and state-model
      assertions, together with their validation evidence.

11. `compatibility-view`
    - Captures legacy or reserved schema fields, including zero-live fields.
    - Prevents confusing "not live" with "not implemented".

## Compatibility Table

| Current implementation concept | Model v3 placement | Status |
|---|---|---|
| `depends_on` | resolved hard `consumes` view | compatibility view |
| `depends_on_by_platform` | conditional hard `consumes` view | implemented, zero live uses |
| `soft_depends_on` | soft `consumes` view | implemented, zero live uses |
| `requires` | `requires` relation to `condition` over `host-context` | live; enters canonical resource order |
| `presence` profile | legacy/reserved profile | implemented, zero live uses |
| `verification` profile | legacy/reserved profile for old verification modeling | implemented, zero live uses |
| `service` resource type | legacy/reserved type | implemented, zero live uses |
| `observe_success` / `observe_failure` | observation decoder metadata | implemented, zero live uses |
| `dependency_gate` | preflight-control consume that changes dependency state | implemented, zero live uses |
| `stopped_installation` / `stopped_runtime` | alternate runtime-state mapping | implemented, partly zero live |
| `runtime_manager` / `probe_kind` | legacy runtime display/probe hints | live; compatibility metadata |
| `trace` in verification tests | unstructured legacy `verifies` relation | live; migrate to structured `verifies` |

## Why Model V3 Is Stronger

Model v3 is stronger because it covers both what the repo declares and what a
run actually does.

| Previous model | Model v3 |
|---|---|
| Mostly static resource graph | Static graph plus run graph |
| Dependencies only explain scheduling | Consumes/provides also explain operation blocking, cache use, and verification status |
| Selection is a policy detail | Selection is a first-class resolved plan |
| Run artifacts are only evidence text/files | Artifacts become typed records with source, phase, and outcome |
| Generated docs are outside the model | Generated docs become derived artifacts with drift checks |
| Governance docs are outside the model | Governance claims become model elements tied to evidence |
| Caches are implementation details | Caches become observation inputs with invalidation rules |
| Legacy fields are mixed with normal fields | Compatibility views make migration explicit |

The important correction is this:

```text
The managed-resource model is necessary but not sufficient.
The full project model needs static elements plus run elements.
```

That lets the refactor keep the clean `provides` / `consumes` idea while also
covering selection, execution, verification, evidence, generated docs, and
governance.

The executable contract and orthogonality rules that make this safe to add are
defined in
[executable-contract-and-orthogonality.md](09-executable-contract-and-orthogonality.md).
