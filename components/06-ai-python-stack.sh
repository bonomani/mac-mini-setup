#!/usr/bin/env bash
# Component: AI Python Stack (PyTorch MPS + LLM frameworks)
# BGS: UCC + Basic — bash 3.2 compatible (no declare -A)
#
# BISS: Axis A = UCC (state convergence — pip packages installed + launchd service loaded)
#       Axis B = Basic
# Boundary: local filesystem · pip/PyPI (network) · macOS launchd (Unsloth Studio service)

# Helper: define one pip group as a ucc_target
# Usage: _pip_group <name> <first_pkg_to_observe> "<space-separated packages>"
_pip_group() {
  local name="$1" first="$2" pkgs="$3"
  local fn="${name//[^a-zA-Z0-9]/_}"

  eval "_observe_grp_${fn}() { pip_is_installed '${first}' && pip show '${first}' 2>/dev/null | awk '/^Version:/ {print \$2}' || echo 'absent'; }"
  eval "_install_grp_${fn}() { ucc_run pip install -q ${pkgs}; }"
  eval "_update_grp_${fn}()  { ucc_run pip install -q --upgrade ${pkgs}; }"

  ucc_target \
    --name    "pip-group-$name" \
    --observe "_observe_grp_${fn}" \
    --desired "@present" \
    --install "_install_grp_${fn}" \
    --update  "_update_grp_${fn}"
}

_pip_group "pytorch" \
  "torch" \
  "torch torchvision torchaudio"

_pip_group "huggingface" \
  "transformers" \
  "transformers diffusers accelerate datasets tokenizers sentencepiece huggingface-hub peft trl"

# langchain-core must be >=1.0.0 for langgraph + langchain-ollama compatibility.
# Custom observe checks version — forces upgrade if still on 0.x.
_observe_grp_langchain() {
  python3 -c "
import importlib.util, sys
if importlib.util.find_spec('langchain_core') is None: sys.exit(1)
import langchain_core
from packaging.version import Version
sys.exit(0 if Version(langchain_core.__version__) >= Version('1.0.0') else 1)
" 2>/dev/null && python3 -c "import langchain_core; print(langchain_core.__version__)" 2>/dev/null || echo "absent"
}
_install_grp_langchain() {
  ucc_run pip install -q "langchain-core>=1.0.0" langchain langchain-community langchain-ollama langgraph
}
_update_grp_langchain() {
  ucc_run pip install -q --upgrade "langchain-core>=1.0.0" langchain langchain-community langchain-ollama langgraph
}
ucc_target \
  --name    "pip-group-langchain" \
  --observe _observe_grp_langchain \
  --desired "@present" \
  --install _install_grp_langchain \
  --update  _update_grp_langchain

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
  "jupyterlab ipywidgets nbformat"
# Note: jupyter-ai removed — it pins langchain<0.4.0, incompatible with langchain>=1.0.0

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

# Note: the unsloth Python package cannot be imported on Apple Silicon —
# it raises NotImplementedError at import time (NVIDIA/AMD/Intel GPUs only).
# Unsloth Studio runs in its own isolated venv and works on Mac via the CLI.
# Do NOT install the pip package — it is unused and untestable on this platform.

# --- Unsloth Studio setup (downloads frontend, creates venv) ---
_observe_unsloth_studio_setup() {
  [[ -d "$HOME/.unsloth/studio" ]] && echo "present" || echo "absent"
}
_run_unsloth_studio_setup() {
  ucc_run unsloth studio setup
}

ucc_target \
  --name    "unsloth-studio-setup" \
  --observe _observe_unsloth_studio_setup \
  --desired "@present" \
  --install _run_unsloth_studio_setup \
  --update  _run_unsloth_studio_setup

# --- Unsloth Studio — launchd (port 8888, survives reboot) ---
UNSLOTH_PLIST="$HOME/Library/LaunchAgents/ai.unsloth.studio.plist"

# launchd does not load pyenv shims — resolve the absolute binary path now
UNSLOTH_BIN="$(pyenv which unsloth 2>/dev/null || command -v unsloth)"

UNSLOTH_PLIST_MARKER="<!-- ai.unsloth.studio v2 -->"

_observe_unsloth_studio_launchd() {
  launchctl list 2>/dev/null | grep -q "ai.unsloth.studio" || { echo "absent"; return; }
  grep -qF "$UNSLOTH_PLIST_MARKER" "$UNSLOTH_PLIST" 2>/dev/null || { echo "outdated"; return; }
  echo "loaded"
}

_install_unsloth_studio_launchd() {
  mkdir -p "$(dirname "$UNSLOTH_PLIST")"
  cat > "$UNSLOTH_PLIST" <<PLIST
${UNSLOTH_PLIST_MARKER}
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>             <string>ai.unsloth.studio</string>
  <key>ProgramArguments</key>
  <array>
    <string>${UNSLOTH_BIN}</string>
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

# Verify Metal/MPS availability
if [[ "$UCC_DRY_RUN" != "1" ]] && is_installed python3; then
  _mps=$(python3 -c "import torch; print('available' if torch.backends.mps.is_available() else 'not available (CPU only)')" 2>/dev/null || true)
  [[ -n "$_mps" ]] && log_info "MPS (Metal) GPU: $_mps"
fi

ucc_summary "06-ai-python-stack"
