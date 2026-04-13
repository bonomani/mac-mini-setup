#!/usr/bin/env bash
# lib/ucc_brew.sh — Brew package outdated cache and observe helpers
# Sourced by lib/ucc.sh

# Populated once in install.sh; exported so component subshells
# can read it without repeating the network call.
brew_cache_versions() {
  export _BREW_VERSIONS_CACHE
  export _BREW_CASK_VERSIONS_CACHE
  _BREW_VERSIONS_CACHE=$(brew list --versions 2>/dev/null || true)
  _BREW_CASK_VERSIONS_CACHE=$(brew list --cask --versions 2>/dev/null || true)
}

brew_cache_outdated() {
  export _BREW_OUTDATED_CACHE
  export _BREW_CASK_OUTDATED_CACHE
  export _BREW_CASK_OUTDATED_GREEDY_AUTO_UPDATES_CACHE
  brew_cache_versions
  _BREW_OUTDATED_CACHE=$(brew outdated --quiet 2>/dev/null || true)
  _BREW_CASK_OUTDATED_CACHE=$(brew outdated --cask --quiet 2>/dev/null || true)
  _BREW_CASK_OUTDATED_GREEDY_AUTO_UPDATES_CACHE=$(brew outdated --cask --greedy-auto-updates --quiet 2>/dev/null || true)
  brew_cache_livecheck
}

# Cross-check installed formulae against upstream via `brew livecheck`.
# Catches releases that are newer than the formula in Homebrew (formula lag).
# Opt-in via UIC_PREF_UPSTREAM_CHECK=1 because livecheck is network-bound and slow.
# Output format from `brew livecheck --quiet --newer-only --installed`:
#   <name> : <installed> ==> <latest>
brew_cache_livecheck() {
  export _BREW_LIVECHECK_CACHE=""
  [[ "${UIC_PREF_UPSTREAM_CHECK:-0}" == "1" ]] || return 0
  _BREW_LIVECHECK_CACHE=$(brew livecheck --quiet --newer-only --installed 2>/dev/null || true)
}

# Match a formula or cask short name in the livecheck cache.
_brew_livecheck_is_outdated() {
  local pkg="${1##*/}"
  [[ -n "${_BREW_LIVECHECK_CACHE:-}" ]] || return 1
  echo "${_BREW_LIVECHECK_CACHE}" | awk -F' *: *' -v p="$pkg" '$1==p{found=1} END{exit !found}'
}

brew_refresh_caches() {
  if [[ "${UIC_PREF_TOOL_UPDATE:-always-upgrade}" == "always-upgrade" ]]; then
    brew_cache_outdated
  else
    brew_cache_versions
  fi
}

# Match short name ("ariaflow") or full tap name ("bonomani/ariaflow/ariaflow")
_brew_is_outdated() { echo "${_BREW_OUTDATED_CACHE:-}" | grep -qE "(^|/)${1}$"; }

_brew_flag_true() {
  case "${1:-false}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

_brew_cask_is_outdated() {
  local cache="${_BREW_CASK_OUTDATED_CACHE:-}"
  if _brew_flag_true "${2:-false}"; then
    cache="${_BREW_CASK_OUTDATED_GREEDY_AUTO_UPDATES_CACHE:-}"
  fi
  echo "$cache" | grep -qE "(^|/)${1}$"
}

# Return 0 if the given brew service is in 'started' state.
# Usage: brew_service_is_started <service_name>
# Accepts full tap refs (e.g. bonomani/ariaflow/ariaflow → ariaflow).
brew_service_is_started() {
  local svc="${1##*/}"
  brew services list 2>/dev/null | awk -v svc="$svc" '$1==svc {print $2}' | grep -q '^started$'
}

# Generic observe helpers — return: absent | outdated | current
# Respect UIC_PREF_TOOL_UPDATE / UIC_PREF_LIB_UPDATE based on update_class.
# Optional second arg: update_class (tool|lib, default: tool).
# brew_cask_is_installed is defined in lib/utils.sh
# which is always sourced before these helpers are called.
# Lookup version from cache (no brew subprocess)
# Strip tap prefix for cache lookup: brew list --versions emits short names,
# but driver.ref may carry a tap (e.g. anomalyco/tap/opencode → opencode).
_brew_cached_version()      { local p="${1##*/}"; echo "${_BREW_VERSIONS_CACHE:-}"      | awk -v p="$p" '$1==p{print $NF}'; }
_brew_cask_cached_version() { local p="${1##*/}"; echo "${_BREW_CASK_VERSIONS_CACHE:-}" | awk -v p="$p" '$1==p{v=$NF; sub(/,.*$/,"",v); print v}'; }

# Return the effective update policy for a given update_class.
_brew_update_policy_for_class() {
  case "${1:-tool}" in
    lib) printf '%s' "${UIC_PREF_LIB_UPDATE:-install-only}" ;;
    *)   printf '%s' "${UIC_PREF_TOOL_UPDATE:-always-upgrade}" ;;
  esac
}

brew_observe() {
  local pkg="$1" update_class="${2:-tool}" ver
  # Use version cache for presence check — avoids `brew list <pkg>` subprocess
  ver=$(_brew_cached_version "$pkg")
  [[ -z "$ver" ]] && { echo "absent"; return; }
  if [[ "$(_brew_update_policy_for_class "$update_class")" == "always-upgrade" ]]; then
    _brew_is_outdated "$pkg" && { echo "outdated"; return; }
  fi
  echo "$ver"
}

brew_cask_observe() {
  local pkg="$1" greedy_auto_updates="${2:-false}" update_class="${3:-tool}" ver
  ver=$(_brew_cask_cached_version "$pkg")
  [[ -z "$ver" ]] && { echo "absent"; return; }
  if [[ "$(_brew_update_policy_for_class "$update_class")" == "always-upgrade" ]]; then
    _brew_cask_is_outdated "$pkg" "$greedy_auto_updates" && { echo "outdated"; return; }
  fi
  echo "$ver"
}

# Post-process a brew observe state with `brew livecheck` results.
# If `brew outdated` says current but livecheck found a newer upstream release,
# return "outdated". Otherwise pass-through.
# Reads driver.ref and update_class to identify the package and policy.
_ucc_brew_state_with_upstream() {
  local cfg_dir="$1" yaml="$2" target="$3" state="$4"
  if [[ "$state" == "absent" || "$state" == "outdated" ]]; then
    printf '%s' "$state"; return
  fi
  local update_class
  update_class="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "update_class" 2>/dev/null || true)"
  if [[ "$(_brew_update_policy_for_class "${update_class:-tool}")" != "always-upgrade" ]]; then
    printf '%s' "$state"; return
  fi
  local ref
  ref="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref" 2>/dev/null || true)"
  [[ -n "$ref" ]] || { printf '%s' "$state"; return; }
  if _brew_livecheck_is_outdated "$ref"; then
    printf 'outdated'; return
  fi
  printf '%s' "$state"
}
