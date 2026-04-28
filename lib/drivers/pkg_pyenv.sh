#!/usr/bin/env bash
# lib/drivers/pkg_pyenv.sh — pyenv-version backend.
# Extracted from lib/drivers/pkg.sh on 2026-04-28 (PLAN refactor #3, slice 7).

# pyenv-version
_pyenv_ensure_path() {
  command -v pyenv >/dev/null 2>&1 || {
    [[ -x "$HOME/.pyenv/bin/pyenv" ]] || return 1
    export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
    PATH="$PYENV_ROOT/bin:$PATH"
  }
  export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
  case ":$PATH:" in *":$PYENV_ROOT/shims:"*) ;; *) PATH="$PYENV_ROOT/shims:$PATH" ;; esac
  export PATH
  eval "$(pyenv init - bash 2>/dev/null)" 2>/dev/null || true
  command -v pyenv >/dev/null 2>&1
}
_pkg_pyenv_available() { _pyenv_ensure_path; }
_pkg_pyenv_activate()  { _pyenv_ensure_path; }
_pkg_pyenv_observe()   {
  local v="$1"
  pyenv versions 2>/dev/null | grep -q "$v" && printf '%s' "$v" || printf 'absent'
}
_pkg_pyenv_install()   { ucc_run pyenv install "$1" && ucc_run pyenv global "$1"; }
_pkg_pyenv_update()    { ucc_run pyenv install --skip-existing "$1" && ucc_run pyenv global "$1"; }
_pkg_pyenv_version()   { python3 --version 2>/dev/null | awk '{print $2}'; }
_pkg_pyenv_outdated()  { return 1; }
