# Mac Mini AI Setup

Scripts to set up a Mac mini (Apple Silicon, 64 GB) as an AI workstation.

## What's installed

| Component | Script | Description |
|-----------|--------|-------------|
| Homebrew | `01-homebrew.sh` | Package manager |
| Git | `02-git.sh` | Version control |
| Docker | `03-docker.sh` | Containers (48 GB RAM allocated) |
| Python | `04-python.sh` | Python 3.12 via pyenv |
| Ollama | `05-ollama.sh` | Local LLMs via Apple Metal (llama3, mistral, qwen-coder…) |
| AI Python Stack | `06-ai-python-stack.sh` | PyTorch (MPS), transformers, LangChain, LlamaIndex, ChromaDB… |
| AI Apps | `07-ai-apps.sh` | Open WebUI, Flowise, n8n, Qdrant (via Docker) |
| Dev Tools | `08-dev-tools.sh` | Node, VSCode, Oh My Zsh, CLI utilities |
| macOS Defaults | `09-macos-defaults.sh` | System tuning (no sleep, performance) |

## Usage

```bash
# Full install
chmod +x install.sh
./install.sh

# Single component
./install.sh 05-ollama

# Multiple components
./install.sh 04-python 06-ai-python-stack
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
