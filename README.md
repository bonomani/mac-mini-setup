# Mac Mini AI Setup

Scripts to set up an AI workstation.
macOS remains the primary target, while Linux and WSL2 run the portable subset
and skip unsupported components automatically.
The repo also declares a local system-level composition target so the governed
state can describe the whole machine, not only individual components.

## Governance

- BGS entry: `./BGS.md`
- decision record: `./docs/bgs-decision.md`
- BISS evidence: `./docs/biss-classification.md`
- ASM state model: `./docs/setup-state-model.md`
- ASM state artifact: `./docs/setup-state-artifact.yaml`
- ASM artifact validator: `./tools/validate_setup_state_artifact.py`
- orchestration target graph: `./ucc/`
- orchestration graph validator: `./tools/validate_targets_manifest.py`
- UCC engine: `./lib/ucc.sh`
- UIC preflight: `./lib/uic.sh`
- TIC verification: `./lib/tic.sh`
- manifest formatter: `./tools/format_targets_manifest.py`

## Repository Inventory

### Root

| File | Type | Purpose | Key Notes |
|---|---|---|---|
| `README.md` | Markdown | Project overview | Entry doc for usage and structure |
| `BGS.md` | Markdown/YAML-style | BGS governance entry | Links decision and evidence docs |
| `CLAUDE.md` | Markdown | Local agent instructions | Repo-specific coding guidance |
| `install.sh` | Bash | Main orchestrator | Runs UIC, UCC, TIC, and summaries |
| `clean.py` | Python | Cleanup helper | Removes Python cache and build artifacts |
| `.gitignore` | Git config | Ignore rules | Python, venv, IDE, env, system files |
| `.claude/settings.json` | JSON | Claude tool permissions | Repo-local permission allowlist |

### Docs

| File | Type | Purpose | Key Notes |
|---|---|---|---|
| `docs/bgs-decision.md` | Markdown | BGS decision record | Scope, controls, evidence, limitations |
| `docs/biss-classification.md` | Markdown | BISS classification | Boundary inventory and axis mapping |
| `docs/setup-state-model.md` | Markdown | ASM setup model | States, transitions, admissibility |
| `docs/setup-state-artifact.yaml` | YAML | Example ASM artifact | Validator-backed sample state |
| `docs/evidence/ollama.declaration.json` | JSON | Example UCC declaration | Illustrative evidence |
| `docs/evidence/ollama.result.json` | JSON | Example UCC result | Shows observe/diff/result structure |

### Libraries

| File | Type | Purpose | Key Notes |
|---|---|---|---|
| `lib/ucc.sh` | Bash library | UCC engine entry | Loads core UCC subsystems |
| `lib/ucc_log.sh` | Bash library | Logging and runtime context | Defines run mode, dry-run, correlation ID |
| `lib/ucc_brew.sh` | Bash library | Brew cache helpers | Observes installed and outdated packages |
| `lib/ucc_asm.sh` | Bash library | ASM state helpers | Builds desired/observed state JSON |
| `lib/ucc_artifacts.sh` | Bash library | Artifact writer | Records declaration/result JSONL |
| `lib/ucc_targets.sh` | Bash library | Target lifecycle engine | Implements `ucc_target` and helpers |
| `lib/uic.sh` | Bash library | UIC preflight engine | Gates, preferences, export/template logic |
| `lib/tic.sh` | Bash library | TIC test helper | Read-only verification primitive |
| `lib/tic_runner.sh` | Bash library | TIC YAML runner | Loads test suites and container checks |
| `lib/summary.sh` | Bash library | Summary renderer | Prints final component/profile/runtime summary |
| `lib/utils.sh` | Bash library | Shared helpers | PATH setup, YAML wrappers, install helpers |
| `lib/homebrew.sh` | Bash library | Homebrew component logic | Xcode CLT, build-deps, Homebrew install |
| `lib/pip_group.sh` | Bash library | Pip group generator | Dynamic AI Python stack targets |
| `lib/docker.sh` | Bash library | Docker component logic | Docker Desktop + resources |
| `lib/ollama_models.sh` | Bash library | Ollama model targets | Autopull groups by size preference |
| `lib/ai_apps.sh` | Bash library | AI app stack logic | Compose file + per-app runtimes |
| `lib/cli_tools.sh` | Bash library | CLI tools logic | Git, CLI tools, Oh My Zsh |
| `lib/node_stack.sh` | Bash library | Node stack logic | nvm, Node.js, npm globals |
| `lib/build_tools.sh` | Bash library | Build tools logic | Build tools |
| `lib/vscode_ext.sh` | Bash library | VS Code extension targets | Dynamic extension install targets |
| `lib/unsloth_studio.sh` | Bash library | Unsloth Studio logic | launchd/systemd service |
| `lib/system.sh` | Bash library | System component logic | OS config + composition |

### Tools

| File | Type | Purpose | Key Notes |
|---|---|---|---|
| `tools/read_config.py` | Python | Config reader | YAML access helper built on `yaml.safe_load` |
| `tools/validate_setup_state_artifact.py` | Python | ASM artifact validator | Delegates to external ASM validator |
| `tools/validate_targets_manifest.py` | Python | UCC manifest validator | Checks targets, deps, components, dispatch, runtime endpoints |
| `tools/format_targets_manifest.py` | Python | Manifest formatter | Enforces canonical target key ordering |

### Defaults

| File | Type | Purpose | Key Notes |
|---|---|---|---|
| `defaults/gates.yaml` | YAML | UIC gates | Single hard gate: supported-platform |
| `defaults/preferences.yaml` | YAML | UIC preferences | Safe defaults and operator overrides |
| `defaults/selection.yaml` | YAML | Target selection | Default selection mode and globally disabled targets |
| `defaults/profiles.yaml` | YAML | UCC profiles | Configured/runtime/capability/parametric baselines for convergence targets |

### UCC Software Manifests

| File | Type | Purpose | Key Notes |
|---|---|---|---|
| `ucc/software/homebrew.yaml` | YAML manifest | software-bootstrap | Xcode CLT, build-deps, Homebrew, network probe |
| `ucc/software/docker.yaml` | YAML manifest | docker | Docker Desktop + resources + capabilities |
| `ucc/software/ai-python-stack.yaml` | YAML manifest | ai-python-stack | Pip groups, Unsloth Studio, GPU probes |
| `ucc/software/ai-apps.yaml` | YAML manifest | ai-apps | Ollama + models + Docker Compose services |
| `ucc/software/cli-tools.yaml` | YAML manifest | cli-tools | Git, CLI tools, Oh My Zsh |
| `ucc/software/node-stack.yaml` | YAML manifest | node-stack | Node.js, nvm, npm global packages |
| `ucc/software/vscode.yaml` | YAML manifest | vscode-stack | VS Code, extensions, settings |
| `ucc/software/build-tools.yaml` | YAML manifest | build-tools | Build tools |
| `ucc/software/vscode-settings.json` | JSON | VS Code settings patch | Merged into user settings |

### UCC System Manifests

| File | Type | Purpose | Key Notes |
|---|---|---|---|
| `ucc/system/system.yaml` | YAML manifest | system | OS config (pmset, defaults, softwareupdate) + composition |

### TIC

| File | Type | Purpose | Key Notes |
|---|---|---|---|
| `tic/software/verify.yaml` | YAML | Software verification suite | Imports, package presence, service health |
| `tic/system/verify.yaml` | YAML | System verification suite | Independent health checks + system-composition |
| `tic/software/integration.yaml` | YAML | Integration test suite | Cross-component interaction tests |

### Tests

| File | Type | Purpose | Key Notes |
|---|---|---|---|
| `tests/` | Python | Unit tests | 30 unit tests across 8 test files  |

### Runtime Templates And Scripts

| File | Type | Purpose | Key Notes |
|---|---|---|---|
| `stack/docker-compose.yml` | YAML | AI app compose template | Open WebUI, Flowise, OpenHands, n8n, Qdrant |
| `scripts/ai-healthcheck` | Bash | Local healthcheck helper | Prints versions, extensions, models, containers |
| `scripts/check-langchain-core-version` | Python | Version guard helper | Ensures `langchain-core >= 1.0.0` |
| `scripts/pyenv-zshrc-snippet` | Shell snippet | pyenv shell init | Appended to `.zshrc` during setup |

## Managed Components

The installer is manifest-driven. Components are declared under `ucc/software/`
and `ucc/system/`, then dispatched through `install.sh`.

| Component | Manifest | Description |
|-----------|----------|-------------|
| software-bootstrap | `ucc/software/homebrew.yaml` | Xcode CLT, build-deps, Homebrew, network probe |
| cli-tools | `ucc/software/cli-tools.yaml` | Git, CLI tools, Oh My Zsh |
| node-stack | `ucc/software/node-stack.yaml` | Node.js, nvm, npm global packages |
| vscode-stack | `ucc/software/vscode.yaml` | VS Code, extensions, settings |
| docker | `ucc/software/docker.yaml` | Docker Desktop + resources + capabilities |
| ai-python-stack | `ucc/software/ai-python-stack.yaml` | PyTorch, HF, LangChain, pip groups, GPU probes, Unsloth |
| ai-apps | `ucc/software/ai-apps.yaml` | Ollama + models + Docker Compose services |
| build-tools | `ucc/software/build-tools.yaml` | Build tools |
| system | `ucc/system/system.yaml` | OS config (pmset, defaults, softwareupdate) + composition |
| verify | `tic/` | Post-convergence verification + integration tests |

## Usage

```bash
# Full install
chmod +x install.sh
./install.sh

# Single component
./install.sh ollama

# Multiple components
./install.sh python ai-python-stack

# Start with nothing selected
./install.sh --none
```

If you want admin-gated targets such as `macos-defaults` or
`macos-software-update` to converge in the same run without prompts, open a
non-interactive sudo ticket first:

```bash
sudo -v && ./install.sh
```

## Target Selection

`defaults/selection.yaml` ships repository defaults — read-only at runtime.
User overrides live in `~/.ai-stack/selection.yaml` and persist across runs.
The interactive prompt asks per-target whether to enable or disable, and
writes the choice to the user-local file.

Components are derived from the YAML manifests and serve as pure
organizational grouping. Platform support is declared per component in the
`ucc/software/*.yaml` and `ucc/system/*.yaml` manifests. On unsupported
hosts such components are skipped automatically instead of aborting the
whole installer.

### Display modes

The `skip-display-mode` preference controls output verbosity:
- `full` (default): every target is shown with its current state
- `fast`: hides non-selected targets and unrelated components — good for
  targeted runs like `./install.sh ariaflow`

### Preferred driver policy

When a target is detected installed via a non-preferred driver (e.g.
ollama installed via curl while the preferred driver is brew), the script
prompts inline with three choices: migrate now, ignore permanently, or
warn next run. Permanent ignores are saved to
`~/.ai-stack/target-overrides.yaml` so the prompt only appears once per
target.

## macOS Validation

Run these commands on the target Mac to validate the governed install flow
and the AI app stack behavior end to end:

```bash
# 1. Resolve gates and preferences only
./install.sh --preflight

# 2. Preview AI app stack convergence
./install.sh --dry-run ai-apps

# 3. Apply AI app stack convergence
./install.sh ai-apps

# 4. Run read-only verification
./install.sh verify
```

Expected checkpoints:
- `--preflight` should show `macos-platform` as `ok`
- `--dry-run ai-apps` should evaluate `docker-daemon`, `docker-compose-cli`,
  and `ai-apps-template`
- `ai-apps` should converge `ai-stack-compose-file` plus the per-app
  runtime targets for Open WebUI, Flowise, OpenHands, n8n, and Qdrant
- `verify` should pass the remaining non-duplicated software checks after
  convergence
- `verify` may skip `system-composition-converged` when run standalone,
  because that assertion only applies when the current invocation also
  emitted `system-composition` target status

## Services

| Service | URL |
|---------|-----|
| Ollama API | http://127.0.0.1:11434 |
| Unsloth Studio | http://127.0.0.1:8888 |
| Open WebUI | http://localhost:3000 |
| Flowise | http://localhost:3001 |
| OpenHands | http://localhost:3002 |
| n8n | http://localhost:5678 |
| Qdrant | http://localhost:6333 |
| aria2 RPC | http://127.0.0.1:6800 |
| ariaflow API | http://127.0.0.1:8000 |
| ariaflow web UI | http://127.0.0.1:8001 |

## Requirements

- macOS 14+ for the full workstation profile
- Linux or WSL2 for the portable subset
- Apple Silicon is recommended when you want MPS/Metal acceleration
- 64 GB RAM is recommended for large local model workflows, but not required
