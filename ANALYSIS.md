# mac-mini-setup Repository Analysis

## Overview
This is an AI Workstation Setup Framework for macOS with comprehensive governance and orchestration capabilities.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         ai-stack                                    │
├─────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐    ┌──────────────────┐    ┌───────────────┐ │
│  │     UCC          │    │      TIC         │    │     BGS       │ │
│  │   (Orchestration)│    │   (Verification) │    │ (Compliance)  │ │
│  │ - Declarative    │    │ - Read-only      │    │ - ASM State   │ │
│  │   targets (YAML) │    │   verification   │    │ - Boundary    │ │
│  │ - Convergence    │    │   suites         │    │   Governance  │ │
│  │   engine         │    │                  │    │               │ │
│  └────────┬─────────┘    └──────────────────┘    └───────────────┘ │
│           │                                                          │
│  ┌────────▼─────────┐    ┌──────────────────┐                      │
│  │      UIC         │    │     ASM          │                      │
│  │   (Preflight)    │    │ State Model      │                      │
│  │ - Gates          │    │ - 5 state axes   │                      │
│  │ - Preferences    │    │ - Admissible     │                      │
│  └────────┬─────────┘    └──────────────────┘                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. UCC (Universal Convergence Contract) - v370c1f7
- **94 orchestration targets** across software + system layers
- **17 driver kinds** across three classes: install (7), config (6), runtime (4)
- All P1–P8 architecture principles fully applied (see `DRIVER_ARCHITECTURE.md`)
- Topological ordering via dependency graph
- Three-field result model: observation + outcome + completion

### 2. TIC (Test Intent Contract) - v7cfba80
- Read-only verification suites
- Evidence generation for compliance

### 3. UIC (Universal Intent Contract) - v11bd400
- Preflight gate evaluation
- Preference resolution with safe defaults

### 4. BGS (Boundary Governance Suite)
- ASM-aligned state model
- 5-state axes: installation, runtime, health, admin, dependencies

## UIC Preferences
| Preference | Default | Options | Rationale |
|------------|---------|---------|-----------|
| python-version | 3.12.3 | 3.11.9\|3.12.3\|3.13.0 | 3.12.3 tested stable with ML library support |
| docker-memory-gb | 48 | 16\|32\|48\|56 | Leaves 16GB for macOS on 64GB machine |
| docker-cpu-count | 10 | 4\|6\|8\|10\|12 | 10 cores leaves 2 for macOS |
| docker-swap-mib | 4096 | 1024\|2048\|4096\|8192 | Adequate for AI workloads |
| docker-disk-mib | 204800 | 102400\|204800\|307200\|512000 | 200GB covers AI models |
| ollama-model-autopull | none | none\|small\|medium\|large | Controls automatic model downloads |
| pytorch-device | mps | mps\|cpu | Metal GPU acceleration on Apple Silicon |
| ai-apps-image-policy | reuse-local | reuse-local\|always-pull | Image update behavior |
| service-policy | autostart | manual\|autostart | Service startup control |

## Governance Gates
| Gate | Scope | Class | Blocking |
|------|-------|-------|----------|
| supported-platform | global | readiness | hard |
| apple-silicon | ai-python-stack | readiness | soft |
| docker-daemon | ai-apps | readiness | soft |
| ollama-api | ollama | readiness | soft |
| sudo-available | macos-defaults | authorization | soft |
| docker-settings-file | docker-config | readiness | soft |

## Driver Architecture

All 17 drivers are fully compliant and governed by 8 architecture principles documented in
`DRIVER_ARCHITECTURE.md`. Drivers are separated into three classes mapped to target `type:`.
Config drivers additionally implement `_apply` (dedicated verb for configuration targets).

**Install drivers** (`type: package`) — observe version/presence, install, update

| Driver | target type | observe | action | evidence | Notes |
|---|---|:---:|:---:|:---:|---|
| brew | package | ✅ | ✅ | ✅ | cask=true for casks; previous_ref → force-link |
| app-bundle | package | ✅ | ✅ | ✅ | delegates to brew-cask when cask installed; API-based outdated detection |
| vscode-marketplace | package | ✅ | ✅ | ✅ | |
| ollama-model | package | ✅ | ✅ | ✅ | |
| npm-global | package | ✅ | ✅ | ✅ | |
| pip | package | ✅ | ✅ | ✅ | min_version constraint support |
| pyenv-version | package | ✅ | ✅ | ✅ | respects UIC_PREF_PYTHON_VERSION override |

**Config drivers** (`type: config`, `type: bool`) — observe configured/absent, apply settings

| Driver | target type | observe | action | evidence | Notes |
|---|---|:---:|:---:|:---:|---|
| json-merge | config | ✅ | ✅ | ✅ | Python-based JSON patch |
| user-defaults | config/bool | ✅ | ✅ | ✅ | macOS defaults write |
| pmset | config | ✅ | ✅ | ✅ | power management |
| softwareupdate-defaults | config/bool | ✅ | ✅ | ✅ | macOS software update flags |
| brew-analytics | config | ✅ | ✅ | ✅ | |
| docker-settings | config | ✅ | ✅ | ✅ | |

**Runtime drivers** (`type: runtime`) — observe running/stopped, start/stop service

| Driver | target type | observe | action | evidence | Notes |
|---|---|:---:|:---:|:---:|---|
| brew-service | runtime | ✅ | ✅ | ✅ | start/stop via brew services |
| launchd | runtime | ✅ | ✅ | ✅ | load/unload via launchctl |
| custom-daemon | runtime | ✅ | — | ✅ | observe only; started externally |
| compose-file | runtime | ✅ | — | ✅ | observe file exists; managed by compose |

> **Planned**: Formalize the 3-class separation with dedicated dispatch verbs (`apply` for
> config, `start`/`stop`/`restart` for runtime) and validator enforcement of class–type
> alignment. See todo list.

## Compliant Targets
| Component | Manifest | Description |
|-----------|----------|-------------|
| Homebrew | ucc/software/homebrew.yaml | Brew + Xcode CLT |
| Git | ucc/software/git.yaml | Package install |
| Docker | ucc/software/docker.yaml | Docker Desktop + settings |
| Python | ucc/software/python.yaml | pyenv + Python 3.12.3 |
| Ollama | ucc/software/ollama.yaml | Local LLM runtime + model autopull |
| AI Python Stack | ucc/software/ai-python-stack.yaml | PyTorch, HF, LangChain |
| AI Apps | ucc/software/ai-apps.yaml | Docker Compose apps stack |
| Dev Tools | ucc/software/dev-tools.yaml | VS Code, Node, OMZ |
| System | ucc/system/*.yaml | Whole-machine compose |

## Usage
```bash
./install.sh                    # Full install
./install.sh --dry-run          # Preview changes
./install.sh ollama             # Single component
./install.sh --mode update      # Update all
./install.sh --preflight        # Check gates/prefs only
```

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

## Framework Versions
- UCC: v370c1f7
- UIC: v11bd400
