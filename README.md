# Mac Mini AI Setup

Scripts to set up a Mac mini (Apple Silicon, 64 GB) as an AI workstation.

## Governance

- BGS entry: `./BGS.md`
- decision record: `./docs/bgs-decision.md`
- BISS evidence: `./docs/biss-classification.md`
- ASM state model: `./docs/setup-state-model.md`
- ASM state artifact: `./docs/setup-state-artifact.yaml`
- ASM artifact validator: `./tools/validate_setup_state_artifact.py`
- orchestration target graph: `./targets/`
- orchestration graph validator: `./tools/validate_targets_manifest.py`
- UCC engine: `./lib/ucc.sh`
- UIC preflight: `./lib/uic.sh`
- TIC verification: `./lib/tic.sh`

## What's installed

| Component | Script | Description |
|-----------|--------|-------------|
| Homebrew | `homebrew.sh` | Package manager |
| Git | `git.sh` | Version control |
| Docker | `docker.sh` | Containers (48 GB RAM allocated) |
| Python | `python.sh` | Python 3.12 via pyenv |
| Ollama | `ollama.sh` | Local LLMs via Apple Metal (llama3, mistral, qwen-coder…) |
| AI Python Stack | `ai-python-stack.sh` | PyTorch (MPS), transformers, LangChain, LlamaIndex, ChromaDB… |
| AI Apps | `ai-apps.sh` | Open WebUI, Flowise, n8n, Qdrant (via Docker) |
| Dev Tools | `dev-tools.sh` | Node, VSCode, Oh My Zsh, CLI utilities |
| macOS Defaults | `macos-defaults.sh` | System tuning (no sleep, performance) |

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

## Services

| Service | URL |
|---------|-----|
| Open WebUI (Ollama chat) | http://localhost:3000 |
| Flowise (LLM flows) | http://localhost:3001 |
| n8n (automation) | http://localhost:5678 |
| Qdrant (vector DB) | http://localhost:6333 |
| Ollama API | http://localhost:11434 |

## Requirements

- macOS 14+ (Sonoma or later)
- Apple Silicon (M1/M2/M3/M4)
- 64 GB unified memory
