# Claude Code Directives - mac-mini-setup (UCC framework)

## Scope
- Priority: `src/` or main project folder
- Ignore: `__pycache__/`, `.venv/`, `.pytest_cache/`, `*.pyc`, `build/`, `dist/`

## Reading
- Check relevance before opening (rg/grep/head or Select-String)
- Read the minimum necessary

## Code
- Change the strict minimum
- Follow PEP8 + typing if already used
- Don't touch imports unnecessarily
- No refactoring outside scope
- Never use `...` in final code

## Async
- Don't introduce asyncio if absent
- Don't mix sync/async

## Tests
- Targeted testing: `pytest -k <test>`
- Don't run the full suite without reason

## Install
- Use `pip install -e .` for local dependencies

## Lint
- Use ruff (preferred)

## Errors
- Read the last 20 useful lines
- Max 2 attempts, then stop and ask

## Responses
- Short, technical
- No variants
- No unnecessary explanations

---

## UCC Framework Rules

### Rule 1 — YAML must not contain code

Fields `oracle.*`, `observe_cmd`, `evidence.*`, `actions.*`, `desired_cmd`, `skip_when`, `oracle` (tic) must contain **only** a plain function call with optional `${var}` args. Never:

- Shell operators: `|`, `&&`, `||`, `;`
- Redirections: `>`, `2>`, `>&`
- Subshells: `$(...)`, backticks
- Bash tests: `[[ ]]`, `[ ]`
- Inline tools: `awk`, `grep`, `sed`, `printf`, `echo`, `curl`, `python3 -c`, `defaults read`
- Framework internals: `$CFG_DIR`, `$YAML_PATH`, `$TARGET_NAME` (use wrapper functions instead)

**Fix**: extract to a lib function, then call it by name.

### Rule 2 — Lib functions must not hardcode software-specific config

Paths, service names, package names, domain strings, process patterns that are already defined as YAML top-level variables must **not** be hardcoded inside lib functions. They must be passed as parameters or read from YAML internally.

**Fix**: add the value as a top-level YAML var and either pass it via `driver.<key>` (read with `_ucc_yaml_target_get`) or read it with `yaml_get_many` using the implicit `$CFG_DIR`/`$YAML_PATH` context.

### Rule 3 — Config vars read internally, not passed back from YAML

When a function only needs a YAML config variable to do its work, it should **read it from YAML internally** (via `yaml_get_many "$CFG_DIR" "$YAML_PATH" <key>`) rather than accept it as an argument from the YAML caller.

**Violation pattern**: `install: my_fn "${some_yaml_var}"` where `some_yaml_var` is the only meaningful arg.
**Fix**: `install: my_fn` — function reads `some_yaml_var` from YAML itself.

**Exception**: functions that are genuinely reusable across different YAML files with different values (e.g. `brew_install`, `home_path`) should keep their parameters.

### Rule 4 — Driver config stays inside the driver

When a target's `oracle`, `evidence`, or `actions` field passes `${driver.<key>}` back as a function argument, that value belongs inside the driver, not in the YAML.

**Violation pattern**: `install: my_fn "${driver.service_name}"` or `evidence: my_fn '${driver.ref}'`
**Fix**: implement a proper `driver.kind: <name>` driver file (`lib/drivers/<name>.sh`) that reads `driver.<key>` internally via `_ucc_yaml_target_get`.

### Rule 5 — Framework plumbing vars must not appear in YAML

`$CFG_DIR`, `$YAML_PATH`, `$TARGET_NAME`, `$HOST_PLATFORM` and similar framework-internal variables must never appear in YAML field values.

**Fix**: wrap the call in a lib function that injects these implicitly (e.g. `http_probe_endpoint` wraps `_ucc_http_probe_endpoint "$CFG_DIR" "$YAML_PATH" "$TARGET_NAME"`).

### Rule 6 — `requires:` is only for platform impossibilities

`requires:` on a target means "this can NEVER work on other platforms" — OS kernel APIs, hardware features, platform-specific system tools.

**Use `requires:`**:

- `pmset` commands → `requires: macos` (macOS kernel power management)
- `xcode-command-line-tools` → `requires: macos` (macOS SDK)
- `mps-available` → `requires: macos` (Apple Metal GPU hardware)
- `systemd` service → `requires: linux,wsl2` (Linux init system)
- `CUDA` → `requires: linux,wsl2` (NVIDIA GPU drivers)

**Do NOT use `requires:`**:

- Package not yet in apt/brew on some platform → driver fails naturally, may work in future
- brew tap not available on Linux → will work if tap is ported
- Software only tested on macOS → not a platform impossibility

**Principle**: Package availability can change. Platform APIs cannot. Let the driver handle PM failures — don't block with `requires:` what might work tomorrow.

### Rule 7 — `depends_on` is for cross-ecosystem dependencies only

YAML `depends_on` entries track dependencies that no single package manager can see. Do NOT duplicate intra-PM dependencies (the PM already handles those).

**Use `depends_on`**:

- Cross-driver: `python` → `xz` (pyenv-version needs package driver)
- Cross-ecosystem: `ariaflow-server` → `networkquality-available` (OS binary)
- Phase ordering: `git-global-config` → `git` (config needs package)
- Composition: `system-composition` → all system targets

**Do NOT use `depends_on`**:

- brew formula A depends on brew formula B → brew handles it
- pip package A requires pip package B → pip handles it

**Conditional syntax**: `target?condition` with comma OR:

- `xcode-command-line-tools?macos` — only on macOS
- `build-deps?!brew` — when PM is not brew
- `dep?macos>=14,linux,wsl2` — version comparison + OR

### Rule 8 — YAML is configuration only, never runtime logic

YAML files declare **what** (names, values, relationships), never **when** or **how** to act at runtime. Runtime decisions belong in code where the execution context is available.

**Allowed in YAML**: target names, driver keys, dependency lists, profile types, display names, package refs, default values, option lists, rationale text.

**Not allowed in YAML**: conditional execution rules (`skip_when`, `run_if`), environment-dependent switches, mode/state checks, temporal logic. These belong in the code that reads the YAML.

**Principle**: YAML is a static declaration. If a field's value only makes sense with runtime context (current args, environment, platform state), it belongs in code.

### Rule 9 — Target names follow suffix-by-profile convention

Target names carry their profile via a suffix. A reader should be able to infer the target kind from the name alone.

| Profile | Suffix | Meaning | Examples |
|---|---|---|---|
| `capability` | `-available` | "X is present and usable right now by downstream targets" (presence + health + deps checked at observe time) | `docker-available`, `network-available`, `mps-available`, `cuda-available` |
| `runtime` | `-running` / `-stopped` | Active runtime state of a service | `ai-stack-compose-running` |
| `configured` (`type: package`) | none | The target **is** the thing being installed | `git`, `cli-jq`, `vscode`, `ollama` |
| `configured` (`type: config`) | none / free-form | Settings or declared-state file | `git-global-config`, `vscode-settings` |
| `parametric` | none | Tunable value with a desired setting | `docker-memory-gb`, `brew-analytics` |
| gate (in `defaults/gates.yaml`) | free-form | Pre-convergence readiness check | `supported-platform` |

**Do not invent synonyms** for `-available` (`-ready`, `-reachable`, `-operational`). They all collapse to the same observe-time check in this framework. Package targets stay bare (`git`, not `git-installed`) — installation state is implicit in the target kind.

### Rule 10 — No bash glue between target installs

Lib functions must not place raw bash between `ucc_yaml_simple_target` calls that assumes a prior target materialized. Declare the dependency in YAML instead.

**Bad** — assumes `pyenv` is on PATH after its install call, bypasses the dependency graph, and breaks in dry-run (prior target is a no-op):

```bash
ucc_yaml_simple_target "$cfg_dir" "$yaml" "pyenv"
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"               # ← bash glue
ucc_yaml_simple_target "$cfg_dir" "$yaml" "python"
```

**Good** — declare the edge, let the framework order the calls, let each driver self-activate:

```yaml
pyenv:   { depends_on: [homebrew] }
python:  { depends_on: [xz, pyenv] }
```

```bash
ucc_yaml_simple_target "$cfg_dir" "$yaml" "pyenv"
ucc_yaml_simple_target "$cfg_dir" "$yaml" "python"   # pkg driver's pyenv
                                                     # backend self-activates
```

**Why this works**: the `pkg` driver calls `_pkg_<backend>_activate` during observe, and the exports persist in the caller shell. Subsequent targets see a fully-activated runtime without the caller lib function having to do it manually.

**Exception**: `lib/tic_runner.sh` post-convergence verification runs have no observe pass to piggyback on and may re-establish `PYENV_ROOT` / `NVM_DIR` explicitly.

### Rule 11 — Platform-conditional dependencies must be declared with `?platform`

When a dependent target lists a dep that only exists on certain platforms, declare the platform condition explicitly with the `?` syntax. Don't rely on the dep target's own `requires:` to silently filter it from the graph.

**Bad** — implicit silent skip:

```yaml
ariaflow-server:
  depends_on:
    - networkquality-available    # has `requires: macos`, silently dropped on linux/wsl2
    - mdns-available
    - avahi                       # has `requires: linux,wsl2`, silently dropped on macos
```

This works at runtime (the framework's per-target `requires:` filter happens to make it correct), but the polyglot intent — "use networkquality on macos, avahi on linux" — is invisible to a reader of `ariaflow-server`.

**Good** — explicit conditional dep:

```yaml
ariaflow-server:
  depends_on:
    - networkquality-available?macos
    - mdns-available
    - avahi?linux,wsl2
```

Reader sees the per-platform composition without having to chase the dep targets' own `requires:` fields.

**Why this matters**:

Two skip mechanisms exist and produce different cascade behavior on dependents — the asymmetry is principled but easy to misread:

| Skip source | Effect on dependents |
|---|---|
| Component group-skipped (cross-component, `_component_supported_for`) | Dep gets synthetic `platform-skipped` status. Dependents cascade-`[skip]` with "dependency not applicable on `<host>`" (see lib/ucc_targets.sh `_ucc_check_deps_recursive`). |
| Per-target `requires:` skipped (same-component or cross-component) | Dep filtered from observation, no status recorded. Dep-check finds no status and no oracle → silently treats as satisfied. Dependent proceeds. |

Using `?platform` makes the dep ITSELF conditional, sidestepping both mechanisms — the dep simply isn't in the graph for the wrong platform. This is cleaner than relying on either skip cascade.

**Conditional dep syntax** (parsed by `tools/validate_targets_manifest.py:_resolve_conditional_dep`, comma = OR):

- `?value` — match host (`?macos`, `?linux`, `?wsl2`)
- `?!value` — NOT match (`?!brew`)
- `?name>=version` — version compare (`?macos>=14`)
- `?macos>=14,linux,wsl2` — OR combination

### Naming

- Functions called directly from YAML (no leading underscore): `docker_resources_observe`, `brew_service_is_started`
- Internal helpers not called from YAML (leading underscore): `_docker_cask_ensure`, `_ai_cache_get`
