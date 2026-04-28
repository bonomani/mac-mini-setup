#!/usr/bin/env bash
# lib/utils_cache.sh — disk cache with TTL for slow network checks.
#
# Extracted from lib/utils.sh on 2026-04-28 (PLAN refactor #4, slice 1).
# Sourced from utils.sh; consumers (brew livecheck, pip outdated, etc.)
# call _ucc_cache_fresh / _read / _write / _invalidate / _invalidate_glob
# unchanged.

# ── Disk cache with TTL (network check results) ───────────────────────────────
# Caches slow network-bound command output under ~/.ai-stack/cache/ with a TTL.
# Used to avoid re-running `brew livecheck`, `pip list --outdated`, etc. on
# every invocation when the answer rarely changes.
#
# UCC_CACHE_DIR defaults to ~/.ai-stack/cache
# UCC_CACHE_TTL_MIN defaults to 60 minutes
#
# Bypass the cache by setting UCC_NO_CACHE=1 (forces refresh).
#
# ── Subshell cache discipline ─────────────────────────────────────────────────
# In-memory cache vars (e.g. _BREW_VERSIONS_CACHE, _PIP_OUTDATED_CACHE,
# _NPM_GLOBAL_VERSIONS_CACHE, _PIPX_CACHE, _PKG_*_OUTDATED_CACHE) MUST be
# `export`ed (or use `declare -g`). The framework calls observe functions
# inside subshells via `observed=$($observe_fn)`. Vars set inside a subshell
# are NOT visible to the parent — so a non-exported cache populated in
# observe is invisible to the next observe and gets re-computed.
#
# This caused regression #38: pip-outdated cache populated in subshell,
# action invalidation only touched the (empty) parent var, then verify
# re-ran observe in another subshell which re-populated from disk where
# the pre-upgrade snapshot was still fresh. Fix: invalidate the disk cache
# in the action (parent shell) so the verify subshell finds it stale.
#
# Audit confirmed (2026-04-15): all session-level caches in lib/ucc_brew.sh,
# lib/drivers/{pip,pkg,package,npm,pip_bootstrap}.sh use `export` correctly.
# `_PIP_ISO_KIND`/`_PIP_ISO_NAME` in pip.sh are intentionally locals (not
# cached across calls — re-parsed each time via `_pip_parse_isolation`).

_ucc_cache_dir() {
  printf '%s' "${UCC_CACHE_DIR:-$HOME/.ai-stack/cache}"
}

_ucc_cache_path() {
  printf '%s/%s' "$(_ucc_cache_dir)" "$1"
}

# Return 0 if cache file exists and is younger than TTL (default 60 min).
_ucc_cache_fresh() {
  local path="$1"
  local ttl="${2:-${UCC_CACHE_TTL_MIN:-60}}"
  [[ "${UCC_NO_CACHE:-0}" == "1" ]] && return 1
  [[ -f "$path" ]] || return 1
  # find -mmin -N → modified within the last N minutes
  [[ -n "$(find "$path" -mmin "-$ttl" 2>/dev/null | head -1)" ]]
}

# Read cache content (caller must check freshness first).
_ucc_cache_read() {
  local path; path="$(_ucc_cache_path "$1")"
  [[ -f "$path" ]] && cat "$path"
}

# Write content (from stdin) to cache file, creating dir as needed.
_ucc_cache_write() {
  local path; path="$(_ucc_cache_path "$1")"
  mkdir -p "$(dirname "$path")" 2>/dev/null || return 1
  cat > "$path"
}

# Invalidate (delete) a cache file. Called after a state-changing action
# whose disk-cached observation would otherwise be stale (e.g. after
# `pip install --upgrade`, the cached `pip list --outdated` result is no
# longer accurate until it refreshes on next observe).
_ucc_cache_invalidate() {
  local path; path="$(_ucc_cache_path "$1")"
  rm -f "$path" 2>/dev/null || true
}

# Bulk invalidate caches matching a glob pattern. Useful for "wipe all
# upstream-check caches" or "reset everything" scenarios.
# Usage:
#   _ucc_cache_invalidate_glob 'pip-outdated-*'   # all pip outdated caches
#   _ucc_cache_invalidate_glob '*'                # nuke all caches
_ucc_cache_invalidate_glob() {
  local pattern="$1"
  local dir; dir="$(_ucc_cache_dir)"
  [[ -d "$dir" ]] || return 0
  # Use find to avoid shell-glob issues with no-match
  find "$dir" -maxdepth 1 -name "$pattern" -delete 2>/dev/null || true
}
