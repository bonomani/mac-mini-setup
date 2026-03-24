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
  < <(yaml_list "$DIR" "$DIR/config/ai-apps.yaml" services)
[[ ${#_AI_SERVICES[@]} -gt 0 ]] || _AI_SERVICES=(open-webui flowise openhands n8n qdrant)

_NODE_VER="$(          yaml_get "$DIR" "$DIR/config/dev-tools.yaml"       node_version          24)"
_ARIA2_PORT="$(        yaml_get "$DIR" "$DIR/config/dev-tools.yaml"       aria2_port            6800)"
_ARIAFLOW_WEB_PORT="$( yaml_get "$DIR" "$DIR/config/dev-tools.yaml"       ariaflow_web_port     8001)"
_OLLAMA_API_HOST="$(   yaml_get "$DIR" "$DIR/config/ollama.yaml"          api_host              127.0.0.1)"
_OLLAMA_API_PORT="$(   yaml_get "$DIR" "$DIR/config/ollama.yaml"          api_port              11434)"
_UNSLOTH_PORT="$(      yaml_get "$DIR" "$DIR/config/ai-python-stack.yaml" unsloth_studio.port   8888)"
_UNSLOTH_LABEL="$(     yaml_get "$DIR" "$DIR/config/ai-python-stack.yaml" unsloth_studio.label  ai.unsloth.studio)"
_UNSLOTH_STUDIO_DIR="$HOME/$(yaml_get "$DIR" "$DIR/config/ai-python-stack.yaml" unsloth_studio.studio_dir .unsloth/studio)"

# Ensure pyenv and node are in PATH so oracle commands resolve correctly
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
if [[ -d "/opt/homebrew/opt/node@${_NODE_VER}/bin" ]]; then
  export PATH="/opt/homebrew/opt/node@${_NODE_VER}/bin:$PATH"
elif [[ -d "/usr/local/opt/node@${_NODE_VER}/bin" ]]; then
  export PATH="/usr/local/opt/node@${_NODE_VER}/bin:$PATH"
fi

run_tic_tests_from_yaml "$DIR" "$DIR/config/verify.yaml"
run_container_tic_tests_from_yaml "$DIR" "$DIR/config/ai-apps.yaml"

tic_summary "verify"
