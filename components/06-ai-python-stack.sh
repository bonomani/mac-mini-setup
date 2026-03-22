#!/usr/bin/env bash
# Component: AI Python Stack (PyTorch MPS + LLM frameworks)
# UCC + Basic — bash 3.2 compatible (no declare -A)

# Helper: define one pip group as a ucc_target
# Usage: _pip_group <name> <first_pkg_to_observe> "<space-separated packages>"
_pip_group() {
  local name="$1" first="$2" pkgs="$3"
  local fn="${name//[^a-zA-Z0-9]/_}"

  eval "_observe_grp_${fn}() { pip_is_installed '${first}' && echo 'current' || echo 'absent'; }"
  eval "_install_grp_${fn}() { ucc_run pip install -q ${pkgs}; }"
  eval "_update_grp_${fn}()  { ucc_run pip install -q --upgrade ${pkgs}; }"

  ucc_target \
    --name    "pip-group-$name" \
    --observe "_observe_grp_${fn}" \
    --desired "current" \
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

_pip_group "unsloth" \
  "unsloth" \
  "unsloth[studio]"

# --- Unsloth Studio — launchd (port 8888, survives reboot) ---
UNSLOTH_PLIST="$HOME/Library/LaunchAgents/ai.unsloth.studio.plist"

_observe_unsloth_studio_launchd() {
  launchctl list 2>/dev/null | grep -q "ai.unsloth.studio" && echo "loaded" || echo "absent"
}

_install_unsloth_studio_launchd() {
  local python_bin
  python_bin="$(command -v python3)"
  local unsloth_bin
  unsloth_bin="$(command -v unsloth 2>/dev/null || dirname "$python_bin")/unsloth"
  mkdir -p "$(dirname "$UNSLOTH_PLIST")"
  cat > "$UNSLOTH_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>             <string>ai.unsloth.studio</string>
  <key>ProgramArguments</key>
  <array>
    <string>${unsloth_bin}</string>
    <string>studio</string>
    <string>-H</string><string>0.0.0.0</string>
    <string>-p</string><string>8888</string>
  </array>
  <key>RunAtLoad</key>         <true/>
  <key>KeepAlive</key>         <true/>
  <key>StandardOutPath</key>   <string>${HOME}/.unsloth-studio.log</string>
  <key>StandardErrorPath</key> <string>${HOME}/.unsloth-studio.log</string>
  <key>WorkingDirectory</key>  <string>${HOME}</string>
</dict>
</plist>
PLIST
  ucc_run launchctl load "$UNSLOTH_PLIST"
}

_update_unsloth_studio_launchd() {
  launchctl unload "$UNSLOTH_PLIST" 2>/dev/null || true
  _install_unsloth_studio_launchd
}

ucc_target \
  --name    "unsloth-studio-launchd" \
  --observe _observe_unsloth_studio_launchd \
  --desired "loaded" \
  --install _install_unsloth_studio_launchd \
  --update  _update_unsloth_studio_launchd

log_info "Unsloth Studio → http://0.0.0.0:8888"

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
