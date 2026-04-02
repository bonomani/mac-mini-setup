# mac-mini-setup Repository Analysis

## Overview

AI Workstation Setup Framework for macOS, Linux, and WSL2 with declarative
orchestration, driver-based package management, and post-convergence verification.

## Architecture

```
install.sh
  ├── UIC (Pre-convergence)
  │   ├── Gate evaluation (1 gate: supported-platform)
  │   └── Preference resolution (13 preferences)
  ├── UCC (Convergence)
  │   ├── Component runners (7 components)
  │   ├── Driver dispatch (30 driver kinds)
  │   └── Target orchestration (100+ targets)
  ├── TIC (Verification)
  │   ├── Software verify (11 tests)
  │   ├── System verify (6 tests)
  │   └── Integration tests (6 tests)
  └── Summary + Services
```

## Components

| Component | YAML | Platforms | Targets | Description |
|-----------|------|-----------|---------|-------------|
| software-bootstrap | homebrew.yaml | all | 5 | Xcode CLT, build-deps, Homebrew, analytics, network |
| dev-tools | dev-tools.yaml | all | 51 | Git, Python, Node, CLI tools, VS Code, OMZ |
| docker | docker.yaml | macos | 4 | Docker Desktop + resources + capabilities |
| ai-apps | ai-apps.yaml | all | 16 | Ollama + models + Docker Compose services |
| ai-python-stack | ai-python-stack.yaml | all | 18 | PyTorch, HF, LangChain, pip groups, GPU probes |
| macos-config | macos-config.yaml | macos | 14 | pmset, defaults, softwareupdate, sudo probe |
| system | system.yaml | macos | 1 | Host composition meta-target |

## Driver Architecture

30 driver kinds across 4 classes. See `DRIVER_ARCHITECTURE.md` for full details.

- **Package** (13): `package`, `brew`, `app-bundle`, `pip`, `npm-global`, `pyenv-brew`,
  `pyenv-version`, `nvm`, `nvm-version`, `vscode-marketplace`, `ollama-model`, `pip-bootstrap`, `build-deps`
- **Config** (14): `brew-analytics`, `brew-unlink`, `json-merge`, `user-defaults`, `pmset`,
  `softwareupdate-defaults`, `softwareupdate-schedule`, `docker-settings`, `cli-symlink`,
  `script-installer`, `zsh-config`, `path-export`, `bin-script`, `git-global`
- **Runtime** (5): `brew-service`, `docker-compose-service`, `launchd`, `custom-daemon`, `compose-file`

Key features:
- **Driver-implied dependencies**: drivers declare `depends_on` and `provided_by_tool` — YAML targets don't repeat them
- **Platform-aware `package` driver**: dispatches to brew (macOS) or apt/dnf/pacman (Linux/WSL2)
- **Driver schema validation**: required/optional keys enforced at validation time

## Gates

| Gate | Type | Purpose |
|------|------|---------|
| supported-platform | hard/global | Block unsupported platforms |

All other preconditions are now **capability/precondition targets**: sudo-available,
docker-settings-file, networkquality-available, ai-apps-template, network-available,
docker-available, mps-available, cuda-available.

## Usage

```bash
./install.sh                    # Full install
./install.sh --dry-run          # Preview changes
./install.sh --mode check       # Drift detection (observe only)
./install.sh --mode update      # Update all
./install.sh --interactive      # Prompt for prefs + confirm each change
./install.sh --preflight        # Check gates/prefs only
./install.sh ai-apps            # Single component
./install.sh ollama             # Single target
```

## Services

| Service | URL |
|---------|-----|
| Ollama API | http://127.0.0.1:11434 |
| Ariaflow API | http://127.0.0.1:8000 |
| Ariaflow Web | http://127.0.0.1:8001 |
| Open WebUI | http://localhost:3000 |
| Flowise | http://localhost:3001 |
| OpenHands | http://localhost:3002 |
| n8n | http://localhost:5678 |
| Qdrant | http://localhost:6333 |
| Unsloth Studio | http://127.0.0.1:8888 |
