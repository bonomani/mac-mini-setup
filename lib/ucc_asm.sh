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
  printf '%s' "$1" | jq -e 'type == "object"' >/dev/null 2>&1
}

_ucc_json_equal() {
  local axes="${3:-}"
  if [[ -n "$axes" ]]; then
    printf '%s\n%s\n%s' "$1" "$2" "$axes" | jq -Rse '
      split("\n") |
      (.[0] | fromjson) as $l | (.[1] | fromjson) as $r |
      (.[2] | split(",") | map(select(length>0))) as $axes |
      ([$axes[] | {(.): $l[.]}] | add) == ([$axes[] | {(.): $r[.]}] | add)
    ' >/dev/null 2>&1
  else
    printf '%s\n%s' "$1" "$2" | jq -Rse 'split("\n")[0:2] | (.[0]|fromjson) == (.[1]|fromjson)' >/dev/null 2>&1
  fi
}

_ucc_display_state() {
  local axes="${2:-}"
  printf '%s\n%s' "$1" "$axes" | jq -Rse '
    split("\n") |
    (.[0] | try fromjson catch null) as $s |
    if ($s | type) != "object" then .[0]
    else
      (if .[1] != "" then .[1] | split(",") | map(select(length>0))
       else ["installation_state","runtime_state","health_state","admin_state","dependency_state","config_value"]
         | map(select($s[.] != null and $s[.] != ""))
       end) as $keys |
      if ($keys | length) == 0 then ($s | tojson)
      else $keys | map("\(.)=\($s[.])") | join(" ")
      end
    end
  ' -r 2>/dev/null || printf '%s' "$1"
}

if ! command -v jq >/dev/null 2>&1; then
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
    python3 - "$1" "$axes" <<'PY' 2>/dev/null || printf '%s' "$1"
import json, sys
try:
    state = json.loads(sys.argv[1])
    if not isinstance(state, dict):
        print(sys.argv[1], end="")
        sys.exit(0)
except Exception:
    print(sys.argv[1], end="")
    sys.exit(0)
axes = [a for a in sys.argv[2].split(",") if a] if len(sys.argv) > 2 and sys.argv[2] else []
fields = []
keys = axes or [k for k in ("installation_state", "runtime_state", "health_state", "admin_state", "dependency_state", "config_value") if k in state]
for key in keys:
    value = state.get(key)
    if value:
        fields.append(f"{key}={value}")
print(" ".join(fields) if fields else json.dumps(state, separators=(",", ":")), end="")
PY
  }
fi

if command -v jq >/dev/null 2>&1; then
  _ucc_state_obj() {
    printf '%s' "$1" | jq -c 'if type == "object" then . else {"state": .} end' 2>/dev/null \
      || printf '{"state":"%s"}' "$(_ucc_jstr "$1")"
  }
else
  _ucc_state_obj() {
    if _ucc_is_json_obj "$1"; then
      printf '%s' "$1"
    else
      printf '{"state":"%s"}' "$(_ucc_jstr "$1")"
    fi
  }
fi

if command -v jq >/dev/null 2>&1; then
  _ucc_diff_obj() {
    local before="$1" after="$2" axes="${3:-}"
    jq -cn \
      --arg before "$before" \
      --arg after  "$after"  \
      --arg axes   "$axes"   \
    '
      def is_obj: try (fromjson | type == "object") catch false;
      def to_state: . as $v | try ($v | fromjson) catch {"state": $v};
      def proj($ax): if ($ax | length) > 0
        then to_entries | map(select(.key | IN($ax[]))) | from_entries
        else . end;
      ($before | is_obj) as $bo |
      ($after  | is_obj) as $ao |
      ($axes | if . == "" then [] else split(",") | map(select(length>0)) end) as $ax |
      if ($bo or $ao) then
        ($before | to_state) as $b | ($after | to_state) as $a |
        if ($b | proj($ax)) == ($a | proj($ax)) then {}
        else {"before": $b, "after": $a}
        end
      else
        if $before == $after then {}
        else {"state": {"before": $before, "after": $after}}
        end
      end
    ' 2>/dev/null
  }
else
  _ucc_diff_obj() {
    local before="$1" after="$2" axes="${3:-}"
    local _bo _ao
    _ucc_is_json_obj "$before" && _bo=1 || _bo=0
    _ucc_is_json_obj "$after"  && _ao=1 || _ao=0
    if [[ $_bo -eq 1 || $_ao -eq 1 ]]; then
      if _ucc_json_equal "$before" "$after" "$axes"; then
        printf '{}'
      else
        local _bs _as
        [[ $_bo -eq 1 ]] && _bs="$before" || _bs="$(printf '{"state":"%s"}' "$(_ucc_jstr "$before")")"
        [[ $_ao -eq 1 ]] && _as="$after"  || _as="$(printf '{"state":"%s"}' "$(_ucc_jstr "$after")")"
        printf '{"before":%s,"after":%s}' "$_bs" "$_as"
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
fi

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

_ucc_deps_for_target() {
  local target="$1" cache_var="$2"
  local cache="${!cache_var:-}"
  if [[ -n "$cache" ]]; then
    printf '%s\n' "$cache" | awk -F'\t' -v t="$target" '$1==t{print $2; exit}' | tr ',' '\n'
  else
    python3 "$UCC_TARGETS_QUERY_SCRIPT" "$3" "$target" "$UCC_TARGETS_MANIFEST" 2>/dev/null || true
  fi
}

_ucc_dependency_evidence() {
  local target="$1" deps="" dep status pairs=()
  [[ "$target" == "system-composition" ]] && return 0
  [[ -n "${UCC_TARGETS_MANIFEST:-}" && -n "${UCC_TARGETS_QUERY_SCRIPT:-}" && -n "${UCC_TARGET_STATUS_FILE:-}" ]] || return 0
  [[ -e "${UCC_TARGETS_MANIFEST}" && -f "${UCC_TARGETS_QUERY_SCRIPT}" ]] || return 0
  deps=$(_ucc_deps_for_target "$target" "_UCC_ALL_DEPS_CACHE" "--deps")
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
  [[ -n "${UCC_TARGETS_MANIFEST:-}" && -n "${UCC_TARGETS_QUERY_SCRIPT:-}" && -n "${UCC_TARGET_STATUS_FILE:-}" ]] || return 0
  [[ -e "${UCC_TARGETS_MANIFEST}" && -f "${UCC_TARGETS_QUERY_SCRIPT}" ]] || return 0
  deps=$(_ucc_deps_for_target "$target" "_UCC_ALL_SOFT_DEPS_CACHE" "--soft-deps")
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
      # `outdated` = package is installed and works, but a newer version is
      # available. Distinct from `Degraded` (broken/drift) — surfaced as
      # `Outdated` so reviewers can tell upgrade-pending apart from real
      # degradation in the dry-run/real-run output.
      ucc_asm_state --installation Installed --runtime Stopped --health Outdated --admin Enabled --dependencies DepsReady
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
    needs-update)
      # Config drift — declared state and observed state diverge; action needed.
      ucc_asm_state --installation Installed --runtime Stopped --health Degraded --admin Enabled --dependencies DepsReady
      ;;
    outdated)
      # Newer version available, current still works — distinct from drift.
      ucc_asm_state --installation Installed --runtime Stopped --health Outdated --admin Enabled --dependencies DepsReady
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

_ucc_profile_flush() {
  [[ -n "$current_id" ]] || return 0
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
}

_ucc_load_profiles() {
  local profile_file="" line current_id="" current_label="" current_aliases="" current_axes="" current_expected="" current_installation="" current_runtime="" current_health="" current_admin="" current_dependencies=""
  profile_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/defaults/profiles.yaml"
  [[ -f "$profile_file" ]] || return 0

  while IFS= read -r line; do
    case "$line" in
      "  - id: "*)
        _ucc_profile_flush
        current_id="${line#  - id: }"
        current_label="" current_aliases="" current_axes="" current_expected=""
        current_installation="" current_runtime="" current_health="" current_admin="" current_dependencies=""
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

  _ucc_profile_flush
}

_ucc_load_profiles

_ucc_profile_index() {
  local profile="$1" i aliases alias _ucc_alias_list
  for i in "${!_UCC_PROFILE_IDS[@]}"; do
    [[ "${_UCC_PROFILE_IDS[$i]}" == "$profile" ]] && { printf '%s' "$i"; return 0; }
    aliases="${_UCC_PROFILE_ALIASES[$i]}"
    IFS='|' read -r -a _ucc_alias_list <<< "$aliases"
    for alias in "${_ucc_alias_list[@]}"; do
      [[ -n "$alias" && "$alias" == "$profile" ]] && { printf '%s' "$i"; return 0; }
    done
  done
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
  [[ -n "$idx" ]] && printf '%s' "${_UCC_PROFILE_AXES[$idx]}"
}

_ucc_profile_desired() {
  local idx
  idx="$(_ucc_profile_index "$1")"
  [[ -n "$idx" ]] || return 0
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
  [[ -n "$idx" ]] && printf '%s' "${_UCC_PROFILE_EXPECTED_TEXT[$idx]}"
}

UCC_ASM_CONFIGURED_AXES="$(_ucc_profile_axes configured)"
UCC_ASM_RUNTIME_AXES="$(_ucc_profile_axes runtime)"

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
