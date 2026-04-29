#!/usr/bin/env bash
# lib/utils_migration.sh — preferred-driver migration safety policy.
#
# Extracted from lib/utils.sh on 2026-04-29 (PLAN refactor #4, slice 2).
# Sourced from utils.sh; consumers (drivers + handle_unmanaged_brew_package
# + brew_cask_migrate_install) keep working unchanged.

# ── Migration safety probes ───────────────────────────────────────────────────
# Per-process cache: lines of "<owner>:<ref>\t<verdict>\t<evidence>"
_MIGRATION_SAFETY_CACHE=""

# Echoes "safe" or "destructive". Cached per (owner, ref).
# Side-effect: emits one log_info line on first assessment with the evidence.
_assess_migration_safety() {
  local owner="$1" ref="$2"
  local key="${owner}:${ref}" cached
  cached=$(printf '%s\n' "$_MIGRATION_SAFETY_CACHE" \
    | awk -F'\t' -v k="$key" '$1==k{print $2; exit}')
  if [[ -n "$cached" ]]; then
    printf '%s' "$cached"
    return
  fi
  local fn="_migration_safety_${owner//-/_}"
  local verdict evidence
  if declare -f "$fn" >/dev/null 2>&1; then
    # Probe must echo "<verdict>\t<evidence>"
    local out; out="$("$fn" "$ref")"
    verdict="${out%%	*}"
    evidence="${out#*	}"
  else
    verdict=destructive
    evidence="unknown owner"
  fi
  [[ "$verdict" != "safe" && "$verdict" != "destructive" ]] && verdict=destructive
  _MIGRATION_SAFETY_CACHE="${_MIGRATION_SAFETY_CACHE:+${_MIGRATION_SAFETY_CACHE}
}${key}	${verdict}	${evidence}"
  log_info "migration-safety: ${owner}/${ref} → ${verdict} (${evidence})"
  printf '%s' "$verdict"
}

# brew formula probe
_migration_safety_brew() {
  local ref="$1"
  local dependents services sysetc plists orphan_risk
  dependents="$(brew uses --installed --recursive "$ref" 2>/dev/null | head -1)"
  # Orphan check: would removing <ref> leave critical leaves (e.g. node) with
  # no dependents? Those are exactly what `brew autoremove` would purge.
  # Even with HOMEBREW_NO_AUTOREMOVE=1 in our migrator, we err on the side of
  # caution: if removing <ref> would orphan node/python/git/etc., classify
  # destructive so the user explicitly opts in.
  orphan_risk=""
  local crit
  for crit in node python python@3 git ruby; do
    brew list --formula "$crit" >/dev/null 2>&1 || continue
    # Is <crit> only depended on by <ref> (transitively)?
    local users
    users="$(brew uses --installed --recursive "$crit" 2>/dev/null | grep -vxF "$ref" | head -1)"
    if [[ -z "$users" ]]; then
      orphan_risk="$crit"
      break
    fi
  done
  services="$(brew services list 2>/dev/null | awk -v r="$ref" '$1==r{print; exit}')"
  local prefix; prefix="$(brew --prefix 2>/dev/null)"
  sysetc=""
  if [[ -n "$prefix" && -d "$prefix/etc/$ref" ]]; then
    [[ -n "$(ls -A "$prefix/etc/$ref" 2>/dev/null)" ]] && sysetc="$prefix/etc/$ref"
  fi
  plists=""
  if [[ -n "$prefix" ]]; then
    plists="$(grep -lr --include='*.plist' -F "$prefix/opt/$ref" \
      /Library/LaunchDaemons /Library/LaunchAgents "$HOME/Library/LaunchAgents" 2>/dev/null | head -1)"
  fi
  if [[ -z "$dependents" && -z "$services" && -z "$sysetc" && -z "$plists" && -z "$orphan_risk" ]]; then
    printf 'safe\tdependents=0 services=none system_config=none launchd=none orphans=none'
  else
    local why=""
    [[ -n "$dependents" ]]  && why+="dependents "
    [[ -n "$services" ]]    && why+="brew-services "
    [[ -n "$sysetc" ]]      && why+="system-config "
    [[ -n "$plists" ]]      && why+="launchd "
    [[ -n "$orphan_risk" ]] && why+="would-orphan=${orphan_risk} "
    printf 'destructive\t%s' "${why% }"
  fi
}

# brew cask probe — always destructive (system-wide /Applications, kexts, etc.)
_migration_safety_brew_cask() {
  printf 'destructive\t/Applications scope'
}

# unknown / curl-installed probe — never auto-migrate
_migration_safety_external() {
  printf 'destructive\tunknown footprint'
}

# Resolve effective safety: probe + per-target YAML override.
# Usage: _migration_safety_for_target <cfg_dir> <yaml> <target> <owner> <ref>
_migration_safety_for_target() {
  local cfg_dir="$1" yaml="$2" target="$3" owner="$4" ref="$5"
  local override
  override="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.migration_safety" 2>/dev/null || true)"
  if [[ -n "$override" && "$override" != "auto" ]]; then
    log_info "migration-safety: ${target} pinned to '${override}' via driver.migration_safety"
    printf '%s' "$override"
    return
  fi
  _assess_migration_safety "$owner" "$ref"
}

brew_cask_migrate_install() {
  local pkg="$1"
  ucc_run brew install --cask --force "$pkg" || return $?
  brew_refresh_caches 2>/dev/null || true
}

# Detect install source for a CLI binary: brew (formula), brew-cask, external, or absent.
# Usage: cli_install_source <binary> [brew_formula]
cli_install_source() {
  local bin="$1" formula="${2:-}"
  if ! command -v "$bin" >/dev/null 2>&1; then
    printf 'absent'
  elif [[ -n "$formula" ]] && is_installed brew && brew list "$formula" >/dev/null 2>&1; then
    printf 'brew'
  else
    printf 'external'
  fi
}

# Add a target to the per-target preferred-driver ignore list.
# Persists to ~/.ai-stack/target-overrides.yaml.
_preferred_driver_ignore_add() {
  local target="$1"
  local overrides_file="${UIC_PREF_FILE%/*}/target-overrides.yaml"
  mkdir -p "$(dirname "$overrides_file")"
  python3 -c "
import yaml, sys, os
path, target = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    with open(path) as f:
        data = yaml.safe_load(f) or {}
ignored = data.get('preferred-driver-ignore') or []
if target not in ignored:
    ignored.append(target)
    data['preferred-driver-ignore'] = ignored
    with open(path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)
" "$overrides_file" "$target" 2>/dev/null
}

# Handle a CLI tool installed outside brew.
# Per-target ignore list overrides the global preferred-driver-policy.
# In interactive mode, prompts the user inline with migrate/ignore/warn choices.
# Usage: handle_unmanaged_brew_package <formula> <display_name>
handle_unmanaged_brew_package() {
  local formula="$1" display_name="${2:-$1}"
  # Check per-target ignore list first
  if [[ -n "${UCC_PREFERRED_DRIVER_IGNORED:-}" && "${UCC_PREFERRED_DRIVER_IGNORED}" == *"|${formula}|"* ]]; then
    return 0
  fi
  # Interactive mode: prompt inline
  if [[ "${UCC_INTERACTIVE:-0}" == "1" && -c /dev/tty ]]; then
    printf '\n  [?] %s is installed outside brew, but the preferred driver is brew.\n' "$display_name"
    printf '      Options:\n'
    printf '        1) migrate — uninstall and reinstall via brew (this run only)\n'
    printf '        2) ignore  — accept the current install permanently (saved)\n'
    printf '       *3) warn    — show this warning again next run\n'
    printf '      → '
    local _choice; read -r _choice < /dev/tty
    case "$_choice" in
      1)
        sudo_is_available || { log_warn "Migrating ${display_name} requires admin; run: sudo -v"; return 125; }
        ucc_run brew install "$formula" || return 1
        return 0
        ;;
      2)
        _preferred_driver_ignore_add "$formula"
        UCC_PREFERRED_DRIVER_IGNORED="${UCC_PREFERRED_DRIVER_IGNORED}${formula}|"
        export UCC_PREFERRED_DRIVER_IGNORED
        log_info "${display_name} added to ignore list (~/.ai-stack/target-overrides.yaml)"
        return 0
        ;;
      *)
        log_warn "${display_name} installed outside brew. Will ask again next run."
        return 124
        ;;
    esac
  fi
  # Non-interactive: fall back to global policy
  local policy="${UIC_PREF_PREFERRED_DRIVER_POLICY:-warn}"
  case "$policy" in
    ignore)
      log_info "${display_name} installed outside brew; ignoring (policy=ignore)."
      return 0
      ;;
    warn)
      log_warn "${display_name} installed outside brew. To migrate: brew install ${formula} (or: ./install.sh --pref preferred-driver-policy=migrate ${formula})"
      return 124
      ;;
    migrate)
      sudo_is_available || { log_warn "Migrating ${display_name} requires admin; run: sudo -v"; return 125; }
      ucc_run brew install "$formula" || return 1
      ;;
    *)
      log_warn "Unknown preferred-driver-policy '$policy'; treating as warn."
      return 124
      ;;
  esac
}

