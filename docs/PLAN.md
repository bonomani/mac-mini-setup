# PLAN

(empty — see git log for completed work)

## Closed phases

### Phase 4 — Group A: package installers — DONE (partial scope)

Landed in commits `9246a9b`..`80a4ee7`. The new `kind: pkg` driver is the
sole package dispatcher for 41 targets across 6 yaml files, with 8
backends: `brew`, `brew-cask`, `native-pm`, `npm`, `pyenv`, `ollama`,
`vscode`, `curl`. Implicit dependency injection per backend mirrors the
old per-driver `DRIVER_META` behavior.

**Stays separate** (deliberate, documented in commits):

- `kind: pip` — multi-package shape (`probe_pkg` + `install_packages: [...]`)
  doesn't fit the single-ref-per-backend model. Forcing a sub-object backend
  would muddy the cleanest property of the dispatcher. 13 targets remain on
  `kind: pip`.
- `kind: pip-bootstrap` — special bootstrap step.
- `kind: pyenv-brew` — installs pyenv plugins from `pyenv_packages` and writes
  a shell-init snippet. Driver-specific logic that doesn't fit "single ref".
- `kind: nvm` / `kind: nvm-version` — context fields (`nvm_dir`) and
  activation semantics that don't fit the single-ref shape.

### Phase 5 — Group B: GUI / app bundles — partially absorbed

`brew-cask` is already a backend of `kind: pkg` (cf. iterm2, lm-studio). The
remaining `kind: app-bundle` targets (downloading dmg/pkg/zip directly from
upstream) stay separate; their action is wholly different from any
package-manager backend.
