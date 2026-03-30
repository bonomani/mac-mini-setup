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
- **28 targets** across software + system layers
- **13 driver kinds** for package/config/runtime management
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
| Driver | observe | action | evidence |
|--------|---------|--------|----------|
| brew-formula | ✅ | ✅ | ✅ |
| brew-cask | ✅ | ✅ | ✅ |
| app-bundle | ✅ | ✅ | ✅ |
| vscode-marketplace | ✅ | ✅ | ✅ |
| ollama-model | ✅ | ✅ | ✅ |
| npm-global | ✅ | ✅ | ✅ |
| pip | ✅ | ✅ | ✅ |
| user-defaults | ✅ | ✅ | ✅ |
| pmset | ✅ | ✅ | ✅ |
| docker-settings | ✅ | ✅ | ✅ |

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
