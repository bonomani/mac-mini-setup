#!/usr/bin/env bash
# Component: AI Python Stack (PyTorch MPS + LLM frameworks)
# UCC + Basic — bash 3.2 compatible (no declare -A)

# Helper: define one pip group as a ucc_target
# Usage: _pip_group <name> <first_pkg_to_observe> "<space-separated packages>"
_pip_group() {
  local name="$1" first="$2" pkgs="$3"
  local fn="${name//[^a-zA-Z0-9]/_}"

  eval "_observe_grp_${fn}() { pip_is_installed '${first}' && echo 'installed' || echo 'absent'; }"
  eval "_install_grp_${fn}() { ucc_run pip install -q ${pkgs}; }"
  eval "_update_grp_${fn}()  { ucc_run pip install -q --upgrade ${pkgs}; }"

  ucc_target \
    --name    "pip-group-$name" \
    --observe "_observe_grp_${fn}" \
    --desired "installed" \
    --install "_install_grp_${fn}" \
    --update  "_update_grp_${fn}"
}

_pip_group "pytorch" \
  "torch" \
  "torch torchvision torchaudio"

_pip_group "huggingface" \
  "transformers" \
  "transformers diffusers accelerate datasets tokenizers sentencepiece huggingface-hub peft trl"

_pip_group "langchain" \
  "langchain" \
  "langchain langchain-community langchain-ollama langgraph"

_pip_group "llamaindex" \
  "llama-index" \
  "llama-index llama-index-llms-ollama llama-index-embeddings-ollama"

_pip_group "llm-clients" \
  "openai" \
  "openai anthropic"

_pip_group "vector-dbs" \
  "chromadb" \
  "chromadb faiss-cpu qdrant-client"

_pip_group "jupyter" \
  "jupyterlab" \
  "jupyterlab ipywidgets jupyter-ai nbformat"

_pip_group "serving" \
  "fastapi" \
  "fastapi uvicorn gradio"

_pip_group "data-science" \
  "numpy" \
  "numpy pandas scipy scikit-learn matplotlib seaborn"

_pip_group "utilities" \
  "python-dotenv" \
  "python-dotenv rich tqdm"

_pip_group "optimum" \
  "optimum" \
  "optimum"

# Verify Metal/MPS availability
if [[ "$UCC_DRY_RUN" != "1" ]] && is_installed python3; then
  python3 - <<'EOF' 2>/dev/null || true
import torch
if torch.backends.mps.is_available():
    print("MPS (Metal) GPU acceleration: available")
else:
    print("MPS (Metal) GPU acceleration: not available (CPU only)")
EOF
fi

ucc_summary "06-ai-python-stack"
