#!/usr/bin/env bash
# Component: TIC verification suite
# BGS suite — TIC verification layer
#
# BISS: Axis A = GIC (read-only observation — no convergence side-effects)
#       Axis B = Basic
# Boundary: local filesystem + system APIs + HTTP (read-only probes only)
#
# This component verifies the observable outcomes of all prior UCC components.
# It does NOT mutate state. It MUST run last (after all UCC components).
#
# TIC SPEC compliance:
#   - Each tic_test declares: name, intent, oracle, trace
#   - Oracle exit code is the sole truth signal (pass=0, fail≠0)
#   - Diagnostics (observed output) are captured and emitted on failure
#   - Skip reason is explicit when a test is not applicable

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DIR/lib/tic.sh"

# Load AI service list from config (shared with 07-ai-apps)
_AI_SERVICES=()
while IFS= read -r _s; do [[ -n "$_s" ]] && _AI_SERVICES+=("$_s"); done \
  < <(python3 "$DIR/tools/read_config.py" --list "$DIR/config/07-ai-apps.yaml" services 2>/dev/null)
# Fallback if config unavailable
[[ ${#_AI_SERVICES[@]} -gt 0 ]] || _AI_SERVICES=(open-webui flowise openhands n8n qdrant)

# Load node version and ariaflow ports from config
_NODE_VER="$(python3 "$DIR/tools/read_config.py" --get "$DIR/config/08-dev-tools.yaml" node_version 2>/dev/null)"
_NODE_VER="${_NODE_VER:-24}"
_ARIA2_PORT="$(python3 "$DIR/tools/read_config.py" --get "$DIR/config/08-dev-tools.yaml" aria2_port 2>/dev/null)"
_ARIA2_PORT="${_ARIA2_PORT:-6800}"
_ARIAFLOW_WEB_PORT="$(python3 "$DIR/tools/read_config.py" --get "$DIR/config/08-dev-tools.yaml" ariaflow_web_port 2>/dev/null)"
_ARIAFLOW_WEB_PORT="${_ARIAFLOW_WEB_PORT:-8001}"

# Load Ollama API config
_OLLAMA_API_HOST="$(python3 "$DIR/tools/read_config.py" --get "$DIR/config/05-ollama.yaml" api_host 2>/dev/null)"
_OLLAMA_API_HOST="${_OLLAMA_API_HOST:-127.0.0.1}"
_OLLAMA_API_PORT="$(python3 "$DIR/tools/read_config.py" --get "$DIR/config/05-ollama.yaml" api_port 2>/dev/null)"
_OLLAMA_API_PORT="${_OLLAMA_API_PORT:-11434}"

# Load Unsloth Studio config
_UNSLOTH_PORT="$(python3 "$DIR/tools/read_config.py" --get "$DIR/config/06-ai-python-stack.yaml" unsloth_studio.port 2>/dev/null)"
_UNSLOTH_PORT="${_UNSLOTH_PORT:-8888}"
_UNSLOTH_LABEL="$(python3 "$DIR/tools/read_config.py" --get "$DIR/config/06-ai-python-stack.yaml" unsloth_studio.label 2>/dev/null)"
_UNSLOTH_LABEL="${_UNSLOTH_LABEL:-ai.unsloth.studio}"
_UNSLOTH_STUDIO_DIR="$HOME/$(python3 "$DIR/tools/read_config.py" --get "$DIR/config/06-ai-python-stack.yaml" unsloth_studio.studio_dir 2>/dev/null)"
_UNSLOTH_STUDIO_DIR="${_UNSLOTH_STUDIO_DIR:-$HOME/.unsloth/studio}"

# Load pyenv shims so python3/pip/unsloth resolve correctly
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"

# Load node path
if [[ -d "/opt/homebrew/opt/node@${_NODE_VER}/bin" ]]; then
  export PATH="/opt/homebrew/opt/node@${_NODE_VER}/bin:$PATH"
elif [[ -d "/usr/local/opt/node@${_NODE_VER}/bin" ]]; then
  export PATH="/usr/local/opt/node@${_NODE_VER}/bin:$PATH"
fi

# ──────────────────────────────────────────────────────────────
# 01-homebrew
# ──────────────────────────────────────────────────────────────
tic_test \
  --name   "brew-installed" \
  --intent "brew must be present and functional" \
  --oracle "brew --version >/dev/null 2>&1" \
  --trace  "component:01-homebrew / ucc-target:homebrew"

tic_test \
  --name   "xcode-clt-installed" \
  --intent "Xcode Command Line Tools must be present (brew dependency)" \
  --oracle "xcode-select -p >/dev/null 2>&1" \
  --trace  "component:01-homebrew / ucc-target:xcode-command-line-tools"

tic_test \
  --name   "brew-analytics-off" \
  --intent "brew analytics must be disabled" \
  --oracle "brew analytics state 2>/dev/null | grep -qi disabled" \
  --trace  "component:01-homebrew / ucc-target:brew-analytics=off"

# ──────────────────────────────────────────────────────────────
# 02-git
# ──────────────────────────────────────────────────────────────
tic_test \
  --name   "git-installed" \
  --intent "git must be present" \
  --oracle "git --version >/dev/null 2>&1" \
  --trace  "component:02-git / ucc-target:git"

tic_test \
  --name   "git-user-configured" \
  --intent "git global user.name must be set" \
  --oracle "git config --global user.name >/dev/null 2>&1" \
  --trace  "component:02-git / ucc-target:git-global-config"

# ──────────────────────────────────────────────────────────────
# 03-docker
# ──────────────────────────────────────────────────────────────
tic_test \
  --name   "docker-app-installed" \
  --intent "Docker Desktop must be installed" \
  --oracle "[[ -d /Applications/Docker.app ]]" \
  --trace  "component:03-docker / ucc-target:docker-desktop"

tic_test \
  --name   "docker-daemon-running" \
  --intent "Docker daemon must be running" \
  --oracle "docker info >/dev/null 2>&1" \
  --trace  "component:03-docker / ucc-target:docker-desktop"

# ──────────────────────────────────────────────────────────────
# 04-python
# ──────────────────────────────────────────────────────────────
tic_test \
  --name   "xz-installed" \
  --intent "xz must be installed before Python is compiled (lzma dependency)" \
  --oracle "brew list xz >/dev/null 2>&1" \
  --trace  "component:04-python / ucc-target:xz"

tic_test \
  --name   "pyenv-installed" \
  --intent "pyenv must be present" \
  --oracle "pyenv --version >/dev/null 2>&1" \
  --trace  "component:04-python / ucc-target:pyenv"

tic_test \
  --name   "python-installed" \
  --intent "python3 must be present via pyenv" \
  --oracle "python3 --version >/dev/null 2>&1" \
  --trace  "component:04-python / ucc-target:python-3.12.3"

tic_test \
  --name   "python-lzma" \
  --intent "lzma C extension must be compiled into Python (requires xz at build time)" \
  --oracle "python3 -c 'import lzma'" \
  --trace  "component:04-python / ucc-target:xz + python-3.12.3"

tic_test \
  --name   "pip-installed" \
  --intent "pip must be present and functional" \
  --oracle "pip --version >/dev/null 2>&1" \
  --trace  "component:04-python / ucc-target:pip-latest"

# ──────────────────────────────────────────────────────────────
# 05-ollama
# ──────────────────────────────────────────────────────────────
tic_test \
  --name   "ollama-installed" \
  --intent "ollama CLI must be present" \
  --oracle "ollama --version >/dev/null 2>&1" \
  --trace  "component:05-ollama / ucc-target:ollama"

tic_test \
  --name   "ollama-api-reachable" \
  --intent "ollama HTTP API must respond on port ${_OLLAMA_API_PORT}" \
  --oracle "curl -fsS http://${_OLLAMA_API_HOST}:${_OLLAMA_API_PORT}/api/tags >/dev/null 2>&1" \
  --trace  "component:05-ollama / ucc-target:ollama-service"

# ──────────────────────────────────────────────────────────────
# 06-ai-python-stack
# ──────────────────────────────────────────────────────────────
tic_test \
  --name   "torch-importable" \
  --intent "torch must be importable" \
  --oracle "python3 -c 'import torch'" \
  --trace  "component:06-ai-python-stack / ucc-target:pip-group-pytorch"

tic_test \
  --name   "torch-mps-available" \
  --intent "MPS (Metal) GPU acceleration must be available on Apple Silicon" \
  --oracle "python3 -c 'import torch; assert torch.backends.mps.is_available()'" \
  --trace  "component:06-ai-python-stack / ucc-target:pip-group-pytorch"

tic_test \
  --name   "transformers-importable" \
  --intent "transformers must be importable" \
  --oracle "python3 -c 'import transformers'" \
  --trace  "component:06-ai-python-stack / ucc-target:pip-group-huggingface"

tic_test \
  --name   "langchain-importable" \
  --intent "langchain must be importable" \
  --oracle "python3 -c 'import langchain'" \
  --trace  "component:06-ai-python-stack / ucc-target:pip-group-langchain"

tic_test \
  --name   "langchain-core-version" \
  --intent "langchain-core must be >=1.0.0 (required by langgraph and langchain-ollama)" \
  --oracle "python3 -c \"
import importlib.util, sys
import langchain_core
from packaging.version import Version
sys.exit(0 if Version(langchain_core.__version__) >= Version('1.0.0') else 1)
\"" \
  --trace  "component:06-ai-python-stack / ucc-target:pip-group-langchain"

tic_test \
  --name   "unsloth-importable" \
  --intent "unsloth Python package is not importable on Apple Silicon (NVIDIA/AMD only)" \
  --oracle "true" \
  --skip   "not importable on Apple Silicon (NVIDIA only) — Studio runs in its own venv" \
  --trace  "component:06-ai-python-stack / ucc-target:unsloth-studio-setup"

tic_test \
  --name   "unsloth-studio-setup-dir" \
  --intent "unsloth studio setup must have completed (${_UNSLOTH_STUDIO_DIR} must exist)" \
  --oracle "[[ -d \"${_UNSLOTH_STUDIO_DIR}\" ]]" \
  --trace  "component:06-ai-python-stack / ucc-target:unsloth-studio-setup"

tic_test \
  --name   "unsloth-studio-launchd-loaded" \
  --intent "unsloth studio launchd service must be loaded" \
  --oracle "launchctl list 2>/dev/null | grep -q '${_UNSLOTH_LABEL}'" \
  --trace  "component:06-ai-python-stack / ucc-target:unsloth-studio-launchd"

tic_test \
  --name   "unsloth-studio-port-${_UNSLOTH_PORT}" \
  --intent "unsloth studio must be listening on port ${_UNSLOTH_PORT}" \
  --oracle "curl -fsS --max-time 5 http://127.0.0.1:${_UNSLOTH_PORT} >/dev/null 2>&1" \
  --trace  "component:06-ai-python-stack / ucc-target:unsloth-studio-launchd"

# ──────────────────────────────────────────────────────────────
# 07-ai-apps
# ──────────────────────────────────────────────────────────────
_docker_container_running() {
  docker inspect --format '{{.State.Status}}' "$1" 2>/dev/null | grep -q "^running$"
}

for _svc in "${_AI_SERVICES[@]}"; do
  _svc_fn="${_svc//-/_}"
  eval "
tic_test \
  --name   \"docker-container-${_svc}\" \
  --intent \"${_svc} container must be running\" \
  --oracle \"_docker_container_running '${_svc}'\" \
  --trace  \"component:07-ai-apps / ucc-target:ai-stack-running\"
"
done

# ──────────────────────────────────────────────────────────────
# 08-dev-tools
# ──────────────────────────────────────────────────────────────
tic_test \
  --name   "node-${_NODE_VER}-installed" \
  --intent "node must be v${_NODE_VER}.x (required by Unsloth Studio, Claude Code, BMAD)" \
  --oracle "node --version 2>/dev/null | grep -q '^v${_NODE_VER}\.'" \
  --trace  "component:08-dev-tools / ucc-target:node-${_NODE_VER}-lts"

tic_test \
  --name   "cmake-installed" \
  --intent "cmake must be present (required for Unsloth GGUF inference)" \
  --oracle "cmake --version >/dev/null 2>&1" \
  --trace  "component:08-dev-tools / cli-cmake"

tic_test \
  --name   "claude-code-installed" \
  --intent "claude-code npm global must be installed" \
  --oracle "npm ls -g @anthropic-ai/claude-code --depth=0 >/dev/null 2>&1" \
  --trace  "component:08-dev-tools / ucc-target:npm-global-@anthropic-ai/claude-code"

tic_test \
  --name   "bmad-method-installed" \
  --intent "bmad-method npm global must be installed" \
  --oracle "npm ls -g bmad-method --depth=0 >/dev/null 2>&1" \
  --trace  "component:08-dev-tools / ucc-target:npm-global-bmad-method"

tic_test \
  --name   "ariaflow-installed" \
  --intent "ariaflow CLI must be present" \
  --oracle "ariaflow --version >/dev/null 2>&1 || ariaflow lifecycle >/dev/null 2>&1" \
  --trace  "component:08-dev-tools / ucc-target:ariaflow"

tic_test \
  --name   "ariaflow-web-installed" \
  --intent "ariaflow-web brew formula must be installed" \
  --oracle "brew list ariaflow-web >/dev/null 2>&1" \
  --trace  "component:08-dev-tools / ucc-target:ariaflow-web"

tic_test \
  --name   "ariaflow-web-service-started" \
  --intent "ariaflow-web brew service must be running (port ${_ARIAFLOW_WEB_PORT})" \
  --oracle "brew services list 2>/dev/null | awk '/^ariaflow-web/ {print \$2}' | grep -q '^started$'" \
  --trace  "component:08-dev-tools / ucc-target:ariaflow-web-service"

tic_test \
  --name   "ariaflow-web-port-${_ARIAFLOW_WEB_PORT}" \
  --intent "ariaflow web UI must be listening on port ${_ARIAFLOW_WEB_PORT}" \
  --oracle "curl -fsS --max-time 5 http://127.0.0.1:${_ARIAFLOW_WEB_PORT} >/dev/null 2>&1" \
  --trace  "component:08-dev-tools / ucc-target:ariaflow-web-service"

tic_test \
  --name   "vscode-installed" \
  --intent "Visual Studio Code must be installed" \
  --oracle "[[ -d '/Applications/Visual Studio Code.app' ]] || is_installed code" \
  --trace  "component:08-dev-tools / ucc-target:vscode"

tic_test \
  --name   "omz-installed" \
  --intent "Oh My Zsh must be installed" \
  --oracle "[[ -d \"\$HOME/.oh-my-zsh\" ]]" \
  --trace  "component:08-dev-tools / ucc-target:oh-my-zsh"

tic_test \
  --name   "healthcheck-script-present" \
  --intent "ai-healthcheck script must be present and executable" \
  --oracle "[[ -x \"\$HOME/bin/ai-healthcheck\" ]]" \
  --trace  "component:08-dev-tools / ucc-target:ai-healthcheck"

# ──────────────────────────────────────────────────────────────
# 09-macos-defaults
# ──────────────────────────────────────────────────────────────
tic_test \
  --name   "pmset-ac-sleep-0" \
  --intent "AC sleep must be 0 to prevent interruption during long AI runs" \
  --oracle "pmset -g | awk '/^[[:space:]]+sleep / {exit (\$2 == \"0\") ? 0 : 1}'" \
  --trace  "component:09-macos-defaults / ucc-target:pmset-ac-sleep=0"

tic_test \
  --name   "app-nap-disabled" \
  --intent "App Nap must be disabled to keep background AI processes active" \
  --oracle "[[ \"\$(defaults read NSGlobalDomain NSAppSleepDisabled 2>/dev/null)\" == '1' ]]" \
  --trace  "component:09-macos-defaults / ucc-target:app-nap=disabled"

tic_summary "10-verify"
