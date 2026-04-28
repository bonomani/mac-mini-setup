#!/usr/bin/env bash
# lib/uic_yaml.sh — UIC YAML loaders (gates + preferences).
#
# Extracted from lib/uic.sh on 2026-04-28 (PLAN refactor #6, slice 1).
# Sourced from lib/uic.sh after the gate/preference engine so loaders
# can call uic_gate / uic_preference unchanged.

# ── YAML loaders (called from install.sh) ─────────────────────────────────────

load_uic_gates() {
  local dir="$1"
  local gates_file="$dir/defaults/gates.yaml"
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
#
# Platform filtering: prefs are skipped when the current HOST_PLATFORM isn't
# in their applicable set. Sources of the applicable set (first match wins):
#   1. The pref's own `platforms:` list (e.g. pytorch-device on macos only).
#   2. The file's top-level `platforms:` list (e.g. all docker-* on macos).
#   3. All platforms if neither is declared.
_uic_parse_prefs_from_yaml() {
  local yaml_file="$1"
  [[ -f "$yaml_file" ]] || return 0
  python3 -c "
import yaml, sys, os
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
host = os.environ.get('HOST_PLATFORM', '')
variant = os.environ.get('HOST_PLATFORM_VARIANT', '')
# Match rule mirrors install.sh _component_supported_for:
#   platform == HOST_PLATFORM_VARIANT   (e.g. wsl2)
#   platform == HOST_PLATFORM           (e.g. wsl)
#   platform == 'linux' and HOST_PLATFORM == 'wsl'  (wsl→linux fallback)
def host_matches(platforms):
    if not platforms:
        return True
    for p in platforms:
        if p == variant or p == host:
            return True
        if p == 'linux' and host == 'wsl':
            return True
    return False
file_platforms = data.get('platforms') or []
file_ok = host_matches(file_platforms)
for p in data.get('preferences', []):
    if not isinstance(p, dict): continue
    pref_platforms = p.get('platforms') or []
    # Per-pref platforms override file-level when declared.
    applies = host_matches(pref_platforms) if pref_platforms else file_ok
    if not applies:
        continue
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
  done < <(_uic_parse_prefs_from_yaml "$dir/defaults/preferences.yaml")

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

  # 3. Build set of UIC_PREF_* env vars referenced by selected component lib files
  # (only when explicit targets are given — for full runs, all prefs are relevant)
  #
  # `libs:` in component YAML is a space-separated list (e.g.
  # `libs: ai_apps ollama_models` or `libs: docker docker_unattended`);
  # install.sh sources them via unquoted word-split `for _lib in $_libs`.
  # We must use the same whitespace-splitting semantics here — using
  # `IFS=','` would collapse a multi-lib value into a single array
  # element like "docker docker_unattended", the file-exists check
  # would fail, and _referenced_prefs would come back empty. That in
  # turn filters out every component pref from the [PREF] display
  # (the pref-not-in-referenced-set branch at line ~546 skips the
  # declaration entirely when no lib references it).
  local _referenced_prefs=""
  if [[ "${UCC_EXPLICIT_TARGETS:-0}" == "1" ]]; then
    local _comp _libs _lib
    for _comp in ${TO_RUN[@]+"${TO_RUN[@]}"}; do
      [[ "${_sel_comps}" == *"${_comp}|"* ]] || continue
      _libs="$(printf '%s\n' "${_all_dispatch:-}" | awk -F'\t' -v c="$_comp" '$1==c{print $2; exit}')"
      # Unquoted $_libs to word-split on whitespace — matches install.sh
      # convention. Space/tab/newline all produce a separate array entry.
      for _lib in $_libs; do
        [[ -f "$dir/lib/${_lib}.sh" ]] || continue
        _referenced_prefs+="$(grep -oE 'UIC_PREF_[A-Z_]+' "$dir/lib/${_lib}.sh" 2>/dev/null | sort -u | tr '\n' '|' || true)"
      done
    done
  fi

  # 4. Call uic_preference with stdin free
  for _i in "${!_pref_names[@]}"; do
    local _pname="${_pref_names[$_i]}"
    # default-selection only matters when no explicit targets were given
    if [[ "$_pname" == "default-selection" && "${UCC_EXPLICIT_TARGETS:-0}" == "1" ]]; then
      continue
    fi
    # preferred-driver-policy is handled inline when drift is detected
    # (per-target, on demand). Resolve as non-interactive so it picks up
    # env/file/default without prompting upfront.
    if [[ "$_pname" == "preferred-driver-policy" ]]; then
      local _saved_interactive="${UCC_INTERACTIVE:-0}"
      UCC_INTERACTIVE=0
      uic_preference --name "${_pref_names[$_i]}" --default "${_pref_defaults[$_i]}" \
        --options "${_pref_options[$_i]}" --rationale "${_pref_rationales[$_i]}" \
        --scope "global"
      UCC_INTERACTIVE="$_saved_interactive"
      continue
    fi
    # When explicit targets are given, scope preferences to those used by selected components.
    # Always-relevant prefs bypass scoping.
    if [[ "${UCC_EXPLICIT_TARGETS:-0}" == "1" ]]; then
      case "$_pname" in
        skip-display-mode) ;;  # always relevant — controls output verbosity
        *)
          local _env_key
          _env_key="UIC_PREF_$(echo "${_pname//-/_}" | tr '[:lower:]' '[:upper:]')"
          [[ "$_referenced_prefs" == *"${_env_key}|"* ]] || continue
          ;;
      esac
    fi
    uic_preference --name "${_pref_names[$_i]}" --default "${_pref_defaults[$_i]}" \
      --options "${_pref_options[$_i]}" --rationale "${_pref_rationales[$_i]}" \
      --scope "global"
  done
}
