#!/usr/bin/env bash
# lib/drivers/pip.sh — driver.kind: pip
# driver.probe_pkg:       primary package to probe for presence/version
# driver.install_packages: space-separated list of packages to install/upgrade
# driver.min_version:     minimum required version (empty = no constraint)
# driver.isolation:       absent (global pip) | pipx | {kind: venv, name: <name>}
#                         pipx: each package installed into its own venv via
#                               pipx. No cross-package conflicts possible.
#                         venv: shared named venv via pyenv-virtualenv.
#                               Targets with the same name share one environment.

# Ensure pip + python are on PATH for non-interactive subshells.
# Falls back to the pyenv-managed interpreter when pyenv is set up.
_pip_ensure_path() {
  if command -v pip >/dev/null 2>&1; then
    return 0
  fi
  declare -f _pyenv_ensure_path >/dev/null 2>&1 && _pyenv_ensure_path 2>/dev/null || true
  command -v pip >/dev/null 2>&1 && return 0
  command -v python3 >/dev/null 2>&1 || return 1
  return 0  # python3 -m pip is the fallback path
}

# ── Isolation parsing ────────────────────────────────────────────────────────
# Sets _PIP_ISO_KIND (none|pipx|venv) and _PIP_ISO_NAME (venv name, empty for others).
# Supports both scalar (isolation: pipx) and object (isolation: {kind: venv, name: X}).
_pip_parse_isolation() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _PIP_ISO_KIND="none"
  _PIP_ISO_NAME=""
  local kind
  kind="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.isolation.kind" 2>/dev/null || true)"
  if [[ -n "$kind" ]]; then
    _PIP_ISO_KIND="$kind"
    _PIP_ISO_NAME="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.isolation.name" 2>/dev/null || true)"
    return
  fi
  local scalar
  scalar="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.isolation" 2>/dev/null || true)"
  [[ -n "$scalar" ]] && _PIP_ISO_KIND="$scalar"
}

# ── Venv isolation backend ───────────────────────────────────────────────────
# Uses pyenv-virtualenv to manage named venvs under ~/.pyenv/versions/<name>.

# Return the pip binary path for a named venv.
_pip_venv_pip_cmd() {
  local name="$1"
  local pyenv_root="${PYENV_ROOT:-$HOME/.pyenv}"
  printf '%s/versions/%s/bin/pip' "$pyenv_root" "$name"
}

# Return the python binary path for a named venv.
_pip_venv_python_cmd() {
  local name="$1"
  local pyenv_root="${PYENV_ROOT:-$HOME/.pyenv}"
  printf '%s/versions/%s/bin/python' "$pyenv_root" "$name"
}

# Install packages into a venv. Prefers uv (10-100x faster resolver/installer)
# when available, falls back to direct pip. Handles flag differences:
#   pip: install -q --upgrade-strategy only-if-needed [--upgrade] <pkgs>
#   uv:  pip install -q [--upgrade] <pkgs>   (uv's default resolver is
#        already "only-if-needed"; --upgrade-strategy flag doesn't exist)
# Usage: _pip_venv_install <name> [--upgrade] <pkgs...>
_pip_venv_install() {
  local name="$1"; shift
  local upgrade=""
  if [[ "$1" == "--upgrade" ]]; then upgrade="--upgrade"; shift; fi
  local py_path; py_path="$(_pip_venv_python_cmd "$name")"
  if command -v uv >/dev/null 2>&1; then
    ucc_run uv pip install --python "$py_path" -q $upgrade "$@"
  else
    local pip_path; pip_path="$(_pip_venv_pip_cmd "$name")"
    ucc_run "$pip_path" install -q --upgrade-strategy only-if-needed $upgrade "$@"
  fi
}

# Ensure venv exists; create via pyenv-virtualenv if absent. Idempotent.
_pip_venv_ensure() {
  local name="$1"
  local pip_path
  pip_path="$(_pip_venv_pip_cmd "$name")"
  [[ -x "$pip_path" ]] && return 0
  # Get the current pyenv global version as base
  local py_ver
  py_ver="$(pyenv global 2>/dev/null)" || py_ver=""
  [[ -n "$py_ver" ]] || { log_warn "pip/venv: no pyenv global version set"; return 1; }
  log_info "pip/venv: creating venv '$name' (python $py_ver)"
  ucc_run pyenv virtualenv "$py_ver" "$name" || return 1
  # Upgrade pip inside the fresh venv to suppress repeated upgrade notices
  "$pip_path" install -q --upgrade pip 2>/dev/null || true
}

# Run `pip check` inside a venv and warn on internal dependency conflicts.
# Cached per-process: each venv is checked at most once per run.
_pip_venv_check_conflicts() {
  local name="$1"
  local cache_var="_PIP_VENV_CHECKED_${name//[^a-zA-Z0-9]/_}"
  [[ -n "${!cache_var+x}" ]] && return 0
  export "$cache_var=1"
  _pip_venv_available "$name" || return 0
  local pip_path output
  pip_path="$(_pip_venv_pip_cmd "$name")"
  output="$("$pip_path" check 2>/dev/null || true)"
  if [[ -n "$output" ]] && ! printf '%s' "$output" | grep -q "No broken requirements found"; then
    log_warn "pip/venv '$name': dependency conflicts detected"
    printf '%s\n' "$output" | head -10 | while IFS= read -r line; do
      [[ -n "$line" ]] && log_warn "  ${line}"
    done
  fi
}

# True if the venv exists and has a working pip.
_pip_venv_available() {
  local name="$1"
  local pip_path
  pip_path="$(_pip_venv_pip_cmd "$name")"
  [[ -x "$pip_path" ]]
}

# ── Per-venv pip version cache ───────────────────────────────────────────────
# Each venv gets its own cache var: _PIP_VENV_CACHE_<sanitized_name>

_pip_venv_cache_var() {
  local name="$1"
  printf '_PIP_VENV_CACHE_%s' "${name//[^a-zA-Z0-9]/_}"
}

_pip_venv_cache_versions() {
  local name="$1"
  local pip_path var
  pip_path="$(_pip_venv_pip_cmd "$name")"
  var="$(_pip_venv_cache_var "$name")"
  export "$var"
  eval "$var=\"\$($pip_path list --format=json 2>/dev/null || echo '[]')\""
}

_pip_venv_cached_version() {
  local name="$1" pkg="$2"
  local var cache
  var="$(_pip_venv_cache_var "$name")"
  cache="${!var:-}"
  if [[ -z "$cache" ]]; then
    local pip_path
    pip_path="$(_pip_venv_pip_cmd "$name")"
    $pip_path show "$pkg" 2>/dev/null | awk '/^Version:/{print $2}'
    return
  fi
  python3 -c "
import sys, json
pkgs = json.load(sys.stdin)
name = sys.argv[1].lower().replace('-','_')
for p in pkgs:
    if p['name'].lower().replace('-','_') == name:
        print(p['version']); sys.exit(0)
" "$pkg" 2>/dev/null <<< "$cache"
}

# ── Per-venv outdated cache ──────────────────────────────────────────────────

_pip_venv_outdated_cache_var() {
  printf '_PIP_VENV_OUTDATED_%s' "${1//[^a-zA-Z0-9]/_}"
}

_pip_venv_outdated_cache_load() {
  local name="$1"
  [[ "${UIC_PREF_UPSTREAM_CHECK:-0}" == "1" ]] || return 1
  local var
  var="$(_pip_venv_outdated_cache_var "$name")"
  [[ -n "${!var+x}" ]] && return 0
  export "$var"
  local cache_key="pip-outdated-venv-${name//[^a-zA-Z0-9]/_}"
  local cache_path; cache_path="$(_ucc_cache_path "$cache_key")"
  if _ucc_cache_fresh "$cache_path"; then
    eval "$var=\"\$(_ucc_cache_read '$cache_key')\""
    return 0
  fi
  local pip_path
  pip_path="$(_pip_venv_pip_cmd "$name")"
  eval "$var=\"\$($pip_path list --outdated --format=json 2>/dev/null || true)\""
  printf '%s' "${!var}" | _ucc_cache_write "$cache_key"
  return 0
}

_pip_venv_pkgs_outdated() {
  local name="$1" pkgs="$2"
  [[ -n "$pkgs" ]] || return 1
  _pip_venv_outdated_cache_load "$name" || return 1
  local var cache
  var="$(_pip_venv_outdated_cache_var "$name")"
  cache="${!var:-}"
  [[ -n "$cache" ]] || return 1
  printf '%s' "$cache" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
outdated = {(p.get('name') or '').lower() for p in data}
wanted = set('$pkgs'.lower().split())
sys.exit(0 if wanted & outdated else 1)
" 2>/dev/null
}

# ── Global pip caches (unchanged) ────────────────────────────────────────────

# Cache `pip list --outdated --format=json` once per process; opt-in via
# UIC_PREF_UPSTREAM_CHECK=1 (network call, can be slow on big environments).
# Disk-cached under ~/.ai-stack/cache/pip-outdated-global (TTL 60min).
_pip_outdated_cache_load() {
  [[ "${UIC_PREF_UPSTREAM_CHECK:-0}" == "1" ]] || return 1
  [[ -n "${_PIP_OUTDATED_CACHE+x}" ]] && return 0
  export _PIP_OUTDATED_CACHE=""
  local cache_key="pip-outdated-global"
  local cache_path; cache_path="$(_ucc_cache_path "$cache_key")"
  if _ucc_cache_fresh "$cache_path"; then
    _PIP_OUTDATED_CACHE="$(_ucc_cache_read "$cache_key")"
    return 0
  fi
  local cmd="pip"
  command -v pip >/dev/null 2>&1 || cmd="python3 -m pip"
  _PIP_OUTDATED_CACHE="$($cmd list --outdated --format=json 2>/dev/null || true)"
  printf '%s' "$_PIP_OUTDATED_CACHE" | _ucc_cache_write "$cache_key"
  return 0
}

# True (0) if any of the space-separated packages is in pip's outdated list.
_pip_pkgs_outdated() {
  local pkgs="$1"
  [[ -n "$pkgs" ]] || return 1
  _pip_outdated_cache_load || return 1
  [[ -n "$_PIP_OUTDATED_CACHE" ]] || return 1
  printf '%s' "$_PIP_OUTDATED_CACHE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
outdated = {(p.get('name') or '').lower() for p in data}
wanted = set('$pkgs'.lower().split())
sys.exit(0 if wanted & outdated else 1)
" 2>/dev/null
}

# ── pipx isolation backend ───────────────────────────────────────────────────
_pipx_available() { command -v pipx >/dev/null 2>&1; }

# Cache `pipx list --json` once per process. Maps tool name → version.
_pipx_cache_load() {
  [[ -n "${_PIPX_CACHE+x}" ]] && return 0
  export _PIPX_CACHE=""
  _pipx_available || return 1
  _PIPX_CACHE="$(pipx list --json 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for name, info in (d.get('venvs') or {}).items():
    md = info.get('metadata') or {}
    pkg = (md.get('main_package') or {})
    ver = pkg.get('package_version', '')
    print(f'{name}\t{ver}')
" 2>/dev/null || true)"
}

_pipx_version() {
  local pkg="$1"
  _pipx_cache_load
  printf '%s\n' "${_PIPX_CACHE:-}" | awk -F'\t' -v p="$pkg" '$1==p{print $2; exit}'
}

# pipx outdated cache: pipx has no `outdated` json so we compare each tool's
# version against PyPI's latest via the same opt-in flag.
_pipx_outdated() {
  [[ "${UIC_PREF_UPSTREAM_CHECK:-0}" == "1" ]] || return 1
  local pkg="$1"
  local installed; installed="$(_pipx_version "$pkg")"
  [[ -n "$installed" ]] || return 1
  local latest
  latest="$(curl -fsS --max-time 5 "https://pypi.org/pypi/${pkg}/json" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('info',{}).get('version',''))" 2>/dev/null)"
  [[ -n "$latest" ]] || return 1
  [[ "$installed" != "$latest" ]] || return 1
  # any version difference (newer per pypi) → outdated
  declare -f _pkg_version_lt >/dev/null 2>&1 || return 1
  _pkg_version_lt "$installed" "$latest"
}

_pipx_install_pkgs() {
  local pkgs="$1" pkg
  for pkg in $pkgs; do
    pipx list --short 2>/dev/null | awk '{print $1}' | grep -qx "$pkg" || \
      ucc_run pipx install "$pkg" || return 1
  done
  unset _PIPX_CACHE
}

_pipx_upgrade_pkgs() {
  local pkgs="$1" pkg
  for pkg in $pkgs; do
    ucc_run pipx upgrade "$pkg" || return 1
  done
  unset _PIPX_CACHE
}

# ── Driver interface ─────────────────────────────────────────────────────────
_ucc_driver_pip_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _pip_parse_isolation "$cfg_dir" "$yaml" "$target"

  # ── pipx ──
  if [[ "$_PIP_ISO_KIND" == "pipx" ]]; then
    _pipx_available || { printf 'absent'; return; }
    local probe ver
    probe="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.probe_pkg")"
    [[ -n "$probe" ]] || return 1
    ver="$(_pipx_version "$probe")"
    [[ -z "$ver" ]] && { printf 'absent'; return; }
    if _pipx_outdated "$probe"; then
      printf 'outdated'
    else
      printf '%s' "$ver"
    fi
    return
  fi

  # ── venv ──
  if [[ "$_PIP_ISO_KIND" == "venv" ]]; then
    local vname="$_PIP_ISO_NAME"
    [[ -n "$vname" ]] || { log_warn "pip/venv: isolation.name missing for $target"; return 1; }
    _pip_venv_available "$vname" || { printf 'absent'; return; }
    local probe min_ver pkgs ver
    probe="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.probe_pkg")"
    [[ -n "$probe" ]] || return 1
    min_ver="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.min_version")"
    pkgs="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.install_packages")"
    ver="$(_pip_venv_cached_version "$vname" "$probe")"
    if [[ -z "$ver" ]]; then
      printf 'absent'
      return
    fi
    if [[ -n "$min_ver" ]]; then
      local py_path
      py_path="$(_pip_venv_python_cmd "$vname")"
      if ! $py_path -c \
        "from packaging.version import Version; import sys; raise SystemExit(0 if Version('$min_ver') <= Version(sys.argv[1]) else 1)" \
        "$ver" 2>/dev/null; then
        printf 'absent'
        return
      fi
    fi
    if _pip_venv_pkgs_outdated "$vname" "$pkgs"; then
      printf 'outdated'
    else
      printf '%s' "$ver"
    fi
    return
  fi

  # ── global pip (no isolation) ──
  _pip_ensure_path || { printf 'absent'; return; }
  local probe min_ver pkgs ver
  probe="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.probe_pkg")"
  [[ -n "$probe" ]] || return 1
  min_ver="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.min_version")"
  pkgs="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.install_packages")"
  ver="$(_pip_cached_version "$probe")"
  if [[ -z "$ver" ]]; then
    printf 'absent'
    return
  fi
  if [[ -n "$min_ver" ]]; then
    if ! python3 -c \
      "from packaging.version import Version; import sys; raise SystemExit(0 if Version('$min_ver') <= Version(sys.argv[1]) else 1)" \
      "$ver" 2>/dev/null; then
      printf 'absent'
      return
    fi
  fi
  if _pip_pkgs_outdated "$pkgs"; then
    printf 'outdated'
  else
    printf '%s' "$ver"
  fi
}

_ucc_driver_pip_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  _pip_parse_isolation "$cfg_dir" "$yaml" "$target"
  local pkgs update_class update_policy
  pkgs="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.install_packages")"
  [[ -n "$pkgs" ]] || return 1
  # Resolve update_class: pipx/venv-tool → default tool, pip/venv-lib → default lib
  update_class="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "update_class" 2>/dev/null || true)"
  if [[ -z "$update_class" ]]; then
    [[ "$_PIP_ISO_KIND" == "pipx" ]] && update_class="tool" || update_class="lib"
  fi
  case "$update_class" in
    lib) update_policy="${UIC_PREF_LIB_UPDATE:-install-only}" ;;
    *)   update_policy="${UIC_PREF_TOOL_UPDATE:-always-upgrade}" ;;
  esac

  # ── pipx ──
  if [[ "$_PIP_ISO_KIND" == "pipx" ]]; then
    if ! _pipx_available; then
      log_warn "pipx not available — install with: brew install pipx"
      return 1
    fi
    case "$action" in
      install) _pipx_install_pkgs "$pkgs" ;;
      update)
        [[ "$update_policy" == "install-only" ]] && return 0
        _pipx_upgrade_pkgs "$pkgs"
        ;;
    esac
    return $?
  fi

  # ── venv ──
  if [[ "$_PIP_ISO_KIND" == "venv" ]]; then
    local vname="$_PIP_ISO_NAME"
    [[ -n "$vname" ]] || { log_warn "pip/venv: isolation.name missing for $target"; return 1; }
    _pip_venv_ensure "$vname" || return 1
    # Conflict dry-run uses pip directly (uv has no equivalent dry-run format).
    local pip_cmd
    pip_cmd="$(_pip_venv_pip_cmd "$vname")"
    local rc=0
    case "$action" in
      install)
        _pip_venv_install "$vname" $pkgs \
          && _pip_venv_cache_versions "$vname"
        rc=$?
        ;;
      update)
        [[ "$update_policy" == "install-only" ]] && return 0
        if _pip_update_would_conflict "$pip_cmd" "$pkgs"; then
          return 0
        fi
        _pip_venv_install "$vname" --upgrade $pkgs \
          && _pip_venv_cache_versions "$vname"
        rc=$?
        ;;
    esac
    # Warn on internal conflicts (cached per-venv per-process)
    _pip_venv_check_conflicts "$vname"
    return $rc
  fi

  # ── global pip ──
  _pip_ensure_path || { log_warn "pip not available (no pyenv/python on PATH)"; return 1; }
  local pip_cmd
  if command -v pip >/dev/null 2>&1; then
    pip_cmd="pip"
  else
    pip_cmd="python3 -m pip"
  fi
  case "$action" in
    install)
      # Plain install: don't touch existing deps unless required by <pkgs>.
      ucc_run $pip_cmd install -q --upgrade-strategy only-if-needed $pkgs \
        && pip_cache_versions
      ;;
    update)
      # Respect update policy: lib-class targets skip upgrades under balanced.
      [[ "$update_policy" == "install-only" ]] && return 0
      # Non-destructive update: dry-run first; if the resolver would
      # leave any other already-installed package with an unsatisfied
      # constraint ("X requires Y<Z, but you have Y>=Z"), skip the
      # upgrade entirely and leave the current install untouched.
      # Outdated detection still flags the target so the operator
      # knows there's a pending update; only the *write* is gated.
      if _pip_update_would_conflict "$pip_cmd" "$pkgs"; then
        return 0
      fi
      ucc_run $pip_cmd install -q --upgrade --upgrade-strategy only-if-needed $pkgs \
        && pip_cache_versions
      ;;
  esac
}

# Return 0 (= would conflict) if a dry-run upgrade reports incompatibility
# warnings against any other installed package. Logs the offending lines.
_pip_update_would_conflict() {
  local pip_cmd="$1" pkgs="$2"
  local out conflicts
  out="$($pip_cmd install --dry-run --upgrade --upgrade-strategy only-if-needed -q $pkgs 2>&1 || true)"
  # pip prints lines like:
  #   unsloth 2026.4.4 requires torch<2.11.0,>=2.4.0, but you have torch 2.11.0 which is incompatible.
  conflicts="$(printf '%s\n' "$out" | grep -E '^[A-Za-z0-9._-]+ [^ ]+ requires .*which is incompatible\.$' || true)"
  [[ -z "$conflicts" ]] && return 1
  log_warn "pip update for [${pkgs}] would break existing packages; skipping (non-destructive)."
  printf '%s\n' "$conflicts" | head -5 | while IFS= read -r line; do
    log_warn "  ${line}"
  done
  log_warn "  Resolve manually with a coordinated upgrade, or relax the conflicting pins, then re-run."
  return 0
}

_ucc_driver_pip_recover() {
  local cfg_dir="$1" yaml="$2" target="$3" level="$4"
  _pip_parse_isolation "$cfg_dir" "$yaml" "$target"
  local pkgs
  pkgs="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.install_packages")"
  [[ -n "$pkgs" ]] || return 1

  # ── pipx ──
  if [[ "$_PIP_ISO_KIND" == "pipx" ]]; then
    _pipx_available || return 1
    case "$level" in
      1) _pipx_upgrade_pkgs "$pkgs" ;;
      2) # Reinstall via pipx
        local pkg; for pkg in $pkgs; do
          pipx uninstall "$pkg" 2>/dev/null || true
        done
        _pipx_install_pkgs "$pkgs"
        ;;
      *) return 2 ;;  # level not supported
    esac
    return $?
  fi

  # ── venv ──
  if [[ "$_PIP_ISO_KIND" == "venv" ]]; then
    local vname="$_PIP_ISO_NAME"
    [[ -n "$vname" ]] || return 1
    _pip_venv_ensure "$vname" || return 1
    local pip_cmd
    pip_cmd="$(_pip_venv_pip_cmd "$vname")"
    case "$level" in
      1) ucc_run $pip_cmd install -q --upgrade-strategy only-if-needed $pkgs ;;
      2) ucc_run $pip_cmd install -q --no-cache-dir --force-reinstall $pkgs ;;
      *) return 2 ;;
    esac
    return $?
  fi

  # ── global pip ──
  _pip_ensure_path || return 1
  local pip_cmd="pip"
  command -v pip >/dev/null 2>&1 || pip_cmd="python3 -m pip"
  case "$level" in
    1) # Retry install
      ucc_run $pip_cmd install -q --upgrade-strategy only-if-needed $pkgs
      ;;
    2) # Force reinstall without cache
      ucc_run $pip_cmd install -q --no-cache-dir --force-reinstall $pkgs
      ;;
    *) return 2 ;;  # level not supported
  esac
}

_ucc_driver_pip_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _pip_parse_isolation "$cfg_dir" "$yaml" "$target"
  local probe ver
  probe="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.probe_pkg")"
  [[ -n "$probe" ]] || return 1

  if [[ "$_PIP_ISO_KIND" == "pipx" ]]; then
    ver="$(_pipx_version "$probe")"
    printf 'version=%s  pkg=%s  isolation=pipx' "${ver:-absent}" "$probe"
    return
  fi
  if [[ "$_PIP_ISO_KIND" == "venv" ]]; then
    local vname="$_PIP_ISO_NAME"
    ver="$(_pip_venv_cached_version "$vname" "$probe")"
    printf 'version=%s  pkg=%s  venv=%s' "${ver:-absent}" "$probe" "$vname"
    return
  fi
  ver="$(_pip_cached_version "$probe")"
  printf 'version=%s  pkg=%s' "${ver:-absent}" "$probe"
}
