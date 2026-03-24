#!/usr/bin/env bash
# Component: AI Python Stack (PyTorch MPS + LLM frameworks)
# BGS: UCC + Basic — bash 3.2 compatible (no declare -A)
#
# BISS: Axis A = UCC (state convergence — pip packages installed + launchd service loaded)
#       Axis B = Basic
# Boundary: local filesystem · pip/PyPI (network) · macOS launchd (Unsloth Studio service)
#
# Note: jupyter-ai is intentionally absent — it pins langchain<0.4.0, incompatible with langchain>=1.0.0
# Note: the unsloth Python package cannot be imported on Apple Silicon — it raises
#       NotImplementedError at import time (NVIDIA/AMD/Intel GPUs only).
#       Unsloth Studio runs in its own isolated venv and works on Mac via the CLI.
#       Do NOT install the pip package — it is unused and untestable on this platform.

_PY_CFG_DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
_PY_CFG="$_PY_CFG_DIR/config/06-ai-python-stack.yaml"

source "$_PY_CFG_DIR/lib/pip_group.sh"

# Load pip groups from config
while IFS=$'\t' read -r grp_name grp_probe grp_pkgs grp_minver; do
  [[ -n "$grp_name" ]] || continue
  _pip_group "$grp_name" "$grp_probe" "$grp_pkgs" "$grp_minver"
done < <(python3 "$_PY_CFG_DIR/tools/read_config.py" --records \
    "$_PY_CFG" pip_groups name probe packages min_version 2>/dev/null)

# Load Unsloth Studio config from YAML
_UNSLOTH_LABEL="$(python3 "$_PY_CFG_DIR/tools/read_config.py" --get "$_PY_CFG" unsloth_studio.label 2>/dev/null)"
_UNSLOTH_PLIST_MARKER="$(python3 "$_PY_CFG_DIR/tools/read_config.py" --get "$_PY_CFG" unsloth_studio.plist_marker 2>/dev/null)"
_UNSLOTH_PORT="$(python3 "$_PY_CFG_DIR/tools/read_config.py" --get "$_PY_CFG" unsloth_studio.port 2>/dev/null)"
_UNSLOTH_HOST="$(python3 "$_PY_CFG_DIR/tools/read_config.py" --get "$_PY_CFG" unsloth_studio.host 2>/dev/null)"
_UNSLOTH_STUDIO_DIR="$HOME/$(python3 "$_PY_CFG_DIR/tools/read_config.py" --get "$_PY_CFG" unsloth_studio.studio_dir 2>/dev/null)"
_UNSLOTH_LOG="$HOME/$(python3 "$_PY_CFG_DIR/tools/read_config.py" --get "$_PY_CFG" unsloth_studio.log_file 2>/dev/null)"

UNSLOTH_PLIST="$HOME/Library/LaunchAgents/${_UNSLOTH_LABEL}.plist"
UNSLOTH_PLIST_MARKER="$_UNSLOTH_PLIST_MARKER"
# launchd does not load pyenv shims — resolve the absolute binary path now
UNSLOTH_BIN="$(pyenv which unsloth 2>/dev/null || command -v unsloth)"

# --- Unsloth Studio setup (downloads frontend, creates venv) ---
_observe_unsloth_studio_setup() {
  ucc_asm_package_state "$([[ -d "$_UNSLOTH_STUDIO_DIR" ]] && echo "present" || echo "absent")"
}
_evidence_unsloth_studio_setup() { printf 'folder=%s' "$_UNSLOTH_STUDIO_DIR"; }
_run_unsloth_studio_setup()       { ucc_run unsloth studio setup; }

ucc_target_nonruntime \
  --name    "unsloth-studio-setup" \
  --observe _observe_unsloth_studio_setup \
  --evidence _evidence_unsloth_studio_setup \
  --install _run_unsloth_studio_setup \
  --update  _run_unsloth_studio_setup

# --- Unsloth Studio — launchd (port configured in YAML, survives reboot) ---
_observe_unsloth_studio_launchd() {
  launchctl list 2>/dev/null | grep -q "$_UNSLOTH_LABEL" || { ucc_asm_service_state "absent"; return; }
  grep -qF "$UNSLOTH_PLIST_MARKER" "$UNSLOTH_PLIST" 2>/dev/null || { ucc_asm_service_state "outdated"; return; }
  ucc_asm_service_state "loaded"
}
_evidence_unsloth_studio_launchd() {
  local pid
  pid=$(pgrep -f 'unsloth.*studio' 2>/dev/null | head -1 || true)
  [[ -n "$pid" ]] && printf 'pid=%s port=%s plist=%s' "$pid" "$_UNSLOTH_PORT" "$UNSLOTH_PLIST" \
                  || printf 'port=%s plist=%s' "$_UNSLOTH_PORT" "$UNSLOTH_PLIST"
}
_install_unsloth_studio_launchd() {
  mkdir -p "$(dirname "$UNSLOTH_PLIST")"
  cat > "$UNSLOTH_PLIST" <<PLIST
${UNSLOTH_PLIST_MARKER}
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>             <string>${_UNSLOTH_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${UNSLOTH_BIN}</string>
    <string>studio</string>
    <string>-H</string><string>${_UNSLOTH_HOST}</string>
    <string>-p</string><string>${_UNSLOTH_PORT}</string>
  </array>
  <key>RunAtLoad</key>         <true/>
  <key>KeepAlive</key>         <true/>
  <key>StandardOutPath</key>   <string>${_UNSLOTH_LOG}</string>
  <key>StandardErrorPath</key> <string>${_UNSLOTH_LOG}</string>
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

ucc_target_service \
  --name    "unsloth-studio-launchd" \
  --observe _observe_unsloth_studio_launchd \
  --evidence _evidence_unsloth_studio_launchd \
  --desired "$(ucc_asm_state --installation Configured --runtime Running --health Healthy --admin Enabled --dependencies DepsReady)" \
  --install _install_unsloth_studio_launchd \
  --update  _update_unsloth_studio_launchd

# Verify Metal/MPS availability
if [[ "$UCC_DRY_RUN" != "1" ]] && is_installed python3; then
  _mps=$(python3 -c "import torch; print('available' if torch.backends.mps.is_available() else 'not available (CPU only)')" 2>/dev/null || true)
  [[ -n "$_mps" ]] && ucc_profile_note runtime "MPS (Metal) GPU: $_mps"
fi

ucc_summary "06-ai-python-stack"
