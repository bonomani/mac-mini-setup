# PLAN

## Open

No ollama items open as of 2026-04-15 end-of-day. Refactor sweep
#43–#53 shipped 2026-04-15. Ollama internet-research items #54–#57
shipped 2026-04-15 — daemon version probe (`/api/version`), install-
method evidence (`install=app`/`cli`), and automated apply of staged
Squirrel updates via SIGTERM + async poll (Ollama converges
0.20.6 → 0.20.7 unattended). Driver running-check refactor #58
shipped same day. Three items deferred (#2 cross-platform Docker,
#4 Phase C1, #6 Docker unattended Checkpoint C), four closed
not-a-bug (#16 via #34, #24, #27, #36; #29 confirmed intentional).
Docker install/launch is fully functional (tested 2026-04-13). Test
suite green. Pip venv isolation shipped (2026-04-14).

| # | Item | Status | Priority |
|---|---|---|---|
| 1 | ~~Auto-include dependency components~~ | ✅ DONE 2026-04-13 (`8f59b2e`, `2117c51`) | — |
| 2 | Docker cross-platform (WSL2/Linux) | Design + compat matrix ready | Low |
| 3 | ~~Minimize env size (145KB `_UCC_*` bloat)~~ | ✅ DONE 2026-04-13 (`9862f89`) — cleanup in `ucc_reset_registered_targets` | — |
| 4 | Phase C1 — drift helper | Waiting-for-consumer | Low |
| 5 | ~~`docker-privileged-ports` target~~ | ✅ DONE 2026-04-13 (`f064f39`, `d50b28f`) | — |
| 6 | Docker unattended first install — Checkpoint C | In-progress — core shipped, only Mac mini clean-state e2e remains | In-progress |
| 7 | ~~Fix test suite — 43 failing integration tests~~ | ✅ DONE 2026-04-13 — 159 pass, 1 skipped, 0 failed | — |
| 8 | ~~Driver convention: `_<driver>_state()` helper~~ | ✅ DONE 2026-04-13 — 7 drivers extracted, 12 share only cached YAML reads (no duplication) | — |
| 9 | ~~Extract install.sh functions to lib/~~ | ✅ DONE 2026-04-13 — install.sh 1225→991 lines (`c463e5c`) | — |
| 10 | ~~Unify batch cache access~~ | ✅ DONE 2026-04-13 — `_ucc_yaml_target_get_many` uses `_UCC_YTGT_*` cache (`3647ee4`) | — |
| 11 | Unified `update-policy` pref | ✅ DONE 2026-04-13 (`da6b335`, `7a9566a`) | — |
| 12 | Pip venv isolation (`isolation.kind: venv`) | ✅ DONE 2026-04-14 (`9a8cf5c`, `7287079`, `dede47a`) | — |
| 13 | ~~Dry-run ordering: `pyenv init` runs before pyenv exists~~ | ✅ DONE 2026-04-14 — 3 dep edges added, inline glue removed, rule codified in SPEC §3 | — |
| 14 | ~~Cascade-skip dependents of platform-skipped targets~~ | ✅ DONE 2026-04-14 — `platform-skipped` synthetic status emitted at group skip, handled in dep-gate with clean `[skip]` | — |
| 15 | ~~Platform-gate PREF display~~ | ✅ DONE 2026-04-14 — YAML parser filters by file + per-pref `platforms:`, using same match rule as `_component_supported_for` | — |
| 16 | ~~Ollama on WSL — review autostart semantics~~ | ✅ CLOSED 2026-04-15 — fixed by #34 (`requires: launchd,systemd` replaces `requires: macos>=14,linux,wsl2`). Ollama target now skips cleanly on WSL2 without systemd. | — |
| 17 | ~~Reconcile Summary "Total" vs "By Profile" counts~~ | ✅ DONE 2026-04-14 — renamed section to "By Profile — observations" for clarity | — |
| 18 | ~~Platform-aware header / RAM warning~~ | ✅ DONE 2026-04-14 — 32 GB RAM warning gated to `HOST_PLATFORM == macos` | — |
| 19 | ~~Add `python-venv-available` capability target~~ | ✅ DONE 2026-04-14 — probe in `lib/utils.sh` (7 failure modes), YAML target + 14 consumers wired | — |
| 20 | ~~`mps-available` / `cuda-available` skipped in dry-run~~ | ✅ DONE 2026-04-14 — removed `UCC_DRY_RUN != 1` + `case macos` gates in `pip_group.sh`; YAML `requires:` already handles platform filter | — |
| 21 | ~~Asymmetric skip-cascade: per-target `requires:` vs. component platform-skip~~ | ✅ DONE 2026-04-14 — codified asymmetry as principled in CLAUDE.md Rule 11; require explicit `?platform` for platform-conditional deps; ariaflow-server YAML fixed | — |
| 22 | ~~`brew services` backend on non-macOS hosts (ariaflow-server / -dashboard)~~ | ✅ DONE 2026-04-14 — added `init_system` fingerprint segment (launchd/systemd/no-init-system); ariaflow targets now `requires: launchd,systemd` | — |
| 23 | ~~`ai-stack-compose-file` installs even when `ai-stack-compose-running` is platform-skipped~~ | ✅ DONE 2026-04-14 — added `depends_on: [docker-available]` so it cascade-skips on WSL | — |
| 24 | ~~`avahi` installs despite `mdns-available` already passing~~ | ❌ CLOSED — not a bug. avahi is the Linux-native mDNS daemon; installing on Linux is correct even when dns-sd.exe interop also satisfies mdns-available. The two coexist. | — |
| 25 | ~~Services-list filtering — hide endpoints unreachable on this host~~ | ✅ DONE 2026-04-14 — `print_services_summary` reads `UCC_TARGET_STATUS_FILE` and filters out failed/skipped/never-converged targets; WSL drops 6 docker-stack endpoints | — |
| 26 | ~~Distinguish "Degraded" (broken) from "Outdated" (upgrade pending)~~ | ✅ DONE 2026-04-14 — `outdated` raw value now maps to `health_state=Outdated` (vs `Degraded` for drift); split also distinguishes `needs-update` (drift) from `outdated` (version) in config state model | — |
| 27 | ~~`Healthy` asserted without a probe~~ | ❌ CLOSED 2026-04-14 — re-read the drivers. All 4 (script-installer, path-export, zsh-config, home-artifact) DO have real probes (file/dir/setting checks). Pre-converge `Unknown` reflects the file not-yet existing; post-converge `Healthy` is asserted from actual file-exists checks, not vacuous. | — |
| 28 | ~~Profile-count math reconciliation (post-#17 follow-up)~~ | ✅ DONE 2026-04-14 — investigated: `Total` only counts `[ok]` lines (already-converged targets), `By Profile` counts every observation including dry-run plans. Same data, different scope. Clarified label to "By Profile — observations (incl. dry-run plans)" | — |
| 29 | ~~`ollama-model-llama3.2` default-enabled — verify it's intentional~~ | ✅ CLOSED 2026-04-14 — confirmed intentional. llama3.2 stays enabled by default; the larger models (llama3.1 8b/70b, qwen3, qwen2.5-coder, mistral) remain disabled | — |
| 30 | ~~Display-order within a group should follow dep order, not declaration order~~ | ✅ DONE 2026-04-14 — `_ucc_target_filtered_out` defers `[disabled]`/`[skip requires:]` emissions in defer mode; flush emits in topo order; flush no longer early-returns on empty registration | — |
| 31 | ~~`Unsloth Studio` display name collision~~ | ✅ DONE 2026-04-14 — disambiguated to `Unsloth Studio (launchd)` and `Unsloth Studio (systemd)` | — |
| 32 | ~~Inconsistent skip-message wording: `xcode-command-line-tools` / `build-deps`~~ | ✅ DONE 2026-04-14 — removed explicit `ucc_skip_target` calls in `homebrew.sh`; YAML `requires:` now handles both (uniform "requires: …" message) | — |
| 33 | ~~Capability-target dry-run projection misleading: shows `X -> Healthy` even when no install action exists~~ | ✅ DONE 2026-04-14 — dry-run path in `ucc_target` now checks for `install_fn`; capability targets (observe-only) emit `[observe] state="…" (observe-only)` instead of a misleading transition | — |
| 34 | ~~`ollama` target attempts autostart on WSL without init-system gate~~ | ✅ DONE 2026-04-14 — `requires: macos>=14,linux,wsl2` replaced with `requires: launchd,systemd` (same #22 pattern as ariaflow); WSL2 without systemd cleanly skips | — |
| 35 | ~~`pip-latest` (pip-bootstrap driver) ignores `update-policy=balanced`~~ | ✅ DONE 2026-04-14 — pip-bootstrap now detects `outdated` state via `pip list --outdated` (gated on `UIC_PREF_UPSTREAM_CHECK`) and respects `UIC_PREF_TOOL_UPDATE` in update action | — |
| 36 | ~~`softwareupdate-auto-check=1` silently overwrites user's manual opt-out~~ | ❌ CLOSED 2026-04-14 — not a bug, by design. Parametric targets are declarative; dry-run announces the change (`config_value=0 -> config_value=1`). Operator opts out via selection.yaml, target-overrides.yaml, or `--pref default-selection=none`. Same semantics as Ansible/Chef. | — |
| 37 | ~~`sudo-available` capability shows `health_state=Degraded`~~ | ✅ DONE 2026-04-14 — `_ucc_observe_yaml_capability_target` now emits `health=Unavailable` (was Degraded) when probe returns false. Degraded is reserved for broken/drift. | — |
| 38 | ~~Disk-cached `pip list --outdated` not invalidated after successful pip upgrade~~ | ✅ DONE 2026-04-14 (`dbae935`) — new `_ucc_cache_invalidate` helper called from pip-bootstrap, pip driver (global + venv), brew_upgrade, brew_cask_upgrade after successful action | — |
| 39 | ~~Component run stops showing remaining targets after a single target FAIL~~ | ✅ DONE 2026-04-14 (`ee874a2`) — `ucc_flush_registered_targets` now records failed status + `continue` instead of `return 1` on dep-fail; switches execute path to `|| true`. Dry-run shows 116 target lines (was ~99) | — |
| 40 | ~~`[policy] observed=… (policy blocked)` misleading for observe-only targets~~ | ✅ DONE 2026-04-14 — capability targets (no install_fn) now emit `[observe] state="…" (observe-only)` in both dry-run and real-run; other profiles keep the legacy "policy blocked" treatment when install_fn is missing for a different reason (e.g. parametric with failed dep-gate) | — |
| 41 | ~~`pip-group-huggingface` verify-after-update reports outdated despite upgrade succeeding~~ | ✅ DONE 2026-04-14 — pip driver (venv + global) + pip-bootstrap return rc=124 (warn) when post-upgrade observe still flags pkgs as outdated. Constraint-bound packages now show `[warn]` instead of `[fail]`. The pip outdated-list / upgrade-strategy mismatch is unavoidable; we acknowledge it as constraint-bound rather than failing. | — |
| 42 | ~~`ollama` target reports `[fail] install error` when Ollama.app daemon is already running~~ | ✅ DONE 2026-04-14 — custom-daemon driver now falls back to top-level `fallback_start_cmd` when `driver.start_cmd` is unset; if neither exists, returns rc=124 (warn) instead of 1 (fail). The daemon meant to be externally managed (launchd) no longer reports as a hard failure. | — |
| 43 | ~~Rule 2 cleanup — runtime paths hardcoded in lib/~~ | ✅ DONE 2026-04-15 (`df59c9d`) — 4 paths now have UCC_* env overrides: UCC_OLLAMA_ENDPOINT, UCC_DOCKER_SOCKET, UCC_OLLAMA_APP_PATH, UCC_APPS_DIR. Defaults preserve current macOS behavior. | — |
| 44 | ~~Centralize curl timeouts~~ | ✅ DONE 2026-04-15 (`472bfcc`) — `_ucc_curl_timeout` helper with 4 categories (probe/endpoint/metadata/download). 12 sites refactored. Per-category override via UCC_CURL_TIMEOUT_<CAT>. | — |
| 45 | ~~Hoist magic sleeps/retry constants~~ | ✅ DONE 2026-04-15 (`0e11fcb`) — 3 sites with env overrides: UCC_DOCKER_QUIT_WAIT_S, UCC_DOCKER_READY_INTERVAL_S, UCC_DOCKER_READY_ATTEMPTS, UCC_COMPOSE_PROBE_DELAYS, UCC_DAEMON_WAIT_S. | — |
| 46 | ~~Batch YAML reads in drivers~~ | ✅ DONE 2026-04-15 (`904b59c`) — Discovery: framework already has pre-load batch (`_UCC_YAML_BATCH_KEYS` in install.sh:908). 15 keys used by drivers were missing from the list, forcing Python subprocess fallback. Added: display_name, driver.backend, driver.curl_args, driver.installer_url, driver.isolation, driver.isolation.{kind,name}, driver.log_path, driver.migration_safety, driver.pull_policy_env, driver.requires_sudo, driver.start_cmd, driver.subkind, driver.upstream, update_class. Per-driver _batch_init helpers deferred — marginal gain on top of cache hits. | — |
| 47 | ~~Unified cache abstraction~~ | ✅ DONE 2026-04-15 (`ed6c330`) — added `_ucc_cache_invalidate_glob` for bulk by-pattern invalidation. Deeper auto-registration deferred — current 8 cache sites work cleanly with existing `_ucc_cache_*` helpers. | — |
| 48 | ~~Document + validate exit codes 124/125~~ | ✅ DONE 2026-04-15 (`36dde0d`) — UCC exit-code convention documented in ucc_log.sh; validation guard in `_ucc_run_yaml_action` warns + treats-as-fail any non-conventional code. | — |
| 49 | ~~Subshell cache discipline~~ | ✅ DONE 2026-04-15 (`36dde0d`) — discipline doc added in utils.sh: in-memory cache vars MUST be exported. Audit confirmed current state OK. | — |
| 50 | ~~Extract pip / pip-bootstrap shared constraint-bound logic~~ | ✅ DONE 2026-04-15 (`ad59666`) — extracted to `lib/pip_common.sh` `_pip_constraint_bound_check`. 3 sites reduced from 6 lines to 1 each. | — |
| 51 | ~~Driver capabilities registry~~ | ✅ DONE 2026-04-15 (`994cfa5`) — `_ucc_driver_dispatch` now logs (debug) when a non-custom kind is missing observe/action. Once per (kind, op) pair. | — |
| 52 | ~~Logging consistency~~ | ✅ DONE 2026-04-15 (`994cfa5`) — service.sh now log_warns on every failure path (brew_install, brew_upgrade, brew services start, launchctl load, unknown backend) with target context. | — |
| 53 | ~~Reassess deferred items~~ | ✅ DONE 2026-04-15 (`36dde0d`) — #16 closed (subsumed by #34); #6 moved Deferred → In-progress (only Mac mini clean-state e2e remains). | — |
| 54 | ~~Ollama daemon version probe via `/api/version`~~ | ✅ DONE 2026-04-15 (`bc58c4a`) — custom-daemon gains `driver.version_probe_path`. When set and the daemon is running, HTTP-probe the endpoint for `{"version":"X.Y.Z"}` instead of `bin --version`. Running daemon version is now authoritative for the outdated check (CLI binary can lag the .app bundle). | — |
| 55 | ~~Surface Ollama install method in evidence~~ | ✅ DONE 2026-04-15 (`bc58c4a`) — custom-daemon gains `driver.install_app_path`. Evidence line shows `install=app` when the path exists, `install=cli` otherwise. `.app` install signals Squirrel self-updating. SQLite DB read for `auto_update_enabled` not needed — path presence is sufficient signal. | — |
| 56 | ~~Rename `externally_managed_updates` → clearer semantic~~ | ✅ DONE 2026-04-15 — renamed YAML field to `self_updating` across all files (ucc_targets.sh, validator schema, install.sh batch keys, ai-apps.yaml, homebrew.yaml, test assertions). Log message changed from "update remains externally managed" to "self-updating target — update deferred to built-in updater". No backward-compat kept (clean break). | — |
| 57 | ~~Apply staged Squirrel updates for Ollama~~ | ✅ DONE 2026-04-15 (`5dba726`, cleanup `a74b7b6`) — `_update_ollama` in `lib/ai_apps.sh` now detects a staged bundle at `~/Library/Caches/ollama/updates/*/Ollama-darwin.zip`, SIGTERMs the app (AppleScript `quit` is canceled by the app's confirm dialog non-interactively), relaunches, and polls `/api/version` for up to ~60s — Squirrel's ShipIt runs async after relaunch and swaps the bundle. End-to-end: ollama converged 0.20.6 → 0.20.7 unattended. Custom-daemon driver's generic apply path dropped in cleanup — unreachable because ollama overrides driver dispatch with wrapper functions. `driver.pending_update_glob` kept for evidence (`update=pending`). | — |
| 58 | ~~Share running-check between observe + evidence in custom-daemon~~ | ✅ DONE 2026-04-15 (`f16bd43`) — `_ucc_driver_custom_daemon_running` helper unifies the pgrep + HTTP-fallback check. Fixes silent drift where evidence used pgrep-only and (when pgrep missed an externally-managed daemon) fell back to stale `bin --version` instead of the authoritative HTTP version probe. −23/+18 lines. | — |

### Unified `update-policy` pref

**Problem:** Three correlated concerns are currently spread across two
prefs (`package-update-policy` + `brew-livecheck`) with unclear naming.
Without `brew-livecheck=1`, no driver detects outdated packages — 7
drivers (brew, pip, pipx, nvm, custom-daemon, pkg, package,
script-installer) all silently report `[ok]` for installed-but-outdated
software. The pip driver also reuses `UIC_PREF_BREW_LIVECHECK` to gate
its own `pip list --outdated` cache — a naming mismatch that makes the
pref harder to reason about.

**Solution:** Replace `package-update-policy` and `brew-livecheck` with
a single `update-policy` pref:

```yaml
update-policy: conservative | balanced | aggressive
```

| Policy | Tools | Libs | Upstream check |
|---|---|---|---|
| `conservative` | install-only | install-only | off |
| `balanced` | always-upgrade | install-only | on |
| `aggressive` | always-upgrade | always-upgrade | on |

**Default:** `balanced` — tools stay current automatically, libs stay
stable until explicitly requested, upstream version checking enabled.

#### Target classification via `update_class`

The distinction is not about the driver — it's about whether upgrading
can break other installed software. Declared per-target in YAML:

```yaml
git:
  update_class: tool    # self-contained, safe to auto-upgrade

xz:
  update_class: lib     # shared dependency, upgrade can break consumers
```

| Class | Rule | Examples |
|---|---|---|
| `tool` (default) | Self-contained, no shared deps | jq, wget, git, ollama, iterm2, claude-code, nvm |
| `lib` | Shared dependency graph, upgrade can break consumers | pip packages, xz, openssl, gcc, build-deps |

**Driver defaults** (when `update_class` is not set in YAML):
- `pip` (no isolation) → `lib`
- `pip` (isolation=pipx) → `tool`
- All other drivers → `tool`

This lets brew formulae like `xz` or `openssl` opt into `lib` behavior
while most brew packages stay as `tool`.

#### Current code state (as of 2026-04-13)

The two legacy prefs already work but are spread across drivers:
- `UIC_PREF_PACKAGE_UPDATE_POLICY` — checked by `brew_refresh_caches`,
  `brew_formula_observe`, `brew_cask_observe` (lib/ucc_brew.sh)
- `UIC_PREF_BREW_LIVECHECK` — gates `brew livecheck` cache
  (lib/ucc_brew.sh) **and** `pip list --outdated` + `pipx` PyPI check
  (lib/drivers/pip.sh), despite the brew-specific name

The pip driver has no equivalent of `UIC_PREF_PACKAGE_UPDATE_POLICY` —
it always upgrades on `action=update` (gated only by
`_pip_update_would_conflict`). The new `update-policy` must wire
`lib`-class policy into `_ucc_driver_pip_action` so `balanced` skips
pip upgrades while `aggressive` attempts them.

#### Implementation steps

1. **New pref**: add `update-policy` to UIC preferences (conservative |
   balanced | aggressive). Default: `balanced`.
2. **Internal expansion**: map the single pref to three internal vars:
   - `UIC_PREF_UPSTREAM_CHECK` (on/off) — replaces `UIC_PREF_BREW_LIVECHECK`
   - `UIC_PREF_TOOL_UPDATE` (install-only | always-upgrade)
   - `UIC_PREF_LIB_UPDATE` (install-only | always-upgrade) — replaces
     `UIC_PREF_PACKAGE_UPDATE_POLICY` for lib-class targets
3. **Wire `update_class` into drivers**:
   - `_ucc_driver_pip_action`: read target's `update_class` (default
     `lib`); check `UIC_PREF_LIB_UPDATE` before attempting upgrade.
     The `_pip_update_would_conflict` safety check remains active in all
     modes — `aggressive` enables the upgrade attempt but the conflict
     guard still prevents breakage.
   - `brew_formula_observe` / `brew_cask_observe`: read target's
     `update_class` (default `tool`); check the matching policy var.
   - Other drivers (nvm, pkg, custom-daemon, script-installer): default
     `tool`, check `UIC_PREF_TOOL_UPDATE`.
4. **Mark targets**: add `update_class: lib` to brew formulae that are
   shared dependencies: xz, openssl, gcc, icu4c, readline, etc.
   Pip targets get `lib` by driver default so no YAML change needed.

**Operator overrides:** `--pref update-policy=aggressive` for a full
upgrade run. Or `--pref lib-update=always-upgrade` to override just
the lib part while keeping the rest at `balanced`. Granular knobs:
`--pref tool-update=install-only`, `--pref upstream-check=0`.

### Pip venv isolation (`isolation.kind: venv`)

**Problem:** All pip-group targets install into the global pyenv Python
environment. Packages with incompatible dependency constraints break
each other silently — pip reports conflicts but installs anyway. Three
incompatible zones identified (2026-04-13):

1. **unsloth/unsloth-zoo** — pins torch<2.11, datasets<4.4,
   transformers≤5.5, trl≤0.24 — incompatible with modern HF stack
2. **jupyter-ai-magics** — pins langchain<0.4 — incompatible with
   langchain 1.x used by pip-group-langchain
3. **datasets↔fsspec** — datasets 4.8 requires fsspec≤2026.2.0 but
   serving group pulls fsspec 2026.3.0

**Solution:** Extend the pip driver's existing `isolation` field from a
scalar (`pipx`) to an object with `kind` and `name`:

```yaml
# No isolation (current default — global pip)
pip-group-utilities:
  driver:
    kind: pip
    install_packages: python-dotenv

# pipx isolation (current — 1 venv per tool, no import sharing)
some-cli-tool:
  driver:
    kind: pip
    isolation:
      kind: pipx
    install_packages: some-tool

# venv isolation (new — shared named venv)
pip-group-pytorch:
  driver:
    kind: pip
    isolation:
      kind: venv
      name: ai-modern
    install_packages: torch torchvision torchaudio

pip-group-langchain:
  driver:
    kind: pip
    isolation:
      kind: venv
      name: ai-modern          # same venv, shares torch
    install_packages: langchain langchain-core

pip-group-jupyter:
  driver:
    kind: pip
    isolation:
      kind: venv
      name: jupyter-ai         # separate venv
    install_packages: jupyterlab jupyter-ai-magics
```

**Isolation modes:**

| `isolation` | Behaviour |
|---|---|
| absent | pip global (current, unchanged) |
| `kind: pipx` | 1 venv per package (current, unchanged) |
| `kind: venv, name: X` | shared named venv X (new) |

**Venv layout (3 environments):**

| Venv | Pip groups | Why isolated |
|---|---|---|
| `ai-modern` | pytorch, huggingface, langchain, llamaindex, llm-clients, vector-dbs, serving, data-science, utilities, dev-tools, optimum | Main compatible stack |
| `jupyter-ai` | jupyter, jupyter-ai-magics | langchain <0.4 conflict |
| `unsloth` | unsloth, unsloth-zoo | torch/transformers/trl version pins |

**Design rationale — follows existing patterns:**

The framework already has three isolation architectures, all using the
same `depends_on`-based pattern:

| Tech | Infra target | Package targets | Isolation unit |
|---|---|---|---|
| Docker | `ai-stack-compose-running` | `open-webui-runtime` etc. | container |
| Node | `nvm` → `node-lts` | `npm-global-claude-code` etc. | node version |
| Brew | `homebrew` | `git`, `jq` etc. | Cellar prefix |
| **Pip+venv** | (pip driver creates venv) | `pip-group-*` | **named venv** |

Unlike the others, pip venv creation is handled inside the pip driver
(like pipx), not as a separate infra target. The venv is created
idempotently on first `pip install` into it. This matches the pipx
pattern where `pipx install` creates the venv as a side effect.

**Implementation steps:**

1. **Parse `isolation` as object or scalar**: in `_ucc_driver_pip_observe`
   and `_ucc_driver_pip_action`, read `driver.isolation` — if it has a
   `.kind` subfield, use object form; if scalar `pipx`, treat as
   `{kind: pipx}` for backward compat; if absent, global pip.
2. **Venv management helpers**:
   - `_pip_venv_ensure <name>` — create venv via `pyenv virtualenv
     <python_version> <name>` if it doesn't exist
   - `_pip_venv_activate <name>` — set PATH to
     `~/.pyenv/versions/<name>/bin` so pip/python resolve to the venv
   - `_pip_venv_pip_cmd <name>` — return the venv's pip path directly
3. **Wire into observe**: when `isolation.kind=venv`, activate the venv
   before running `pip list` / `_pip_cached_version` / outdated checks.
   Version cache must be per-venv (key by venv name).
4. **Wire into action**: when `isolation.kind=venv`, ensure venv exists,
   then `pip install` into it. `_pip_update_would_conflict` dry-run
   also runs inside the venv.
5. **YAML migration**: add `isolation: {kind: venv, name: ...}` to all
   pip-group targets in `ai-python-stack.yaml`. Group assignment per
   the 3-venv table above.
6. **pip_cache_versions per venv**: the global `_PIP_VERSIONS_CACHE`
   must become per-venv. Use `_PIP_VERSIONS_CACHE_<VENV_NAME>` or a
   keyed lookup.

### Driver convention: `_<driver>_state()` helper

Observe and evidence functions often share the same "read current
state" logic. Rather than changing the dispatch protocol, each driver
that shares logic should extract a `_<driver>_state()` helper. Observe
calls it directly; evidence wraps it as `key=value`.

**Extracted helpers (7/7 with real command duplication):**
- `setting.sh` → `_setting_read_value()` (`5e4a86d`)
- `swupdate_schedule.sh` → `_swupdate_schedule_state()` (`1bfeff6`)
- `pip_bootstrap.sh` → `_pip_bootstrap_version()` (`63d775e`)
- `git_global.sh` → `_git_global_read()` (`63d775e`)
- `compose_file.sh` → `_compose_file_resolve_path()` (`63d775e`)
- `nvm.sh` → `_nvm_resolve_dir()` + `_nvm_self_version()` (`63d775e`)
- `app_bundle.sh` → `_app_bundle_plist_version()` (`63d775e`)

**Not extracted (12 — share only cached YAML field reads, no command duplication):**
brew, build_deps, compose_apply, custom_daemon, git_repo, home_artifact,
path_export, pip, script_installer, service, vscode/json-merge, zsh_config.

**Not applicable:** brew_unlink, docker_compose_service (different logic);
npm, package, pkg (dispatchers).

### Extract install.sh functions to lib/

install.sh is 1,225 lines with 25 functions. Several groups are pure
logic with no install flow dependency — they belong in dedicated lib
files for separation of concerns and testability.

**Phase 1 — `lib/ucc_selection.sh`** (selection/resolution logic):
- `_resolve_component()` (lines 406–437) — resolves component + auto-includes deps
- `_resolve_selection()` (lines 442–456) — dispatches component vs target args
- `_resolve_target()` (lines 394–404) — resolves single target to UCC_TARGET_SET
- Related state: `_resolved[]`, `UCC_TARGET_SET`, `_MANIFEST_DIR`, `_QUERY_SCRIPT`

**Phase 2 — `lib/ucc_interactive.sh`** (interactive browser):
- Component/target selection browser (lines 667–750)
- `_show_menu()`, `_get_comp_targets()`, browse loop
- Related state: `_BROWSE_COMPS[]`, `_COMP_TARGETS_DATA[]`, `UCC_TARGET_SET`

**Phase 3 — `lib/ucc_display.sh`** (display/plan output):
- `print_execution_plan()` (lines 1025–1038)
- `_display_component_name()` (lines 1013–1023)
- `_collect_layer_components()` (lines 985–1012)

**Expected result:** install.sh drops to ~900 lines. Each lib file
can be sourced independently and unit-tested.

### Unify batch cache access in `_ucc_yaml_target_get_many`

`_ucc_yaml_target_get_many()` (line 165 in ucc_targets.sh) always
calls python3 directly, bypassing the pre-loaded `_UCC_YTGT_*` batch
cache that install.sh populates at startup.

**Call sites that bypass cache:**
- Line 755: `_ucc_observe_yaml_parametric_target` — observe_cmd, dependency_gate
- Line 781: `_ucc_evidence_yaml_parametric_target` — observe_cmd
- Line 801: `_ucc_yaml_parametric_desired_value` — desired_cmd, desired_value
- Line 921: `_ucc_observe_yaml_runtime_oracle_target` — oracle.configured, oracle.runtime, stopped_*

All these keys are already in `_UCC_YAML_BATCH_KEYS` (install.sh
line 1099). When the cache is populated, these calls should read from
it instead of spawning python3.

**Fix:** Make `_ucc_yaml_target_get_many()` check the batch cache
first (same pattern as `_ucc_yaml_target_get` at line 154), falling
back to python3 only when uncached.

**Expected result:** 4–8 fewer python3 invocations per component run.

### Fix test suite — 43 failing integration tests (DONE)

All 43 failing tests fixed (2026-04-13). Final: 159 pass, 1 skipped.

**Fixes applied:**

| Cat | Fix | Commits |
|---|---|---|
| A | Source correct lib files (npm.sh, ollama_models.sh, vscode_ext.sh, homebrew.sh, pip_group.sh) | `7d5954f` |
| B | Protect empty arrays with `${arr[@]+"..."}` | `95d78b1`, `9e61110` |
| C | Update driver kinds (softwareupdate-defaults→setting, brew-formula→brew, brew-service→service) | `7d5954f` |
| D | Export HOST_PLATFORM=macos in xcode test preambles | `7d5954f` |
| E | Migrate capability fixtures to driver.kind: capability + driver.probe | `7d5954f` |
| F | Fix driver dispatch fallthrough, PYTHONPATH for HOME override, stub renames, assertion updates | `7d5954f`, `6afdc7a` |

**Bugs found and fixed during investigation:**
- `_ucc_run_yaml_action`: non-custom drivers with no action handler blocked YAML actions → fixed with `&& return` fallthrough (`8316b31`)
- `_ucc_driver_evidence`: driver evidence failure masked by `_ucc_driver_github_latest` → fixed with `|| return 1` (`9034539`)
- `AI_SERVICES[@]` unbound in `ai_apps.sh` → protected (`7d5954f`)
- `_write_compose_file` used local `stack_template_rel` (unbound in deferred mode) → use `_AI_APPS_TEMPLATE_FILE` (`6afdc7a`)
- `sudo -n true` fails inside `$()` subshells on macOS (tty-bound tickets) → detect at startup, cache in `_UCC_SUDO_AVAILABLE` (`12c627a`)
- `run_elevated` prompted for password in non-interactive mode → use `sudo -n` (`b79b2f5`)
- `defaults write -bool 1` invalid on macOS (requires true/false) → normalize values (`308ebff`)
- `softwareupdate --schedule` observe pattern didn't match actual output → fix grep (`274c5ce`)
- Deprecated driver kinds `desktop-app`, `docker-compose` removed from code + validator (`d185edd`, `631682d`)

**Refactorings applied:**
- `_ucc_driver_dispatch` hub deduplication (-36 lines) (`6f55222`)
- Dead desktop-app/docker-compose observe code removal (-129 lines) (`d185edd`)
- `_ucc_env()` test preamble helper (-69 lines) (`00eb983`)
- Driver observe/evidence dedup in setting.sh and swupdate_schedule.sh (`5e4a86d`, `1bfeff6`)

### Auto-include dependency components when selecting a single component

`./install.sh docker` fails because `docker-desktop` depends on
`homebrew` which lives in the `software-bootstrap` component. The
framework doesn't auto-include `software-bootstrap` — it only runs
the explicitly requested component, and cross-component dependencies
show as `dep-fail`.

**Expected behavior**: when a user selects a component (e.g. `docker`),
the framework should resolve `depends_on` across component boundaries
and automatically include any component that provides a required target.
In this case, selecting `docker` should auto-include `software-bootstrap`
(provides `homebrew`).

**Current workaround**: `./install.sh software-bootstrap docker` or
run without component filter (`./install.sh`).

### Docker support on Windows (WSL2) and Linux

Docker currently only runs on macOS (`platforms: [macos]` in
`docker.yaml`). The probes and launch logic are macOS-specific:
`open -g`, `osascript quit`, `pgrep com.docker.backend`, Apple
Virtualization.framework process tree.

**Current OS compatibility status** (2026-04-13):

| Function | macOS | Linux | WSL2 | Notes |
|---|---|---|---|---|
| `docker_desktop_observe` | ✅ | ❌ app path | ❌ app path | Checks `/Applications/Docker.app` |
| `docker_desktop_is_running` | ✅ | ❌ pgrep | ❌ pgrep | Checks `com.docker.backend` process |
| `docker_desktop_pid` | ✅ | ❌ pgrep | ❌ pgrep | Same process name |
| `docker_daemon_configured` | ✅ | ✅ | ✅ | Socket check — portable |
| `docker_daemon_is_running` | ✅ | ✅ | ✅ | `/_ping` on socket — portable |
| `docker_daemon_status` | ✅ | ✅ | ✅ | Calls `docker_daemon_is_running` |
| `docker_version` | ✅ | ✅ | ✅ | `/version` on socket — portable |
| `docker_resources_observe` | ✅ | ❌ path | ❌ path | Reads macOS `settings-store.json` |
| `docker_resources_apply` | ✅ | ❌ path | ❌ path | Writes macOS `settings-store.json` |
| `_docker_launch` | ✅ | ❌ open -g | ❌ open -g | macOS `open` command |
| `_docker_kill_zombies` | ✅ | ❌ osascript | ❌ osascript | macOS AppleScript |
| `_docker_ready` | ✅ | ✅ | ✅ | `/_ping` on socket — portable |
| `_docker_bootstrap_complete` | ✅ | ❌ path | ❌ path | macOS `settings-store.json` |
| `_docker_cask_ensure` | ✅ | ❌ brew cask | ❌ brew cask | macOS brew only |
| `_docker_strip_quarantine` | ✅ | n/a | n/a | macOS Gatekeeper xattr |
| `_docker_settings_store_patch` | ✅ | ❌ path | ❌ path | macOS `settings-store.json` |
| `_docker_assisted_*` | ✅ | n/a | n/a | macOS-only unattended install |

**Summary**: daemon-level probes (socket-based) are already portable.
Desktop-level probes and all install/launch/stop actions are macOS-only.

**Windows (WSL2)**:
- Docker Desktop for Windows uses WSL2 backend — `docker-desktop`
  and `docker-desktop-data` WSL distributions
- Process: `Docker Desktop.exe` + `com.docker.backend.exe`
- Socket: `/var/run/docker.sock` (exposed into WSL2 distros)
- Launch: `powershell.exe -Command "Start-Process 'Docker Desktop'"`
  or via Windows start menu integration
- No `open -g`, no `osascript`, no `pgrep` on process names

**Linux (native Docker Engine)**:
- No Docker Desktop needed — `dockerd` runs natively via systemd
- Socket: `/var/run/docker.sock` (standard)
- Launch: `systemctl start docker`
- Probes: `systemctl is-active docker` or `/_ping` on socket
- Or Docker Desktop for Linux (QEMU VM, same architecture as macOS)

**Actions**:
1. Add `platforms: [macos, linux, wsl2]` to `docker.yaml`
2. Abstract probes: `docker_desktop_is_running` dispatches per platform
   (pgrep on macOS, systemctl on Linux, powershell on WSL2)
3. Abstract launch: `_docker_launch` dispatches per platform
4. `docker_daemon_configured` and `docker_daemon_is_running` already
   use the socket — these are portable as-is
5. `docker-daemon` on native Linux: `driver.kind: systemd-service`
   instead of `custom`, no `docker-desktop` dependency

### Minimize exported environment size across the framework

install.sh accumulates hundreds of `_UCC_*` exported variables during
convergence (target state, evidence, runtime probes, etc.). On a full
run this reaches 500+ vars / 145+ KB. This pollutes child processes
and caused Docker Desktop to silently fail to start (com.docker.backend
crashes when inherited env is too large — confirmed 2026-04-13).

**Current workaround**: `_docker_launch` uses `env -i` to strip vars
before `open -g`. But other external processes launched via `bash -c`
(brew services, docker-compose, launchctl) inherit the same bloated
env and could hit similar limits.

**Actions**:
1. Audit `_UCC_*` exports — use shell variables (not exported) where
   the value is only needed in the current shell, not in child processes.
2. Where exports are required (cross-`bash -c` communication), unset
   them as soon as they're consumed.
3. Consider a single serialized snapshot (one var or tempfile) instead
   of hundreds of individual exports.
4. Add `env -i` or `env --unset='_UCC_*'` to all external process
   launches (brew, docker-compose, launchctl, open) as defense in depth.

**Principle**: the framework's internal bookkeeping must never leak
into external tools. Keep the exported env as small as possible.

### Phase C1 — uniform drift helper

`_ucc_yaml_parametric_observed_state` already computes drift for every
parametric target. A `_cfg_drift` helper would only matter if drivers
themselves needed to short-circuit on drift before reaching the
framework. None do. Defer until a driver actually wants this.

### `docker-privileged-ports-available` — vmnetd as a first-class target

Docker Desktop uses `com.docker.vmnetd` (a privileged LaunchDaemon)
to bind ports below 1024. Since Docker Desktop 4.15, vmnetd is NOT
installed on first launch — it's installed on-demand when a user
first enables "Allow privileged port mapping" in Settings > Advanced.
Without vmnetd, Docker shows a macOS Authorization Services dialog
that blocks startup in non-interactive mode.

The assisted install prewrite sets `RequireVmnetd: false` to suppress
this dialog (safe default — all current services use ports >= 1024).
This target would flip it to `true` and seed vmnetd when needed.

**Target:** `docker-privileged-ports-available`

```yaml
docker-privileged-ports-available:
  component: docker
  profile: configured
  type: config
  state_model: parametric
  display_name: Privileged port mapping
  depends_on:
  - docker-desktop
  - sudo-available
  driver:
    kind: custom
  observe_cmd: docker_privileged_ports_observe
  desired_cmd: docker_privileged_ports_desired
  actions:
    install: docker_privileged_ports_apply
```

**Observe** (3 conditions, all must be true for "configured"):
1. Binary exists: `/Library/PrivilegedHelperTools/com.docker.vmnetd`
2. Launchd service loaded: `launchctl list | grep -q vmnetd`
3. Settings key: `RequireVmnetd: true` in `settings-store.json`

**Action** (fix whichever condition is missing):
- Binary missing → seed from Docker.app (existing
  `_docker_assisted_seed_vmnetd` + `_docker_assisted_extract_launchd_plist`)
- Binary exists but not loaded → `launchctl bootstrap system ...`
  (fixes the broken state where binary is present but service crashed)
- `RequireVmnetd` not set → write to settings via `json_merge.py`

**Dependency pattern:** always dispatched in `run_docker_from_yaml`
(always try to enable when sudo is available). Services needing
port < 1024 add `depends_on: docker-privileged-ports-available`.

**Functions already exist:** `_docker_assisted_seed_vmnetd`,
`_docker_assisted_extract_launchd_plist` in `lib/docker_unattended.sh`.
Need new: `docker_privileged_ports_observe`,
`docker_privileged_ports_desired`, `docker_privileged_ports_apply`.

**Key discovery (2026-04-12):** the settings-store.json key that
controls the dialog is `RequireVmnetd` (found by toggling
Docker Desktop > Settings > Advanced > "Allow privileged port mapping"
and diffing the JSON).

---

### Docker Desktop — fully unattended first install on macOS

`_docker_desktop_install_and_start` currently fails fast in
non-interactive mode when Docker Desktop has not been bootstrapped on
the user account, because three independent prompts block first install
and none of them have a clean CLI bypass:

1. **brew cask install** symlinks Docker's CLI plugins into
   `/usr/local/cli-plugins/`, which prompts sudo. Cached sudo would
   normally satisfy this, but Homebrew issue
   [#17915](https://github.com/Homebrew/brew/issues/17915) makes every
   `brew` invocation invalidate the user's sudo ticket as a side effect.
2. **macOS Authorization Services Cocoa dialog** for the privileged
   helper on Docker.app's first launch. Not a sudo prompt — a separate
   subsystem that requires GUI interaction.
3. **EULA / Subscription Service Agreement dialog**. If the user does
   not accept it, Docker Desktop quits the daemon.

**Validated experimental recipe** (works end-to-end on Docker Desktop
4.68 + macOS 26 / Apple Silicon, hand-tested 2026-04-11):

1. `script -q /dev/null brew install --cask --no-binaries docker-desktop` —
   the `script` wrapper isolates brew's sudo activity in a separate pty
   so it does not invalidate the user's outer ticket. `--no-binaries`
   skips the brew `binary` stanzas. The cask's `postflight do` block
   still runs sudo for the `kubectl.docker` symlink — gracefully fails
   on a fresh pty and brew rolls back the install. (Open question: how
   to skip the postflight too. Maybe `HOMEBREW_NO_INSTALL_CLEANUP` or a
   monkey-patched cask formula?)
2. `xattr -dr com.apple.quarantine /Applications/Docker.app`
3. **Seed vmnetd manually** to bypass the Authorization Services dialog.
   The helper binary lives at
   `/Applications/Docker.app/Contents/Library/LaunchServices/com.docker.vmnetd`
   inside the bundle and is signed by Docker Inc (9BNSXJN65R). Its
   embedded `__TEXT,__launchd_plist` segment provides the LaunchDaemon
   plist (extract via Python `find b'<?xml' / b'</plist>'`). Copy
   binary to `/Library/PrivilegedHelperTools/com.docker.vmnetd`
   (`root:wheel 0755`) and write the plist (with `ProgramArguments`
   added — Docker's embedded version omits it because SMJobBless
   injects the path automatically) to
   `/Library/LaunchDaemons/com.docker.vmnetd.plist` (`root:wheel 0644`),
   then `sudo launchctl bootstrap system /Library/LaunchDaemons/com.docker.vmnetd.plist`.
   Docker Desktop's SMJobBless `is helper installed and valid?` check
   then passes and the Cocoa dialog never appears. After Docker is up,
   it discards the seeded helper because Docker 4.x on Apple Silicon
   actually uses `com.docker.helper` at the user launchd domain, not
   vmnetd at the system domain — so the seed is theatre that satisfies
   the legacy SMJobBless check and is then garbage-collected.
4. **Pre-write the EULA acceptance** to
   `~/Library/Group Containers/group.com.docker/settings-store.json`
   before launching Docker.app. The three keys that flip on EULA
   accept (verified by before/after diff):
   ```json
   "DisplayedOnboarding": true,
   "LicenseTermsVersion": 2,
   "ShowInstallScreen": false
   ```
   Use `tools/drivers/json_merge.py` to add them without touching the
   other settings.
5. `open -a /Applications/Docker.app` — daemon comes up in seconds,
   no dialogs, no prompts. (Original hand-test on 2026-04-11 used
   `open -g -a`, which worked there because vmnetd was already
   seeded so Docker had no dialog to show. But commit `f08328e`
   later proved `-g` silently returns 0 without actually starting
   Docker on Apple Silicon in the general case — Docker's
   launchd-managed inner bundle does not activate under background
   open. Use plain `open -a` in the implementation to match what
   `_docker_launch` in `lib/docker.sh` already does.)

Wire this up as an opt-in path behind a preference (default = current
conservative gate). The recipe touches `/Library/PrivilegedHelperTools`
and `/Library/LaunchDaemons` with sudo, depends on Docker.app's
internal layout, and could break with any Docker Desktop release —
opt-in for users who actually need unattended setup (CI, fleet
provisioning) and accept the maintenance cost.

Bootstrap detection lives in `_docker_bootstrap_complete` (checks
`LicenseTermsVersion` in settings-store.json). Use the same probe as
the bypass condition for any future variant.

#### Existing lib functions to reuse (2026-04-11 bootstrap recovery)

The Docker bootstrap recovery work yesterday added several helpers
to `lib/docker.sh` that the assisted-install path should call directly
instead of reimplementing. Listed here so the implementation session
finds them:

| Function | Purpose | Commit |
|---|---|---|
| `_docker_bootstrap_complete` | Check `LicenseTermsVersion` in `settings-store.json` — reads `settings_relpath` from YAML | `5a79a42` / `fce0367` |
| `_docker_strip_quarantine "$app_path"` | Run `xattr -dr com.apple.quarantine` recursively on the bundle | `ba8f095` |
| `_docker_launch` | `env -i` + `nohup open -g` + `/_ping` socket readiness poll (30s). Reads `app_path`/`app_name` from YAML. 500-state pre-check via `/info` on socket | `f08328e` / `0cea1a6` |
| `_docker_kill_zombies "$pattern" "$app_name"` | `osascript quit` + `pkill` fallback. Accepts `app_name` param | `fce0367` |
| `_docker_settings_store_patch "$relpath"` | Write silent-start flags to `settings-store.json` | `71c2dee` |
| `docker_desktop_observe` | Checks app directory existence — reads `docker_desktop_app_path` from YAML | `813aa78` / `fce0367` |
| `docker_desktop_is_running` | `pgrep` on `docker_desktop_process` from YAML | `fce0367` |
| `docker_desktop_pid` | PID of root process (was `docker_daemon_pid` — renamed, daemon has no host PID) | `fce0367` |
| `docker_daemon_configured` | Checks socket existence (`~/.docker/run/docker.sock`) instead of `command -v docker` | `fce0367` |
| `docker_daemon_is_running` | `curl /_ping` on socket (was `docker info` — PATH-dependent) | `0cea1a6` |
| `docker_version` | `curl /version` on socket (was `docker --version` — PATH-dependent) | `0cea1a6` |
| `_docker_ready` | `curl /_ping` on socket with `docker ps` fallback | `fce0367` |

The assisted-install orchestrator should call these helpers rather
than rolling its own `open -a` / `xattr` / `pkill` / `defaults write`
sequences. They're all in `lib/docker.sh` and already sourced by
every install.sh run.

**Not a driver, a lib.** The planned file is `lib/docker_unattended.sh`,
not `lib/drivers/docker_unattended.sh`. It's a helper library called
from within `_docker_desktop_install_and_start` (in `lib/docker.sh`)
when `UIC_PREF_DOCKER_FIRST_INSTALL=assisted`. It does NOT declare a
new `driver.kind`. Consequences:

- No entry needed in `DRIVER_SCHEMA` or `KNOWN_*_DRIVERS` sets.
- No entry needed in `tests/test_driver_smoke.py::FAKE_DRIVER_FIELDS`.
- `docs/driver-feature-matrix.md` does not gain a row (and therefore
  no doc regen is required just for this file).
- Sourced from `lib/ucc.sh` after `lib/docker.sh` in the same block.

**Implementation-time constraint — pre-commit hook.** Since
`2026-04-11`, every commit on this repo runs through
`tools/check-bgs.sh` via `~/.git-hooks/pre-commit`. That runs
`build-driver-matrix.py --check` + `build-spec.py --check` and blocks
commits with drift. Implementation commits that touch `ucc/software/docker.yaml`
(e.g., to add the `docker-first-install` preference) will trip
`build-spec.py --check` if the preference table isn't regenerated.
Plan the commit shape accordingly: either regen docs in the same
commit or split "add preference" into its own commit that also
regenerates the spec.

#### Implementation plan

**Preference (`ucc/software/docker.yaml`)**

Add to the `preferences:` block:
```yaml
- name: docker-first-install
  default: manual
  options: manual|assisted
  rationale: manual fails fast in non-interactive mode and requires the
    user to bootstrap Docker once interactively (sudo + macOS auth dialog
    + EULA accept); assisted runs the experimental recipe that pre-writes
    EULA settings, seeds vmnetd to bypass the auth dialog, and uses a
    SUDO_ASKPASS shim so brew's sudo calls succeed non-interactively
```

Read in code as `UIC_PREF_DOCKER_FIRST_INSTALL` (existing convention).

**Password sourcing**

The recipe needs sudo. Three sources, in order:
1. `UCC_SUDO_PASS` env var (CI / scripted use).
2. Interactive prompt via `read -s` from `/dev/tty` (interactive operator).
3. Fail with a clear message naming both options.

Never log the password. Never write it to a process arg. Store it in a
mode-0600 temp file under `mktemp -d` with mode 0700, deleted on EXIT
trap (with `dd if=/dev/zero` overwrite first).

**SUDO_ASKPASS — native brew support, no PATH shim required**

An earlier draft of this plan assumed brew's internal sudo calls did
not pass `-A`, which would have required a PATH-shadowed wrapper
around `sudo`. A 2026-04-12 static analysis of Homebrew's source code
(`Library/Homebrew/system_command.rb`, the `sudo_prefix` method used
by every internal brew sudo call) showed the opposite: **brew already
injects `-A` automatically** when `SUDO_ASKPASS` is set in the
environment.

The relevant Homebrew code:
```ruby
def sudo_prefix
  askpass_flags = ENV.key?("SUDO_ASKPASS") ? ["-A"] : []
  # ...
  ["/usr/bin/sudo", *user_flags, *askpass_flags, "-E", *env_args, "--"]
end
```

Important details:

1. Homebrew uses the **hardcoded absolute path** `/usr/bin/sudo`. A
   PATH-shadowing wrapper would NOT be intercepted. This is why the
   original draft plan would have failed if implemented.
2. Homebrew **auto-adds `-A`** to the sudo invocation when
   `SUDO_ASKPASS` is present in the environment. That's exactly the
   behavior we need: sudo with `-A` reads the askpass helper from
   `SUDO_ASKPASS` and invokes it instead of prompting the terminal.
3. Homebrew always passes `-E` in the prefix, which preserves the
   invoking user's environment through the sudo call (so
   `HOMEBREW_*` and other env vars still reach whatever runs under
   sudo).
4. Cask postflight `do` blocks run in the same brew Ruby process and
   go through the same `SystemCommand` → `sudo_prefix` path, so the
   kubectl symlink postflight ALSO benefits from the auto-`-A`.
5. `sudo` reads `SUDO_ASKPASS` from the outer user's env at startup
   (before its own env_reset runs), so no sudoers `env_keep +=
   SUDO_ASKPASS` configuration is required.

**Simplified setup**. Just write a mode-0600 password file and a
mode-0755 askpass helper that cats the file, then export one env var:

```bash
# Password file (mode 0600, bc-owned)
printf '%s' "$password" > "$workdir/pass"
chmod 600 "$workdir/pass"

# Askpass helper (executable, NOT setuid — sudo refuses setuid askpass)
cat > "$workdir/askpass.sh" <<EOF
#!/bin/bash
cat "$workdir/pass"
EOF
chmod 755 "$workdir/askpass.sh"

# Single env var — no PATH manipulation
export SUDO_ASKPASS="$workdir/askpass.sh"
```

After that, any `brew install --cask ...` invocation under this
environment gets auto-wrapped by brew as
`/usr/bin/sudo -A -E -- <brew's real command>`, which reads the
askpass helper for the password and proceeds non-interactively.

**What this retires from the earlier design**:

- No `$WORKDIR/sudo` wrapper file
- No `PATH="$WORKDIR:$PATH"` prepend
- No "Open question: validate brew uses PATH-resolved sudo" risk
- No need for a separate `expect` / sudoers patch fallback

**File layout**

New file `lib/docker_unattended.sh`. Sourced from `lib/ucc.sh` next to
`lib/docker.sh`. Functions:

- `_docker_assisted_install` — top-level orchestrator. Returns 0 on
  full success or non-zero with a logged warning. Steps:
  1. Read YAML vars (`docker_desktop_cask_id`, `docker_desktop_app_path`,
     `settings_relpath`).
  2. Get password via `_docker_assisted_get_password`.
  3. Set up workdir + askpass helper via `_docker_assisted_setup_askpass`,
     export `SUDO_ASKPASS`, install EXIT trap to shred + unlink on
     any exit (normal, error, SIGINT). No PATH manipulation — brew's
     `sudo_prefix` auto-adds `-A` when it sees `SUDO_ASKPASS`.
  4. `sudo -A -v` to validate the password before doing real work.
  5. `_docker_assisted_prewrite_eula` — write the three EULA keys to
     `settings-store.json` (creating the parent directory if missing,
     merging into existing file via `tools/drivers/json_merge.py`).
  6. `brew install --cask docker-desktop` — relies on the shim.
  7. `_docker_strip_quarantine` (already exists in `lib/docker.sh`).
  8. `_docker_assisted_seed_vmnetd` — extract embedded launchd plist
     from the helper Mach-O, copy binary + write plist to /Library
     with the correct ownership/perms, `launchctl bootstrap`.
  9. `open -a /Applications/Docker.app` (NOT `-g` — we proved on
     2026-04-11 that `-g` returns 0 without actually starting Docker
     on Apple Silicon; use plain foreground launch).
 10. Poll `~/.docker/run/docker.sock` (max 90s, 2s intervals).
 11. Verify by running `/Applications/Docker.app/Contents/Resources/bin/docker version`.
- `_docker_assisted_get_password` — env var → tty prompt → fail.
- `_docker_assisted_setup_askpass` — write password file +
  askpass helper, export `SUDO_ASKPASS`.
- `_docker_assisted_prewrite_eula` — JSON merge.
- `_docker_assisted_seed_vmnetd` — extract+copy+bootstrap.
- `_docker_assisted_cleanup` — wipe workdir on EXIT trap.

**Helper function sketches**

These are not final code — they're starting points sized so the next
session can paste them in and iterate.

```bash
# Three sources, in order: UCC_SUDO_PASS env > interactive read -s > fail.
_docker_assisted_get_password() {
  if [[ -n "${UCC_SUDO_PASS:-}" ]]; then
    printf '%s' "$UCC_SUDO_PASS"
    return 0
  fi
  if [[ "${UCC_INTERACTIVE:-1}" == "1" && -r /dev/tty ]]; then
    local _p
    printf 'sudo password for assisted Docker install: ' >/dev/tty
    IFS= read -r -s _p </dev/tty
    printf '\n' >/dev/tty
    [[ -n "$_p" ]] || { log_warn "empty password"; return 2; }
    printf '%s' "$_p"
    return 0
  fi
  log_warn "Assisted install needs UCC_SUDO_PASS env var in non-interactive mode"
  return 2
}

# Set up askpass helper + mode-0600 password file, export SUDO_ASKPASS.
# Brew's internal sudo calls auto-add -A when SUDO_ASKPASS is set, so
# no PATH-shadowing sudo wrapper is needed. (Verified 2026-04-12 via
# static analysis of Homebrew's Library/Homebrew/system_command.rb
# sudo_prefix method.)
# Caller captures the workdir path and installs the EXIT trap.
_docker_assisted_setup_askpass() {
  local password="$1"
  local workdir; workdir="$(mktemp -d)" || return 1
  chmod 700 "$workdir"
  printf '%s' "$password" > "$workdir/pass"
  chmod 600 "$workdir/pass"
  cat > "$workdir/askpass.sh" <<ASKPASS
#!/bin/bash
cat "$workdir/pass"
ASKPASS
  chmod 755 "$workdir/askpass.sh"
  export SUDO_ASKPASS="$workdir/askpass.sh"
  printf '%s' "$workdir"
}

# Called from EXIT trap. Overwrite the password file before unlinking
# so the password never sits on disk after the run.
_docker_assisted_cleanup() {
  local workdir="$1"
  [[ -n "$workdir" && -d "$workdir" ]] || return 0
  if [[ -f "$workdir/pass" ]]; then
    dd if=/dev/zero of="$workdir/pass" bs=1 count="$(wc -c < "$workdir/pass")" 2>/dev/null || true
  fi
  rm -rf "$workdir"
}

# Merge the three EULA-acceptance keys into settings-store.json using
# the existing tools/drivers/json_merge.py helper. Creates the file if
# it does not exist yet.
_docker_assisted_prewrite_eula() {
  local settings_path="$1"
  mkdir -p "$(dirname "$settings_path")"
  [[ -f "$settings_path" ]] || printf '%s\n' '{}' > "$settings_path"
  local patch_dir="$CFG_DIR/.build"
  mkdir -p "$patch_dir"
  local patch="$patch_dir/docker-eula-patch.json"
  cat > "$patch" <<'JSON'
{
  "LicenseTermsVersion": 2,
  "DisplayedOnboarding": true,
  "ShowInstallScreen": false
}
JSON
  python3 "$CFG_DIR/tools/drivers/json_merge.py" apply "$settings_path" "$patch"
}

# Extract the launchd plist embedded in the vmnetd binary, copy both
# files into /Library, and launchctl-bootstrap the daemon.
_docker_assisted_seed_vmnetd() {
  local bin_src="/Applications/Docker.app/Contents/Library/LaunchServices/com.docker.vmnetd"
  local bin_dst="/Library/PrivilegedHelperTools/com.docker.vmnetd"
  local plist_dst="/Library/LaunchDaemons/com.docker.vmnetd.plist"
  [[ -f "$bin_src" ]] || { log_warn "vmnetd binary not found at $bin_src"; return 1; }

  # The Info.plist fields embedded in the binary identify Docker Inc as
  # the signer (certificate leaf subject CN = "Developer ID Application:
  # Docker Inc (9BNSXJN65R)"). Verify that the running binary still
  # matches before seeding — protects against Docker Inc rotating
  # signing identities in a future release.
  codesign -v --strict "$bin_src" || { log_warn "vmnetd signature invalid"; return 1; }

  # Scan the helper Mach-O for its embedded launchd_plist segment. The
  # binary contains two XML plists: the helper's Info.plist (identified
  # by CFBundleIdentifier) and the launchd plist (identified by Label
  # and MachServices/Sockets, no CFBundleIdentifier). Use Python to
  # find and extract the second one.
  local launchd_plist
  launchd_plist="$(python3 - "$bin_src" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
i = 0
while True:
    s = data.find(b'<?xml', i)
    if s < 0: break
    e = data.find(b'</plist>', s)
    if e < 0: break
    e += len(b'</plist>')
    chunk = data[s:e].decode('utf-8', errors='replace')
    if 'Label' in chunk and 'CFBundleIdentifier' not in chunk:
        sys.stdout.write(chunk)
        sys.exit(0)
    i = e
sys.exit(1)
PY
  )" || { log_warn "failed to extract vmnetd launchd plist"; return 1; }

  sudo -A install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools /Library/LaunchDaemons
  sudo -A cp "$bin_src" "$bin_dst"
  sudo -A chown root:wheel "$bin_dst"
  sudo -A chmod 755 "$bin_dst"
  printf '%s' "$launchd_plist" | sudo -A tee "$plist_dst" >/dev/null
  sudo -A chown root:wheel "$plist_dst"
  sudo -A chmod 644 "$plist_dst"
  sudo -A launchctl bootstrap system "$plist_dst" 2>&1 || true
  # bootstrap is idempotent-ish but can fail if already loaded; that's
  # fine, the existing daemon is the one we want.
}
```

**Dispatch (`lib/docker.sh`)**

In `_docker_desktop_install_and_start`, before the existing gate:
```bash
if ! _docker_bootstrap_complete; then
  case "${UIC_PREF_DOCKER_FIRST_INSTALL:-manual}" in
    assisted)
      _docker_assisted_install || return $?
      return 0
      ;;
    manual|*)
      # ... existing gate (fail in non-interactive, info-log in interactive)
      ;;
  esac
fi
```
Keeps the default path 100% unchanged.

**Open issues / risks**

1. **kubectl postflight** — `brew install --cask docker-desktop` runs
   a `postflight do` block that tries to symlink `kubectl.docker` into
   `/usr/local/bin/`. ~~With the SUDO_ASKPASS shim, the postflight's
   sudo call should succeed. **Untested.**~~ **Update 2026-04-12**:
   static analysis of Homebrew's `Library/Homebrew/system_command.rb`
   confirmed that cask postflight `do` blocks go through the same
   `SystemCommand` → `sudo_prefix` path as other brew sudo calls, and
   the prefix auto-adds `-A` when `SUDO_ASKPASS` is set. So the
   kubectl postflight's sudo call should be intercepted by our
   askpass helper automatically, same as the CLI-plugins symlinks.
   Still needs end-to-end confirmation on the Mac mini in Test 3 of
   the test plan, but the mechanism is in place.
2. **vmnetd code-signing churn** — if Docker Inc changes the signing
   identity, the seeded helper's signature won't match Docker.app's
   `SMPrivilegedExecutables` requirement and SMJobBless will reject it.
   We should `codesign -d -r-` the helper at runtime and compare it
   to the requirement string in `Info.plist`, falling back to the
   manual path if they don't match.
3. **Embedded plist parsing** — relies on finding `<?xml` and
   `</plist>` markers in the Mach-O `__TEXT,__launchd_plist` segment,
   distinguishing the launchd plist from the helper's `Info.plist`
   (filter on presence of `Label` and absence of `CFBundleIdentifier`).
   Brittle if Docker changes the segment layout. Better to use
   `otool -X -s __TEXT __launchd_plist` and parse the hex.
4. **EULA `LicenseTermsVersion` value** — currently `2`. Will Docker
   bump this in a future version, expecting users to re-accept? If
   yes, our pre-write becomes stale and the EULA dialog reappears.
   Mitigation: read the value from a Docker-published source if
   available, or refresh on every assisted run.
5. **`com.docker.helper` user-domain agent** — modern Docker uses
   this instead of system-domain vmnetd. Our seed satisfies the legacy
   SMJobBless check and is then garbage-collected. If Docker drops the
   SMJobBless code path entirely in a future version, our seed becomes
   irrelevant — but the dialog might also disappear, in which case
   the assisted path can drop step (8) entirely.
6. **Settings JSON merge** — `tools/drivers/json_merge.py` is used
   elsewhere; reuse it. If `settings-store.json` does not exist yet
   (fresh install), we create the parent dir and the file with just
   the three keys. Docker writes the rest on first launch, merging.
7. **Password security** — temp file is mode 0600, dir is 0700,
   deleted on EXIT (including SIGINT/SIGTERM). Acceptable for an
   opt-in advanced flow but document the trade-off.

**Test plan**

Validation runs on a clean Mac mini after each cleanup:

1. `UIC_PREF_DOCKER_FIRST_INSTALL=manual` + non-interactive →
   gate fires, no work done. (Regression check.)
2. `UIC_PREF_DOCKER_FIRST_INSTALL=manual` + interactive → manual
   path runs, all three dialogs appear, user clicks through. (Regression
   check.)
3. `UIC_PREF_DOCKER_FIRST_INSTALL=assisted` + interactive →
   ONE password prompt at start, then no further interaction; Docker
   daemon up; `docker version` works.
4. `UIC_PREF_DOCKER_FIRST_INSTALL=assisted` +
   `UCC_SUDO_PASS=...` + non-interactive → ZERO interaction; Docker
   daemon up; `docker version` works.
5. `UIC_PREF_DOCKER_FIRST_INSTALL=assisted` + non-interactive
   without `UCC_SUDO_PASS` → fails clean with a clear "set
   `UCC_SUDO_PASS` or run interactively" message.
6. `UIC_PREF_DOCKER_FIRST_INSTALL=assisted` + WRONG password →
   fails at the `sudo -A -v` validation step before any real work; no
   side effects on disk.
7. After a successful assisted run, re-run `--no-interactive
   docker-desktop` → `_docker_bootstrap_complete` returns true, gate
   skipped, daemon already running, no-op `[ok]`.

**Per-step rollback** (if the assisted install fails mid-way, clean up
only the artifacts produced up to the failure point — avoids a full
wipe when a later step trips):

| Failed at | Cleanup commands |
|---|---|
| Step 4 (`sudo -A -v`) | Nothing to clean. Wrong password rejected before any write. |
| Step 5 (pre-write EULA) | `rm -f ~/Library/Group Containers/group.com.docker/settings-store.json` if we created it; or `git checkout $PATCH_BACKUP` if we backed it up first |
| Step 6 (`brew install`) | `brew uninstall --cask docker-desktop 2>/dev/null \|\| true` |
| Step 7 (strip quarantine) | No cleanup needed (xattr removal is safe) |
| Step 8 (seed vmnetd) | `sudo launchctl bootout system/com.docker.vmnetd 2>/dev/null`; `sudo rm -f /Library/LaunchDaemons/com.docker.vmnetd.plist /Library/PrivilegedHelperTools/com.docker.vmnetd` |
| Step 9 (`open -a`) | `osascript -e 'quit app "Docker"' 2>/dev/null` |
| Step 10 (socket poll timeout) | Step 8 cleanup above; also kill Docker.app: `pkill -f 'com\.docker' 2>/dev/null` |

**Full teardown** (if none of the above work or user wants a clean
slate) — same sequence used by the cleanup script at the top of this
plan entry:

```bash
osascript -e 'quit app "Docker"' 2>/dev/null || true
pkill -f 'com\.docker' 2>/dev/null || true
brew uninstall --cask --zap docker-desktop 2>/dev/null || true
sudo launchctl bootout system/com.docker.vmnetd 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/com.docker.vmnetd.plist
sudo rm -f /Library/PrivilegedHelperTools/com.docker.vmnetd
sudo rm -f /Library/PrivilegedHelperTools/com.docker.socket
rm -rf ~/Library/Group\ Containers/group.com.docker
rm -rf ~/Library/Containers/com.docker.docker
rm -rf ~/Library/Containers/com.docker.helper
rm -rf ~/.docker
rm -rf ~/Library/Application\ Support/Docker\ Desktop
rm -f  ~/Library/Preferences/com.docker.docker.plist
rm -rf ~/Library/Caches/com.docker.docker
rm -rf ~/Library/LaunchAgents/com.docker*
```

**Estimated effort**

- New `lib/docker_unattended.sh`: ~150 lines.
- Dispatch in `lib/docker.sh`: ~10 lines.
- Preference entry in `docker.yaml`: 4 lines.
- Source line in `lib/ucc.sh`: 1 line.
- Test cycles on the Mac mini: 6-8 clean+install runs.

Realistically: implement in one focused session, test in another. Do
not start without a clean Docker uninstall and a way to revert `/Library`
state if seeding goes wrong (`launchctl bootout system/com.docker.vmnetd
&& sudo rm /Library/PrivilegedHelperTools/com.docker.vmnetd
/Library/LaunchDaemons/com.docker.vmnetd.plist`).

#### Execution plan (commit-by-commit)

Split the implementation into 11 concrete steps, interleaved with
**three Mac mini checkpoints** (A/B/C) so we validate early and don't
stack 6 commits of unverified code before the first runtime test. Steps
2-7 commit real code; Step 0 is a pre-flight gate; Steps 1, 9, 10 are
book-ends.

| Step | Work | Environment | Commit? |
|---|---|---|---|
| 0 | Pre-flight: validate `SUDO_ASKPASS` shim intercepts brew's sudo calls | WSL (static analysis of Homebrew source) | No |
| 1 | Baseline capture: pytest green, validator clean, git state clean, scout docker.yaml preferences block shape + json_merge.py interface | WSL | No |
| 2 | Add `docker-first-install` preference to `ucc/software/docker.yaml`, regenerate `docs/SPEC.md` | WSL | ✅ Commit 1 |
| **A** | **Mac mini Checkpoint A — sanity check.** User runs `./install.sh --no-interactive docker-desktop` and pastes the [docker] + [PREF] sections. Confirms: (a) the new preference is visible in the PREF report, (b) default `manual` is selected, (c) existing Docker behavior is unchanged (no regressions from adding the YAML entry). ~2 min on Mac mini. | Mac mini | No |
| 3 | New `lib/docker_unattended.sh` with three helpers: `_docker_assisted_get_password`, `_docker_assisted_setup_askpass`, `_docker_assisted_cleanup`. Source from `lib/ucc.sh`. Add `tests/test_docker_unattended.py` with ~5 WSL-runnable unit tests (env-var path, tty-absent failure, askpass creates expected files with correct perms, cleanup wipes + removes workdir, cleanup is idempotent). | WSL | ✅ Commit 2 |
| 4 | Add `_docker_assisted_prewrite_eula` helper. Add 2-3 tests (creates file if missing, merges into existing file preserving other keys, 3 required keys end up set). | WSL | ✅ Commit 3 |
| 5 | Add `_docker_assisted_seed_vmnetd` helper. Python extraction logic is partially WSL-testable (run the `<?xml>`/`</plist>` scan against a canned sample); the `sudo cp` + `launchctl bootstrap` steps are Mac-mini-only. Commit with an explicit "unverified end-to-end on Mac mini until Checkpoint C" note in the message. | WSL (extraction only) | ✅ Commit 4 |
| 6 | Add `_docker_assisted_install` top-level orchestrator. Delegates to the existing `lib/docker.sh` helpers (`_docker_strip_quarantine`, `_docker_launch`) wherever possible. No standalone tests — orchestration is tested end-to-end on the Mac mini. | WSL (static only) | ✅ Commit 5 |
| 7 | Wire dispatch in `lib/docker.sh`. Add the `UIC_PREF_DOCKER_FIRST_INSTALL=assisted` branch to `_docker_desktop_install_and_start` before the existing gate. ~10 LOC. bash -n + pytest + hook validate, but runtime behavior only meaningfully testable on Mac mini. | WSL | ✅ Commit 6 |
| **B** | **Mac mini Checkpoint B — regression check.** User runs `./install.sh --no-interactive docker-desktop` (still with default `manual` pref). Confirms: the `assisted` branch is fully inert when the pref is `manual` — no change in existing Docker behavior, no stray askpass files, no permissions surprises. ~2 min on Mac mini. | Mac mini | No |
| — | **STOP HERE. HAND OFF TO MAC MINI for Checkpoint C.** WSL work complete. | — | — |
| **C** | **Mac mini Checkpoint C — full matrix.** 7 tests from the "Test plan" section, each from a fully-clean Docker state, with `UIC_PREF_DOCKER_FIRST_INSTALL=assisted`. Total ~45-60 min on Mac mini. User runs; Claude reads paste and diagnoses per test. | Mac mini | No |
| 9 | Triage and fix any test failures from Checkpoint C. Each failure = 1-2 more commits. Expected iterations: 0-3. | WSL (code) + Mac mini (verify) | ✅ Commits 7+ |
| 10 | Move Docker Desktop unattended entry from Open to Closed in `docs/PLAN.md`. Final commit. | WSL | ✅ Final commit |

**WSL work (Steps 2-7)**: ~6 commits, ~2-3 hours of focused work, no
Mac mini required. Every commit passes through the pre-commit hook.

**Mac mini handoffs**: three short checkpoints instead of one long
test matrix. Checkpoint A (~2 min) catches YAML/pref regressions
before we stack 5 more commits. Checkpoint B (~2 min) catches any
`manual`-path regression introduced by the dispatch wiring. Checkpoint
C (~45-60 min) is the end-to-end `assisted`-path validation.

**Abort criteria** (stop and check with the user if any of these
happen):

1. Checkpoint A surfaces any PREF/validator regression from the YAML
   edit — roll back Commit 1, don't proceed to Step 3.
2. Step 5 vmnetd extraction fails on WSL partial test — the Python
   logic can't find the plist in a real vmnetd binary extracted from
   an earlier Mac mini session. May mean Docker changed the Mach-O
   layout since 2026-04-11.
3. Checkpoint B shows the `manual`-path has regressed — the dispatch
   wiring leaked. Roll back Commit 6, reinspect Step 7.
4. Checkpoint C Test 4 (the "true non-interactive with `UCC_SUDO_PASS`"
   test) fails twice in a row even after Step 9 iteration — we're
   chasing a moving target.
5. Any Checkpoint C test accidentally breaks the Mac mini's existing
   working Docker install — roll back immediately, do not proceed.
6. Step 9 exceeds 3 iterations — the approach isn't converging,
   take a break and re-plan.

#### Step 9 triage findings (2026-04-12, 15 iterations)

Key discoveries during Checkpoint C testing:

- **`RequireVmnetd`** is the `settings-store.json` key controlling
  the privileged port dialog (found by toggling Docker Desktop >
  Settings > Advanced > "Allow privileged port mapping" and diffing
  JSON). Setting `RequireVmnetd: false` suppresses the dialog.
- **Docker Desktop 4.15+** does NOT install vmnetd on first launch
  (principle of least privilege). vmnetd is on-demand only, for
  ports < 1024.
- **`docker info` hangs** for 30s+ during Docker startup (CLI plugin
  enumeration blocks on socket). `docker ps -q` returns instantly.
- **`open -g -a /path`** puts Docker in a stuck 500 state.
  `open -g /path` (bundle direct, no `-a`) works reliably.
- **`osascript quit "Docker"` ≠ `osascript quit "Docker Desktop"`** —
  only the latter cleanly stops Docker Desktop. The shorter name
  leaves a persistent 500 error state.
- **~~`~/.docker/run/docker.sock` does not exist~~** — CORRECTED
  2026-04-13: the socket DOES exist on Docker Desktop 4.68 / Apple
  Silicon. Verified via `curl --unix-socket ~/.docker/run/docker.sock
  http://localhost/_ping` → `OK`. All probes now use this socket
  directly (`/_ping`, `/version`, `/info`) instead of the docker CLI.
- **EULA prewrite now writes 5 keys**: `LicenseTermsVersion`,
  `DisplayedOnboarding`, `ShowInstallScreen`,
  `OpenUIOnStartupDisabled`, `RequireVmnetd`.

#### Step 11 — `docker-privileged-ports-available` target

vmnetd seeding should be a first-class UCC target, not embedded
in the assisted orchestrator. Design:

```yaml
docker-privileged-ports-available:
  component: docker
  profile: configured
  type: config
  state_model: parametric
  display_name: Privileged port mapping
  depends_on:
  - docker-desktop
  - sudo-available
  driver:
    kind: custom
  observe_cmd: docker_privileged_ports_observe
  desired_cmd: docker_privileged_ports_desired
  actions:
    install: docker_privileged_ports_apply
```

**Two auto conditions** (both handled by the dependency graph):
1. **Consumer needs it** — service target with port < 1024 adds
   `depends_on: docker-privileged-ports-available`
2. **Sudo is available** — target depends on `sudo-available`

No consumer + no sudo → target skipped.
Consumer + sudo → vmnetd seeded, `RequireVmnetd: true` written.

**Observe** (3 conditions, all must be true):
1. Binary exists: `/Library/PrivilegedHelperTools/com.docker.vmnetd`
2. Launchd service loaded: `launchctl list | grep -q vmnetd`
3. Settings key: `RequireVmnetd: true` in `settings-store.json`

**Action** (fix whichever condition is missing):
- Binary missing → seed (existing `_docker_assisted_seed_vmnetd`)
- Binary exists but not loaded → `launchctl bootstrap system ...`
- `RequireVmnetd` not set → write via `json_merge.py`

**Functions already exist**: `_docker_assisted_seed_vmnetd`,
`_docker_assisted_extract_launchd_plist` in `lib/docker_unattended.sh`.
**Need new**: `docker_privileged_ports_observe`,
`docker_privileged_ports_desired`, `docker_privileged_ports_apply`.

**Prewrite keeps `RequireVmnetd: false`** — safe default for
headless launch. This target flips it to `true` when needed.

#### Step 12 — Separate docker-desktop (app install) from docker-daemon (daemon lifecycle) — ✅ DONE 2026-04-13

Implemented differently from the original design but achieves the same
separation of concerns:

```yaml
docker-desktop:       # install: _docker_desktop_install (brew cask + settings + launch)
docker-daemon:        # install: _docker_daemon_start (nohup open -g + /_ping readiness)
docker-available:     # capability: probe socket
docker-resources:     # parametric: settings-store.json
```

**Key changes (commits fce0367..0cea1a6):**
- `_docker_desktop_install` does brew cask + settings patch + launch
  via `_docker_launch` (clean env with `env -i`)
- `_docker_daemon_start` handles daemon start independently
- All probes switched from docker CLI (PATH-dependent) to socket-based
  (`curl /_ping`, `/version`, `/info`)
- All hardcodes eliminated — values read from YAML
- `docker_daemon_pid` renamed `docker_desktop_pid` (PID is Desktop's
  root process, not the daemon which runs in the VM)
- `docker_daemon_configured` checks socket existence instead of
  `command -v docker`
- Process architecture and shutdown cascade timings documented in
  `lib/docker.sh` header (verified by kill tests on Apple Silicon)

**Root cause of the 20s-quit bug:** Docker Desktop silently fails when
the inherited environment exceeds ~145 KB (hundreds of `_UCC_*` exports
accumulated during install.sh). Fixed by launching with `env -i HOME PATH`.

### Dry-run ordering: `pyenv init` runs before pyenv exists

**Symptom (dry-run on WSL where pyenv is not yet installed):**

```
/home/bc/repos/github/bonomani/mac-mini-setup/lib/pip_group.sh: line 157: pyenv: command not found
```

**This is not just a redirection bug — it's a dry-run/dependency
contract violation.** The visible stderr line is the tip; the real
issue is that dry-run silently breaks the implicit ordering contract
between targets in the same lib function.

**The sequence in `lib/pip_group.sh:153-158`:**

```bash
ucc_yaml_simple_target "$cfg_dir" "$yaml" "pyenv"    # (1) install pyenv
ucc_yaml_simple_target "$cfg_dir" "$yaml" "xz"
export PYENV_ROOT="$HOME/$_PYENV_DIR"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)" 2>/dev/null || true           # (2) activate pyenv
ucc_yaml_simple_target "$cfg_dir" "$yaml" "python"   # (3) uses pyenv
```

The code assumes a hard chain `pyenv → python`:
1. (1) materializes the binary.
2. (2) activates it in the current shell.
3. (3) observes/installs python via pyenv.

**Install mode:** works — (1) actually installs, so (2) finds pyenv on PATH.

**Dry-run mode:** (1) is a no-op (`[dry-run]` marker only, nothing
installed). (2) then calls a non-existent binary. Bash emits
`pyenv: command not found` during the `$(...)` command substitution —
the `2>/dev/null` on `eval` does **not** suppress it, because the
message is produced by bash before `eval` is invoked.

Then (3) runs against a shell that doesn't have pyenv on PATH. It
*happens* to print the right-looking `Absent → Configured` transition
(no pyenv → looks Absent), but any finer observation (version match,
virtualenv presence) would be wrong. Every pip-group target
downstream of pyenv inherits this broken shell state.

**Two layers to fix:**

1. **Narrow fix (stops stderr + unblocks dry-run of this file):**
   guard the init call with `command -v`:

   ```bash
   if command -v pyenv >/dev/null 2>&1; then
     eval "$(pyenv init -)"
   fi
   ```

   Preferred over redirect-hiding because it also avoids silently
   masking real `pyenv init` failures when pyenv *is* installed but
   misconfigured.

2. **Declare the missing dependency edges** (root cause): the
   pattern "install A → raw bash glue → install B" only exists in the
   first place because the `pyenv → python` edge is **hidden in the
   YAML**. Trace what's currently declared:

   | Target | Declared `depends_on` | Actually needs |
   |---|---|---|
   | `pyenv` | *(none)* | `homebrew` — implicit, driver is `pyenv-brew` |
   | `python` | `xz` | `xz` **+ `pyenv`** — `pyenv` hidden in `backends: [pyenv: ${python_version}]` |

   Direction note: `python` depends on `pyenv`, not the reverse.
   pyenv is a bash tool that *installs* Python (same relationship as
   `nvm → node`). It does not need Python to run.

   **Fix — add the missing edges explicitly:**

   ```yaml
   pyenv:
     depends_on: [homebrew]
   python:
     depends_on: [xz, pyenv]
   ```

   Once the graph is complete, the inline `eval "$(pyenv init -)"` in
   `pip_group.sh` between the two targets becomes **unnecessary** —
   the framework's dependency-ordered processing guarantees pyenv is
   observed (and in non-dry-run: installed + activated) before
   `python` is reached. The activation step, if still needed, moves
   into the `pyenv` driver's own post-install hook, not into a caller
   lib function.

3. **Framework rule (prevents recurrence):** with the edges declared,
   codify the rule: **lib functions must not place raw bash between
   `ucc_yaml_simple_target` calls that assumes a prior target
   materialized — declare the dependency in YAML instead.** The
   dependency graph is the source of truth for ordering; imperative
   glue code in lib functions is a smell.

   Optional framework enhancement: have the `pkg` driver recognize
   when `backends:` references another target name (e.g.
   `backends: [pyenv: ${python_version}]`) and **auto-inject** the
   edge. That way the YAML doesn't need to duplicate an edge that's
   already implicit in `backends:`.

**Acceptance:**
- Fresh WSL dry-run produces zero stray stderr lines in the
  `[ai-python-stack]` group prior to pyenv installation.
- The same dry-run on a host that *does* have pyenv installed still
  exercises the init path (i.e. the fix must not hide the
  post-install wiring from dry-run verification).
- `depends_on` for `pyenv` and `python` in
  `ucc/software/ai-python-stack.yaml` explicitly lists `homebrew` and
  `pyenv` respectively. Graph visualization (or `install.sh
  --print-graph` if it exists) shows the `python → pyenv → homebrew`
  chain.
- The inline `eval "$(pyenv init -)"` between `ucc_yaml_simple_target`
  calls in `lib/pip_group.sh` is either removed (activation moved
  into the `pyenv` driver) or wrapped with `command -v pyenv`.
- A follow-up note in `docs/SPEC.md` or driver docs captures the rule
  chosen in layer (3): no bash glue between target installs —
  declare dependencies instead.

### Cascade-skip dependents of platform-skipped targets

**Symptom:** on WSL, the dry-run reports:

```
[dep-fail] AI stack compose up (ai-stack-compose-running)
           dependency not satisfied (oracle fail): docker-daemon
```

…but `docker-daemon` itself was group-skipped one section earlier
with `Skipping docker (platform=wsl unsupported)`. `[dep-fail]` reads
like a real failure; a user debugging WSL output will chase a
non-issue.

**Desired behavior:** when a target's `depends_on` resolves to a
target that was skipped because of platform (not because it failed),
the dependent should report `[skip]` with reason
`dependency skipped (platform)` instead of `[dep-fail]`.

**Where to change:** dependency-gate resolution in `lib/ucc_targets.sh`
(the `dependency_gate` path used by observe). It needs to distinguish
three cases for an unsatisfied dep:
1. dep failed oracle → `[dep-fail]` (current behavior, keep)
2. dep was disabled by policy → `[skip] disabled dep`
3. dep was skipped because of platform → `[skip] platform`

**Acceptance:** WSL dry-run shows `[skip]` (not `[dep-fail]`) for
`ai-stack-compose-running` and any other target whose only unmet dep
is `docker-daemon` / `docker-available`.

### Platform-gate PREF display

**Symptom:** on WSL, the PREF block still prints mac-only tuning
knobs:

```
[PREF]  docker-memory-gb      48      options: 16|32|48|56
[PREF]  docker-cpu-count      10      options: 4|6|8|10|12
[PREF]  docker-swap-mib       4096
[PREF]  docker-disk-mib       204800
[PREF]  docker-first-install  manual
[PREF]  pytorch-device        mps     options: mps|cpu
```

None of these are actionable on WSL (docker group is skipped, MPS is
Apple-only).

**Fix:** extend `preferences.yaml` entries with an optional
`platforms:` field (same syntax as target `requires:` / `platforms:`),
and filter the PREF print loop by the running `$HOST_PLATFORM` before
display. Missing `platforms:` means "all platforms" (current default).

```yaml
preferences:
  - name: docker-memory-gb
    platforms: [macos]
    default: 48
    ...
  - name: pytorch-device
    platforms: [macos]
    default: mps
    ...
```

**Note:** this is **display-only** — the preference values must still
be read if any code path consults them (e.g. future WSL docker
support). Only the printout is gated.

**Acceptance:** WSL dry-run's PREF block contains only prefs that
apply to linux/wsl2.

### Ollama on WSL — review autostart semantics

**Symptom:** WSL dry-run shows:

```
[dry-run] Ollama (ollama)
  "installation_state=Configured runtime_state=Stopped
   health_state=Degraded dependency_state=DepsReady" ->
  "installation_state=Configured runtime_state=Running
   health_state=Healthy dependency_state=DepsReady"
[dry-run] Ollama nomic-embed-text (ollama-model-nomic-embed-text)
  installation_state=Absent -> Configured
```

Ollama on Linux uses a systemd unit (`ollama.service`), not
`brew services`. The current runtime driver may not know to start it
via `systemctl`, and under WSL without systemd the autostart path may
fail at apply time (dry-run hides this).

**Action:** verify at non-dry-run time that:
1. Ollama installation on WSL actually produces a working service
   (systemd vs. manual `ollama serve`).
2. The runtime driver has a correct start path for Linux/WSL, or the
   target declares `requires: macos` for the autostart behavior and
   uses a separate install-only target elsewhere.
3. Model-pull oracle (`ollama-model-*`) doesn't silently hang waiting
   for a server that isn't running.

This is a verification task — may turn into a real bug or may close
as "works as designed."

### Reconcile Summary "Total" vs "By Profile" counts

**Symptom:** the WSL dry-run Summary block shows:

```
── Convergence / software
  software-bootstrap      2 ok  skip=1
  ai-python-stack         2 ok
  build-tools             skip=3
  ai-apps                 2 ok
  network-services        1 ok
  node-stack              2 ok
  cli-tools               10 ok
  vscode-stack            2 ok  skip=2
  ──────────────────────────────────────────────────────
  Total                   21 ok  skip=6
  ──────────────────────────────────────────────────────
  By Profile
  Configured              61 ok
  Runtime                 3 ok
  Capability              2 ok
  Parametric              2 ok
```

`Total 21 ok` vs `Configured 61 ok` are counting different things
(group rollup vs per-profile observation). The labels don't make that
obvious.

**Fix (one of):**
- Rename the second block header to `By Profile — observations`
  (plural, explicit).
- Or reconcile to a single counting scheme.
- Or add a one-line explanation under the separator.

**Acceptance:** a reader seeing the Summary for the first time should
not ask "why do these numbers disagree."

### Platform-aware header / RAM warning

**Symptom:** WSL dry-run header and warnings are Mac-framed:

```
AI Workstation Setup | platform=wsl | mode=install dry_run=1
x86_64 · 15 GB
...
[WARN] Less than 32 GB RAM — large models may be slow
```

The `platform=wsl` line is correct, but the services summary at the
end still lists Mac-oriented endpoints and the 32 GB RAM warning
threshold was calibrated for a 64 GB Mac mini. On a 15 GB WSL dev
host the warning is noise.

**Fix:** low-effort polish —
1. Drop or reword the RAM warning when `platform != macos` (or
   re-threshold for linux/wsl2).
2. Keep the services summary but prefix entries that won't be
   reachable on the current host (e.g. `[skipped] Open WebUI …` when
   the compose stack is not running).

**Acceptance:** header output on WSL reads as informational, not as
"this tool is misconfigured for your box."

### Add `python-venv-available` capability target

**Context:** after #12 (pip venv isolation), each pip group with
`isolation.kind: venv` creates its own venv lazily inside the pip
driver. The venv is a silent side-effect of the first pip-group
target that needs it — not a named framework target.

**Problem:** the precondition "this Python interpreter can create
venvs" is invisible to the framework. If it fails (disk full, venv
module missing, permissions on `$HOME/.venvs`, broken `_ctypes` in a
pyenv-compiled Python, Debian `python3-venv` package absent on
non-pyenv systems), the failure surfaces inside **each** pip-group
line, 13 times, with confusing context — not as a single clear
capability failure.

It's also the same class of hidden-dependency issue as #13: the pip
groups depend on "venv works," but that edge isn't declared.

**Fix — add a single shared capability target** (Option C from the
earlier discussion; rejected Options A=inline status quo, B=per-venv
target explosion):

```yaml
python-venv-available:
  component: ai-python-stack
  profile: capability
  type: capability
  display_name: Python venv module
  depends_on:
  - python
  driver:
    kind: capability
    probe: python_venv_is_available
  evidence:
    status: python_venv_status
```

**Why `depends_on: [python]` alone — nothing else:**

venv is a stdlib module; it ships bundled with any correctly-built
Python. It has no installation step of its own. So the capability
depends only on a correctly-built `python` — not on the tools *used*
to build it.

Transitive chain (after #13 is applied):

```
python-venv-available
  └── python
        ├── xz                        (compile-time: liblzma for stdlib lzma)
        └── pyenv                     (← new from #13)
              └── homebrew            (← new from #13)
                    ├── network-available
                    ├── xcode-command-line-tools  (?macos)
                    └── build-deps                 (?!brew, linux/wsl2)
```

**Rejected direct deps** (all transitive via `python`):

| Candidate | Why rejected |
|---|---|
| `pyenv` | Transitive via `python` once #13 lands. Adding directly = duplication. |
| `build-deps` / `xcode-command-line-tools` | Transitive via `python → pyenv → homebrew`. |
| `xz` | Transitive via `python`. |
| `homebrew` | Transitive. |
| `pip-latest` | Independent concern — `pip-latest` upgrades global pip; venv creation uses `ensurepip` stubs bundled in Python. |

**Principle:** the capability asserts *Python ended up correctly
built*. It doesn't care about the path taken to get there — that's
`python`'s own `depends_on` chain to manage.

**Expected dry-run output** (once #13 + #19 both land):

```
[ok|dry-run] Build dependencies (build-deps)
[ok|dry-run] Network (network-available)
[ok|dry-run] Homebrew (homebrew)
[ok|dry-run] pyenv
[ok|dry-run] XZ Utils (xz)
[ok|dry-run] Python (python)
[ok|dry-run] Python venv module (python-venv-available)
[dry-run  ] PyTorch packages (pip-group-pytorch)
[dry-run  ] Hugging Face packages (pip-group-huggingface)
...
```

A break anywhere in the chain shows **one** failure at the right
level, not 13 confusing pip-group failures downstream.

**Failure modes the probe must catch** (why this is worth its own
capability, not just a `python -m venv --help` smoke test):

| # | Failure | Root cause | Detection |
|---|---|---|---|
| 1 | venv module missing | Debian splits `python3-venv` into a separate apt package; minimal builds skip it | `python -m venv --help` non-zero |
| 2 | ensurepip missing | pyenv-built Python without `ensurepip`; Debian minimal | `python -c 'import ensurepip'` fails |
| 3 | Broken `_ssl` / `_hashlib` | Python compiled without OpenSSL headers (pyenv ran before `build-deps`/`openssl`) | `python -c 'import ssl, hashlib'` fails |
| 4 | Broken `_ctypes` | Python compiled without libffi headers | `python -c 'import ctypes'` fails |
| 5 | Venv root not writable | `$HOME/.venvs` missing or wrong perms | `test -w <venv_root>` (or parent) |
| 6 | Broken pip bootstrap | venv creates but pip install fails (ensurepip stubs corrupt, proxy) | Throwaway venv smoke test: `python -m venv /tmp/x && /tmp/x/bin/pip --version` |
| 7 | Disk full / quota | No space on venv-root filesystem | Smoke test fails with `ENOSPC` |

**Probe scope — what it does vs. doesn't:**

Does:
- Prove `python -m venv` end-to-end on *this* interpreter.
- Prove a created venv has a functional `pip`.
- Prove the venv root is writable.

Does **not**:
- Create real per-group venvs (stays inline in pip driver, lazy).
- Check PyPI reachability (that's `network-available`).
- Check per-package install (that's each `pip-group-*` target).

**Reference probe implementation** (`python_venv_is_available`):

```bash
python_venv_is_available() {
  command -v python >/dev/null 2>&1 || return 1

  # (1) venv module importable
  python -m venv --help >/dev/null 2>&1 || return 1

  # (2,3,4) critical stdlib modules
  python -c 'import ensurepip, ssl, hashlib, ctypes' 2>/dev/null || return 1

  # (5,6,7) smoke test: real venv + pip works
  local tmp
  tmp="$(mktemp -d)" || return 1
  if ! python -m venv "$tmp/v" >/dev/null 2>&1; then
    rm -rf "$tmp"; return 1
  fi
  if ! "$tmp/v/bin/pip" --version >/dev/null 2>&1; then
    rm -rf "$tmp"; return 1
  fi
  rm -rf "$tmp"
  return 0
}
```

**Not covered — deliberately out of scope:**

Multiple Python env tools exist. This capability only asserts
**stdlib `venv`**. Others are separate tools with their own targets
(or none):

| Tool | Target today | Reason for exclusion |
|---|---|---|
| `venv` (stdlib) | **this capability (#19)** | — |
| `virtualenv` (pip pkg) | No | Superset of venv; not used by pip groups here |
| `pipx` | No | Isolated CLI installs — distinct concern |
| `pyenv-virtualenv` | No | pyenv plugin — not the isolation path chosen by #12 |
| `poetry` / `conda` | No | Different ecosystems — out of scope for this repo |

Every pip-group target with `isolation.kind: venv` adds
`python-venv-available` to its `depends_on`. Per-group venv creation
stays inline in the pip driver — this target is precondition-only,
not per-venv.

**Naming:** follows the `-available` suffix convention codified in
`docs/SPEC.md` section 3.1 (target naming). Reject alternatives
`pip-venv-infra`, `venv-ready`, `python-venv-ok`.

**Why Option C and not Option B (per-venv targets):**
- 13 pip groups × 1 venv = 13 near-identical targets. Pure noise.
- Individual venv creation is one `python -m venv <path>` call,
  idempotent by existence check — doesn't warrant a framework target
  each.
- The *precondition* (venv module works at all) is what's worth
  making explicit; the per-venv creation is not.

**Acceptance:**
- New `python-venv-available` target in
  `ucc/software/ai-python-stack.yaml` with `depends_on: [python]`.
- All 13 `pip-group-*` targets with `isolation.kind: venv` list
  `python-venv-available` in their `depends_on`.
- On a host with a broken-venv Python (e.g. Debian without
  `python3-venv` package, or a pyenv-build that failed to compile
  `_ssl`/`_ctypes`), dry-run shows **one** `[fail]`/`[cap-fail]` line
  on `python-venv-available` and `[dep-fail]` on each pip-group —
  not 13 identical-looking install failures later.
- Probe runs in < 500 ms (no heavy package install, just
  interpreter + tempdir check).

### `mps-available` / `cuda-available` skipped in dry-run

`lib/pip_group.sh:184-190`:

```bash
# ---- GPU capability probes ----
if [[ "$UCC_DRY_RUN" != "1" ]] && is_installed python3; then
  case "${HOST_PLATFORM:-}" in
    macos) ucc_yaml_capability_target ... "mps-available" ;;
  esac
  ucc_yaml_capability_target ... "cuda-available"
fi
```

Both probes are gated behind `UCC_DRY_RUN != 1` — they don't run in
dry-run mode at all. Result on WSL dry-run: lines 77-78 show
`[skip] not processed` for both, even though cuda-available declares
`requires: linux,wsl2` and would apply.

**Why this is wrong:** dry-run's purpose is to show what observe
would find. Hiding observations is the opposite of that.
Inconsistent with `python-venv-available` which now runs in dry-run
(it shows `[dry-run] -> Healthy DepsReady`).

**The `is_installed python3` guard** is also stale: pyenv shims may
not be on PATH when the runner reaches this point, so even in
non-dry-run, the probes can be incorrectly skipped on hosts where
Python only exists via pyenv.

**Fix:**
1. Remove the `UCC_DRY_RUN != 1` gate — capability targets are
   observe-only, safe in dry-run.
2. Replace `is_installed python3` with the same dep-graph approach
   used elsewhere: declare `mps-available: depends_on: [pip-group-pytorch]`
   (already declared) and let the framework decide if the dep chain
   is satisfied.
3. If the probe genuinely needs to be skipped on platforms where
   it's irrelevant, use the existing `requires:` mechanism in YAML
   (already in place: mps→macos, cuda→linux,wsl2). The runner
   shouldn't second-guess.

**Acceptance:** WSL dry-run shows `[dry-run]` or `[ok]` line for
`cuda-available` (and macOS dry-run for `mps-available`), not
`[skip] not processed`.

### Asymmetric skip-cascade: per-target `requires:` vs. component platform-skip

Two different "this target doesn't apply on this host" mechanisms
produce different cascade behavior on dependents:

| Source of skip | Recorded status | Dependent's reaction |
|---|---|---|
| Whole component group-skipped (install.sh `_component_supported_for`) | `platform-skipped` (synthetic, from #14) | Cascade `[skip]` with `dependency not applicable on <host>` |
| Per-target `requires: macos` skip | (no synthetic status) | Dependent reports `DepsReady`, proceeds as if the dep didn't exist |

Concrete example on WSL:
- `ai-stack-compose-running` depends on `docker-available` →
  cross-component (docker is platform-skipped) →
  **clean `[skip]`** ✓
- `ariaflow-server` depends on `networkquality-available` →
  same-component (`requires: macos`) →
  ariaflow-server reports `DepsReady` and proceeds ✗

The ariaflow-server outcome is what we want (it should still install
on WSL even without networkquality), but the asymmetry is confusing.

**Decide one rule and apply it consistently:**

- **Option A — "skipped deps are satisfied":** treat both kinds of
  platform-skip as a non-blocker for dependents. Drop #14's
  `platform-skipped` cascade; let cross-component deps proceed too
  (then `ai-stack-compose-running` would try to install docker
  compose on WSL → fail at runtime, regression).
- **Option B — "skipped deps are vacuous":** introduce a third
  status `platform-vacuous` for deps that don't apply but shouldn't
  block. Use for `requires:`-skipped deps. Keep `platform-skipped`
  blocking for cross-component group skips (current behavior).
- **Option C — "platforms decide blocking":** read each dep's
  `requires:` field at dep-check time. If the dep has `requires:
  macos` and the host is non-mac, treat as satisfied (don't try to
  observe). If the dep has no `requires:` but its component was
  platform-skipped, treat as blocking.

Option C is the most consistent with declarative intent — `requires:`
already encodes "this is mac-only, don't expect it elsewhere," so a
dependent can ignore it on non-mac. Option B is the cheapest patch.

**Acceptance:** a documented rule in CLAUDE.md (extend Rule 9 or add
Rule 11) plus matching code so a reader can predict cascade behavior
from the YAML alone.

### `brew services` backend on non-macOS hosts

Two ariaflow targets (`ariaflow-server`, `ariaflow-dashboard`) and
`ollama` (#16, deferred) all use `driver.kind: service` with
`backend: brew`. On macOS, this delegates to `brew services`
(launchd-backed, works out of the box).

On WSL/Linux:
- Linuxbrew has `brew services` but it depends on **systemd**.
- Default WSL2 distros do not enable systemd unless the user
  explicitly opts in (`/etc/wsl.conf` `[boot] systemd=true`).
- Without systemd, `brew services start <name>` fails silently or
  errors.

WSL dry-run reports `[dry-run] Ariaflow Server ... -> Running`
(line 100) and `[dry-run] Ollama ... -> Running` (line 90). Real
install would attempt to start and very likely fail mid-converge.

**Options:**
1. Detect systemd availability at observe time. If not available,
   either `[skip]` the service start (and surface a hint to the
   user about enabling systemd) or fall back to a manual-start path
   (`ollama serve &` style with a written systemd unit / wsl.conf
   snippet for next reboot).
2. Add a `service-policy=manual` short-circuit so the operator must
   start services themselves on WSL — already partly the case via
   the `service-policy` pref (default `autostart`); could auto-flip
   to `manual` when systemd is absent.
3. Mark the targets `requires: macos` if WSL service support is out
   of scope, and surface a clear "service management not available
   on this host" message in dry-run.

This item subsumes deferred #16 (Ollama is one instance of the same
problem). Worth solving the general case.

**Acceptance:** WSL dry-run for any `kind: service, backend: brew`
target either reports a credible plan (systemd path or manual hint)
or shows `[skip]` with a reason — never a misleading `-> Running`
that will fail at apply time.

## Closed

### 2026-04-13 session — Docker hardening and launch fix

**Docker probe and config hardening** (`fce0367`) — Eliminated all
hardcoded values from `lib/docker.sh`. Every function now reads config
(app path, process name, settings path, app name) from YAML via
`yaml_get_many`. Renamed `docker_backend_process` → `docker_desktop_process`
and `docker_daemon_pid` → `docker_desktop_pid` to reflect the real
architecture (com.docker.backend is the root process, the daemon runs
inside the Linux VM with no host PID).

**Socket-based probes** (`0cea1a6`) — Switched all Docker daemon probes
from the `docker` CLI (PATH-dependent, unreliable on Apple Silicon) to
direct socket access via `curl --unix-socket ~/.docker/run/docker.sock`:
`/_ping` for readiness, `/version` for version, `/info` for 500-state
detection. CLI calls kept as fallbacks only.

**Process architecture documented** — Kill tests on Apple Silicon
confirmed: com.docker.backend is the root process (PPID 1, launched by
launchd), GUI is a child of the backend (not the other way around),
killing ANY component triggers full shutdown (no auto-restart). Timings
documented in `lib/docker.sh` header.

**Install/launch separation** (`554c6bc`) — `_docker_desktop_install`
now only does brew cask install + settings patch. Launch moved to
`_docker_launch` called at the end. Removed dead debug code and Phase 3
manual-start warning from `run_docker_from_yaml`.

**Large-env launch failure** (`0cea1a6`) — Root cause found: Docker
Desktop's com.docker.backend silently fails to start when the inherited
environment exceeds ~145 KB (500+ `_UCC_*` exports accumulated during
install.sh). Fixed by launching with `env -i HOME="$HOME" PATH="$PATH"`.

**Actions wired** (`07a6525`) — `docker-desktop` and `docker-daemon`
targets now have `actions.install` in the YAML. Previously observe-only.

**Assisted install vmnetd step** — `_docker_assisted_seed_vmnetd` wired
as Step 7 in `_docker_assisted_install`. Hardcoded app path replaced
with parameter.

Commits: `fce0367`, `979fa8a`, `554c6bc`, `4848e5e`, `0cea1a6`,
`07a6525`.

---

### 2026-04-12 session

**Phase B4 — hoist compose-up to a first-class target** — The
implementation that landed today matches the "better plan" design
recorded in the Open section yesterday (the one that replaced the
original "move _ai_apply_compose_runtime to lib/docker_compose.sh"
sketch with the cleaner "upstream-gate + observe-only dependents"
model). No second compose-based component exists yet, but the
refactor was justified by two observations:

1. The existing sentinel-based implementation had real coupling
   costs for ai-apps itself — the dep graph was lying (each per-
   service target's `depends_on: ai-stack-compose-file` hid the
   actual sibling side-effect of running `docker compose up -d`).
   Promoting compose-up to a first-class target makes the graph
   honest.
2. The pattern is already used in the framework at 1→1 scale
   (`docker-desktop → docker-available`) and 1→2 scale
   (`pytorch → mps-available + cuda-available`). Extending it to
   1→5 is applying a known primitive, not inventing a new concept —
   so risk is lower than speculative abstraction normally carries.

What actually shipped:

- **New driver `lib/drivers/compose_apply.sh`** (96 LOC) with
  observe/action/evidence hooks. Uses `driver.path_env` (env var
  name indirection, matching the existing `compose-file` driver)
  and optional `driver.pull_policy_env` for "always-pull" gating.
  Observe resolves the compose path, runs `docker compose config
  --services` to enumerate declared services, then checks every
  service has a running container (matching by name with a regex
  that tolerates `--` and `__` compose-project naming). Action
  runs optional `docker compose pull` then `docker compose -f <path>
  up -d`.
- **New target `ai-stack-compose-running`** in ai-apps.yaml,
  profile: runtime, driver.kind: compose-apply. depends_on:
  [docker-desktop, ai-stack-compose-file]. This is the single
  apply gate for the whole ai-apps compose stack.
- **5 runtime targets rewired** (open-webui, flowise, openhands,
  n8n, qdrant) to `depends_on: ai-stack-compose-running` instead of
  `depends_on: ai-stack-compose-file`. Their driver is now pure-
  observe — no _action hook in `docker-compose-service`.
- **`_action` hook deleted** from `lib/drivers/docker_compose_service.sh`.
  The driver is now observe + evidence + recover only. The retry-
  with-backoff HTTP probe from `e36a399` is preserved.
- **Sentinel and apply function deleted** from `lib/ai_apps.sh`:
  `_AI_APPS_APPLY_SENTINEL` variable, its lifecycle (`mkdir -p` +
  `:>` sentinel touch), and the entire `_ai_apply_compose_runtime`
  function. Replaced with: `export COMPOSE_FILE` (so the driver
  reads it via `driver.path_env`), pre-dispatch
  `_remove_legacy_containers` call, `ucc_yaml_runtime_target` for
  `ai-stack-compose-running` before the per-service loop, and a
  second `_ai_warm_metadata_cache` call after that dispatch.
- **Validator updated**: `compose-apply` added to both
  `KNOWN_RUNTIME_DRIVERS` and `DRIVER_SCHEMA` (required: path_env,
  optional: pull_policy_env).
- **Smoke test updated**: `compose-apply` added to
  `FAKE_DRIVER_FIELDS` with a non-existent `path_env` so the
  synthetic observe falls through to "stopped" cleanly. All 55
  tests pass in `tests/test_driver_smoke.py +
  tests/test_drivers.py + tests/test_capability_driver.py +
  tests/test_yaml_schema.py`.
- **Docs regenerated** — driver-feature-matrix.md gains a
  `compose-apply` row and drops `docker-compose-service`'s action
  column from ✅ to —. SPEC.md ai-apps section grows 15 → 16
  targets (the new `ai-stack-compose-running`).

What the refactor buys going forward:

- Adding a second compose stack (monitoring, homelab, media server,
  dev databases) requires **zero lib/ changes**. The new component's
  runner sets its own `COMPOSE_FILE` env var, the YAML declares a
  `*-compose-running` target with `driver.kind: compose-apply` +
  `driver.path_env: COMPOSE_FILE`, plus N `docker-compose-service`
  observe-only targets depending on it.
- The dep graph tells the truth: running
  `./install.sh open-webui-runtime` now visibly resolves as
  `docker-desktop → ai-stack-compose-file → ai-stack-compose-running
  → open-webui-runtime`. The shared sibling side-effect is explicit.
- Failure modes clean up: if `docker compose up -d` fails, the
  gate target reports `[fail]` and the 5 dependents each report
  `[dep-fail]` via the framework's existing propagation. One
  clear root cause.

Mac mini verification still required: the smoke test can exercise
the driver's dispatch path but can't actually run `docker compose`
on WSL without a container stack. The real validation is
`./install.sh --no-interactive` on the Mac mini, with the ai-apps
compose stack torn down first (`docker compose -f
$HOME/.ai-stack/docker-compose.yml down`), confirming the new dep
chain brings everything up cleanly.

Commits: `cd56046` (add compose-apply driver, inert), `34d806a`
(atomic cutover — remove sentinel, rewire YAML, delete _action).

---

### 2026-04-11 session

Three items closed in one long session that started with a Docker
Desktop bootstrap recovery and ended with Phase X1 per-driver smoke
tests.

**Capability driver refactor** — Replaced the legacy verbose shape
(`profile: capability + driver.kind: custom + runtime_manager:
capability + probe_kind: command + oracle.runtime: <fn>`) with a
single `driver.kind: capability + driver.probe: <fn>` declaration.
7 targets migrated across 5 YAML files (`network-available`,
`networkquality-available`, `mdns-available`, `mps-available`,
`cuda-available`, `docker-available`, `sudo-available`). New
`KNOWN_CAPABILITY_DRIVERS` set in the validator; legacy fields
(`runtime_manager`, `probe_kind`, `oracle.runtime` on capability
profile) hard-rejected so authors cannot reintroduce the dead
boilerplate. `ucc_yaml_capability_target` and
`_ucc_observe_yaml_capability_target` now read `driver.probe` instead
of `oracle.runtime`. `install.sh`'s `_UCC_YAML_BATCH_KEYS` pre-fetch
list updated to include `driver.probe`. Two pre-existing miscalls
(`lib/homebrew.sh` and `lib/docker.sh` dispatched `network-available`
/ `docker-available` through `ucc_yaml_runtime_target` instead of the
capability dispatcher) fixed along the way — a latent bug that only
surfaced once the dispatchers diverged. New
`tests/test_capability_driver.py` adds 15 regression tests (validator
positive + 5 negatives + dispatcher round-trip). Verified end-to-end
on the Mac mini: all 7 capability targets report `[ok]` in
`--no-interactive` mode with matching evidence. Runtime-profile
targets (`unsloth-studio`, `docker-desktop`) not migrated — their
`kind: custom` declarations remain; a separate follow-up if desired.

Commits: `e48da96` (atomic cutover), `2863044` (batch-keys fix),
`d17a16c` (runner dispatch fix), `a637074` (tests), `3d5759b`
(regen docs), `3e04358` (PLAN update).

**Phase X1.5 — `--check` drift hook wired into pre-commit** —
`tools/check-bgs.sh` now uses `git rev-parse --show-toplevel` for
REPO_ROOT (was `$(cd "$(dirname "$0")/.." && pwd)` which broke when
the script was invoked via a symlink from `.git/hooks/` or
`~/.git-hooks/`). Added an inert guard so the script exits 0
silently in repos that do not carry `tools/build-driver-matrix.py`
— safe to install as a global pre-commit hook without affecting
unrelated repos. BGS validator step moved from "skip whole script on
missing validator" to "skip only the BGS step, still run drift
checks" so doc drift is caught even when the BGS private repo is
not present. Hook installed as symlink at `~/.git-hooks/pre-commit`
(the user's existing global hooks dir, which already contains a
`commit-msg` hook that strips `Co-Authored-By: *@anthropic.com`
lines — the two hooks coexist). Verified end-to-end: drift detection
blocks commits with `rc=1` and a clear DRIFT message; clean commits
pass. Every commit on this repo now enforces
`python3 tools/build-driver-matrix.py --check` +
`python3 tools/build-spec.py --check`.

Commits: `b74bb8f` (hook + script fix + PLAN update).

**Phase X1 — per-driver smoke test fixtures** — New
`tests/test_driver_smoke.py` (~205 LOC) uses `pytest.parametrize`
over every driver kind that defines a `_ucc_driver_<kind>_observe`
hook in `lib/drivers/`. Each test sources `lib/ucc.sh + lib/utils.sh`
in a bash subshell and invokes the observe function against a
minimal synthetic YAML fixture, asserting exit code is 0 or 1
(both are "driver dispatched cleanly" outcomes). A `FAKE_DRIVER_FIELDS`
dict provides the minimum required fields for each of the 24
currently-covered kinds, with all values designed to resolve to
the driver's "missing" state on the test host. Two meta-sanity
tests enforce that `FAKE_DRIVER_FIELDS` stays in sync with
`DRIVER_SCHEMA[kind]['required']` and that every driver with an
`_observe` hook in `lib/drivers/` is either covered or explicitly
skipped with a documented reason. Runtime: ~1.5 seconds for 26
tests (24 driver smoke + 2 sanity).

Catches: driver files that source clean but crash on first hook
invocation (unbound vars under `set -u`, typos in case branches
matching YAML keys, missing helper function calls). Does NOT catch:
capability targets (dispatched through `ucc_yaml_capability_target`,
not through a driver `_observe` hook — covered by the existing
`tests/test_capability_driver.py`), install-action correctness
(fixture targets are never executed), or meta-drivers like
`npm-global` / `package` that delegate to other kinds. Also
explicitly excluded: `vscode-marketplace` (retired).

Sanity check: injected an unbound-variable crash into
`_ucc_driver_brew_observe`, test failed with `rc=127` and surfaced
bash's stderr in the assert message. Reverted, tests green.

Paired with: a new `InstallShBatchKeysTests` class in
`tests/test_capability_driver.py` adds two static regression tests
for the specific capability-cache bug that today's driver smoke test
CANNOT reach (because it lives in `ucc_yaml_capability_target`'s
dispatch path, not in a driver hook). `test_batch_keys_include_driver_probe`
asserts `driver.probe` appears in install.sh, and
`test_batch_keys_excludes_oracle_runtime` asserts the legacy key
has been removed. Both checks are static file-content greps — they
directly document the invariant "any field the capability dispatcher
reads from the pre-fetched cache MUST be in `_UCC_YAML_BATCH_KEYS`".

Commits: `9762e07` (driver smoke test), `88bbc5e` (install.sh batch
key regression tests).

**Auxiliary fixes from the same session** — not strictly part of
either item above, but landed while recovering the Mac mini's Docker
Desktop install and revealed along the way:

- `ba8f095` — Stop Gatekeeper reinstall loop on Docker Desktop
  (`greedy_auto_updates: true` + unstrtipped quarantine made brew
  reinstall the cask on every run, then tripped a macOS dialog).
- `71c2dee` — Correct the `settings_relpath` YAML key that was
  never being read because the lib code used a non-existent
  `docker_settings_store_relpath` key; also always strip quarantine
  in `_docker_daemon_start` defensively.
- `5a79a42` — Replace `_docker_privileged_helper_installed` (which
  looked for `/Library/PrivilegedHelperTools/com.docker.vmnetd` —
  gone on Apple Silicon Docker 4.x) with `_docker_bootstrap_complete`
  which checks `LicenseTermsVersion` in `settings-store.json`.
- `813aa78` + `f08328e` — `_docker_launch` stops calling the
  nonexistent `docker desktop start` CLI plugin and uses plain
  `open -a /Applications/Docker.app` (`-g` proven broken on Apple
  Silicon — returns 0 without starting Docker).
- `69f47d4` — Escalating recovery feature for failed targets plus
  `winget` backend for `pkg` + `mdns-available` capability target
  (originally wired wrong, fixed in the follow-ups below).
- `ec2d426` + `2261b78` + `5fb5445` — Successive fixes for the new
  network-services targets: missing `state_model`, invalid
  `apt_ref/dnf_ref`, wire `mdns-available` + `avahi` into the
  component runner.
- `6a07393` + `07b63af` — Document the validated recipe for
  fully-unattended Docker first install (vmnetd seeding + EULA
  settings pre-write + SUDO_ASKPASS shim) in PLAN.md as deferred
  future work.

### Earlier closed work

All driver-tier work that had a real consumer: D2, D3, D4, B2, C2,
B3, X2. See git log for details.

Three items honestly skipped:
- **C3** (desired-value comparison in observe) — already handled by
  the parametric framework.
- **C4** (fold compose-file into home-artifact) — would require a
  new one-target subkind; premature abstraction.
- **B1** (state vocab static check) — can't be enforced at static
  analysis without actually running drivers; belongs to runtime tests.

## Out of scope

- New `pkg` backends (mise, nix, aur). Add when a real target needs them.
