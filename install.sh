#!/usr/bin/env bash
# ============================================================
#  Mac Mini AI Setup — Main installer
#  Optimized for Apple Silicon + 64 GB RAM
#  UCC + Basic compliant
# ============================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/ucc.sh"

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
    --dry-run)       export UCC_DRY_RUN=1; shift ;;
    --mode)          export UCC_MODE="$2"; shift 2 ;;
    --debug)         export UCC_DEBUG=1;   shift ;;
    -h|--help)       usage ;;
    -*)              log_warn "Unknown option: $1"; shift ;;
    *)               TO_RUN+=("$1"); shift ;;
  esac
done

[[ ${#TO_RUN[@]} -eq 0 ]] && TO_RUN=("${COMPONENTS[@]}")

# Validate mode
[[ "$UCC_MODE" =~ ^(install|update)$ ]] || log_error "Invalid --mode: $UCC_MODE (must be install or update)"

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

# --- Run components -----------------------------------------
TOTAL_OBSERVED=0; TOTAL_APPLIED=0; TOTAL_CHANGED=0; TOTAL_FAILED=0; TOTAL_SKIPPED=0
FAILED_COMPONENTS=()

for comp in "${TO_RUN[@]}"; do
  SCRIPT="$DIR/components/${comp}.sh"
  if [[ ! -f "$SCRIPT" ]]; then
    log_warn "Component not found: ${comp}.sh — skipping"
    continue
  fi
  echo ""
  echo "--------------------------------------------------------"
  log_info "Component: $comp"
  echo "--------------------------------------------------------"

  # Reset per-script counters before sourcing
  _UCC_OBSERVED=0; _UCC_APPLIED=0; _UCC_CHANGED=0; _UCC_FAILED=0; _UCC_SKIPPED=0

  if bash \
      -c "source \"$DIR/lib/ucc.sh\"; source \"$DIR/lib/utils.sh\"; source \"$SCRIPT\"" \
      -- "$SCRIPT"; then
    log_info "Component done: $comp"
  else
    log_warn "Component failed: $comp"
    FAILED_COMPONENTS+=("$comp")
  fi
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
log_info "  Jupyter Lab      → run: jupyter lab"
echo ""

[[ ${#FAILED_COMPONENTS[@]} -eq 0 ]]
