#!/usr/bin/env bash
# lib/drivers/pkg_ollama.sh — ollama-model backend.
# Extracted from lib/drivers/pkg.sh on 2026-04-28 (PLAN refactor #3, slice 8).

# ollama-model
_pkg_ollama_available() { command -v ollama >/dev/null 2>&1; }
_pkg_ollama_activate()  { :; }
_pkg_ollama_observe()   {
  local m="$1"
  ollama_model_present "$m" && printf '%s' "$m" || printf 'absent'
}
_pkg_ollama_install()   { ollama_model_pull "$1"; }
_pkg_ollama_update()    { ollama_model_pull "$1"; }
_pkg_ollama_version()   { :; }
_pkg_ollama_outdated()  { return 1; }
