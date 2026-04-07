# Runtime Activation Gaps

Drivers/backends that call binaries gated by shell-init activation
(`nvm.sh`, `pyenv init`, …). The dependency check confirms the runtime is
*installed*, but does not propagate the runtime's environment into the
dependent action's process — so the driver must activate the runtime itself.

## Audit (post-Phase-4)

| Driver / pkg backend | Calls | Activation | Status |
|---|---|---|---|
| `pkg` backend `npm` | `npm` | nvm `nvm.sh` | ✅ via `_npm_ensure_path` (in-process gate) |
| `pkg` backend `pyenv` | `pyenv install`, `pyenv global` | `pyenv init` shims | ❌ gap (`_pyenv_ensure_path` not implemented) |
| `pkg` backend `brew` / `brew-cask` | `brew` | none — brew puts itself on PATH | ✅ implicit |
| `pkg` backend `native-pm` | `apt-get` / `dnf` / `pacman` / `zypper` | none — system PMs | ✅ implicit |
| `pkg` backend `ollama` | `ollama` | none on macOS (brew) | ✅ implicit |
| `pkg` backend `vscode` | `code` | none (cli on PATH after `cli-symlink`) | ✅ implicit |
| `pkg` backend `curl` | `curl` | none | ✅ implicit |
| `kind: pip` (separate driver) | `pip` / `python -m pip` | active python (system vs pyenv) | ❌ gap |
| `kind: nvm` / `nvm-version` | `nvm` | self-sources in `bash -c` subshell | ✅ OK (good model) |
| `kind: docker_compose_service` | `docker compose` | none — Docker Desktop on PATH | ✅ implicit |
| `kind: brew` (legacy), `service` | `brew` | implicit | ✅ |

## Real gaps

1. **`pkg` backend `pyenv`** — calls `pyenv install` / `pyenv global` bare.
   Works in interactive shells (where `pyenv init` is sourced from
   `~/.zshrc`) but fails inside `install.sh` subprocesses on a fresh box.
   Surfaces if any non-pyenv-component target gets a `pyenv` backend.

2. **`kind: pip`** — picks whichever `python` is on PATH. If the intended
   interpreter is the pyenv-managed one, missing activation silently
   selects the wrong python (or fails outright). Affects 13 ai-python-stack
   targets that stayed on `kind: pip`.

## Right pattern

Two equivalent idioms already in the codebase:

- **Self-sourcing wrapper** (`lib/drivers/nvm.sh`):
  ```sh
  bash -c 'source "$HOME/.nvm/nvm.sh" 2>/dev/null && nvm --version'
  ```
- **In-process gate** (`lib/drivers/npm.sh:_npm_ensure_path`): source once
  in the parent shell, every action gates on the helper.

The in-process gate is cheaper (no extra process per call) and shares
cache state with the rest of the driver.

## Recommended fix

Add `_pyenv_ensure_path` to `pkg.sh` mirroring `_npm_ensure_path`:

- exports `PYENV_ROOT`, prepends `$PYENV_ROOT/bin` and `$PYENV_ROOT/shims`,
  runs `eval "$(pyenv init - bash)"`. Idempotent.
- Wire `_pkg_pyenv_activate` (currently a no-op) to call it.

For `kind: pip`: add `_pip_ensure_path` that delegates to
`_pyenv_ensure_path` when the target's pyenv dependency is in scope.

## Bigger structural fix (still out of scope)

Generic activation hook in the dispatcher:

```sh
_ucc_driver_activate <kind>
```

`_ucc_driver_action` would call it before every install/update/observe.
The pkg dispatcher already supports this via `_pkg_<be>_activate`; only
the per-driver `_ucc_driver_<kind>_action` callers (the non-pkg ones)
would need to opt in.

## Why this exists

Component runners (e.g. `run_node_stack_from_yaml`) source their own
runtime init at the top, so targets handled *inside* that runner work
fine. Targets in *other* components that happen to use the same driver
kind never benefit, because the dependency check is logical, not
environmental — `node-lts=ok` means "installed", not "on PATH right now".
