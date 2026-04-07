# Runtime Activation Gaps

Several drivers call binaries that only exist on `$PATH` after a shell-init
script (e.g. `nvm.sh`, `pyenv init`) has been sourced. UCC's dependency
checker confirms the runtime *target* is installed (e.g. `node-lts=ok`) but
does **not** propagate the runtime's environment to the dependent action's
process. The driver therefore has to activate the runtime itself, on demand.

## Audit

| Driver | Calls | Activation needed | Status |
|---|---|---|---|
| `lib/drivers/npm.sh` (`npm-global`) | `npm` | nvm `nvm.sh` | ✅ fixed via `_npm_ensure_path` |
| `lib/drivers/pyenv.sh` (`pyenv-version`) | `pyenv install`, `pyenv global`, `pyenv which` | `pyenv init` shims | ❌ gap |
| `lib/drivers/pip.sh` (`pip`) | `pip` / `python -m pip` | active python (system vs pyenv) | ❌ gap |
| `lib/drivers/pyenv_brew.sh` | `pyenv --version`, `pyenv root` | none — these don't need shims | ✅ OK |
| `lib/drivers/nvm.sh` (`nvm`, `nvm-version`) | `nvm` | self-sources in `bash -c` subshell | ✅ OK (good model) |
| `lib/drivers/ollama_model.sh` | `ollama` | none on macOS (brew puts it on PATH) | ✅ implicit |
| `lib/drivers/docker_compose_service.sh` | `docker compose` | none — Docker Desktop on PATH | ✅ implicit |
| `lib/drivers/brew.sh`, `brew_service.sh` | `brew` | none once homebrew target ran | ✅ implicit |

## Real gaps

1. **`pyenv-version`** — `pyenv install` / `pyenv global` rely on shims being
   active. Today the driver invokes `pyenv` bare. Symptom mirrors the npm
   case: works in interactive shells, fails inside `install.sh` subprocesses
   on a fresh box.

2. **`pip`** — picks whichever `python` is on PATH. If the intended
   interpreter is the pyenv-managed one, missing activation silently selects
   the wrong python (or fails outright).

## Right pattern

Two equivalent idioms already in the codebase:

- **Self-sourcing wrapper** (`lib/drivers/nvm.sh`):
  ```sh
  bash -c 'source "$HOME/.nvm/nvm.sh" 2>/dev/null && nvm --version'
  ```
- **In-process gate** (`lib/drivers/npm.sh:_npm_ensure_path`): source once in
  the parent shell, every action gates on the helper.

The in-process gate is cheaper (no extra process per call) and shares cache
state with the rest of the driver.

## Recommended fix

Per-driver `_<kind>_ensure_path` helpers for `pyenv-version` and `pip`,
mirroring `_npm_ensure_path`:

- `_pyenv_ensure_path` — exports `PYENV_ROOT`, prepends `$PYENV_ROOT/bin` and
  `$PYENV_ROOT/shims`, runs `eval "$(pyenv init - bash)"`. Idempotent.
- `_pip_ensure_path` — calls `_pyenv_ensure_path` when the target's pyenv
  dependency is in scope, otherwise verifies system python.

## Bigger structural fix (out of scope)

Generic activation hook in the driver dispatcher:

```sh
_ucc_driver_activate <kind>   # source this driver's runtime once per process
```

`_ucc_driver_action` would call it before every install/update/observe. Each
driver declares its activation once (`_ucc_driver_<kind>_activate`) and the
dispatcher enforces it. Eliminates the per-helper guards and the risk of
forgetting to gate a new action.

## Why this exists

Component runners (e.g. `run_node_stack_from_yaml`) source their own runtime
init at the top, so targets handled *inside* that runner work fine. Targets
in *other* components that happen to use the same driver kind never benefit,
because the dependency check is logical, not environmental — `node-lts=ok`
means "installed", not "on PATH right now".
