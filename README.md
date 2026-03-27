# Mac Mini AI Setup

Scripts to set up an AI workstation.
macOS remains the primary target, while Linux and WSL run the portable subset
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
| `docs/evidence/ollama-service.declaration.json` | JSON | Example UCC declaration | Illustrative evidence |
| `docs/evidence/ollama-service.result.json` | JSON | Example UCC result | Shows observe/diff/result structure |

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
| `lib/homebrew.sh` | Bash library | Homebrew component logic | Xcode CLT, Homebrew install, analytics-off |
| `lib/git.sh` | Bash library | Git component logic | Package install and global config |
| `lib/python.sh` | Bash library | Python component logic | pyenv, Python version, pip bootstrap |
| `lib/pip_group.sh` | Bash library | Pip group generator | Dynamic AI Python stack targets |
| `lib/docker.sh` | Bash library | Docker component logic | Docker Desktop and resource settings |
| `lib/ollama.sh` | Bash library | Ollama component logic | Installer, service startup, API checks |
| `lib/ollama_models.sh` | Bash library | Ollama model targets | Autopull groups by size preference |
| `lib/ai_apps.sh` | Bash library | AI app stack logic | Compose file install and per-app runtimes |
| `lib/dev_tools.sh` | Bash library | Dev tools logic | VS Code, Node, npm, OMZ, ariaflow |
| `lib/vscode_ext.sh` | Bash library | VS Code extension targets | Dynamic extension install targets |
| `lib/macos_defaults.sh` | Bash library | macOS defaults logic | Parametric config targets and UI restarts |
| `lib/unsloth_studio.sh` | Bash library | Unsloth Studio logic | Setup plus launchd service |
| `lib/system.sh` | Bash library | System composition logic | Derives whole-machine state from governed subsystem targets |

### Tools

| File | Type | Purpose | Key Notes |
|---|---|---|---|
| `tools/read_config.py` | Python | Config reader | YAML access helper built on `yaml.safe_load` |
| `tools/validate_setup_state_artifact.py` | Python | ASM artifact validator | Delegates to external ASM validator |
| `tools/validate_targets_manifest.py` | Python | UCC manifest validator | Checks targets, deps, components, dispatch, runtime endpoints |

### Policy

| File | Type | Purpose | Key Notes |
|---|---|---|---|
| `policy/gates.yaml` | YAML | UIC gates | Hard/soft preflight gate declarations |
| `policy/preferences.yaml` | YAML | UIC preferences | Safe defaults and operator overrides |
| `policy/components.yaml` | YAML | Component policy | Per-component `enabled|disabled|remove` mode declarations |
| `policy/profiles.yaml` | YAML | UCC profiles | Presence/configured/runtime/parametric baselines |

### UCC Software Manifests

| File | Type | Purpose | Key Notes |
|---|---|---|---|
| `ucc/software/homebrew.yaml` | YAML manifest | Homebrew component | Xcode CLT and brew targets |
| `ucc/software/git.yaml` | YAML manifest | Git component | Brew-backed package target |
| `ucc/software/docker.yaml` | YAML manifest | Docker component | Docker Desktop package plus desktop runtime target |
| `ucc/software/python.yaml` | YAML manifest | Python component | pyenv, xz, python, pip targets |
| `ucc/software/ollama.yaml` | YAML manifest | Ollama component | Package, runtime target, evidence, model sets |
| `ucc/software/ai-python-stack.yaml` | YAML manifest | AI Python stack | Pip groups and Unsloth Studio |
| `ucc/software/ai-apps.yaml` | YAML manifest | AI apps stack | Docker Compose targets and runtime endpoints |
| `ucc/software/dev-tools.yaml` | YAML manifest | Dev tools component | VS Code, Node, OMZ, ariaflow, npm |
| `ucc/software/vscode-settings.json` | JSON | VS Code settings patch | Merged into user settings |

### UCC System Manifests

| File | Type | Purpose | Key Notes |
|---|---|---|---|
| `ucc/system/git-config.yaml` | YAML manifest | Git config component | Global git settings |
| `ucc/system/docker-config.yaml` | YAML manifest | Docker config component | Parametric resource settings |
| `ucc/system/macos-defaults.yaml` | YAML manifest | macOS defaults component | Power, Finder, Dock, extension settings |
| `ucc/system/system.yaml` | YAML manifest | System composition component | Declares whole-machine composition over subsystem targets |

### TIC

| File | Type | Purpose | Key Notes |
|---|---|---|---|
| `tic/software/verify.yaml` | YAML | Software verification suite | Imports, package presence, and non-duplicated runtime checks |
| `tic/system/verify.yaml` | YAML | System verification suite | Machine-state checks and verification evidence for `system-composition` |

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
| Homebrew | `ucc/software/homebrew.yaml` | Homebrew plus Xcode Command Line Tools and analytics-off |
| Git | `ucc/software/git.yaml` | Git package install |
| Docker | `ucc/software/docker.yaml` | Docker Desktop install |
| Python | `ucc/software/python.yaml` | pyenv, Python 3.12.3, and pip bootstrap |
| Ollama | `ucc/software/ollama.yaml` | Local LLM runtime plus optional model autopull |
| AI Python Stack | `ucc/software/ai-python-stack.yaml` | PyTorch (MPS), HF, LangChain, LlamaIndex, vector DBs, Jupyter, serving libs, Unsloth Studio |
| AI Apps | `ucc/software/ai-apps.yaml` | Open WebUI, Flowise, OpenHands, n8n, Qdrant via Docker Compose |
| Dev Tools | `ucc/software/dev-tools.yaml` | VS Code, Node 24, npm globals, Oh My Zsh, CLI tools, ariaflow |
| Git Config | `ucc/system/git-config.yaml` | Global git defaults |
| Docker Config | `ucc/system/docker-config.yaml` | Docker memory/CPU/swap/disk resource settings |
| macOS Defaults | `ucc/system/macos-defaults.yaml` | Power, Finder, Dock, and visibility defaults |
| AI Workstation | `ucc/system/system.yaml` | Whole-machine composition target over required governed subsystem targets |
| Verify | `tic/software/verify.yaml`, `tic/system/verify.yaml` | Read-only post-convergence verification, including system-level evidence for `system-composition` |

## Usage

```bash
# Full install
chmod +x install.sh
./install.sh

# Single component
./install.sh ollama

# Multiple components
./install.sh python ai-python-stack
```

## Component Policy

Component participation is controlled in `policy/components.yaml`.

Supported modes:
- `enabled`: include the component in normal runs
- `disabled`: skip the component without treating it as a failure
- `remove`: reserved for future removal handlers; currently reported and skipped safely

Platform support is also declared per component in the `ucc/software/*.yaml`
and `ucc/system/*.yaml` manifests. On unsupported hosts such components are
skipped automatically instead of aborting the whole installer.

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
| Unsloth Studio | http://0.0.0.0:8888 |
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
- Linux or WSL for the portable subset
- Apple Silicon is recommended when you want MPS/Metal acceleration
- 64 GB RAM is recommended for large local model workflows, but not required
