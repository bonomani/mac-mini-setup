#!/usr/bin/env bash
# Component: TIC verification suite
# BGS suite — TIC verification layer
#
# BISS: Axis A = GIC (read-only observation — no convergence side-effects)
#       Axis B = Basic
# Boundary: local filesystem + system APIs + HTTP (read-only probes only)

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DIR/lib/tic.sh"
source "$DIR/lib/tic_runner.sh"

# Load runtime variables used by oracle strings at eval time
_AI_SERVICES=()
while IFS= read -r _s; do [[ -n "$_s" ]] && _AI_SERVICES+=("$_s"); done \
  < <(python3 "$DIR/tools/read_config.py" --list "$DIR/config/07-ai-apps.yaml" services 2>/dev/null)
[[ ${#_AI_SERVICES[@]} -gt 0 ]] || _AI_SERVICES=(open-webui flowise openhands n8n qdrant)

_NODE_VER="$(python3 "$DIR/tools/read_config.py" --get "$DIR/config/08-dev-tools.yaml" node_version 2>/dev/null)"
_NODE_VER="${_NODE_VER:-24}"
_ARIA2_PORT="$(python3 "$DIR/tools/read_config.py" --get "$DIR/config/08-dev-tools.yaml" aria2_port 2>/dev/null)"
_ARIA2_PORT="${_ARIA2_PORT:-6800}"
_ARIAFLOW_WEB_PORT="$(python3 "$DIR/tools/read_config.py" --get "$DIR/config/08-dev-tools.yaml" ariaflow_web_port 2>/dev/null)"
_ARIAFLOW_WEB_PORT="${_ARIAFLOW_WEB_PORT:-8001}"
_OLLAMA_API_HOST="$(python3 "$DIR/tools/read_config.py" --get "$DIR/config/05-ollama.yaml" api_host 2>/dev/null)"
_OLLAMA_API_HOST="${_OLLAMA_API_HOST:-127.0.0.1}"
_OLLAMA_API_PORT="$(python3 "$DIR/tools/read_config.py" --get "$DIR/config/05-ollama.yaml" api_port 2>/dev/null)"
_OLLAMA_API_PORT="${_OLLAMA_API_PORT:-11434}"
_UNSLOTH_PORT="$(python3 "$DIR/tools/read_config.py" --get "$DIR/config/06-ai-python-stack.yaml" unsloth_studio.port 2>/dev/null)"
_UNSLOTH_PORT="${_UNSLOTH_PORT:-8888}"
_UNSLOTH_LABEL="$(python3 "$DIR/tools/read_config.py" --get "$DIR/config/06-ai-python-stack.yaml" unsloth_studio.label 2>/dev/null)"
_UNSLOTH_LABEL="${_UNSLOTH_LABEL:-ai.unsloth.studio}"
_UNSLOTH_STUDIO_DIR="$HOME/$(python3 "$DIR/tools/read_config.py" --get "$DIR/config/06-ai-python-stack.yaml" unsloth_studio.studio_dir 2>/dev/null)"
_UNSLOTH_STUDIO_DIR="${_UNSLOTH_STUDIO_DIR:-$HOME/.unsloth/studio}"

# Ensure pyenv and node are in PATH so oracle commands resolve correctly
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
if [[ -d "/opt/homebrew/opt/node@${_NODE_VER}/bin" ]]; then
  export PATH="/opt/homebrew/opt/node@${_NODE_VER}/bin:$PATH"
elif [[ -d "/usr/local/opt/node@${_NODE_VER}/bin" ]]; then
  export PATH="/usr/local/opt/node@${_NODE_VER}/bin:$PATH"
fi

run_tic_tests_from_yaml "$DIR" "$DIR/config/10-verify.yaml"
run_container_tic_tests_from_yaml "$DIR" "$DIR/config/07-ai-apps.yaml"

tic_summary "10-verify"
