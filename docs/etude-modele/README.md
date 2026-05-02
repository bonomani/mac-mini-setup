# Goal Convergence Model Study

Study folder for turning the conceptual model into a refactoring basis for
the `mac-mini-setup` project.

> **Start here:** [model.md](model.md) is the candidate canonical model. It
> consolidates and supersedes the 13 numbered docs below on points where
> they conflict (notably: 3 axes instead of 6, no `layer` element class,
> driver-kind-implied axis subscription, unified `consumes`/`provides`
> graph, `Host` as a built-in virtual resource). The numbered docs remain
> as detailed reference and historical context.

The core idea remains useful, but there are two levels to keep separate:

> A **model element** is any named node in the system.
> A **managed resource** is the leaf node converged by the engine.

So `software`, `system`, `cli-tools`, and `cli-jq` are all model elements,
but only `cli-jq` is a managed resource.

The complete model distinguishes several element classes:

```text
layer               -> software, system, verification     (legacy framing — see model.md)
component           -> cli-tools, docker, ai-apps
preflight control   -> condition before convergence
managed resource    -> resource managed by the convergence engine
verification test   -> post-convergence verification
run/session         -> one invocation, selection, plan, and artifacts
derived artifact    -> generated spec, run evidence, status files
```

## Live Source Of Truth

The numbers below come from the current manifests:

```text
managed components   : 11
managed resources      : 147
verification tests   : 23
distinct drivers     : 26
live soft deps       : 0
```

Authoritative sources:

- `ucc/software/*.yaml` and `ucc/system/*.yaml` for managed resources.
- `defaults/*.yaml` for gates, preferences, selection, and profiles.
- `tic/**/*.yaml` for verification tests.
- `tools/validate_targets_manifest.py` for graph invariants.
- `docs/SPEC.md` for the specification regenerated from source.

## Goal Model

```text
Project
  -> layer elements        software, system, verification
  -> component elements    functional groups
  -> preflight control     gates, preferences, selection
  -> convergence           resources, relations, desired state
  -> execution             observe/action/evidence + backend selection
  -> policies              admin, update, destructive, preferred driver
  -> state                 observed/desired axes
  -> run model             host, selection, execution plan, artifacts
  -> verification          tests that prove obtained capabilities
```

## Files

| File | Topic |
|---|---|
| **[model.md](model.md)** | **Canonical model — single resource shape, 3 axes, consumes/provides graph, Host as built-in. Read this first.** |

### Detailed reference (numbered, partially superseded by `model.md`)

| # | File | Topic |
|---|---|---|
| 01 | [elements.md](01-elements.md) | Object, managed resource, preflight control, verification test |
| 02 | [scopes.md](02-scopes.md) | Live components / scopes |
| 03 | [capabilities.md](03-capabilities.md) | Capabilities, `provides`, `consumes` |
| 04 | [types.md](04-types.md) | `type`, `profile`, `state_model_derived`, state axes |
| 05 | [synthesis-table.md](05-synthesis-table.md) | Goal model synthesis |
| 06 | [resource-schema.md](06-resource-schema.md) | Goal resource schema |
| 07 | [current-mapping.md](07-current-mapping.md) | Current implementation -> goal model mapping |
| 08 | [implementation-gaps-and-model-v3.md](08-implementation-gaps-and-model-v3.md) | Reverified gaps and complete v3 model coverage |
| 09 | [executable-contract-and-orthogonality.md](09-executable-contract-and-orthogonality.md) | How to add the missing executable contract and keep concepts orthogonal |
| 10 | [visual-model.md](10-visual-model.md) | Visual representation of the v3 model |
| 11 | [avahi-bonjour-declination.md](11-avahi-bonjour-declination.md) | Concrete v3 declination for Avahi, Bonjour, and mDNS |
| 12 | [resource-spec-requirements.md](12-resource-spec-requirements.md) | Required resource-spec semantics for the goal model |
| 13 | [field-values-registry.md](13-field-values-registry.md) | Closed/open enum values for every composed field |

## Core Rule

The convergence graph must stay closed at the managed-resource level:

```text
depends_on          -> another declared managed resource
requires            -> host predicate outside the graph
verification test   -> verifies a resource/capability, but does not converge anything
preflight control   -> allows or blocks the run, but is not a managed resource
```

Hard and soft dependencies are both cases of `consumes`. Their difference is
a property of the relation, not a separate category:

```text
relation := { from, to, relation_type, consume_strength, condition, relation_source, relation_effect }
relation_type := consumes | provides | contains | verifies | requires
consume_strength := hard | soft
```

`depends_on` then becomes a resolved view:

```text
resource A consumes capability X
resource B provides capability X
=> resolved depends_on: A -> B
```
