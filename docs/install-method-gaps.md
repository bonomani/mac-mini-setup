# Install Method Coverage Gaps

Which upstream install methods UCC can drive today, using `opencode` as the
reference case (it ships via the widest variety of channels).

## Covered

| Method | Driver | Notes |
|---|---|---|
| `curl … \| bash` | `lib/drivers/curl_installer.sh`, `lib/drivers/script_installer.sh` | No native outdated check |
| `npm i -g <pkg>` | `lib/drivers/npm.sh` | — |
| `brew install <formula>` | `lib/drivers/brew.sh`, meta `lib/drivers/package.sh` | Lags upstream until formula bumps; livecheck opt-in via `UIC_PREF_BREW_LIVECHECK=1` |
| `apt/dnf/pacman/zypper install` | `lib/drivers/package.sh` (native PM branch) | Linux/WSL2 only |

## Partial

| Method | Driver | Gap |
|---|---|---|
| `brew install <user>/<tap>/<formula>` | `lib/drivers/brew.sh` | Install auto-taps and works; **observe is broken**: `_brew_cached_version` (`lib/ucc_brew.sh:61`) does strict `==` against `brew list --versions` output, which uses the short name. A tapped ref always reads as `absent`. Needs either a `driver.tap` field + short ref, or a normalization step in the cache lookup. |

## Not covered

| Method | Reason |
|---|---|
| `scoop install` | Windows only — out of platform scope |
| `choco install` | Windows only — out of platform scope |
| `paru -S` / AUR | No AUR driver; would need a new `lib/drivers/aur.sh` |
| `mise use -g` | No mise driver |
| `nix run nixpkgs#…` / flake refs | No nix driver |

## Method-selection cheat sheet (worked example: `cli-opencode` on macOS)

Use this matrix to pick a method per target. The same axes apply to any tool
that ships through multiple channels.

| Method | Latest? | Auto-upgrade | UCC support | Notes |
|---|---|---|---|---|
| `brew install opencode` | ❌ lags (1.3.10) | ✅ via `brew upgrade` | ✅ full | Maintained by homebrew-core volunteers — slow bumps |
| `brew install anomalyco/tap/opencode` | ✅ tracks upstream | ✅ via `brew upgrade` | ⚠️ install OK, observe broken (tapped-ref bug) | Best fit once the brew-tap gap is fixed |
| `npm i -g opencode-ai` | ✅ latest | ✅ `npm update -g` | ✅ via `npm.sh` | Adds a Node dependency you'd carry anyway (node-stack present) |
| `curl … \| bash` | ✅ latest | ❌ no outdated detection | ⚠️ installs but state always "installed" | Worst observability |
| `mise use -g opencode` | ✅ latest | ✅ | ❌ no driver | Would require new driver |

**Decision rule**: pick the highest-ranked method whose row has ✅ in *both*
"Latest?" and "UCC support". For `cli-opencode` on macOS, that's `npm i -g
opencode-ai` — which is what `cli-opencode` is configured to use today.

### User override

YAML encodes the *default* method. A user must be able to override it on their
own box without editing tracked files. Proposed mechanism:

1. **Per-target env override** — `UCC_DRIVER__<TARGET>=<kind>:<ref>` resolved
   before driver dispatch in `_ucc_driver_observe` /
   `_ucc_driver_action`. Examples:
   ```sh
   export UCC_DRIVER__cli_opencode='brew:opencode'
   export UCC_DRIVER__cli_opencode='curl:https://opencode.ai/install'
   ```
   (target name normalized: `-` → `_`.)

2. **User overlay file** — `~/.config/ucc/overrides.yaml`, merged on top of the
   tracked YAML by `_ucc_yaml_target_get`:
   ```yaml
   cli-opencode:
     driver:
       kind: brew
       ref: opencode
   ```
   Same precedence as the env var, but persistent and diffable.

3. **Precedence** (highest wins):
   `UCC_DRIVER__*` env > `~/.config/ucc/overrides.yaml` > tracked YAML.

4. **Listing** — `install.sh --show-overrides` prints the effective driver per
   target with the source (env/overlay/yaml), so users can audit drift.

This keeps the tracked YAML authoritative for "what we recommend" while letting
each box pin a different method when the default doesn't fit (offline boxes,
no Node, corporate brew mirror, etc.).

## Implications for `cli-opencode`

Today the target uses `kind: package` → brew → homebrew/core formula, which
lags upstream (currently 1.3.10 vs upstream 1.3.17 from `anomalyco/tap`).
Available paths to track the latest:

1. **Fix the tapped-brew gap** above and switch ref to `anomalyco/tap/opencode`.
2. **Switch driver to `npm`** (`opencode-ai` package).
3. **Switch driver to `curl_installer`** (`https://opencode.ai/install`) — loses
   outdated detection entirely.

Option 1 is the cleanest fit for the existing brew-centric stack and would also
unlock other tapped formulae generally.

## Bigger gap: multi-backend per target

Today the `package` meta-driver (`lib/drivers/package.sh`) only knows three
backends in a fixed order: brew → native PM → curl fallback. Targets cannot
declare arbitrary alternatives (npm, mise, nix, AUR, tapped-brew, …) and cannot
express a preference order.

To make every install method available to any target, the meta-driver would
need:

1. **Backend registry** — each method (`brew`, `brew-tap`, `npm`, `pip`,
   `curl`, `mise`, `nix`, `aur`, native-pm) implements a uniform interface:
   `available?`, `is_installed`, `version`, `is_outdated`, `install`, `upgrade`.
2. **Per-target backend list** in YAML, ordered by preference:
   ```yaml
   driver:
     kind: package
     ref: opencode
     backends:
       - brew-tap: anomalyco/tap/opencode
       - npm: opencode-ai
       - brew: opencode
       - curl: https://opencode.ai/install
   ```
3. **Selection policy** — first available backend wins, with optional global
   override (`UIC_PREF_PACKAGE_BACKEND=npm`).
4. **Unified state model** — observe/install/upgrade dispatch to the selected
   backend's functions.
5. **Migration** — existing `driver.ref` / `driver.apt_ref` etc. become sugar
   for a single-backend list.
