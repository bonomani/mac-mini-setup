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
#       Impl  : lib/tic.sh + lib/tic_runner.sh
#
#  All components MUST be UCC + Basic compliant:
#    - declare BISS classification (Axis A + Axis B + Boundary) in header
#    - declare intent with ucc_target (observe / desired / install / update)
#    - emit structured NOTICE lines (observation / outcome / diff / proof)
#    - respect UCC_MODE (install | update) and UCC_DRY_RUN
#  Component verify runs TIC tests after all UCC components complete.
#
#  Framework version refs (updated 2026-03-25)
#    BGS : bgs@7961fb4
#    ASM : asm@dca032b
#    UCC : ucc@370c1f7
#    UIC : uic@11bd400  (unchanged)
#    TIC : tic@7cfba80  (unchanged)
# ============================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_detect_host_platform() {
  case "$(uname)" in
    Darwin) echo "macos" ;;
    Linux)
      if grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null \
         || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        echo "wsl"
      else
        echo "linux"
      fi
      ;;
    *) echo "unknown" ;;
  esac
}

export HOST_PLATFORM="$(_detect_host_platform)"
source "$DIR/lib/ucc.sh"
source "$DIR/lib/uic.sh"
source "$DIR/lib/tic.sh"
source "$DIR/lib/utils.sh"
source "$DIR/lib/summary.sh"

# ============================================================
#  UIC gate condition functions (read-only, no side effects)
# ============================================================
_gate_supported_platform(){ [[ "$HOST_PLATFORM" == "macos" || "$HOST_PLATFORM" == "linux" || "$HOST_PLATFORM" == "wsl" ]]; }
_gate_macos()           { [[ "$(uname)" == "Darwin" ]]; }
_gate_arm64()           { [[ "$(uname -m)" == "arm64" ]]; }
_gate_docker_daemon()   { docker info &>/dev/null 2>&1; }
_gate_docker_compose()  { docker compose version &>/dev/null 2>&1; }
_gate_docker_settings() { [[ -f "$HOME/Library/Group Containers/group.com.docker/settings.json" ]]; }
_gate_ai_apps_template(){
  local rel
  rel="$(python3 "$DIR/tools/read_config.py" --get "$DIR/ucc/software/ai-apps.yaml" stack.definition_template 2>/dev/null || true)"
  [[ -z "$rel" ]] && rel="stack/docker-compose.yml"
  [[ -f "$DIR/$rel" ]]
}
_gate_ollama_api()      { curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; }
_gate_sudo()            { sudo -n true 2>/dev/null; }

_load_components() {
  local manifest_dir="$DIR/ucc"
  local query_script="$DIR/tools/validate_targets_manifest.py"
  local components=()
  if [[ -d "$manifest_dir" && -x "$(command -v python3)" && -f "$query_script" ]]; then
    while IFS= read -r component; do
      [[ -n "$component" ]] && components+=("$component")
    done < <(python3 "$query_script" --components "$manifest_dir" 2>/dev/null || true)
  fi
  components+=("verify")
  printf '%s\n' "${components[@]}"
}

COMPONENTS=()
while IFS= read -r _component; do
  [[ -n "$_component" ]] && COMPONENTS+=("$_component")
done < <(_load_components)

_COMPONENT_POLICY_FILE="$DIR/policy/components.yaml"
_COMP_POLICY_NAMES=()
_COMP_POLICY_MODES=()

_load_component_policies() {
  local name mode
  [[ -f "$_COMPONENT_POLICY_FILE" ]] || return 0
  while IFS=$'\t' read -r name mode; do
    [[ -n "$name" ]] || continue
    _COMP_POLICY_NAMES+=("$name")
    _COMP_POLICY_MODES+=("${mode:-enabled}")
  done < <(yaml_records "$DIR" "$_COMPONENT_POLICY_FILE" components name mode)
}

_component_mode() {
  local comp="$1" i
  for i in "${!_COMP_POLICY_NAMES[@]}"; do
    [[ "${_COMP_POLICY_NAMES[$i]}" == "$comp" ]] || continue
    printf '%s' "${_COMP_POLICY_MODES[$i]}"
    return 0
  done
  printf 'enabled'
}

_component_supported_for() {
  local comp="$1" config="$2" platform item
  local supported=()
  if [[ "$comp" == "verify" ]]; then
    [[ "$HOST_PLATFORM" == "macos" ]] && return 0
    return 1
  fi
  while IFS= read -r item; do
    [[ -n "$item" ]] && supported+=("$item")
  done < <(yaml_list "$DIR" "$config" platforms)
  [[ ${#supported[@]} -eq 0 ]] && return 0
  for platform in "${supported[@]}"; do
    [[ "$platform" == "$HOST_PLATFORM" ]] && return 0
    [[ "$HOST_PLATFORM" == "wsl" && "$platform" == "linux" ]] && return 0
  done
  return 1
}

_display_component_name() {
  case "$1" in
    system) printf 'AI workstation' ;;
    verify) printf 'Verification' ;;
    *)      printf '%s' "$1" ;;
  esac
}

_load_component_policies

_uic_scope_active() {
  local scope="$1" comp dispatch config mode
  case "$scope" in
    global|target:*) return 0 ;;
    component:*)
      comp="${scope#component:}"
      mode="$(_component_mode "$comp")"
      [[ "$mode" == "enabled" ]] || return 1
      if [[ "$comp" == "verify" ]]; then
        _component_supported_for "$comp" "tic"
        return $?
      fi
      dispatch=$(python3 "$DIR/tools/validate_targets_manifest.py" --dispatch "$comp" "$DIR/ucc" 2>/dev/null || true)
      config=$(echo "$dispatch" | sed -n '4p')
      [[ -z "$config" ]] && return 0
      _component_supported_for "$comp" "$config"
      return $?
      ;;
  esac
  return 0
}


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
  $0 ollama ai-python-stack       # run specific components
  $0 --mode update ollama            # update Ollama only

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
load_uic_gates "$DIR"

# --- Preferences (safe defaults = most conservative choice) -
load_uic_preferences "$DIR"

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
abort_on_global_hard_gate

ARCH=$(uname -m)
case "$HOST_PLATFORM" in
  macos) TOTAL_MEM=$(sysctl -n hw.memsize 2>/dev/null || echo 0) ;;
  linux|wsl) TOTAL_MEM=$(awk '/MemTotal:/ {print $2 * 1024}' /proc/meminfo 2>/dev/null | head -1) ;;
  *) TOTAL_MEM=0 ;;
esac
TOTAL_GB=$(( TOTAL_MEM / 1024 / 1024 / 1024 ))

_arch_label="$ARCH"; [[ "$ARCH" == "arm64" ]] && _arch_label="arm64 (Apple Silicon / Metal)"
_ram_label="${TOTAL_GB} GB"; [[ $TOTAL_GB -ge 32 ]] && _ram_label="${TOTAL_GB} GB (large model capable)"


echo "========================================================"
_hdr_flags="mode=$UCC_MODE"; [[ "$UCC_DRY_RUN" == "1" ]] && _hdr_flags="$_hdr_flags dry_run=1"
echo "  AI Workstation Setup | platform=${HOST_PLATFORM} | $_hdr_flags | $(date '+%Y-%m-%d %H:%M')"
echo "  $_arch_label  ·  $_ram_label"
echo "  Global State     | $(uic_global_state_label) ($(uic_global_state_detail))"
print_profile_contracts
log_debug "correlation_id=$UCC_CORRELATION_ID"
echo "========================================================"

[[ "$HOST_PLATFORM" == "macos" && "$ARCH" != "arm64" ]] && log_warn "Intel Mac detected — some AI acceleration features may differ"
[[ $TOTAL_GB -lt 32 ]]   && log_warn "Less than 32 GB RAM — large models may be slow"

# --- Ensure brew is in PATH (re-checked after each component) ---
_refresh_brew_path() {
  command -v brew &>/dev/null && return
  for _bp in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
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
export UCC_PROFILE_SUMMARY_FILE="$HOME/.ai-stack/runs/${UCC_CORRELATION_ID}.profile-summary"
export UCC_TARGET_STATUS_FILE="$HOME/.ai-stack/runs/${UCC_CORRELATION_ID}.target-status"
export UCC_VERIFICATION_REPORT_FILE="$HOME/.ai-stack/runs/${UCC_CORRELATION_ID}.verification.report"
export UCC_TARGETS_MANIFEST="$DIR/ucc"
export UCC_TARGETS_QUERY_SCRIPT="$DIR/tools/validate_targets_manifest.py"
mkdir -p "$HOME/.ai-stack/runs"

_print_verification_section() {
  [[ -s "$UCC_VERIFICATION_REPORT_FILE" ]] || return 0
  cat "$UCC_VERIFICATION_REPORT_FILE"
}

if [[ -d "$DIR/ucc" && -x "$(command -v python3)" ]]; then
  if ! python3 "$DIR/tools/validate_targets_manifest.py" "$DIR/ucc" >/dev/null; then
    log_error "Invalid orchestration manifest directory: $DIR/ucc"
  fi
fi

# --- Run components -----------------------------------------
FAILED_COMPONENTS=()
_MANIFEST_DIR="$DIR/ucc"
_QUERY_SCRIPT="$DIR/tools/validate_targets_manifest.py"

_comp_prelude="source \"${DIR}/lib/ucc.sh\"; source \"${DIR}/lib/uic.sh\"; source \"${DIR}/lib/utils.sh\""

# Track components per layer for structured summary/output (bash 3 compatible)
_SOFTWARE_COMPS=()
_SYSTEM_COMPS=()
_TIC_COMPS=()

_comp_in_list() {
  local needle="$1"; shift
  local item
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

_collect_layer_components() {
  local filter="$1"
  local comps=() _cfg _comp
  for _i in "${!_DISP_COMPS[@]}"; do
    _cfg="${_DISP_CONFIGS[$_i]}"
    case "$filter" in
      software) [[ "$_cfg" == */system/* || "$_cfg" == "tic" ]] && continue ;;
      system)   [[ "$_cfg" != */system/* ]] && continue ;;
      tic)      [[ "$_cfg" != "tic" ]] && continue ;;
    esac
    _comp="${_DISP_COMPS[$_i]}"
    comps+=("$_comp")
  done
  printf '%s\n' "${comps[@]}"
}

print_execution_plan() {
  local software=() system=() tic=() item
  while IFS= read -r item; do [[ -n "$item" ]] && software+=("$(_display_component_name "$item")"); done < <(_collect_layer_components software)
  while IFS= read -r item; do [[ -n "$item" ]] && system+=("$(_display_component_name "$item")"); done < <(_collect_layer_components system)
  while IFS= read -r item; do [[ -n "$item" ]] && tic+=("$(_display_component_name "$item")"); done < <(_collect_layer_components tic)

  echo ""
  echo "  Execution Plan"
  echo "  ──────────────────────────────────────────────────────"
  [[ ${#software[@]} -gt 0 ]] && printf '  %-14s %s\n' "Software" "$(IFS=', '; echo "${software[*]}")"
  [[ ${#system[@]} -gt 0 ]]   && printf '  %-14s %s\n' "System"   "$(IFS=', '; echo "${system[*]}")"
  [[ ${#tic[@]} -gt 0 ]]      && printf '  %-14s %s\n' "Verify"   "$(IFS=', '; echo "${tic[*]}")"
  return 0
}

_print_component_header() {
  local comp="$1"
  printf '  [%s]\n' "$(_display_component_name "$comp")"
}

# Pre-collect dispatch info for all components (one query per component)
_DISP_COMPS=()
_DISP_LIBS=()
_DISP_RUNNERS=()
_DISP_ON_FAILS=()
_DISP_CONFIGS=()

for comp in "${TO_RUN[@]}"; do
  if [[ "$comp" == "verify" ]]; then
    _mode="$(_component_mode "$comp")"
    case "$_mode" in
      disabled)
        log_info "Skipping $(_display_component_name "$comp") (policy=disabled)"
        continue
        ;;
      remove)
        log_warn "Component $comp policy=remove — removal is not implemented yet; skipping"
        continue
        ;;
    esac
    if ! _component_supported_for "$comp" "tic"; then
      log_info "Skipping $(_display_component_name "$comp") (platform=${HOST_PLATFORM} unsupported)"
      continue
    fi
    _DISP_COMPS+=("$comp")
    _DISP_LIBS+=("")
    _DISP_RUNNERS+=("")
    _DISP_ON_FAILS+=("")
    _DISP_CONFIGS+=("tic")
    continue
  fi
  _dispatch=$(python3 "$_QUERY_SCRIPT" --dispatch "$comp" "$_MANIFEST_DIR" 2>/dev/null || true)
  _libs=$(echo "$_dispatch" | sed -n '1p')
  _runner=$(echo "$_dispatch" | sed -n '2p')
  _on_fail=$(echo "$_dispatch" | sed -n '3p')
  _config=$(echo "$_dispatch" | sed -n '4p')
  _mode="$(_component_mode "$comp")"
  case "$_mode" in
    disabled)
      log_info "Skipping $(_display_component_name "$comp") (policy=disabled)"
      continue
      ;;
    remove)
      log_warn "Component $comp policy=remove — removal is not implemented yet; skipping"
      continue
      ;;
  esac
  if [[ -z "$_libs" || -z "$_runner" || -z "$_config" ]]; then
    log_warn "Component $comp has no dispatch info in manifest — skipping"
    continue
  fi
  if ! _component_supported_for "$comp" "$_config"; then
    log_info "Skipping $(_display_component_name "$comp") (platform=${HOST_PLATFORM} unsupported)"
    continue
  fi
  _DISP_COMPS+=("$comp")
  _DISP_LIBS+=("$_libs")
  _DISP_RUNNERS+=("$_runner")
  _DISP_ON_FAILS+=("$_on_fail")
  _DISP_CONFIGS+=("$_config")
done

_run_comp() {
  local comp="$1" _libs="$2" _runner="$3" _on_fail="$4" _config="$5"
  if uic_component_blocked "$comp"; then
    log_warn "Component $comp blocked by UIC hard gate — outcome=failed, failure_class=permanent, reason=gate_failed"
    FAILED_COMPONENTS+=("$comp"); return
  fi
  local _src=""
  for _lib in $_libs; do _src="${_src}source \"${DIR}/lib/${_lib}.sh\"; "; done
  local _run
  case "$_on_fail" in
    exit)   _run="ucc_reset_registered_targets; export UCC_TARGET_DEFER=1; ${_runner} \"${DIR}\" \"${_config}\" && ucc_flush_registered_targets \"${comp}\" || { ucc_summary \"${comp}\"; exit 1; }" ;;
    ignore) _run="ucc_reset_registered_targets; export UCC_TARGET_DEFER=1; ${_runner} \"${DIR}\" \"${_config}\" && ucc_flush_registered_targets \"${comp}\" || true" ;;
    *)      _run="ucc_reset_registered_targets; export UCC_TARGET_DEFER=1; ${_runner} \"${DIR}\" \"${_config}\" && ucc_flush_registered_targets \"${comp}\"" ;;
  esac
  if ! bash -c "${_comp_prelude}; ${_src}${_run}; ucc_summary \"${comp}\""; then
    log_warn "Component failed: $comp"
    FAILED_COMPONENTS+=("$comp")
  fi
  _refresh_brew_path
}

# _run_layer <label> <filter> <comps_array_ref>
# filter: "software" | "system" | "tic"
_run_layer() {
  local label="$1" filter="$2" comps_ref="$3"
  echo ""; printf '── %s\n' "$label"
  for _i in "${!_DISP_COMPS[@]}"; do
    local _cfg="${_DISP_CONFIGS[$_i]}"
    case "$filter" in
      software) [[ "$_cfg" == */system/* || "$_cfg" == "tic" ]] && continue ;;
      system)   [[ "$_cfg" != */system/* ]] && continue ;;
      tic)      [[ "$_cfg" != "tic" ]] && continue ;;
    esac
    local comp="${_DISP_COMPS[$_i]}"
    eval "${comps_ref}+=(\"\$comp\")"
    _print_component_header "$comp"
    if [[ "$filter" == "tic" ]]; then
      if uic_component_blocked "$comp"; then
        log_warn "Component $comp blocked by UIC hard gate"
        FAILED_COMPONENTS+=("$comp"); continue
      fi
      if ! bash -c "${_comp_prelude}; source \"${DIR}/lib/tic.sh\"; source \"${DIR}/lib/tic_runner.sh\"; run_verify \"${DIR}\"" \
           > "$UCC_VERIFICATION_REPORT_FILE"; then
        log_warn "Component failed: $comp"; FAILED_COMPONENTS+=("$comp")
      fi
      [[ -s "$UCC_VERIFICATION_REPORT_FILE" ]] && cat "$UCC_VERIFICATION_REPORT_FILE"
    else
      _run_comp "$comp" "${_DISP_LIBS[$_i]}" "${_DISP_RUNNERS[$_i]}" "${_DISP_ON_FAILS[$_i]}" "$_cfg"
    fi
  done
}

print_execution_plan

_run_layer "Convergence / software" "software" _SOFTWARE_COMPS
# Rebuild brew cache once after all software components — subshell upgrades
# do not propagate back to the parent shell, so we refresh here in bulk
# rather than after each component (which would be 4 brew calls × N components).
if [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" == "always-upgrade" ]] \
    && command -v brew &>/dev/null; then
  brew_cache_outdated 2>/dev/null || true
fi
_run_layer "Convergence / system"   "system"   _SYSTEM_COMPS
_run_layer "Verification"           "tic"      _TIC_COMPS

# --- Final summary ------------------------------------------
print_final_summary "$DIR" "$UCC_MODE" "${UCC_DRY_RUN:-0}"

[[ ${#FAILED_COMPONENTS[@]} -eq 0 ]]
