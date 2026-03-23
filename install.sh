#!/usr/bin/env bash
# ============================================================
#  Mac Mini AI Setup — Main installer
#  Optimized for Apple Silicon + 64 GB RAM
# ============================================================
#
#  BGS Suite compliance — Boundary Governance Suite
#  BGS slice: BGS-State-Modeled-Governed
#    BISS classification -> ASM state model -> UIC preflight -> UCC convergence
#    TIC verification is kept as additional evidence over the resulting state
#  See: ./BGS.md and ./docs/bgs-decision.md
#
#  BISS (Boundary Interaction Semantic Standard)
#  -----------------------------------------------
#  This installer crosses the following boundaries:
#    - local filesystem       (UCC — convergence)
#    - network                (UCC — downloads; GIC — package index update)
#    - macOS system APIs      (UCC — pmset, defaults write, launchctl)
#    - Docker daemon API      (UCC — container state)
#    - HTTP APIs              (GIC — health checks, model availability probes)
#  All boundary interactions are explicitly classified per component BISS header.
#
#  Framework references (coding standards — do not remove)
#  --------------------------------------------------------
#  BGS  Boundary Governance Suite
#       Repo  : https://github.com/bonomani/bgs
#       WSL   : /home/bc/repos/github/bonomani/bgs
#
#  ASM  Atomic State Model
#       Repo  : https://github.com/bonomani/asm
#       WSL   : /home/bc/repos/github/bonomani/asm
#
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
#  TIC  Test Intent Contract
#       Repo  : https://github.com/bonomani/tic
#       WSL   : /home/bc/repos/github/bonomani/tic
#       Impl  : lib/tic.sh + components/10-verify.sh
#
#  All components MUST be UCC + Basic compliant:
#    - declare BISS classification (Axis A + Axis B + Boundary) in header
#    - declare intent with ucc_target (observe / desired / install / update)
#    - emit structured NOTICE lines (observation / outcome / diff / proof)
#    - respect UCC_MODE (install | update) and UCC_DRY_RUN
#  Component 10-verify runs TIC tests after all UCC components complete.
#
#  Immutable framework version refs (BGS decision record)
#    BGS : bgs@73adc3f
#    ASM : asm@5ca20bd
#    UCC : ucc@da74277
#    UIC : uic@11bd400
#    TIC : tic@7cfba80
# ============================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/ucc.sh"
source "$DIR/lib/uic.sh"
source "$DIR/lib/tic.sh"

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
  "10-verify"
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
  --target-state "host installation_state=Configured" \
  --blocking  "hard"

uic_gate \
  --name      "apple-silicon" \
  --condition _gate_arm64 \
  --scope     "global" \
  --class     "readiness" \
  --target-state "host dependency_state=DepsReady" \
  --blocking  "soft"

uic_gate \
  --name      "docker-daemon" \
  --condition _gate_docker_daemon \
  --scope     "component:07-ai-apps" \
  --class     "readiness" \
  --target-state "07-ai-apps runtime_state=Running dependency_state=DepsReady" \
  --blocking  "soft"

uic_gate \
  --name      "docker-settings-file" \
  --condition _gate_docker_settings \
  --scope     "component:03-docker" \
  --class     "readiness" \
  --target-state "03-docker installation_state=Configured dependency_state=DepsReady" \
  --blocking  "soft"

uic_gate \
  --name      "ollama-api" \
  --condition _gate_ollama_api \
  --scope     "component:05-ollama" \
  --class     "readiness" \
  --target-state "05-ollama runtime_state=Running dependency_state=DepsReady" \
  --blocking  "soft"

uic_gate \
  --name      "sudo-available" \
  --condition _gate_sudo \
  --scope     "component:09-macos-defaults" \
  --class     "authorization" \
  --target-state "09-macos-defaults admin_state=Enabled dependency_state=DepsReady" \
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
  brew update --force --quiet 2>/dev/null || true
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

[[ "$(uname)" == "Darwin" ]] || log_error "This script is for macOS only"

ARCH=$(uname -m)
TOTAL_MEM=$(sysctl -n hw.memsize)
TOTAL_GB=$(( TOTAL_MEM / 1024 / 1024 / 1024 ))

_arch_label="$ARCH"; [[ "$ARCH" == "arm64" ]] && _arch_label="arm64 (Apple Silicon / Metal)"
_ram_label="${TOTAL_GB} GB"; [[ $TOTAL_GB -ge 32 ]] && _ram_label="${TOTAL_GB} GB (large model capable)"

_global_state_label() {
  if [[ ${#_UIC_FAILED_HARD[@]} -gt 0 ]]; then
    printf 'Blocked'
    return
  fi
  if [[ ${#_UIC_FAILED_SOFT[@]} -gt 0 ]]; then
    printf 'Degraded'
    return
  fi
  printf 'Ready'
}

_global_state_detail() {
  local detail=""
  if [[ ${#_UIC_FAILED_HARD[@]} -gt 0 ]]; then
    detail="hard_gates=${_UIC_FAILED_HARD[*]}"
  elif [[ ${#_UIC_FAILED_SOFT[@]} -gt 0 ]]; then
    detail="soft_gates=${_UIC_FAILED_SOFT[*]}"
  else
    detail="all_gates_satisfied"
  fi
  printf '%s' "$detail" | tr ' ' ','
}

_summary_line() {
  local ok="${1:-0}" changed="${2:-0}" failed="${3:-0}" line=""
  line="${ok} ok"
  [[ "$changed" -gt 0 ]] && line="${line}  ${changed} changed"
  [[ "$failed" -gt 0 ]] && line="${line}  ${failed} FAILED"
  printf '%s' "$line"
}

_kind_var_prefix() {
  case "$1" in
    Packages) printf '_kind_packages' ;;
    Config) printf '_kind_config' ;;
    Services) printf '_kind_services' ;;
    *) printf '' ;;
  esac
}

_kind_bump() {
  local prefix
  prefix="$(_kind_var_prefix "$1")"
  [[ -z "$prefix" ]] && return 0
  case "$2" in
    ok) eval "${prefix}_ok=\$(( ${prefix}_ok + 1 ))" ;;
    changed) eval "${prefix}_chg=\$(( ${prefix}_chg + 1 ))" ;;
    failed) eval "${prefix}_fail=\$(( ${prefix}_fail + 1 ))" ;;
  esac
}

echo "========================================================"
_hdr_flags="mode=$UCC_MODE"; [[ "$UCC_DRY_RUN" == "1" ]] && _hdr_flags="$_hdr_flags dry_run=1"
echo "  Mac Mini AI Setup | $_hdr_flags | $(date '+%Y-%m-%d %H:%M')"
echo "  $_arch_label  ·  $_ram_label"
echo "  Global State     | $(_global_state_label) ($(_global_state_detail))"
log_debug "correlation_id=$UCC_CORRELATION_ID"
echo "========================================================"

[[ "$ARCH" != "arm64" ]] && log_warn "Intel Mac detected — some AI acceleration features may differ"
[[ $TOTAL_GB -lt 32 ]]   && log_warn "Less than 32 GB RAM — large models may be slow"

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

# --- Structured UCC artifacts (declaration + result JSONL) ---
export UCC_DECLARATION_FILE="$HOME/.ai-stack/runs/${UCC_CORRELATION_ID}.declaration.jsonl"
export UCC_RESULT_FILE="$HOME/.ai-stack/runs/${UCC_CORRELATION_ID}.result.jsonl"
export UCC_SUMMARY_FILE="$HOME/.ai-stack/runs/${UCC_CORRELATION_ID}.summary"
export UCC_KIND_SUMMARY_FILE="$HOME/.ai-stack/runs/${UCC_CORRELATION_ID}.kind-summary"
mkdir -p "$HOME/.ai-stack/runs"

# --- Run components -----------------------------------------
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

  printf '\n── %s\n' "$comp"

  if ! bash \
      -c "source \"$DIR/lib/ucc.sh\"; source \"$DIR/lib/uic.sh\"; source \"$DIR/lib/utils.sh\"; source \"$SCRIPT\"" \
      -- "$SCRIPT"; then
    log_warn "Component failed: $comp"
    FAILED_COMPONENTS+=("$comp")
  fi
  # Refresh brew PATH in case it was just installed by this component
  _refresh_brew_path
done

# --- Final summary ------------------------------------------
echo ""
echo "========================================================"
_hdr_sum="Summary | mode=$UCC_MODE"
[[ "$UCC_DRY_RUN" == "1" ]] && _hdr_sum="$_hdr_sum | dry_run=1"
echo "  $_hdr_sum"
echo "  ──────────────────────────────────────────────────────"

_total_ok=0; _total_chg=0; _total_fail=0
_kind_packages_ok=0; _kind_packages_chg=0; _kind_packages_fail=0
_kind_config_ok=0; _kind_config_chg=0; _kind_config_fail=0
_kind_services_ok=0; _kind_services_chg=0; _kind_services_fail=0
if [[ -f "$UCC_SUMMARY_FILE" ]]; then
  while IFS='|' read -r _comp _a _b _c _d; do
    if [[ "$_a" == "tic" ]]; then
      printf '  %-22s  TIC  pass=%-3s  fail=%-3s  skip=%s\n' "$_comp" "$_b" "$_c" "$_d"
    else
      _total_ok=$(( _total_ok + _a ))
      _total_chg=$(( _total_chg + _b ))
      _total_fail=$(( _total_fail + _c ))
      _parts=""
      [[ $_a -gt 0 ]] && _parts="${_a} ok"
      [[ $_b -gt 0 ]] && _parts="${_parts:+$_parts  }${_b} changed"
      [[ $_c -gt 0 ]] && _parts="${_parts:+$_parts  }${_c} FAILED"
      printf '  %-22s  %s\n' "$_comp" "${_parts:----}"
    fi
  done < "$UCC_SUMMARY_FILE"
  echo "  ──────────────────────────────────────────────────────"
  printf '  %-22s  %s\n' "Total" "$(_summary_line "$_total_ok" "$_total_chg" "$_total_fail")"
fi

if [[ -f "$UCC_KIND_SUMMARY_FILE" ]]; then
  while IFS='|' read -r _kind _outcome; do
    _kind_bump "$_kind" "$_outcome"
  done < "$UCC_KIND_SUMMARY_FILE"
  echo "  ──────────────────────────────────────────────────────"
  echo "  By Kind"
  printf '  %-22s  %s\n' "Packages" "$(_summary_line "$_kind_packages_ok" "$_kind_packages_chg" "$_kind_packages_fail")"
  printf '  %-22s  %s\n' "Config" "$(_summary_line "$_kind_config_ok" "$_kind_config_chg" "$_kind_config_fail")"
  printf '  %-22s  %s\n' "Services" "$(_summary_line "$_kind_services_ok" "$_kind_services_chg" "$_kind_services_fail")"
fi

if [[ ${#FAILED_COMPONENTS[@]} -gt 0 ]]; then
  echo ""
  log_warn "Failed components: ${FAILED_COMPONENTS[*]}"
fi

echo "  ──────────────────────────────────────────────────────"
echo "  Services"
echo "    Ollama API       → http://127.0.0.1:11434   (ollama pull <model>)"
echo "    Unsloth Studio   → http://0.0.0.0:8888"
echo "    Open WebUI       → http://localhost:3000"
echo "    Flowise          → http://localhost:3001"
echo "    OpenHands        → http://localhost:3002"
echo "    n8n              → http://localhost:5678"
echo "    Qdrant           → http://localhost:6333"
echo "    aria2 RPC        → http://127.0.0.1:6800"
echo "    ariaflow web UI  → http://127.0.0.1:8001"
echo "  ──────────────────────────────────────────────────────"
echo "  Declarations: $UCC_DECLARATION_FILE"
echo "  Results:      $UCC_RESULT_FILE"
echo "========================================================"
echo ""

[[ ${#FAILED_COMPONENTS[@]} -eq 0 ]]
