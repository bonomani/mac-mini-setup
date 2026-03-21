#!/usr/bin/env bash
# ============================================================
#  Mac Mini AI Setup — Main installer
#  Optimized for Apple Silicon + 64 GB RAM
# ============================================================
#
#  Framework references (coding standards — do not remove)
#  --------------------------------------------------------
#  UIC  Universal Intent Contract
#       Repo  : https://github.com/bonomani/uic
#       WSL   : /home/bc/repos/github/bonomani/uic
#       Win   : /mnt/c/scripts/Uic
#
#  UCC  Universal Convergence Contract engine
#       Repo  : https://github.com/bonomani/ucc
#       WSL   : /home/bc/repos/github/bonomani/ucc
#       Win   : /mnt/c/scripts/Ucc
#
#  All components MUST be UCC + Basic compliant:
#    - declare intent with ucc_target (observe / desired / install / update)
#    - emit structured NOTICE lines (observation / outcome / diff / proof)
#    - respect UCC_MODE (install | update) and UCC_DRY_RUN
# ============================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/ucc.sh"
source "$DIR/lib/uic.sh"

# ============================================================
#  UIC gate condition functions (read-only, no side effects)
# ============================================================
_gate_macos()           { [[ "$(uname)" == "Darwin" ]]; }
_gate_arm64()           { [[ "$(uname -m)" == "arm64" ]]; }
_gate_docker_daemon()   { docker info &>/dev/null 2>&1; }
_gate_docker_settings() { [[ -f "$HOME/Library/Group Containers/group.com.docker/settings.json" ]]; }
_gate_ollama_api()      { curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; }
_gate_sudo()            { sudo -n true 2>/dev/null; }

COMPONENTS=(
  "01-homebrew"
  "02-git"
  "03-docker"
  "04-python"
  "05-ollama"
  "06-ai-python-stack"
  "07-ai-apps"
  "08-dev-tools"
  "09-macos-defaults"
)

usage() {
  cat <<EOF

Usage: $0 [options] [component ...]

Without component arguments, runs ALL components in order.

Options:
  --mode install    Install missing components (default)
  --mode update     Update already-installed components
  --dry-run         Show what would change without applying it
  --preflight       Evaluate UIC gates and preferences; do NOT converge
  --debug           Show DEBUG-level output
  -h, --help        Show this help

Available components:
$(printf '  %s\n' "${COMPONENTS[@]}")

Examples:
  $0                                    # full install
  $0 --dry-run                          # preview full install
  $0 --mode update                      # update everything
  $0 --mode update --dry-run            # preview updates
  $0 05-ollama 06-ai-python-stack       # run specific components
  $0 --mode update 05-ollama            # update Ollama only

EOF
  exit 0
}

# --- Parse arguments ----------------------------------------
TO_RUN=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)       export UCC_DRY_RUN=1;     shift ;;
    --mode)          export UCC_MODE="$2";    shift 2 ;;
    --debug)         export UCC_DEBUG=1;      shift ;;
    --preflight)     export UIC_PREFLIGHT=1;  shift ;;
    -h|--help)       usage ;;
    -*)              log_warn "Unknown option: $1"; shift ;;
    *)               TO_RUN+=("$1"); shift ;;
  esac
done

[[ ${#TO_RUN[@]} -eq 0 ]] && TO_RUN=("${COMPONENTS[@]}")

# Validate mode
[[ "$UCC_MODE" =~ ^(install|update)$ ]] || log_error "Invalid --mode: $UCC_MODE (must be install or update)"

# ============================================================
#  UIC — Gates and Preferences
#  Evaluated before any UCC convergence begins (UIC §6)
# ============================================================

# --- Gates --------------------------------------------------
uic_gate \
  --name      "macos-platform" \
  --condition _gate_macos \
  --scope     "global" \
  --class     "readiness" \
  --blocking  "hard"

uic_gate \
  --name      "apple-silicon" \
  --condition _gate_arm64 \
  --scope     "global" \
  --class     "readiness" \
  --blocking  "soft"

uic_gate \
  --name      "docker-daemon" \
  --condition _gate_docker_daemon \
  --scope     "component:07-ai-apps" \
  --class     "readiness" \
  --blocking  "soft"

uic_gate \
  --name      "docker-settings-file" \
  --condition _gate_docker_settings \
  --scope     "component:03-docker" \
  --class     "readiness" \
  --blocking  "soft"

uic_gate \
  --name      "ollama-api" \
  --condition _gate_ollama_api \
  --scope     "component:05-ollama" \
  --class     "readiness" \
  --blocking  "soft"

uic_gate \
  --name      "sudo-available" \
  --condition _gate_sudo \
  --scope     "component:09-macos-defaults" \
  --class     "authorization" \
  --blocking  "soft"

# --- Preferences (safe defaults = most conservative choice) -
uic_preference \
  --name      "python-version" \
  --default   "3.12.3" \
  --options   "3.11.9|3.12.3|3.13.0" \
  --rationale "3.12.3 is the tested stable release with best ML library support; 3.13 is newer but less tested with PyTorch/HF" \
  --scope     "component:04-python"

uic_preference \
  --name      "docker-memory-gb" \
  --default   "48" \
  --options   "16|32|48|56" \
  --rationale "48 GB leaves 16 GB for macOS and native processes on a 64 GB machine; 56 risks host instability under load" \
  --scope     "component:03-docker"

uic_preference \
  --name      "docker-cpu-count" \
  --default   "10" \
  --options   "4|6|8|10|12" \
  --rationale "10 cores leaves 2 for macOS scheduler; 12 (all) risks UI unresponsiveness during heavy container workloads" \
  --scope     "component:03-docker"

uic_preference \
  --name      "ollama-model-autopull" \
  --default   "none" \
  --options   "none|small|medium|large" \
  --rationale "none prevents automatic multi-GB downloads; pull models manually when ready. small=≤3B, medium=≤8B, large=all" \
  --scope     "component:05-ollama"

uic_preference \
  --name      "pytorch-device" \
  --default   "mps" \
  --options   "mps|cpu" \
  --rationale "mps uses Apple Silicon Metal GPU for ML acceleration; cpu works everywhere but is significantly slower" \
  --scope     "component:06-ai-python-stack"

uic_preference \
  --name      "destructive-updates" \
  --default   "off" \
  --options   "on|off" \
  --rationale "off prevents destructive container/package replacement without explicit operator intent; on allows full reimaging on update" \
  --scope     "global"

uic_preference \
  --name      "service-policy" \
  --default   "autostart" \
  --options   "manual|autostart" \
  --rationale "autostart: script starts required services (Docker, Ollama) when not running; manual: operator starts services before running the script" \
  --scope     "global"

uic_preference \
  --name      "package-update-policy" \
  --default   "always-upgrade" \
  --options   "install-only|always-upgrade" \
  --rationale "always-upgrade: upgrade outdated packages on each run; install-only: skip already-installed packages (use to speed up runs when upgrades are not needed)" \
  --scope     "global"

# --- Resolve (evaluate gates, report preferences) -----------
_UIC_RC=0
uic_resolve || _UIC_RC=$?
uic_export

# Update brew index and cache outdated list before any component runs,
# so the outdated cache reflects the latest formula versions.
if [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" == "always-upgrade" ]] \
    && command -v brew &>/dev/null; then
  log_info "Updating Homebrew index (package-update-policy=always-upgrade)..."
  brew update --force --quiet 2>/dev/null || true
  log_info "Caching brew outdated list..."
  brew_cache_outdated
fi

# --- Preflight mode: write template and exit ----------------
if [[ "$UIC_PREFLIGHT" == "1" ]]; then
  uic_write_template
  exit $_UIC_RC
fi

# --- Hard gate failure: abort only on globally-scoped hard gates --------
# Component-scoped hard gates block only their component (via uic_component_blocked).
_GLOBAL_HARD_FAILED=0
for _gi in "${!_UIC_GATE_NAMES[@]}"; do
  [[ "${_UIC_GATE_BLOCKS[$_gi]}" == "hard" ]]   || continue
  [[ "${_UIC_GATE_SCOPES[$_gi]}" == "global" ]]  || continue
  _gkey="$(_uic_gate_key "${_UIC_GATE_NAMES[$_gi]}")"
  [[ "${!_gkey:-}" == "1" ]] && _GLOBAL_HARD_FAILED=1
done
if [[ "$_GLOBAL_HARD_FAILED" == "1" ]]; then
  log_error "UIC global hard gate failed — convergence aborted (run --preflight for details)"
fi

# --- Header -------------------------------------------------
echo ""
echo "========================================================"
echo "  Mac Mini AI Setup"
echo "  mode=$UCC_MODE dry_run=$UCC_DRY_RUN correlation_id=$UCC_CORRELATION_ID"
echo "  $(date)"
echo "========================================================"
echo ""

[[ "$(uname)" == "Darwin" ]] || log_error "This script is for macOS only"

ARCH=$(uname -m)
TOTAL_MEM=$(sysctl -n hw.memsize)
TOTAL_GB=$(( TOTAL_MEM / 1024 / 1024 / 1024 ))

log_info "Architecture : $ARCH"
log_info "RAM          : ${TOTAL_GB} GB"
[[ "$ARCH" == "arm64" ]] \
  && log_info "Apple Silicon detected — Metal GPU acceleration available" \
  || log_warn "Intel Mac detected — some AI acceleration features may differ"
[[ $TOTAL_GB -ge 32 ]] \
  && log_info "RAM sufficient for large models (70B+)" \
  || log_warn "Less than 32 GB RAM — large models may be slow"

# --- Ensure brew is in PATH (re-checked after each component) ---
_refresh_brew_path() {
  command -v brew &>/dev/null && return
  for _bp in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$_bp" ]]; then
      eval "$("$_bp" shellenv)"
      export PATH
      log_debug "brew PATH refreshed from $_bp"
      return
    fi
  done
}
_refresh_brew_path

# --- Run components -----------------------------------------
TOTAL_OBSERVED=0; TOTAL_APPLIED=0; TOTAL_CHANGED=0; TOTAL_FAILED=0; TOTAL_SKIPPED=0
FAILED_COMPONENTS=()

for comp in "${TO_RUN[@]}"; do
  SCRIPT="$DIR/components/${comp}.sh"
  if [[ ! -f "$SCRIPT" ]]; then
    log_warn "Component not found: ${comp}.sh — skipping"
    continue
  fi

  # UIC: skip component if a hard gate scoped to it has failed
  if uic_component_blocked "$comp"; then
    log_warn "Component $comp blocked by UIC hard gate — outcome=failed, failure_class=permanent, reason=gate_failed"
    FAILED_COMPONENTS+=("$comp")
    continue
  fi

  echo ""
  echo "--------------------------------------------------------"
  log_info "Component: $comp"
  echo "--------------------------------------------------------"

  if bash \
      -c "source \"$DIR/lib/ucc.sh\"; source \"$DIR/lib/uic.sh\"; source \"$DIR/lib/utils.sh\"; source \"$SCRIPT\"" \
      -- "$SCRIPT"; then
    log_info "Component done: $comp"
  else
    log_warn "Component failed: $comp"
    FAILED_COMPONENTS+=("$comp")
  fi
  # Refresh brew PATH in case it was just installed by this component
  _refresh_brew_path
done

# --- Final summary ------------------------------------------
echo ""
echo "========================================================"
if [[ ${#FAILED_COMPONENTS[@]} -eq 0 ]]; then
  log_notice "All components completed | mode=$UCC_MODE dry_run=$UCC_DRY_RUN"
else
  log_warn "Completed with failures: ${FAILED_COMPONENTS[*]}"
fi
echo "========================================================"
echo ""
log_info "Services (once running):"
log_info "  Ollama API       → http://localhost:11434"
log_info "  Open WebUI       → http://localhost:3000"
log_info "  Flowise          → http://localhost:3001"
log_info "  n8n              → http://localhost:5678"
log_info "  Qdrant           → http://localhost:6333"
log_info "  OpenHands        → http://localhost:3002"
log_info "  Jupyter Lab      → run: jupyter lab"
echo ""

[[ ${#FAILED_COMPONENTS[@]} -eq 0 ]]
