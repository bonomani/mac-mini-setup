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
#       Impl  : lib/tic.sh + components/verify.sh
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
source "$DIR/lib/ucc.sh"
source "$DIR/lib/uic.sh"
source "$DIR/lib/tic.sh"
source "$DIR/lib/utils.sh"

# ============================================================
#  UIC gate condition functions (read-only, no side effects)
# ============================================================
_gate_macos()           { [[ "$(uname)" == "Darwin" ]]; }
_gate_arm64()           { [[ "$(uname -m)" == "arm64" ]]; }
_gate_docker_daemon()   { docker info &>/dev/null 2>&1; }
_gate_docker_settings() { [[ -f "$HOME/Library/Group Containers/group.com.docker/settings.json" ]]; }
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

_print_services_summary() {
  local services_file="$DIR/services.yaml"
  local name="" url="" note="" line=""
  [[ -f "$services_file" ]] || return 0
  echo "  ──────────────────────────────────────────────────────"
  echo "  Services"
  while IFS= read -r _line; do
    case "$_line" in
      "  - name: "*)
        [[ -n "$name" ]] || { name="${_line#  - name: }"; continue; }
        line="    $(printf '%-16s' "$name") → ${url}"
        [[ -n "$note" ]] && line="${line}   (${note})"
        echo "$line"
        name="${_line#  - name: }"
        url=""
        note=""
        ;;
      "    name: "*)
        name="${_line#    name: }"
        ;;
      "    url: "*)
        url="${_line#    url: }"
        ;;
      "    note: "*)
        note="${_line#    note: }"
        ;;
    esac
  done < "$services_file"
  if [[ -n "$name" ]]; then
    line="    $(printf '%-16s' "$name") → ${url}"
    [[ -n "$note" ]] && line="${line}   (${note})"
    echo "$line"
  fi
}

_load_uic_preferences() {
  local pref_file="$DIR/policy/preferences.yaml"
  local name="" default="" options="" scope="" rationale=""
  [[ -f "$pref_file" ]] || return 0
  while IFS= read -r _line; do
    case "$_line" in
      "  - name: "*)
        if [[ -n "$name" ]]; then
          uic_preference \
            --name "$name" \
            --default "$default" \
            --options "$options" \
            --rationale "$rationale" \
            --scope "${scope:-global}"
        fi
        name="${_line#  - name: }"
        default=""
        options=""
        scope="global"
        rationale=""
        ;;
      "    default: "*)
        default="${_line#    default: }"
        ;;
      "    options: "*)
        options="${_line#    options: }"
        ;;
      "    scope: "*)
        scope="${_line#    scope: }"
        ;;
      "    rationale: "*)
        rationale="${_line#    rationale: }"
        ;;
    esac
  done < "$pref_file"
  if [[ -n "$name" ]]; then
    uic_preference \
      --name "$name" \
      --default "$default" \
      --options "$options" \
      --rationale "$rationale" \
      --scope "${scope:-global}"
  fi
}

_load_uic_gates() {
  local gates_file="$DIR/policy/gates.yaml"
  local name="" condition="" scope="" class="" target_state="" blocking=""
  [[ -f "$gates_file" ]] || return 0
  while IFS= read -r _line; do
    case "$_line" in
      "  - name: "*)
        if [[ -n "$name" ]]; then
          uic_gate \
            --name "$name" \
            --condition "$condition" \
            --scope "${scope:-global}" \
            --class "${class:-readiness}" \
            --target-state "$target_state" \
            --blocking "${blocking:-hard}"
        fi
        name="${_line#  - name: }"
        condition=""
        scope="global"
        class="readiness"
        target_state=""
        blocking="hard"
        ;;
      "    condition: "*)
        condition="${_line#    condition: }"
        ;;
      "    scope: "*)
        scope="${_line#    scope: }"
        ;;
      "    class: "*)
        class="${_line#    class: }"
        ;;
      "    target_state: "*)
        target_state="${_line#    target_state: }"
        ;;
      "    blocking: "*)
        blocking="${_line#    blocking: }"
        ;;
    esac
  done < "$gates_file"
  if [[ -n "$name" ]]; then
    uic_gate \
      --name "$name" \
      --condition "$condition" \
      --scope "${scope:-global}" \
      --class "${class:-readiness}" \
      --target-state "$target_state" \
      --blocking "${blocking:-hard}"
  fi
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
_load_uic_gates

# --- Preferences (safe defaults = most conservative choice) -
_load_uic_preferences

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

_profile_var_prefix() {
  case "$1" in
    presence) printf '_profile_presence' ;;
    configured) printf '_profile_configured' ;;
    runtime) printf '_profile_runtime' ;;
    parametric) printf '_profile_parametric' ;;
    *) printf '' ;;
  esac
}

_profile_bump() {
  local prefix
  prefix="$(_profile_var_prefix "$1")"
  [[ -z "$prefix" ]] && return 0
  case "$2" in
    ok) eval "${prefix}_ok=\$(( ${prefix}_ok + 1 ))" ;;
    changed) eval "${prefix}_chg=\$(( ${prefix}_chg + 1 ))" ;;
    failed) eval "${prefix}_fail=\$(( ${prefix}_fail + 1 ))" ;;
  esac
}

_print_profile_contracts() {
  local profile expected
  for profile in presence configured runtime parametric; do
    expected="$(ucc_profile_expected_text "$profile")"
    [[ -n "$expected" ]] || continue
    printf '  Profile %-10s | baseline: %s\n' "$(ucc_profile_label "$profile")" "$expected"
  done
}

echo "========================================================"
_hdr_flags="mode=$UCC_MODE"; [[ "$UCC_DRY_RUN" == "1" ]] && _hdr_flags="$_hdr_flags dry_run=1"
echo "  Mac Mini AI Setup | $_hdr_flags | $(date '+%Y-%m-%d %H:%M')"
echo "  $_arch_label  ·  $_ram_label"
echo "  Global State     | $(_global_state_label) ($(_global_state_detail))"
_print_profile_contracts
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
_current_section=""

_print_section_header() {
  local section="$1"
  [[ "$section" == "$_current_section" ]] && return
  _current_section="$section"
  echo ""
  printf '── %s\n' "$section"
}

_comp_in_list() {
  local needle="$1"; shift
  local item
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

for comp in "${TO_RUN[@]}"; do
  # UIC: skip component if a hard gate scoped to it has failed
  if uic_component_blocked "$comp"; then
    log_warn "Component $comp blocked by UIC hard gate — outcome=failed, failure_class=permanent, reason=gate_failed"
    FAILED_COMPONENTS+=("$comp")
    continue
  fi

  if [[ "$comp" == "verify" ]]; then
    _TIC_COMPS+=("$comp")
    _print_section_header "TIC"
    SCRIPT="$DIR/components/verify.sh"
    if ! bash -c "${_comp_prelude}; source \"${SCRIPT}\"" -- "$SCRIPT" > "$UCC_VERIFICATION_REPORT_FILE"; then
      log_warn "Component failed: $comp"
      FAILED_COMPONENTS+=("$comp")
    fi
  else
    # Read dispatch info from targets manifest
    _dispatch=$(python3 "$_QUERY_SCRIPT" --dispatch "$comp" "$_MANIFEST_DIR" 2>/dev/null || true)
    _libs=$(echo "$_dispatch" | sed -n '1p')
    _runner=$(echo "$_dispatch" | sed -n '2p')
    _on_fail=$(echo "$_dispatch" | sed -n '3p')
    _config=$(echo "$_dispatch" | sed -n '4p')

    if [[ -z "$_libs" || -z "$_runner" || -z "$_config" ]]; then
      log_warn "Component $comp has no dispatch info in manifest — skipping"
      continue
    fi

    # Determine layer from config path
    if [[ "$_config" == */system/* ]]; then
      _SYSTEM_COMPS+=("$comp")
      _print_section_header "UCC / system"
    else
      _SOFTWARE_COMPS+=("$comp")
      _print_section_header "UCC / software"
    fi

    # Build source lines for each lib
    _src=""
    for _lib in $_libs; do
      _src="${_src}source \"${DIR}/lib/${_lib}.sh\"; "
    done

    # Build runner call with on_fail handling
    case "$_on_fail" in
      exit)   _run="${_runner} \"${DIR}\" \"${_config}\" || { ucc_summary \"${comp}\"; exit 1; }" ;;
      ignore) _run="${_runner} \"${DIR}\" \"${_config}\" || true" ;;
      *)      _run="${_runner} \"${DIR}\" \"${_config}\"" ;;
    esac

    if ! bash -c "${_comp_prelude}; ${_src}${_run}; ucc_summary \"${comp}\""; then
      log_warn "Component failed: $comp"
      FAILED_COMPONENTS+=("$comp")
    fi
  fi
  # Refresh brew PATH in case it was just installed by this component
  _refresh_brew_path
done

_print_verification_section

# --- Final summary ------------------------------------------
echo ""
echo "========================================================"
_hdr_sum="Summary | mode=$UCC_MODE"
[[ "$UCC_DRY_RUN" == "1" ]] && _hdr_sum="$_hdr_sum | dry_run=1"
echo "  $_hdr_sum"
echo "  ──────────────────────────────────────────────────────"

_total_ok=0; _total_chg=0; _total_fail=0
_profile_presence_ok=0; _profile_presence_chg=0; _profile_presence_fail=0
_profile_configured_ok=0; _profile_configured_chg=0; _profile_configured_fail=0
_profile_runtime_ok=0; _profile_runtime_chg=0; _profile_runtime_fail=0
_profile_parametric_ok=0; _profile_parametric_chg=0; _profile_parametric_fail=0

_print_summary_section() {
  local section_label="$1"; shift
  local _comps=("$@")
  local _printed=0
  [[ ${#_comps[@]} -eq 0 ]] && return
  if [[ -f "$UCC_SUMMARY_FILE" ]]; then
    while IFS='|' read -r _comp _a _b _c _d; do
      _comp_in_list "$_comp" "${_comps[@]}" || continue
      if [[ $_printed -eq 0 ]]; then
        echo "  ── $section_label"
        _printed=1
      fi
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
  fi
}

_print_summary_section "UCC / software" "${_SOFTWARE_COMPS[@]}"
_print_summary_section "UCC / system"   "${_SYSTEM_COMPS[@]}"
_print_summary_section "TIC"            "${_TIC_COMPS[@]}"
echo "  ──────────────────────────────────────────────────────"
printf '  %-22s  %s\n' "Total" "$(_summary_line "$_total_ok" "$_total_chg" "$_total_fail")"

if [[ -f "$UCC_PROFILE_SUMMARY_FILE" ]]; then
  while IFS='|' read -r _profile _outcome; do
    _profile_bump "$_profile" "$_outcome"
  done < "$UCC_PROFILE_SUMMARY_FILE"
  echo "  ──────────────────────────────────────────────────────"
  echo "  By Profile"
  printf '  %-22s  %s\n' "$(ucc_profile_label presence)"   "$(_summary_line "$_profile_presence_ok"   "$_profile_presence_chg"   "$_profile_presence_fail")"
  printf '  %-22s  %s\n' "$(ucc_profile_label configured)" "$(_summary_line "$_profile_configured_ok" "$_profile_configured_chg" "$_profile_configured_fail")"
  printf '  %-22s  %s\n' "$(ucc_profile_label runtime)"    "$(_summary_line "$_profile_runtime_ok"    "$_profile_runtime_chg"    "$_profile_runtime_fail")"
  printf '  %-22s  %s\n' "$(ucc_profile_label parametric)" "$(_summary_line "$_profile_parametric_ok" "$_profile_parametric_chg" "$_profile_parametric_fail")"
fi

if [[ ${#FAILED_COMPONENTS[@]} -gt 0 ]]; then
  echo ""
  log_warn "Failed components: ${FAILED_COMPONENTS[*]}"
fi

_print_services_summary
echo "  ──────────────────────────────────────────────────────"
echo "  Declarations: $UCC_DECLARATION_FILE"
echo "  Results:      $UCC_RESULT_FILE"
echo "========================================================"
echo ""

[[ ${#FAILED_COMPONENTS[@]} -eq 0 ]]
