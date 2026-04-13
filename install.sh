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

_detect_host_arch() { uname -m; }

_detect_host_os_id() {
  case "$(uname)" in
    Darwin) printf 'macos-%s' "$(sw_vers -productVersion 2>/dev/null || echo unknown)" ;;
    Linux)
      if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        printf '%s-%s' "${ID:-unknown}" "${VERSION_ID:-unknown}"
      else
        printf 'linux-unknown'
      fi
      ;;
    *) printf 'unknown' ;;
  esac
}

_detect_host_package_manager() {
  if command -v brew >/dev/null 2>&1; then printf 'brew'
  elif command -v apt-get >/dev/null 2>&1; then printf 'apt'
  elif command -v dnf >/dev/null 2>&1; then printf 'dnf'
  elif command -v pacman >/dev/null 2>&1; then printf 'pacman'
  elif command -v zypper >/dev/null 2>&1; then printf 'zypper'
  else printf 'unknown'
  fi
}

export HOST_ARCH="$(_detect_host_arch)"
export HOST_OS_ID="$(_detect_host_os_id)"
export HOST_PACKAGE_MANAGER="$(_detect_host_package_manager)"

_build_host_fingerprint() {
  local os ver arch pm
  arch="$HOST_ARCH"
  pm="$HOST_PACKAGE_MANAGER"
  case "$HOST_PLATFORM" in
    macos)
      os="macos"
      ver="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
      ;;
    wsl)
      # wsl2-ubuntu/22.04 or wsl1-debian/12
      if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        os="${HOST_PLATFORM_VARIANT}-${ID:-linux}"
        ver="${VERSION_ID:-unknown}"
      else
        os="${HOST_PLATFORM_VARIANT}-linux"
        ver="unknown"
      fi
      # Detect Windows host version
      local _winver; _winver="$(cmd.exe /c ver 2>/dev/null | tr -d '\r' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
      if [[ -n "$_winver" ]]; then
        local _build; _build="$(echo "$_winver" | cut -d. -f3)"
        [[ "${_build:-0}" -ge 22000 ]] && pm="${pm}@windows-11" || pm="${pm}@windows-10"
      fi
      ;;
    linux)
      if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        os="${ID:-linux}"
        ver="${VERSION_ID:-unknown}"
      else
        os="linux"
        ver="unknown"
      fi
      ;;
    *) os="unknown"; ver="unknown" ;;
  esac
  printf '%s/%s/%s/%s' "$os" "$ver" "$arch" "$pm"
}

export HOST_FINGERPRINT="$(_build_host_fingerprint)"
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

# ============================================================
#  UIC gate condition functions (read-only, no side effects)
# ============================================================
_gate_supported_platform(){ [[ "$HOST_PLATFORM_VARIANT" == "macos" || "$HOST_PLATFORM_VARIANT" == "linux" || "$HOST_PLATFORM_VARIANT" == "wsl2" ]]; }

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
  for platform in ${supported[@]+"${supported[@]}"}; do
    [[ "$platform" == "${HOST_PLATFORM_VARIANT:-unknown}" ]] && return 0
    [[ "$platform" == "$HOST_PLATFORM" ]] && return 0
    [[ "$HOST_PLATFORM" == "wsl" && "$platform" == "linux" ]] && return 0
  done
  return 1
}

_uic_scope_active() {
  local scope="$1" comp config
  case "$scope" in
    global|target:*) return 0 ;;
    component:*)
      comp="${scope#component:}"
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


# Helper: update user-local selection overrides (~/.ai-stack/selection.yaml)
# enable: adds to enabled: list (overrides defaults disabled)
# disable: adds to disabled: list (adds to defaults disabled)
_USER_SELECTION_FILE="${UIC_PREF_FILE%/*}/selection.yaml"
_selection_override_set() {
  local target="$1" action="$2"  # action: enable|disable
  local _sel_file="${_USER_SELECTION_FILE:-$HOME/.ai-stack/selection.yaml}"
  mkdir -p "$(dirname "$_sel_file")"
  python3 -c "
import yaml, sys, os
path, target, action = sys.argv[1], sys.argv[2], sys.argv[3]
if os.path.exists(path):
    with open(path) as f:
        data = yaml.safe_load(f) or {}
else:
    data = {}
enabled = data.get('enabled') or []
disabled = data.get('disabled') or []
if action == 'enable':
    if target not in enabled: enabled.append(target)
    if target in disabled: disabled.remove(target)
elif action == 'disable':
    if target not in disabled: disabled.append(target)
    if target in enabled: enabled.remove(target)
data['enabled'] = enabled
data['disabled'] = disabled
with open(path, 'w') as f:
    yaml.dump(data, f, default_flow_style=False, sort_keys=False)
" "$_sel_file" "$target" "$action" 2>/dev/null
}

usage() {
  cat <<EOF

Usage: $0 [options] [component|target ...]

Without arguments, uses default-selection preference (all or none).
Pass a component name to run that component.
Pass a target name (not a component) to run only that target.

Options:
  --mode install    Install missing components (default)
  --mode update     Update already-installed components
  --all             Select all components and targets
  --none            Select nothing (show current state only)
  --mode check      Observe current state without changing anything (drift detection)
  --dry-run         Show what would change without applying it
  --interactive     Prompt for preferences and confirm each change
  --no-interactive  Skip all prompts (CI/automation mode)
  --preflight       Evaluate UIC gates and preferences; do NOT converge
  --pref key=value  Set a UIC preference for this run only (repeatable)
  --show-overrides  Print user overrides (UCC_OVERRIDE__* env + target-overrides.yaml) and exit
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
export UCC_TARGET_SET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)       export UCC_DRY_RUN=1;     shift ;;
    --mode)          export UCC_MODE="$2";    shift 2 ;;
    --interactive)   export UCC_INTERACTIVE=1; shift ;;
    --no-interactive) export UCC_INTERACTIVE=0; shift ;;
    --all)           export UCC_DEFAULT_SELECTION=all;  shift ;;
    --none)          export UCC_DEFAULT_SELECTION=none; shift ;;
    --debug)         export UCC_DEBUG=1;      shift ;;
    --preflight)     export UIC_PREFLIGHT=1;  shift ;;
    --show-overrides)
      # Print effective user overrides (env + overlay) and exit.
      # Sources lib so the helpers are available without running the full pipeline.
      # shellcheck disable=SC1091
      source "$(dirname "$0")/lib/ucc_targets.sh" 2>/dev/null || true
      printf '%-8s  %-40s  %-30s  %s\n' SOURCE TARGET KEY VALUE
      _ucc_user_override_list 2>/dev/null \
        | awk -F'\t' '{printf "%-8s  %-40s  %-30s  %s\n", $1, $2, $3, $4}'
      exit 0
      ;;
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

# --- Interactive mode resolution (after arg parsing so --no-interactive works) ---
if [[ -z "${UCC_INTERACTIVE:-}" ]]; then
  _saved_interactive=""
  _pf="${UIC_PREF_FILE:-$HOME/.ai-stack/preferences.env}"
  if [[ -f "$_pf" ]]; then _saved_interactive="$(grep -E '^interactive=' "$_pf" 2>/dev/null | head -1 | cut -d= -f2- || true)"; fi
  if [[ "$_saved_interactive" == "no" ]]; then
    export UCC_INTERACTIVE=0
  elif [[ "$_saved_interactive" == "yes" ]]; then
    export UCC_INTERACTIVE=1
  elif [[ -c /dev/tty ]]; then
    printf '\n  [?] Run in interactive mode? (*1=yes, 2=no) → '
    read -r _im_choice < /dev/tty
    [[ "$_im_choice" == "2" ]] && export UCC_INTERACTIVE=0 || export UCC_INTERACTIVE=1
  else
    export UCC_INTERACTIVE=0
  fi
fi

# ── Resolve positional args into a target set and component list ──
source "${DIR}/lib/ucc_selection.sh"

_UCC_SELECTION_FILE="${UIC_PREF_FILE%/*}/selection.env"

# Load defaults/selection.yaml defaults
_SELECTION_POLICY="$DIR/defaults/selection.yaml"
_POLICY_DEFAULT="all"
_POLICY_DISABLED=""
if [[ -f "$_SELECTION_POLICY" ]]; then
  _POLICY_DEFAULT="$(python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    d = yaml.safe_load(f) or {}
print(d.get('default', 'all'))
" "$_SELECTION_POLICY" 2>/dev/null || echo all)"
  _POLICY_DISABLED="$(python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    d = yaml.safe_load(f) or {}
for t in (d.get('disabled') or []):
    print(t)
" "$_SELECTION_POLICY" 2>/dev/null || true)"
fi

_resolved=()
if [[ "${UCC_DEFAULT_SELECTION:-}" == "all" ]]; then
  # --all flag
  for _c in "${COMPONENTS[@]}"; do _resolve_component "$_c"; done
elif [[ "${UCC_DEFAULT_SELECTION:-}" == "none" ]]; then
  # --none flag: nothing selected
  :
elif [[ ${#TO_RUN[@]} -gt 0 ]]; then
  # Explicit args: resolve those
  _EXPLICIT_TARGETS=1
  _resolve_selection "${TO_RUN[@]}"
elif [[ -f "$_UCC_SELECTION_FILE" ]]; then
  # No args: load saved user selection
  _saved_items=()
  while IFS= read -r _line; do
    [[ -n "$_line" && "$_line" != \#* ]] && _saved_items+=("$_line")
  done < "$_UCC_SELECTION_FILE"
  if [[ ${#_saved_items[@]} -gt 0 ]]; then
    log_info "Loaded selection from $_UCC_SELECTION_FILE"
    _resolve_selection "${_saved_items[@]}"
  fi
else
  # No args, no user selection → use policy default
  _default_sel="${UIC_PREF_DEFAULT_SELECTION:-$_POLICY_DEFAULT}"
  # Also check user pref file
  _pf="${UIC_PREF_FILE:-$HOME/.ai-stack/preferences.env}"
  if [[ -f "$_pf" ]]; then
    _user_default="$(grep -E '^default-selection=' "$_pf" 2>/dev/null | head -1 | cut -d= -f2- || true)"
    if [[ -n "$_user_default" ]]; then _default_sel="$_user_default"; fi
  fi
  if [[ "$_default_sel" == "all" ]]; then
    for _c in "${COMPONENTS[@]}"; do _resolve_component "$_c"; done
  fi
fi

# Build effective disabled list: (defaults.disabled + user.disabled) - user.enabled
_USER_ENABLED=""
_USER_DISABLED=""
if [[ -f "$_USER_SELECTION_FILE" ]]; then
  _USER_ENABLED="$(python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    d = yaml.safe_load(f) or {}
for t in (d.get('enabled') or []):
    print(t)
" "$_USER_SELECTION_FILE" 2>/dev/null || true)"
  _USER_DISABLED="$(python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    d = yaml.safe_load(f) or {}
for t in (d.get('disabled') or []):
    print(t)
" "$_USER_SELECTION_FILE" 2>/dev/null || true)"
fi

# Merge: start with defaults disabled, add user disabled, subtract user enabled
export UCC_DISABLED_TARGETS=""
_all_disabled="${_POLICY_DISABLED}
${_USER_DISABLED}"
_user_enabled_set="|"
if [[ -n "$_USER_ENABLED" ]]; then
  while IFS= read -r _ue; do
    [[ -n "$_ue" ]] && _user_enabled_set="${_user_enabled_set}${_ue}|"
  done <<< "$_USER_ENABLED"
fi
while IFS= read -r _dt; do
  [[ -z "$_dt" ]] && continue
  # Skip if user explicitly enabled this target
  if [[ "$_user_enabled_set" == *"|${_dt}|"* ]]; then continue; fi
  # Avoid duplicates
  if [[ "${UCC_DISABLED_TARGETS}" == *"${_dt}|"* ]]; then continue; fi
  UCC_DISABLED_TARGETS="${UCC_DISABLED_TARGETS}${_dt}|"
done <<< "$_all_disabled"

# Load per-target preferred-driver ignore list (~/.ai-stack/target-overrides.yaml)
export UCC_PREFERRED_DRIVER_IGNORED="|"
_OVERRIDES_FILE="${UIC_PREF_FILE%/*}/target-overrides.yaml"
if [[ -f "$_OVERRIDES_FILE" ]]; then
  while IFS= read -r _line; do
    [[ -n "$_line" ]] && UCC_PREFERRED_DRIVER_IGNORED="${UCC_PREFERRED_DRIVER_IGNORED}${_line}|"
  done < <(python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    d = yaml.safe_load(f) or {}
for t in (d.get('preferred-driver-ignore') or []):
    print(t)
" "$_OVERRIDES_FILE" 2>/dev/null || true)
fi

# For explicit CLI targets in interactive mode, prompt enable/disable and persist
if [[ "${_EXPLICIT_TARGETS:-0}" == "1" && "${UCC_INTERACTIVE:-0}" == "1" && -c /dev/tty ]]; then
  for _et in "${TO_RUN[@]}"; do
    # Only prompt for actual targets, not components
    python3 "$_QUERY_SCRIPT" --find-target "$_et" "$_MANIFEST_DIR" >/dev/null 2>&1 || continue
    _is_disabled=0
    [[ "${UCC_DISABLED_TARGETS}" == *"${_et}|"* ]] && _is_disabled=1
    if [[ $_is_disabled -eq 1 ]]; then
      printf '\n  [?] Target '\''%s'\'' is currently disabled.\n' "$_et"
      printf '      Options: *1=enable, 2=keep disabled  →  '
    else
      printf '\n  [?] Target '\''%s'\'' is currently enabled.\n' "$_et"
      printf '      Options: *1=keep enabled, 2=disable  →  '
    fi
    read -r _td_choice < /dev/tty
    if [[ $_is_disabled -eq 1 ]]; then
      if [[ "$_td_choice" != "2" ]]; then
        _selection_override_set "$_et" enable
        UCC_DISABLED_TARGETS="${UCC_DISABLED_TARGETS//${_et}|/}"
        log_info "Enabled '$_et' — updated ~/.ai-stack/selection.yaml"
      fi
    else
      if [[ "$_td_choice" == "2" ]]; then
        _selection_override_set "$_et" disable
        UCC_DISABLED_TARGETS="${UCC_DISABLED_TARGETS}${_et}|"
        log_info "Disabled '$_et' — updated ~/.ai-stack/selection.yaml"
      fi
    fi
  done
fi

# Save selected components for preference scoping
export UCC_SELECTED_COMPS=""
for _c in "${_resolved[@]+"${_resolved[@]}"}"; do
  UCC_SELECTED_COMPS="${UCC_SELECTED_COMPS}${_c}|"
done

# Always add all components — targets filter via UCC_TARGET_SET,
# unselected targets show as [skip] with current state
for _c in "${COMPONENTS[@]}"; do _resolved+=("$_c"); done

# Deduplicate components while preserving order
_deduped=(); _seen_comps=""
for _c in "${_resolved[@]+"${_resolved[@]}"}"; do
  [[ "$_seen_comps" == *"|${_c}|"* ]] && continue
  _seen_comps="${_seen_comps}|${_c}|"
  _deduped+=("$_c")
done
TO_RUN=("${_deduped[@]+"${_deduped[@]}"}")
export UCC_TARGET_SET
export UCC_EXPLICIT_TARGETS="${_EXPLICIT_TARGETS:-0}"

# Validate mode
[[ "$UCC_MODE" =~ ^(install|update|check)$ ]] || log_error "Invalid --mode: $UCC_MODE (must be install, update, or check)"
# check mode is observe-only — equivalent to dry-run
[[ "$UCC_MODE" == "check" ]] && export UCC_DRY_RUN=1

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

# --- Interactive: component/target selection (before prefs) ----
source "${DIR}/lib/ucc_interactive.sh"
if [[ "${UCC_INTERACTIVE:-0}" == "1" && -c /dev/tty && -z "$UCC_TARGET_SET" ]]; then
  _interactive_browse
  # Update selected components for preference scoping
  UCC_SELECTED_COMPS=""
  for _c in "${_resolved[@]+"${_resolved[@]}"}"; do
    UCC_SELECTED_COMPS="${UCC_SELECTED_COMPS}${_c}|"
  done
  export UCC_SELECTED_COMPS

  # Save selection prompt (right after selection, before preferences)
  if [[ -n "${_selection:-}${UCC_TARGET_SET}" ]]; then
    printf '\n  [?] Save this selection for future runs?\n'
    printf '      Options: 1=yes, *2=no  →  '
    read -r _save_sel < /dev/tty
    if [[ "$_save_sel" == "1" ]]; then
      mkdir -p "$(dirname "$_UCC_SELECTION_FILE")"
      printf '# Saved selection\n' > "$_UCC_SELECTION_FILE"
      if [[ "${_selection:-}" == "a" || "${_selection:-}" == "all" ]]; then
        for _c in "${COMPONENTS[@]}"; do echo "$_c" >> "$_UCC_SELECTION_FILE"; done
      else
        # Save individual targets/components from the set
        echo "$UCC_TARGET_SET" | tr '|' '\n' | while read _t; do
          [[ -n "$_t" ]] && echo "$_t"
        done >> "$_UCC_SELECTION_FILE"
      fi
      log_info "Selection saved to $_UCC_SELECTION_FILE"
    fi
  fi
fi

# --- Gates --------------------------------------------------
load_uic_gates "$DIR"

# --- Preferences (only for selected components) ---------------
load_uic_preferences "$DIR"

# --- Resolve (evaluate gates, report preferences) -----------
_UIC_RC=0
uic_resolve || _UIC_RC=$?
uic_export

# --- Interactive: save preferences + interactive mode to file ---
if [[ "${UCC_INTERACTIVE:-0}" == "1" ]] && [[ -c /dev/tty ]]; then
  _pref_file="${UIC_PREF_FILE:-$HOME/.ai-stack/preferences.env}"

  # Save pinned preferences (explicitly chosen by user or loaded from file/env)
  _pinned_count=0
  for _i in "${!_UIC_PREF_PINNED[@]}"; do
    [[ "${_UIC_PREF_PINNED[$_i]}" == "1" ]] && _pinned_count=$((_pinned_count + 1))
  done

  if [[ $_pinned_count -gt 0 ]]; then
    echo ""
    echo "  Locked preferences:"
    mkdir -p "$(dirname "$_pref_file")"
    printf '# User preferences (locked choices)\n' > "$_pref_file"
    for _i in "${!_UIC_PREF_NAMES[@]}"; do
      if [[ "${_UIC_PREF_PINNED[$_i]}" == "1" ]]; then
        _label=""
        if [[ "${_UIC_PREF_VALUES[$_i]}" == "${_UIC_PREF_DEFAULTS[$_i]}" ]]; then
          _label="(locked to default)"
        else
          _label="(non-default)"
        fi
        printf '    %-28s %s %s\n' "${_UIC_PREF_NAMES[$_i]}" "${_UIC_PREF_VALUES[$_i]}" "$_label"
        printf '%s=%s\n' "${_UIC_PREF_NAMES[$_i]}" "${_UIC_PREF_VALUES[$_i]}" >> "$_pref_file"
      fi
    done
    log_info "Saved to $_pref_file"
  fi
fi

# --- Interactive: sudo acquisition ---------------------------
if [[ "${UCC_INTERACTIVE:-0}" == "1" ]] && [[ -c /dev/tty ]]; then
  if sudo_not_available; then
    # List targets that need admin
    echo ""
    echo "  Targets requiring admin privileges:"
    python3 -c "
import yaml, os
for root, _, files in os.walk('$_MANIFEST_DIR'):
    for f in files:
        if not f.endswith('.yaml'): continue
        with open(os.path.join(root, f)) as fh:
            data = yaml.safe_load(fh) or {}
        for t, td in (data.get('targets') or {}).items():
            if isinstance(td, dict) and td.get('admin_required'):
                print(f'    - {td.get(\"display_name\", t)}')
" 2>/dev/null
    printf '\n  [?] Acquire sudo now?\n'
    printf '      Options: 1=yes, *2=no  →  '
    read -r _sudo_answer < /dev/tty
    if [[ "$_sudo_answer" == "1" ]]; then
      sudo -v
    fi
  fi
fi

# --- Sudo detection -------------------------------------------
# sudo -n true inside $() subshells (where ucc_target captures
# observe output) loses the tty-bound ticket on macOS. Detect once
# here (in the main shell, with tty access) and export the result
# so sudo_is_available can check the flag without re-probing.
#
# Keepalive: sudo -v in a background subshell can't refresh the
# ticket (subshells lose tty context on macOS). Instead, we refresh
# the ticket inline before each component via _ucc_sudo_refresh.
if sudo -n true 2>/dev/null; then
  export _UCC_SUDO_AVAILABLE=1
else
  export _UCC_SUDO_AVAILABLE=0
fi

_ucc_sudo_refresh() {
  [[ "${_UCC_SUDO_AVAILABLE:-0}" == "1" ]] || return 0
  # sudo -v in the main shell (foreground, with tty) refreshes the ticket.
  # If the ticket expired and can't be renewed, clear the flag so
  # admin_required targets get [policy] instead of [fail].
  if ! sudo -v -n 2>/dev/null; then
    export _UCC_SUDO_AVAILABLE=0
  fi
}

# Warm Brew caches before any component runs. Version caches are needed in all
# modes; outdated caches are only useful when upgrades are enabled.
if command -v brew &>/dev/null; then
  if [[ "${UIC_PREF_TOOL_UPDATE:-always-upgrade}" == "always-upgrade" ]]; then
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

source "${DIR}/lib/ucc_display.sh"

_component_has_selected_targets() {
  local comp="$1" _t
  while IFS= read -r _t; do
    [[ -z "$_t" ]] && continue
    [[ "${UCC_TARGET_SET:-}" == *"${_t}|"* ]] && return 0
  done < <(python3 "$_QUERY_SCRIPT" --ordered-targets "$comp" "$_MANIFEST_DIR" 2>/dev/null)
  return 1
}

_print_component_header() {
  local comp="$1"
  # Fast mode: skip header if no targets in this component are selected
  if [[ "${UIC_PREF_SKIP_DISPLAY_MODE:-full}" == "fast" ]] \
    && [[ -n "${UCC_TARGET_SET:-}" ]] \
    && ! _component_has_selected_targets "$comp"; then
    return 0
  fi
  printf '  [%s]\n' "$(_display_component_name "$comp")"
}

# Pre-collect dispatch info for all components (one query per component)
_DISP_LIBS=()
_DISP_RUNNERS=()
_DISP_ON_FAILS=()
_DISP_CONFIGS=()

for comp in "${TO_RUN[@]}"; do
  if [[ "$comp" == "verify" ]]; then
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
  state_model observe_success observe_failure driver.probe \
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
  driver.plist driver.bin driver.process driver.path_env \
  driver.src_path driver.link_relpath driver.cmd driver.hint \
  driver.install_url driver.install_dir driver.install_args driver.upgrade_script \
  driver.config_file driver.bin_dir driver.shell_profile \
  driver.script_name driver.formula driver.launchd_dir driver.nvm_dir \
  driver.apt_ref driver.dnf_ref driver.pacman_ref \
  driver.version_cmd driver.github_repo driver.fallback_install_url \
  driver.fallback_install_args driver.update_cmd driver.externally_managed_updates \
  driver.repo driver.dest driver.branch requires"
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
    # Count targets in the blocked component and record them as skipped
    local _skip_count
    _skip_count=$(python3 "$_QUERY_SCRIPT" --ordered-targets "$comp" "$_MANIFEST_DIR" 2>/dev/null | wc -l)
    _skip_count=$(( _skip_count + 0 ))  # ensure numeric
    [[ -n "${UCC_SUMMARY_FILE:-}" && $_skip_count -gt 0 ]] && \
      printf '%s|%d|%d|%d|%d\n' "$comp" 0 0 0 "$_skip_count" >> "$UCC_SUMMARY_FILE" 2>/dev/null || true
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
  # Refresh sudo ticket before component execution. bash -c loses tty
  # context, so sudo -n inside the child can't see the parent's ticket.
  # sudo -v here (in the main shell with tty) renews it just in time.
  _ucc_sudo_refresh
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
      # Skip verification when nothing was selected
      if [[ -z "${UCC_TARGET_SET:-}" ]]; then
        log_info "Skipping $(_display_component_name "$comp") (no targets selected)"
        continue
      fi
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
