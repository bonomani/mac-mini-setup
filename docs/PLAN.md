# PLAN

## Open

Three items remain — all deferred until there's a real consumer that
exercises the gap, not because the plan listed them.

### Phase B4 — decouple `docker-compose-service` from `ai_apps`

`_ucc_driver_docker_compose_service_action` calls
`_ai_apply_compose_runtime`, defined in `lib/ai_apps.sh`. Any other
component using `kind: docker-compose-service` would silently fail.
Today **no other component does**, so the decoupling has no current
consumer. Move the compose-apply primitive into a shared
`lib/docker_compose.sh` when (and only when) a second component needs it.

### Phase C1 — uniform drift helper

`_ucc_yaml_parametric_observed_state` already computes drift for every
parametric target. A `_cfg_drift` helper would only matter if drivers
themselves needed to short-circuit on drift before reaching the
framework. None do. Defer until a driver actually wants this.

### Phase X1 — per-driver smoke test fixtures

`tests/test_drivers.py` already covers schema/meta sync, and every
commit runs `bash -n` on touched driver files. A parametrized fixture
that loads each driver and asserts its hooks are callable would catch
the marginal "I added a function that fails to source" bug. Worth it
when a regression actually slips through; not before.

### Phase X1.5 — `--check` mode for `build-driver-matrix.py` in pre-commit

Trivial follow-up: install the BGS pre-commit hook and add
`python3 tools/build-driver-matrix.py --check` alongside it so a
silently-stale matrix fails the commit. ~10 minutes when the next
hook install happens.

## Closed

All driver-tier work that had a real consumer: D2, D3, D4, B2, C2, B3,
X2. See git log for details.

Three items honestly skipped:
- **C3** (desired-value comparison in observe) — already handled by
  the parametric framework.
- **C4** (fold compose-file into home-artifact) — would require a new
  one-target subkind; premature abstraction.
- **B1** (state vocab static check) — can't be enforced at static
  analysis without actually running drivers; belongs to runtime tests.

## Out of scope

- New `pkg` backends (mise, nix, aur). Add when a real target needs them.
