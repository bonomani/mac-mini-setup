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

### Naming

- Functions called directly from YAML (no leading underscore): `ollama_host_supported`, `brew_service_is_started`
- Internal helpers not called from YAML (leading underscore): `_docker_cask_ensure`, `_ai_cache_get`
