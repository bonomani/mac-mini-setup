#!/usr/bin/env bash
# Component: AI Python Stack (PyTorch MPS + LLM frameworks)
# BGS: UCC + Basic — bash 3.2 compatible (no declare -A)
#
# BISS: Axis A = UCC (state convergence — pip packages installed + launchd service loaded)
#       Axis B = Basic
# Boundary: local filesystem · pip/PyPI (network) · macOS launchd (Unsloth Studio service)

# Helper: define one pip group as a ucc_target
# Usage: _pip_group <name> <probe_pkg> "<space-separated packages>" [<min_version>]
# When min_version is set, the observe uses importlib.metadata + packaging.version
# to enforce a minimum version of the probe package (triggers upgrade if below).
_pip_group() {
  local name="$1" first="$2" pkgs="$3" minver="${4:-}"
  local fn="${name//[^a-zA-Z0-9]/_}"

  if [[ -n "$minver" ]]; then
    eval "_observe_grp_${fn}() {
      local raw
      raw=\$(python3 -c \"
import sys
try:
    import importlib.metadata
    ver = importlib.metadata.version('${first}')
    from packaging.version import Version
    sys.exit(0 if Version(ver) >= Version('${minver}') else 1)
except Exception:
    sys.exit(1)
\" 2>/dev/null && pip show '${first}' 2>/dev/null | awk '/^Version:/ {print \$2}' || echo 'absent')
      ucc_asm_package_state \"\$raw\"
    }"
  else
    eval "_observe_grp_${fn}() { local raw; raw=\$(pip_is_installed '${first}' && pip show '${first}' 2>/dev/null | awk '/^Version:/ {print \$2}' || echo 'absent'); ucc_asm_package_state \"\$raw\"; }"
  fi
  eval "_evidence_grp_${fn}() { local ver; ver=\$(pip show '${first}' 2>/dev/null | awk '/^Version:/ {print \$2}'); [[ -n \"\$ver\" ]] && printf 'version=%s pkg=${first}' \"\$ver\"; }"
  eval "_install_grp_${fn}() { ucc_run pip install -q ${pkgs}; }"
  eval "_update_grp_${fn}()  { ucc_run pip install -q --upgrade ${pkgs}; }"

  ucc_target_nonruntime \
    --name    "pip-group-$name" \
    --observe "_observe_grp_${fn}" \
    --evidence "_evidence_grp_${fn}" \
    --install "_install_grp_${fn}" \
    --update  "_update_grp_${fn}"
}

# Load pip groups from config — see config/06-ai-python-stack.yaml
# Note: jupyter-ai is intentionally absent — it pins langchain<0.4.0, incompatible with langchain>=1.0.0
_PY_CFG_DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
_PY_CFG="$_PY_CFG_DIR/config/06-ai-python-stack.yaml"
while IFS='|' read -r grp_name grp_probe grp_pkgs grp_minver; do
  [[ -n "$grp_name" ]] || continue
  _pip_group "$grp_name" "$grp_probe" "$grp_pkgs" "$grp_minver"
done < <(python3 "$_PY_CFG_DIR/tools/read_config.py" --records \
    "$_PY_CFG" pip_groups name probe packages min_version 2>/dev/null)

# Note: the unsloth Python package cannot be imported on Apple Silicon —
# it raises NotImplementedError at import time (NVIDIA/AMD/Intel GPUs only).
# Unsloth Studio runs in its own isolated venv and works on Mac via the CLI.
# Do NOT install the pip package — it is unused and untestable on this platform.

# --- Unsloth Studio setup (downloads frontend, creates venv) ---
_observe_unsloth_studio_setup() {
  local raw
  raw=$([[ -d "$HOME/.unsloth/studio" ]] && echo "present" || echo "absent")
  ucc_asm_package_state "$raw"
}
_evidence_unsloth_studio_setup() { printf 'folder=%s' "$HOME/.unsloth/studio"; }
_run_unsloth_studio_setup() {
  ucc_run unsloth studio setup
}

ucc_target_nonruntime \
  --name    "unsloth-studio-setup" \
  --observe _observe_unsloth_studio_setup \
  --evidence _evidence_unsloth_studio_setup \
  --install _run_unsloth_studio_setup \
  --update  _run_unsloth_studio_setup

# --- Unsloth Studio — launchd (port 8888, survives reboot) ---
UNSLOTH_PLIST="$HOME/Library/LaunchAgents/ai.unsloth.studio.plist"

# launchd does not load pyenv shims — resolve the absolute binary path now
UNSLOTH_BIN="$(pyenv which unsloth 2>/dev/null || command -v unsloth)"

UNSLOTH_PLIST_MARKER="<!-- ai.unsloth.studio v2 -->"

_observe_unsloth_studio_launchd() {
  local raw
  launchctl list 2>/dev/null | grep -q "ai.unsloth.studio" || { ucc_asm_service_state "absent"; return; }
  grep -qF "$UNSLOTH_PLIST_MARKER" "$UNSLOTH_PLIST" 2>/dev/null || { ucc_asm_service_state "outdated"; return; }
  ucc_asm_service_state "loaded"
}
_evidence_unsloth_studio_launchd() {
  local pid
  pid=$(pgrep -f 'unsloth.*studio' 2>/dev/null | head -1 || true)
  [[ -n "$pid" ]] && printf 'pid=%s port=8888 plist=%s' "$pid" "$UNSLOTH_PLIST" || printf 'port=8888 plist=%s' "$UNSLOTH_PLIST"
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
