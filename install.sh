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

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "ERROR: run this script as your normal user, not via sudo." >&2
  echo "       If admin rights are needed, acquire a sudo ticket first:" >&2
  echo "       sudo -v && ./install.sh" >&2
  exit 1
fi

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

_detect_host_platform_variant() {
  case "$(uname)" in
    Darwin) echo "macos" ;;
    Linux)
      if grep -qiE 'wsl2' /proc/sys/kernel/osrelease 2>/dev/null \
         || grep -qiE 'wsl2' /proc/version 2>/dev/null; then
        echo "wsl2"
      elif grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null \
         || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        echo "wsl1"
      else
        echo "linux"
      fi
      ;;
    *) echo "unknown" ;;
  esac
}

export HOST_PLATFORM="$(_detect_host_platform)"
export HOST_PLATFORM_VARIANT="$(_detect_host_platform_variant)"
source "$DIR/lib/ucc.sh"
source "$DIR/lib/uic.sh"
source "$DIR/lib/tic.sh"
source "$DIR/lib/utils.sh"
source "$DIR/lib/summary.sh"

# ============================================================
#  Early manifest cache (needed by gates and component list)
# ============================================================
_MANIFEST_DIR="$DIR/ucc"
_QUERY_SCRIPT="$DIR/tools/validate_targets_manifest.py"
_all_dispatch=$(python3 "$_QUERY_SCRIPT" --all-dispatch "$_MANIFEST_DIR" 2>/dev/null || true)
_GATE_DOCKER_SETTINGS_REL=$(python3 "$DIR/tools/read_config.py" --get "$DIR/ucc/system/docker-config.yaml" settings_relpath 2>/dev/null || true)
_GATE_AI_APPS_TEMPLATE_REL=$(python3 "$DIR/tools/read_config.py" --get "$DIR/ucc/software/ai-apps.yaml" stack.definition_template 2>/dev/null || true)
[[ -z "$_GATE_DOCKER_SETTINGS_REL" ]] && _GATE_DOCKER_SETTINGS_REL="Library/Group Containers/group.com.docker/settings.json"
[[ -z "$_GATE_AI_APPS_TEMPLATE_REL" ]] && _GATE_AI_APPS_TEMPLATE_REL="stack/docker-compose.yml"

# ============================================================
#  UIC gate condition functions (read-only, no side effects)
# ============================================================
_gate_supported_platform(){ [[ "$HOST_PLATFORM_VARIANT" == "macos" || "$HOST_PLATFORM_VARIANT" == "linux" || "$HOST_PLATFORM_VARIANT" == "wsl2" ]]; }
_gate_arm64()           { [[ "$(uname -m)" == "arm64" ]]; }
_gate_docker_daemon()   { docker info &>/dev/null 2>&1; }
_gate_docker_compose()  { docker compose version &>/dev/null 2>&1; }
_gate_docker_settings() { [[ -f "$HOME/$_GATE_DOCKER_SETTINGS_REL" ]]; }
_gate_ai_apps_template(){ [[ -f "$DIR/$_GATE_AI_APPS_TEMPLATE_REL" ]]; }
_gate_ollama_api()      {
  local host port path
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      api_host)      host="$value" ;;
      api_port)      port="$value" ;;
      api_tags_path) path="$value" ;;
    esac
  done < <(python3 "$DIR/tools/read_config.py" --get-many "$DIR/ucc/software/ai-apps.yaml" \
      api_host api_port api_tags_path 2>/dev/null || true)
  [[ -z "$host" ]] && host="127.0.0.1"
  [[ -z "$port" ]] && port="11434"
  [[ -z "$path" ]] && path="/api/tags"
  curl -fsS "http://${host}:${port}${path}" >/dev/null 2>&1
}
_gate_networkquality()  { command -v networkQuality >/dev/null 2>&1; }
_gate_sudo()            { sudo -n true 2>/dev/null; }

_load_components() {
  local components=()
  if [[ -n "$_all_dispatch" ]]; then
    while IFS= read -r component; do
      [[ -n "$component" ]] && components+=("$component")
    done < <(printf '%s\n' "$_all_dispatch" | awk -F'\t' '{print $1}')
  elif [[ -d "$_MANIFEST_DIR" && -x "$(command -v python3)" && -f "$_QUERY_SCRIPT" ]]; then
    while IFS= read -r component; do
      [[ -n "$component" ]] && components+=("$component")
    done < <(python3 "$_QUERY_SCRIPT" --components "$_MANIFEST_DIR" 2>/dev/null || true)
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
    [[ "$platform" == "${HOST_PLATFORM_VARIANT:-unknown}" ]] && return 0
    [[ "$platform" == "$HOST_PLATFORM" ]] && return 0
    [[ "$HOST_PLATFORM" == "wsl" && "$platform" == "linux" ]] && return 0
  done
  return 1
}

_display_component_name() {
  case "$1" in
    macos-software-update) printf 'macOS software update' ;;
    system) printf 'AI workstation' ;;
    verify) printf 'Verification' ;;
    *)      printf '%s' "$1" ;;
  esac
}

_load_component_policies

_uic_scope_active() {
  local scope="$1" comp config mode
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
      config=$(printf '%s\n' "${_all_dispatch:-}" | awk -F'\t' -v c="$comp" '$1==c{print $5; exit}')
      [[ -z "$config" ]] && return 0
      _component_supported_for "$comp" "$config"
      return $?
      ;;
  esac
  return 0
}


usage() {
  cat <<EOF

Usage: $0 [options] [component|target ...]

Without arguments, runs ALL components in order.
Pass a component name to run that component.
Pass a target name (not a component) to run only that target.

Options:
  --mode install    Install missing components (default)
  --mode update     Update already-installed components
  --dry-run         Show what would change without applying it
  --preflight       Evaluate UIC gates and preferences; do NOT converge
  --pref key=value  Set a UIC preference for this run only (repeatable)
  --debug           Show DEBUG-level output
  -h, --help        Show this help

Available components:
$(printf '  %s\n' "${COMPONENTS[@]}")

Examples:
  $0                                    # full install
  $0 --dry-run                          # preview full install
  $0 --mode update                      # update everything
  $0 --mode update --dry-run            # preview updates
  $0 ollama ai-python-stack             # run specific components
  $0 --mode update ollama               # update Ollama only
  $0 unsloth-studio                     # run single target (auto-resolves component)
  $0 --pref preferred-driver-policy=migrate docker  # migrate Docker from DMG to brew-cask

EOF
  exit 0
}

# --- Parse arguments ----------------------------------------
TO_RUN=()
export UCC_TARGET_FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)       export UCC_DRY_RUN=1;     shift ;;
    --mode)          export UCC_MODE="$2";    shift 2 ;;
    --debug)         export UCC_DEBUG=1;      shift ;;
    --preflight)     export UIC_PREFLIGHT=1;  shift ;;
    --pref)
      _pref_kv="$2"; shift 2
      _pref_key="${_pref_kv%%=*}"
      _pref_val="${_pref_kv#*=}"
      _pref_env="UIC_PREF_$(echo "${_pref_key//-/_}" | tr '[:lower:]' '[:upper:]')"
      export "${_pref_env}=${_pref_val}"
      ;;
    -h|--help)       usage ;;
    -*)              log_warn "Unknown option: $1"; shift ;;
    *)               TO_RUN+=("$1"); shift ;;
  esac
done

# Resolve each positional arg:
#   component:<name>  → explicit component
#   target:<name>     → explicit target, auto-resolve component
#   <name>            → try component first, then target (ambiguous names: component wins)
_resolved=()
for _arg in ${TO_RUN[@]+"${TO_RUN[@]}"}; do
  case "$_arg" in
    component:*)
      _name="${_arg#component:}"
      if ! printf '%s\n' "${COMPONENTS[@]}" | grep -qx "$_name"; then
        log_error "Unknown component: '$_name'"
      fi
      _resolved+=("$_name")
      ;;
    target:*)
      _name="${_arg#target:}"
      _comp=$(python3 "$_QUERY_SCRIPT" --find-target "$_name" "$_MANIFEST_DIR" 2>/dev/null || true)
      if [[ -z "$_comp" ]]; then
        log_error "Unknown target: '$_name'"
      fi
      log_info "Resolved target '$_name' → component '$_comp'"
      [[ -z "$UCC_TARGET_FILTER" ]] && export UCC_TARGET_FILTER="$_name"
      _resolved+=("$_comp")
      ;;
    *)
      if printf '%s\n' "${COMPONENTS[@]}" | grep -qx "$_arg"; then
        _resolved+=("$_arg")
      else
        _comp=$(python3 "$_QUERY_SCRIPT" --find-target "$_arg" "$_MANIFEST_DIR" 2>/dev/null || true)
        if [[ -z "$_comp" ]]; then
          log_error "Unknown component or target: '$_arg'"
        fi
        log_info "Resolved target '$_arg' → component '$_comp'"
        [[ -z "$UCC_TARGET_FILTER" ]] && export UCC_TARGET_FILTER="$_arg"
        _resolved+=("$_comp")
      fi
      ;;
  esac
done
TO_RUN=("${_resolved[@]+"${_resolved[@]}"}")

[[ ${#TO_RUN[@]} -eq 0 ]] && TO_RUN=("${COMPONENTS[@]}")

# Validate mode
[[ "$UCC_MODE" =~ ^(install|update)$ ]] || log_error "Invalid --mode: $UCC_MODE (must be install or update)"

# ============================================================
#  UIC — Gates and Preferences
#  Evaluated before any UCC convergence begins (UIC §6)
# ============================================================

# --- Pre-load remaining manifest caches (one python3 call for all four) ---
export _UCC_ALL_DEPS_CACHE
export _UCC_ALL_SOFT_DEPS_CACHE
export _UCC_ALL_ORDERED_CACHE
export _UCC_ALL_DISPLAY_NAMES_CACHE
export _UCC_ALL_ORACLES_CACHE
_UCC_ALL_DEPS_CACHE=""
_UCC_ALL_SOFT_DEPS_CACHE=""
_UCC_ALL_ORDERED_CACHE=""
_UCC_ALL_DISPLAY_NAMES_CACHE=""
_UCC_ALL_ORACLES_CACHE=""
_current_section=""
while IFS= read -r _cache_line; do
  case "$_cache_line" in
    "__section__	all_deps")              _current_section="deps" ;;
    "__section__	all_soft_deps")         _current_section="soft_deps" ;;
    "__section__	all_ordered_targets")   _current_section="ordered" ;;
    "__section__	all_display_names")     _current_section="display" ;;
    "__section__	all_oracle_configured") _current_section="oracles" ;;
    *)
      case "$_current_section" in
        deps)    _UCC_ALL_DEPS_CACHE="${_UCC_ALL_DEPS_CACHE:+${_UCC_ALL_DEPS_CACHE}
}${_cache_line}" ;;
        soft_deps) _UCC_ALL_SOFT_DEPS_CACHE="${_UCC_ALL_SOFT_DEPS_CACHE:+${_UCC_ALL_SOFT_DEPS_CACHE}
}${_cache_line}" ;;
        ordered) _UCC_ALL_ORDERED_CACHE="${_UCC_ALL_ORDERED_CACHE:+${_UCC_ALL_ORDERED_CACHE}
}${_cache_line}" ;;
        display) _UCC_ALL_DISPLAY_NAMES_CACHE="${_UCC_ALL_DISPLAY_NAMES_CACHE:+${_UCC_ALL_DISPLAY_NAMES_CACHE}
}${_cache_line}" ;;
        oracles) _UCC_ALL_ORACLES_CACHE="${_UCC_ALL_ORACLES_CACHE:+${_UCC_ALL_ORACLES_CACHE}
}${_cache_line}" ;;
      esac
      ;;
  esac
done < <(python3 "$_QUERY_SCRIPT" --all-caches "$_MANIFEST_DIR" 2>/dev/null || true)
unset _current_section _cache_line

# --- Gates --------------------------------------------------
load_uic_gates "$DIR"

# --- Preferences (safe defaults = most conservative choice) -
load_uic_preferences "$DIR"

# --- Resolve (evaluate gates, report preferences) -----------
_UIC_RC=0
uic_resolve || _UIC_RC=$?
uic_export

# Warm Brew caches before any component runs. Version caches are needed in all
# modes; outdated caches are only useful when upgrades are enabled.
if command -v brew &>/dev/null; then
  if [[ "${UIC_PREF_PACKAGE_UPDATE_POLICY:-always-upgrade}" == "always-upgrade" ]]; then
    brew update --force --quiet 2>/dev/null || true
  fi
  brew_refresh_caches
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
print_layer_contracts
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

if [[ -d "$DIR/ucc" && -x "$(command -v python3)" ]]; then
  if ! python3 "$DIR/tools/validate_targets_manifest.py" "$DIR/ucc" >/dev/null; then
    log_error "Invalid orchestration manifest directory: $DIR/ucc"
  fi
fi

# --- Run components -----------------------------------------
FAILED_COMPONENTS=()

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
  [[ ${#comps[@]} -gt 0 ]] && printf '%s\n' "${comps[@]}"
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
  _dispatch=$(printf '%s\n' "$_all_dispatch" | awk -F'\t' -v c="$comp" '$1==c{print $2"\n"$3"\n"$4"\n"$5; exit}')
  _libs=$(printf '%s\n' "$_dispatch" | sed -n '1p')
  _runner=$(printf '%s\n' "$_dispatch" | sed -n '2p')
  _on_fail=$(printf '%s\n' "$_dispatch" | sed -n '3p')
  _config=$(printf '%s\n' "$_dispatch" | sed -n '4p')
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

# Pre-load per-target scalar+evidence cache for each component YAML file.
# One python3 call per file; exports _UCC_YTGT_<yaml_fn>_<target_fn>=base64(NUL-rows).
# Setup functions read from these vars (base64 -d) instead of spawning python3.
_UCC_YAML_BATCH_KEYS="profile actions.install actions.update \
  driver.externally_managed_updates type oracle.configured observe_cmd \
  state_model observe_success observe_failure oracle.runtime \
  desired_cmd desired_value dependency_gate driver.kind \
  driver.service_name driver.package_ref driver.app_path \
  driver.greedy_auto_updates stopped_installation stopped_runtime \
  stopped_health stopped_dependencies admin_required \
  driver.ref driver.probe_pkg driver.install_packages \
  driver.min_version driver.extension_id driver.package \
  driver.domain driver.key driver.value driver.type driver.setting \
  driver.settings_relpath driver.patch_relpath \
  driver.update_api driver.download_url_tpl driver.package_ext driver.brew_cask \
  driver.version driver.previous_ref driver.cask \
  driver.plist driver.bin driver.process driver.path_env"
_seen_yaml_files=()
for _i in "${!_DISP_COMPS[@]}"; do
  _yaml_file="${_DISP_CONFIGS[$_i]}"
  [[ -z "$_yaml_file" || "$_yaml_file" == "tic" ]] && continue
  _already_seen=0
  for _seen in "${_seen_yaml_files[@]+"${_seen_yaml_files[@]}"}"; do
    [[ "$_seen" == "$_yaml_file" ]] && { _already_seen=1; break; }
  done
  [[ $_already_seen -eq 1 ]] && continue
  _seen_yaml_files+=("$_yaml_file")
  _yaml_fn="${_yaml_file//[^a-zA-Z0-9]/_}"
  # One python3 call per YAML file; outputs shell export statements read by eval
  while IFS= read -r _export_stmt; do
    [[ -n "$_export_stmt" ]] && eval "$_export_stmt"
  done < <(python3 "$DIR/tools/read_config.py" \
    --split-yaml-batch "$_yaml_fn" "$DIR/$_yaml_file" \
    $(printf '%s\n' "$_UCC_YAML_BATCH_KEYS") 2>/dev/null || true)
done
unset _seen_yaml_files _already_seen _seen _yaml_file _yaml_fn _i _export_stmt

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
  [[ "$comp" == "docker" ]] && env -i HOME="$HOME" PATH="$PATH" USER="$USER" TERM="$TERM" script -q /dev/null docker desktop start
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
# Rebuild Brew caches once after all software components — subshell upgrades
# do not propagate back to the parent shell, so we refresh here in bulk.
if command -v brew &>/dev/null; then
  brew_refresh_caches 2>/dev/null || true
fi
_run_layer "Convergence / system"   "system"   _SYSTEM_COMPS
_run_layer "Verification"           "tic"      _TIC_COMPS

# --- Final summary ------------------------------------------
print_final_summary "$DIR" "$UCC_MODE" "${UCC_DRY_RUN:-0}"

[[ ${#FAILED_COMPONENTS[@]} -eq 0 ]]
