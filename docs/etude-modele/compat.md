# Compatibility view: v3 spec → canonical model

> **Status**: migration mapping from the v3 spec (the 13 numbered docs in
> this folder) to the canonical model defined in
> [model.md](model.md). Closes the last open question in `model.md` §
> Open questions.

This document is the migration contract. Every v3 concept is listed with
its disposition in the new model:

- **kept** — concept exists with the same name and meaning
- **collapsed** — concept folded into a more general primitive
- **removed** — concept dropped (no consumer, or pure implementation
  detail)

Each entry includes the migration recipe — how to translate the legacy
form to the new form, and what code (if any) needs to change.

## 1. Element types (`element_type`, 33 values → 8 classes)

### 1a. Static plane (22 values)

| v3 element_type | Disposition | New model |
|---|---|---|
| `project` | **kept** | top of `Project → Component → Resource` |
| `layer` | **removed** | not declared in any YAML; software/system are filesystem buckets |
| `component` | **kept** | `Component` element |
| `resource-template` | **kept** | lives on `Component.resource_templates` |
| `managed-resource` | **collapsed** | `Resource` (single shape for all managed/unmanaged) |
| `capability` | **kept** | `Capability` value object (typed surface) |
| `provider-selection` | **collapsed** | conditional `consumes` entries + `priority` per consumer |
| `condition` | **collapsed** | `Predicate` AST, used inline wherever conditions appear |
| `policy` | **kept** | `Resource.policy` block |
| `driver-contract` | **collapsed** | `driver.kind` catalog (typed contract per kind) |
| `backend-contract` | **collapsed** | per-`capability_type` operation contract (deferred — open Q1 in model.md) |
| `preflight-gate` | **collapsed** | `Resource` with `provides: preflight/*` |
| `preference` | **collapsed** | `Component.parameters` (typed parameter declarations) |
| `verification-suite` | **removed** | use `Component` for grouping verification tests |
| `verification-test` | **collapsed** | `Resource` with `provides: verification/*` |
| `derived-artifact` | **kept** | output of the report phase (run-plane) |
| `governance-claim` | **removed** | no consumer; no shape ever defined |
| `output-contract` | **removed** | deferred (open Q1 in model.md) |
| `external-provider` | **collapsed** | host-published capabilities via the `Host` virtual resource. Note: the related `capability_scope: external` enum value was also removed; use `capability_scope: host` + `external: true` flag (see `model.md` §Capability) |
| `compatibility-view` | **removed** | this document IS the compatibility view |
| `compatibility-import` | **removed** | one-shot migration, not an ongoing model concept |
| `compatibility-warning` | **removed** | runtime concern (validator finding), not an element |

### 1b. Run plane (11 values)

| v3 element_type | Disposition | New model |
|---|---|---|
| `host-context` | **collapsed** | provided by `Host` (a built-in `Resource`); `RunSession.host_context` snapshot |
| `run-session` | **kept** | `RunSession` element |
| `selection-plan` | **collapsed** | `RunSession.selection` field |
| `execution-plan` | **collapsed** | computed during the `plan` phase; not declared |
| `resource-operation` | **collapsed** | `Operation` element (one per resource × axis × session) |
| `operation-outcome` | **collapsed** | `Operation.outcome` field (closed enum) |
| `transition-inhibitor` | **collapsed** | `Operation.inhibitor` field |
| `observation-cache` | **removed** | implementation detail (engine internal cache) |
| `run-artifact` | **kept** | output of the report phase |
| `verification-context` | **removed** | use `Component` for grouping; no separate shape needed |
| `managed-resource-status` | **collapsed** | implicit `managed-resource-status/<id>` capability published by every managed resource |

### Net: 33 → 8 element classes

`Project`, `Component`, `Resource`, `Capability`, `Host`, `RunSession`,
`Operation`, `RunArtifact`. (`Capability` is a value object, not an
element; the others are first-class.)

## 2. Relation types (`relation_type`, 14 → 2)

| v3 relation_type | Disposition | New model |
|---|---|---|
| `contains` | **kept** | only on `Component` (component → resource) |
| `declares` | **removed** | implicit in resource declaration (no separate edge) |
| `generates` | **collapsed** | `resource_template` instantiation |
| `derives` | **removed** | derivation is computed, not modeled |
| `selects` | **collapsed** | `RunSession.selection.{include, exclude}` |
| `overrides` | **collapsed** | `consumes.priority` (per consumer); parameter override hierarchy (component) |
| `consumes` | **kept** | typed edge to a Capability |
| `provides` | **kept** | typed edge from Resource to Capability |
| `configures` | **collapsed** | `consumes` of the configured resource's capability + capability_type=`config-file` provides |
| `requires` | **collapsed** | `consumes(strength: applicable)` for platform/host gates; `consumes(strength: hard, condition: P)` for conditional deps |
| `verifies` | **collapsed** | `Resource.consumes` of the capability being verified + `provides: verification/*` |
| `schedules` | **collapsed** | implicit topological order computed during `plan` phase |
| `records` | **collapsed** | implicit; every `Operation` produces evidence captured in the run-plane |
| `invalidates` | **removed** | cache invalidation is implementation |

### Net: 14 → 2 declarable + 1 structural

Declarable: `consumes`, `provides`. Structural (only on Component):
`contains`. Everything else is computed at plan time.

## 3. Top-level resource fields (15+ → 4)

| v3 field | Disposition | New model |
|---|---|---|
| `element_type` | **removed** | single `Resource` shape |
| `name`, `display_name`, `component` | **kept** | identity block |
| `resource_type` | **removed** | derived from `driver.kind` and the namespace of `provides` capabilities |
| `convergence_profile_derived` | **removed** | derived from axis subscription |
| `state_model_derived` | **removed** | derived from axis subscription |
| `driver` | **kept** | enriched with kind catalog + per-kind params + optional axes block (custom) + hooks + snapshot |
| `policy` | **kept** | uniform `Predicate \| bool` value space |
| `desired_state.{installation, runtime, health, admin, dependencies, value}` | **collapsed** | `driver.axes.<axis>.desired` (only when `kind: custom`); admin & dependencies recharacterized as policy / graph concerns |
| `operation_contract.{observe, converge, snapshot, recover, pre/post_converge}` | **collapsed** | folded entirely into `driver` (kind-specific or `custom.axes`) |
| `provides` | **kept** | typed (`when_axes`, `condition`, `qualifiers`) |
| `consumes` | **kept** | typed (`strength`, `condition`, `priority`, `args`) |
| `verifies` | **collapsed** | this resource provides a `verification/*` capability that consumers consume |
| `requires` | **collapsed** | `consumes(platform/X, strength: applicable)` via `Host` |
| `configures` | **collapsed** | `consumes` + `provides: config-file/*` |
| `relations` (typed array) | **collapsed** | replaced by typed `consumes`/`provides` |
| `provider_selection` | **collapsed** | conditional `consumes` + `priority` |
| `endpoints[]` | **collapsed** | `provides: http-endpoint/* @ host` with `qualifiers` (this is EXT-A, kept) |
| `depends_on` (legacy) | **removed as source** | derivable view of hard `consumes` |
| `requires_string` (legacy) | **removed as source** | derivable view of `requires` predicates |
| `*_derived` fields | **removed** | computed by the validator; not stored |

## 4. Driver / backend / provider concept cleanup

v3 had a **7-field driver expression**:

```yaml
driver:
  kind: <one-of-26-legacy-values>
  action_type: converge | observe | snapshot
  tool_type:  <one-of-21>
  backends:
    - provider_name: <one-of-10>
      provider_type: package-manager | fetch-method | app-registry
      subtype: cask | ...
      ref: ...
backend_type: <alias-for-provider-name>
```

Collapsed in the new model to **one driver kind + kind-specific params**:

```yaml
driver:
  kind: <one-of-32-catalogued-or-custom>
  # kind-specific params, e.g. for `pkg`:
  refs: { brew: jq, native-pm: jq }
  bin: jq
```

Mapping:

| v3 concept | New model |
|---|---|
| `driver_type` (legacy 26 values) | one `driver.kind` value |
| `action_type` | implied by which axis the kind subscribes to |
| `tool_type` | implied by `driver.kind` |
| `provider_type` | implied by `driver.kind`'s capability dispatch |
| `provider_name` | implied by which `package-manager-available/*` capability the host provides + which conditional `consumes` matches |
| `backend_type` | alias of `provider_name`, removed |
| `driver.backends` | conditional `consumes` entries, one per backend |

## 5. State axes (6 → 3)

| v3 "axis" (in `desired_state`) | New model |
|---|---|
| `installation` | **install** axis |
| `runtime` | **run** axis |
| `config_value` | **config** axis |
| `health` | **derived** from live `provides` (no separate axis) |
| `admin` | **policy concern**: `policy.admin: <Predicate> \| bool` |
| `dependencies` | **graph concern**: handled by `consumes` resolution |

## 6. Driver kind catalog migration (~26 legacy → 32 new)

| v3 `driver.kind` | New `driver.kind` | Notes |
|---|---|---|
| `pkg` | `pkg` | params: `refs`, `bin` |
| `pip` | `pip` | params: `isolation`, `probe_pkg`, `install_packages` |
| `npm` | `npm` | params: `package`, `version` |
| `git-repo` | `git-repo` | params: `url`, `dest`, `ref` |
| `git-global` | `git-global` | params: `key`, `value` |
| `setting` | `setting` | params: `path`, `key`, `value` |
| `service` | `service` | params: `unit`, `manager` |
| `compose-file` | `compose-file` | params: `path`, `content` |
| `compose-apply` | `compose-apply` | params: `compose_file`, `services` |
| `docker-compose-service` | `docker-compose-service` | params: `service_name` |
| `app-bundle` | `app-bundle` | params: `bundle_path`, `source` |
| `home-artifact` | `home-artifact` | params: `dest`, `source` |
| `script-installer` | `script-installer` | params: `url`, `verify_cmd` |
| `pyenv` | `pyenv` | params: `version` |
| `nvm` | `nvm` | params: `version` |
| `vscode` | `vscode` | params: `extension_id` |
| `ollama` | `ollama` | params: `model` |
| `path-export` | `path-export` | params: `dirs`, `rc_file` |
| `swupdate-schedule` | `swupdate-schedule` | params: `enabled`, `frequency` |
| `softwareupdate-schedule` | `softwareupdate-schedule` | macOS-specific alias of swupdate-schedule |
| `brew-analytics` | `brew-analytics` | params: `desired` |
| `brew-unlink` | `brew-unlink` | params: `formula` |
| `build-deps` | `build-deps` | params: `set: brew\|apt\|dnf` |
| `corepack` | `corepack` | params: `enabled` |
| `custom-daemon` | `custom-daemon` | params: `pid_fn`, `start_fn`, `stop_fn` |
| `json-merge` | `json-merge` | params: `target_file`, `keys` |
| `nvm-version` | `nvm-version` | params: `version` |
| `pip-bootstrap` | `pip-bootstrap` | (no params) |
| `pyenv-brew` | `pyenv-brew` | (specialty wrapper around pkg) |
| `zsh-config` | `zsh-config` | params: `theme`, `installer_url`, `omz_dir` |
| `capability` | `observe` | with `fn: { name, args }` |
| `predicate` | `observe` | with `predicate: <Predicate>` |
| `oracle` | `observe` | with `fn: { name, args }` |
| `custom` | `custom` | declares per-axis logic in `driver.axes` |

The 32-kind catalog has been validated against all 148 live resources by
`tools/simulate_model.py`; coverage is 100%.

## 7. Required code changes per package (`AUTHORITY.md` ownership)

| Package | Change | Effort |
|---|---|---|
| `lib-foundations` | minimal — `Identifiable`, `Predicate`, `Contract`, `Generator` super-forms unchanged | small |
| `lib-capabilities` | remove `ProviderSelection` shape (collapsed); `Capability` and `CapabilityEdge` unchanged | small |
| `lib-registry` | shrink `ELEMENT_TYPE` 33→8; shrink `RELATION_TYPE` 14→3; add `DRIVER_KIND_CATALOG` (32 values); remove `CONVERGENCE_PROFILE_DERIVED`, `STATE_MODEL_DERIVED` (now computed) | medium |
| `lib-schema` | rewrite around single `Resource` interface; collapse `OperationContract`, `DesiredState`, `relations[]` typed unions into per-axis blocks under `driver` | **large** — biggest refactor |
| `lib-contract` | runtime forms mostly unchanged; orthogonality matrix needs updating since many concepts collapsed | medium |
| `lib-mapping` | repurpose as the v3→canonical translator; `LegacyView` / `GoalView` retained but redefined | medium |
| `lib-quality` | rules survive but some become trivial (e.g. `condition_intersection` still meaningful; `package_output_contract` deferred with output_contract) | medium |
| `lib-cases` | refresh examples (Avahi/Bonjour) to canonical form; the simulator's emitted `mac-mini-v3/manifests-v4/*.yaml` already shows the form | small |
| `mac-mini-v3` | runtime updates: consume new `Resource` shape; replace `OperationContract` dispatcher with per-axis dispatcher; honor the 32-kind catalog | **large** |

## 8. Migration sequence (no flag day)

Recommended order to avoid breakage:

1. **Land `model.md` and this `compat.md`** (done — see commits `74140fa`, `9ee8798`, `22b746c`, `5749bda`, `189ceba`, `e27119b`).
2. **Land `simulate_model.py`** (done — `8a98f33`). Provides the v3→v4 translator that lib-mapping will absorb.
3. **Update `lib-registry`**: add new closed enums (`DRIVER_KIND_CATALOG`, `CONSUME_STRENGTH` extended with `applicable`), keep legacy enums alongside as deprecated.
4. **Update `lib-schema`**: add new `Resource` interface, keep legacy `ManagedResource` etc. as deprecated re-exports.
5. **Update `lib-mapping`**: implement bi-directional v3 ↔ canonical translation.
6. **Update `mac-mini-v3`**: support both old `manifests/*.yaml` and new `manifests-v4/*.yaml`. Begin by accepting both, validating both, but only running the legacy path. Then flip to running v4 once the runtime is verified.
7. **Run a parallel-validation period**: every legacy YAML is re-translated to v4 and the run plans diffed; surface mismatches via `lib-quality`.
8. **Switch over**: legacy types removed from `lib-registry`/`lib-schema`; only `compat.md` retained as historical record.

## 9. What stays as-is (no migration)

- **EXT-A** (`http-endpoint` qualifiers): kept verbatim.
- **EXT-B** (`desired_state.value` polymorphism): kept as `axes.<axis>.desired: { literal | command }`.
- **EXT-C** (inhibitor coupling): kept as `Operation.inhibitor`.
- **EXT-D** (version operators): kept as qualifier matching syntax.
- **EXT-E** (parametric resources): kept as `resource_template` on Component.
- **AUTHORITY.md** ownership table: rules unchanged; only the contents per package change.
- **`check-authority.py`, `check-imports.py`, `check-conformance.py`,
  `check-drift.py`, `simulate_model.py`**: tooling unchanged; targets
  updated as enums shift.

## 10. Concept count summary

| Concept | v3 | New model | Δ |
|---|---:|---:|---:|
| Element classes | 33 | 8 | −25 |
| Relation types | 14 | 3 (2 declared + 1 structural) | −11 |
| Top-level resource fields | 15+ | 4 | −11+ |
| State axes | 6 (mixed with predicates) | 3 (state) + 2 (predicates) + 1 (derived) | clearer split |
| Driver fields per resource | 7 | 1 (`kind`) + per-kind params | −6 |
| Driver kinds | ~26 | 32 (incl. `custom`) | catalogued |
| `consumes.strength` values | 2 | 3 | +1 (`applicable`) |
| Policy value-type | mixed enum + object | uniform `Predicate \| bool` | normalized |
| No-axis observation kinds | 3 (`capability`, `predicate`, `oracle`) | 1 (`observe`) | −2 |

## 11. References

- [model.md](model.md) — the canonical model.
- [AUTHORITY.md](AUTHORITY.md) — package ownership manifest (unchanged).
- The 13 numbered docs (`01-elements.md` … `13-field-values-registry.md`)
  — historical reference. Conflicts between them and `model.md` are
  resolved in favor of `model.md`.
- `tools/simulate_model.py` — automated v3 → canonical translator,
  validates coverage against the 148 live resources in
  `mac-mini-setup/`.
- `mac-mini-v3/manifests-v4/` — the 148 live resources translated to
  the canonical model, one YAML per resource.
