#!/usr/bin/env bash
# lib/ucc_targets_yaml.sh — YAML target-field reader + user-override layer.
#
# Extracted from lib/ucc_targets.sh on 2026-04-28 (PLAN refactor #2, slice 1).
# These helpers read fields off a target manifest, apply env / overlay-file
# overrides, and evaluate inline YAML scalar expressions. Sourced from
# lib/ucc_targets.sh before the lifecycle functions that depend on them.

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
    "${UCC_FRAMEWORK_PYTHON:-python3}" "$cfg_dir/tools/read_config.py" --target-get-many-with-evidence "$yaml" "$target" "$@" 2>/dev/null || true
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
  # 1. env var (sanitize: bash var names allow only [A-Za-z0-9_])
  local env_target="${target//-/_}"
  env_target="${env_target//[^A-Za-z0-9_]/_}"
  local env_key="${key//./_}"
  env_key="${env_key//[^A-Za-z0-9_]/_}"
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
    val="$("${UCC_FRAMEWORK_PYTHON:-python3}" "$cfg_dir/tools/read_config.py" --target-get "$yaml" "$target" "$key" 2>/dev/null || true)"
  fi
  printf '%s' "${val:-$default}"
}

_ucc_yaml_target_get_many() {
  local cfg_dir="$1" yaml="$2" target="$3"
  shift 3
  local yaml_fn="${yaml//[^a-zA-Z0-9]/_}"
  local target_fn="${target//[^a-zA-Z0-9]/_}"
  local cache_var="_UCC_YTGT_${yaml_fn}_${target_fn}"
  if [[ -n "${!cache_var:-}" ]]; then
    # Filter cached rows to only requested keys
    local _keys=""
    local _k; for _k in "$@"; do _keys="${_keys}|${_k}"; done
    _keys="${_keys#|}"
    printf '%s' "${!cache_var}" | base64 -d | awk -F'\t' -v keys="$_keys" \
      'BEGIN{RS="\0"; n=split(keys,ka,"|"); for(i=1;i<=n;i++) want[ka[i]]=1}
       $1 in want {printf "%s\t%s\0",$1,$2}'
  else
    "${UCC_FRAMEWORK_PYTHON:-python3}" "$cfg_dir/tools/read_config.py" --target-get-many "$yaml" "$target" "$@" 2>/dev/null || true
  fi
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
  local cfg_dir="$1" yaml="$2" target="$3" expr="$4" _rc=0
  _ucc_eval_yaml_expr "$cfg_dir" "$yaml" "$target" "$expr" >/dev/null 2>&1 || _rc=$?
  if [[ $_rc -gt 1 ]]; then
    # rc=1 is normal "condition false"; rc>1 signals a probe error
    log_warn "oracle probe error (rc=$_rc) for target '$target': $expr" 2>/dev/null || true
  fi
  return $_rc
}

_ucc_eval_yaml_scalar_cmd() {
  local cfg_dir="$1" yaml="$2" target="$3" cmd="$4" output trimmed _rc=0
  output="$(_ucc_eval_yaml_expr "$cfg_dir" "$yaml" "$target" "$cmd" 2>/dev/null)" || _rc=$?
  if [[ $_rc -ne 0 && -z "$output" ]]; then
    log_warn "observe probe failed (rc=$_rc) for target '$target': $cmd" 2>/dev/null || true
  fi
  output="${output%%$'\n'*}"
  trimmed="${output#"${output%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  printf '%s' "$trimmed"
}
