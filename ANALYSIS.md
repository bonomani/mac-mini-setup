# mac-mini-setup Repository Analysis

## Overview

AI Workstation Setup Framework for macOS, Linux, and WSL2 with declarative
orchestration, driver-based package management, and post-convergence verification.

## Architecture

```
install.sh
  ├── UIC (Pre-convergence)
  │   ├── Gate evaluation (1 gate: supported-platform)
  │   └── Preference resolution
  ├── UCC (Convergence)
  │   ├── Component runners (11 components)
  │   ├── Driver dispatch (~32 driver kinds incl. probes)
  │   └── Target orchestration (~147 targets across 11 YAML files)
  ├── TIC (Verification)
  │   └── Software / system verify + integration tests
  └── Summary + Services
```

Live counts come from `ucc/**/*.yaml`. Re-derive with:

```bash
grep -hE 'component:[[:space:]]' ucc -r | awk -F'component:' '{print $2}' | awk '{print $1}' | sort -u
```

## Components

| Component | YAML | Platforms | Targets | Description |
|-----------|------|-----------|---------|-------------|
| software-bootstrap | homebrew.yaml | all | 5 | Xcode CLT, build-deps, Homebrew, analytics |
| cli-tools | cli-tools.yaml | all | 54 | Git, CLI tools, Oh My Zsh, language toolchains |
| node-stack | node-stack.yaml | all | 6 | Node.js, nvm, npm global packages |
| vscode-stack | vscode.yaml | all | 10 | VS Code, extensions, settings |
| docker | docker.yaml | macos | 5 | Docker Desktop + resources + capabilities |
| ai-apps | ai-apps.yaml | all | 16 | Ollama + models + Docker Compose services |
| ai-python-stack | ai-python-stack.yaml | all | 25 | PyTorch, HF, LangChain, pip groups, GPU probes |
| build-tools | build-tools.yaml | all | 3 | Build tools |
| network-services | network-services.yaml | all | 5 | mDNS / network reachability capabilities |
| system | system.yaml | macos | 15 | pmset, defaults, softwareupdate, sudo, composition |
| linux-system | linux.yaml | linux,wsl2 | 3 | Linux/WSL2 system-layer targets |

## Driver Architecture

See `DRIVER_ARCHITECTURE.md` and the generated `docs/driver-feature-matrix.md`
for the authoritative driver inventory.

The driver surface is consolidating around three shared dispatchers — `pkg`
(package install/upgrade across backends), `setting` (declarative config
values), and `service` (runtime lifecycle). Specialized kinds (`pip`,
`custom-daemon`, `script-installer`, `path-export`, …) remain where the
shared dispatchers don't yet cover the semantics.

Key features:
- **Driver-implied dependencies**: drivers declare `depends_on` and `provided_by_tool` — YAML targets don't repeat them
- **Platform-aware `pkg` driver**: dispatches to brew (macOS) or native PM (Linux/WSL2) with GitHub-release fallback
- **Driver schema validation**: required/optional keys enforced at validation time (`tools/validate_targets_manifest.py`)
- **`requires:` field**: declares platform impossibilities (e.g. `requires: linux,wsl2`)
- **Conditional deps**: `target?condition` with OR, version compare, negation
- **Host fingerprint**: os/version/arch/pm/init-system for platform-aware dispatch

## Tests

Run `python3 -m pytest tests/ -q`. Suite size grows with regression coverage;
re-derive with `python3 -m pytest tests/ --collect-only -q | tail -1`.

## Gates

| Gate | Type | Purpose |
|------|------|---------|
| supported-platform | hard/global | Block unsupported platforms |

All other preconditions are **capability targets** (suffix `-available`):
sudo-available, network-available, docker-available, mdns-available,
mps-available, cuda-available, networkquality-available, etc.

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
