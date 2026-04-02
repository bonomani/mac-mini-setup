#!/usr/bin/env bash
# ============================================================
#  UIC/0.1 — Universal Input Contract engine
#  Pre-convergence gate evaluation and preference resolution
#
#  Repo  : https://github.com/bonomani/uic
#  WSL   : /home/bc/repos/github/bonomani/uic
#  Win   : /mnt/c/scripts/Uic
#
#  Resolution order (UIC §6 — normative):
#    1. Evaluate hard GATES  → outcome=failed, failure_class=permanent
#    2. Evaluate soft GATES  → outcome=unchanged, inhibitor=policy
#    3. Load PREFERENCES     → ambiguity_unresolved on missing required
#    4. Derive POLICIES      → inhibitor=policy on violation
#    5. Begin UCC convergence (Steps 0–6)
#
#  Pre-flight mode (UIC §7):
#    Set UIC_PREFLIGHT=1 or pass --preflight to install.sh
#    Reports gate/preference status. Does NOT modify state.
#
#  Preferences file:
#    $HOME/.ai-stack/preferences.env  — KEY=value overrides
#    Defaults are the globally safest choices.
# ============================================================

UIC_PREFLIGHT=${UIC_PREFLIGHT:-0}
UIC_PREF_FILE=${UIC_PREF_FILE:-"$HOME/.ai-stack/preferences.env"}

# Parallel indexed arrays (bash 3.2 compatible — no declare -A)
_UIC_GATE_NAMES=()
_UIC_GATE_CONDS=()
_UIC_GATE_SCOPES=()
_UIC_GATE_CLASSES=()
_UIC_GATE_BLOCKS=()
_UIC_GATE_TARGETS=()

_UIC_PREF_NAMES=()
_UIC_PREF_VALUES=()
_UIC_PREF_DEFAULTS=()
_UIC_PREF_OPTIONS=()
_UIC_PREF_RATIONALES=()
_UIC_PREF_SCOPES=()

_UIC_FAILED_HARD=()
_UIC_FAILED_SOFT=()

# ============================================================
#  Internal helpers
# ============================================================

# Normalize name to uppercase env-var key  (bash 3.2: use tr, not ${^^})
_uic_pref_key()  { echo "UIC_PREF_$(echo  "${1//-/_}" | tr '[:lower:]' '[:upper:]')"; }
_uic_gate_key()  { echo "UIC_GATE_FAILED_$(echo "${1//-/_}" | tr '[:lower:]' '[:upper:]')"; }

# Read operator-provided value from preferences file
_uic_file_val() {
  local key
  key=$(echo "${1//-/_}" | tr '[:lower:]' '[:upper:]')
  [[ -f "$UIC_PREF_FILE" ]] \
    && grep -E "^${key}=" "$UIC_PREF_FILE" 2>/dev/null | head -1 | cut -d= -f2- \
    || true
}

# ============================================================
#  uic_gate — declare a gate
#
#  Usage:
#    uic_gate --name <name> --condition <fn> \
#             [--scope global|component:<name>|target:<name>] \
#             [--class readiness|authorization|integrity] \
#             [--target-state <asm-target-description>] \
#             [--blocking hard|soft]
# ============================================================
uic_gate() {
  local name="" cond="" scope="global" class="readiness" blocking="hard" target_state=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)      name="$2";     shift 2 ;;
      --condition) cond="$2";     shift 2 ;;
      --scope)     scope="$2";    shift 2 ;;
      --class)     class="$2";    shift 2 ;;
      --target-state) target_state="$2"; shift 2 ;;
      --blocking)  blocking="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  _UIC_GATE_NAMES+=("$name")
  _UIC_GATE_CONDS+=("$cond")
  _UIC_GATE_SCOPES+=("$scope")
  _UIC_GATE_CLASSES+=("$class")
  _UIC_GATE_BLOCKS+=("$blocking")
  _UIC_GATE_TARGETS+=("$target_state")
}

# ============================================================
#  uic_preference — declare a preference with a safe default
#
#  Usage:
#    uic_preference --name <name> --default <safe-default> \
#                  --options "<a|b|c>" --rationale "<text>" \
#                  [--scope global|component:<name>]
#
#  Invariants (UIC §4):
#    - options must have at least 2 entries (pipe-separated)
#    - rationale is mandatory
#    - operator file value is validated against options; invalid → default
# ============================================================
uic_preference() {
  local name="" default="" options="" rationale="" scope="global"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)      name="$2";      shift 2 ;;
      --default)   default="$2";   shift 2 ;;
      --options)   options="$2";   shift 2 ;;
      --rationale) rationale="$2"; shift 2 ;;
      --scope)     scope="$2";     shift 2 ;;
      *) shift ;;
    esac
  done

  # UIC §4 invariant: minimum 2 options
  # Use echo (adds trailing newline) so wc -l counts lines not newlines:
  # "mps|cpu" → "mps\ncpu\n" → wc -l = 2  (printf '%s' gives 1 newline = wrong)
  local opt_count
  opt_count=$(echo "$options" | tr '|' '\n' | wc -l | tr -d ' ')
  if [[ "$opt_count" -lt 2 ]]; then
    log_warn "UIC defect: preference '$name' has fewer than 2 options ($opt_count found) — skipping"
    return 0   # warn but do not abort the script (set -e safe)
  fi

  # UIC §4 invariant: rationale mandatory
  if [[ -z "$rationale" ]]; then
    log_warn "UIC defect: preference '$name' missing rationale — skipping"
    return 0   # warn but do not abort the script (set -e safe)
  fi

  # Resolve: env-var (--pref / CI) > interactive prompt > operator file > safe default
  local resolved="$default"
  local file_val env_key env_val
  env_key="$(_uic_pref_key "$name")"
  env_val="${!env_key:-}"
  if [[ -n "$env_val" ]]; then
    if echo "$options" | tr '|' '\n' | grep -qx "$env_val" 2>/dev/null; then
      resolved="$env_val"
    else
      log_warn "UIC: preference '$name' — env var value '$env_val' not in options ($options); using safe default '$default'"
    fi
  elif [[ "${UCC_INTERACTIVE:-0}" == "1" ]] && [[ -c /dev/tty ]]; then
    log_debug "uic_preference: interactive prompt for '$name'"
    # Interactive mode: prompt user to choose
    # Print header once before first interactive preference
    if [[ -z "${_UIC_INTERACTIVE_HEADER_SHOWN:-}" ]]; then
      echo ""
      echo "  ── Preference Selection ──────────────────────────────"
      _UIC_INTERACTIVE_HEADER_SHOWN=1
    fi
    local _opts_arr=() _i=1 _choice _opts_inline=""
    while IFS= read -r _o; do
      _opts_arr+=("$_o")
      local _marker=""
      [[ "$_o" == "$default" ]] && _marker="*"
      _opts_inline="${_opts_inline:+$_opts_inline, }${_marker}${_i})${_o}"
      _i=$((_i + 1))
    done < <(echo "$options" | tr '|' '\n')
    printf '  [?] %-28s [%s] ' "$name" "$_opts_inline"
    read -r _choice < /dev/tty
    if [[ -n "$_choice" && "$_choice" =~ ^[0-9]+$ && "$_choice" -ge 1 && "$_choice" -le "${#_opts_arr[@]}" ]]; then
      resolved="${_opts_arr[$((_choice - 1))]}"
    fi
  else
    file_val="$(_uic_file_val "$name")"
    if [[ -n "$file_val" ]]; then
      if echo "$options" | tr '|' '\n' | grep -qx "$file_val" 2>/dev/null; then
        resolved="$file_val"
      else
        log_warn "UIC: preference '$name' — operator value '$file_val' not in options ($options); using safe default '$default'"
      fi
    fi
  fi

  # Tag scope as env when the value came from an env var (--pref / CI)
  [[ -n "$env_val" && "$resolved" == "$env_val" ]] && scope="env"

  _UIC_PREF_NAMES+=("$name")
  _UIC_PREF_VALUES+=("$resolved")
  _UIC_PREF_DEFAULTS+=("$default")
  _UIC_PREF_OPTIONS+=("$options")
  _UIC_PREF_RATIONALES+=("$rationale")
  _UIC_PREF_SCOPES+=("$scope")
}

# ============================================================
#  uic_get — read a resolved preference value (works in subshells)
#
#  Reads from exported env var UIC_PREF_<NAME>.
#  Falls back to the default embedded in the key if declared.
# ============================================================
uic_get() {
  local name="$1"
  local key
  key="$(_uic_pref_key "$name")"
  local val="${!key:-}"
  if [[ -n "$val" ]]; then
    echo "$val"
    return 0
  fi
  log_warn "UIC: preference '$name' not resolved — declare it before uic_resolve"
  return 1
}

# ============================================================
#  uic_gate_failed — check if a named gate has failed (subshell safe)
# ============================================================
uic_gate_failed() {
  local key
  key="$(_uic_gate_key "$1")"
  [[ "${!key:-}" == "1" ]]
}

# ============================================================
#  uic_component_blocked — true if any hard gate scoped to component failed
# ============================================================
uic_component_blocked() {
  local comp="$1"
  local i
  for i in "${!_UIC_GATE_NAMES[@]}"; do
    [[ "${_UIC_GATE_SCOPES[$i]}" == "component:${comp}" ]] || continue
    [[ "${_UIC_GATE_BLOCKS[$i]}" == "hard" ]]              || continue
    local g="${_UIC_GATE_NAMES[$i]}"
    local gkey
    gkey="$(_uic_gate_key "$g")"
    [[ "${!gkey:-}" == "1" ]] && return 0
  done
  return 1
}

# ============================================================
#  _uic_eval_gate — evaluate a single gate and print result
# ============================================================
_uic_eval_gate() {
  local i="$1"
  local name="${_UIC_GATE_NAMES[$i]}"
  local cond="${_UIC_GATE_CONDS[$i]}"
  local blocking="${_UIC_GATE_BLOCKS[$i]}"
  local class="${_UIC_GATE_CLASSES[$i]}"
  local scope="${_UIC_GATE_SCOPES[$i]}"
  local target_state="${_UIC_GATE_TARGETS[$i]}"

  local scope_short="${scope/component:/}"
  local target_suffix=""
  if [[ -n "$target_state" ]]; then
    local _tname="${target_state%% *}"
    local _taxes="${target_state#* }"
    [[ "$_taxes" == "$_tname" ]] && _taxes=""
    if [[ "$_tname" == "$scope_short" ]]; then
      target_suffix=" ${_taxes}"
    else
      target_suffix=" target=${_tname} ${_taxes}"
    fi
    target_suffix="${target_suffix% }"
  fi
  if declare -F _uic_scope_active >/dev/null 2>&1 && ! _uic_scope_active "$scope"; then
    printf '[GATE]  %-36s skip  [%s/%s] →%s%s\n' "$name" "$blocking" "$class" "$scope_short" "$target_suffix"
    return 0
  fi
  if $cond 2>/dev/null; then
    printf '[GATE]  %-36s ok    [%s/%s] →%s%s\n' "$name" "$blocking" "$class" "$scope_short" "$target_suffix"
    return 0
  else
    printf '[GATE]  %-36s WARN  [%s/%s] →%s%s\n' "$name" "$blocking" "$class" "$scope_short" "$target_suffix"
    if [[ "$blocking" == "hard" ]]; then
      log_warn "UIC hard gate '$name' failed — scope=$scope, failure_class=permanent"
    fi
    return 1
  fi
}

# ============================================================
#  uic_resolve — evaluate all gates, print preference report
#
#  Returns:
#    0  all hard gates satisfied, no undeclared required preferences
#    1  one or more hard gates failed
#    2  soft gate failures only
# ============================================================
uic_resolve() {
  local exit_code=0 i

  echo ""
  echo "  UIC Pre-Convergence Resolution"
  echo "  ──────────────────────────────────────────────────────"

  # Steps 1+2: Gates — always show all with their result
  for i in "${!_UIC_GATE_NAMES[@]}"; do
    local blocking="${_UIC_GATE_BLOCKS[$i]}"
    if ! _uic_eval_gate "$i"; then
      if [[ "$blocking" == "hard" ]]; then
        _UIC_FAILED_HARD+=("${_UIC_GATE_NAMES[$i]}")
        exit_code=1
      else
        _UIC_FAILED_SOFT+=("${_UIC_GATE_NAMES[$i]}")
        [[ $exit_code -eq 0 ]] && exit_code=2
      fi
    fi
  done

  # Steps 3+4: Preferences — all loaded prefs are relevant (filtered at load time)
  echo ""
  for i in "${!_UIC_PREF_NAMES[@]}"; do
    local name="${_UIC_PREF_NAMES[$i]}"
    local val="${_UIC_PREF_VALUES[$i]}"
    local default="${_UIC_PREF_DEFAULTS[$i]}"
    local opts="${_UIC_PREF_OPTIONS[$i]}"
    local rationale="${_UIC_PREF_RATIONALES[$i]}"
    local scope="${_UIC_PREF_SCOPES[$i]}"
    local scope_short="${scope/component:/}"
    if [[ "$val" != "$default" ]]; then
      printf '[PREF]  %-30s %-18s →%-20s options: %s\n' "$name" "${val} *" "$scope_short" "$opts"
    else
      printf '[PREF]  %-30s %-18s →%-20s options: %s\n' "$name" "$val" "$scope_short" "$opts"
    fi
    printf '        # %s\n' "$rationale"
  done
  [[ -f "$UIC_PREF_FILE" ]] && echo "  Preferences file: $UIC_PREF_FILE  [operator overrides active]"

  echo ""
  if [[ $exit_code -eq 0 ]]; then
    echo "  resolution: PASS"
  elif [[ $exit_code -eq 1 ]]; then
    echo "  resolution: FAIL — hard gate failure"
  else
    echo "  resolution: WARN — ${#_UIC_FAILED_SOFT[@]} soft gate(s) not satisfied"
  fi
  echo ""

  return $exit_code
}

# ============================================================
#  uic_export — export resolved values as env vars for subshells
#  Call immediately after uic_resolve
# ============================================================
uic_export() {
  local i key

  # Export gate failures
  for gate in "${_UIC_FAILED_HARD[@]+"${_UIC_FAILED_HARD[@]}"}"; do
    key="$(_uic_gate_key "$gate")"
    export "${key}=1"
  done
  for gate in "${_UIC_FAILED_SOFT[@]+"${_UIC_FAILED_SOFT[@]}"}"; do
    key="$(_uic_gate_key "$gate")"
    export "${key}=1"
  done

  # Export resolved preferences
  for i in "${!_UIC_PREF_NAMES[@]}"; do
    key="$(_uic_pref_key "${_UIC_PREF_NAMES[$i]}")"
    export "${key}=${_UIC_PREF_VALUES[$i]}"
  done
}

# ============================================================
#  uic_write_template — write a preferences override template
# ============================================================
uic_write_template() {
  local target="${1:-${UIC_PREF_FILE}.template}"
  mkdir -p "$(dirname "$target")"
  {
    printf '# UIC Preferences — Mac Mini AI Setup\n'
    printf '# Generated : %s\n' "$(date)"
    printf '# Defaults  : globally safest choices (conservative, reversible, non-destructive)\n'
    printf '# To activate overrides:\n'
    printf '#   cp %s %s\n' "$target" "$UIC_PREF_FILE"
    printf '#   edit the file, uncomment and change desired values\n'
    printf '\n'
    local i
    for i in "${!_UIC_PREF_NAMES[@]}"; do
      local name="${_UIC_PREF_NAMES[$i]}"
      local default="${_UIC_PREF_DEFAULTS[$i]}"
      local opts="${_UIC_PREF_OPTIONS[$i]}"
      local rationale="${_UIC_PREF_RATIONALES[$i]}"
      local scope="${_UIC_PREF_SCOPES[$i]}"
      local key
      key=$(echo "${name//-/_}" | tr '[:lower:]' '[:upper:]')
      printf '# %-30s [scope=%s]\n' "$name" "$scope"
      printf '# Options   : %s\n' "$opts"
      printf '# Rationale : %s\n' "$rationale"
      printf '#%s=%s\n' "$key" "$default"
      printf '\n'
    done
  } > "$target"
  log_info "UIC preferences template written to: $target"
  log_info "Edit and rename to $UIC_PREF_FILE to activate overrides"
}

# ── YAML loaders (called from install.sh) ─────────────────────────────────────

load_uic_gates() {
  local dir="$1"
  local gates_file="$dir/policy/gates.yaml"
  local name="" condition="" scope="" class="" target_state="" blocking=""
  [[ -f "$gates_file" ]] || return 0
  while IFS= read -r _line; do
    case "$_line" in
      "  - name: "*)
        if [[ -n "$name" ]]; then
          uic_gate --name "$name" --condition "$condition" \
            --scope "${scope:-global}" --class "${class:-readiness}" \
            --target-state "$target_state" --blocking "${blocking:-hard}"
        fi
        name="${_line#  - name: }"; condition=""; scope="global"
        class="readiness"; target_state=""; blocking="hard" ;;
      "    condition: "*)   condition="${_line#    condition: }" ;;
      "    scope: "*)       scope="${_line#    scope: }" ;;
      "    class: "*)       class="${_line#    class: }" ;;
      "    target_state: "*)target_state="${_line#    target_state: }" ;;
      "    blocking: "*)    blocking="${_line#    blocking: }" ;;
    esac
  done < "$gates_file"
  [[ -n "$name" ]] && uic_gate --name "$name" --condition "$condition" \
    --scope "${scope:-global}" --class "${class:-readiness}" \
    --target-state "$target_state" --blocking "${blocking:-hard}"
}

_uic_unquote_scalar() {
  local value="$1"
  case "$value" in
    \"*\") value="${value#\"}"; value="${value%\"}" ;;
    \'*\') value="${value#\'}"; value="${value%\'}" ;;
  esac
  printf '%s' "$value"
}

# Parse preferences from a YAML file's preferences: section using Python.
# Outputs tab-separated: name\tdefault\toptions\trationale
_uic_parse_prefs_from_yaml() {
  local yaml_file="$1"
  [[ -f "$yaml_file" ]] || return 0
  python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
for p in data.get('preferences', []):
    if not isinstance(p, dict): continue
    d = p.get('default','')
    if isinstance(d, bool): d = str(d).lower()
    print('{}\t{}\t{}\t{}'.format(
        p.get('name',''), d, p.get('options',''), p.get('rationale','')))
" "$yaml_file" 2>/dev/null || true
}

load_uic_preferences() {
  local dir="$1"
  local _pref_names=() _pref_defaults=() _pref_options=() _pref_rationales=()

  # 1. Global preferences from policy
  while IFS=$'\t' read -r _n _d _o _r; do
    [[ -n "$_n" ]] || continue
    _pref_names+=("$_n"); _pref_defaults+=("$_d")
    _pref_options+=("$_o"); _pref_rationales+=("$_r")
  done < <(_uic_parse_prefs_from_yaml "$dir/policy/preferences.yaml")

  # 2. Component preferences from selected component YAMLs
  local _sel_comps="${UCC_SELECTED_COMPS:-}"
  for _comp in ${TO_RUN[@]+"${TO_RUN[@]}"}; do
    [[ "${_sel_comps}" == *"${_comp}|"* ]] || continue
    for _yaml in "$dir"/ucc/software/*.yaml "$dir"/ucc/system/*.yaml; do
      [[ -f "$_yaml" ]] || continue
      local _ycomp; _ycomp="$(head -1 "$_yaml" | sed 's/^component: //')"
      [[ "$_ycomp" == "$_comp" ]] || continue
      while IFS=$'\t' read -r _n _d _o _r; do
        [[ -n "$_n" ]] || continue
        _pref_names+=("$_n"); _pref_defaults+=("$_d")
        _pref_options+=("$_o"); _pref_rationales+=("$_r")
      done < <(_uic_parse_prefs_from_yaml "$_yaml")
      break
    done
  done

  # 3. Call uic_preference with stdin free
  for _i in "${!_pref_names[@]}"; do
    uic_preference --name "${_pref_names[$_i]}" --default "${_pref_defaults[$_i]}" \
      --options "${_pref_options[$_i]}" --rationale "${_pref_rationales[$_i]}" \
      --scope "global"
  done
}

# ── Global state display helpers ──────────────────────────────────────────────

uic_global_state_label() {
  if [[ ${#_UIC_FAILED_HARD[@]} -gt 0 ]]; then printf 'Blocked'
  elif [[ ${#_UIC_FAILED_SOFT[@]} -gt 0 ]]; then printf 'Degraded'
  else printf 'Ready'
  fi
}

uic_global_state_detail() {
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

# ── Hard gate abort helper ────────────────────────────────────────────────────

abort_on_global_hard_gate() {
  local _gi _gkey
  for _gi in "${!_UIC_GATE_NAMES[@]}"; do
    [[ "${_UIC_GATE_BLOCKS[$_gi]}" == "hard" ]]  || continue
    [[ "${_UIC_GATE_SCOPES[$_gi]}" == "global" ]] || continue
    _gkey="$(_uic_gate_key "${_UIC_GATE_NAMES[$_gi]}")"
    if [[ "${!_gkey:-}" == "1" ]]; then
      log_error "UIC global hard gate '${_UIC_GATE_NAMES[$_gi]}' failed — convergence aborted (run --preflight for details)"
    fi
  done
}
