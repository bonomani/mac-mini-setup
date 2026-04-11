#!/usr/bin/env bash
# lib/ucc_targets.sh — Target lifecycle (ucc_target), convenience helpers, and summary
# Sourced by lib/ucc.sh

# ── YAML evidence executor ─────────────────────────────────────────────────────

# ucc_eval_evidence_from_yaml <cfg_dir> <yaml> <target>
# Execute evidence snippets declared in the target's YAML evidence: block.
# Outputs: key=value  key=value  (two-space separated, omits empty values)
# Top-level YAML scalar ${vars} are pre-substituted by read_config.py.
ucc_eval_evidence_from_yaml() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local _first=1 _key _cmd _val
  local fn="${target//[^a-zA-Z0-9]/_}"
  local _cached_var="_UCC_OBS_CACHED_${fn}"
  local _ev_var="_UCC_OBS_EVIDENCE_${fn}"

  if _ucc_driver_evidence "$cfg_dir" "$yaml" "$target"; then
    return
  fi

  while IFS=$'\t' read -r -d '' _key _cmd; do
    [[ -z "$_key" || -z "$_cmd" ]] && continue
    _val=$(_ucc_eval_yaml_expr "$cfg_dir" "$yaml" "$target" "$_cmd" 2>/dev/null || true)
    [[ -z "$_val" ]] && continue
    [[ $_first -eq 0 ]] && printf '  '
    printf '%s=%s' "$_key" "$_val"
    _first=0
  done < <(
    if [[ -n "${!_cached_var:-}" ]]; then
      [[ -n "${!_ev_var:-}" ]] && printf '%s' "${!_ev_var}" | base64 -d
    else
      python3 "$cfg_dir/tools/read_config.py" --evidence "$yaml" "$target" 2>/dev/null
    fi
  )
}

# _ucc_ytgt_source <cfg_dir> <yaml> <target> <keys...>
# Emits NUL-delimited scalar+evidence rows for <target>.
# Uses pre-loaded _UCC_YTGT_<yaml_fn>_<target_fn> (base64 -d) when available,
# falls back to python3 --target-get-many-with-evidence.
_ucc_ytgt_source() {
  local cfg_dir="$1" yaml="$2" target="$3"
  shift 3
  local yaml_fn="${yaml//[^a-zA-Z0-9]/_}"
  local target_fn="${target//[^a-zA-Z0-9]/_}"
  local cache_var="_UCC_YTGT_${yaml_fn}_${target_fn}"
  if [[ -n "${!cache_var:-}" ]]; then
    printf '%s' "${!cache_var}" | base64 -d
  else
    python3 "$cfg_dir/tools/read_config.py" --target-get-many-with-evidence "$yaml" "$target" "$@" 2>/dev/null || true
  fi
}

# ── User override layer (env + overlay file) ─────────────────────────────────
# Precedence (highest first): env var > overlay yaml > tracked yaml.
#
# This is the single per-target user overlay. Slot-in to the existing
# ~/.ai-stack/ layered model:
#   preferences.env       — UIC policies (KEY=value)
#   selection.yaml        — per-target run/skip selection
#   target-overrides.yaml — per-target field overrides (this layer) +
#                           per-target opt-outs (preferred-driver-ignore)
#
#  Env var format:  UCC_OVERRIDE__<TARGET>__<KEY>=<value>
#                   target: '-' → '_';  key: '.' → '_'
#  Example:         UCC_OVERRIDE__cli_opencode__driver_kind=brew
#
#  Overlay file:    $HOME/.ai-stack/target-overrides.yaml
#  Top-level key:   target-overrides
#  Shape:           target-overrides: { <target>: { driver: { kind: brew, ... } } }
_UCC_OVERLAY_CACHE_LOADED=0
_UCC_OVERLAY_CACHE=""

_ucc_overlay_load_once() {
  [[ "$_UCC_OVERLAY_CACHE_LOADED" == "1" ]] && return 0
  _UCC_OVERLAY_CACHE_LOADED=1
  local file="${UIC_PREF_FILE:-$HOME/.ai-stack/preferences.env}"
  file="${file%/*}/target-overrides.yaml"
  [[ -f "$file" ]] || return 0
  _UCC_OVERLAY_CACHE="$(python3 - "$file" 2>/dev/null <<'PY' || true
import sys, yaml
def flatten(prefix, node, out):
    if isinstance(node, dict):
        for k, v in node.items():
            key = f"{prefix}.{k}" if prefix else k
            flatten(key, v, out)
    else:
        out.append((prefix, node))
try:
    with open(sys.argv[1]) as f:
        data = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)
overrides = (data or {}).get('target-overrides') or {}
for target, fields in overrides.items():
    flat = []
    flatten("", fields or {}, flat)
    for k, v in flat:
        print(f"{target}\t{k}\t{v}")
PY
)"
}

# Echo override value for <target> <key>, return 0 if found.
_ucc_user_override_get() {
  local target="$1" key="$2"
  # 1. env var
  local env_target="${target//-/_}"
  local env_key="${key//./_}"
  local env_var="UCC_OVERRIDE__${env_target}__${env_key}"
  if [[ -n "${!env_var:-}" ]]; then
    printf '%s' "${!env_var}"
    return 0
  fi
  # 2. overlay file
  _ucc_overlay_load_once
  [[ -n "$_UCC_OVERLAY_CACHE" ]] || return 1
  local val
  val=$(printf '%s\n' "$_UCC_OVERLAY_CACHE" \
    | awk -F'\t' -v t="$target" -v k="$key" '$1==t && $2==k{print $3; exit}')
  [[ -n "$val" ]] || return 1
  printf '%s' "$val"
}

# List all known overrides as "<source>\t<target>\t<key>\t<value>" lines.
# Used by install.sh --show-overrides.
_ucc_user_override_list() {
  local v
  while IFS='=' read -r name v; do
    [[ "$name" == UCC_OVERRIDE__*__* ]] || continue
    local rest="${name#UCC_OVERRIDE__}"
    local t="${rest%%__*}"
    local k="${rest#*__}"
    printf 'env\t%s\t%s\t%s\n' "${t//_/-}" "${k//_/.}" "$v"
  done < <(env)
  _ucc_overlay_load_once
  [[ -n "$_UCC_OVERLAY_CACHE" ]] || return 0
  printf '%s\n' "$_UCC_OVERLAY_CACHE" | awk -F'\t' '{print "overlay\t"$0}'
}

_ucc_yaml_target_get() {
  local cfg_dir="$1" yaml="$2" target="$3" key="$4" default="${5:-}"
  # User override layer takes precedence over the tracked YAML.
  local override
  if override="$(_ucc_user_override_get "$target" "$key")" && [[ -n "$override" ]]; then
    printf '%s' "$override"
    return
  fi
  local yaml_fn="${yaml//[^a-zA-Z0-9]/_}"
  local target_fn="${target//[^a-zA-Z0-9]/_}"
  local cache_var="_UCC_YTGT_${yaml_fn}_${target_fn}"
  local val=""
  if [[ -n "${!cache_var:-}" ]]; then
    val="$(printf '%s' "${!cache_var}" | base64 -d | awk -v k="$key" -F'\t' 'BEGIN{RS="\0"} $1==k{print $2; exit}')"
  else
    val="$(python3 "$cfg_dir/tools/read_config.py" --target-get "$yaml" "$target" "$key" 2>/dev/null || true)"
  fi
  printf '%s' "${val:-$default}"
}

_ucc_yaml_target_get_many() {
  local cfg_dir="$1" yaml="$2" target="$3"
  shift 3
  python3 "$cfg_dir/tools/read_config.py" --target-get-many "$yaml" "$target" "$@" 2>/dev/null || true
}

_ucc_yaml_target_driver_get() {
  local cfg_dir="$1" yaml="$2" target="$3" key="$4" default="${5:-}" val=""
  local driver_key="driver.$key"
  while IFS=$'\t' read -r -d '' row_key row_value; do
    case "$row_key" in
      "$driver_key") val="$row_value" ;;
    esac
  done < <(_ucc_yaml_target_get_many "$cfg_dir" "$yaml" "$target" "$driver_key")
  printf '%s' "${val:-$default}"
}

_ucc_yaml_target_action_get() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4" val=""
  val="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "actions.$action")"
  if [[ -z "$val" && "$action" == "update" ]]; then
    val="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "actions.install")"
  fi
  printf '%s' "$val"
}

# _ucc_yaml_target_admin_required <cfg_dir> <yaml> <target> <action_key>
# Returns 0 (true) if admin is required for this specific action.
# admin_required values:
#   true / yes / 1        → required for all actions
#   install               → required for install only
#   update                → required for update only
#   install,update        → required for both (same as true)
_ucc_yaml_target_admin_required() {
  local cfg_dir="$1" yaml="$2" target="$3" action_key="${4:-}" val=""
  local yaml_fn="${yaml//[^a-zA-Z0-9]/_}"
  local target_fn="${target//[^a-zA-Z0-9]/_}"
  local cache_var="_UCC_YTGT_${yaml_fn}_${target_fn}"
  if [[ -n "${!cache_var:-}" ]]; then
    val=$(printf '%s' "${!cache_var}" | base64 -d \
      | awk -v k="admin_required" -F'\t' 'BEGIN{RS="\0"} $1==k{print $2; exit}')
  else
    val="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "admin_required")"
  fi
  [[ -n "$val" ]] || return 1
  # true/yes/1 → all actions
  [[ "$val" == "true" || "$val" == "1" || "$val" == "yes" ]] && return 0
  # named action(s) — comma-separated; match against current action_key
  [[ -n "$action_key" ]] || return 1
  local entry
  while IFS= read -r -d ',' entry; do
    entry="${entry// /}"
    [[ "$entry" == "$action_key" ]] && return 0
  done <<< "${val},"
  return 1
}

_ucc_eval_yaml_expr() {
  local cfg_dir="$1" yaml="$2" target="$3" expr="$4"
  local CFG_DIR="$cfg_dir" YAML_PATH="$yaml" TARGET_NAME="$target"
  eval "$expr"
}

_ucc_yaml_expr_succeeds() {
  local cfg_dir="$1" yaml="$2" target="$3" expr="$4"
  _ucc_eval_yaml_expr "$cfg_dir" "$yaml" "$target" "$expr" >/dev/null 2>&1
}

_ucc_eval_yaml_scalar_cmd() {
  local cfg_dir="$1" yaml="$2" target="$3" cmd="$4" output trimmed
  output="$(_ucc_eval_yaml_expr "$cfg_dir" "$yaml" "$target" "$cmd" 2>/dev/null || true)"
  output="${output%%$'\n'*}"
  trimmed="${output#"${output%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  printf '%s' "$trimmed"
}

_ucc_observed_prefers_update_action() {
  local observed="$1"
  [[ "$observed" == "outdated" || "$observed" == "needs-update" ]] && return 0
  _ucc_is_json_obj "$observed" || return 1
  [[ "$observed" == *'"runtime_state":"Stopped"'* ]] || return 1
  [[ "$observed" == *'"health_state":"Degraded"'* ]] || return 1
  if [[ "$observed" == *'"installation_state":"Installed"'* ]]; then
    return 0
  fi
  if [[ "$observed" == *'"installation_state":"Configured"'* && "$observed" == *'"config_value":'* ]]; then
    return 0
  fi
  return 1
}

# ── Convenience target helpers ────────────────────────────────────────────────

_UCC_DISPLAY_NAME_CACHE_KEYS=()
_UCC_DISPLAY_NAME_CACHE_VALUES=()
_UCC_DISPLAY_NAME_CACHE_LOADED=0

_ucc_display_name_load_cache() {
  [[ $_UCC_DISPLAY_NAME_CACHE_LOADED -eq 1 ]] && return
  _UCC_DISPLAY_NAME_CACHE_LOADED=1
  [[ -z "${_UCC_ALL_DISPLAY_NAMES_CACHE:-}" ]] && return
  while IFS=$'\t' read -r key value; do
    [[ -n "$key" ]] || continue
    # Append target name when display name differs
    if [[ -n "$value" && "$value" != "$key" ]]; then
      value="${value} (${key})"
    fi
    _UCC_DISPLAY_NAME_CACHE_KEYS+=("$key")
    _UCC_DISPLAY_NAME_CACHE_VALUES+=("$value")
  done <<< "$_UCC_ALL_DISPLAY_NAMES_CACHE"
}

_ucc_display_name() {
  local target="$1" idx display_name="$1"
  _ucc_display_name_load_cache
  for idx in "${!_UCC_DISPLAY_NAME_CACHE_KEYS[@]}"; do
    if [[ "${_UCC_DISPLAY_NAME_CACHE_KEYS[$idx]}" == "$target" ]]; then
      printf '%s' "${_UCC_DISPLAY_NAME_CACHE_VALUES[$idx]}"
      return
    fi
  done

  if [[ -n "${UCC_TARGETS_MANIFEST:-}" && -n "${UCC_TARGETS_QUERY_SCRIPT:-}" ]]; then
    if [[ -e "${UCC_TARGETS_MANIFEST}" && -f "${UCC_TARGETS_QUERY_SCRIPT}" ]]; then
      display_name="$(python3 "$UCC_TARGETS_QUERY_SCRIPT" --display-name "$target" "$UCC_TARGETS_MANIFEST" 2>/dev/null || true)"
      [[ -n "$display_name" ]] || display_name="$target"
    fi
  fi

  # Show target name in parentheses when display name differs
  if [[ "$display_name" != "$target" ]]; then
    display_name="${display_name} (${target})"
  fi
  _UCC_DISPLAY_NAME_CACHE_KEYS+=("$target")
  _UCC_DISPLAY_NAME_CACHE_VALUES+=("$display_name")
  printf '%s' "$display_name"
}

_ucc_emit_target_line() {
  local profile="$1" status="$2" name="$3" detail="${4:-}" line=""
  if [[ -n "$detail" ]]; then
    line=$(printf '      [%-8s] %-30s %s' "$status" "$name" "$detail")
  else
    line=$(printf '      [%-8s] %s' "$status" "$name")
  fi
  _ucc_emit_profile_line "$profile" "$line"
}

_ucc_policy_detail() {
  local name="$1" observed="$2" desired="$3" axes="$4" evidence_fn="$5" reason="$6"
  local evidence=""
  evidence="$(_ucc_compose_evidence "$name" "$observed" "$axes" "$evidence_fn")"
  if [[ -n "$evidence" ]]; then
    printf '%s (%s)' "$evidence" "$reason"
    return 0
  fi
  printf '"%s" -> "%s" (%s)' \
    "$(_ucc_display_state "$observed" "$axes")" \
    "$(_ucc_display_state "$desired" "$axes")" \
    "$reason"
}

_ucc_policy_warn_detail() {
  local name="$1" observed="$2" axes="$3" evidence_fn="$4" reason="$5"
  local evidence=""
  evidence="$(_ucc_compose_evidence "$name" "$observed" "$axes" "$evidence_fn")"
  if [[ -n "$evidence" ]]; then
    printf '%s  %s' "$reason" "$evidence"
    return 0
  fi
  printf '%s' "$reason"
}

_ucc_observe_yaml_simple_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local target_type configured_cmd observe_cmd state_model success_raw failure_raw raw_state
  local fn="${target//[^a-zA-Z0-9]/_}"
  local _cached_var="_UCC_OBS_CACHED_${fn}"

  if [[ -n "${!_cached_var:-}" ]]; then
    local _v
    _v="_UCC_OBS_TYPE_${fn}";    target_type="${!_v}"
    _v="_UCC_OBS_ORACLE_${fn}";  configured_cmd="${!_v}"
    _v="_UCC_OBS_CMD_${fn}";     observe_cmd="${!_v}"
    _v="_UCC_OBS_MODEL_${fn}";   state_model="${!_v}"
    _v="_UCC_OBS_SUCCESS_${fn}"; success_raw="${!_v}"
    _v="_UCC_OBS_FAILURE_${fn}"; failure_raw="${!_v}"
  else
    while IFS=$'\t' read -r -d '' key value; do
      case "$key" in
        type)              target_type="$value" ;;
        oracle.configured) configured_cmd="$value" ;;
        observe_cmd)       observe_cmd="$value" ;;
        state_model)       state_model="$value" ;;
        observe_success)   success_raw="$value" ;;
        observe_failure)   failure_raw="$value" ;;
      esac
    done < <(_ucc_yaml_target_get_many "$cfg_dir" "$yaml" "$target" type oracle.configured observe_cmd state_model observe_success observe_failure)
  fi
  [[ -n "$target_type" ]] || target_type="config"
  [[ -n "$state_model" ]] || state_model="$target_type"

  local driver_raw
  if driver_raw="$(_ucc_driver_observe "$cfg_dir" "$yaml" "$target")"; then
    [[ -n "$driver_raw" ]] || driver_raw="absent"
    case "$state_model" in
      package) ucc_asm_package_state "$driver_raw" ;;
      *)       ucc_asm_config_state  "$driver_raw" ;;
    esac
    return
  fi

  if [[ -n "$observe_cmd" ]]; then
    raw_state="$(_ucc_eval_yaml_scalar_cmd "$cfg_dir" "$yaml" "$target" "$observe_cmd")"
    [[ -n "$raw_state" ]] || raw_state="absent"
    case "$state_model" in
      package)
        ucc_asm_package_state "$raw_state"
        ;;
      *)
        ucc_asm_config_state "$raw_state"
        ;;
    esac
    return
  fi

  case "$state_model" in
    package)
      [[ -n "$success_raw" ]] || success_raw="present"
      [[ -n "$failure_raw" ]] || failure_raw="absent"
      ;;
    *)
      [[ -n "$success_raw" ]] || success_raw="configured"
      [[ -n "$failure_raw" ]] || failure_raw="absent"
      ;;
  esac

  if [[ -n "$configured_cmd" ]] && _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$configured_cmd"; then
    raw_state="$success_raw"
  else
    raw_state="$failure_raw"
  fi

  case "$state_model" in
    package)
      ucc_asm_package_state "$raw_state"
      ;;
    *)
      ucc_asm_config_state "$raw_state"
      ;;
  esac
}

_ucc_run_yaml_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action_key="$4"
  local cmd

  if [[ "$action_key" == "install" || "$action_key" == "update" ]]; then
    local _driver_kind
    _driver_kind="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.kind")"
    if [[ -n "$_driver_kind" && "$_driver_kind" != "custom" ]]; then
      _ucc_driver_action "$cfg_dir" "$yaml" "$target" "$action_key"
      return
    fi
  fi

  case "$action_key" in
    install)
      cmd="$(_ucc_yaml_target_action_get "$cfg_dir" "$yaml" "$target" "install")"
      ;;
    update)
      cmd="$(_ucc_yaml_target_action_get "$cfg_dir" "$yaml" "$target" "update")"
      ;;
    *)
      cmd="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "$action_key")"
      ;;
  esac
  [[ -n "$cmd" ]] || return 1
  if _ucc_yaml_target_admin_required "$cfg_dir" "$yaml" "$target" "$action_key"; then
    if sudo_not_available; then
      log_warn "Target '$target' requires admin privileges; acquire a sudo ticket first with: sudo -v"
      return 125
    fi
  fi
  _ucc_eval_yaml_expr "$cfg_dir" "$yaml" "$target" "$cmd"
}

# Return 0 if target should be skipped due to UCC_TARGET_SET filter.
# Emits a visible [skip] line so all targets are accounted for.
# UCC_TARGET_SET is always set:
#   - empty = nothing selected (skip all)
#   - populated = only targets in the set run
export _UCC_EMITTED_TARGETS=""

# Evaluate a requires: condition string (comma = OR).
# Each atom: value (match), !value (negate), name>=ver (version compare).
# Returns 0 if any atom is true.
_ucc_eval_requires() {
  local requires="$1" cond
  local _host_vals="|${HOST_PLATFORM:-}|${HOST_PLATFORM_VARIANT:-}|${HOST_ARCH:-}|${HOST_OS_ID:-}|${HOST_PACKAGE_MANAGER:-}|"
  # Add fingerprint segments
  local _fp="${HOST_FINGERPRINT:-}"
  local _seg; for _seg in ${_fp//\// }; do _host_vals="${_host_vals}${_seg}|"; done

  IFS=',' read -ra _conds <<< "$requires"
  for cond in "${_conds[@]}"; do
    cond="${cond// /}"  # trim
    [[ -z "$cond" ]] && continue

    # Version comparison: name>=version, name<version, etc.
    if [[ "$cond" =~ ^(!?)([a-zA-Z][a-zA-Z0-9_-]*)(>=|<=|>|<|==|!=)(.+)$ ]]; then
      local _neg="${BASH_REMATCH[1]}" _name="${BASH_REMATCH[2]}" _op="${BASH_REMATCH[3]}" _ver="${BASH_REMATCH[4]}"
      # Extract version from HOST_OS_ID: "macos-15.4" → macos=15.4
      local _actual=""
      if [[ "${HOST_OS_ID:-}" == "${_name}-"* ]]; then
        _actual="${HOST_OS_ID#${_name}-}"
      fi
      if [[ -n "$_actual" ]]; then
        local _result=1
        # Compare as dotted version tuples (avoid pipe-to-read subshell issue)
        local _smaller; _smaller="$(printf '%s\n%s' "$_actual" "$_ver" | sort -V 2>/dev/null | head -1 || echo "$_ver")"
        case "$_op" in
          ">=") [[ "$_smaller" == "$_ver" || "$_actual" == "$_ver" ]] && _result=0 ;;
          "<=") [[ "$_smaller" == "$_actual" || "$_actual" == "$_ver" ]] && _result=0 ;;
          ">")  [[ "$_smaller" == "$_ver" && "$_actual" != "$_ver" ]] && _result=0 ;;
          "<")  [[ "$_smaller" == "$_actual" && "$_actual" != "$_ver" ]] && _result=0 ;;
          "==") [[ "$_actual" == "$_ver" ]] && _result=0 ;;
          "!=") [[ "$_actual" != "$_ver" ]] && _result=0 ;;
        esac
        [[ -n "$_neg" ]] && { [[ $_result -eq 0 ]] && _result=1 || _result=0; }
        [[ $_result -eq 0 ]] && return 0
      else
        # Name not found — atom fails (unless negated)
        [[ -n "$_neg" ]] && return 0
      fi
      continue
    fi

    # Negation: !value
    if [[ "$cond" == !* ]]; then
      [[ "$_host_vals" != *"|${cond#!}|"* ]] && return 0
      continue
    fi

    # Simple match: value
    [[ "$_host_vals" == *"|${cond}|"* ]] && return 0
  done
  return 1  # no condition matched
}

_ucc_target_filtered_out() {
  local target="$1" cfg_dir="${2:-}" yaml="${3:-}"
  # Check if globally disabled by policy
  if [[ -n "${UCC_DISABLED_TARGETS:-}" && "${UCC_DISABLED_TARGETS}" == *"${target}|"* ]]; then
    _UCC_EMITTED_TARGETS="${_UCC_EMITTED_TARGETS}|${target}|"
    local display_name; display_name="$(_ucc_display_name "$target")"
    printf '      [%-8s] %-30s %s\n' "disabled" "$display_name" "disabled by policy"
    return 0
  fi
  # Check requires: condition (platform/version/PM support)
  if [[ -n "$cfg_dir" && -n "$yaml" ]]; then
    local _requires; _requires="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "requires" 2>/dev/null || true)"
    if [[ -n "$_requires" ]] && ! _ucc_eval_requires "$_requires"; then
      _UCC_EMITTED_TARGETS="${_UCC_EMITTED_TARGETS}|${target}|"
      local display_name; display_name="$(_ucc_display_name "$target")"
      printf '      [%-8s] %-30s %s\n' "skip" "$display_name" "requires: ${_requires}"
      return 0
    fi
  fi
  if [[ "${UCC_TARGET_SET:-}" != *"${target}|"* ]]; then
    _UCC_EMITTED_TARGETS="${_UCC_EMITTED_TARGETS}|${target}|"
    # Fast mode: hide non-selected targets entirely (no observe, no output)
    if [[ "${UIC_PREF_SKIP_DISPLAY_MODE:-full}" == "fast" ]]; then
      return 0
    fi
    local display_name state=""
    display_name="$(_ucc_display_name "$target")"
    # Try to observe current state (read-only, best-effort)
    if [[ -n "$cfg_dir" && -n "$yaml" ]]; then
      # Try driver first, then fall back to YAML oracle/observe_cmd
      state="$(_ucc_driver_observe "$cfg_dir" "$yaml" "$target" 2>/dev/null || true)"
      if [[ -z "$state" ]]; then
        # Custom driver — try observe_cmd
        local _obs_cmd; _obs_cmd="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "observe_cmd" 2>/dev/null || true)"
        if [[ -n "$_obs_cmd" ]]; then
          state="$(_ucc_eval_yaml_expr "$cfg_dir" "$yaml" "$target" "$_obs_cmd" 2>/dev/null || true)"
        fi
      fi
      if [[ -z "$state" ]]; then
        # Try oracle.configured
        local _oracle; _oracle="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "oracle.configured" 2>/dev/null || true)"
        if [[ -n "$_oracle" ]]; then
          if _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$_oracle" 2>/dev/null; then
            state="configured"
          fi
        fi
      fi
      if [[ -z "$state" ]]; then
        # Try oracle.runtime
        local _rt_oracle; _rt_oracle="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "oracle.runtime" 2>/dev/null || true)"
        if [[ -n "$_rt_oracle" ]]; then
          if _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$_rt_oracle" 2>/dev/null; then
            state="running"
          else
            state="stopped"
          fi
        fi
      fi
    fi
    if [[ -n "$state" && "$state" != "absent" ]]; then
      printf '      [%-8s] %-30s %s (current: %s)\n' "skip" "$display_name" "not selected" "$state"
    else
      printf '      [%-8s] %-30s %s\n' "skip" "$display_name" "not selected"
    fi
    return 0
  fi
  return 1
}

ucc_yaml_simple_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _ucc_target_filtered_out "$target" "$cfg_dir" "$yaml" && return 0
  local fn profile install_cmd update_cmd externally_managed_updates driver_kind
  local obs_type="" obs_oracle="" obs_cmd="" obs_model="" obs_success="" obs_failure=""
  local _ev_b64=""
  fn="${target//[^a-zA-Z0-9]/_}"
  profile="configured"
  install_cmd=""
  update_cmd=""
  externally_managed_updates=""
  driver_kind=""
  while IFS=$'\t' read -r -d '' key value; do
    if [[ "$key" == "__evidence__" ]]; then _ev_b64="$value"; continue; fi
    case "$key" in
      profile)                           [[ -n "$value" ]] && profile="$value" ;;
      actions.install)                   install_cmd="$value" ;;
      actions.update)                    update_cmd="$value" ;;
      driver.externally_managed_updates) externally_managed_updates="$value" ;;
      driver.kind)                       driver_kind="$value" ;;
      type)                              obs_type="$value" ;;
      oracle.configured)                 obs_oracle="$value" ;;
      observe_cmd)                       obs_cmd="$value" ;;
      state_model)                       obs_model="$value" ;;
      observe_success)                   obs_success="$value" ;;
      observe_failure)                   obs_failure="$value" ;;
    esac
  done < <(_ucc_ytgt_source "$cfg_dir" "$yaml" "$target" \
      profile actions.install actions.update driver.externally_managed_updates driver.kind \
      type oracle.configured observe_cmd state_model observe_success observe_failure)
  [[ -z "$update_cmd" ]] && update_cmd="$install_cmd"
  # A dispatched driver handles install/update even when actions.* are absent from YAML
  local driver_dispatched=0
  [[ -n "$driver_kind" && "$driver_kind" != "custom" ]] && driver_dispatched=1

  export "_UCC_OBS_CACHED_${fn}=1"
  export "_UCC_OBS_TYPE_${fn}=${obs_type}"
  export "_UCC_OBS_ORACLE_${fn}=${obs_oracle}"
  export "_UCC_OBS_CMD_${fn}=${obs_cmd}"
  export "_UCC_OBS_MODEL_${fn}=${obs_model}"
  export "_UCC_OBS_SUCCESS_${fn}=${obs_success}"
  export "_UCC_OBS_FAILURE_${fn}=${obs_failure}"
  export "_UCC_OBS_EVIDENCE_${fn}=${_ev_b64}"

  eval "_uyst_obs_${fn}() { _ucc_observe_yaml_simple_target '${cfg_dir}' '${yaml}' '${target}'; }"
  eval "_uyst_evd_${fn}() { ucc_eval_evidence_from_yaml '${cfg_dir}' '${yaml}' '${target}'; }"
  if [[ -n "$install_cmd" || "$driver_dispatched" == "1" ]]; then
    eval "_uyst_ins_${fn}() { _ucc_run_yaml_action '${cfg_dir}' '${yaml}' '${target}' install; }"
    eval "_uyst_upd_${fn}() { _ucc_run_yaml_action '${cfg_dir}' '${yaml}' '${target}' update; }"
  fi
  # Escalating recovery: wire _ucc_driver_recover if driver supports it
  if [[ "$driver_dispatched" == "1" ]]; then
    eval "_uyst_rec_${fn}() { _ucc_driver_recover '${cfg_dir}' '${yaml}' '${target}' \"\$1\"; }"
  fi

  local args=(--name "$target" --profile "$profile" --observe "_uyst_obs_${fn}" --evidence "_uyst_evd_${fn}")
  [[ -n "$install_cmd" || "$driver_dispatched" == "1" ]] && args+=(--install "_uyst_ins_${fn}")
  [[ -n "$install_cmd" || "$driver_dispatched" == "1" ]] && args+=(--update "_uyst_upd_${fn}")
  [[ "$driver_dispatched" == "1" ]] && args+=(--recover "_uyst_rec_${fn}")
  [[ "$externally_managed_updates" == "true" || "$externally_managed_updates" == "1" || "$externally_managed_updates" == "yes" ]] && \
    args+=(--warn-on-update-failure)
  ucc_target "${args[@]}"
}

_ucc_observe_yaml_capability_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local fn="${target//[^a-zA-Z0-9]/_}"
  local _cached_var="_UCC_OBS_CACHED_${fn}"
  local runtime_cmd
  if [[ -n "${!_cached_var:-}" ]]; then
    local _v="_UCC_CAP_RUNTIME_${fn}"; runtime_cmd="${!_v}"
  else
    runtime_cmd="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.probe")"
  fi
  if [[ -n "$runtime_cmd" ]] && _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$runtime_cmd"; then
    ucc_asm_state --installation Configured --runtime Running --health Healthy --admin Enabled --dependencies DepsReady
  else
    ucc_asm_state --installation Configured --runtime Stopped --health Degraded --admin Enabled --dependencies DepsReady
  fi
}

ucc_yaml_capability_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _ucc_target_filtered_out "$target" "$cfg_dir" "$yaml" && return 0
  local fn runtime_cmd=""
  local _ev_b64=""
  fn="${target//[^a-zA-Z0-9]/_}"
  while IFS=$'\t' read -r -d '' key value; do
    if [[ "$key" == "__evidence__" ]]; then _ev_b64="$value"; continue; fi
    case "$key" in
      driver.probe) runtime_cmd="$value" ;;
    esac
  done < <(_ucc_ytgt_source "$cfg_dir" "$yaml" "$target" driver.probe)

  export "_UCC_OBS_CACHED_${fn}=1"
  export "_UCC_OBS_EVIDENCE_${fn}=${_ev_b64}"
  export "_UCC_CAP_RUNTIME_${fn}=${runtime_cmd}"

  eval "_uyct_obs_${fn}() { _ucc_observe_yaml_capability_target '${cfg_dir}' '${yaml}' '${target}'; }"
  eval "_uyct_evd_${fn}() { ucc_eval_evidence_from_yaml '${cfg_dir}' '${yaml}' '${target}'; }"

  ucc_target \
    --name "$target" \
    --profile capability \
    --observe "_uyct_obs_${fn}" \
    --evidence "_uyct_evd_${fn}"
}

_ucc_yaml_gate_dependency_state() {
  local gate="$1" dep_state="DepsReady" gate_key=""
  [[ -n "$gate" ]] || { printf '%s' "$dep_state"; return; }
  gate_key="UIC_GATE_FAILED_$(echo "${gate//-/_}" | tr '[:lower:]' '[:upper:]')"
  [[ "${!gate_key:-0}" == "1" ]] && dep_state="DepsDegraded"
  printf '%s' "$dep_state"
}

_ucc_yaml_parametric_observed_state() {
  local current="$1" desired="$2" dep_state="$3"
  if [[ "$current" == "$desired" ]]; then
    ucc_asm_state \
      --installation Configured \
      --runtime Stopped \
      --health Healthy \
      --admin Enabled \
      --dependencies "$dep_state" \
      --config-value "$current"
  else
    ucc_asm_state \
      --installation Configured \
      --runtime Stopped \
      --health Degraded \
      --admin Enabled \
      --dependencies "$dep_state" \
      --config-value "$current"
  fi
}

_ucc_yaml_parametric_desired_state() {
  local desired="$1" dep_state="$2"
  ucc_asm_state \
    --installation Configured \
    --runtime Stopped \
    --health Healthy \
    --admin Enabled \
    --dependencies "$dep_state" \
    --config-value "$desired"
}

_ucc_observe_yaml_parametric_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local observe_cmd desired gate current dep_state
  local fn="${target//[^a-zA-Z0-9]/_}"
  local _cached_var="_UCC_OBS_CACHED_${fn}"
  if [[ -n "${!_cached_var:-}" ]]; then
    local _v
    _v="_UCC_PARAM_OBS_CMD_${fn}"; observe_cmd="${!_v}"
    _v="_UCC_PARAM_GATE_${fn}";    gate="${!_v}"
    _v="_UCC_PARAM_DESIRED_${fn}"; desired="${!_v}"
  else
    while IFS=$'\t' read -r -d '' key value; do
      case "$key" in
        observe_cmd)     observe_cmd="$value" ;;
        dependency_gate) gate="$value" ;;
      esac
    done < <(_ucc_yaml_target_get_many "$cfg_dir" "$yaml" "$target" observe_cmd dependency_gate)
    desired="$(_ucc_yaml_parametric_desired_value "$cfg_dir" "$yaml" "$target")"
  fi
  dep_state="$(_ucc_yaml_gate_dependency_state "$gate")"
  local driver_raw
  if driver_raw="$(_ucc_driver_observe "$cfg_dir" "$yaml" "$target")"; then
    [[ -n "$driver_raw" ]] || driver_raw="absent"
    _ucc_yaml_parametric_observed_state "$driver_raw" "$desired" "$dep_state"
    return
  fi
  current="$(_ucc_eval_yaml_scalar_cmd "$cfg_dir" "$yaml" "$target" "$observe_cmd")"
  _ucc_yaml_parametric_observed_state "$current" "$desired" "$dep_state"
}

_ucc_evidence_yaml_parametric_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local observe_cmd current evidence
  local fn="${target//[^a-zA-Z0-9]/_}"
  local _cached_var="_UCC_OBS_CACHED_${fn}"
  if [[ -n "${!_cached_var:-}" ]]; then
    local _v="_UCC_PARAM_OBS_CMD_${fn}"; observe_cmd="${!_v}"
  else
    while IFS=$'\t' read -r -d '' key value; do
      case "$key" in
        observe_cmd) observe_cmd="$value" ;;
      esac
    done < <(_ucc_yaml_target_get_many "$cfg_dir" "$yaml" "$target" observe_cmd)
  fi
  local CFG_DIR="$cfg_dir" YAML_PATH="$yaml" TARGET_NAME="$target"
  evidence="$(ucc_eval_evidence_from_yaml "$cfg_dir" "$yaml" "$target")"
  if [[ -n "$evidence" ]]; then
    printf '%s' "$evidence"
    return 0
  fi
  current="$(_ucc_eval_yaml_scalar_cmd "$cfg_dir" "$yaml" "$target" "$observe_cmd")"
  printf 'value=%s' "$current"
}

_ucc_yaml_parametric_desired_value() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local desired_cmd desired_value
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      desired_cmd) desired_cmd="$value" ;;
      desired_value) desired_value="$value" ;;
    esac
  done < <(_ucc_yaml_target_get_many "$cfg_dir" "$yaml" "$target" desired_cmd desired_value)

  if [[ -n "$desired_cmd" ]]; then
    _ucc_eval_yaml_scalar_cmd "$cfg_dir" "$yaml" "$target" "$desired_cmd"
    return 0
  fi
  printf '%s' "$desired_value"
}

ucc_yaml_parametric_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _ucc_target_filtered_out "$target" "$cfg_dir" "$yaml" && return 0
  local fn install_cmd update_cmd desired gate dep_state driver_kind
  local obs_cmd="" obs_gate="" desired_cmd="" desired_value_raw=""
  local _ev_b64=""
  fn="${target//[^a-zA-Z0-9]/_}"
  install_cmd=""
  update_cmd=""
  driver_kind=""
  while IFS=$'\t' read -r -d '' key value; do
    if [[ "$key" == "__evidence__" ]]; then _ev_b64="$value"; continue; fi
    case "$key" in
      actions.install)  install_cmd="$value" ;;
      actions.update)   update_cmd="$value" ;;
      desired_cmd)      desired_cmd="$value" ;;
      desired_value)    desired_value_raw="$value" ;;
      dependency_gate)  obs_gate="$value" ;;
      observe_cmd)      obs_cmd="$value" ;;
      driver.kind)      driver_kind="$value" ;;
    esac
  done < <(_ucc_ytgt_source "$cfg_dir" "$yaml" "$target" \
      actions.install actions.update desired_cmd desired_value dependency_gate observe_cmd driver.kind)
  [[ -z "$update_cmd" ]] && update_cmd="$install_cmd"
  local driver_dispatched=0
  [[ -n "$driver_kind" && "$driver_kind" != "custom" ]] && driver_dispatched=1
  if [[ -n "$desired_cmd" ]]; then
    desired="$(_ucc_eval_yaml_scalar_cmd "$cfg_dir" "$yaml" "$target" "$desired_cmd")"
  else
    desired="$desired_value_raw"
  fi
  gate="$obs_gate"
  dep_state="$(_ucc_yaml_gate_dependency_state "$gate")"

  export "_UCC_OBS_CACHED_${fn}=1"
  export "_UCC_OBS_EVIDENCE_${fn}=${_ev_b64}"
  export "_UCC_PARAM_OBS_CMD_${fn}=${obs_cmd}"
  export "_UCC_PARAM_GATE_${fn}=${gate}"
  export "_UCC_PARAM_DESIRED_${fn}=${desired}"

  eval "_uypt_obs_${fn}() { _ucc_observe_yaml_parametric_target '${cfg_dir}' '${yaml}' '${target}'; }"
  eval "_uypt_evd_${fn}() { _ucc_evidence_yaml_parametric_target '${cfg_dir}' '${yaml}' '${target}'; }"
  if [[ ("$driver_dispatched" == "1" || -n "$install_cmd") && "$dep_state" == "DepsReady" ]]; then
    eval "_uypt_ins_${fn}() { _ucc_run_yaml_action '${cfg_dir}' '${yaml}' '${target}' install; }"
    eval "_uypt_upd_${fn}() { _ucc_run_yaml_action '${cfg_dir}' '${yaml}' '${target}' update; }"
  fi

  local args=(
    --name "$target"
    --profile parametric
    --observe "_uypt_obs_${fn}"
    --evidence "_uypt_evd_${fn}"
    --desired "$(_ucc_yaml_parametric_desired_state "$desired" "$dep_state")"
  )
  [[ ("$driver_dispatched" == "1" || -n "$install_cmd") && "$dep_state" == "DepsReady" ]] && args+=(--install "_uypt_ins_${fn}")
  [[ ("$driver_dispatched" == "1" || -n "$install_cmd") && "$dep_state" == "DepsReady" ]] && args+=(--update "_uypt_upd_${fn}")
  ucc_target "${args[@]}"
}

_ucc_observe_yaml_runtime_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local fn="${target//[^a-zA-Z0-9]/_}"
  local _cached_var="_UCC_OBS_CACHED_${fn}"
  local runtime_driver
  if [[ -n "${!_cached_var:-}" ]]; then
    local _v="_UCC_RT_DRIVER_${fn}"; runtime_driver="${!_v}"
  else
    runtime_driver="$(_ucc_yaml_target_driver_get "$cfg_dir" "$yaml" "$target" "kind")"
  fi
  # Try driver dispatch first — drivers like custom-daemon have their own observe
  local _driver_state
  if _driver_state="$(_ucc_driver_observe "$cfg_dir" "$yaml" "$target" 2>/dev/null)"; then
    # Map driver raw state to ASM
    case "$_driver_state" in
      absent)  ucc_asm_state --installation Absent --runtime NeverStarted --health Unavailable --admin Enabled --dependencies DepsUnknown ;;
      running) ucc_asm_runtime_desired ;;
      stopped)
        local _sh _sd _v
        _v="_UCC_RT_STOPPED_HEALTH_${fn}"; _sh="${!_v:-Degraded}"
        _v="_UCC_RT_STOPPED_DEPS_${fn}"; _sd="${!_v:-DepsDegraded}"
        ucc_asm_state --installation Configured --runtime Stopped --health "$_sh" --admin Enabled --dependencies "$_sd" ;;
      *)       ucc_asm_state --installation Configured --runtime Stopped --health Degraded --admin Enabled --dependencies DepsReady ;;
    esac
    return
  fi
  case "$runtime_driver" in
    desktop-app)
      _ucc_observe_yaml_desktop_app_runtime_target "$cfg_dir" "$yaml" "$target"
      return ;;
    docker-compose)
      _ucc_observe_yaml_docker_compose_runtime_target "$cfg_dir" "$yaml" "$target"
      return ;;
  esac
  _ucc_observe_yaml_runtime_oracle_target "$cfg_dir" "$yaml" "$target"
}

_ucc_observe_yaml_runtime_oracle_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local configured_cmd runtime_cmd stopped_installation stopped_runtime stopped_health stopped_dependencies
  local fn="${target//[^a-zA-Z0-9]/_}"
  local _cached_var="_UCC_OBS_CACHED_${fn}"
  if [[ -n "${!_cached_var:-}" ]]; then
    local _v
    _v="_UCC_RT_CONFIGURED_${fn}";    configured_cmd="${!_v}"
    _v="_UCC_RT_RUNTIME_${fn}";       runtime_cmd="${!_v}"
    _v="_UCC_RT_STOPPED_INST_${fn}";  stopped_installation="${!_v}"
    _v="_UCC_RT_STOPPED_RT_${fn}";    stopped_runtime="${!_v}"
    _v="_UCC_RT_STOPPED_HEALTH_${fn}";stopped_health="${!_v}"
    _v="_UCC_RT_STOPPED_DEPS_${fn}";  stopped_dependencies="${!_v}"
  else
    while IFS=$'\t' read -r -d '' key value; do
      case "$key" in
        oracle.configured)    configured_cmd="$value" ;;
        oracle.runtime)       runtime_cmd="$value" ;;
        stopped_installation) stopped_installation="$value" ;;
        stopped_runtime)      stopped_runtime="$value" ;;
        stopped_health)       stopped_health="$value" ;;
        stopped_dependencies) stopped_dependencies="$value" ;;
      esac
    done < <(_ucc_yaml_target_get_many "$cfg_dir" "$yaml" "$target" \
      oracle.configured oracle.runtime stopped_installation stopped_runtime stopped_health stopped_dependencies)
  fi
  [[ -n "$stopped_installation" ]] || stopped_installation="Configured"
  [[ -n "$stopped_runtime" ]] || stopped_runtime="Stopped"
  [[ -n "$stopped_health" ]] || stopped_health="Degraded"
  [[ -n "$stopped_dependencies" ]] || stopped_dependencies="DepsDegraded"

  if [[ -n "$configured_cmd" ]] && ! _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$configured_cmd"; then
    ucc_asm_state --installation Absent --runtime NeverStarted --health Unavailable --admin Enabled --dependencies DepsUnknown
    return
  fi

  if [[ -n "$runtime_cmd" ]] && _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$runtime_cmd"; then
    ucc_asm_runtime_desired
    return
  fi

  ucc_asm_state \
    --installation "$stopped_installation" \
    --runtime "$stopped_runtime" \
    --health "$stopped_health" \
    --admin Enabled \
    --dependencies "$stopped_dependencies"
}

_ucc_observe_yaml_desktop_app_runtime_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local configured_cmd runtime_cmd package_ref app_path greedy_auto_updates observed install_source policy
  local fn="${target//[^a-zA-Z0-9]/_}"
  local _cached_var="_UCC_OBS_CACHED_${fn}"
  if [[ -n "${!_cached_var:-}" ]]; then
    local _v
    _v="_UCC_RT_CONFIGURED_${fn}"; configured_cmd="${!_v}"
    _v="_UCC_RT_RUNTIME_${fn}";    runtime_cmd="${!_v}"
    _v="_UCC_RT_PKG_${fn}";        package_ref="${!_v}"
    _v="_UCC_RT_APP_${fn}";        app_path="${!_v}"
    _v="_UCC_RT_GREEDY_${fn}";     greedy_auto_updates="${!_v}"
  else
    while IFS=$'\t' read -r -d '' key value; do
      case "$key" in
        oracle.configured)          configured_cmd="$value" ;;
        oracle.runtime)             runtime_cmd="$value" ;;
        driver.package_ref)         package_ref="$value" ;;
        driver.app_path)            app_path="$value" ;;
        driver.greedy_auto_updates) greedy_auto_updates="$value" ;;
      esac
    done < <(_ucc_yaml_target_get_many "$cfg_dir" "$yaml" "$target" \
      oracle.configured oracle.runtime driver.package_ref driver.app_path driver.greedy_auto_updates)
  fi

  observed="installed"
  policy="${UIC_PREF_PREFERRED_DRIVER_POLICY:-warn}"
  if [[ -n "$package_ref" ]] && command -v desktop_app_install_source >/dev/null 2>&1; then
    install_source="$(desktop_app_install_source "$package_ref" "$app_path" 2>/dev/null || true)"
  elif [[ -n "$app_path" && -d "$app_path" ]]; then
    install_source="app-bundle"
  else
    install_source="absent"
  fi

  if [[ "$install_source" == "brew-cask" ]] && command -v brew_cask_observe >/dev/null 2>&1; then
    observed="$(brew_cask_observe "$package_ref" "$greedy_auto_updates" 2>/dev/null || true)"
  elif [[ "$install_source" == "app-bundle" ]]; then
    if [[ "$policy" == "ignore" ]]; then
      observed="installed"
    else
      printf 'needs-update'
      return
    fi
  elif [[ -n "$configured_cmd" ]] && ! _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$configured_cmd"; then
    observed="absent"
  fi

  if [[ "$observed" == "absent" ]] && [[ -n "$configured_cmd" ]] && ! _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$configured_cmd"; then
    ucc_asm_state --installation Absent --runtime NeverStarted --health Unavailable --admin Enabled --dependencies DepsUnknown
    return
  fi

  if [[ -n "$runtime_cmd" ]] && _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$runtime_cmd"; then
    if [[ "$observed" == "outdated" ]]; then
      ucc_asm_state --installation Installed --runtime Running --health Degraded --admin Enabled --dependencies DepsDegraded
    else
      ucc_asm_runtime_desired
    fi
    return
  fi

  if [[ "$observed" == "outdated" ]]; then
    ucc_asm_state --installation Installed --runtime Stopped --health Degraded --admin Enabled --dependencies DepsDegraded
    return
  fi

  ucc_asm_state --installation Configured --runtime Stopped --health Unavailable --admin Enabled --dependencies DepsDegraded
}

_ucc_observe_yaml_docker_compose_runtime_target() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local runtime_cmd service_name state
  local fn="${target//[^a-zA-Z0-9]/_}"
  local _cached_var="_UCC_OBS_CACHED_${fn}"
  if [[ -n "${!_cached_var:-}" ]]; then
    local _v
    _v="_UCC_RT_RUNTIME_${fn}"; runtime_cmd="${!_v}"
    _v="_UCC_RT_SERVICE_${fn}"; service_name="${!_v}"
  else
    while IFS=$'\t' read -r -d '' key value; do
      case "$key" in
        oracle.runtime)      runtime_cmd="$value" ;;
        driver.service_name) service_name="$value" ;;
      esac
    done < <(_ucc_yaml_target_get_many "$cfg_dir" "$yaml" "$target" oracle.runtime driver.service_name)
  fi
  [[ -f "${COMPOSE_FILE:-}" ]] || {
    ucc_asm_state --installation Absent --runtime Stopped --health Unavailable --admin Enabled --dependencies DepsFailed
    return
  }

  state="$(docker inspect --format '{{.State.Status}}' "$service_name" 2>/dev/null || true)"
  if [[ -z "$state" ]]; then
    ucc_asm_state --installation Configured --runtime Stopped --health Unavailable --admin Enabled --dependencies DepsReady
    return
  fi
  if [[ "$state" != "running" ]]; then
    ucc_asm_state --installation Configured --runtime Stopped --health Degraded --admin Enabled --dependencies DepsReady
    return
  fi

  if [[ -n "$runtime_cmd" ]] && ! _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$runtime_cmd"; then
    ucc_asm_state --installation Configured --runtime Running --health Degraded --admin Enabled --dependencies DepsReady
    return
  fi

  ucc_asm_runtime_desired
}

ucc_yaml_runtime_target() {
  local cfg_dir="$1" yaml="$2" target="$3" install_fn="${4:-}" update_fn="${5:-}"
  _ucc_target_filtered_out "$target" "$cfg_dir" "$yaml" && return 0
  local fn install_cmd update_cmd
  local obs_configured="" obs_runtime="" obs_driver="" obs_service="" obs_pkg="" obs_app="" obs_greedy=""
  local obs_stopped_inst="" obs_stopped_rt="" obs_stopped_health="" obs_stopped_deps=""
  local _ev_b64=""
  fn="${target//[^a-zA-Z0-9]/_}"
  install_cmd=""
  update_cmd=""
  while IFS=$'\t' read -r -d '' key value; do
    if [[ "$key" == "__evidence__" ]]; then _ev_b64="$value"; continue; fi
    case "$key" in
      actions.install)             install_cmd="$value" ;;
      actions.update)              update_cmd="$value" ;;
      oracle.configured)           obs_configured="$value" ;;
      oracle.runtime)              obs_runtime="$value" ;;
      driver.kind)                 obs_driver="$value" ;;
      driver.service_name)         obs_service="$value" ;;
      driver.package_ref)          obs_pkg="$value" ;;
      driver.app_path)             obs_app="$value" ;;
      driver.greedy_auto_updates)  obs_greedy="$value" ;;
      stopped_installation)        obs_stopped_inst="$value" ;;
      stopped_runtime)             obs_stopped_rt="$value" ;;
      stopped_health)              obs_stopped_health="$value" ;;
      stopped_dependencies)        obs_stopped_deps="$value" ;;
    esac
  done < <(_ucc_ytgt_source "$cfg_dir" "$yaml" "$target" \
      actions.install actions.update oracle.configured oracle.runtime \
      driver.kind driver.service_name driver.package_ref driver.app_path \
      driver.greedy_auto_updates stopped_installation stopped_runtime \
      stopped_health stopped_dependencies)
  [[ -z "$update_cmd" ]] && update_cmd="$install_cmd"
  # A dispatched driver handles install/update even when actions.* are absent from YAML
  local driver_dispatched=0
  [[ -n "$obs_driver" && "$obs_driver" != "custom" ]] && driver_dispatched=1

  export "_UCC_OBS_CACHED_${fn}=1"
  export "_UCC_OBS_EVIDENCE_${fn}=${_ev_b64}"
  export "_UCC_RT_CONFIGURED_${fn}=${obs_configured}"
  export "_UCC_RT_RUNTIME_${fn}=${obs_runtime}"
  export "_UCC_RT_DRIVER_${fn}=${obs_driver}"
  export "_UCC_RT_SERVICE_${fn}=${obs_service}"
  export "_UCC_RT_PKG_${fn}=${obs_pkg}"
  export "_UCC_RT_APP_${fn}=${obs_app}"
  export "_UCC_RT_GREEDY_${fn}=${obs_greedy}"
  export "_UCC_RT_STOPPED_INST_${fn}=${obs_stopped_inst}"
  export "_UCC_RT_STOPPED_RT_${fn}=${obs_stopped_rt}"
  export "_UCC_RT_STOPPED_HEALTH_${fn}=${obs_stopped_health}"
  export "_UCC_RT_STOPPED_DEPS_${fn}=${obs_stopped_deps}"

  eval "_uyrt_obs_${fn}() { _ucc_observe_yaml_runtime_target '${cfg_dir}' '${yaml}' '${target}'; }"
  eval "_uyrt_evd_${fn}() { ucc_eval_evidence_from_yaml '${cfg_dir}' '${yaml}' '${target}'; }"
  if [[ -z "$install_fn" && ( -n "$install_cmd" || "$driver_dispatched" == "1" ) ]]; then
    eval "_uyrt_ins_${fn}() {
      local rc=0 runtime_cmd=''
      _ucc_run_yaml_action '${cfg_dir}' '${yaml}' '${target}' install || rc=\$?
      if [[ \$rc -eq 0 ]]; then
        runtime_cmd=\"\$(_ucc_yaml_target_get '${cfg_dir}' '${yaml}' '${target}' 'oracle.runtime')\"
        [[ -n \"\$runtime_cmd\" ]] && _ucc_wait_for_yaml_runtime_probe '${cfg_dir}' '${yaml}' '${target}' \"\$runtime_cmd\" || true
      fi
      return \$rc
    }"
    install_fn="_uyrt_ins_${fn}"
  fi
  if [[ -z "$update_fn" && ( -n "$update_cmd" || -n "$install_cmd" || "$driver_dispatched" == "1" ) ]]; then
    eval "_uyrt_upd_${fn}() {
      local rc=0 runtime_cmd=''
      _ucc_run_yaml_action '${cfg_dir}' '${yaml}' '${target}' update || rc=\$?
      if [[ \$rc -eq 0 ]]; then
        runtime_cmd=\"\$(_ucc_yaml_target_get '${cfg_dir}' '${yaml}' '${target}' 'oracle.runtime')\"
        [[ -n \"\$runtime_cmd\" ]] && _ucc_wait_for_yaml_runtime_probe '${cfg_dir}' '${yaml}' '${target}' \"\$runtime_cmd\" || true
      fi
      return \$rc
    }"
    update_fn="_uyrt_upd_${fn}"
  fi

  local args=(
    --name "$target"
    --observe "_uyrt_obs_${fn}"
    --evidence "_uyrt_evd_${fn}"
    --desired "$(ucc_asm_runtime_desired)"
  )
  [[ -n "$install_fn" ]] && args+=(--install "$install_fn")
  [[ -n "$update_fn" ]] && args+=(--update "$update_fn")
  ucc_target_service "${args[@]}"
}

_ucc_observe_brew_runtime_formula() {
  local pkg="$1" service_name="$2" runtime_cmd="${3:-}" configured_cmd="${4:-}" cfg_dir="${5:-}" yaml="${6:-}" target="${7:-}"
  local pkg_state

  pkg_state="$(brew_observe "$pkg")"

  if [[ "$pkg_state" == "absent" ]]; then
    ucc_asm_state --installation Absent --runtime NeverStarted --health Unavailable --admin Enabled --dependencies DepsUnknown
    return
  fi

  if [[ "$pkg_state" == "outdated" ]]; then
    if brew_service_is_started "$service_name"; then
      ucc_asm_state --installation Installed --runtime Running --health Degraded --admin Enabled --dependencies DepsDegraded
    else
      ucc_asm_state --installation Installed --runtime Stopped --health Degraded --admin Enabled --dependencies DepsDegraded
    fi
    return
  fi

  if [[ -n "$configured_cmd" ]] && ! _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$configured_cmd"; then
    ucc_asm_state --installation Installed --runtime Stopped --health Degraded --admin Enabled --dependencies DepsDegraded
    return
  fi

  if ! brew_service_is_started "$service_name"; then
    ucc_asm_state --installation Configured --runtime Stopped --health Degraded --admin Enabled --dependencies DepsDegraded
    return
  fi

  if [[ -n "$runtime_cmd" ]] && ! _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$runtime_cmd"; then
    ucc_asm_state --installation Configured --runtime Running --health Degraded --admin Enabled --dependencies DepsDegraded
    return
  fi

  ucc_asm_runtime_desired
}

_ucc_apply_brew_runtime_formula() {
  local pkg="$1" brew_ref="$2" service_name="$3" runtime_cmd="${4:-}" mode="${5:-install}" cfg_dir="${6:-}" yaml="${7:-}" target="${8:-}"
  local pkg_state

  pkg_state="$(brew_observe "$pkg")"
  if [[ "$pkg_state" == "absent" ]]; then
    brew_install "$brew_ref" || return 1
  elif [[ "$pkg_state" == "outdated" || "$mode" == "update" ]]; then
    brew_upgrade "$brew_ref" || return 1
  fi

  if brew_service_is_started "$service_name"; then
    ucc_run brew services restart "$brew_ref" || return 1
  else
    ucc_run brew services start "$brew_ref" || return 1
  fi

  [[ -n "$runtime_cmd" ]] && _ucc_wait_for_yaml_runtime_probe "$cfg_dir" "$yaml" "$target" "$runtime_cmd"
}

_ucc_wait_for_runtime_probe() {
  local runtime_cmd="$1"
  local attempts="${UCC_RUNTIME_WAIT_ATTEMPTS:-20}"
  local interval="${UCC_RUNTIME_WAIT_INTERVAL:-1}"
  local i

  [[ -n "$runtime_cmd" ]] || return 0

  for ((i = 1; i <= attempts; i++)); do
    if eval "$runtime_cmd" >/dev/null 2>&1; then
      return 0
    fi
    [[ "$i" -lt "$attempts" ]] && sleep "$interval"
  done

  return 1
}

_ucc_wait_for_yaml_runtime_probe() {
  local cfg_dir="$1" yaml="$2" target="$3" runtime_cmd="$4"
  local attempts="${UCC_RUNTIME_WAIT_ATTEMPTS:-20}"
  local interval="${UCC_RUNTIME_WAIT_INTERVAL:-1}"
  local i

  [[ -n "$runtime_cmd" ]] || return 0

  for ((i = 1; i <= attempts; i++)); do
    if _ucc_yaml_expr_succeeds "$cfg_dir" "$yaml" "$target" "$runtime_cmd"; then
      return 0
    fi
    [[ "$i" -lt "$attempts" ]] && sleep "$interval"
  done

  return 1
}

# ucc_brew_runtime_formula_target <target-name> <brew-pkg> [brew-ref] [cfg_dir] [yaml] [service-name]
# Software-centric brew formula target: package presence, service lifecycle, and
# runtime probe are governed as one runtime-profile target.
ucc_brew_runtime_formula_target() {
  local tname="$1" pkg="$2" brew_ref="${3:-$2}" cfg_dir="${4:-}" yaml="${5:-}" service_name="${6:-$2}"
  _ucc_target_filtered_out "$tname" "$cfg_dir" "$yaml" && return 0
  local fn; fn="${tname//[^a-zA-Z0-9]/_}"
  eval "_ubrt_obs_${fn}() {
    local runtime_cmd configured_cmd
    if [[ -n '${cfg_dir}' && -n '${yaml}' ]]; then
      runtime_cmd=\"\$(_ucc_yaml_target_get '${cfg_dir}' '${yaml}' '${tname}' 'oracle.runtime')\"
      configured_cmd=\"\$(_ucc_yaml_target_get '${cfg_dir}' '${yaml}' '${tname}' 'oracle.configured')\"
    fi
    _ucc_observe_brew_runtime_formula '${pkg}' '${service_name}' \"\$runtime_cmd\" \"\$configured_cmd\" '${cfg_dir}' '${yaml}' '${tname}'
  }"
  eval "_ubrt_evd_${fn}() {
    if [[ -n '${cfg_dir}' && -n '${yaml}' ]]; then
      ucc_eval_evidence_from_yaml '${cfg_dir}' '${yaml}' '${tname}'
      return
    fi
    local ver
    ver=\$(_brew_cached_version '${pkg}')
    [[ -n \"\$ver\" ]] && printf 'version=%s' \"\$ver\"
  }"
  eval "_ubrt_ins_${fn}() {
    local runtime_cmd=''
    if [[ -n '${cfg_dir}' && -n '${yaml}' ]]; then
      runtime_cmd=\"\$(_ucc_yaml_target_get '${cfg_dir}' '${yaml}' '${tname}' 'oracle.runtime')\"
    fi
    _ucc_apply_brew_runtime_formula '${pkg}' '${brew_ref}' '${service_name}' \"\$runtime_cmd\" install '${cfg_dir}' '${yaml}' '${tname}'
  }"
  eval "_ubrt_upd_${fn}() {
    local runtime_cmd=''
    if [[ -n '${cfg_dir}' && -n '${yaml}' ]]; then
      runtime_cmd=\"\$(_ucc_yaml_target_get '${cfg_dir}' '${yaml}' '${tname}' 'oracle.runtime')\"
    fi
    _ucc_apply_brew_runtime_formula '${pkg}' '${brew_ref}' '${service_name}' \"\$runtime_cmd\" update '${cfg_dir}' '${yaml}' '${tname}'
  }"
  ucc_target_service --name "$tname" \
    --observe "_ubrt_obs_${fn}" \
    --evidence "_ubrt_evd_${fn}" \
    --desired "$(ucc_asm_runtime_desired)" \
    --install "_ubrt_ins_${fn}" \
    --update "_ubrt_upd_${fn}"
}

# ── _ucc_record_outcome — shared emit+count+record for all outcome paths ───────
# Usage: _ucc_record_outcome <profile> <name> <COUNTER|""> <target_status> \
#                             <summary_status> <msg_id> <started_at> <diff_json> <result_json>
# COUNTER: CONVERGED | CHANGED | FAILED | "" (unchanged / dry-run paths)
_ucc_record_outcome() {
  local _p="$1" _n="$2" _ctr="$3" _tst="$4" _sst="$5" _mid="$6" _sat="$7" _dif="$8" _res="$9"
  [[ -n "$_ctr" ]] && eval "_UCC_${_ctr}=\$(( _UCC_${_ctr} + 1 ))"
  _ucc_record_profile_summary "$_p" "$_sst"
  _ucc_record_target_status "$_n" "$_tst"
  local _dur; _dur=$(_ucc_duration_ms "$_sat")
  _ucc_record_result "$_mid" "$_dur" "$_dif" "$_res"
}

_UCC_REGISTERED_NAMES=()
_UCC_REGISTERED_ARGS=()
_UCC_REGISTERED_ENV=()

ucc_reset_registered_targets() {
  _UCC_REGISTERED_NAMES=()
  _UCC_REGISTERED_ARGS=()
  _UCC_REGISTERED_ENV=()
}

_ucc_should_snapshot_var() {
  local name="$1" decl="${2:-}"
  [[ -n "$name" ]] || return 1
  [[ "$name" =~ ^(_UCC_|BASH_|EUID$|PPID$|SHELLOPTS$|BASHPID$|FUNCNAME$|BASH_SOURCE$|BASH_LINENO$|LINENO$|RANDOM$|SECONDS$|SRANDOM$|PIPESTATUS$|GROUPS$|DIRSTACK$|COMP_|COPROC$|MAPFILE$) ]] && return 1
  [[ "$decl" == declare\ -r* || "$decl" == "declare -ir"* || "$decl" == "declare -ar"* || "$decl" == "declare -A -r"* || "$decl" == "declare -n -r"* ]] && return 1
  return 0
}

_ucc_capture_visible_vars() {
  local name decl snapshot=""
  while IFS= read -r name; do
    decl="$(declare -p "$name" 2>/dev/null || true)"
    [[ -n "$decl" ]] || continue
    _ucc_should_snapshot_var "$name" "$decl" || continue
    snapshot+="${decl}"$'\n'
  done < <(compgen -A variable | LC_ALL=C sort)
  printf '%s' "$snapshot"
}

_ucc_register_target() {
  local args=("$@") name="" argv="" arg snapshot=""
  while [[ ${#args[@]} -gt 0 ]]; do
    case "${args[0]}" in
      --name) name="${args[1]:-}"; args=("${args[@]:2}") ;;
      *) args=("${args[@]:1}") ;;
    esac
  done
  [[ -n "$name" ]] || { log_error "Attempted to register unnamed target"; return 1; }
  for arg in "$@"; do
    argv+="$(printf '%q ' "$arg")"
  done
  snapshot="$(_ucc_capture_visible_vars)"
  _UCC_REGISTERED_NAMES+=("$name")
  _UCC_REGISTERED_ARGS+=("${argv% }")
  _UCC_REGISTERED_ENV+=("$snapshot")
}

_ucc_registered_index() {
  local needle="$1" i
  for i in "${!_UCC_REGISTERED_NAMES[@]}"; do
    [[ "${_UCC_REGISTERED_NAMES[$i]}" == "$needle" ]] && { printf '%s' "$i"; return 0; }
  done
  return 1
}

_ucc_target_status_value() {
  local target="$1"
  [[ -n "${UCC_TARGET_STATUS_FILE:-}" && -f "${UCC_TARGET_STATUS_FILE:-}" ]] || return 0
  awk -F'|' -v dep="$target" '$1==dep {val=$2} END {print val}' "$UCC_TARGET_STATUS_FILE" 2>/dev/null || true
}

# Return direct depends_on list for a target (newline-separated).
_ucc_target_direct_deps() {
  local t="$1"
  if [[ -n "${_UCC_ALL_DEPS_CACHE:-}" ]]; then
    printf '%s\n' "$_UCC_ALL_DEPS_CACHE" | awk -F'\t' -v tgt="$t" '$1==tgt{print $2; exit}' | tr ',' '\n'
  else
    python3 "$UCC_TARGETS_QUERY_SCRIPT" --deps "$t" "$UCC_TARGETS_MANIFEST" 2>/dev/null || true
  fi
}

# Return the oracle.configured command for a target, or empty if none.
_ucc_target_oracle_configured() {
  local t="$1"
  if [[ -n "${_UCC_ALL_ORACLES_CACHE:-}" ]]; then
    printf '%s\n' "$_UCC_ALL_ORACLES_CACHE" | awk -F'\t' -v tgt="$t" '$1==tgt{print $2; exit}'
  fi
}

# Recursively walk the transitive dep closure of $root_target.
# Arguments:
#   $1 root_target  — the target whose deps we are checking now
#   $2 origin       — the top-level target that started the chain (for error messages)
#   $3 visited      — colon-separated cycle guard (e.g. "A:B:C")
#
# Per dep:
#   status "failed"   → hard block (dep ran this session and failed)
#   status non-empty, non-failed → dep ran and passed; its own transitive deps were
#                                   already validated when it ran — skip recursion
#   status empty      → dep not run this session; probe oracle.configured:
#                         oracle fail → hard block
#                         oracle pass or no oracle → recurse into dep's own deps
_ucc_check_deps_recursive() {
  local root_target="$1" origin="${2:-$1}" visited="${3:-}" dep deps status oracle_cmd
  deps="$(_ucc_target_direct_deps "$root_target")"
  [[ -n "$deps" ]] || return 0
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    # Cycle guard — colons added at check time, not storage time
    [[ ":${visited}:" == *":${dep}:"* ]] && continue
    status="$(_ucc_target_status_value "$dep")"
    if [[ "$status" == "failed" ]]; then
      printf '      [%-8s] %-30s dependency failed this run: %s\n' \
        "dep-fail" "$(_ucc_display_name "$origin")" "$dep"
      return 1
    fi
    if [[ -n "$status" ]]; then
      # Dep ran this session and did not fail; its transitive deps were already
      # validated before it executed — no need to recurse further.
      continue
    fi
    # Dep not run this session — probe its oracle.configured to verify it's installed
    oracle_cmd="$(_ucc_target_oracle_configured "$dep")"
    if [[ -n "$oracle_cmd" ]]; then
      if ! eval "$oracle_cmd" 2>/dev/null; then
        printf '      [%-8s] %-30s dependency not satisfied (oracle fail): %s\n' \
          "dep-fail" "$(_ucc_display_name "$origin")" "$dep"
        return 1
      fi
      # Oracle passed — record a synthetic status so evidence shows "oracle-pass" not "unknown"
      _ucc_record_target_status "$dep" "oracle-pass"
    fi
    # Oracle passed (or no oracle) — recurse into this dep's own deps
    _ucc_check_deps_recursive "$dep" "$origin" "${visited}:${dep}" || return 1
  done <<< "$deps"
  return 0
}

_ucc_require_declared_dependencies_resolved() {
  local target="$1"
  [[ -n "${UCC_TARGETS_MANIFEST:-}" && -n "${UCC_TARGETS_QUERY_SCRIPT:-}" ]] || return 0
  _ucc_check_deps_recursive "$target" "$target" "$target"
}

# ── ucc_target — full UCC Steps 0-6 lifecycle per target ─────────────────────

_ucc_execute_target() {
  local _ucc_snapshot="${UCC_EXEC_SNAPSHOT:-}"
  if [[ -n "$_ucc_snapshot" ]]; then
    eval "$_ucc_snapshot"
  fi

  local name="" observe_fn="" desired="" install_fn="" update_fn="" axes="" profile="" evidence_fn="" recover_fn=""
  local warn_on_update_failure=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)    name="$2";       shift 2 ;;
      --observe) observe_fn="$2"; shift 2 ;;
      --desired) desired="$2";    shift 2 ;;
      --install) install_fn="$2"; shift 2 ;;
      --update)  update_fn="$2";  shift 2 ;;
      --axes)    axes="$2";       shift 2 ;;
      --evidence) evidence_fn="$2"; shift 2 ;;
      --profile) profile="$2";    shift 2 ;;
      --recover) recover_fn="$2"; shift 2 ;;
      --warn-on-update-failure) warn_on_update_failure=1; shift ;;
      *) shift ;;
    esac
  done

  [[ -z "$axes" && -n "$profile" ]] && axes="$(_ucc_profile_axes "$profile")"
  if [[ -z "$desired" && "$profile" == "parametric" ]]; then
    log_warn "parametric target '$name' requires explicit --desired with --config-value — profile default has no config_value, will cause perpetual re-convergence"
  fi
  [[ -z "$desired" && -n "$profile" ]] && desired="$(_ucc_profile_desired "$profile")"

  local started_at declaration_ts mode target_id msg_id duration_ms display_name
  started_at=$(date +%s 2>/dev/null || echo 0)
  declaration_ts=$(_ucc_now_utc)
  mode="apply"
  [[ "$UCC_DRY_RUN" == "1" ]] && mode="dry_run"
  target_id=$(_ucc_target_id "$name")
  msg_id="${UCC_CORRELATION_ID:-run}-${target_id}"
  display_name="$(_ucc_display_name "$name")"
  _ucc_record_declaration "$msg_id" "$name" "$desired" "$mode" "$declaration_ts"

  # Step 1 – Observe current state
  local observed obs_exit
  observed=$($observe_fn 2>/dev/null)
  obs_exit=$?

  # observation=failed: observe function crashed (non-zero exit)
  if [[ $obs_exit -ne 0 ]]; then
    _ucc_emit_target_line "$profile" "obs-fail" "$display_name" "observe fn exited non-zero"
    _ucc_record_outcome "$profile" "$name" "FAILED" "failed" "failed" "$msg_id" "$started_at" \
      "{}" "{\"observation\":\"failed\",\"message\":\"observe function exited non-zero\"}"
    return 0
  fi

  # observation=indeterminate: observe ran (exit 0) but produced no usable state
  if [[ -z "$observed" ]]; then
    _ucc_emit_target_line "$profile" "unknown" "$display_name" "observe returned no state"
    _ucc_record_outcome "$profile" "$name" "FAILED" "failed" "failed" "$msg_id" "$started_at" \
      "{}" "{\"observation\":\"indeterminate\",\"message\":\"observe returned empty state\"}"
    return 0
  fi

  log_debug "observed=\"$observed\" desired=\"$desired\" mode=$UCC_MODE"

  # Helper: is observed state satisfying desired?
  # @present wildcard: any value other than "absent" or "outdated" counts as present
  _ucc_satisfied() {
    local obs="$1" des="$2"
    [[ "$des" == "@present" && "$obs" != "absent" && "$obs" != "outdated" ]] && return 0
    [[ "$(_ucc_diff_obj "$obs" "$des" "$axes")" == "{}" ]]
  }

  # Step 3 – Diff: is observed state == desired?
  if _ucc_satisfied "$observed" "$desired"; then

    if [[ "$UCC_MODE" == "update" && -n "$update_fn" ]]; then
      # Update mode: run upgrade even when state already matches
    if [[ "$UCC_DRY_RUN" == "1" ]]; then
        _ucc_emit_target_line "$profile" "dry-run" "$display_name" "state=\"$(_ucc_display_state "$observed" "$axes")\" (update skipped)"
        _ucc_record_outcome "$profile" "$name" "" "unchanged" "unchanged" "$msg_id" "$started_at" \
          "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":{}}" \
          "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"dry_run\",\"message\":\"update transition not applied due to dry-run mode\"}"
        return 0
    fi
      local update_rc=0
      $update_fn || update_rc=$?
      if [[ $update_rc -eq 0 ]]; then
        local verified ver_exit
        verified=$($observe_fn 2>/dev/null)
        ver_exit=$?
        if [[ $ver_exit -eq 0 ]] && _ucc_satisfied "$verified" "$desired"; then
          _ucc_emit_target_line "$profile" "updated" "$display_name" "\"$(_ucc_display_state "$observed" "$axes")\" -> \"$(_ucc_display_state "$verified" "$axes")\""
          _ucc_record_outcome "$profile" "$name" "CHANGED" "ok" "changed" "$msg_id" "$started_at" \
            "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$verified" "$axes"),\"observed_after\":$(_ucc_state_obj "$verified")}" \
            "{\"observation\":\"ok\",\"outcome\":\"changed\",\"completion\":\"complete\",\"proof\":{\"change\":\"update_applied\"}}"
        elif [[ "$warn_on_update_failure" == "1" ]]; then
          _ucc_emit_target_line "$profile" "warn" "$display_name" "update remains externally managed  $(_ucc_compose_evidence "$name" "${verified:-$observed}" "$axes" "$evidence_fn")"
          _ucc_record_outcome "$profile" "$name" "" "warn" "unchanged" "$msg_id" "$started_at" \
            "{}" "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"update must be applied externally\"}"
        else
          _ucc_attempt_escalation "$observe_fn" "$desired" "$axes" "$recover_fn" \
            "$display_name" "$profile" "updated" "$name" "$observed" "$msg_id" "$started_at" \
            && return 0
          _ucc_emit_target_line "$profile" "fail" "$display_name" "verify after update: \"$(_ucc_display_state "${verified:-?}" "$axes")\"  $(_ucc_compose_evidence "$name" "${verified:-$observed}" "$axes" "$evidence_fn")"
          _ucc_record_outcome "$profile" "$name" "FAILED" "failed" "failed" "$msg_id" "$started_at" \
            "{}" "{\"observation\":\"failed\",\"message\":\"post-update verify did not reach desired state\"}"
        fi
      elif [[ $update_rc -eq 124 ]]; then
        _ucc_emit_target_line "$profile" "warn" "$display_name" \
          "$(_ucc_policy_warn_detail "$name" "$observed" "$axes" "$evidence_fn" "transition blocked by policy")"
        _ucc_record_outcome "$profile" "$name" "" "warn" "unchanged" "$msg_id" "$started_at" \
          "{}" "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"transition blocked by policy\"}"
      elif [[ $update_rc -eq 125 ]]; then
        _ucc_emit_target_line "$profile" "policy" "$display_name" \
          "$(_ucc_policy_detail "$name" "$observed" "$desired" "$axes" "$evidence_fn" "admin required")"
        _ucc_record_outcome "$profile" "$name" "" "unchanged" "unchanged" "$msg_id" "$started_at" \
          "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$desired" "$axes")}" \
          "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"transition requires admin privileges\"}"
      elif [[ "$warn_on_update_failure" == "1" ]]; then
        _ucc_emit_target_line "$profile" "warn" "$display_name" "update remains externally managed  $(_ucc_compose_evidence "$name" "$observed" "$axes" "$evidence_fn")"
        _ucc_record_outcome "$profile" "$name" "" "warn" "unchanged" "$msg_id" "$started_at" \
          "{}" "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"update must be applied externally\"}"
      else
        _ucc_attempt_escalation "$observe_fn" "$desired" "$axes" "$recover_fn" \
          "$display_name" "$profile" "updated" "$name" "$observed" "$msg_id" "$started_at" \
          && return 0
        _ucc_emit_target_line "$profile" "fail" "$display_name" "update error state=\"$(_ucc_display_state "$observed" "$axes")\""
        _ucc_record_outcome "$profile" "$name" "FAILED" "failed" "failed" "$msg_id" "$started_at" \
          "{}" "{\"observation\":\"failed\",\"message\":\"update function failed\"}"
      fi
    else
      # Already at desired state
      _ucc_emit_target_line "$profile" "ok" "$display_name" "$(_ucc_compose_evidence "$name" "$observed" "$axes" "$evidence_fn")"
      _ucc_record_outcome "$profile" "$name" "CONVERGED" "ok" "ok" "$msg_id" "$started_at" \
        "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":{}}" \
        "{\"observation\":\"ok\",\"outcome\":\"converged\"}"
    fi
    return 0
  fi

  # Step 4: Apply transition
  if [[ "$UCC_DRY_RUN" == "1" ]]; then
    _ucc_emit_target_line "$profile" "dry-run" "$display_name" "\"$(_ucc_display_state "$observed" "$axes")\" -> \"$(_ucc_display_state "$desired" "$axes")\""
    _ucc_record_outcome "$profile" "$name" "" "unchanged" "unchanged" "$msg_id" "$started_at" \
      "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$desired" "$axes")}" \
      "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"dry_run\",\"message\":\"transition not applied due to dry-run mode\"}"
    return 0
  fi

  if [[ -z "$install_fn" ]]; then
    _ucc_emit_target_line "$profile" "policy" "$display_name" \
      "$(_ucc_policy_detail "$name" "$observed" "$desired" "$axes" "$evidence_fn" "policy blocked")"
    _ucc_record_outcome "$profile" "$name" "" "unchanged" "unchanged" "$msg_id" "$started_at" \
      "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$desired" "$axes")}" \
      "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"transition not applied - no install function declared\"}"
    return 0
  fi

  # Route outdated → update_fn (upgrade), absent → install_fn (fresh install)
  local action_fn="$install_fn"
  local action_label="installed"
  local action_context="install"
  if _ucc_observed_prefers_update_action "$observed" && [[ -n "$update_fn" ]]; then
    action_fn="$update_fn"
    action_label="updated"
    action_context="update"
  fi

  # Interactive mode: confirm before applying changes
  if [[ "${UCC_INTERACTIVE:-0}" == "1" && -t 0 ]]; then
    printf '      [?] %s %s? [Y/n] ' "$action_context" "$display_name"
    local _confirm
    read -r _confirm
    if [[ "$_confirm" =~ ^[Nn] ]]; then
      _ucc_emit_target_line "$profile" "skip" "$display_name" "user declined"
      _ucc_record_outcome "$profile" "$name" "" "unchanged" "unchanged" "$msg_id" "$started_at" \
        "{}" "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"user\",\"message\":\"user declined interactive confirmation\"}"
      return 0
    fi
  fi

  local action_rc=0
  $action_fn || action_rc=$?

  # Step 5 – Verify: re-observe after transition.
  # Always attempt verify when action ran (not a policy exit).  The action may
  # have succeeded even on non-zero exit (e.g. brew exits 1 when a dependency
  # unlinks a conflicting keg, yet the package itself was installed correctly).
  # If verify confirms desired state, declare success regardless of action_rc.
  if [[ $action_rc -ne 124 && $action_rc -ne 125 ]]; then
    local verified ver_exit
    verified=$($observe_fn 2>/dev/null)
    ver_exit=$?
    log_debug "post-${action_context} observed=\"$verified\""
    if [[ $ver_exit -eq 0 ]] && _ucc_satisfied "$verified" "$desired"; then
      _ucc_emit_target_line "$profile" "$action_label" "$display_name" "\"$(_ucc_display_state "$observed" "$axes")\" -> \"$(_ucc_display_state "$verified" "$axes")\""
      _ucc_record_outcome "$profile" "$name" "CHANGED" "ok" "changed" "$msg_id" "$started_at" \
        "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$verified" "$axes"),\"observed_after\":$(_ucc_state_obj "$verified")}" \
        "{\"observation\":\"ok\",\"outcome\":\"changed\",\"completion\":\"complete\",\"proof\":{\"change\":\"verify_pass\"}}"
    elif [[ "$warn_on_update_failure" == "1" && "$action_context" == "update" ]]; then
      _ucc_emit_target_line "$profile" "warn" "$display_name" "update remains externally managed  $(_ucc_compose_evidence "$name" "${verified:-$observed}" "$axes" "$evidence_fn")"
      _ucc_record_outcome "$profile" "$name" "" "warn" "unchanged" "$msg_id" "$started_at" \
        "{}" "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"update must be applied externally\"}"
    elif [[ $action_rc -eq 0 ]]; then
      _ucc_attempt_escalation "$observe_fn" "$desired" "$axes" "$recover_fn" \
        "$display_name" "$profile" "$action_label" "$name" "$observed" "$msg_id" "$started_at" \
        && return 0
      _ucc_emit_target_line "$profile" "fail" "$display_name" "verify after ${action_context}: \"$(_ucc_display_state "${verified:-?}" "$axes")\"  $(_ucc_compose_evidence "$name" "${verified:-$observed}" "$axes" "$evidence_fn")"
      _ucc_record_outcome "$profile" "$name" "FAILED" "failed" "failed" "$msg_id" "$started_at" \
        "{}" "{\"observation\":\"failed\",\"message\":\"post-${action_context} verify did not reach desired state\"}"
    else
      _ucc_attempt_escalation "$observe_fn" "$desired" "$axes" "$recover_fn" \
        "$display_name" "$profile" "$action_label" "$name" "$observed" "$msg_id" "$started_at" \
        && return 0
      _ucc_emit_target_line "$profile" "fail" "$display_name" "${action_context} error was=\"$(_ucc_display_state "$observed" "$axes")\"  $(_ucc_compose_evidence "$name" "$observed" "$axes" "$evidence_fn")"
      _ucc_record_outcome "$profile" "$name" "FAILED" "failed" "failed" "$msg_id" "$started_at" \
        "{}" "{\"observation\":\"failed\",\"message\":\"${action_context} function failed; verify also did not reach desired state\"}"
    fi
    return 0
  fi
  if [[ $action_rc -eq 124 ]]; then
    _ucc_emit_target_line "$profile" "warn" "$display_name" \
      "$(_ucc_policy_warn_detail "$name" "$observed" "$axes" "$evidence_fn" "transition blocked by policy")"
    _ucc_record_outcome "$profile" "$name" "" "warn" "unchanged" "$msg_id" "$started_at" \
      "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$desired" "$axes")}" \
      "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"transition blocked by policy\"}"
  elif [[ $action_rc -eq 125 ]]; then
    _ucc_emit_target_line "$profile" "policy" "$display_name" \
      "$(_ucc_policy_detail "$name" "$observed" "$desired" "$axes" "$evidence_fn" "admin required")"
    _ucc_record_outcome "$profile" "$name" "" "unchanged" "unchanged" "$msg_id" "$started_at" \
      "{\"observed_before\":$(_ucc_state_obj "$observed"),\"diff\":$(_ucc_diff_obj "$observed" "$desired" "$axes")}" \
      "{\"observation\":\"ok\",\"outcome\":\"unchanged\",\"inhibitor\":\"policy\",\"message\":\"transition requires admin privileges\"}"
  fi
}

ucc_flush_registered_targets() {
  local component="$1" ordered="" target idx
  local declared=() undeclared=()
  [[ ${#_UCC_REGISTERED_NAMES[@]} -gt 0 ]] || return 0

  if [[ -n "${_UCC_ALL_ORDERED_CACHE:-}" ]]; then
    ordered="$(printf '%s\n' "$_UCC_ALL_ORDERED_CACHE" | awk -F'\t' -v c="$component" '$1==c{print $2; exit}' | tr ',' '\n')"
  elif [[ -n "${UCC_TARGETS_MANIFEST:-}" && -n "${UCC_TARGETS_QUERY_SCRIPT:-}" ]]; then
    ordered="$(python3 "$UCC_TARGETS_QUERY_SCRIPT" --ordered-targets "$component" "$UCC_TARGETS_MANIFEST" 2>/dev/null || true)"
  fi

  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    declared+=("$target")
  done <<< "$ordered"

  for target in "${declared[@]}"; do
    idx="$(_ucc_registered_index "$target" || true)"
    [[ -n "$idx" ]] || continue
    # Target set filter applied at entry points (ucc_yaml_*_target functions)
    _ucc_require_declared_dependencies_resolved "$target" || return 1
    UCC_EXEC_SNAPSHOT="${_UCC_REGISTERED_ENV[$idx]}" eval "_ucc_execute_target ${_UCC_REGISTERED_ARGS[$idx]}" || return 1
  done

  local name seen
  for idx in "${!_UCC_REGISTERED_NAMES[@]}"; do
    name="${_UCC_REGISTERED_NAMES[$idx]}"
    seen=0
    for target in "${declared[@]}"; do
      [[ "$target" == "$name" ]] && { seen=1; break; }
    done
    [[ "$seen" -eq 1 ]] && continue
    log_warn "Target '$name' is not declared in the manifest; executing after topo-sorted targets with no dependencies"
    undeclared+=("$idx")
  done

  for idx in "${undeclared[@]}"; do
    UCC_EXEC_SNAPSHOT="${_UCC_REGISTERED_ENV[$idx]}" eval "_ucc_execute_target ${_UCC_REGISTERED_ARGS[$idx]}" || return 1
  done

  # Emit [skip] for targets in the component that the runner never processed
  for target in "${declared[@]}"; do
    # Check if target was registered (runner called ucc_yaml_*_target for it)
    _was_processed=0
    for _rn in "${_UCC_REGISTERED_NAMES[@]+"${_UCC_REGISTERED_NAMES[@]}"}"; do
      [[ "$_rn" == "$target" ]] && { _was_processed=1; break; }
    done
    # Check if target was already handled by _ucc_target_filtered_out
    [[ "${_UCC_EMITTED_TARGETS:-}" == *"|${target}|"* ]] && _was_processed=1
    if [[ $_was_processed -eq 0 ]]; then
      local _dn; _dn="$(_ucc_display_name "$target")"
      if [[ -n "${UCC_DISABLED_TARGETS:-}" && "${UCC_DISABLED_TARGETS}" == *"${target}|"* ]]; then
        printf '      [%-8s] %-30s %s\n' "disabled" "$_dn" "disabled by policy"
      else
        printf '      [%-8s] %-30s %s\n' "skip" "$_dn" "not processed"
      fi
    fi
  done
}

ucc_target() {
  # Extract --name for filter check
  local _tgt_name="" _a _prev=0
  for _a in "$@"; do
    if [[ $_prev -eq 1 ]]; then _tgt_name="$_a"; break; fi
    [[ "$_a" == "--name" ]] && _prev=1
  done
  [[ -n "$_tgt_name" ]] && _ucc_target_filtered_out "$_tgt_name" && return 0

  if [[ "${UCC_TARGET_DEFER:-0}" == "1" ]]; then
    _ucc_register_target "$@"
  else
    _ucc_execute_target "$@"
  fi
}

_ucc_target_with_default_profile() {
  local _default="$1"; shift
  local has_profile=0 args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile) has_profile=1; args+=("$1" "$2"); shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  [[ "$has_profile" -eq 0 ]] && args+=(--profile "$_default")
  ucc_target "${args[@]}"
}

ucc_target_nonruntime() { _ucc_target_with_default_profile configured "$@"; }
ucc_target_service()    { _ucc_target_with_default_profile runtime    "$@"; }

ucc_skip_target() {
  _ucc_target_filtered_out "$1" && return 0
  local name="$1" reason="$2"
  local display_name
  display_name="$(_ucc_display_name "$name")"
  printf '      [%-8s] %-30s %s\n' "skip" "$display_name" "$reason"
  _UCC_SKIPPED=$(( ${_UCC_SKIPPED:-0} + 1 ))
  _UCC_EMITTED_TARGETS="${_UCC_EMITTED_TARGETS}|${name}|"
}

# ── ucc_summary — write per-component counts to summary file ──────────────────

ucc_summary() {
  local comp="${1:-}"
  if [[ -n "${UCC_SUMMARY_FILE:-}" && -n "$comp" ]]; then
    printf '%s|%d|%d|%d|%d\n' "$comp" "$_UCC_CONVERGED" "$_UCC_CHANGED" "$_UCC_FAILED" "${_UCC_SKIPPED:-0}" \
      >> "$UCC_SUMMARY_FILE" 2>/dev/null || true
  fi
}
