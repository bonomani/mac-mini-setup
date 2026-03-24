#!/usr/bin/env bash
# lib/ucc_asm.sh — JSON state helpers, ASM state model, and profile loading
# Sourced by lib/ucc.sh

# ── JSON helpers ─────────────────────────────────────────────────────────────

_ucc_jstr() { printf '%s' "$*" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

_ucc_now_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "1970-01-01T00:00:00Z"
}

_ucc_target_id() {
  printf '%s' "$1" | tr -cs '[:alnum:]' '-' | sed 's/^-*//; s/-*$//' | tr '[:upper:]' '[:lower:]'
}

_ucc_is_json_obj() {
  python3 - "$1" <<'PY' 2>/dev/null
import json, sys
try:
    value = json.loads(sys.argv[1])
    sys.exit(0 if isinstance(value, dict) else 1)
except Exception:
    sys.exit(1)
PY
}

_ucc_state_obj() {
  if _ucc_is_json_obj "$1"; then
    printf '%s' "$1"
  else
    printf '{"state":"%s"}' "$(_ucc_jstr "$1")"
  fi
}

_ucc_diff_obj() {
  local before="$1" after="$2" axes="${3:-}"
  if _ucc_is_json_obj "$before" || _ucc_is_json_obj "$after"; then
    if _ucc_json_equal "$before" "$after" "$axes"; then
      printf '{}'
    else
      printf '{"before":%s,"after":%s}' "$(_ucc_state_obj "$before")" "$(_ucc_state_obj "$after")"
    fi
  else
    if [[ "$before" == "$after" ]]; then
      printf '{}'
    else
      printf '{"state":{"before":"%s","after":"%s"}}' \
        "$(_ucc_jstr "$before")" "$(_ucc_jstr "$after")"
    fi
  fi
}

_ucc_json_equal() {
  python3 - "$1" "$2" "${3:-}" <<'PY' 2>/dev/null
import json, sys
try:
    left = json.loads(sys.argv[1])
    right = json.loads(sys.argv[2])
    axes = [a for a in sys.argv[3].split(",") if a] if len(sys.argv) > 3 and sys.argv[3] else []
    if axes:
        left = {k: left.get(k) for k in axes}
        right = {k: right.get(k) for k in axes}
    sys.exit(0 if left == right else 1)
except Exception:
    sys.exit(1)
PY
}

_ucc_display_state() {
  local axes="${2:-}"
  if _ucc_is_json_obj "$1"; then
    python3 - "$1" "$axes" <<'PY' 2>/dev/null
import json, sys
state = json.loads(sys.argv[1])
axes = [a for a in sys.argv[2].split(",") if a] if len(sys.argv) > 2 and sys.argv[2] else []
fields = []
keys = axes or ("installation_state", "runtime_state", "health_state", "admin_state", "dependency_state")
for key in keys:
    value = state.get(key)
    if value:
        fields.append(f"{key}={value}")
print(" ".join(fields) if fields else json.dumps(state, separators=(",", ":")))
PY
  else
    printf '%s' "$1"
  fi
}

_ucc_evidence_text() {
  local observed="$1" axes="${2:-}" evidence_fn="${3:-}" evidence=""
  if [[ -n "$evidence_fn" ]]; then
    evidence=$($evidence_fn 2>/dev/null || true)
  fi
  if [[ -n "$evidence" ]]; then
    printf '%s' "$evidence"
    return 0
  fi
  printf 'observed=%s' "$(_ucc_display_state "$observed" "$axes")"
}

_ucc_dependency_evidence() {
  local target="$1" deps="" dep status pairs=()
  [[ -n "${UCC_TARGETS_MANIFEST:-}" && -n "${UCC_TARGETS_QUERY_SCRIPT:-}" && -n "${UCC_TARGET_STATUS_FILE:-}" ]] || return 0
  [[ -e "${UCC_TARGETS_MANIFEST}" && -f "${UCC_TARGETS_QUERY_SCRIPT}" ]] || return 0
  deps=$(python3 "$UCC_TARGETS_QUERY_SCRIPT" --deps "$target" "$UCC_TARGETS_MANIFEST" 2>/dev/null || true)
  [[ -n "$deps" ]] || return 0
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    status=$(awk -F'|' -v dep="$dep" '$1==dep {val=$2} END {print val}' "$UCC_TARGET_STATUS_FILE" 2>/dev/null || true)
    [[ -z "$status" ]] && status="unknown"
    pairs+=("${dep}=${status}")
  done <<< "$deps"
  [[ ${#pairs[@]} -gt 0 ]] && printf 'deps: %s' "$(IFS=', '; echo "${pairs[*]}")"
}

_ucc_soft_dependency_evidence() {
  local target="$1" deps="" dep status pairs=() gate gate_key
  [[ -n "${UCC_TARGETS_MANIFEST:-}" && -n "${UCC_TARGETS_QUERY_SCRIPT:-}" ]] || return 0
  [[ -e "${UCC_TARGETS_MANIFEST}" && -f "${UCC_TARGETS_QUERY_SCRIPT}" ]] || return 0
  deps=$(python3 "$UCC_TARGETS_QUERY_SCRIPT" --soft-deps "$target" "$UCC_TARGETS_MANIFEST" 2>/dev/null || true)
  [[ -n "$deps" ]] || return 0
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    if [[ "$dep" == gate:* ]]; then
      gate="${dep#gate:}"
      gate_key="UIC_GATE_FAILED_$(echo "${gate//-/_}" | tr '[:lower:]' '[:upper:]')"
      if [[ "${!gate_key:-0}" == "1" ]]; then
        status="warn"
      else
        status="ok"
      fi
      pairs+=("${gate}=${status}")
    else
      status=$(awk -F'|' -v dep="$dep" '$1==dep {val=$2} END {print val}' "$UCC_TARGET_STATUS_FILE" 2>/dev/null || true)
      [[ -z "$status" ]] && status="unknown"
      pairs+=("${dep}=${status}")
    fi
  done <<< "$deps"
  [[ ${#pairs[@]} -gt 0 ]] && printf 'soft_deps: %s' "$(IFS=', '; echo "${pairs[*]}")"
}

_ucc_compose_evidence() {
  local target="$1" observed="$2" axes="$3" evidence_fn="$4" primary deps soft_deps
  primary="$(_ucc_evidence_text "$observed" "$axes" "$evidence_fn")"
  deps="$(_ucc_dependency_evidence "$target")"
  soft_deps="$(_ucc_soft_dependency_evidence "$target")"
  if [[ -n "$primary" ]]; then
    printf '%s' "$primary"
    [[ -n "$deps" ]] && printf '  %s' "$deps"
    [[ -n "$soft_deps" ]] && printf '  %s' "$soft_deps"
  elif [[ -n "$deps" || -n "$soft_deps" ]]; then
    [[ -n "$deps" ]] && printf '%s' "$deps"
    [[ -n "$soft_deps" ]] && printf '%s%s' "${deps:+  }" "$soft_deps"
  else
    printf '%s' "$primary"
  fi
}

# ── ASM state model ───────────────────────────────────────────────────────────

ucc_asm_state() {
  local installation="" runtime="" health="" admin="" dependency="" config_value=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --installation)  installation="$2";  shift 2 ;;
      --runtime)       runtime="$2";       shift 2 ;;
      --health)        health="$2";        shift 2 ;;
      --admin)         admin="$2";         shift 2 ;;
      --dependencies)  dependency="$2";    shift 2 ;;
      --config-value)  config_value="$2";  shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -n "$config_value" ]]; then
    printf '{"installation_state":"%s","runtime_state":"%s","health_state":"%s","admin_state":"%s","dependency_state":"%s","config_value":"%s"}' \
      "$(_ucc_jstr "$installation")" \
      "$(_ucc_jstr "$runtime")" \
      "$(_ucc_jstr "$health")" \
      "$(_ucc_jstr "$admin")" \
      "$(_ucc_jstr "$dependency")" \
      "$(_ucc_jstr "$config_value")"
  else
    printf '{"installation_state":"%s","runtime_state":"%s","health_state":"%s","admin_state":"%s","dependency_state":"%s"}' \
      "$(_ucc_jstr "$installation")" \
      "$(_ucc_jstr "$runtime")" \
      "$(_ucc_jstr "$health")" \
      "$(_ucc_jstr "$admin")" \
      "$(_ucc_jstr "$dependency")"
  fi
}

ucc_asm_package_state() {
  case "$1" in
    absent)
      ucc_asm_state --installation Absent --runtime NeverStarted --health Unknown --admin Enabled --dependencies DepsUnknown
      ;;
    outdated)
      ucc_asm_state --installation Installed --runtime Stopped --health Degraded --admin Enabled --dependencies DepsReady
      ;;
    *)
      ucc_asm_state --installation Configured --runtime Stopped --health Healthy --admin Enabled --dependencies DepsReady
      ;;
  esac
}

# ucc_asm_config_state <raw-value> [<desired-value>]
# Parametric config state per ASM SOFTWARE-MODEL.md §3b.
# When a desired-value is supplied both observed and desired carry config_value,
# so convergence requires the value to match — not just installation=Configured.
# When no desired-value is supplied (presence-only check), config_value is omitted.
ucc_asm_config_state() {
  local raw="$1" desired_val="${2:-}"
  case "$raw" in
    absent|unset)
      ucc_asm_state --installation Installed --runtime NeverStarted --health Unknown --admin Enabled --dependencies DepsUnknown
      ;;
    needs-update|outdated)
      ucc_asm_state --installation Installed --runtime Stopped --health Degraded --admin Enabled --dependencies DepsReady
      ;;
    *)
      if [[ -n "$desired_val" ]]; then
        ucc_asm_state --installation Configured --runtime Stopped --health Healthy --admin Enabled --dependencies DepsReady \
          --config-value "$raw"
      else
        ucc_asm_state --installation Configured --runtime Stopped --health Healthy --admin Enabled --dependencies DepsReady
      fi
      ;;
  esac
}

# ucc_asm_config_desired <desired-value>
# Produce the desired parametric state for a config target.
# Always pairs with ucc_asm_config_state called with the same desired-value arg.
ucc_asm_config_desired() {
  ucc_asm_state --installation Configured --runtime Stopped --health Healthy --admin Enabled --dependencies DepsReady \
    --config-value "$1"
}

ucc_asm_service_state() {
  case "$1" in
    absent|stopped)
      ucc_asm_state --installation Configured --runtime Stopped --health Unavailable --admin Enabled --dependencies DepsReady
      ;;
    outdated)
      ucc_asm_state --installation Configured --runtime Running --health Degraded --admin Enabled --dependencies DepsReady
      ;;
    loaded|started|running)
      ucc_asm_state --installation Configured --runtime Running --health Healthy --admin Enabled --dependencies DepsReady
      ;;
    *)
      ucc_asm_state --installation Configured --runtime Running --health Healthy --admin Enabled --dependencies DepsReady
      ;;
  esac
}

# ── Profile loading ───────────────────────────────────────────────────────────

_UCC_PROFILE_IDS=()
_UCC_PROFILE_LABELS=()
_UCC_PROFILE_ALIASES=()
_UCC_PROFILE_AXES=()
_UCC_PROFILE_EXPECTED_TEXT=()
_UCC_PROFILE_INSTALLATION=()
_UCC_PROFILE_RUNTIME=()
_UCC_PROFILE_HEALTH=()
_UCC_PROFILE_ADMIN=()
_UCC_PROFILE_DEPENDENCIES=()

_ucc_load_profiles() {
  local profile_file="" line="" current_id="" current_label="" current_aliases="" current_axes="" current_expected="" current_installation="" current_runtime="" current_health="" current_admin="" current_dependencies=""
  profile_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/policy/profiles.yaml"
  [[ -f "$profile_file" ]] || return 0

  while IFS= read -r line; do
    case "$line" in
      "  - id: "*)
        if [[ -n "$current_id" ]]; then
          _UCC_PROFILE_IDS+=("$current_id")
          _UCC_PROFILE_LABELS+=("$current_label")
          _UCC_PROFILE_ALIASES+=("$current_aliases")
          _UCC_PROFILE_AXES+=("$current_axes")
          _UCC_PROFILE_EXPECTED_TEXT+=("$current_expected")
          _UCC_PROFILE_INSTALLATION+=("$current_installation")
          _UCC_PROFILE_RUNTIME+=("$current_runtime")
          _UCC_PROFILE_HEALTH+=("$current_health")
          _UCC_PROFILE_ADMIN+=("$current_admin")
          _UCC_PROFILE_DEPENDENCIES+=("$current_dependencies")
        fi
        current_id="${line#  - id: }"
        current_label=""
        current_aliases=""
        current_axes=""
        current_expected=""
        current_installation=""
        current_runtime=""
        current_health=""
        current_admin=""
        current_dependencies=""
        ;;
      "    label: "*)        current_label="${line#    label: }" ;;
      "    aliases: "*)      current_aliases="${line#    aliases: }" ;;
      "    axes: "*)         current_axes="${line#    axes: }" ;;
      "    expected_text: "*)current_expected="${line#    expected_text: }" ;;
      "    installation: "*) current_installation="${line#    installation: }" ;;
      "    runtime: "*)      current_runtime="${line#    runtime: }" ;;
      "    health: "*)       current_health="${line#    health: }" ;;
      "    admin: "*)        current_admin="${line#    admin: }" ;;
      "    dependencies: "*) current_dependencies="${line#    dependencies: }" ;;
    esac
  done < "$profile_file"

  if [[ -n "$current_id" ]]; then
    _UCC_PROFILE_IDS+=("$current_id")
    _UCC_PROFILE_LABELS+=("$current_label")
    _UCC_PROFILE_ALIASES+=("$current_aliases")
    _UCC_PROFILE_AXES+=("$current_axes")
    _UCC_PROFILE_EXPECTED_TEXT+=("$current_expected")
    _UCC_PROFILE_INSTALLATION+=("$current_installation")
    _UCC_PROFILE_RUNTIME+=("$current_runtime")
    _UCC_PROFILE_HEALTH+=("$current_health")
    _UCC_PROFILE_ADMIN+=("$current_admin")
    _UCC_PROFILE_DEPENDENCIES+=("$current_dependencies")
  fi
}

_ucc_load_profiles

_ucc_profile_index() {
  local profile="$1" i aliases alias
  for i in "${!_UCC_PROFILE_IDS[@]}"; do
    [[ "${_UCC_PROFILE_IDS[$i]}" == "$profile" ]] && { printf '%s' "$i"; return 0; }
    aliases="${_UCC_PROFILE_ALIASES[$i]}"
    IFS='|' read -r -a _ucc_alias_list <<< "$aliases"
    for alias in "${_ucc_alias_list[@]}"; do
      [[ -n "$alias" && "$alias" == "$profile" ]] && { printf '%s' "$i"; return 0; }
    done
  done
  printf ''
}

ucc_asm_presence_desired() {
  ucc_asm_state \
    --installation Configured \
    --runtime Stopped \
    --health Healthy \
    --admin Enabled \
    --dependencies DepsReady
}

ucc_asm_configured_desired() {
  ucc_asm_state \
    --installation Configured \
    --runtime Stopped \
    --health Healthy \
    --admin Enabled \
    --dependencies DepsReady
}

ucc_asm_runtime_desired() {
  ucc_asm_state \
    --installation Configured \
    --runtime Running \
    --health Healthy \
    --admin Enabled \
    --dependencies DepsReady
}

_ucc_profile_axes() {
  local idx
  idx="$(_ucc_profile_index "$1")"
  [[ -n "$idx" ]] && printf '%s' "${_UCC_PROFILE_AXES[$idx]}" || printf ''
}

_ucc_profile_desired() {
  local idx
  idx="$(_ucc_profile_index "$1")"
  [[ -n "$idx" ]] || { printf ''; return 0; }
  ucc_asm_state \
    --installation "${_UCC_PROFILE_INSTALLATION[$idx]}" \
    --runtime "${_UCC_PROFILE_RUNTIME[$idx]}" \
    --health "${_UCC_PROFILE_HEALTH[$idx]}" \
    --admin "${_UCC_PROFILE_ADMIN[$idx]}" \
    --dependencies "${_UCC_PROFILE_DEPENDENCIES[$idx]}"
}

ucc_profile_label() {
  local idx
  idx="$(_ucc_profile_index "${1:-configured}")"
  [[ -n "$idx" ]] && printf '%s' "${_UCC_PROFILE_LABELS[$idx]}" || printf 'Configured'
}

ucc_profile_expected_text() {
  local idx
  idx="$(_ucc_profile_index "$1")"
  [[ -n "$idx" ]] && printf '%s' "${_UCC_PROFILE_EXPECTED_TEXT[$idx]}" || printf ''
}

UCC_ASM_PRESENCE_AXES="$(_ucc_profile_axes presence)"
UCC_ASM_CONFIGURED_AXES="$(_ucc_profile_axes configured)"
UCC_ASM_RUNTIME_AXES="$(_ucc_profile_axes runtime)"

ucc_component_profile() {
  local component="$1" profile=""
  if [[ -n "${UCC_TARGETS_MANIFEST:-}" && -n "${UCC_TARGETS_QUERY_SCRIPT:-}" ]] \
      && [[ -e "${UCC_TARGETS_MANIFEST}" && -f "${UCC_TARGETS_QUERY_SCRIPT}" ]]; then
    profile=$(python3 "$UCC_TARGETS_QUERY_SCRIPT" --component-profile "$component" "$UCC_TARGETS_MANIFEST" 2>/dev/null || true)
  fi
  if [[ -n "$profile" ]]; then
    printf '%s' "$profile"
    return 0
  fi
  [[ "$component" == "verify" ]] && printf 'verification' || printf 'configured'
}

# ── Profile report helpers ────────────────────────────────────────────────────

_ucc_profile_report_path() {
  local profile="${1:-configured}"
  [[ -n "${UCC_PROFILE_REPORT_DIR:-}" ]] || return 1
  printf '%s/%s.report' "${UCC_PROFILE_REPORT_DIR%/}" "${profile}"
}

_ucc_emit_profile_line() {
  local profile="$1" line="$2" path=""
  printf '%s\n' "$line"
  path=$(_ucc_profile_report_path "$profile" 2>/dev/null || true)
  [[ -n "$path" ]] && printf '%s\n' "$line" >> "$path" 2>/dev/null || true
}

ucc_profile_note() {
  local profile="$1"; shift
  _ucc_emit_profile_line "$profile" "  $*"
}
