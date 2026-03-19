#!/usr/bin/env bash
# Component: AI Python Stack (PyTorch MPS + LLM frameworks)
# UCC + Basic

# Groups of pip packages — each group is one UCC target
declare -A PKG_GROUPS=(
  ["pytorch"]="torch torchvision torchaudio"
  ["huggingface"]="transformers diffusers accelerate datasets tokenizers sentencepiece huggingface-hub peft trl"
  ["langchain"]="langchain langchain-community langchain-ollama"
  ["llamaindex"]="llama-index llama-index-llms-ollama llama-index-embeddings-ollama"
  ["llm-clients"]="openai anthropic"
  ["vector-dbs"]="chromadb faiss-cpu qdrant-client"
  ["jupyter"]="jupyterlab ipywidgets jupyter-ai nbformat"
  ["serving"]="fastapi uvicorn gradio"
  ["data-science"]="numpy pandas scipy scikit-learn matplotlib seaborn"
  ["utilities"]="python-dotenv rich tqdm"
)

# Observe: check if the first package in the group is installed
# (proxy for the group being installed)
_make_observe() {
  local first_pkg="$1"
  echo "pip_is_installed $first_pkg && echo 'installed' || echo 'absent'"
}

_make_install() {
  local pkgs="$1"
  echo "pip install $pkgs"
}

_make_update() {
  local pkgs="$1"
  echo "pip install --upgrade $pkgs"
}

for group in "${!PKG_GROUPS[@]}"; do
  pkgs="${PKG_GROUPS[$group]}"
  first_pkg="${pkgs%% *}"  # first package in the list

  eval "_observe_${group}() { pip_is_installed '$first_pkg' && echo 'installed' || echo 'absent'; }"
  eval "_install_${group}() { ucc_run pip install $pkgs; }"
  eval "_update_${group}()  { ucc_run pip install --upgrade $pkgs; }"

  ucc_target \
    --name    "pip-group-$group" \
    --observe "_observe_${group}" \
    --desired "installed" \
    --install "_install_${group}" \
    --update  "_update_${group}"
done

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
