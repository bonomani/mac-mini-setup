# Install Method Coverage Gaps

Which upstream install methods UCC can drive today, after Phase 4 (the
unified `kind: pkg` driver with backend registry).

## Covered (via `kind: pkg` backends)

| Method | Backend | Outdated | Notes |
|---|---|---|---|
| `brew install <formula>` | `brew` | ✅ (livecheck opt-in) | Lags upstream until formula bumps; `UIC_PREF_BREW_LIVECHECK=1` catches the lag |
| `brew install <user>/<tap>/<formula>` | `brew` | ✅ | Tap auto-installs; `_brew_cached_version` strips tap prefix (fixed in commit `ae16139`) |
| `brew install --cask <name>` | `brew-cask` | ✅ (with `--greedy` when `driver.greedy_auto_updates: true`) | macOS GUI apps |
| `apt/dnf/pacman/zypper install` | `native-pm` | ❌ | Linux/WSL2 only |
| `npm i -g <pkg>` | `npm` | ✅ (opt-in) | `npm outdated -g --json` cached per process |
| `pyenv install <ver>` | `pyenv` | ❌ | |
| `ollama pull <model>` | `ollama` | ❌ | |
| `code --install-extension <id>` | `vscode` | ❌ | |
| `curl … \| bash` | `curl` | ❌ | `driver.curl_args` for `-y` and similar |

## Still separate (deliberate, documented)

| Method | Driver | Reason |
|---|---|---|
| `pip install <pkg> [<pkg>…]` | `kind: pip` | Multi-package shape (`probe_pkg` + `install_packages: [...]`) doesn't fit single-ref backend model |
| `pyenv` brew install + plugin/init | `kind: pyenv-brew` | Installs `pyenv_packages` plugins and writes a shell-init snippet |
| `nvm` install + version | `kind: nvm` / `nvm-version` | Carries `nvm_dir` context and self-sources `nvm.sh` in subshells |
| Pip bootstrap | `kind: pip-bootstrap` | Special bootstrap step |
| Direct dmg/pkg/zip download | `kind: app-bundle` | Action is wholly different from any package-manager backend |
| `git clone` | `kind: git-repo` | Single-purpose; already has outdated detection |

## Not covered

| Method | Reason |
|---|---|
| `scoop install` | Windows only — out of platform scope |
| `choco install` | Windows only — out of platform scope |
| `paru -S` / AUR | No `aur` backend; would slot into `pkg` if added |
| `mise use -g` | No `mise` backend |
| `nix run nixpkgs#…` / flake refs | No `nix` backend |

## Method-selection cheat sheet

Targets that can be installed via multiple channels declare them in
preference order under `driver.backends`. The first backend whose
`_pkg_<be>_available` returns true wins. Example (`cli-opencode`):

```yaml
driver:
  kind: pkg
  backends:
  - npm: opencode-ai
  - brew: opencode
  bin: opencode
  github_repo: sst/opencode
```

On a Mac mini with brew + node both present, npm wins (first in the list).
Override per box without editing tracked YAML — see "User override" below.

| Method | Latest? | Auto-upgrade | UCC support |
|---|---|---|---|
| `brew install <formula>` | ❌ lags | ✅ | ✅ via `pkg` |
| `brew install --cask <name>` | ✅ (greedy) | ✅ | ✅ via `pkg` |
| `brew install <tap>/<formula>` | ✅ | ✅ | ✅ via `pkg` (tapped refs work) |
| `npm i -g <pkg>` | ✅ | ✅ (opt-in) | ✅ via `pkg` |
| `pyenv install <ver>` | ✅ | ❌ | ✅ via `pkg` |
| `ollama pull <model>` | ✅ (per tag) | ❌ | ✅ via `pkg` |
| `vscode-marketplace` | ✅ | ❌ | ✅ via `pkg` |
| `apt/dnf/pacman/zypper` | ✅ | ❌ | ✅ via `pkg` |
| `curl … \| bash` | ✅ | ❌ | ✅ via `pkg` (no observability) |
| `pip install` (multi-pkg) | ✅ | ❌ | ✅ via separate `kind: pip` |
| `mise use -g` | ✅ | ✅ | ❌ no backend |
| `paru -S` (AUR) | ✅ | ✅ | ❌ no backend |

**Decision rule**: pick the highest-ranked method that works on the box and
that you actually have a backend for. The dispatcher does this automatically
once you list the backends in YAML order.

## User override

Implemented in commit `8b7e8e6`. Three layers, highest precedence first:

1. **Env var** — `UCC_OVERRIDE__<TARGET>__<KEY>=<value>` (target `-` → `_`,
   key `.` → `_`):
   ```sh
   UCC_OVERRIDE__cli_opencode__driver_kind=brew \
   UCC_OVERRIDE__cli_opencode__driver_ref=opencode \
   ./install.sh cli-opencode
   ```
2. **Overlay file** — `~/.ai-stack/target-overrides.yaml`, top-level
   `target-overrides:` key (coexists with `preferred-driver-ignore:`):
   ```yaml
   target-overrides:
     cli-opencode:
       driver:
         kind: pkg
         backends:
         - brew: opencode
   ```
3. **Tracked YAML** — repo defaults.

Listing: `./install.sh --show-overrides` prints effective overrides with
their source (env / overlay).

Limitation: env-var overrides are scalar-only. List fields (`driver.backends`)
must be set via the overlay file, not env vars.
